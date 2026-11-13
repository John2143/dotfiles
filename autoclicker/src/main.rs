//! Scroll-to-click autoclicker.
//!
//! While a scroll mode is active the allowlisted mice are `EVIOCGRAB`ed and every event is
//! re-emitted through a uinput `autoclicker-scroll` mouse that carries everything except the
//! four wheel codes; each wheel notch is replaced by a click. Grabbing is required because
//! Wayland offers no per-device event interception, and the passthrough is required so
//! pointer motion and buttons keep working. The keyboard is never grabbed — that is the
//! escape hatch when the mode misbehaves (the mode itself is never turned off by the daemon).
//!
//! There is no dead-man switch, no maximum duration and no Escape listener: the user turns
//! the mode off, and nothing else does.

use clap::{Parser, Subcommand};
use evdev::uinput::VirtualDevice;
use evdev::{AttributeSet, Device, EventType, InputEvent, KeyCode, PropType, RelativeAxisCode};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{self, BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender, SyncSender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

// ─── Paths ───────────────────────────────────────────────────
// Everything lives in $XDG_RUNTIME_DIR/autoclicker (no /tmp state, no PID file).

fn runtime_dir() -> Option<PathBuf> {
    std::env::var("XDG_RUNTIME_DIR")
        .ok()
        .filter(|d| !d.is_empty())
        .map(|d| PathBuf::from(d).join("autoclicker"))
}

fn sock_path() -> Option<PathBuf> {
    runtime_dir().map(|d| d.join("sock"))
}

fn state_path() -> Option<PathBuf> {
    runtime_dir().map(|d| d.join("state"))
}

// ─── CLI ─────────────────────────────────────────────────────

#[derive(Parser)]
#[command(name = "autoclicker", about = "Scroll-to-click autoclicker")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Run the daemon (normally started by systemd, not by hand)
    Daemon {
        /// Remap this mouse, as VID:PID hex. Repeatable.
        #[arg(long = "device")]
        devices: Vec<String>,
        /// Initial timer interval in milliseconds (min 20)
        #[arg(long, default_value = "500")]
        interval: u64,
        /// Initial timer button: left, middle or right
        #[arg(long, default_value = "left")]
        button: String,
    },
    /// Print one JSON status line for Waybar
    Status,
    /// Stream JSON status lines for Waybar, reconnecting forever
    Watch,
    /// Enable scroll-to-left-click
    On,
    /// Turn the autoclicker off
    Off,
    /// Toggle between off and scroll-to-left-click
    Toggle,
    /// Cycle off -> scroll-left -> scroll-right -> scroll-left
    Cycle,
    /// Set the mode: off, scroll-left, scroll-right, timer
    Mode { mode: String },
    /// Change timer settings
    Set {
        #[command(subcommand)]
        what: SetCmd,
    },
    /// Print one setting: mode, button, interval, target
    Get { field: String },
    /// Restrict scroll-to-click to a window
    Target {
        #[command(subcommand)]
        target: TargetCmd,
    },
    /// Run the pure-function assertions (no hardware, no daemon)
    Selftest,
}

#[derive(Subcommand)]
enum SetCmd {
    Interval { ms: u64 },
    Button { button: String },
}

#[derive(Subcommand)]
enum TargetCmd {
    /// Click regardless of the focused window
    Any,
    /// Clear the target window
    None,
    /// Target one window by Hyprland address (0x prefix allowed)
    Set {
        addr: String,
        #[arg(num_args = 0..)]
        label: Vec<String>,
    },
}

// ─── Modes ───────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Mode {
    Off,
    ScrollLeft,
    ScrollRight,
    Timer,
}

impl Mode {
    fn as_str(self) -> &'static str {
        match self {
            Mode::Off => "off",
            Mode::ScrollLeft => "scroll-left",
            Mode::ScrollRight => "scroll-right",
            Mode::Timer => "timer",
        }
    }

    fn label(self) -> &'static str {
        match self {
            Mode::Off => "Off",
            Mode::ScrollLeft | Mode::ScrollRight => "Scroll mode",
            Mode::Timer => "Timer (auto-click)",
        }
    }

    fn parse(s: &str) -> Option<Mode> {
        match s.trim() {
            "off" => Some(Mode::Off),
            "scroll-left" => Some(Mode::ScrollLeft),
            "scroll-right" => Some(Mode::ScrollRight),
            "timer" => Some(Mode::Timer),
            _ => None,
        }
    }

    fn is_scroll(self) -> bool {
        matches!(self, Mode::ScrollLeft | Mode::ScrollRight)
    }

    fn inject_key(self) -> Option<KeyCode> {
        match self {
            Mode::ScrollLeft => Some(KeyCode::BTN_LEFT),
            Mode::ScrollRight => Some(KeyCode::BTN_RIGHT),
            _ => None,
        }
    }
}

// ─── State ───────────────────────────────────────────────────

struct State {
    mode: Mode,
    interval_ms: u64,
    button: String,
    target_addr: Option<String>,
    target_label: Option<String>,
    active_addr: Option<String>,
    clicks: u64,
    grab_error: Option<String>,
    notches: u64,
    dropped: u64,
    matched: usize,
}

impl State {
    fn new(interval_ms: u64, button: String, target_addr: Option<String>, target_label: Option<String>) -> Self {
        State {
            mode: Mode::Off, // mode is never persisted: the daemon always starts off
            interval_ms: interval_ms.max(20),
            button,
            target_addr,
            target_label,
            active_addr: None,
            clicks: 0,
            grab_error: None,
            notches: 0,
            dropped: 0,
            matched: 0,
        }
    }
}

#[derive(Serialize, Clone)]
struct WaybarStatus {
    text: String,
    class: String,
    tooltip: String,
}

#[derive(Serialize, Deserialize)]
struct IpcRequest {
    cmd: String,
}

