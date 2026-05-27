use clap::{Parser, Subcommand};
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::io::{self, BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

// ─── File paths ──────────────────────────────────────────────

const PID_FILE: &str = "/tmp/autoclicker.pid";
const CONF_FILE: &str = "/tmp/autoclicker.conf";
const START_FILE: &str = "/tmp/autoclicker.start";
const SOCK_FILE: &str = "/tmp/autoclicker.sock";

// ─── CLI ─────────────────────────────────────────────────────

#[derive(Parser)]
#[command(name = "autoclicker", about = "Wayland autoclicker with safety features")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Run the click daemon
    Daemon {
        /// Interval between clicks in milliseconds (min 20ms)
        #[arg(short, long, default_value = "500")]
        interval: u64,
        /// Mouse button: left, middle, or right
        #[arg(short, long, default_value = "left")]
        button: String,
        /// Enable dead-man switch (pause on mouse movement)
        #[arg(short = 'd', long, default_value_t = true)]
        deadman: bool,
        /// Dead-man threshold in pixels
        #[arg(long, default_value = "10")]
        deadman_threshold: u32,
        /// Maximum duration in seconds (0 = unlimited)
        #[arg(short = 't', long, default_value = "300")]
        max_duration: u64,
        /// Maximum click count (0 = unlimited)
        #[arg(short = 'n', long, default_value = "0")]
        max_clicks: u64,
    },
    /// Output one-shot JSON status
    Status,
    /// Output continuous JSON status for Waybar
    Watch,
    /// Stop the running daemon
    Stop,
    /// Show the wofi control menu
    Menu,
}

// ─── IPC types ────────────────────────────────────────────────

#[derive(Serialize, Deserialize)]
struct IpcRequest {
    cmd: String,
}

#[derive(Serialize, Clone)]
struct WaybarStatus {
    text: String,
    class: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    percentage: Option<u64>,
    tooltip: String,
}

struct DaemonState {
    interval: u64,
    button: String,
    deadman: bool,
    deadman_threshold: u32,
    max_duration: u64,
    max_clicks: u64,
    running: bool,
    elapsed: u64,
    click_count: u64,
}

// ─── Config ──────────────────────────────────────────────────

fn read_conf() -> HashMap<String, String> {
    let mut map = HashMap::new();
    if let Ok(file) = fs::File::open(CONF_FILE) {
        for line in BufReader::new(file).lines().flatten() {
            let line = line.trim().to_string();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some(eq) = line.find('=') {
                let key = line[..eq].trim().to_string().to_uppercase();
                let val = line[eq + 1..].trim().to_string();
                map.insert(key, val);
            }
        }
    }
    map
}

fn conf_get(map: &HashMap<String, String>, key: &str, default: &str) -> String {
    map.get(&key.to_uppercase())
        .cloned()
        .unwrap_or_else(|| default.to_string())
}

