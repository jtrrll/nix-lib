//! Zellij session control.

use std::collections::BTreeSet;
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread::sleep;
use std::time::Duration;

use crate::git::Output;

fn zellij(args: &[&str]) -> Result<Output, String> {
    let out = Command::new("zellij")
        .args(args)
        .output()
        .map_err(|e| format!("failed to run zellij: {e}"))?;
    Ok(Output {
        status: out.status.success(),
        stdout: String::from_utf8_lossy(&out.stdout).to_string(),
        stderr: String::from_utf8_lossy(&out.stderr).to_string(),
    })
}

/// Names of currently live zellij sessions.
pub fn live_sessions() -> BTreeSet<String> {
    let mut set = BTreeSet::new();
    if let Ok(o) = zellij(&["list-sessions", "--no-formatting", "--short"]) {
        if o.status {
            for line in o.stdout.lines() {
                let name = line.trim();
                if !name.is_empty() {
                    set.insert(name.to_string());
                }
            }
        }
    }
    set
}

/// Start a session in the foreground. When `attach_existing`, attach to an
/// existing session (creating it if absent); otherwise create a fresh one.
pub fn start(slug: &str, cwd: &Path, attach_existing: bool) -> Result<(), String> {
    let mut cmd = Command::new("zellij");
    if attach_existing {
        cmd.arg("attach").arg("--create").arg(slug);
    } else {
        cmd.arg("--session").arg(slug);
    }
    let status = cmd
        .current_dir(cwd)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .map_err(|e| format!("failed to start zellij: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err("zellij exited with an error".to_string())
    }
}

/// Tear down the zellij session with the given slug, if any.
///
/// `kill-session` is asynchronous: it initiates shutdown but returns before the
/// session has fully exited. Deleting too eagerly races that shutdown and
/// leaves the exited session lingering on disk, so wait for the session to
/// leave the live set (bounded) before forcing the delete.
pub fn teardown(slug: &str) {
    let _ = zellij(&["kill-session", slug]);

    for _ in 0..50 {
        if !live_sessions().contains(slug) {
            break;
        }
        sleep(Duration::from_millis(100));
    }

    let _ = zellij(&["delete-session", slug, "--force"]);
}
