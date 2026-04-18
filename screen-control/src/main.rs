use axum::{Json, Router, routing::post};
use serde::Serialize;
use std::process::Command;

#[derive(Serialize)]
struct ScreenResponse {
    success: bool,
    message: String,
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
            return ScreenResponse {
                success: false,
                message: "no hyprland instance found".into(),
            };
        }
    };

    eprintln!("using HYPRLAND_INSTANCE_SIGNATURE={instance}");

    match Command::new("hyprctl")
        .args(args)
        .env("XDG_RUNTIME_DIR", &xdg)
        .env("HYPRLAND_INSTANCE_SIGNATURE", &instance)
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
            message: format!("failed to run hyprctl: {e}"),
        },
    }
}

async fn screen_off() -> Json<ScreenResponse> {
    eprintln!("POST /screen/off");
    Json(run_hyprctl(&["dispatch", "dpms", "off"]))
}

async fn screen_on() -> Json<ScreenResponse> {
    eprintln!("POST /screen/on");
    Json(run_hyprctl(&["dispatch", "dpms", "on"]))
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/screen/off", post(screen_off))
        .route("/screen/on", post(screen_on));

    let addr = "0.0.0.0:50051";
    eprintln!("screen-control server listening on {addr}");

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
