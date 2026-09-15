mod render;
mod state;

use state::{AgentState, HandlerState, PipePayload};
use std::collections::BTreeMap;
use zellij_tile::prelude::*;

register_plugin!(HandlerState);

impl ZellijPlugin for HandlerState {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::ReadCliPipes,
            PermissionType::MessageAndLaunchOtherPlugins,
        ]);
        subscribe(&[
            EventType::TabUpdate,
            EventType::PaneUpdate,
            EventType::ModeUpdate,
            EventType::Mouse,
            EventType::PermissionRequestResult,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::TabUpdate(tabs) => {
                self.active_tab_index = tabs.iter().find(|t| t.active).map(|t| t.position);
                self.tabs = tabs;
                self.refresh_agents();
                true
            }
            Event::PaneUpdate(manifest) => {
                self.pane_manifest = Some(manifest);
                self.refresh_agents();
                true
            }
            Event::ModeUpdate(mode_info) => {
                if let Some(name) = mode_info.session_name {
                    self.session_name = Some(name);
                }
                false
            }
            Event::Mouse(Mouse::LeftClick(row, col)) => {
                let row = row as usize;
                let col = col as usize;
                for region in &self.click_regions {
                    if row == region.row && col >= region.start_col && col < region.end_col {
                        if region.tab_index != self.active_tab_index {
                            switch_tab_to(region.tab_index.unwrap_or(0) as u32 + 1);
                        }
                        if let Some(pane_id) = region.pane_id {
                            focus_terminal_pane(pane_id, false);
                        }
                        return false;
                    }
                }
                false
            }
            Event::Mouse(Mouse::ScrollUp(_)) => {
                if self.total_lines > self.visible_rows {
                    self.scroll_offset = self.scroll_offset.saturating_sub(3);
                    true
                } else {
                    false
                }
            }
            Event::Mouse(Mouse::ScrollDown(_)) => {
                if self.total_lines > self.visible_rows {
                    let max_offset = self.total_lines.saturating_sub(self.visible_rows);
                    self.scroll_offset = (self.scroll_offset + 3).min(max_offset);
                    true
                } else {
                    false
                }
            }
            Event::PermissionRequestResult(_) => {
                set_selectable(false);
                self.request_sync();
                false
            }
            _ => false,
        }
    }

    fn pipe(&mut self, pipe_message: PipeMessage) -> bool {
        match pipe_message.name.as_str() {
            "agent-handler" => {
                let payload_str = match pipe_message.payload {
                    Some(ref s) => s,
                    None => return false,
                };
                let payload: PipePayload = match serde_json::from_str(payload_str) {
                    Ok(p) => p,
                    Err(_) => return false,
                };
                self.update_agent(payload);
                self.broadcast_agents();
                true
            }
            "agent-handler:sync" => {
                if let Some(ref payload) = pipe_message.payload {
                    if let Ok(agents) = serde_json::from_str::<BTreeMap<u32, AgentState>>(payload) {
                        self.merge_agents(agents);
                        return true;
                    }
                }
                false
            }
            "agent-handler:request" => {
                self.broadcast_agents();
                false
            }
            _ => false,
        }
    }

    fn render(&mut self, rows: usize, cols: usize) {
        render::render(self, rows, cols);
    }
}

impl HandlerState {
    fn refresh_agents(&mut self) {
        if let Some(ref manifest) = self.pane_manifest {
            // Build pane_id -> (tab_index, tab_name) map and track exited panes
            self.pane_to_tab.clear();
            let mut exited_panes = std::collections::HashSet::new();
            for tab in &self.tabs {
                if let Some(panes) = manifest.panes.get(&tab.position) {
                    for pane in panes {
                        if !pane.is_plugin {
                            self.pane_to_tab
                                .insert(pane.id, (tab.position, tab.name.clone()));
                            if pane.exited {
                                exited_panes.insert(pane.id);
                            }
                        }
                    }
                }
            }
            // Update tab info on known agents and remove dead/exited panes
            for agent in self.agents.values_mut() {
                if let Some((idx, name)) = self.pane_to_tab.get(&agent.pane_id) {
                    agent.tab_index = Some(*idx);
                    agent.tab_name = Some(name.clone());
                }
            }
            self.agents.retain(|pane_id, _| {
                self.pane_to_tab.contains_key(pane_id) && !exited_panes.contains(pane_id)
            });
        }
    }

