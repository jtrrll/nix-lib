//! Subcommand implementations.

use std::collections::BTreeSet;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use crate::config::{code_root, sessions_root};
use crate::git;
use crate::slug::slugify;
use crate::zellij;

struct RepoSpec {
    repo: String,
    branch: Option<String>,
    label: Option<String>,
}

struct Resolved {
    bare: PathBuf,
    label: String,
    branch: String,
}

/// Split a `--repo` value into a repo and optional branch. Only non-URL repos
/// use `:` as a branch separator, since URLs contain colons themselves.
fn split_repo_branch(val: &str) -> (String, Option<String>) {
    if git::looks_like_url(val) {
        return (val.to_string(), None);
    }
    match val.split_once(':') {
        Some((r, b)) => (r.to_string(), Some(b.to_string())),
        None => (val.to_string(), None),
    }
}

/// Pair positional `--repo`/`--label` values into specs.
fn parse_specs(repos: &[String], labels: &[String]) -> Result<Vec<RepoSpec>, String> {
    if labels.len() > repos.len() {
        return Err("more --label values than --repo values".to_string());
    }
    let mut specs = Vec::with_capacity(repos.len());
    for (idx, val) in repos.iter().enumerate() {
        let (repo, branch) = split_repo_branch(val);
        specs.push(RepoSpec {
            repo,
            branch,
            label: labels.get(idx).cloned(),
        });
    }
    Ok(specs)
}

fn unique_label(base: &str, used: &mut BTreeSet<String>) -> String {
    let base = if base.is_empty() {
        "repo".to_string()
    } else {
        base.to_string()
    };
    if used.insert(base.clone()) {
        return base;
    }
    let mut n = 2;
    loop {
        let candidate = format!("{base}-{n}");
        if used.insert(candidate.clone()) {
            return candidate;
        }
        n += 1;
    }
}

/// Resolve each spec to a bare repo, a unique label, and a branch name.
/// `used` is seeded with labels already taken (e.g. existing worktrees).
/// URL repos not yet under CODE_HOME are bare-cloned on demand.
fn resolve_specs(
    slug: &str,
    code: &Path,
    specs: &[RepoSpec],
    used: &mut BTreeSet<String>,
) -> Result<Vec<Resolved>, String> {
    let mut resolved = Vec::with_capacity(specs.len());
    for spec in specs {
        let (bare, repo_name) = if git::looks_like_url(&spec.repo) {
            let name = git::repo_name_from_ref(&spec.repo);
            let dest = code.join(&name);
            if !git::is_git_repo(&dest) {
                git::clone_bare(&spec.repo, &dest)?;
                println!("cloned {} -> {}", spec.repo, dest.display());
            }
            (dest, name)
        } else {
            let bare = git::resolve_bare_repo(code, &spec.repo)?;
            (bare, git::repo_name_from_ref(&spec.repo))
        };
        let base_label = spec.label.clone().unwrap_or_else(|| slugify(&repo_name));
        let label = unique_label(&base_label, used);
        let branch = spec
            .branch
            .clone()
            .unwrap_or_else(|| format!("{slug}/{label}"));
        resolved.push(Resolved {
            bare,
            label,
            branch,
        });
    }
    Ok(resolved)
}

/// Create a worktree per resolved spec. On failure, roll back only the
/// worktrees created by this call and return the error.
fn create_worktrees(worktrees_dir: &Path, resolved: &[Resolved]) -> Result<(), String> {
    let mut created: Vec<PathBuf> = Vec::new();
    for r in resolved {
        let wt_path = worktrees_dir.join(&r.label);
        if let Err(e) = git::add_worktree(&r.bare, &wt_path, &r.branch) {
            for done in created.iter().rev() {
                let _ = git::remove_worktree(done);
            }
            return Err(e);
        }
        println!("created worktree {} on {}", wt_path.display(), r.branch);
        created.push(wt_path);
    }
    Ok(())
}

/// Labels already present as worktrees under a session.
fn existing_labels(worktrees_dir: &Path) -> BTreeSet<String> {
    let mut set = BTreeSet::new();
    if let Ok(rd) = fs::read_dir(worktrees_dir) {
        for entry in rd.filter_map(|e| e.ok()) {
            if entry.path().is_dir() {
                set.insert(entry.file_name().to_string_lossy().to_string());
            }
        }
    }
    set
}