fn build_status(st: &State) -> WaybarStatus {
    let (text, mut class) = match st.mode {
        Mode::Off => ("󰍺", "autoclicker-off"),
        Mode::ScrollLeft => ("󰁍", "autoclicker-scroll-left"),
        Mode::ScrollRight => ("󰁔", "autoclicker-scroll-right"),
        Mode::Timer => ("󰕰", "autoclicker-timer"),
    };
    if st.mode.is_scroll() && st.grab_error.is_some() {
        class = "autoclicker-error";
    }

    let mut lines = vec![st.mode.label().to_string()];
    match st.mode {
        Mode::ScrollLeft | Mode::ScrollRight => {
            let button = if st.mode == Mode::ScrollLeft { "left" } else { "right" };
            lines.push(format!("Scroll -> {button} click"));
            lines.push(format!("Notches: {}", st.notches));
            lines.push(format!("Clicks: {}", st.clicks));
        }
        Mode::Timer => {
            lines.push(format!("Interval: {}ms", st.interval_ms));
            lines.push(format!("Button: {}", st.button));
            lines.push(format!("Clicks: {}", st.clicks));
        }
        Mode::Off => {}
    }
    if st.dropped > 0 {
        lines.push(format!("Dropped: {}", st.dropped));
    }
    lines.push(match (&st.target_addr, &st.target_label) {
        (None, _) => "Target: any".to_string(),
        (Some(_), Some(label)) => format!("Target: {label}"),
        (Some(addr), None) => format!("Target: {addr}"),
    });
    if st.mode.is_scroll() && st.matched == 0 && st.grab_error.is_none() {
        lines.push("No mouse device matched".to_string());
    }
    if let Some(err) = &st.grab_error {
        lines.push(err.clone());
    }

    WaybarStatus {
        text: text.to_string(),
        class: class.to_string(),
        tooltip: lines.join("\n"),
    }
}

fn off_state_json() -> String {
    serde_json::to_string(&WaybarStatus {
        text: "󰍺".to_string(),
        class: "autoclicker-off".to_string(),
        tooltip: "Off\nTarget: any".to_string(),
    })
    .unwrap_or_else(|_| "{\"text\":\"\",\"class\":\"autoclicker-off\",\"tooltip\":\"\"}".to_string())
}

// ─── Persisted settings ──────────────────────────────────────

fn load_state() -> HashMap<String, String> {
    let mut map = HashMap::new();
    let Some(path) = state_path() else { return map };
    let Ok(file) = fs::File::open(path) else { return map };
    for line in BufReader::new(file).lines().map_while(Result::ok) {
        let line = line.trim().to_string();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(eq) = line.find('=') {
            map.insert(
                line[..eq].trim().to_uppercase(),
                line[eq + 1..].trim().to_string(),
            );
        }
    }
    map
}

fn save_state(st: &State) {
    let Some(path) = state_path() else { return };
    if let Some(dir) = path.parent() {
        let _ = fs::create_dir_all(dir);
    }
    let mut out = String::new();
    out.push_str(&format!("INTERVAL={}\n", st.interval_ms));
    out.push_str(&format!("BUTTON={}\n", st.button));
    if let Some(addr) = &st.target_addr {
        out.push_str(&format!("TARGET_ADDR={addr}\n"));
    }
    if let Some(label) = &st.target_label {
        out.push_str(&format!("TARGET_LABEL={}\n", label.replace('\n', " ")));
    }
    let _ = fs::write(path, out);
}

// ─── Buttons and addresses ───────────────────────────────────

fn button_to_key(button: &str) -> KeyCode {
    match button {
        "right" => KeyCode::BTN_RIGHT,
        "middle" => KeyCode::BTN_MIDDLE,
        _ => KeyCode::BTN_LEFT,
    }
}

fn valid_button(button: &str) -> String {
    match button {
        "right" | "middle" | "left" => button.to_string(),
        _ => "left".to_string(),
    }
}

fn normalize_addr(s: &str) -> String {
    let t = s.trim();
    let t = t
        .strip_prefix("0x")
        .or_else(|| t.strip_prefix("0X"))
        .unwrap_or(t);
    t.to_ascii_lowercase()
}

fn target_matches(st: &State) -> bool {
    match (&st.target_addr, &st.active_addr) {
        (None, _) => true,
        (Some(target), Some(active)) => target == active,
        (Some(_), None) => false,
    }
}

// ─── Frame rewriting (pure) ──────────────────────────────────

fn is_wheel_axis(axis: RelativeAxisCode) -> bool {
    is_wheel_code(axis.0)
}

fn is_wheel_code(code: u16) -> bool {
    code == RelativeAxisCode::REL_WHEEL.0
        || code == RelativeAxisCode::REL_WHEEL_HI_RES.0
        || code == RelativeAxisCode::REL_HWHEEL.0
        || code == RelativeAxisCode::REL_HWHEEL_HI_RES.0
}

/// Token bucket: at most 30 clicks per second, burst 30, so a device that emits a storm of
/// notches cannot flood clicks. Excess notches are dropped, never queued.
struct ClickBudget {
    tokens: f64,
    last: Instant,
}

impl ClickBudget {
    const CAPACITY: f64 = 30.0;
    const RATE: f64 = 30.0;

    fn new() -> Self {
        ClickBudget {
            tokens: Self::CAPACITY,
            last: Instant::now(),
        }
    }