    fn update_agent(&mut self, payload: PipePayload) {
        let entry = self.agents.entry(payload.pane_id).or_insert_with(|| {
            AgentState::new(payload.pane_id, payload.name.clone().unwrap_or_default())
        });
        entry.activity = payload.activity;
        if let Some(name) = payload.name {
            entry.name = name;
        }
        entry.action = payload.action;
        entry.snippet = payload.snippet;
        if let Some((idx, tab_name)) = self.pane_to_tab.get(&payload.pane_id) {
            entry.tab_index = Some(*idx);
            entry.tab_name = Some(tab_name.clone());
        }
    }

    fn merge_agents(&mut self, incoming: BTreeMap<u32, AgentState>) {
        for (pane_id, agent) in incoming {
            self.agents.insert(pane_id, agent);
        }
    }

    fn request_sync(&self) {
        pipe_message_to_plugin(MessageToPlugin::new("agent-handler:request"));
    }

    fn broadcast_agents(&self) {
        let mut msg = MessageToPlugin::new("agent-handler:sync");
        msg.message_payload = Some(serde_json::to_string(&self.agents).unwrap_or_default());
        pipe_message_to_plugin(msg);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use state::{Activity, AgentState, PipePayload};

    fn make_state() -> HandlerState {
        HandlerState::default()
    }

    #[test]
    fn update_agent_inserts_new_agent() {
        let mut state = make_state();
        let payload = PipePayload {
            pane_id: 5,
            activity: Activity::Busy,
            name: Some("agent-1".into()),
        };
        state.update_agent(payload);
        assert_eq!(state.agents.len(), 1);
        let agent = state.agents.get(&5).unwrap();
        assert_eq!(agent.name, "agent-1");
        assert_eq!(agent.activity, Activity::Busy);
    }

    #[test]
    fn update_agent_updates_existing_agent_activity() {
        let mut state = make_state();
        state.agents.insert(5, AgentState::new(5, "agent-1".into()));

        let payload = PipePayload {
            pane_id: 5,
            activity: Activity::Permission,
            name: None,
        };
        state.update_agent(payload);
        assert_eq!(state.agents.get(&5).unwrap().activity, Activity::Permission);
        assert_eq!(state.agents.get(&5).unwrap().name, "agent-1");
    }

    #[test]
    fn update_agent_updates_name_when_provided() {
        let mut state = make_state();
        state
            .agents
            .insert(5, AgentState::new(5, "old-name".into()));

        let payload = PipePayload {
            pane_id: 5,
            activity: Activity::Idle,
            name: Some("new-name".into()),
        };
        state.update_agent(payload);
        assert_eq!(state.agents.get(&5).unwrap().name, "new-name");
    }

    #[test]
    fn merge_agents_adds_unknown_agents() {
        let mut state = make_state();
        state
            .agents
            .insert(1, AgentState::new(1, "existing".into()));

        let mut incoming = BTreeMap::new();
        incoming.insert(2, AgentState::new(2, "new-agent".into()));
        state.merge_agents(incoming);

        assert_eq!(state.agents.len(), 2);
        assert!(state.agents.contains_key(&1));
        assert!(state.agents.contains_key(&2));
    }

    #[test]
    fn merge_agents_overwrites_with_incoming() {
        let mut state = make_state();
        let mut existing = AgentState::new(1, "local".into());
        existing.activity = Activity::Busy;
        state.agents.insert(1, existing);

        let mut incoming = BTreeMap::new();
        let mut remote = AgentState::new(1, "remote".into());
        remote.activity = Activity::Idle;
        incoming.insert(1, remote);
        state.merge_agents(incoming);

        assert_eq!(state.agents.get(&1).unwrap().name, "remote");
        assert_eq!(state.agents.get(&1).unwrap().activity, Activity::Idle);
    }
}
