//! Public site config and the admin festival switch.

use std::sync::Arc;

use axum::extract::State;
use axum::http::HeaderMap;
use axum::Json;
use judgement_protocol::{festival_id_allowed, PublicConfigResponse, SetFestivalRequest};
use serde_json::json;

use crate::auth::user_is_admin;
use crate::error::ApiError;
use crate::state::AppState;

pub async fn get_public_config(State(state): State<Arc<AppState>>) -> Json<PublicConfigResponse> {
    let festival_id = state.festival_id.lock().unwrap().clone();
    Json(PublicConfigResponse { festival_id })
}

pub async fn set_festival(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<SetFestivalRequest>,
) -> Result<Json<PublicConfigResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user_id = session.user_id.ok_or(ApiError::Unauthorized)?;
    if !user_is_admin(&state, user_id).await? {
        return Err(ApiError::Forbidden("admin only".into()));
    }
    let id = body.id.trim().to_ascii_lowercase();
    if !festival_id_allowed(&id) {
        return Err(ApiError::BadRequest("unknown festival".into()));
    }
    state
        .store
        .upsert_setting("festival", json!({ "id": id }))
        .await
        .map_err(|e| ApiError::Conflict(format!("save festival: {e}")))?;
    *state.festival_id.lock().unwrap() = id.clone();
    Ok(Json(PublicConfigResponse { festival_id: id }))
}
