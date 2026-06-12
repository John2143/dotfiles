use axum::{Json, Router, routing::post};
use serde::{Deserialize, Serialize};
use std::process::Command;

#[derive(Serialize)]
struct ScreenResponse {
    success: bool,
    message: String,
}
#[derive(Deserialize)]
struct KeypadRequest {
    color: Option<String>,
    brightness: Option<u8>,
}

fn run_ps2avr_rgb(args: &[&str]) -> ScreenResponse {
    match Command::new("/run/current-system/sw/bin/ps2avr-rgb")
        .args(args)
        .output()
    {
        Ok(output) if output.status.success() => ScreenResponse {
            success: true,
            message: String::from_utf8_lossy(&output.stdout).trim().to_string(),
        },
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            ScreenResponse {
                success: false,
                message: if stderr.is_empty() { stdout } else { stderr },
            }
        }
        Err(e) => ScreenResponse {
            success: false,
            message: format!("failed to run ps2avr-rgb: {e}"),
        },
    }
}

fn find_hyprland_instance() -> Option<String> {
    let xdg = std::env::var("XDG_RUNTIME_DIR").unwrap_or("/run/user/1000".into());
    let hypr_dir = std::path::Path::new(&xdg).join("hypr");
    let entry = std::fs::read_dir(hypr_dir).ok()?.next()?.ok()?;
    Some(entry.file_name().to_string_lossy().into_owned())
}

fn run_hyprctl(args: &[&str]) -> ScreenResponse {
    let xdg = std::env::var("XDG_RUNTIME_DIR").unwrap_or("/run/user/1000".into());

    let instance = match find_hyprland_instance() {
        Some(sig) => sig,
        None => {
            let msg = "no hyprland instance found";
            eprintln!("hyprctl: {msg}");
            return ScreenResponse {
                success: false,
                message: msg.into(),
            };
        }
    };

    eprintln!("hyprctl: HYPRLAND_INSTANCE_SIGNATURE={instance}");

    match Command::new("hyprctl")
        .args(args)
        .env("XDG_RUNTIME_DIR", &xdg)
        .env("HYPRLAND_INSTANCE_SIGNATURE", &instance)
        .output()
    {
        Ok(output) if output.status.success() => {
            let msg = String::from_utf8_lossy(&output.stdout).trim().to_string();
            eprintln!("hyprctl: success: {msg}");
            ScreenResponse {
                success: true,
                message: msg,
            }
        }
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            let msg = if stderr.is_empty() { stdout } else { stderr };
            eprintln!("hyprctl: error (code {:?}): {msg}", output.status.code());
            ScreenResponse {
                success: false,
                message: msg,
            }
        }
        Err(e) => {
            eprintln!("hyprctl: failed to launch: {e}");
            ScreenResponse {
                success: false,
                message: format!("failed to run hyprctl: {e}"),
            }
        }
    }
}


async fn screen_off() -> Json<ScreenResponse> {
    eprintln!("POST /screen/off");
    Json(run_hyprctl(&["dispatch", r#"hl.dsp.dpms({ action = "disable" })"#]))
}


async fn screen_on() -> Json<ScreenResponse> {
    eprintln!("POST /screen/on");
    Json(run_hyprctl(&["dispatch", r#"hl.dsp.dpms({ action = "enable" })"#]))
}
async fn keypad_off() -> Json<ScreenResponse> {
    eprintln!("POST /keypad/off");
    Json(run_ps2avr_rgb(&["off"]))
}

async fn keypad_on() -> Json<ScreenResponse> {
    eprintln!("POST /keypad/on");
    Json(run_ps2avr_rgb(&["on"]))
}

async fn keypad_color(Json(body): Json<KeypadRequest>) -> Json<ScreenResponse> {
    let color = body.color.as_deref().unwrap_or("FFFFFF");
    eprintln!("POST /keypad/color {color}");
    Json(run_ps2avr_rgb(&["color", color]))
}

async fn keypad_brightness(Json(body): Json<KeypadRequest>) -> Json<ScreenResponse> {
    let b = body.brightness.unwrap_or(128);
    let b_str = b.to_string();
    eprintln!("POST /keypad/brightness {b}");
    Json(run_ps2avr_rgb(&["brightness", &b_str]))
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/screen/off", post(screen_off))
        .route("/screen/on", post(screen_on))
        .route("/keypad/off", post(keypad_off))
        .route("/keypad/on", post(keypad_on))
        .route("/keypad/color", post(keypad_color))
        .route("/keypad/brightness", post(keypad_brightness));

    let addr = "0.0.0.0:50051";
    eprintln!("screen-control server listening on {addr}");

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
