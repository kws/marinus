#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde_json::Value;
use std::{path::PathBuf, sync::Mutex, time::Duration};
use tauri::Manager;
use tauri_plugin_dialog::DialogExt;
use tokio::{process::Command, sync::watch};

#[derive(Default)]
struct BackendState(Mutex<Option<watch::Sender<bool>>>);

fn backend_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let path = app
        .path()
        .resource_dir()
        .map_err(|e| e.to_string())?
        .join("backend");
    if path.is_dir() {
        return Ok(path);
    }
    #[cfg(debug_assertions)]
    {
        let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources/backend");
        if source.is_dir() {
            return Ok(source);
        }
    }
    Err("The packaged Wi-Fi backend is missing. Rebuild with npm run desktop:build.".into())
}

fn backend_command(root: PathBuf) -> Command {
    #[cfg(target_os = "macos")]
    let command = Command::new(root.join("Marinus.app/Contents/MacOS/marinus"));
    #[cfg(target_os = "windows")]
    let mut command = Command::new(root.join("marinus.exe"));
    #[cfg(target_os = "windows")]
    command.creation_flags(0x08000000); // CREATE_NO_WINDOW; scanner remains unelevated.
    #[cfg(target_os = "linux")]
    let command = {
        let mut command = Command::new("/usr/bin/python3");
        command.arg(root.join("wifi_scan.py"));
        command
    };
    command
}

fn decode_output(stdout: &[u8], stderr: &[u8], success: bool, kind: &str) -> Result<Value, String> {
    if stdout.len() > 8 * 1024 * 1024 {
        return Err("Wi-Fi backend returned an oversized result.".into());
    }
    let value: Value = serde_json::from_slice(stdout).map_err(|_| {
        let detail = String::from_utf8_lossy(stderr);
        if detail.trim().is_empty() {
            "Wi-Fi backend did not return valid JSON.".into()
        } else {
            detail.chars().take(2000).collect::<String>()
        }
    })?;
    if value["contract_version"] != "0.1.0" {
        return Err("Unsupported Wi-Fi backend contract version.".into());
    }
    let failed = if kind == "scan" {
        value["scan"]["status"] == "failed"
    } else {
        value["error"].is_object()
    };
    if !success && !failed {
        return Err("Wi-Fi backend exited before completing the request.".into());
    }
    if kind == "scan"
        && (value["observations"].as_array().is_none()
            || (failed && !value["observations"].as_array().unwrap().is_empty()))
    {
        return Err("Invalid Wi-Fi scan result.".into());
    }
    Ok(value)
}

async fn run_backend(
    app: tauri::AppHandle,
    state: tauri::State<'_, BackendState>,
    kind: &str,
    interface: Option<String>,
    cached: bool,
) -> Result<Value, String> {
    // The frontend can request these fixed operations; it never supplies an executable or shell command.
    if let Some(ref id) = interface {
        if id.is_empty() || id.len() > 200 || id.chars().any(char::is_control) {
            return Err("Invalid Wi-Fi interface identifier.".into());
        }
    }
    let root = backend_path(&app)?;
    let (sender, mut receiver) = watch::channel(false);
    {
        let mut slot = state.0.lock().map_err(|_| "Wi-Fi request lock failed")?;
        if slot.is_some() {
            return Err("A Wi-Fi request is already running.".into());
        }
        *slot = Some(sender);
    }
    let mut command = backend_command(root);
    command.arg(kind).arg("--json").kill_on_drop(true);
    if kind == "scan" {
        command.args(["--timeout", "90"]);
        if let Some(id) = interface {
            command.arg("--interface").arg(id);
        }
        if cached {
            command.arg("--cached");
        }
    }
    let result = tokio::select! {
        _ = receiver.changed() => Err("Scan cancelled.".into()),
        result = tokio::time::timeout(Duration::from_secs(100), command.output()) => {
            match result {
                Ok(Ok(output)) => decode_output(&output.stdout, &output.stderr, output.status.success(), kind),
                Ok(Err(error)) => Err(format!("Could not start the Wi-Fi backend: {error}")),
                Err(_) => Err("Wi-Fi backend timed out. Check location permission or NetworkManager authorization.".into()),
            }
        }
    };
    *state.0.lock().map_err(|_| "Wi-Fi request lock failed")? = None;
    result
}

#[tauri::command]
async fn backend_interfaces(
    app: tauri::AppHandle,
    state: tauri::State<'_, BackendState>,
) -> Result<Value, String> {
    run_backend(app, state, "interfaces", None, false).await
}

#[tauri::command]
async fn backend_scan(
    app: tauri::AppHandle,
    state: tauri::State<'_, BackendState>,
    interface: String,
    cached: bool,
) -> Result<Value, String> {
    run_backend(app, state, "scan", Some(interface), cached).await
}

