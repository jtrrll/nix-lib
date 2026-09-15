//! Filesystem roots, overridable via environment for testing and packaging.

use std::env;
use std::path::PathBuf;

fn home() -> Result<PathBuf, String> {
    env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| "HOME is not set".to_string())
}

/// Root under which sessions live (`SESSION_HOME`, default `~/sessions`).
pub fn sessions_root() -> Result<PathBuf, String> {
    match env::var_os("SESSION_HOME") {
        Some(p) => Ok(PathBuf::from(p)),
        None => Ok(home()?.join("sessions")),
    }
}

/// Root under which bare repos live (`CODE_HOME`, default `~/code`).
pub fn code_root() -> Result<PathBuf, String> {
    match env::var_os("CODE_HOME") {
        Some(p) => Ok(PathBuf::from(p)),
        None => Ok(home()?.join("code")),
    }
}
