//! Product capacity tiers for concurrent games (protect in-progress tables).

use std::sync::OnceLock;

use crate::state::AppState;

/// Soft band start — create still allowed with a busy notice.
pub const DEFAULT_COMFORT_ACTIVE_GAMES: usize = 25;
/// Product hard gate — reject new create / start / restart.
pub const DEFAULT_HARD_ACTIVE_GAMES: usize = 35;
/// Product hard gate on connected WebSockets (WS/RAM comfort).
pub const DEFAULT_HARD_ACTIVE_WEBSOCKETS: u64 = 200;

pub const CAPACITY_FULL_MESSAGE: &str =
    "Tables are full at the moment. Existing games keep playing — please try again in a few minutes.";

pub const CAPACITY_BUSY_MESSAGE: &str =
    "Lots of games are in progress right now. You can still make a room — starting may take a moment.";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CapacityLevel {
    Comfort,
    Busy,
    Full,
}

impl CapacityLevel {
    pub fn as_str(self) -> &'static str {
        match self {
            CapacityLevel::Comfort => "comfort",
            CapacityLevel::Busy => "busy",
            CapacityLevel::Full => "full",
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct CapacityThresholds {
    pub comfort_active_games: usize,
    pub hard_active_games: usize,
    pub hard_active_websockets: u64,
}

impl CapacityThresholds {
    pub fn from_env() -> Self {
        Self {
            comfort_active_games: env_usize(
                "JUDGEMENT_COMFORT_ACTIVE_GAMES",
                DEFAULT_COMFORT_ACTIVE_GAMES,
            ),
            hard_active_games: env_usize("JUDGEMENT_HARD_ACTIVE_GAMES", DEFAULT_HARD_ACTIVE_GAMES),
            hard_active_websockets: env_u64(
                "JUDGEMENT_HARD_ACTIVE_WEBSOCKETS",
                DEFAULT_HARD_ACTIVE_WEBSOCKETS,
            ),
        }
    }
}

fn env_usize(key: &str, default: usize) -> usize {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn env_u64(key: &str, default: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

static THRESHOLDS: OnceLock<CapacityThresholds> = OnceLock::new();

pub fn thresholds() -> CapacityThresholds {
    *THRESHOLDS.get_or_init(CapacityThresholds::from_env)
}

/// Resolve capacity from live actor count and WebSocket gauge.
pub fn level(active_games: usize, active_websockets: u64) -> CapacityLevel {
    let t = thresholds();
    if active_games >= t.hard_active_games || active_websockets >= t.hard_active_websockets {
        CapacityLevel::Full
    } else if active_games >= t.comfort_active_games {
        CapacityLevel::Busy
    } else {
        CapacityLevel::Comfort
    }
}

pub fn level_for(state: &AppState) -> CapacityLevel {
    let active_games = state.games.lock().unwrap().len();
    let active_websockets = state
        .active_websockets
        .load(std::sync::atomic::Ordering::Relaxed);
    level(active_games, active_websockets)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tiers_by_games() {
        assert_eq!(level(0, 0), CapacityLevel::Comfort);
        assert_eq!(level(24, 0), CapacityLevel::Comfort);
        assert_eq!(level(25, 0), CapacityLevel::Busy);
        assert_eq!(level(34, 100), CapacityLevel::Busy);
        assert_eq!(level(35, 0), CapacityLevel::Full);
    }

    #[test]
    fn tiers_by_websockets() {
        assert_eq!(level(10, 199), CapacityLevel::Comfort);
        assert_eq!(level(10, 200), CapacityLevel::Full);
    }
}
