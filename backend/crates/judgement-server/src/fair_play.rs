//! Post-game fair play votes (REST). Ballots stay private.

use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use judgement_persistence::{
    fair_play::{average_points, fair_play_enabled, validate_ratings, vote_window_open},
    FairPlayRating,
};
use judgement_protocol::{
    FairPlayGameView, FairPlayLeaderboardEntry, FairPlayLeaderboardResponse, FairPlayRatee,
    FairPlaySubmitRequest, FairPlayTotal,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct FairPlayBoardQuery {
    pub limit: Option<i64>,
}

pub async fn get_fair_play_game(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(game_id): Path<Uuid>,
) -> Result<Json<FairPlayGameView>, ApiError> {
    if !fair_play_enabled() {
        return Err(ApiError::BadRequest("fair play is off".into()));
    }
    let session = state.authenticate(&headers)?;
    let voter = session.user_id.ok_or_else(|| ApiError::Unauthorized)?;
    let roster = state
        .store
        .load_fair_play_roster(game_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("fair play: {e}")))?;
    let Some(mine) = roster.iter().find(|s| s.user_id == voter) else {
        return Err(ApiError::Forbidden("you were not at this table".into()));
    };
    let window_open = vote_window_open(mine.finished_at, Utc::now());
    let already = state
        .store
        .fair_play_already_submitted(game_id, voter)
        .await
        .map_err(|e| ApiError::Conflict(format!("fair play: {e}")))?;
    let ratees: Vec<_> = roster
        .iter()
        .filter(|s| s.user_id != voter)
        .map(|s| FairPlayRatee {
            user_id: s.user_id.to_string(),
            display_name: s.display_name.clone(),
            avatar_id: s.avatar_id.clone(),
            photo_url: s.photo_url.clone(),
        })
        .collect();
    let can_vote = window_open && !already && !ratees.is_empty();
    let totals = if already {
        Some(load_totals(&state, game_id).await?)
    } else {
        None
    };
    Ok(Json(FairPlayGameView {
        can_vote,
        already_submitted: already,
        ratees,
        totals,
    }))
}

pub async fn submit_fair_play_game(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(game_id): Path<Uuid>,
    Json(body): Json<FairPlaySubmitRequest>,
) -> Result<Json<FairPlayGameView>, ApiError> {
    if !fair_play_enabled() {
        return Err(ApiError::BadRequest("fair play is off".into()));
    }
    let session = state.authenticate(&headers)?;
    let voter = session.user_id.ok_or_else(|| ApiError::Unauthorized)?;
    let roster = state
        .store
        .load_fair_play_roster(game_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("fair play: {e}")))?;
    let Some(mine) = roster.iter().find(|s| s.user_id == voter) else {
        return Err(ApiError::Forbidden("you were not at this table".into()));
    };
    if !vote_window_open(mine.finished_at, Utc::now()) {
        return Err(ApiError::BadRequest("voting window closed".into()));
    }
    let mut ratings = Vec::with_capacity(body.ratings.len());
    for r in &body.ratings {
        let target = Uuid::parse_str(&r.user_id)
            .map_err(|_| ApiError::BadRequest("invalid user_id".into()))?;
        ratings.push(FairPlayRating {
            target_user_id: target,
            points: r.points,
        });
    }
    validate_ratings(voter, &roster, &ratings).map_err(|msg| ApiError::BadRequest(msg.into()))?;
    let totals = state
        .store
        .submit_fair_play(game_id, voter, &ratings)
        .await
        .map_err(|e| match e {
            judgement_persistence::PersistError::Conflict(msg) => ApiError::Conflict(msg),
            other => ApiError::Conflict(format!("fair play: {other}")),
        })?;
    let ratees: Vec<_> = roster
        .iter()
        .filter(|s| s.user_id != voter)
        .map(|s| FairPlayRatee {
            user_id: s.user_id.to_string(),
            display_name: s.display_name.clone(),
            avatar_id: s.avatar_id.clone(),
            photo_url: s.photo_url.clone(),
        })
        .collect();
    Ok(Json(FairPlayGameView {
        can_vote: false,
        already_submitted: true,
        ratees,
        totals: Some(
            totals
                .into_iter()
                .map(|t| FairPlayTotal {
                    user_id: t.user_id.to_string(),
                    display_name: t.display_name,
                    avatar_id: t.avatar_id,
                    photo_url: t.photo_url,
                    points: t.points,
                    ratings: t.ratings,
                })
                .collect(),
        ),
    }))
}

pub async fn get_fair_play_leaderboard(
    State(state): State<Arc<AppState>>,
    Query(query): Query<FairPlayBoardQuery>,
) -> Result<Json<FairPlayLeaderboardResponse>, ApiError> {
    if !fair_play_enabled() {
        return Ok(Json(FairPlayLeaderboardResponse { players: vec![] }));
    }
    let limit = query.limit.unwrap_or(100).clamp(1, 10_000);
    let rows = state
        .store
        .load_fair_play_leaderboard(limit)
        .await
        .map_err(|e| ApiError::Conflict(format!("fair play board: {e}")))?;
    let players = rows
        .into_iter()
        .enumerate()
        .map(|(index, row)| FairPlayLeaderboardEntry {
            rank: index as i32 + 1,
            display_name: row.display_name,
            avatar_id: row.avatar_id,
            photo_url: row.photo_url,
            points_received: row.points_received,
            ratings_received: row.ratings_received,
            games_rated: row.games_rated,
            average: (average_points(row.points_received, row.ratings_received) * 10.0).round()
                / 10.0,
        })
        .collect();
    Ok(Json(FairPlayLeaderboardResponse { players }))
}

async fn load_totals(state: &AppState, game_id: Uuid) -> Result<Vec<FairPlayTotal>, ApiError> {
    let totals = state
        .store
        .load_fair_play_game_totals(game_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("fair play: {e}")))?;
    Ok(totals
        .into_iter()
        .map(|t| FairPlayTotal {
            user_id: t.user_id.to_string(),
            display_name: t.display_name,
            avatar_id: t.avatar_id,
            photo_url: t.photo_url,
            points: t.points,
            ratings: t.ratings,
        })
        .collect())
}
