//! Public free-to-play board. The game actor never reads this table.

use std::sync::Arc;

use axum::extract::State;
use axum::http::HeaderMap;
use axum::Json;
use chrono::{Duration, Utc};
use judgement_persistence::StoredAvailablePlayer;
use judgement_protocol::{AvailabilityPlayer, AvailabilityResponse, SetAvailabilityRequest};

use crate::error::ApiError;
use crate::state::AppState;

const READY_AT: usize = 3;

pub async fn get_availability(
    State(state): State<Arc<AppState>>,
) -> Result<Json<AvailabilityResponse>, ApiError> {
    let players = state
        .store
        .list_available(Utc::now())
        .await
        .map_err(|e| ApiError::Conflict(format!("list availability: {e}")))?;
    Ok(Json(board_from(players)))
}

pub async fn put_my_availability(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<SetAvailabilityRequest>,
) -> Result<Json<AvailabilityResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user_id = session.user_id.ok_or(ApiError::Unauthorized)?;
    if body.available {
        let until = Utc::now() + Duration::minutes(90);
        state
            .store
            .set_availability(user_id, until)
            .await
            .map_err(|e| ApiError::Conflict(format!("set availability: {e}")))?;
    } else {
        state
            .store
            .clear_availability(user_id)
            .await
            .map_err(|e| ApiError::Conflict(format!("clear availability: {e}")))?;
    }
    let players = state
        .store
        .list_available(Utc::now())
        .await
        .map_err(|e| ApiError::Conflict(format!("list availability: {e}")))?;
    Ok(Json(board_from(players)))
}

fn board_from(players: Vec<StoredAvailablePlayer>) -> AvailabilityResponse {
    let count = players.len() as u32;
    AvailabilityResponse {
        count,
        ready: players.len() >= READY_AT,
        players: players.into_iter().map(to_player).collect(),
    }
}

fn to_player(player: StoredAvailablePlayer) -> AvailabilityPlayer {
    AvailabilityPlayer {
        user_id: player.user_id.to_string(),
        display_name: player.display_name,
        avatar_id: player.avatar_id,
        photo_url: player.photo_url,
        available_until: player.available_until,
    }
}
