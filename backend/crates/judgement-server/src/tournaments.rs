//! Points-series tournaments: admin create/manage, public list/detail + standings.

use std::sync::atomic::Ordering;
use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use chrono::Utc;
use judgement_persistence::{StoredTournament, TournamentStatus};
use judgement_protocol::{
    CreateTournamentRequest, LeaderboardEntry, TournamentDetailResponse, TournamentListResponse,
    TournamentSummary, UpdateTournamentRequest,
};
use uuid::Uuid;

use crate::auth::user_is_admin;
use crate::error::ApiError;
use crate::state::AppState;

pub async fn list_tournaments(
    State(state): State<Arc<AppState>>,
) -> Result<Json<TournamentListResponse>, ApiError> {
    state
        .metrics
        .tournament_standings_reads
        .fetch_add(1, Ordering::Relaxed);
    let stored = state
        .store
        .list_tournaments()
        .await
        .map_err(|e| ApiError::Conflict(format!("list tournaments: {e}")))?;
    let mut tournaments = Vec::with_capacity(stored.len());
    for t in stored {
        // Public list: live first (store order), then recent closed. Hide drafts.
        if t.status == TournamentStatus::Draft {
            continue;
        }
        tournaments.push(summary_for(&state, &t).await?);
    }
    Ok(Json(TournamentListResponse { tournaments }))
}

pub async fn get_tournament(
    State(state): State<Arc<AppState>>,
    Path(id_or_slug): Path<String>,
) -> Result<Json<TournamentDetailResponse>, ApiError> {
    state
        .metrics
        .tournament_standings_reads
        .fetch_add(1, Ordering::Relaxed);
    let tournament = state
        .store
        .load_tournament(&id_or_slug)
        .await
        .map_err(|e| ApiError::Conflict(format!("load tournament: {e}")))?
        .ok_or(ApiError::NotFound("tournament"))?;
    if tournament.status == TournamentStatus::Draft {
        return Err(ApiError::NotFound("tournament"));
    }
    let players = standings_entries(&state, tournament.tournament_id, 50).await?;
    Ok(Json(TournamentDetailResponse {
        tournament: summary_for(&state, &tournament).await?,
        players,
    }))
}

pub async fn create_tournament(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<CreateTournamentRequest>,
) -> Result<Json<TournamentSummary>, ApiError> {
    let user_id = require_admin(&state, &headers).await?;
    let title = body.title.trim().to_string();
    if title.is_empty() || title.len() > 80 {
        return Err(ApiError::BadRequest("title must be 1–80 characters".into()));
    }
    let blurb = body.blurb.trim().to_string();
    if blurb.len() > 280 {
        return Err(ApiError::BadRequest("blurb too long".into()));
    }
    let Some(starts_at) = body.starts_at else {
        return Err(ApiError::BadRequest(
            "starts_at is required so same-named events stay distinct".into(),
        ));
    };
    let status = match body.status.as_deref() {
        None | Some("draft") => TournamentStatus::Draft,
        Some("live") => TournamentStatus::Live,
        Some(_) => return Err(ApiError::BadRequest("status must be draft or live".into())),
    };
    let now = Utc::now();
    let tournament_id = Uuid::new_v4();
    let slug = unique_slug(&state, &title, tournament_id).await?;
    let stored = StoredTournament {
        tournament_id,
        slug,
        title,
        blurb,
        format: "points".into(),
        status,
        starts_at: Some(starts_at),
        ends_at: body.ends_at,
        created_by: Some(user_id),
        created_at: now,
        updated_at: now,
    };
    state
        .store
        .upsert_tournament(&stored)
        .await
        .map_err(|e| ApiError::Conflict(format!("save tournament: {e}")))?;
    state
        .metrics
        .tournament_creates
        .fetch_add(1, Ordering::Relaxed);
    Ok(Json(summary_for(&state, &stored).await?))
}