    fn allow(&mut self) -> bool {
        let now = Instant::now();
        let elapsed = now.duration_since(self.last).as_secs_f64();
        self.last = now;
        self.tokens = (self.tokens + elapsed * Self::RATE).min(Self::CAPACITY);
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

/// Notches (REL_WHEEL only; the HI_RES twin is the same physical notch) in one frame.
/// Counting is suppressed when no click can be injected, so the tooltip never reports
/// notches that were only passed through.
fn wheel_notches(frame: &[InputEvent], counting: bool) -> u32 {
    if !counting {
        return 0;
    }
    frame
        .iter()
        .filter(|ev| ev.event_type() == EventType::RELATIVE && ev.code() == RelativeAxisCode::REL_WHEEL.0)
        .map(|ev| ev.value().unsigned_abs())
        .sum()
}

/// Rewrite one `SYN_REPORT`-delimited frame: drop the wheel codes, forward everything else,
/// and report how many clicks the frame is worth. The press/release pairs are emitted by the
/// click thread as separate SYN frames, the way a real mouse reports them.
/// `inject == None` means the target window is not focused: the wheel is still swallowed
/// (a scroll mode must not scroll) but nothing is clicked.
fn rewrite_frame(
    frame: &[InputEvent],
    inject: Option<KeyCode>,
    cap: &mut ClickBudget,
) -> (Vec<InputEvent>, u32) {
    let mut forwarded: Vec<InputEvent> = Vec::with_capacity(frame.len());
    let mut click_count = 0u32;

    for ev in frame {
        let event_type = ev.event_type();
        if event_type == EventType::RELATIVE {
            if is_wheel_code(ev.code()) {
                continue;
            }
            forwarded.push(*ev);
        } else if event_type == EventType::KEY {
            forwarded.push(*ev);
        }
        // Everything else is dropped: SYN frames are re-added by the kernel for each emit(),
        // and EV_MSC carries hardware scan metadata a virtual device cannot reproduce.
    }

    if inject.is_some() {
        for _ in 0..wheel_notches(frame, true) {
            if cap.allow() {
                click_count += 1;
            }
        }
    }

    (forwarded, click_count)
}

// ─── Device matching (pure) ──────────────────────────────────

/// A VID:PID is not enough: the same Logitech receiver also exposes a keyboard node and the
/// G502 HERO exposes a second node. Grabbing a keyboard node would break typing, so a device
/// must advertise BTN_LEFT *and* REL_WHEEL.
fn matches_device(
    vendor: u16,
    product: u16,
    wanted: &[(u16, u16)],
    has_btn_left: bool,
    has_wheel: bool,
    name: &str,
) -> bool {
    wanted.contains(&(vendor, product))
        && has_btn_left
        && has_wheel
        && !name.starts_with("autoclicker")
}

fn parse_device_arg(s: &str) -> Option<(u16, u16)> {
    let (v, p) = s.trim().split_once(':')?;
    Some((
        u16::from_str_radix(v.trim(), 16).ok()?,
        u16::from_str_radix(p.trim(), 16).ok()?,
    ))
}

fn device_matches(dev: &Device, wanted: &[(u16, u16)]) -> bool {
    let id = dev.input_id();
    let has_btn_left = dev
        .supported_keys()
        .map(|keys| keys.contains(KeyCode::BTN_LEFT))
        .unwrap_or(false);
    let has_wheel = dev
        .supported_relative_axes()
        .map(|axes| axes.contains(RelativeAxisCode::REL_WHEEL))
        .unwrap_or(false);
    matches_device(
        id.vendor(),
        id.product(),
        wanted,
        has_btn_left,
        has_wheel,
        dev.name().unwrap_or(""),
    )
}

fn enumerate_event_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Ok(entries) = fs::read_dir("/dev/input") {
        for entry in entries.flatten() {
            let path = entry.path();
            let is_event = path
                .file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.starts_with("event"))
                .unwrap_or(false);
            if is_event {
                paths.push(path);
            }
        }
    }
    paths.sort();
    paths
}

// ─── Timer clicker ───────────────────────────────────────────

struct Clicker {
    dev: VirtualDevice,
}

impl Clicker {
    fn new() -> Option<Self> {
        let mut keys = AttributeSet::<KeyCode>::new();
        keys.insert(KeyCode::BTN_LEFT);
        keys.insert(KeyCode::BTN_RIGHT);
        keys.insert(KeyCode::BTN_MIDDLE);
        match VirtualDevice::builder()
            .ok()?
            .name("autoclicker")
            .with_keys(&keys)
            .ok()?
            .build()
            .ok()
        {
            Some(dev) => Some(Clicker { dev }),
            None => None,
        }
    }

    fn click(&mut self, button: &str) {
        let code = button_to_key(button).code();
        let down = InputEvent::new_now(EventType::KEY.0, code, 1);
        let _ = self.dev.emit(&[down]);
        thread::sleep(CLICK_HOLD);
        let up = InputEvent::new_now(EventType::KEY.0, code, 0);
        let _ = self.dev.emit(&[up]);
    }
}

// ─── Passthrough device ──────────────────────────────────────

fn build_passthrough(devices: &[&Device]) -> io::Result<VirtualDevice> {
    let mut keys = AttributeSet::<KeyCode>::new();
    keys.insert(KeyCode::BTN_LEFT);
    keys.insert(KeyCode::BTN_RIGHT);
    keys.insert(KeyCode::BTN_MIDDLE);

    let mut axes = AttributeSet::<RelativeAxisCode>::new();
    axes.insert(RelativeAxisCode::REL_X);
    axes.insert(RelativeAxisCode::REL_Y);

    for dev in devices {
        if let Some(supported) = dev.supported_keys() {
            for code in supported.iter() {
                keys.insert(code);
            }
        }
        if let Some(supported) = dev.supported_relative_axes() {
            for code in supported.iter() {
                if !is_wheel_axis(code) {
                    axes.insert(code);
                }
            }
        }
    }

    let mut props = AttributeSet::<PropType>::new();
    props.insert(PropType::POINTER);

    VirtualDevice::builder()?
        .name("autoclicker-scroll")
        .with_keys(&keys)?
        .with_relative_axes(&axes)?
        .with_properties(&props)?
        .build()
}

enum SinkMsg {
    Events(Vec<InputEvent>),
    Shutdown,
}

// ─── Scroll session ──────────────────────────────────────────

struct Session {
    sink: Sender<SinkMsg>,
    sink_handle: Option<thread::JoinHandle<()>>,
    readers: Vec<(PathBuf, Arc<AtomicBool>, thread::JoinHandle<()>)>,
    closed_rx: Receiver<PathBuf>,
    pressed: Arc<Mutex<HashSet<u16>>>,
    clicks: SyncSender<KeyCode>,
    click_handle: Option<thread::JoinHandle<()>>,
}

/// A real mouse reports press and release in separate frames, tens of milliseconds apart.
/// Reproducing that matters: a press and release squeezed into one frame, or a click shorter
/// than a render frame, is not what any consumer of input expects.
const CLICK_HOLD: Duration = Duration::from_millis(30);

fn click_thread(
    clicks: Receiver<KeyCode>,
    sink: Sender<SinkMsg>,
    pressed: Arc<Mutex<HashSet<u16>>>,
    state: Arc<Mutex<State>>,
) {
    while let Ok(key) = clicks.recv() {
        let code = key.code();
        pressed.lock().unwrap().insert(code);
        let down = InputEvent::new_now(EventType::KEY.0, code, 1);
        if sink.send(SinkMsg::Events(vec![down])).is_err() {
            break;
        }
        thread::sleep(CLICK_HOLD);
        let up = InputEvent::new_now(EventType::KEY.0, code, 0);
        if sink.send(SinkMsg::Events(vec![up])).is_err() {
            break;
        }
        pressed.lock().unwrap().remove(&code);
        state.lock().unwrap().clicks += 1;
    }
}

