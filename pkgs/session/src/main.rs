//! `session` — orchestrate a unit of work as one lifecycle across git worktrees
//! and a zellij session, all keyed by a single slug.
//!
//! Layout (source of truth is the filesystem + git, no manifest):
//!   ~/sessions/<slug>/worktrees/<label>/   # a git worktree on branch <slug>/<label>
//!   ~/sessions/<slug>/agent/               # session-scoped agent memory/files
//!   ~/sessions/<slug>/GOALS.md             # what this session is for

mod commands;
mod config;
mod git;
mod slug;
mod zellij;

use std::io;

use clap::{CommandFactory, Parser, Subcommand};
use clap_complete::Shell;

/// Manage development sessions as git worktrees and a zellij session.
///
/// Each session is one unit of work, keyed by a slug derived from its name,
/// owning its worktrees under ~/sessions/<slug>/worktrees/<label> and a zellij
/// session of the same name.
#[derive(Parser)]
#[command(name = "session", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Create a session: worktrees, branches, and a zellij session.
    New {
        /// Free-form session name (slugified for paths, branches, zellij).
        name: String,
        /// Repo spec `<repo>[:<branch>]` (a bare repo name under CODE_HOME, or
        /// a URL to clone). Branches only apply to non-URL repos. Repeatable.
        #[arg(long = "repo", value_name = "REPO[:BRANCH]")]
        repos: Vec<String>,
        /// Label for the --repo at the same position (default: repo name, deduped).
        #[arg(long = "label", value_name = "LABEL")]
        labels: Vec<String>,
    },
    /// Attach to a session's zellij session, creating it if needed.
    Attach {
        /// Session name or slug.
        name: String,
    },
    /// Add one or more worktrees to an existing session.
    AddWorktree {
        /// Session name or slug.
        name: String,
        /// Repo spec `<repo>[:<branch>]` (bare repo name or URL). Repeatable.
        #[arg(long = "repo", value_name = "REPO[:BRANCH]")]
        repos: Vec<String>,
        /// Label for the --repo at the same position (default: repo name, deduped).
        #[arg(long = "label", value_name = "LABEL")]
        labels: Vec<String>,
    },
    /// List sessions with their worktrees and live-zellij status.
    Ls,
    /// Remove a session: worktrees, zellij session, and its directory.
    Rm {
        /// Session name or slug.
        name: String,
        /// Skip confirmation and remove even if a worktree cannot be cleanly removed.
        #[arg(short, long)]
        force: bool,
    },
    /// Print shell completions for the given shell.
    Completions {
        /// Shell to generate completions for.
        shell: Shell,
    },
}

fn main() {
    let cli = Cli::parse();
    let result = match cli.command {
        Commands::New {
            name,
            repos,
            labels,
        } => commands::new(&name, &repos, &labels),
        Commands::Attach { name } => commands::attach(&name),
        Commands::AddWorktree {
            name,
            repos,
            labels,
        } => commands::add_worktree(&name, &repos, &labels),
        Commands::Ls => commands::ls(),
        Commands::Rm { name, force } => commands::rm(&name, force),
        Commands::Completions { shell } => {
            let mut cmd = Cli::command();
            let name = cmd.get_name().to_string();
            clap_complete::generate(shell, &mut cmd, name, &mut io::stdout());
            Ok(())
        }
    };
    if let Err(msg) = result {
        eprintln!("session: {msg}");
        std::process::exit(1);
    }
}
