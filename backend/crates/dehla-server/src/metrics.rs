//! In-process Prometheus-ish text exposition.

use std::sync::atomic::{AtomicU64, Ordering};

use crate::state::AppState;

#[derive(Debug, Default)]
pub struct Metrics {
    pub tips_saved: AtomicU64,
}

impl Metrics {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn render(&self, state: &AppState) -> String {
        let tables = state.games.lock().unwrap().len();
        let ws = state
            .ws_count
            .load(std::sync::atomic::Ordering::Relaxed);
        let tips = self.tips_saved.load(Ordering::Relaxed);

        let mut out = String::with_capacity(256);
        out.push_str("# HELP dehla_tables In-game table actors\n");
        out.push_str("# TYPE dehla_tables gauge\n");
        out.push_str(&format!("dehla_tables {tables}\n"));
        out.push_str("# HELP dehla_ws_connections Active WebSocket connections\n");
        out.push_str("# TYPE dehla_ws_connections gauge\n");
        out.push_str(&format!("dehla_ws_connections {ws}\n"));
        out.push_str("# HELP dehla_tips_saved Tip snapshots persisted successfully\n");
        out.push_str("# TYPE dehla_tips_saved counter\n");
        out.push_str(&format!("dehla_tips_saved {tips}\n"));
        out
    }
}