pub async fn update_tournament(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id_or_slug): Path<String>,
    Json(body): Json<UpdateTournamentRequest>,
) -> Result<Json<TournamentSummary>, ApiError> {
    let _user_id = require_admin(&state, &headers).await?;
    let mut stored = state
        .store
        .load_tournament(&id_or_slug)
        .await
        .map_err(|e| ApiError::Conflict(format!("load tournament: {e}")))?
        .ok_or(ApiError::NotFound("tournament"))?;

    if let Some(title) = body.title {
        let title = title.trim().to_string();
        if title.is_empty() || title.len() > 80 {
            return Err(ApiError::BadRequest("title must be 1–80 characters".into()));
        }
        stored.title = title;
    }
    if let Some(blurb) = body.blurb {
        let blurb = blurb.trim().to_string();
        if blurb.len() > 280 {
            return Err(ApiError::BadRequest("blurb too long".into()));
        }
        stored.blurb = blurb;
    }
    if body.starts_at.is_some() {
        stored.starts_at = body.starts_at;
    }
    if body.ends_at.is_some() {
        stored.ends_at = body.ends_at;
    }
    if let Some(raw) = body.status.as_deref() {
        let next = TournamentStatus::parse(raw)
            .ok_or_else(|| ApiError::BadRequest("status must be draft, live, or closed".into()))?;
        validate_status_transition(stored.status, next)?;
        stored.status = next;
    }
    stored.updated_at = Utc::now();
    state
        .store
        .upsert_tournament(&stored)
        .await
        .map_err(|e| ApiError::Conflict(format!("save tournament: {e}")))?;
    Ok(Json(summary_for(&state, &stored).await?))
}

/// Admin manage peek: includes drafts.
pub async fn admin_get_tournament(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id_or_slug): Path<String>,
) -> Result<Json<TournamentDetailResponse>, ApiError> {
    let _user_id = require_admin(&state, &headers).await?;
    let tournament = state
        .store
        .load_tournament(&id_or_slug)
        .await
        .map_err(|e| ApiError::Conflict(format!("load tournament: {e}")))?
        .ok_or(ApiError::NotFound("tournament"))?;
    let mut summary = summary_for(&state, &tournament).await?;
    summary.live_attached_rooms = Some(count_live_attached(&state, tournament.tournament_id));
    let players = standings_entries(&state, tournament.tournament_id, 5).await?;
    Ok(Json(TournamentDetailResponse {
        tournament: summary,
        players,
    }))
}

pub async fn admin_list_tournaments(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<TournamentListResponse>, ApiError> {
    let _user_id = require_admin(&state, &headers).await?;
    let stored = state
        .store
        .list_tournaments()
        .await
        .map_err(|e| ApiError::Conflict(format!("list tournaments: {e}")))?;
    let mut tournaments = Vec::with_capacity(stored.len());
    for t in stored {
        let mut summary = summary_for(&state, &t).await?;
        summary.live_attached_rooms = Some(count_live_attached(&state, t.tournament_id));
        tournaments.push(summary);
    }
    Ok(Json(TournamentListResponse { tournaments }))
}

/// Admin-only hard delete for old/test events. Standings stamp clears via FK SET NULL.
pub async fn delete_tournament(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id_or_slug): Path<String>,
) -> Result<StatusCode, ApiError> {
    let _user_id = require_admin(&state, &headers).await?;
    let tournament = state
        .store
        .load_tournament(&id_or_slug)
        .await
        .map_err(|e| ApiError::Conflict(format!("load tournament: {e}")))?
        .ok_or(ApiError::NotFound("tournament"))?;
    let removed = state
        .store
        .delete_tournament(tournament.tournament_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("delete tournament: {e}")))?;
    if !removed {
        return Err(ApiError::NotFound("tournament"));
    }
    // Drop attach marks from live lobbies in this process.
    {
        let mut rooms = state.rooms.lock().unwrap();
        for room in rooms.values_mut() {
            if room.tournament_id == Some(tournament.tournament_id) {
                room.tournament_id = None;
            }
        }
    }
    tracing::info!(
        tournament_id = %tournament.tournament_id,
        slug = %tournament.slug,
        "admin deleted tournament"
    );
    Ok(StatusCode::NO_CONTENT)
}