#[tauri::command]
fn cancel_scan(state: tauri::State<'_, BackendState>) -> Result<(), String> {
    if let Some(sender) = state
        .0
        .lock()
        .map_err(|_| "Wi-Fi request lock failed")?
        .as_ref()
    {
        let _ = sender.send(true);
    }
    Ok(())
}

#[tauri::command]
async fn save_capture(
    app: tauri::AppHandle,
    value: Value,
    filename: String,
) -> Result<bool, String> {
    // A native save dialog supplies the path; never accept a write path from the webview.
    let json = serde_json::to_vec_pretty(&value).map_err(|e| e.to_string())?;
    if json.len() > 8 * 1024 * 1024 || value["contract_version"] != "0.1.0" {
        return Err("Invalid capture.".into());
    }
    if !filename.ends_with(".json") || filename.contains(['/', '\\']) {
        return Err("Invalid capture filename.".into());
    }
    let (sender, receiver) = tokio::sync::oneshot::channel();
    app.dialog()
        .file()
        .add_filter("Marinus scan", &["json"])
        .set_file_name(filename)
        .save_file(move |path| {
            let _ = sender.send(path);
        });
    let Some(file) = receiver
        .await
        .map_err(|_| "Save dialog closed unexpectedly")?
    else {
        return Ok(false);
    };
    let path = file.into_path().map_err(|e| e.to_string())?;
    use std::io::Write;
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut output = options
        .open(path)
        .map_err(|e| format!("Could not create capture. Choose a new filename: {e}"))?;
    output
        .write_all(&json)
        .and_then(|_| output.write_all(b"\n"))
        .map_err(|e| e.to_string())?;
    Ok(true)
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            #[cfg(target_os = "windows")]
            if let Some(window) = app.get_webview_window("main") {
                if let Some(monitor) = window.current_monitor()? {
                    // Configured sizes are logical pixels. Fit the native frame inside
                    // the work area so display scaling cannot hide it behind the taskbar.
                    let work = monitor.work_area();
                    let outer = window.outer_size()?;
                    let inner = window.inner_size()?;
                    let frame_width = outer.width.saturating_sub(inner.width);
                    let frame_height = outer.height.saturating_sub(inner.height);
                    let available = tauri::PhysicalSize::new(
                        work.size.width.saturating_sub(frame_width + 32).max(1),
                        work.size.height.saturating_sub(frame_height + 32).max(1),
                    );
                    if outer.width > work.size.width || outer.height > work.size.height {
                        // On small displays, also relax the minimum to the space available.
                        let minimum = tauri::LogicalSize::new(760.0, 520.0)
                            .to_physical::<u32>(monitor.scale_factor());
                        window.set_min_size(Some(tauri::PhysicalSize::new(
                            minimum.width.min(available.width),
                            minimum.height.min(available.height),
                        )))?;
                        let fitted = tauri::PhysicalSize::new(
                            inner.width.min(available.width),
                            inner.height.min(available.height),
                        );
                        window.set_size(fitted)?;
                        window.set_position(tauri::PhysicalPosition::new(
                            work.position.x
                                + (work.size.width.saturating_sub(fitted.width + frame_width) / 2)
                                    as i32,
                            work.position.y
                                + (work
                                    .size
                                    .height
                                    .saturating_sub(fitted.height + frame_height)
                                    / 2) as i32,
                        ))?;
                    }
                }
            }
            #[cfg(not(target_os = "windows"))]
            let _ = app;
            Ok(())
        })
        .manage(BackendState::default())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            backend_interfaces,
            backend_scan,
            cancel_scan,
            save_capture
        ])
        .run(tauri::generate_context!())
        .expect("could not run Marinus Desktop");
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn structured_failures_survive_nonzero_exit() {
        let data = br#"{"contract_version":"0.1.0","scan":{"status":"failed","error":{"code":"permission_denied"}},"observations":[]}"#;
        assert!(decode_output(data, b"denied", false, "scan").is_ok());
    }
    #[test]
    fn crashes_and_incompatible_contracts_are_rejected() {
        assert!(decode_output(b"", b"native failure", false, "scan").is_err());
        assert!(decode_output(br#"{"contract_version":"1.0.0"}"#, b"", true, "scan").is_err());
        assert!(decode_output(
            br#"{"contract_version":"0.1.0","scan":{"status":"completed"},"observations":[]}"#,
            b"",
            false,
            "scan"
        )
        .is_err());
    }
    #[test]
    fn failed_scans_cannot_smuggle_cached_observations() {
        let data =
            br#"{"contract_version":"0.1.0","scan":{"status":"failed"},"observations":[{}]}"#;
        assert!(decode_output(data, b"", false, "scan").is_err());
    }
}