fn conf_get_u64(map: &HashMap<String, String>, key: &str, default: u64) -> u64 {
    map.get(&key.to_uppercase())
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn conf_get_bool(map: &HashMap<String, String>, key: &str, default: bool) -> bool {
    map.get(&key.to_uppercase())
        .map(|v| v.to_lowercase() == "true")
        .unwrap_or(default)
}

// ─── Button mapping ──────────────────────────────────────────

fn button_to_evdev(button: &str) -> evdev::KeyCode {
    match button {
        "right" => evdev::KeyCode::BTN_RIGHT,
        "middle" => evdev::KeyCode::BTN_MIDDLE,
        _ => evdev::KeyCode::BTN_LEFT,
    }
}

// ─── Cursor position (dead-man switch) ──────────────────────

fn get_cursor_pos() -> Option<(i32, i32)> {
    let output = Command::new("hyprctl")
        .args(["cursorpos"])
        .output()
        .ok()?;
    let s = String::from_utf8(output.stdout).ok()?;
    let s = s.trim();
    let mut parts = s.split(',');
    let x: i32 = parts.next()?.trim().parse().ok()?;
    let y: i32 = parts.next()?.trim().parse().ok()?;
    Some((x, y))
}

// ─── Click injection ────────────────────────────────────────

struct Clicker {
    dev: evdev::uinput::VirtualDevice,
}

impl Clicker {
    fn new() -> Self {
        let dev = Self::create_uinput()
            .expect("Failed to create uinput device — is the user in the 'uinput' group?");
        eprintln!("Autoclicker: uinput device ready");
        Clicker { dev }
    }

    fn create_uinput() -> Result<evdev::uinput::VirtualDevice, Box<dyn std::error::Error>> {
        use evdev::uinput::VirtualDevice;
        use evdev::{AttributeSet, KeyCode};

        let mut keys = AttributeSet::<KeyCode>::new();
        keys.insert(KeyCode::BTN_LEFT);
        keys.insert(KeyCode::BTN_RIGHT);
        keys.insert(KeyCode::BTN_MIDDLE);

        let dev = VirtualDevice::builder()?
            .name("autoclicker")
            .with_keys(&keys)?
            .build()?;

        Ok(dev)
    }

    fn click(&mut self, button: &str) {
        use evdev::KeyEvent;
        let key = button_to_evdev(button);
        let code = key.code();
        let down = *KeyEvent::new(evdev::KeyCode::new(code), 1);
        let up = *KeyEvent::new(evdev::KeyCode::new(code), 0);
        let _ = self.dev.emit(&[down]);
        let _ = self.dev.emit(&[up]);
    }
}

// ─── Hotkey listener thread ─────────────────────────────────

fn hotkey_listener(stop_flag: Arc<AtomicBool>) {
    use evdev::{Device, EventSummary, KeyCode};

    let event_dir = match fs::read_dir("/dev/input") {
        Ok(d) => d,
        Err(_) => return,
    };

    for entry in event_dir.flatten() {
        let path = entry.path();
        let path_str = path.to_string_lossy();
        if !path_str.contains("event") {
            continue;
        }

        match Device::open(&path) {
            Ok(device) => {
                let supported = device
                    .supported_keys()
                    .map_or(false, |keys| keys.contains(KeyCode::KEY_ESC));
                if !supported {
                    continue;
                }

                let stop = stop_flag.clone();
                let name = device.name().unwrap_or("unknown").to_string();
                eprintln!("Autoclicker: listening for Escape on {}", name);

                thread::spawn(move || {
                    let mut dev = device;
                    loop {
                        match dev.fetch_events() {
                            Ok(events) => {
                                for ev in events {
                                    if let EventSummary::Key(_, KeyCode::KEY_ESC, 1) =
                                        ev.destructure()
                                    {
                                        eprintln!("Autoclicker: Escape pressed — stopping");
                                        stop.store(true, Ordering::SeqCst);
                                        return;
                                    }
                                }
                            }
                            Err(_) => return,
                        }
                        if stop.load(Ordering::Relaxed) {
                            return;
                        }
                        thread::sleep(Duration::from_millis(50));
                    }
                });
            }
            Err(_) => {}
        }
    }
}

// ─── Unix socket handler thread ─────────────────────────────

fn socket_listener(
    sock_path: PathBuf,
    stop_flag: Arc<AtomicBool>,
    state: Arc<Mutex<DaemonState>>,
    start_time: Instant,
) {
    let _ = fs::remove_file(&sock_path);

    let listener = match UnixListener::bind(&sock_path) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("Autoclicker: cannot bind socket: {}", e);
            return;
        }
    };

    listener
        .set_nonblocking(true)
        .expect("Failed to set nonblocking");

    loop {
        if stop_flag.load(Ordering::Relaxed) {
            break;
        }

        match listener.accept() {
            Ok((stream, _addr)) => {
                let s = stop_flag.clone();
                let st = state.clone();
                thread::spawn(move || handle_client(stream, s, st, start_time));
            }
            Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(100));
            }
            Err(_) => break,
        }
    }

    let _ = fs::remove_file(&sock_path);
}