#[allow(clippy::too_many_arguments)]
fn process_frame(
    frame: &[InputEvent],
    inject: KeyCode,
    cap: &mut ClickBudget,
    sink: &Sender<SinkMsg>,
    clicks: &SyncSender<KeyCode>,
    state: &Arc<Mutex<State>>,
    pressed: &Arc<Mutex<HashSet<u16>>>,
) {
    // The gate is re-read per frame so a focused-window change takes effect immediately.
    let gated = {
        let st = state.lock().unwrap();
        target_matches(&st)
    };
    let inject = if gated { Some(inject) } else { None };

    let notches = wheel_notches(frame, inject.is_some());
    let (out, clicks_wanted) = rewrite_frame(frame, inject, cap);

    if notches > 0 || clicks_wanted > 0 {
        let mut st = state.lock().unwrap();
        st.notches += u64::from(notches);
        st.dropped += u64::from(notches.saturating_sub(clicks_wanted));
    }
    if let Some(key) = inject {
        for _ in 0..clicks_wanted {
            // A full queue means the user is scrolling faster than clicks can be emitted
            // (30 ms apart, 33/s): drop rather than build a backlog that would lag behind.
            if clicks.try_send(key).is_err() {
                break;
            }
        }
    }

    if out.is_empty() {
        return;
    }

    {
        let mut held = pressed.lock().unwrap();
        for ev in &out {
            if ev.event_type() == EventType::KEY {
                if ev.value() == 0 {
                    held.remove(&ev.code());
                } else {
                    held.insert(ev.code());
                }
            }
        }
    }

    let _ = sink.send(SinkMsg::Events(out));
}

#[allow(clippy::too_many_arguments)]
fn read_loop(
    mut dev: Device,
    path: PathBuf,
    sink: Sender<SinkMsg>,
    clicks: SyncSender<KeyCode>,
    state: Arc<Mutex<State>>,
    stop: Arc<AtomicBool>,
    inject: KeyCode,
    pressed: Arc<Mutex<HashSet<u16>>>,
    closed: Sender<PathBuf>,
) {
    let mut cap = ClickBudget::new();
    let mut frame: Vec<InputEvent> = Vec::with_capacity(32);

    while !stop.load(Ordering::Relaxed) {
        match dev.fetch_events() {
            Ok(events) => {
                for ev in events {
                    frame.push(ev);
                    if ev.event_type() == EventType::SYNCHRONIZATION {
                        process_frame(&frame, inject, &mut cap, &sink, &clicks, &state, &pressed);
                        frame.clear();
                    }
                }
            }
            // Non-blocking reads are used so leaving the mode does not have to wait for the
            // user to move the mouse: a blocked read on a grabbed device has no wakeup.
            Err(err) if err.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(2));
            }
            Err(err) => {
                eprintln!("autoclicker: read error on {}: {err}", path.display());
                break;
            }
        }
    }

    let _ = dev.ungrab();
    let _ = closed.send(path);
}

// ─── Control loop ────────────────────────────────────────────

enum Cmd {
    Mode(Mode, Option<Sender<()>>),
    Interval(u64, Option<Sender<()>>),
    Button(String, Option<Sender<()>>),
    Target(Option<String>, Option<String>, Option<Sender<()>>),
}

struct Ctl {
    state: Arc<Mutex<State>>,
    rx: Receiver<Cmd>,
    wanted: Vec<(u16, u16)>,
    session: Option<Session>,
    clicker: Option<Clicker>,
    next_click: Instant,
    last_rescan: Instant,
}

impl Ctl {
    fn start_scroll(&mut self, mode: Mode) {
        let Some(inject) = mode.inject_key() else { return };

        let mut opened: Vec<(PathBuf, Device)> = Vec::new();
        let mut first_error: Option<String> = None;
        for path in enumerate_event_paths() {
            match Device::open(&path) {
                Ok(dev) => {
                    if device_matches(&dev, &self.wanted) {
                        opened.push((path, dev));
                    }
                }
                Err(err) => {
                    if err.kind() == io::ErrorKind::PermissionDenied && first_error.is_none() {
                        first_error = Some(format!("{}: {err}", path.display()));
                    }
                }
            }
        }

        if opened.is_empty() {
            let mut st = self.state.lock().unwrap();
            st.matched = 0;
            if let Some(err) = first_error {
                if st.grab_error.as_deref() != Some(err.as_str()) {
                    eprintln!("autoclicker: no device matched ({err})");
                }
                st.grab_error = Some(err);
            } else {
                // No permission problem: the device is simply absent (or was unplugged).
                st.grab_error = None;
            }
            return;
        }

        let refs: Vec<&Device> = opened.iter().map(|(_, dev)| dev).collect();
        let sink_dev = match build_passthrough(&refs) {
            Ok(dev) => dev,
            Err(err) => {
                self.state.lock().unwrap().grab_error = Some(format!("uinput: {err}"));
                return;
            }
        };
        drop(refs);

        let (sink_tx, sink_rx) = mpsc::channel::<SinkMsg>();
        let sink_handle = thread::spawn(move || {
            let mut dev = sink_dev;
            while let Ok(msg) = sink_rx.recv() {
                match msg {
                    SinkMsg::Events(events) => {
                        if let Err(err) = dev.emit(&events) {
                            eprintln!("autoclicker: emit failed: {err}");
                        }
                    }
                    SinkMsg::Shutdown => break,
                }
            }
        });

        let (closed_tx, closed_rx) = mpsc::channel::<PathBuf>();
        let pressed = Arc::new(Mutex::new(HashSet::new()));
        let (clicks_tx, clicks_rx) = mpsc::sync_channel::<KeyCode>(8);
        let click_handle = {
            let sink = sink_tx.clone();
            let pressed = pressed.clone();
            let state = self.state.clone();
            thread::spawn(move || click_thread(clicks_rx, sink, pressed, state))
        };
        let mut readers = Vec::new();
        let mut last_err: Option<String> = None;

        for (path, mut dev) in opened {
            if let Err(err) = dev.grab() {
                last_err = Some(format!("{}: {err}", path.display()));
                eprintln!("autoclicker: grab failed on {}: {err}", path.display());
                continue;
            }
            if let Err(err) = dev.set_nonblocking(true) {
                eprintln!("autoclicker: set_nonblocking failed on {}: {err}", path.display());
            }
            let stop = Arc::new(AtomicBool::new(false));
            let handle = {
                let path = path.clone();
                let sink = sink_tx.clone();
                let state = self.state.clone();
                let stop = stop.clone();
                let pressed = pressed.clone();
                let closed = closed_tx.clone();
                let clicks = clicks_tx.clone();
                thread::spawn(move || {
                    read_loop(dev, path, sink, clicks, state, stop, inject, pressed, closed);
                })
            };
            readers.push((path, stop, handle));
        }

        if readers.is_empty() {
            drop(clicks_tx);
            let _ = click_handle.join();
            let _ = sink_tx.send(SinkMsg::Shutdown);
            let _ = sink_handle.join();
            let mut st = self.state.lock().unwrap();
            st.matched = 0;
            st.grab_error = last_err.or(first_error);
            return;
        }

        {
            let mut st = self.state.lock().unwrap();
            st.matched = readers.len();
            st.grab_error = None;
        }

        self.session = Some(Session {
            sink: sink_tx,
            sink_handle: Some(sink_handle),
            readers,
            closed_rx,
            pressed,
            clicks: clicks_tx,
            click_handle: Some(click_handle),
        });
    }