async fn require_admin(state: &AppState, headers: &HeaderMap) -> Result<Uuid, ApiError> {
    let session = state.authenticate(headers)?;
    let user_id = session.user_id.ok_or(ApiError::Unauthorized)?;
    if !user_is_admin(state, user_id).await? {
        return Err(ApiError::Forbidden("admin only".into()));
    }
    Ok(user_id)
}

fn validate_status_transition(from: TournamentStatus, to: TournamentStatus) -> Result<(), ApiError> {
    if from == to {
        return Ok(());
    }
    match (from, to) {
        (TournamentStatus::Draft, TournamentStatus::Live)
        | (TournamentStatus::Draft, TournamentStatus::Closed)
        | (TournamentStatus::Live, TournamentStatus::Closed)
        | (TournamentStatus::Closed, TournamentStatus::Live) => Ok(()),
        _ => Err(ApiError::BadRequest(format!(
            "cannot move tournament from {} to {}",
            from.as_str(),
            to.as_str()
        ))),
    }
}

async fn summary_for(
    state: &AppState,
    tournament: &StoredTournament,
) -> Result<TournamentSummary, ApiError> {
    let finished_tables = state
        .store
        .count_tournament_tables(tournament.tournament_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("count tables: {e}")))?;
    Ok(TournamentSummary {
        tournament_id: tournament.tournament_id.to_string(),
        slug: tournament.slug.clone(),
        title: tournament.title.clone(),
        blurb: tournament.blurb.clone(),
        format: tournament.format.clone(),
        status: tournament.status.as_str().to_string(),
        starts_at: tournament.starts_at,
        ends_at: tournament.ends_at,
        finished_tables,
        live_attached_rooms: None,
    })
}

async fn standings_entries(
    state: &AppState,
    tournament_id: Uuid,
    limit: i64,
) -> Result<Vec<LeaderboardEntry>, ApiError> {
    let rows = state
        .store
        .load_tournament_standings(tournament_id, limit)
        .await
        .map_err(|e| ApiError::Conflict(format!("standings: {e}")))?;
    Ok(rows
        .into_iter()
        .enumerate()
        .map(|(index, row)| LeaderboardEntry {
            rank: index as i32 + 1,
            display_name: row.display_name,
            avatar_id: row.avatar_id,
            photo_url: row.photo_url,
            wins: row.wins,
            games: row.games,
            exact_percent: row.exact_percent,
            average_score: row.average_score,
            gold: row.gold,
            silver: row.silver,
            bronze: row.bronze,
            medal_points: row.medal_points,
            exact: row.exact,
            rounds: row.rounds,
        })
        .collect())
}

fn count_live_attached(state: &AppState, tournament_id: Uuid) -> i64 {
    state
        .rooms
        .lock()
        .unwrap()
        .values()
        .filter(|room| room.tournament_id == Some(tournament_id))
        .count() as i64
}

async fn unique_slug(
    state: &AppState,
    title: &str,
    tournament_id: Uuid,
) -> Result<String, ApiError> {
    let base = slugify(title);
    let base = if base.is_empty() {
        format!("event-{}", &tournament_id.to_string()[..8])
    } else {
        base
    };
    let candidates = [
        base.clone(),
        format!("{base}-{}", &tournament_id.to_string()[..6]),
    ];
    for candidate in candidates {
        if state
            .store
            .load_tournament(&candidate)
            .await
            .map_err(|e| ApiError::Conflict(format!("slug check: {e}")))?
            .is_none()
        {
            return Ok(candidate);
        }
    }
    Ok(format!("{base}-{}", tournament_id))
}

fn slugify(raw: &str) -> String {
    let mut out = String::new();
    let mut dash = false;
    for ch in raw.chars().flat_map(|c| c.to_lowercase()) {
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
            dash = false;
        } else if !dash && !out.is_empty() {
            out.push('-');
            dash = true;
        }
    }
    while out.ends_with('-') {
        out.pop();
    }
    out.truncate(48);
    out
}