fn handle_client(
    stream: UnixStream,
    stop_flag: Arc<AtomicBool>,
    state: Arc<Mutex<DaemonState>>,
    start_time: Instant,
) {
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    let mut writer = stream;

    let mut line = String::new();
    if reader.read_line(&mut line).is_err() {
        return;
    }

    let req: IpcRequest = match serde_json::from_str(&line) {
        Ok(r) => r,
        Err(_) => return,
    };

    match req.cmd.as_str() {
        "stop" => {
            stop_flag.store(true, Ordering::SeqCst);
            let _ = writeln!(writer, r#"{{"ok":true}}"#);
        }
        "status" => {
            let status = build_status(&state.lock().unwrap(), start_time);
            let json = serde_json::to_string(&status).unwrap();
            let _ = writeln!(writer, "{}", json);
        }
        "watch" => {
            while !stop_flag.load(Ordering::Relaxed) {
                let status = build_status(&state.lock().unwrap(), start_time);
                let json = serde_json::to_string(&status).unwrap();
                if writeln!(writer, "{}", json).is_err() {
                    break;
                }
                writer.flush().ok();
                thread::sleep(Duration::from_millis(500));
            }
        }
        _ => {}
    }
}

// ─── Status builder ─────────────────────────────────────────

fn build_status(ds: &DaemonState, _start_time: Instant) -> WaybarStatus {
    if !ds.running {
        return WaybarStatus {
            text: "󰍺".to_string(),
            class: "autoclicker-inactive".to_string(),
            percentage: None,
            tooltip: "Autoclicker: OFF".to_string(),
        };
    }

    let deadman_str = if ds.deadman { "ON" } else { "OFF" };

    if ds.max_duration > 0 {
        let elapsed = ds.elapsed;
        let remaining = ds.max_duration.saturating_sub(elapsed);
        let pct = Some((elapsed * 100 / ds.max_duration).min(100));
        let minutes = remaining / 60;
        let seconds = remaining % 60;

        let class = if remaining <= 10 {
            "autoclicker-warning"
        } else if remaining <= 60 {
            "autoclicker-expiring"
        } else {
            "autoclicker-active"
        };

        WaybarStatus {
            text: format!("{}:{:02}", minutes, seconds),
            class: class.to_string(),
            percentage: pct,
            tooltip: format!(
                "Autoclicker: ON\nButton: {}\nInterval: {}ms\nRemaining: {}m {}s\nSafety: dead-man {}",
                ds.button, ds.interval, minutes, seconds, deadman_str
            ),
        }
    } else {
        let mut tooltip = format!(
            "Autoclicker: ON\nButton: {}\nInterval: {}ms",
            ds.button, ds.interval
        );
        if ds.deadman {
            tooltip.push_str(&format!("\nSafety: dead-man {}", deadman_str));
        }

        WaybarStatus {
            text: "󰕰".to_string(),
            class: "autoclicker-active".to_string(),
            percentage: None,
            tooltip,
        }
    }
}

// ─── Daemon main loop ───────────────────────────────────────

fn cmd_daemon(
    interval: u64,
    button: &str,
    deadman: bool,
    deadman_threshold: u32,
    max_duration: u64,
    max_clicks: u64,
) {
    let interval = interval.max(20); // Rate governor: 50 CPS max

    // Write PID file
    fs::write(PID_FILE, format!("{}\n", std::process::id())).expect("Failed to write PID file");

    // Write start timestamp
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    fs::write(START_FILE, now.to_string()).expect("Failed to write start timestamp");

    // Set up clicker
    let mut clicker = Clicker::new();

    // Shared state
    let stop_flag = Arc::new(AtomicBool::new(false));
    let state = Arc::new(Mutex::new(DaemonState {
        interval,
        button: button.to_string(),
        deadman,
        deadman_threshold,
        max_duration,
        max_clicks,
        running: true,
        elapsed: 0,
        click_count: 0,
    }));

    let start_time = Instant::now();

    // Spawn hotkey listener thread
    let hotkey_stop = stop_flag.clone();
    thread::spawn(move || hotkey_listener(hotkey_stop));

    // Spawn socket listener thread
    let sock_path = PathBuf::from(SOCK_FILE);
    let sock_stop = stop_flag.clone();
    let sock_state = state.clone();
    let sock_start = start_time;
    thread::spawn(move || socket_listener(sock_path, sock_stop, sock_state, sock_start));

    // ─── Main click loop ──────────────────────────────────

    let mut last_pos: Option<(i32, i32)> = None;
    let mut click_count: u64 = 0;

    loop {
        if stop_flag.load(Ordering::Relaxed) {
            break;
        }

        // Re-read config each iteration
        let conf = read_conf();
        let cur_interval = conf_get_u64(&conf, "INTERVAL", interval).max(20);
        let cur_button = conf_get(&conf, "BUTTON", button);
        let cur_deadman = conf_get_bool(&conf, "DEADMAN", deadman);
        let cur_threshold = conf_get_u64(&conf, "DEADMAN_THRESHOLD", deadman_threshold as u64)
            as u32;
        let cur_max_dur = conf_get_u64(&conf, "MAX_DURATION", max_duration);
        let cur_max_clk = conf_get_u64(&conf, "MAX_CLICKS", max_clicks);

        // Update shared state
        {
            let mut s = state.lock().unwrap();
            s.interval = cur_interval;
            s.button = cur_button.clone();
            s.deadman = cur_deadman;
            s.deadman_threshold = cur_threshold;
            s.max_duration = cur_max_dur;
            s.max_clicks = cur_max_clk;
            s.elapsed = start_time.elapsed().as_secs();
            s.click_count = click_count;
        }

        // Max duration check
        if cur_max_dur > 0 {
            let elapsed = start_time.elapsed().as_secs();
            if elapsed >= cur_max_dur {
                let _ = Command::new("notify-send")
                    .args([
                        "Autoclicker",
                        &format!("Auto-stopped: {}s elapsed", cur_max_dur),
                    ])
                    .status();
                break;
            }
        }

        // Max click count check
        if cur_max_clk > 0 && click_count >= cur_max_clk {
            let _ = Command::new("notify-send")
                .args([
                    "Autoclicker",
                    &format!("Auto-stopped: {} clicks reached", cur_max_clk),
                ])
                .status();
            break;
        }

        // Dead-man switch
        if cur_deadman {
            if let Some((cx, cy)) = get_cursor_pos() {
                if let Some((lx, ly)) = last_pos {
                    let dx = (cx - lx).unsigned_abs();
                    let dy = (cy - ly).unsigned_abs();
                    if dx + dy > cur_threshold {
                        last_pos = Some((cx, cy));
                        thread::sleep(Duration::from_millis(cur_interval));
                        continue;
                    }
                }
                last_pos = Some((cx, cy));
            }
        }

        // Perform click
        clicker.click(&cur_button);
        click_count += 1;

        thread::sleep(Duration::from_millis(cur_interval));
    }

    // Cleanup
    {
        let mut s = state.lock().unwrap();
        s.running = false;
    }
    let _ = fs::remove_file(PID_FILE);
    let _ = fs::remove_file(SOCK_FILE);
    let _ = Command::new("notify-send")
        .args(["Autoclicker", "Stopped"])
        .status();
    let _ = Command::new("pkill").args(["-RTMIN+15", "waybar"]).status();
}

// ─── Commands ────────────────────────────────────────────────

fn send_ipc(cmd: &str) -> Option<String> {
    let mut stream = UnixStream::connect(SOCK_FILE).ok()?;
    let request = serde_json::to_string(&IpcRequest {
        cmd: cmd.to_string(),
    })
    .ok()?;
    writeln!(stream, "{}", request).ok()?;

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).ok()?;
    if line.is_empty() {
        None
    } else {
        Some(line.trim().to_string())
    }
}