    fn stop_scroll(&mut self) {
        let Some(session) = self.session.take() else { return };

        // 1. Stop the readers (each ungrabs its own device on the way out).
        for (_, stop, _) in &session.readers {
            stop.store(true, Ordering::SeqCst);
        }
        for (_, _, handle) in session.readers {
            let _ = handle.join();
        }

        // 2. Let queued clicks finish, so no click is cut in half by the switch.
        drop(session.clicks);
        if let Some(handle) = session.click_handle {
            let _ = handle.join();
        }

        // 3. Release buttons the passthrough may still hold: a physical button held while
        //    the mode switched would otherwise stay logically pressed in the compositor.
        let held: Vec<u16> = {
            let mut pressed = session.pressed.lock().unwrap();
            pressed.drain().collect()
        };
        if !held.is_empty() {
            let releases: Vec<InputEvent> = held
                .iter()
                .map(|code| InputEvent::new_now(EventType::KEY.0, *code, 0))
                .collect();
            let _ = session.sink.send(SinkMsg::Events(releases));
        }

        // 4. Drop the passthrough device.
        let _ = session.sink.send(SinkMsg::Shutdown);
        if let Some(handle) = session.sink_handle {
            let _ = handle.join();
        }

        self.state.lock().unwrap().matched = 0;
    }

    fn apply_mode(&mut self, mode: Mode) {
        if self.state.lock().unwrap().mode == mode {
            return;
        }
        self.stop_scroll();
        {
            let mut st = self.state.lock().unwrap();
            st.mode = mode;
            st.notches = 0;
            st.dropped = 0;
            st.clicks = 0;
        }
        if mode == Mode::Timer {
            self.clicker = None;
            self.next_click = Instant::now();
        }
        if mode.is_scroll() {
            self.start_scroll(mode);
        }
    }

    fn tick(&mut self) {
        let (mode, interval_ms, button) = {
            let st = self.state.lock().unwrap();
            (st.mode, st.interval_ms, st.button.clone())
        };

        if mode == Mode::Timer {
            if self.clicker.is_none() {
                self.clicker = Clicker::new();
                if self.clicker.is_none() {
                    self.state.lock().unwrap().grab_error =
                        Some("uinput unavailable for timer mode".to_string());
                    self.next_click = Instant::now() + Duration::from_millis(500);
                    return;
                }
            }
            self.state.lock().unwrap().grab_error = None;
            if Instant::now() >= self.next_click {
                if let Some(clicker) = self.clicker.as_mut() {
                    clicker.click(&button);
                }
                self.state.lock().unwrap().clicks += 1;
                self.next_click = Instant::now() + Duration::from_millis(interval_ms);
            }
        } else {
            self.clicker = None;
        }

        if !mode.is_scroll() {
            return;
        }

        // A reader that exits (device unplugged, read error) tears the session down; the
        // rescan below re-opens it, which is how receiver reconnects are picked up.
        if let Some(session) = &self.session {
            if session.closed_rx.try_recv().is_ok() {
                self.stop_scroll();
                self.last_rescan = Instant::now();
                self.start_scroll(mode);
                return;
            }
        }

        if self.session.is_none() && self.last_rescan.elapsed() >= Duration::from_secs(2) {
            self.last_rescan = Instant::now();
            self.start_scroll(mode);
        }
    }
}

