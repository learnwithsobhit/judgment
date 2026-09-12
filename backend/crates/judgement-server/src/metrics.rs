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
    pub ws_disconnected_socket_error: AtomicU64,
    pub ws_disconnected_client_close: AtomicU64,
    pub ws_disconnected_liveness: AtomicU64,
    pub ws_disconnected_stream_ended: AtomicU64,
    pub ws_disconnected_actor_closed: AtomicU64,
    pub ws_disconnected_actor_connect_failed: AtomicU64,
    pub ws_stale_disconnects: AtomicU64,
    pub reconnects: AtomicU64,
    pub bot_takeovers: AtomicU64,
    pub seat_vacancies: AtomicU64,
    pub seat_claims: AtomicU64,
    pub games_ended_vacancy: AtomicU64,
    pub games_restarted: AtomicU64,
    pub games_removed: AtomicU64,
    pub games_compacted: AtomicU64,
    pub games_purged: AtomicU64,
    pub games_abandoned: AtomicU64,
    pub invalid_actions: AtomicU64,
    pub db_write_failures: AtomicU64,
    pub ai_requests: AtomicU64,
    pub ai_fallbacks: AtomicU64,
    pub rooms_reaped: AtomicU64,
    /// Persist commit latency histogram helpers (Prometheus-style).
    pub persist_commit_ms_sum: AtomicU64,
    pub persist_commit_ms_count: AtomicU64,
    pub persist_commit_ms_bucket_le_10: AtomicU64,
    pub persist_commit_ms_bucket_le_50: AtomicU64,
    pub persist_commit_ms_bucket_le_100: AtomicU64,
    pub persist_commit_ms_bucket_le_500: AtomicU64,
    pub persist_commit_ms_bucket_le_inf: AtomicU64,
    pub games_admission_rejected: AtomicU64,
    pub capacity_busy: AtomicU64,
    pub capacity_full_rejected: AtomicU64,
    pub outbound_snapshot_drops: AtomicU64,
    pub actors_respawned: AtomicU64,
    pub soundboard_broadcast: AtomicU64,
    pub voice_notes_broadcast: AtomicU64,
    pub audio_rejected: AtomicU64,
    pub forced_auto_play: AtomicU64,
}

impl Metrics {
    /// Record a finished persist attempt (success or failure) in ms.
    pub fn observe_persist_ms(&self, ms: u64) {
        self.persist_commit_ms_sum.fetch_add(ms, Ordering::Relaxed);
        self.persist_commit_ms_count.fetch_add(1, Ordering::Relaxed);
        self.persist_commit_ms_bucket_le_inf
            .fetch_add(1, Ordering::Relaxed);
        if ms <= 10 {
            self.persist_commit_ms_bucket_le_10
                .fetch_add(1, Ordering::Relaxed);
        }
        if ms <= 50 {
            self.persist_commit_ms_bucket_le_50
                .fetch_add(1, Ordering::Relaxed);
        }
        if ms <= 100 {
            self.persist_commit_ms_bucket_le_100
                .fetch_add(1, Ordering::Relaxed);
        }
        if ms <= 500 {
            self.persist_commit_ms_bucket_le_500
                .fetch_add(1, Ordering::Relaxed);
        }
    }

