use crate::state::{Activity, ClickRegion, HandlerState};
use std::collections::BTreeMap;
use std::io::Write;
use unicode_width::UnicodeWidthStr;

/// Renders the agent tree sidebar.
pub fn render(state: &mut HandlerState, rows: usize, cols: usize) {
    state.click_regions.clear();

    let mut lines: Vec<String> = Vec::new();
    let mut regions: Vec<Option<ClickRegion>> = Vec::new();

    if state.agents.is_empty() {
        lines.push(format_line(" (no agents)", cols));
        regions.push(None);
    } else {
        // Group agents by tab name
        let mut groups: BTreeMap<String, Vec<&crate::state::AgentState>> = BTreeMap::new();
        for agent in state.agents.values() {
            let tab = agent.tab_name.as_deref().unwrap_or("?").to_string();
            groups.entry(tab).or_default().push(agent);
        }

        let group_count = groups.len();
        for (gi, (tab_name, agents)) in groups.iter().enumerate() {
            let is_last_group = gi == group_count - 1;
            let branch = if is_last_group { " └─" } else { " ├─" };
            let continuation = if is_last_group { "    " } else { " │  " };

            let tab_row = lines.len();
            lines.push(format_line(&format!("{} {}", branch, tab_name), cols));
            // Tab header click region — get tab_index from first agent in group
            let group_tab_index = agents.first().and_then(|a| a.tab_index);
            regions.push(Some(ClickRegion {
                start_col: 0,
                end_col: cols,
                pane_id: None,
                tab_index: group_tab_index,
                row: tab_row,
            }));

            let agent_count = agents.len();
            for (ai, agent) in agents.iter().enumerate() {
                let is_last_agent = ai == agent_count - 1;
                let agent_branch = if is_last_agent { "└─" } else { "├─" };

                let symbol = agent.activity.symbol();
                let color = activity_color(&agent.activity);
                let reset = "\x1b[0m";

                let plain_text =
                    format!("{}{} {} {}", continuation, agent_branch, agent.name, symbol);
                let plain_width = UnicodeWidthStr::width(plain_text.as_str());
                let colored_text = format!(
                    "{}{} {}{} {}{}",
                    continuation, agent_branch, color, agent.name, symbol, reset
                );

                let row = lines.len();
                lines.push(pad_colored(&colored_text, plain_width, cols));
                regions.push(Some(ClickRegion {
                    start_col: 0,
                    end_col: cols,
                    pane_id: Some(agent.pane_id),
                    tab_index: agent.tab_index,
                    row,
                }));

                // Detail lines (action and snippet) indented under the agent
                let detail_indent = format!("{}   ", continuation);
                let indent_width = UnicodeWidthStr::width(detail_indent.as_str());
                if let Some(ref action) = agent.action {
                    let icon = "⚙";
                    let icon_width = UnicodeWidthStr::width(icon);
                    let max_action_width = cols.saturating_sub(indent_width + icon_width + 1);
                    let truncated = truncate(action, max_action_width);
                    let plain_width =
                        indent_width + icon_width + 1 + UnicodeWidthStr::width(truncated.as_str());
                    let detail = format!("{}{} \x1b[3m{}\x1b[0m", detail_indent, icon, truncated);
                    lines.push(pad_colored(&detail, plain_width, cols));
                    regions.push(None);
                }
                if let Some(ref snippet) = agent.snippet {
                    let icon = "›";
                    let icon_width = UnicodeWidthStr::width(icon);
                    let max_snippet_width = cols.saturating_sub(indent_width + icon_width + 1);
                    let truncated = truncate(snippet, max_snippet_width);
                    let plain_width =
                        indent_width + icon_width + 1 + UnicodeWidthStr::width(truncated.as_str());
                    let detail = format!("{}{} \x1b[2m{}\x1b[0m", detail_indent, icon, truncated);
                    lines.push(pad_colored(&detail, plain_width, cols));
                    regions.push(None);
                }
                if let Some(ref snippet) = agent.snippet {
                    let icon = "›";
                    let detail = format!(
                        "{}{} \x1b[2m{}\x1b[0m",
                        detail_indent,
                        icon,
                        truncate(snippet, cols.saturating_sub(detail_indent.len() + 3))
                    );
                    let plain_len = detail_indent.len()
                        + 2
                        + snippet
                            .len()
                            .min(cols.saturating_sub(detail_indent.len() + 3));
                    lines.push(pad_colored(&detail, plain_len, cols));
                    regions.push(None);
                }
            }
        }
    }

    // Record total lines for scroll bounds
    state.total_lines = lines.len();
    state.visible_rows = rows;

    // Clamp scroll offset
    if state.scroll_offset >= lines.len() {
        state.scroll_offset = lines.len().saturating_sub(1);
    }

    // Render visible lines with scroll offset
    let visible = &lines[state.scroll_offset..];
    for i in 0..rows {
        if i < visible.len() {
            print!("{}", visible[i]);
        } else {
            print!("{:<width$}", "", width = cols);
        }
    }
    let _ = std::io::stdout().flush();

    // Store click regions, adjusting row indices for scroll offset
    state.click_regions = regions
        .into_iter()
        .flatten()
        .filter(|r| r.row >= state.scroll_offset && r.row < state.scroll_offset + rows)
        .map(|mut r| {
            r.row -= state.scroll_offset;
            r
        })
        .collect();
}

fn format_line(text: &str, cols: usize) -> String {
    let width = UnicodeWidthStr::width(text);
    if width >= cols {
        text.to_string()
    } else {
        format!("{}{}", text, " ".repeat(cols - width))
    }
}

fn pad_colored(colored: &str, plain_width: usize, cols: usize) -> String {
    if plain_width >= cols {
        colored.to_string()
    } else {
        format!("{}{}", colored, " ".repeat(cols - plain_width))
    }
}

fn activity_color(activity: &Activity) -> &'static str {
    match activity {
        Activity::Busy => "\x1b[1;36m",       // bold cyan
        Activity::Permission => "\x1b[1;33m", // bold yellow
        Activity::Retry => "\x1b[1;35m",      // bold magenta
        Activity::Idle => "\x1b[2m",          // dim
    }
}

fn truncate(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else if max_len <= 1 {
        "…".to_string()
    } else {
        format!("{}…", &s[..max_len - 1])
    }
}