fn control_loop(mut ctl: Ctl) {
    loop {
        let timeout = {
            let st = ctl.state.lock().unwrap();
            if st.mode == Mode::Timer {
                Duration::from_millis(st.interval_ms.min(20).max(1))
            } else {
                Duration::from_millis(50)
            }
        };

        match ctl.rx.recv_timeout(timeout) {
            Ok(Cmd::Mode(mode, ack)) => {
                ctl.apply_mode(mode);
                if let Some(ack) = ack {
                    let _ = ack.send(());
                }
            }
            Ok(Cmd::Interval(ms, ack)) => {
                {
                    let mut st = ctl.state.lock().unwrap();
                    st.interval_ms = ms.max(20);
                    save_state(&st);
                }
                if let Some(ack) = ack {
                    let _ = ack.send(());
                }
            }
            Ok(Cmd::Button(button, ack)) => {
                {
                    let mut st = ctl.state.lock().unwrap();
                    st.button = valid_button(&button);
                    save_state(&st);
                }
                if let Some(ack) = ack {
                    let _ = ack.send(());
                }
            }
            Ok(Cmd::Target(addr, label, ack)) => {
                {
                    let mut st = ctl.state.lock().unwrap();
                    st.target_addr = addr;
                    st.target_label = label;
                    save_state(&st);
                }
                if let Some(ack) = ack {
                    let _ = ack.send(());
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => return,
        }

        ctl.tick();
    }
}

// ─── IPC ─────────────────────────────────────────────────────

fn json_ok() -> String {
    "{\"ok\":true}".to_string()
}

fn json_error(message: &str) -> String {
    serde_json::json!({ "ok": false, "error": message }).to_string()
}

fn json_value(value: &str) -> String {
    serde_json::json!({ "ok": true, "value": value }).to_string()
}

fn send_cmd(tx: &Sender<Cmd>, cmd: Cmd) -> bool {
    if tx.send(cmd).is_err() {
        return false;
    }
    true
}

fn wait_ack(ack: Receiver<()>) -> bool {
    ack.recv_timeout(Duration::from_secs(2)).is_ok()
}

fn dispatch(cmd: &str, state: &Arc<Mutex<State>>, tx: &Sender<Cmd>) -> String {
    let cmd = cmd.trim();

    if cmd == "status" {
        let st = state.lock().unwrap();
        return serde_json::to_string(&build_status(&st)).unwrap_or_else(|_| off_state_json());
    }

    if let Some(field) = cmd.strip_prefix("get ") {
        let st = state.lock().unwrap();
        let value = match field.trim() {
            "mode" => st.mode.as_str().to_string(),
            "button" => st.button.clone(),
            "interval" => st.interval_ms.to_string(),
            "target" => match (&st.target_addr, &st.target_label) {
                (None, _) => "any".to_string(),
                (Some(_), Some(label)) => label.clone(),
                (Some(addr), None) => addr.clone(),
            },
            other => return json_error(&format!("unknown field: {other}")),
        };
        return json_value(&value);
    }

    if let Some(mode) = cmd.strip_prefix("mode ") {
        let Some(mode) = Mode::parse(mode) else {
            return json_error("mode must be off, scroll-left, scroll-right or timer");
        };
        return if send_and_wait_mode(mode, tx) {
            json_ok()
        } else {
            json_error("daemon did not acknowledge")
        };
    }

    if cmd == "on" {
        return if send_and_wait_mode(Mode::ScrollLeft, tx) {
            json_ok()
        } else {
            json_error("daemon did not acknowledge")
        };
    }
    if cmd == "off" {
        return if send_and_wait_mode(Mode::Off, tx) {
            json_ok()
        } else {
            json_error("daemon did not acknowledge")
        };
    }
    if cmd == "toggle" {
        let current = state.lock().unwrap().mode;
        let next = if current == Mode::Off {
            Mode::ScrollLeft
        } else {
            Mode::Off
        };
        return if send_and_wait_mode(next, tx) {
            json_ok()
        } else {
            json_error("daemon did not acknowledge")
        };
    }
    if cmd == "cycle" {
        let current = state.lock().unwrap().mode;
        let next = match current {
            Mode::ScrollLeft => Mode::ScrollRight,
            Mode::ScrollRight => Mode::ScrollLeft,
            _ => Mode::ScrollLeft,
        };
        return if send_and_wait_mode(next, tx) {
            json_ok()
        } else {
            json_error("daemon did not acknowledge")
        };
    }

    if let Some(rest) = cmd.strip_prefix("set interval ") {
        let Ok(ms) = rest.trim().parse::<u64>() else {
            return json_error("interval must be a number of milliseconds");
        };
        let (ack_tx, ack_rx) = mpsc::channel();
        if !send_cmd(tx, Cmd::Interval(ms, Some(ack_tx))) || !wait_ack(ack_rx) {
            return json_error("daemon did not acknowledge");
        }
        return json_ok();
    }

    if let Some(rest) = cmd.strip_prefix("set button ") {
        let button = valid_button(rest.trim());
        let (ack_tx, ack_rx) = mpsc::channel();
        if !send_cmd(tx, Cmd::Button(button, Some(ack_tx))) || !wait_ack(ack_rx) {
            return json_error("daemon did not acknowledge");
        }
        return json_ok();
    }

    if cmd == "target any" {
        return send_target(tx, None, None);
    }
    if cmd == "target none" {
        return send_target(tx, None, None);
    }
    if let Some(rest) = cmd.strip_prefix("target set ") {
        let rest = rest.trim();
        let (addr, label) = match rest.split_once(' ') {
            Some((addr, label)) => (addr, Some(label.trim().to_string())),
            None => (rest, None),
        };
        if addr.is_empty() {
            return json_error("target set needs an address");
        }
        return send_target(tx, Some(normalize_addr(addr)), label.filter(|l| !l.is_empty()));
    }

    json_error(&format!("unknown command: {cmd}"))
}

fn send_and_wait_mode(mode: Mode, tx: &Sender<Cmd>) -> bool {
    let (ack_tx, ack_rx) = mpsc::channel();
    if !send_cmd(tx, Cmd::Mode(mode, Some(ack_tx))) {
        return false;
    }
    wait_ack(ack_rx)
}

fn send_target(tx: &Sender<Cmd>, addr: Option<String>, label: Option<String>) -> String {
    let (ack_tx, ack_rx) = mpsc::channel();
    if !send_cmd(tx, Cmd::Target(addr, label, Some(ack_tx))) || !wait_ack(ack_rx) {
        return json_error("daemon did not acknowledge");
    }
    json_ok()
}

fn handle_connection(mut stream: UnixStream, state: Arc<Mutex<State>>, tx: Sender<Cmd>) {
    let Ok(snapshot) = stream.try_clone() else {
        return;
    };
    let mut reader = BufReader::new(snapshot);
    let mut line = String::new();
    if reader.read_line(&mut line).is_err() {
        return;
    }

    let request: IpcRequest = match serde_json::from_str(line.trim()) {
        Ok(request) => request,
        Err(err) => {
            let _ = writeln!(stream, "{}", json_error(&format!("bad request: {err}")));
            return;
        }
    };

    if request.cmd.trim() == "watch" {
        let mut last = String::new();
        loop {
            let json = {
                let st = state.lock().unwrap();
                serde_json::to_string(&build_status(&st)).unwrap_or_else(|_| off_state_json())
            };
            if json != last {
                if writeln!(stream, "{json}").is_err() || stream.flush().is_err() {
                    return;
                }
                last = json;
            }
            thread::sleep(Duration::from_millis(200));
        }
    }

    let response = dispatch(&request.cmd, &state, &tx);
    let _ = writeln!(stream, "{response}");
}

fn spawn_socket_listener(listener: UnixListener, state: Arc<Mutex<State>>, tx: Sender<Cmd>) {
    thread::spawn(move || {
        for connection in listener.incoming() {
            match connection {
                Ok(stream) => {
                    let state = state.clone();
                    let tx = tx.clone();
                    thread::spawn(move || handle_connection(stream, state, tx));
                }
                Err(err) => {
                    eprintln!("autoclicker: accept failed: {err}");
                    thread::sleep(Duration::from_millis(200));
                }
            }
        }
    });
}

// ─── Hyprland focused-window events ──────────────────────────

fn hyprland_socket() -> Option<PathBuf> {
    let runtime = std::env::var("XDG_RUNTIME_DIR").ok()?;
    let signature = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").ok()?;
    Some(
        PathBuf::from(runtime)
            .join("hypr")
            .join(signature)
            .join(".socket2.sock"),
    )
}

fn hyprland_events(state: Arc<Mutex<State>>) {
    loop {
        let Some(path) = hyprland_socket() else {
            thread::sleep(Duration::from_secs(2));
            continue;
        };
        match UnixStream::connect(&path) {
            Ok(stream) => {
                let reader = BufReader::new(stream);
                for line in reader.lines().map_while(Result::ok) {
                    if let Some(payload) = line.strip_prefix("activewindowv2>>") {
                        let addr = normalize_addr(payload);
                        let mut st = state.lock().unwrap();
                        st.active_addr = if addr.is_empty() { None } else { Some(addr) };
                    }
                }
            }
            Err(_) => {}
        }
        thread::sleep(Duration::from_secs(2));
    }
}

// ─── Client side ─────────────────────────────────────────────

fn send_ipc(cmd: &str) -> Option<String> {
    let path = sock_path()?;
    let mut stream = UnixStream::connect(path).ok()?;
    let request = serde_json::json!({ "cmd": cmd }).to_string();
    writeln!(stream, "{request}").ok()?;
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).ok()?;
    Some(line.trim().to_string())
}

fn run_simple(cmd: &str) {
    match send_ipc(cmd) {
        Some(response) if response.contains("\"ok\":true") => {}
        Some(response) => {
            eprintln!("autoclicker: {response}");
            std::process::exit(1);
        }
        None => {
            eprintln!("autoclicker: daemon not running");
            std::process::exit(1);
        }
    }
}

fn cmd_status() {
    match send_ipc("status") {
        Some(response) => println!("{response}"),
        None => println!("{}", off_state_json()),
    }
}

fn cmd_watch() {
    loop {
        if let Some(path) = sock_path() {
            if let Ok(stream) = UnixStream::connect(path) {
                let request = serde_json::json!({ "cmd": "watch" }).to_string();
                let mut writer = match stream.try_clone() {
                    Ok(writer) => writer,
                    Err(_) => {
                        thread::sleep(Duration::from_secs(2));
                        continue;
                    }
                };
                if writeln!(writer, "{request}").is_ok() {
                    let reader = BufReader::new(stream);
                    for line in reader.lines().map_while(Result::ok) {
                        if line.is_empty() {
                            continue;
                        }
                        println!("{line}");
                        let _ = io::stdout().flush();
                    }
                }
            }
        }
        // Daemon absent or the stream ended: Waybar must still get a line, otherwise it
        // hides the module entirely.
        println!("{}", off_state_json());
        let _ = io::stdout().flush();
        thread::sleep(Duration::from_secs(2));
    }
}

// ─── Daemon ──────────────────────────────────────────────────

fn cmd_daemon(device_args: Vec<String>, interval: u64, button: String) {
    let Some(dir) = runtime_dir() else {
        eprintln!("autoclicker: XDG_RUNTIME_DIR is not set");
        std::process::exit(1);
    };
    let _ = fs::create_dir_all(&dir);
    let sock = dir.join("sock");

    if UnixStream::connect(&sock).is_ok() {
        eprintln!("autoclicker: already running");
        std::process::exit(1);
    }
    let _ = fs::remove_file(&sock);

    let wanted: Vec<(u16, u16)> = device_args
        .iter()
        .filter_map(|arg| {
            let parsed = parse_device_arg(arg);
            if parsed.is_none() {
                eprintln!("autoclicker: ignoring malformed --device {arg}");
            }
            parsed
        })
        .collect();

    let saved = load_state();
    let interval_ms = saved
        .get("INTERVAL")
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(interval)
        .max(20);
    let button = valid_button(saved.get("BUTTON").map(String::as_str).unwrap_or(&button));
    let target_addr = saved.get("TARGET_ADDR").map(|v| normalize_addr(v));
    let target_label = saved.get("TARGET_LABEL").cloned();

    let state = Arc::new(Mutex::new(State::new(
        interval_ms,
        button,
        target_addr,
        target_label,
    )));

    let listener = match UnixListener::bind(&sock) {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("autoclicker: cannot bind {}: {err}", sock.display());
            std::process::exit(1);
        }
    };

    let (tx, rx) = mpsc::channel::<Cmd>();
    spawn_socket_listener(listener, state.clone(), tx.clone());

    {
        let state = state.clone();
        thread::spawn(move || hyprland_events(state));
    }

    eprintln!(
        "autoclicker: daemon ready (devices: {}, interval {}ms, button {})",
        if wanted.is_empty() {
            "none".to_string()
        } else {
            wanted
                .iter()
                .map(|(v, p)| format!("{v:04x}:{p:04x}"))
                .collect::<Vec<_>>()
                .join(",")
        },
        interval_ms,
        state.lock().unwrap().button
    );

    control_loop(Ctl {
        state,
        rx,
        wanted,
        session: None,
        clicker: None,
        next_click: Instant::now(),
        last_rescan: Instant::now() - Duration::from_secs(10),
    });
}