/// Create the agent memory directory and a goals template for a new session.
fn scaffold_workspace(session_dir: &Path, name: &str) -> Result<(), String> {
    let agent_dir = session_dir.join("agent");
    fs::create_dir_all(&agent_dir).map_err(|e| format!("creating {}: {e}", agent_dir.display()))?;

    let goals = session_dir.join("GOALS.md");
    let template = format!(
        "# Goals: {name}\n\n\
         <!-- What is this session trying to accomplish? -->\n\n\
         ## Context\n\n\
         ## Tasks\n\n\
         - [ ] \n",
    );
    fs::write(&goals, template).map_err(|e| format!("writing {}: {e}", goals.display()))?;

    let agent_readme = agent_dir.join("README.md");
    let agent_note = "# Agent workspace\n\n\
         Scratch space for agent memory, notes, and generated files scoped to\n\
         this session. Safe to delete with the session.\n";
    let _ = fs::write(&agent_readme, agent_note);
    Ok(())
}

/// Prompt for a yes/no answer on stdin, defaulting to No.
fn confirm(prompt: &str) -> Result<bool, String> {
    use std::io::Write;
    print!("{prompt} [y/N] ");
    io::stdout().flush().ok();
    let mut input = String::new();
    io::stdin()
        .read_line(&mut input)
        .map_err(|e| format!("reading input: {e}"))?;
    let a = input.trim().to_ascii_lowercase();
    Ok(a == "y" || a == "yes")
}

pub fn new(name: &str, repos: &[String], labels: &[String]) -> Result<(), String> {
    let specs = parse_specs(repos, labels)?;

    let slug = slugify(name);
    if slug.is_empty() {
        return Err(format!("name '{name}' produces an empty slug"));
    }

    let session_dir = sessions_root()?.join(&slug);
    if session_dir.exists() {
        return Err(format!(
            "session '{slug}' already exists at {}",
            session_dir.display()
        ));
    }

    // Resolve and validate everything BEFORE creating anything, so a bad spec
    // can't leave a half-built session behind.
    let code = code_root()?;
    let mut used_labels: BTreeSet<String> = BTreeSet::new();
    let resolved = resolve_specs(&slug, &code, &specs, &mut used_labels)?;

    let worktrees_dir = session_dir.join("worktrees");
    fs::create_dir_all(&worktrees_dir)
        .map_err(|e| format!("creating {}: {e}", worktrees_dir.display()))?;

    if let Err(e) = create_worktrees(&worktrees_dir, &resolved) {
        let _ = fs::remove_dir_all(&session_dir);
        return Err(e);
    }

    // A place for agent memory/files and a goals document for the session.
    if let Err(e) = scaffold_workspace(&session_dir, name) {
        eprintln!("session: warning: {e}");
    }

    // Start (and attach to) a zellij session named after the slug, rooted at
    // the session dir. No generated layout — zellij's default.
    zellij::start(&slug, &session_dir, false)
}

pub fn attach(name: &str) -> Result<(), String> {
    let slug = slugify(name);
    let session_dir = sessions_root()?.join(&slug);
    if !session_dir.exists() {
        return Err(format!("session '{slug}' not found"));
    }
    zellij::start(&slug, &session_dir, true)
}

pub fn add_worktree(name: &str, repos: &[String], labels: &[String]) -> Result<(), String> {
    if repos.is_empty() {
        return Err("no --repo given".to_string());
    }
    let specs = parse_specs(repos, labels)?;

    let slug = slugify(name);
    let session_dir = sessions_root()?.join(&slug);
    if !session_dir.exists() {
        return Err(format!("session '{slug}' not found"));
    }
    let worktrees_dir = session_dir.join("worktrees");

    let code = code_root()?;
    // Seed with existing labels so new ones don't collide on disk.
    let mut used_labels = existing_labels(&worktrees_dir);
    let resolved = resolve_specs(&slug, &code, &specs, &mut used_labels)?;

    fs::create_dir_all(&worktrees_dir)
        .map_err(|e| format!("creating {}: {e}", worktrees_dir.display()))?;
    create_worktrees(&worktrees_dir, &resolved)
}

