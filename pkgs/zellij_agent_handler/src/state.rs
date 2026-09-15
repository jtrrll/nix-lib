use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use zellij_tile::prelude::*;

/// Activity state for an agent.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Activity {
    Idle,
    Busy,
    Permission,
    Retry,
}

impl Activity {
    pub fn symbol(&self) -> &'static str {
        match self {
            Activity::Idle => "○",
            Activity::Busy => "●",
            Activity::Permission => "⚠",
            Activity::Retry => "↻",
        }
    }
}

/// State of a single agent pane.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AgentState {
    pub pane_id: u32,
    pub name: String,
    pub activity: Activity,
    pub tab_name: Option<String>,
    pub tab_index: Option<usize>,
    pub action: Option<String>,
    pub snippet: Option<String>,
}

impl AgentState {
    pub fn new(pane_id: u32, name: String) -> Self {
        Self {
            pane_id,
            name,
            activity: Activity::Idle,
            tab_name: None,
            tab_index: None,
            action: None,
            snippet: None,
        }
    }
}

/// Message sent from an agent harness via `zellij pipe`.
#[derive(Debug, Deserialize, PartialEq)]
pub struct PipePayload {
    pub pane_id: u32,
    pub activity: Activity,
    pub name: Option<String>,
    pub action: Option<String>,
    pub snippet: Option<String>,
}

/// Click region for mouse interaction.
pub struct ClickRegion {
    pub start_col: usize,
    pub end_col: usize,
    pub pane_id: Option<u32>,
    pub tab_index: Option<usize>,
    pub row: usize,
}

/// Top-level plugin state.
#[derive(Default)]
pub struct HandlerState {
    pub agents: BTreeMap<u32, AgentState>,
    pub pane_to_tab: HashMap<u32, (usize, String)>,
    pub tabs: Vec<TabInfo>,
    pub pane_manifest: Option<PaneManifest>,
    pub active_tab_index: Option<usize>,
    pub session_name: Option<String>,
    pub click_regions: Vec<ClickRegion>,
    pub scroll_offset: usize,
    pub total_lines: usize,
    pub visible_rows: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn activity_symbols_are_distinct() {
        let symbols: Vec<&str> = [
            Activity::Idle,
            Activity::Busy,
            Activity::Permission,
            Activity::Retry,
        ]
        .iter()
        .map(|a| a.symbol())
        .collect();
        let mut unique = symbols.clone();
        unique.dedup();
        assert_eq!(symbols.len(), unique.len());
    }

    #[test]
    fn agent_state_new_defaults_to_idle() {
        let agent = AgentState::new(5, "test-agent".into());
        assert_eq!(agent.activity, Activity::Idle);
        assert_eq!(agent.pane_id, 5);
        assert_eq!(agent.name, "test-agent");
        assert_eq!(agent.tab_name, None);
        assert_eq!(agent.tab_index, None);
    }

    #[test]
    fn pipe_payload_deserializes_from_json() {
        let json = r#"{"pane_id":9,"activity":"Busy","name":"agent-1"}"#;
        let payload: PipePayload = serde_json::from_str(json).unwrap();
        assert_eq!(payload.pane_id, 9);
        assert_eq!(payload.activity, Activity::Busy);
        assert_eq!(payload.name, Some("agent-1".into()));
    }

    #[test]
    fn pipe_payload_deserializes_without_name() {
        let json = r#"{"pane_id":3,"activity":"Idle"}"#;
        let payload: PipePayload = serde_json::from_str(json).unwrap();
        assert_eq!(payload.pane_id, 3);
        assert_eq!(payload.activity, Activity::Idle);
        assert_eq!(payload.name, None);
    }

    #[test]
    fn agent_state_roundtrips_through_json() {
        let agent = AgentState {
            pane_id: 7,
            name: "assistant".into(),
            activity: Activity::Permission,
            tab_name: Some("workspace".into()),
            tab_index: Some(0),
        };
        let json = serde_json::to_string(&agent).unwrap();
        let recovered: AgentState = serde_json::from_str(&json).unwrap();
        assert_eq!(agent, recovered);
    }

    #[test]
    fn agents_btreemap_roundtrips_through_json() {
        let mut agents = BTreeMap::new();
        agents.insert(1, AgentState::new(1, "agent-1".into()));
        agents.insert(
            2,
            AgentState {
                pane_id: 2,
                name: "agent-2".into(),
                activity: Activity::Busy,
                tab_name: Some("agents".into()),
                tab_index: Some(1),
            },
        );
        let json = serde_json::to_string(&agents).unwrap();
        let recovered: BTreeMap<u32, AgentState> = serde_json::from_str(&json).unwrap();
        assert_eq!(agents, recovered);
    }
}