// ─── Selftest ────────────────────────────────────────────────

fn ev(event_type: EventType, code: u16, value: i32) -> InputEvent {
    InputEvent::new(event_type.0, code, value)
}

fn syn() -> InputEvent {
    ev(EventType::SYNCHRONIZATION, 0, 0)
}

fn wheel(value: i32) -> InputEvent {
    ev(EventType::RELATIVE, RelativeAxisCode::REL_WHEEL.0, value)
}

fn rel(axis: RelativeAxisCode, value: i32) -> InputEvent {
    ev(EventType::RELATIVE, axis.0, value)
}

fn key(code: KeyCode, value: i32) -> InputEvent {
    ev(EventType::KEY, code.code(), value)
}

fn selftest() -> bool {
    let mut failures = Vec::new();

    let check = |name: &str, ok: bool, failures: &mut Vec<String>| {
        if !ok {
            failures.push(name.to_string());
        }
    };

    // 1. One notch: one click queued, the wheel itself is not forwarded.
    {
        let mut cap = ClickBudget::new();
        let frame = vec![wheel(-1), syn()];
        let (out, clicks) = rewrite_frame(&frame, Some(KeyCode::BTN_RIGHT), &mut cap);
        let ok = clicks == 1
            && out.is_empty()
            && !out
                .iter()
                .any(|e| e.event_type() == EventType::RELATIVE && is_wheel_code(e.code()));
        check("case1 forward click", ok, &mut failures);
    }

    // 2. The HI_RES twin is not a second notch.
    {
        let mut cap = ClickBudget::new();
        let frame = vec![
            rel(RelativeAxisCode::REL_WHEEL_HI_RES, -120),
            syn(),
        ];
        let (out, clicks) = rewrite_frame(&frame, Some(KeyCode::BTN_LEFT), &mut cap);
        check(
            "case2 hi-res only",
            clicks == 0 && out.is_empty(),
            &mut failures,
        );
    }

    // 3. Motion passes through verbatim.
    {
        let mut cap = ClickBudget::new();
        let frame = vec![
            rel(RelativeAxisCode::REL_X, 5),
            rel(RelativeAxisCode::REL_Y, -3),
            syn(),
        ];
        let (out, clicks) = rewrite_frame(&frame, Some(KeyCode::BTN_LEFT), &mut cap);
        let ok = clicks == 0
            && out.len() == 2
            && out[0].value() == 5
            && out[1].value() == -3;
        check("case3 motion passthrough", ok, &mut failures);
    }

    // 4. Target not focused: wheel still swallowed, nothing clicked.
    {
        let mut cap = ClickBudget::new();
        let frame = vec![wheel(1), rel(RelativeAxisCode::REL_X, 1), syn()];
        let (out, clicks) = rewrite_frame(&frame, None, &mut cap);
        let ok = clicks == 0
            && out.len() == 1
            && out[0].event_type() == EventType::RELATIVE
            && out[0].code() == RelativeAxisCode::REL_X.0;
        check("case4 gated frame", ok, &mut failures);
    }

    // 5. Governor: a storm of notches cannot exceed 30 clicks.
    {
        let mut cap = ClickBudget::new();
        let mut frame: Vec<InputEvent> = (0..100).map(|_| wheel(1)).collect();
        frame.push(syn());
        let (_, clicks) = rewrite_frame(&frame, Some(KeyCode::BTN_LEFT), &mut cap);
        let noches = wheel_notches(&frame, true);
        let dropped = noches.saturating_sub(clicks);
        check(
            "case5 click cap",
            clicks <= 30 && clicks == 30 && dropped == 70,
            &mut failures,
        );
    }

    // 6. Address normalisation.
    {
        check(
            "case6 normalize_addr",
            normalize_addr("0x5E30D85D2280") == normalize_addr("5e30d85d2280")
                && normalize_addr("5e30d85d2280") == "5e30d85d2280",
            &mut failures,
        );
    }

    // 7. Device matching: the receiver's keyboard node must be rejected.
    {
        let wanted = [(0x046d, 0xc547)];
        let ok = matches_device(
            0x046d,
            0xc547,
            &wanted,
            true,
            true,
            "Logitech USB Receiver",
        ) && !matches_device(
            0x046d,
            0xc547,
            &wanted,
            true,
            false,
            "Logitech USB Receiver",
        ) && !matches_device(0x046d, 0xc547, &wanted, false, true, "Logitech USB Receiver")
            && !matches_device(0x046d, 0xc547, &wanted, true, true, "autoclicker-scroll")
            && !matches_device(0x342d, 0xe4c5, &wanted, true, true, "AKKO Keyboard");
        check("case7 device match", ok, &mut failures);
    }

    if failures.is_empty() {
        println!("selftest: PASS");
        true
    } else {
        for failure in &failures {
            println!("selftest: FAIL: {failure}");
        }
        false
    }
}

