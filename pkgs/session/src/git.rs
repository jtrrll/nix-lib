//! Git plumbing: running git and the worktree/branch/clone operations sessions
//! rely on.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Result of running an external command.
pub struct Output {
    pub status: bool,
    pub stdout: String,
    pub stderr: String,
}

/// Run `git -C <dir> <args...>` and capture its output.
pub fn git(dir: &Path, args: &[&str]) -> Result<Output, String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .output()
        .map_err(|e| format!("failed to run git: {e}"))?;
    Ok(Output {
        status: out.status.success(),
        stdout: String::from_utf8_lossy(&out.stdout).to_string(),
        stderr: String::from_utf8_lossy(&out.stderr).to_string(),
    })
}

pub fn is_git_repo(dir: &Path) -> bool {
    dir.is_dir()
        && git(dir, &["rev-parse", "--git-dir"])
            .map(|o| o.status)
            .unwrap_or(false)
}

pub fn is_dirty(wt: &Path) -> bool {
    git(wt, &["status", "--porcelain"])
        .map(|o| o.status && !o.stdout.trim().is_empty())
        .unwrap_or(false)
}

pub fn current_branch(wt: &Path) -> Option<String> {
    let o = git(wt, &["branch", "--show-current"]).ok()?;
    if o.status {
        let b = o.stdout.trim();
        if b.is_empty() {
            None
        } else {
            Some(b.to_string())
        }
    } else {
        None
    }
}

pub fn git_common_dir(wt: &Path) -> Option<PathBuf> {
    let o = git(
        wt,
        &["rev-parse", "--path-format=absolute", "--git-common-dir"],
    )
    .ok()?;
    if !o.status {
        return None;
    }
    let p = o.stdout.trim();
    if p.is_empty() {
        None
    } else {
        Some(PathBuf::from(p))
    }
}

/// Bare-repo directory name for a worktree (trailing `.git` stripped).
pub fn worktree_repo_name(wt: &Path) -> Option<String> {
    let common = git_common_dir(wt)?;
    let name = common.file_name()?.to_string_lossy().to_string();
    Some(name.strip_suffix(".git").unwrap_or(&name).to_string())
}

/// Locate a bare repo under CODE_HOME by name (with or without `.git`).
pub fn resolve_bare_repo(code: &Path, repo: &str) -> Result<PathBuf, String> {
    for cand in [code.join(repo), code.join(format!("{repo}.git"))] {
        if is_git_repo(&cand) {
            return Ok(cand);
        }
    }
    Err(format!(
        "repo '{repo}' not found under {} (pass a URL to clone it, or `git clone-bare` it first)",
        code.display()
    ))
}

/// Heuristic: does this `--repo` value name a remote to clone rather than a
/// repo already under CODE_HOME?
pub fn looks_like_url(s: &str) -> bool {
    s.contains("://") || s.starts_with("git@")
}

/// Derive a bare-repo directory name from a URL or local ref: the final path
/// component with any trailing `.git` removed.
pub fn repo_name_from_ref(s: &str) -> String {
    let trimmed = s.trim_end_matches('/');
    let last = trimmed.rsplit(['/', ':']).next().unwrap_or(trimmed);
    last.strip_suffix(".git").unwrap_or(last).to_string()
}

/// Bare-clone a remote into `dest`, wiring up the fetch refspec and origin/HEAD
/// so new worktree branches can fork from the remote's default branch.
pub fn clone_bare(url: &str, dest: &Path) -> Result<(), String> {
    let dest_str = dest.to_string_lossy().to_string();
    let out = Command::new("git")
        .args(["clone", "--bare", url, &dest_str])
        .output()
        .map_err(|e| format!("failed to run git clone: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "git clone --bare failed for {url}: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    // Populate refs/remotes/origin/* and origin/HEAD for accurate base branches.
    let _ = git(
        dest,
        &[
            "config",
            "remote.origin.fetch",
            "+refs/heads/*:refs/remotes/origin/*",
        ],
    );
    let _ = git(dest, &["fetch", "--quiet", "origin"]);
    let _ = git(dest, &["remote", "set-head", "origin", "--auto"]);
    Ok(())
}

/// Start point for a freshly created branch: the remote's default branch when
/// known (origin/HEAD), otherwise fall back to the bare repo's current HEAD.
fn default_start_point(bare: &Path) -> Option<String> {
    let has_origin_head = git(
        bare,
        &[
            "rev-parse",
            "--verify",
            "--quiet",
            "refs/remotes/origin/HEAD",
        ],
    )
    .map(|o| o.status)
    .unwrap_or(false);
    if has_origin_head {
        Some("refs/remotes/origin/HEAD".to_string())
    } else {
        None
    }
}

/// Add a worktree at `wt_path` on `branch`. Existing branches are checked out
/// as-is; new branches fork from the remote default branch when known.
pub fn add_worktree(bare: &Path, wt_path: &Path, branch: &str) -> Result<(), String> {
    let branch_exists = git(
        bare,
        &[
            "show-ref",
            "--verify",
            "--quiet",
            &format!("refs/heads/{branch}"),
        ],
    )
    .map(|o| o.status)
    .unwrap_or(false);

    let path = wt_path.to_string_lossy().to_string();
    let start_point = if branch_exists {
        None
    } else {
        default_start_point(bare)
    };
    let args: Vec<&str> = match (branch_exists, &start_point) {
        (true, _) => vec!["worktree", "add", &path, branch],
        (false, Some(sp)) => vec!["worktree", "add", "-b", branch, &path, sp],
        (false, None) => vec!["worktree", "add", "-b", branch, &path],
    };
    let out = git(bare, &args)?;
    if !out.status {
        return Err(format!(
            "git worktree add failed for {}: {}",
            wt_path.display(),
            out.stderr.trim()
        ));
    }
    Ok(())
}

pub fn remove_worktree(wt: &Path) -> Result<(), String> {
    let path = wt.to_string_lossy().to_string();
    let out = git(wt, &["worktree", "remove", "--force", &path])?;
    if out.status {
        return Ok(());
    }
    Err(format!(
        "failed to remove worktree {}: {}",
        wt.display(),
        out.stderr.trim()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn repo_name_from_ref_variants() {
        assert_eq!(repo_name_from_ref("api"), "api");
        assert_eq!(repo_name_from_ref("api.git"), "api");
        assert_eq!(
            repo_name_from_ref("https://github.com/org/repo.git"),
            "repo"
        );
        assert_eq!(repo_name_from_ref("https://github.com/org/repo"), "repo");
        assert_eq!(repo_name_from_ref("git@github.com:org/repo.git"), "repo");
        assert_eq!(repo_name_from_ref("ssh://git@host/org/repo.git"), "repo");
        assert_eq!(repo_name_from_ref("git@github.com:org/repo/"), "repo");
    }

    #[test]
    fn looks_like_url_detects_remotes() {
        assert!(looks_like_url("https://github.com/org/repo"));
        assert!(looks_like_url("ssh://git@host/org/repo"));
        assert!(looks_like_url("git@github.com:org/repo.git"));
        assert!(!looks_like_url("repo"));
        assert!(!looks_like_url("org-repo"));
    }
}
