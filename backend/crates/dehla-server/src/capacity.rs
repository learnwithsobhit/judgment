//! Product capacity hard gate (see docs/dehla_game_estimation.md).

use std::sync::atomic::Ordering;

use crate::state::AppState;

/// Product hard gate — reject new create / start / ws.
pub const MAX_ACTIVE_TABLES: usize = 40;
/// Product hard gate on connected WebSockets (4 seats × 40).
pub const MAX_ACTIVE_WEBSOCKETS: usize = 160;

pub const CAPACITY_FULL_MESSAGE: &str =
    "Tables are full at the moment. Existing games keep playing — please try again in a few minutes.";

pub fn is_full(state: &AppState) -> bool {
    let tables = state.games.lock().unwrap().len();
    let ws = state.ws_count.load(Ordering::Relaxed);
    tables >= MAX_ACTIVE_TABLES || ws >= MAX_ACTIVE_WEBSOCKETS
}