// ─── Main ────────────────────────────────────────────────────

fn main() {
    let cli = Cli::parse();
    match cli.command {
        Commands::Daemon {
            devices,
            interval,
            button,
        } => cmd_daemon(devices, interval, button),
        Commands::Status => cmd_status(),
        Commands::Watch => cmd_watch(),
        Commands::On => run_simple("on"),
        Commands::Off => run_simple("off"),
        Commands::Toggle => run_simple("toggle"),
        Commands::Cycle => run_simple("cycle"),
        Commands::Mode { mode } => run_simple(&format!("mode {mode}")),
        Commands::Set { what } => match what {
            SetCmd::Interval { ms } => run_simple(&format!("set interval {ms}")),
            SetCmd::Button { button } => run_simple(&format!("set button {button}")),
        },
        Commands::Get { field } => match send_ipc(&format!("get {field}")) {
            Some(response) => match serde_json::from_str::<serde_json::Value>(&response) {
                Ok(value) => {
                    if let Some(text) = value.get("value").and_then(|v| v.as_str()) {
                        println!("{text}");
                    } else {
                        eprintln!("autoclicker: {response}");
                        std::process::exit(1);
                    }
                }
                Err(_) => {
                    eprintln!("autoclicker: {response}");
                    std::process::exit(1);
                }
            },
            None => {
                eprintln!("autoclicker: daemon not running");
                std::process::exit(1);
            }
        },
        Commands::Target { target } => match target {
            TargetCmd::Any => run_simple("target any"),
            TargetCmd::None => run_simple("target none"),
            TargetCmd::Set { addr, label } => {
                let mut cmd = format!("target set {addr}");
                if !label.is_empty() {
                    cmd.push(' ');
                    cmd.push_str(&label.join(" "));
                }
                run_simple(&cmd)
            }
        },
        Commands::Selftest => {
            if !selftest() {
                std::process::exit(1);
            }
        }
    }
}