pub fn ls() -> Result<(), String> {
    let root = sessions_root()?;
    if !root.exists() {
        println!("no sessions (missing {})", root.display());
        return Ok(());
    }
    let live = zellij::live_sessions();

    let mut entries: Vec<PathBuf> = fs::read_dir(&root)
        .map_err(|e| format!("reading {}: {e}", root.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.is_dir())
        .collect();
    entries.sort();

    if entries.is_empty() {
        println!("no sessions");
        return Ok(());
    }

    for dir in entries {
        let slug = dir
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        let marker = if live.contains(&slug) { "*" } else { " " };
        println!("{marker} {slug}");
        let wt_dir = dir.join("worktrees");
        if let Ok(rd) = fs::read_dir(&wt_dir) {
            let mut wts: Vec<PathBuf> = rd.filter_map(|e| e.ok().map(|e| e.path())).collect();
            wts.sort();
            for wt in wts {
                let label = wt
                    .file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .to_string();
                let branch = git::current_branch(&wt).unwrap_or_else(|| "?".to_string());
                let repo = git::worktree_repo_name(&wt).unwrap_or_else(|| "?".to_string());
                println!("    {label}  [{repo}]  {branch}");
            }
        }
    }
    if !live.is_empty() {
        println!("\n* = live zellij session");
    }
    Ok(())
}

pub fn rm(name: &str, force: bool) -> Result<(), String> {
    let slug = slugify(name);
    let session_dir = sessions_root()?.join(&slug);
    if !session_dir.exists() {
        return Err(format!("session '{slug}' not found"));
    }

    // Enumerate worktrees up front, both for the confirmation prompt and to
    // know which bare repos to prune afterwards.
    let wt_dir = session_dir.join("worktrees");
    let worktrees: Vec<PathBuf> = fs::read_dir(&wt_dir)
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.is_dir())
        .collect();
    let dirty: Vec<&PathBuf> = worktrees.iter().filter(|p| git::is_dirty(p)).collect();

    if !force {
        println!(
            "About to remove session '{slug}' ({} worktree(s)) at {}",
            worktrees.len(),
            session_dir.display()
        );
        for d in &dirty {
            println!("  ! {} has uncommitted changes", d.display());
        }
        if !confirm("Proceed?")? {
            println!("aborted");
            return Ok(());
        }
    }

    // Collect the bare repos we touch so we can prune them afterwards.
    let mut bares: BTreeSet<PathBuf> = BTreeSet::new();
    for wt in &worktrees {
        if let Some(bare) = git::git_common_dir(wt) {
            bares.insert(bare);
        }
        if let Err(e) = git::remove_worktree(wt) {
            if !force {
                return Err(format!("{e} (use --force to remove anyway)"));
            }
            eprintln!("warning: {e}; forcing");
        }
    }

    zellij::teardown(&slug);

    // Remove the session directory and prune dangling worktree refs.
    fs::remove_dir_all(&session_dir)
        .map_err(|e| format!("removing {}: {e}", session_dir.display()))?;
    for bare in bares {
        let _ = git::git(&bare, &["worktree", "prune"]);
    }
    println!("removed session '{slug}'");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unique_label_dedupes() {
        let mut used = BTreeSet::new();
        assert_eq!(unique_label("api", &mut used), "api");
        assert_eq!(unique_label("api", &mut used), "api-2");
        assert_eq!(unique_label("api", &mut used), "api-3");
        assert_eq!(unique_label("", &mut used), "repo");
    }

    #[test]
    fn split_repo_branch_handles_urls_and_locals() {
        assert_eq!(split_repo_branch("api"), ("api".into(), None));
        assert_eq!(
            split_repo_branch("api:feature/x"),
            ("api".into(), Some("feature/x".into()))
        );
        // URLs must not be split on their colons.
        assert_eq!(
            split_repo_branch("https://github.com/org/repo.git"),
            ("https://github.com/org/repo.git".into(), None)
        );
        assert_eq!(
            split_repo_branch("git@github.com:org/repo.git"),
            ("git@github.com:org/repo.git".into(), None)
        );
    }
}
