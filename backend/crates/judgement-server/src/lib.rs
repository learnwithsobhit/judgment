//! Axum room service and per-game actors (PLAN.md Phase 3 + Phase 5 + Phase 9).

pub mod actor;
pub mod cors;
pub mod emotes;
pub mod error;
pub mod events;
pub mod http_limit;
pub mod metrics;
pub mod persist;
pub mod rag_boot;
pub mod reaper;
pub mod restore;
pub mod routes;
pub mod state;
pub mod ws;

use std::sync::Arc;

use axum::extract::State;
use axum::http::StatusCode;
use axum::middleware;
use axum::routing::{any, get, post};
use axum::Router;

use crate::cors::cors_layer_from_env;
use crate::http_limit::rate_limit_middleware;
use crate::metrics::Gauges;
use crate::state::AppState;

pub fn build_router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .route("/metrics", get(metrics_endpoint))
        .route("/api/v1/guest-sessions", post(routes::create_guest_session))
        .route("/api/v1/me/avatar", post(routes::set_avatar))
        .route("/api/v1/rooms", post(routes::create_room))
        .route("/api/v1/rooms/{room_ref}", get(routes::get_room))
        .route("/api/v1/rooms/{room_ref}/join", post(routes::join_room))
        .route("/api/v1/rooms/{room_ref}/claim", post(routes::claim_seat))
        .route("/api/v1/rooms/{room_ref}/end", post(routes::end_game))
        .route("/api/v1/rooms/{room_ref}/leave", post(routes::leave_room))
        .route(
            "/api/v1/rooms/{room_ref}/remove-player",
            post(routes::remove_player),
        )
        .route("/api/v1/rooms/{room_ref}/ready", post(routes::set_ready))
        .route("/api/v1/rooms/{room_ref}/start", post(routes::start_game))
        .route("/api/v1/events", post(events::create_event))
        .route("/api/v1/events/{slug}", get(events::get_event))
        .route("/api/v1/events/{slug}/rsvps", post(events::create_rsvp))
        .route(
            "/api/v1/events/{slug}/rsvps/me",
            post(events::cancel_rsvp),
        )
        .route("/api/v1/events/{slug}/manage", get(events::manage_event))
        .route("/api/v1/events/{slug}/open-lobby", post(events::open_lobby))
        .route("/api/v1/events/{slug}/cancel", post(events::cancel_event))
        .route(
            "/api/v1/events/{slug}/calendar.ics",
            get(events::calendar_ics),
        )
        .route("/api/v1/games/{game_id}/history", get(routes::get_game_history))
        .route("/api/v1/games/{game_id}/result", get(routes::get_game_result))
        .route("/api/v1/games/{game_id}/coach/{player_id}", get(routes::get_game_coach))
        .route("/api/v1/games/{game_id}/highlights", get(routes::get_game_highlights))
        .route(
            "/api/v1/games/{game_id}/rounds/{round_index}/summary",
            get(routes::get_round_summary),
        )
        .route("/api/v1/ai/rules/query", post(routes::ai_rules_query))
        .route("/api/v1/games/{game_id}/ws", any(ws::game_ws))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            rate_limit_middleware,
        ))
        .layer(tower_http::trace::TraceLayer::new_for_http())
        .layer(cors_layer_from_env())
        .with_state(state)
}

async fn healthz() -> &'static str {
    "ok"
}

async fn readyz(State(state): State<Arc<AppState>>) -> Result<&'static str, StatusCode> {
    state.store.ping().await.map_err(|err| {
        tracing::error!(error = %err, "readyz ping failed");
        StatusCode::SERVICE_UNAVAILABLE
    })?;
    Ok("ready")
}

async fn metrics_endpoint(State(state): State<Arc<AppState>>) -> String {
    let gauges = Gauges {
        active_websockets: state
            .active_websockets
            .load(std::sync::atomic::Ordering::Relaxed),
        active_rooms: state.rooms.lock().unwrap().len() as u64,
        active_game_actors: state.games.lock().unwrap().len() as u64,
    };
    state.metrics.render_prometheus(gauges)
}