    /// Count a WS disconnect. `reason` is a stable `/metrics` label.
    pub fn record_ws_disconnect(&self, reason: &'static str) {
        self.ws_disconnected.fetch_add(1, Ordering::Relaxed);
        let bucket = match reason {
            "socket_error" => &self.ws_disconnected_socket_error,
            "client_close" => &self.ws_disconnected_client_close,
            "liveness" => &self.ws_disconnected_liveness,
            "stream_ended" => &self.ws_disconnected_stream_ended,
            "actor_closed" => &self.ws_disconnected_actor_closed,
            "actor_connect_failed" => &self.ws_disconnected_actor_connect_failed,
            _ => return,
        };
        bucket.fetch_add(1, Ordering::Relaxed);
    }

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
        counter!(
            "judgement_http_requests_total",
            "HTTP requests that passed the rate limiter",
            http_requests
        );
        counter!(
            "judgement_http_rate_limited_total",
            "HTTP requests rejected by rate limit",
            rate_limited
        );
        counter!(
            "judgement_games_started_total",
            "Games started",
            games_started
        );
        counter!(
            "judgement_games_completed_total",
            "Games completed",
            games_completed
        );
        counter!(
            "judgement_ws_connected_total",
            "WebSocket upgrades accepted",
            ws_connected
        );
        counter!(
            "judgement_ws_disconnected_total",
            "WebSocket disconnects observed",
            ws_disconnected
        );
        counter!(
            "judgement_ws_disconnected_socket_error_total",
            "WS disconnects from socket/TCP reset",
            ws_disconnected_socket_error
        );
        counter!(
            "judgement_ws_disconnected_client_close_total",
            "WS disconnects from client Close frames",
            ws_disconnected_client_close
        );
        counter!(
            "judgement_ws_disconnected_liveness_total",
            "WS disconnects from idle liveness timeout",
            ws_disconnected_liveness
        );
        counter!(
            "judgement_ws_disconnected_stream_ended_total",
            "WS disconnects from read stream end",
            ws_disconnected_stream_ended
        );
        counter!(
            "judgement_ws_disconnected_actor_closed_total",
            "WS disconnects because the game actor closed",
            ws_disconnected_actor_closed
        );
        counter!(
            "judgement_ws_disconnected_actor_connect_failed_total",
            "WS upgrades that failed actor Connect handoff",
            ws_disconnected_actor_connect_failed
        );
        counter!(
            "judgement_ws_stale_disconnects_total",
            "Disconnects ignored because a newer WS already owns the seat",
            ws_stale_disconnects
        );
        counter!(
            "judgement_reconnects_total",
            "Player reconnects that restored control",
            reconnects
        );
        counter!(
            "judgement_bot_takeovers_total",
            "Legacy bot takeovers (unused in live replace-or-end)",
            bot_takeovers
        );
        counter!(
            "judgement_seat_vacancies_total",
            "Seats marked vacant after grace/leave",
            seat_vacancies
        );
        counter!(
            "judgement_seat_claims_total",
            "Vacant seats claimed by a new human",
            seat_claims
        );
        counter!(
            "judgement_games_ended_vacancy_total",
            "Games ended by host or vacancy timeout",
            games_ended_vacancy
        );
        counter!(
            "judgement_games_restarted_total",
            "Games rematched via host restart",
            games_restarted
        );
        counter!(
            "judgement_games_removed_total",
            "Game actors removed from the active map after abort/restart",
            games_removed
        );
        counter!(
            "judgement_games_compacted_total",
            "Finished games compacted (ops/backfill)",
            games_compacted
        );
        counter!(
            "judgement_games_purged_total",
            "Terminal games hard-deleted on finish/abort or reaper backstop",
            games_purged
        );
        counter!(
            "judgement_games_abandoned_total",
            "In-memory abandoned game actors dropped",
            games_abandoned
        );
        counter!(
            "judgement_invalid_actions_total",
            "Rejected game commands",
            invalid_actions
        );
        counter!(
            "judgement_db_write_failures_total",
            "Persist commit failures",
            db_write_failures
        );
        counter!(
            "judgement_ai_requests_total",
            "AI / rules query requests",
            ai_requests
        );
        counter!(
            "judgement_ai_fallbacks_total",
            "AI responses that used deterministic fallback",
            ai_fallbacks
        );
        counter!(
            "judgement_rooms_reaped_total",
            "Abandoned rooms garbage-collected",
            rooms_reaped
        );
        counter!(
            "judgement_games_admission_rejected_total",
            "start_game rejected because emergency MAX_ACTIVE_GAMES cap reached",
            games_admission_rejected
        );
        counter!(
            "judgement_capacity_busy_total",
            "Creates that succeeded while in the busy capacity band",
            capacity_busy
        );
        counter!(
            "judgement_capacity_full_rejected_total",
            "Creates/starts rejected by the product capacity hard gate",
            capacity_full_rejected
        );
        counter!(
            "judgement_outbound_snapshot_drops_total",
            "StateSnapshot try_send drops (client buffer full)",
            outbound_snapshot_drops
        );
        counter!(
            "judgement_actors_respawned_total",
            "Dead game actors respawned from tip snapshot",
            actors_respawned
        );
        counter!(
            "judgement_soundboard_broadcast_total",
            "Curated soundboard clips broadcast to a table",
            soundboard_broadcast
        );
        counter!(
            "judgement_voice_notes_broadcast_total",
            "Ephemeral voice notes broadcast to a table",
            voice_notes_broadcast
        );
        counter!(
            "judgement_audio_rejected_total",
            "Soundboard/voice commands rejected (cooldown, size, mime, allow-list)",
            audio_rejected
        );
        counter!(
            "judgement_forced_auto_play_total",
            "Singleton legal cards auto-played without waiting for a tap",
            forced_auto_play
        );

        out.push_str(
            "# HELP judgement_persist_commit_duration_milliseconds Persist commit latency\n",
        );
        out.push_str("# TYPE judgement_persist_commit_duration_milliseconds histogram\n");
        out.push_str(&format!(
            "judgement_persist_commit_duration_milliseconds_bucket{{le=\"10\"}} {}\n",
            self.persist_commit_ms_bucket_le_10.load(Ordering::Relaxed)
        ));
        out.push_str(&format!(
            "judgement_persist_commit_duration_milliseconds_bucket{{le=\"50\"}} {}\n",
            self.persist_commit_ms_bucket_le_50.load(Ordering::Relaxed)
        ));
        out.push_str(&format!(
            "judgement_persist_commit_duration_milliseconds_bucket{{le=\"100\"}} {}\n",
            self.persist_commit_ms_bucket_le_100.load(Ordering::Relaxed)
        ));
        out.push_str(&format!(
            "judgement_persist_commit_duration_milliseconds_bucket{{le=\"500\"}} {}\n",
            self.persist_commit_ms_bucket_le_500.load(Ordering::Relaxed)
        ));
        out.push_str(&format!(
            "judgement_persist_commit_duration_milliseconds_bucket{{le=\"+Inf\"}} {}\n",
            self.persist_commit_ms_bucket_le_inf.load(Ordering::Relaxed)
        ));
        out.push_str(&format!(
            "judgement_persist_commit_duration_milliseconds_sum {}\n",
            self.persist_commit_ms_sum.load(Ordering::Relaxed)
        ));
        out.push_str(&format!(
            "judgement_persist_commit_duration_milliseconds_count {}\n",
            self.persist_commit_ms_count.load(Ordering::Relaxed)
        ));

        out.push_str("# HELP judgement_active_websockets Approximate active WS connections\n");
        out.push_str("# TYPE judgement_active_websockets gauge\n");
        out.push_str(&format!(
            "judgement_active_websockets {}\n",
            gauges.active_websockets
        ));
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