fn cmd_status() {
    match send_ipc("status") {
        Some(json) => {
            println!("{}", json);
        }
        None => {
            let _ = fs::remove_file(PID_FILE);
            let _ = fs::remove_file(START_FILE);
            let status = WaybarStatus {
                text: "󰍺".to_string(),
                class: "autoclicker-inactive".to_string(),
                percentage: None,
                tooltip: "Autoclicker: OFF".to_string(),
            };
            println!("{}", serde_json::to_string(&status).unwrap());
        }
    }
}

fn cmd_watch() {
    match UnixStream::connect(SOCK_FILE) {
        Ok(stream) => {
            let request = serde_json::to_string(&IpcRequest {
                cmd: "watch".to_string(),
            })
            .unwrap();
            let mut writer = stream.try_clone().unwrap();
            writeln!(writer, "{}", request).ok();

            let reader = BufReader::new(stream);
            for line in reader.lines() {
                if let Ok(json) = line {
                    println!("{}", json);
                    io::stdout().flush().ok();
                }
            }
        }
        Err(_) => {
            let status = WaybarStatus {
                text: "󰍺".to_string(),
                class: "autoclicker-inactive".to_string(),
                percentage: None,
                tooltip: "Autoclicker: OFF".to_string(),
            };
            loop {
                println!("{}", serde_json::to_string(&status).unwrap());
                io::stdout().flush().ok();
                thread::sleep(Duration::from_millis(500));
            }
        }
    }
}

fn cmd_stop() {
    // Try socket first
    if send_ipc("stop").is_some() {
        thread::sleep(Duration::from_millis(100));
    }

    // Also try SIGTERM via PID file (fallback)
    if let Ok(pid_str) = fs::read_to_string(PID_FILE) {
        if let Ok(pid) = pid_str.trim().parse::<i32>() {
            let _ = kill(Pid::from_raw(pid), Signal::SIGTERM);
        }
    }

    let _ = fs::remove_file(PID_FILE);
    let _ = fs::remove_file(START_FILE);
    let _ = fs::remove_file(SOCK_FILE);
    let _ = Command::new("pkill").args(["-RTMIN+15", "waybar"]).status();
}

fn cmd_menu() {
    let _ = Command::new("autoclicker-menu").status();
}

// ─── Main ────────────────────────────────────────────────────

fn main() {
    let cli = Cli::parse();
    match cli.command {
        Commands::Daemon {
            interval,
            button,
            deadman,
            deadman_threshold,
            max_duration,
            max_clicks,
        } => cmd_daemon(
            interval,
            &button,
            deadman,
            deadman_threshold,
            max_duration,
            max_clicks,
        ),
        Commands::Status => cmd_status(),
        Commands::Watch => cmd_watch(),
        Commands::Stop => cmd_stop(),
        Commands::Menu => cmd_menu(),
    }
}
