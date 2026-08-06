//! Dehla Pakad HTTP + WebSocket server (ADR 0006).

mod actor;
mod capacity;
mod cors;
mod error;
mod metrics;
mod routes;
mod state;
mod ws;

use std::sync::Arc;

use axum::routing::{get, post};
use axum::{Json, Router};
use dehla_protocol::HealthResponse;

pub use state::AppState;

pub fn build_router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .route("/metrics", get(metrics_endpoint))
        .route("/api/v1/guest-sessions", post(routes::create_guest_session))
        .route("/api/v1/rooms", post(routes::create_room))
        .route("/api/v1/rooms/{room_ref}", get(routes::get_room))
        .route("/api/v1/rooms/{room_ref}/join", post(routes::join_room))
        .route(
            "/api/v1/rooms/{room_ref}/partnership",
            post(routes::set_partnership),
        )
        .route("/api/v1/rooms/{room_ref}/ready", post(routes::ready))
        .route("/api/v1/rooms/{room_ref}/start", post(routes::start_game_route))
        .route("/api/v1/rooms/{room_ref}/leave", post(routes::leave_room))
        .route("/api/v1/rooms/{room_ref}/claim", post(routes::claim_seat))
        .route("/api/v1/rooms/{room_ref}/end", post(routes::end_game))
        .route("/api/v1/rooms/{room_ref}/restart", post(routes::restart_game))
        .route("/api/v1/games/{game_id}/ws", get(ws::ws_upgrade))
        .layer(cors::cors_layer_from_env())
        .with_state(state)
}

async fn healthz() -> Json<HealthResponse> {
    Json(HealthResponse::ok())
}

async fn readyz(
    axum::extract::State(state): axum::extract::State<Arc<AppState>>,
) -> Result<Json<HealthResponse>, axum::http::StatusCode> {
    state
        .store
        .ping()
        .await
        .map_err(|_| axum::http::StatusCode::SERVICE_UNAVAILABLE)?;
    Ok(Json(HealthResponse::ok()))
}

async fn metrics_endpoint(
    axum::extract::State(state): axum::extract::State<Arc<AppState>>,
) -> String {
    state.metrics.render(&state)
}
