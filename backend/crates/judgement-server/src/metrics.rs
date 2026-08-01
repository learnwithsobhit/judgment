//! In-process Prometheus text exposition (PLAN.md §22 / Phase 9).

use std::sync::atomic::{AtomicU64, Ordering};

/// Process-wide counters. No third-party Prometheus client required.
#[derive(Debug, Default)]
pub struct Metrics {
    pub http_requests: AtomicU64,
    pub rate_limited: AtomicU64,
    pub games_started: AtomicU64,
    pub games_completed: AtomicU64,
    pub ws_connected: AtomicU64,
    pub ws_disconnected: AtomicU64,
    pub reconnects: AtomicU64,
    pub bot_takeovers: AtomicU64,
    pub seat_vacancies: AtomicU64,
    pub seat_claims: AtomicU64,
    pub games_ended_vacancy: AtomicU64,
    pub games_compacted: AtomicU64,
    pub games_purged: AtomicU64,
    pub games_abandoned: AtomicU64,
    pub invalid_actions: AtomicU64,
    pub db_write_failures: AtomicU64,
    pub ai_requests: AtomicU64,
    pub ai_fallbacks: AtomicU64,
    pub rooms_reaped: AtomicU64,
}

impl Metrics {
    pub fn render_prometheus(&self, gauges: Gauges) -> String {
        let mut out = String::with_capacity(2048);
        macro_rules! counter {
            ($name:literal, $help:literal, $field:ident) => {
                out.push_str(concat!("# HELP ", $name, " ", $help, "\n"));
                out.push_str(concat!("# TYPE ", $name, " counter\n"));
                out.push_str(&format!(
                    "{} {}\n",
                    $name,
                    self.$field.load(Ordering::Relaxed)
                ));
            };
        }
        counter!("judgement_http_requests_total", "HTTP requests that passed the rate limiter", http_requests);
        counter!("judgement_http_rate_limited_total", "HTTP requests rejected by rate limit", rate_limited);
        counter!("judgement_games_started_total", "Games started", games_started);
        counter!("judgement_games_completed_total", "Games completed", games_completed);
        counter!("judgement_ws_connected_total", "WebSocket upgrades accepted", ws_connected);
        counter!("judgement_ws_disconnected_total", "WebSocket disconnects observed", ws_disconnected);
        counter!("judgement_reconnects_total", "Player reconnects that restored control", reconnects);
        counter!("judgement_bot_takeovers_total", "Legacy bot takeovers (unused in live replace-or-end)", bot_takeovers);
        counter!("judgement_seat_vacancies_total", "Seats marked vacant after grace/leave", seat_vacancies);
        counter!("judgement_seat_claims_total", "Vacant seats claimed by a new human", seat_claims);
        counter!("judgement_games_ended_vacancy_total", "Games ended by host or vacancy timeout", games_ended_vacancy);
        counter!("judgement_games_compacted_total", "Finished games compacted (events pruned)", games_compacted);
        counter!("judgement_games_purged_total", "Terminal games hard-deleted by TTL", games_purged);
        counter!("judgement_games_abandoned_total", "In-memory abandoned game actors dropped", games_abandoned);
        counter!("judgement_invalid_actions_total", "Rejected game commands", invalid_actions);
        counter!("judgement_db_write_failures_total", "Persist commit failures", db_write_failures);
        counter!("judgement_ai_requests_total", "AI / rules query requests", ai_requests);
        counter!("judgement_ai_fallbacks_total", "AI responses that used deterministic fallback", ai_fallbacks);
        counter!("judgement_rooms_reaped_total", "Abandoned rooms garbage-collected", rooms_reaped);

        out.push_str("# HELP judgement_active_websockets Approximate active WS connections\n");
        out.push_str("# TYPE judgement_active_websockets gauge\n");
        out.push_str(&format!("judgement_active_websockets {}\n", gauges.active_websockets));
        out.push_str("# HELP judgement_active_rooms Lobby + in-game rooms\n");
        out.push_str("# TYPE judgement_active_rooms gauge\n");
        out.push_str(&format!("judgement_active_rooms {}\n", gauges.active_rooms));
        out.push_str("# HELP judgement_active_game_actors Running game actors\n");
        out.push_str("# TYPE judgement_active_game_actors gauge\n");
        out.push_str(&format!(
            "judgement_active_game_actors {}\n",
            gauges.active_game_actors
        ));
        out
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub struct Gauges {
    pub active_websockets: u64,
    pub active_rooms: u64,
    pub active_game_actors: u64,
}
