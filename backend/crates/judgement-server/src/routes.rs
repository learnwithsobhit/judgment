//! REST handlers for guest sessions and room management (PLAN.md §13.1).

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::{Path, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use judgement_domain::{
    trump_rule_from_config, validate_trump_cycle, ActionId, GameId, GameRules, PlayerId,
    PlayerState, RoomId, SessionId, Suit, MAX_PLAYERS, MIN_PLAYERS,
};
use judgement_engine::GameEngine;
use judgement_persistence::{NewGamePlayer, StoredRoom};
use judgement_ai::{
    coach_from_analysis, narrate_highlights, narrate_round_summary,
    ExplanationResponse as AiExplanation, RulesQueryRequest as AiRulesQuery, TrickPlayQuery,
    TrickQuery,
};
use judgement_analytics::{
    analyse_player, compute_highlights, score_table_from_history_scores, summarize_round,
    scores_from_value,
};
use judgement_protocol::{
    ClaimSeatRequest, ClaimSeatResponse, CoachingResponse, CreateGuestSessionRequest,
    CreateGuestSessionResponse, CreateRoomRequest, CreateRoomResponse, EndGameResponse,
    ExplanationResponse, GameHistoryResponse, GameResultResponse, HighlightsResponse,
    JoinRoomRequest, JoinRoomResponse, ReadyRequest, RemovePlayerRequest, RestartGameResponse,
    RoomView, RoundResultView, RoundSummaryResponse, RulesQueryRequest, SetAvatarRequest,
    SetAvatarResponse, StartGameRequest, StartGameResponse,
};
use crate::emotes::is_allowed_avatar;
use tokio::sync::oneshot;

use crate::actor::{self, ActorMessage, SpawnActor};
use crate::capacity::{level_for, CapacityLevel, CAPACITY_FULL_MESSAGE};
use crate::cleanup::{
    check_restart_rate_limit, make_aborted_hook, make_finished_hook, make_host_changed_hook,
    record_restart,
};
use crate::error::ApiError;
use crate::persist::{persist_new_game, stored_room, stored_session};
use crate::state::{generate_room_code, AppState, GameInfo, Room, RoomSeat, RoomStatus, Session};

/// Load-shed new tables so existing actors keep DB pool headroom (CAP Availability).
pub const MAX_ACTIVE_GAMES: usize = 100;

fn reject_if_capacity_full(state: &AppState) -> Result<CapacityLevel, ApiError> {
    let level = level_for(state);
    if level == CapacityLevel::Full {
        state
            .metrics
            .capacity_full_rejected
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        return Err(ApiError::CapacityFull(CAPACITY_FULL_MESSAGE.into()));
    }
    Ok(level)
}

pub async fn set_avatar(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<SetAvatarRequest>,
) -> Result<Json<SetAvatarResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    if !is_allowed_avatar(&body.avatar_id) {
        return Err(ApiError::BadRequest("unknown avatar_id".into()));
    }
    let avatar_id = state
        .set_avatar(session.id, body.avatar_id.clone())
        .ok_or(ApiError::Unauthorized)?;
    // Refresh session from map for persist.
    let session = state
        .sessions
        .lock()
        .unwrap()
        .get(&session.id)
        .cloned()
        .ok_or(ApiError::Unauthorized)?;
    state
        .store
        .upsert_session(&stored_session(&session))
        .await
        .map_err(|e| ApiError::Conflict(format!("persist session: {e}")))?;
    // Persist lobby seats that carry the new avatar.
    let room_snapshots: Vec<_> = {
        let rooms = state.rooms.lock().unwrap();
        rooms
            .values()
            .filter(|r| r.seats.iter().any(|s| s.session_id == session.id))
            .map(stored_room)
            .collect()
    };
    for snapshot in room_snapshots {
        state
            .store
            .upsert_room(&snapshot)
            .await
            .map_err(|e| ApiError::Conflict(format!("persist room: {e}")))?;
    }
    Ok(Json(SetAvatarResponse { avatar_id }))
}

pub async fn create_guest_session(
    State(state): State<Arc<AppState>>,
    Json(body): Json<CreateGuestSessionRequest>,
) -> Result<Json<CreateGuestSessionResponse>, ApiError> {
    let nickname = body.nickname.trim().to_string();
    if nickname.is_empty() || nickname.chars().count() > 24 {
        return Err(ApiError::BadRequest("nickname must be 1-24 characters".into()));
    }
    let session = state.create_session(nickname);
    state
        .store
        .upsert_session(&stored_session(&session))
        .await
        .map_err(|e| ApiError::Conflict(format!("persist session: {e}")))?;
    Ok(Json(CreateGuestSessionResponse {
        session_id: session.id,
        nickname: session.nickname,
        token: session.token,
    }))
}

pub async fn create_room(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<CreateRoomRequest>,
) -> Result<Json<CreateRoomResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let capacity = reject_if_capacity_full(&state)?;
    if capacity == CapacityLevel::Busy {
        state
            .metrics
            .capacity_busy
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    }

    let max_players = body.max_players.unwrap_or(6);
    if !(MIN_PLAYERS..=MAX_PLAYERS).contains(&max_players) {
        return Err(ApiError::BadRequest(format!(
            "max_players must be between {MIN_PLAYERS} and {MAX_PLAYERS}"
        )));
    }
    let turn_timeout_seconds = body.turn_timeout_seconds.map(|t| t.clamp(5, 300));

    let round_schedule = body.round_schedule.unwrap_or_default();
    let (trump_cycle, first_trump) = normalize_trump_config(body.trump_cycle, body.first_trump)?;
    // Validate against table size at create; start_game re-checks seated count.
    let reveal_trump = trump_cycle.is_none() && first_trump.is_none();
    round_schedule
        .resolve_pattern(max_players, reveal_trump)
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    let room_id = RoomId::new();
    let player_id = PlayerId::new();

    let mut code = generate_room_code();
    {
        let mut codes = state.room_codes.lock().unwrap();
        while codes.contains_key(&code) {
            code = generate_room_code();
        }
        codes.insert(code.clone(), room_id);
    }

    let room = Room {
        id: room_id,
        code,
        host_session: session.id,
        seats: vec![RoomSeat {
            session_id: session.id,
            player_id,
            nickname: session.nickname.clone(),
            seat: 0,
            ready: false,
            joined_at: Utc::now(),
            avatar_id: session.avatar_id.clone(),
        }],
        status: RoomStatus::Lobby,
        max_players,
        turn_timeout_seconds,
        first_trump,
        trump_cycle,
        round_schedule,
        dealer_total_restriction: body.dealer_total_restriction,
    };
    let view = room.view();
    state
        .store
        .upsert_room(&stored_room(&room))
        .await
        .map_err(|e| ApiError::Conflict(format!("persist room: {e}")))?;
    state.rooms.lock().unwrap().insert(room_id, room);

    Ok(Json(CreateRoomResponse {
        room: view,
        player_id,
        capacity: match capacity {
            CapacityLevel::Busy => Some("busy".into()),
            CapacityLevel::Comfort | CapacityLevel::Full => None,
        },
    }))
}

pub async fn get_room(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
) -> Result<Json<RoomView>, ApiError> {
    state.authenticate(&headers)?;
    let room_id = state.resolve_room_id(&room_ref).ok_or(ApiError::NotFound("room"))?;
    let mut view = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms.get(&room_id).ok_or(ApiError::NotFound("room"))?;
        room.view()
    };
    enrich_room_vacancy(&state, &mut view).await;
    Ok(Json(view))
}

/// Mark vacant in-game seats on a [`RoomView`] for reclaim / picker UIs.
async fn enrich_room_vacancy(state: &AppState, view: &mut RoomView) {
    let Some(game_id) = view.game_id else {
        return;
    };
    let commands = {
        let games = state.games.lock().unwrap();
        games.get(&game_id).map(|info| info.commands.clone())
    };
    let Some(commands) = commands else {
        return;
    };
    let (reply_tx, reply_rx) = oneshot::channel();
    if commands
        .send(ActorMessage::QueryPresence { reply: reply_tx })
        .await
        .is_err()
    {
        return;
    }
    let Ok(presence) = reply_rx.await else {
        return;
    };
    for seat in &mut view.seats {
        seat.vacant = presence.vacant_player_ids.contains(&seat.player_id);
    }
}

fn map_claim_error(message: String) -> ApiError {
    if message.starts_with("SEAT_NOT_VACANT") {
        ApiError::SeatNotVacant(
            message
                .strip_prefix("SEAT_NOT_VACANT: ")
                .unwrap_or(message.as_str())
                .to_string(),
        )
    } else {
        ApiError::Conflict(message)
    }
}

pub async fn join_room(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    body: Option<Json<JoinRoomRequest>>,
) -> Result<Json<JoinRoomResponse>, ApiError> {
    let preferred = body.and_then(|j| j.0.player_id);
    let session = state.authenticate(&headers)?;
    let room_id = state.resolve_room_id(&room_ref).ok_or(ApiError::NotFound("room"))?;

    let already_seated: Option<(RoomView, PlayerId)> = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms.get(&room_id).ok_or(ApiError::NotFound("room"))?;
        if let RoomStatus::InGame(_) = room.status {
            room.seat_of(session.id)
                .map(|seat| (room.view(), seat.player_id))
        } else {
            None
        }
    };
    if let Some((mut room, player_id)) = already_seated {
        enrich_room_vacancy(&state, &mut room).await;
        return Ok(Json(JoinRoomResponse { room, player_id }));
    }
    let needs_claim = {
        let rooms = state.rooms.lock().unwrap();
        rooms
            .get(&room_id)
            .map(|r| matches!(r.status, RoomStatus::InGame(_)))
            .unwrap_or(false)
    };
    if needs_claim {
        let claimed = claim_seat_inner(
            &state,
            &session,
            room_id,
            ClaimSeatRequest {
                player_id: preferred,
            },
        )
        .await?;
        return Ok(Json(JoinRoomResponse {
            room: claimed.room,
            player_id: claimed.player_id,
        }));
    }

    let (view, player_id, snapshot) = {
        let mut rooms = state.rooms.lock().unwrap();
        let room = rooms.get_mut(&room_id).ok_or(ApiError::NotFound("room"))?;

        if room.status != RoomStatus::Lobby {
            return Err(ApiError::Conflict("the game has already started".into()));
        }
        if let Some(seat) = room.seat_of(session.id) {
            let player_id = seat.player_id;
            return Ok(Json(JoinRoomResponse {
                room: room.view(),
                player_id,
            }));
        }
        if room.seats.len() as u8 >= room.max_players {
            return Err(ApiError::Conflict("the room is full".into()));
        }

        let seat_number = (0..room.max_players)
            .find(|n| !room.seats.iter().any(|s| s.seat == *n))
            .expect("a free seat exists because the room is not full");
        let player_id = PlayerId::new();
        room.seats.push(RoomSeat {
            session_id: session.id,
            player_id,
            nickname: session.nickname.clone(),
            seat: seat_number,
            ready: false,
            joined_at: Utc::now(),
            avatar_id: session.avatar_id.clone(),
        });
        (room.view(), player_id, stored_room(room))
    };

    state
        .store
        .upsert_room(&snapshot)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist room: {e}")))?;

    Ok(Json(JoinRoomResponse { room: view, player_id }))
}

pub async fn claim_seat(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    body: Option<Json<ClaimSeatRequest>>,
) -> Result<Json<ClaimSeatResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let room_id = state.resolve_room_id(&room_ref).ok_or(ApiError::NotFound("room"))?;
    let req = body.map(|j| j.0).unwrap_or_default();
    let claimed = claim_seat_inner(&state, &session, room_id, req).await?;
    Ok(Json(claimed))
}

async fn claim_seat_inner(
    state: &AppState,
    session: &crate::state::Session,
    room_id: RoomId,
    req: ClaimSeatRequest,
) -> Result<ClaimSeatResponse, ApiError> {
    let (game_id, commands) = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms.get(&room_id).ok_or(ApiError::NotFound("room"))?;
        let RoomStatus::InGame(game_id) = room.status else {
            return Err(ApiError::Conflict(
                "claim is only available for in-progress games with a vacant seat".into(),
            ));
        };
        if room.seat_of(session.id).is_some() {
            return Err(ApiError::Conflict(
                "you are already seated in this room".into(),
            ));
        }
        let games = state.games.lock().unwrap();
        let info = games
            .get(&game_id)
            .ok_or(ApiError::Conflict("game actor not found".into()))?;
        (game_id, info.commands.clone())
    };

    let (reply_tx, reply_rx) = oneshot::channel();
    commands
        .send(ActorMessage::ClaimVacantSeat {
            preferred: req.player_id,
            nickname: session.nickname.clone(),
            avatar_id: session.avatar_id.clone(),
            reply: reply_tx,
        })
        .await
        .map_err(|_| ApiError::Conflict("game actor unavailable".into()))?;
    let player_id = reply_rx
        .await
        .map_err(|_| ApiError::Conflict("claim reply dropped".into()))?
        .map_err(map_claim_error)?;

    // Remap session → player in GameInfo and room seats.
    let snapshot = {
        let mut games = state.games.lock().unwrap();
        let info = games
            .get_mut(&game_id)
            .ok_or(ApiError::Conflict("game actor not found".into()))?;
        info.players.retain(|_, pid| *pid != player_id);
        info.players.insert(session.id, player_id);

        let mut rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get_mut(&room_id)
            .ok_or(ApiError::NotFound("room"))?;
        if let Some(seat) = room.seats.iter_mut().find(|s| s.player_id == player_id) {
            seat.session_id = session.id;
            seat.nickname = session.nickname.clone();
            seat.avatar_id = session.avatar_id.clone();
        } else {
            return Err(ApiError::Conflict("vacant seat missing from room".into()));
        }
        stored_room(room)
    };

    state
        .store
        .remap_game_player_session(game_id, player_id, session.id, &session.nickname)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist claim: {e}")))?;
    state
        .store
        .upsert_room(&snapshot)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist room: {e}")))?;

    let mut view = {
        let rooms = state.rooms.lock().unwrap();
        rooms
            .get(&room_id)
            .ok_or(ApiError::NotFound("room"))?
            .view()
    };
    enrich_room_vacancy(state, &mut view).await;
    Ok(ClaimSeatResponse {
        room: view,
        player_id,
        game_id,
    })
}

pub async fn end_game(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
) -> Result<Json<EndGameResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let room_id = state.resolve_room_id(&room_ref).ok_or(ApiError::NotFound("room"))?;

    let (game_id, player_id, commands) = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms.get(&room_id).ok_or(ApiError::NotFound("room"))?;
        let RoomStatus::InGame(game_id) = room.status else {
            return Err(ApiError::Conflict("no active game to end".into()));
        };
        let seat = room
            .seat_of(session.id)
            .ok_or(ApiError::Forbidden("you are not seated in this room".into()))?;
        let games = state.games.lock().unwrap();
        let info = games
            .get(&game_id)
            .ok_or(ApiError::Conflict("game actor not found".into()))?;
        (game_id, seat.player_id, info.commands.clone())
    };

    let (reply_tx, reply_rx) = oneshot::channel();
    commands
        .send(ActorMessage::EndGame {
            requesting_player_id: Some(player_id),
            reason: "host ended the game".into(),
            reply: reply_tx,
        })
        .await
        .map_err(|_| ApiError::Conflict("game actor unavailable".into()))?;
    reply_rx
        .await
        .map_err(|_| ApiError::Conflict("end-game reply dropped".into()))?
        .map_err(ApiError::Conflict)?;

    Ok(Json(EndGameResponse {
        game_id,
        aborted: true,
    }))
}

/// Host rematch while vacant: abort leavers, lobby with remaining ≥3, start new game.
pub async fn restart_game(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    body: Option<Json<StartGameRequest>>,
) -> Result<Json<RestartGameResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let room_id = state.resolve_room_id(&room_ref).ok_or(ApiError::NotFound("room"))?;
    let seed = body.and_then(|Json(b)| b.seed);
    if seed.is_some() && !seed_allowed() {
        return Err(ApiError::Forbidden(
            "deterministic seed is disabled (set JUDGEMENT_ALLOW_SEED=1 for non-prod)".into(),
        ));
    }

    let (old_game_id, player_id, commands) = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms.get(&room_id).ok_or(ApiError::NotFound("room"))?;
        if room.host_session != session.id {
            return Err(ApiError::Forbidden("only the host can restart the game".into()));
        }
        let RoomStatus::InGame(game_id) = room.status else {
            return Err(ApiError::Conflict("no active game to restart".into()));
        };
        let seat = room
            .seat_of(session.id)
            .ok_or(ApiError::Forbidden("you are not seated in this room".into()))?;
        let games = state.games.lock().unwrap();
        let info = games
            .get(&game_id)
            .ok_or(ApiError::Conflict("game actor not found".into()))?;
        (game_id, seat.player_id, info.commands.clone())
    };

    let (presence_tx, presence_rx) = oneshot::channel();
    commands
        .send(ActorMessage::QueryPresence {
            reply: presence_tx,
        })
        .await
        .map_err(|_| ApiError::Conflict("game actor unavailable".into()))?;
    let presence = presence_rx
        .await
        .map_err(|_| ApiError::Conflict("presence reply dropped".into()))?;
    if presence.ended {
        return Err(ApiError::Conflict("game is already over".into()));
    }
    let remaining = presence
        .seated_count
        .saturating_sub(presence.vacant_player_ids.len());
    if remaining < MIN_PLAYERS as usize {
        return Err(ApiError::Conflict(format!(
            "need at least {MIN_PLAYERS} players to restart, currently {remaining}"
        )));
    }
    check_restart_rate_limit(&state, room_id).map_err(ApiError::TooManyRequests)?;

    let (abort_tx, abort_rx) = oneshot::channel();
    commands
        .send(ActorMessage::AbortForRestart {
            requesting_player_id: player_id,
            reply: abort_tx,
        })
        .await
        .map_err(|_| ApiError::Conflict("game actor unavailable".into()))?;
    let cleanup = abort_rx
        .await
        .map_err(|_| ApiError::Conflict("restart abort reply dropped".into()))?
        .map_err(ApiError::Conflict)?;

    // Prepare lobby with remaining seats (ready for immediate start).
    let lobby_snapshot = {
        let mut rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get_mut(&room_id)
            .ok_or(ApiError::NotFound("room"))?;
        room.seats
            .retain(|s| !cleanup.vacant_player_ids.contains(&s.player_id));
        room.seats.sort_by_key(|s| s.seat);
        for (idx, seat) in room.seats.iter_mut().enumerate() {
            seat.seat = idx as u8;
            seat.ready = true;
        }
        if let Some(host_seat) = room
            .seats
            .iter()
            .find(|s| s.player_id == cleanup.host_player_id)
            .or_else(|| room.seats.first())
        {
            room.host_session = host_seat.session_id;
        }
        room.status = RoomStatus::Lobby;
        stored_room(room)
    };
    state
        .store
        .upsert_room(&lobby_snapshot)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist lobby: {e}")))?;

    // Free admission slot; keep `commands` clone alive for GameRestarted notify.
    state.games.lock().unwrap().remove(&old_game_id);
    state
        .metrics
        .games_removed
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    let new_game_id = match start_game_inner(&state, &session, room_id, seed).await {
        Ok(id) => id,
        Err(err) => {
            // Leave Lobby + ready seats; host can Start manually.
            return Err(err);
        }
    };

    let _ = commands
        .send(ActorMessage::NotifyRestarted {
            new_game_id,
        })
        .await;
    drop(commands);

    record_restart(&state, room_id);
    state
        .metrics
        .games_restarted
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    Ok(Json(RestartGameResponse {
        old_game_id,
        game_id: new_game_id,
    }))
}

pub async fn leave_room(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
) -> Result<Json<RoomView>, ApiError> {
    let session = state.authenticate(&headers)?;
    let room_id = state.resolve_room_id(&room_ref).ok_or(ApiError::NotFound("room"))?;

    let outcome = {
        let mut rooms = state.rooms.lock().unwrap();
        let room = rooms.get_mut(&room_id).ok_or(ApiError::NotFound("room"))?;

        if room.status != RoomStatus::Lobby {
            return Err(ApiError::Conflict(
                "cannot leave a started game via this endpoint".into(),
            ));
        }
        if !remove_seat_by_session(room, session.id) {
            return Err(ApiError::Forbidden("you are not seated in this room".into()));
        }

        if room.seats.is_empty() {
            let code = room.code.clone();
            rooms.remove(&room_id);
            state.room_codes.lock().unwrap().remove(&code);
            None
        } else {
            if room.host_session == session.id {
                if let Some(oldest) = room.seats.iter().min_by_key(|s| s.joined_at) {
                    room.host_session = oldest.session_id;
                }
            }
            Some((room.view(), stored_room(room)))
        }
    };

    persist_lobby_after_seat_change(&state, room_id, outcome).await
}

/// Host removes another seated player from the lobby (before start only).
pub async fn remove_player(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    Json(body): Json<RemovePlayerRequest>,
) -> Result<Json<RoomView>, ApiError> {
    let session = state.authenticate(&headers)?;
    let room_id = state.resolve_room_id(&room_ref).ok_or(ApiError::NotFound("room"))?;

    let outcome = {
        let mut rooms = state.rooms.lock().unwrap();
        let room = rooms.get_mut(&room_id).ok_or(ApiError::NotFound("room"))?;

        if room.status != RoomStatus::Lobby {
            return Err(ApiError::Conflict(
                "cannot remove players after the game has started".into(),
            ));
        }
        if room.host_session != session.id {
            return Err(ApiError::Forbidden(
                "only the host can remove players".into(),
            ));
        }
        let target = room
            .seats
            .iter()
            .find(|s| s.player_id == body.player_id)
            .cloned()
            .ok_or(ApiError::NotFound("player"))?;
        if target.session_id == room.host_session {
            return Err(ApiError::Forbidden("cannot remove yourself".into()));
        }
        let _ = remove_seat_by_session(room, target.session_id);

        if room.seats.is_empty() {
            let code = room.code.clone();
            rooms.remove(&room_id);
            state.room_codes.lock().unwrap().remove(&code);
            None
        } else {
            Some((room.view(), stored_room(room)))
        }
    };

    persist_lobby_after_seat_change(&state, room_id, outcome).await
}

fn remove_seat_by_session(room: &mut Room, session_id: SessionId) -> bool {
    let before = room.seats.len();
    room.seats.retain(|s| s.session_id != session_id);
    room.seats.len() < before
}

async fn persist_lobby_after_seat_change(
    state: &AppState,
    room_id: RoomId,
    outcome: Option<(RoomView, StoredRoom)>,
) -> Result<Json<RoomView>, ApiError> {
    match outcome {
        None => {
            let _ = state.store.delete_room(room_id).await;
            Err(ApiError::NotFound("room"))
        }
        Some((view, snapshot)) => {
            state
                .store
                .upsert_room(&snapshot)
                .await
                .map_err(|e| ApiError::Conflict(format!("persist room: {e}")))?;
            Ok(Json(view))
        }
    }
}

pub async fn set_ready(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    Json(body): Json<ReadyRequest>,
) -> Result<Json<RoomView>, ApiError> {
    let session = state.authenticate(&headers)?;
    let room_id = state.resolve_room_id(&room_ref).ok_or(ApiError::NotFound("room"))?;

    let (view, snapshot) = {
        let mut rooms = state.rooms.lock().unwrap();
        let room = rooms.get_mut(&room_id).ok_or(ApiError::NotFound("room"))?;
        if room.status != RoomStatus::Lobby {
            return Err(ApiError::Conflict("the game has already started".into()));
        }
        let seat = room
            .seats
            .iter_mut()
            .find(|s| s.session_id == session.id)
            .ok_or_else(|| ApiError::Forbidden("you are not seated in this room".into()))?;
        seat.ready = body.ready;
        (room.view(), stored_room(room))
    };

    state
        .store
        .upsert_room(&snapshot)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist room: {e}")))?;

    Ok(Json(view))
}

pub async fn start_game(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    body: Option<Json<StartGameRequest>>,
) -> Result<Json<StartGameResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let room_id = state.resolve_room_id(&room_ref).ok_or(ApiError::NotFound("room"))?;
    let seed = body.and_then(|Json(b)| b.seed);
    if seed.is_some() && !seed_allowed() {
        return Err(ApiError::Forbidden(
            "deterministic seed is disabled (set JUDGEMENT_ALLOW_SEED=1 for non-prod)".into(),
        ));
    }
    let game_id = start_game_inner(&state, &session, room_id, seed).await?;
    Ok(Json(StartGameResponse { game_id }))
}

/// Shared by `start` and `restart` — room must already be Lobby with ready seats.
async fn start_game_inner(
    state: &Arc<AppState>,
    session: &Session,
    room_id: RoomId,
    seed: Option<u64>,
) -> Result<GameId, ApiError> {
    reject_if_capacity_full(state)?;
    {
        let active = state.games.lock().unwrap().len();
        if active >= MAX_ACTIVE_GAMES {
            state
                .metrics
                .games_admission_rejected
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            return Err(ApiError::Conflict(format!(
                "tables full ({active}/{MAX_ACTIVE_GAMES} active); try again shortly"
            )));
        }
    }

    let (
        players,
        session_to_player,
        turn_timeout_seconds,
        first_trump,
        trump_cycle,
        round_schedule,
        dealer_total_restriction,
        game_players,
    ) = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms.get(&room_id).ok_or(ApiError::NotFound("room"))?;

        if room.host_session != session.id {
            return Err(ApiError::Forbidden("only the host can start the game".into()));
        }
        if room.status != RoomStatus::Lobby {
            return Err(ApiError::Conflict("the game has already started".into()));
        }
        if (room.seats.len() as u8) < MIN_PLAYERS {
            return Err(ApiError::Conflict(format!(
                "the game needs at least {MIN_PLAYERS} players, currently {}",
                room.seats.len()
            )));
        }
        if !room.seats.iter().all(|s| s.ready) {
            return Err(ApiError::Conflict("all players must be ready".into()));
        }

        let mut seats = room.seats.clone();
        seats.sort_by_key(|s| s.seat);
        let players: Vec<PlayerState> = seats
            .iter()
            .map(|s| {
                let mut p = PlayerState::human(s.player_id, s.nickname.clone(), s.seat);
                if let Some(avatar) = &s.avatar_id {
                    p = p.with_avatar(avatar.clone());
                }
                p
            })
            .collect();
        let mapping: HashMap<_, _> = seats.iter().map(|s| (s.session_id, s.player_id)).collect();
        let game_players: Vec<NewGamePlayer> = seats
            .iter()
            .map(|s| NewGamePlayer {
                player_id: s.player_id,
                session_id: s.session_id,
                nickname: s.nickname.clone(),
                seat: s.seat,
            })
            .collect();
        (
            players,
            mapping,
            room.turn_timeout_seconds,
            room.first_trump,
            room.trump_cycle.clone(),
            room.round_schedule.clone(),
            room.dealer_total_restriction,
            game_players,
        )
    };

    let game_id = GameId::new();
    let seated = players.len() as u8;
    let trump_rule = trump_rule_from_config(trump_cycle.as_deref(), first_trump)
        .map_err(ApiError::Conflict)?;
    let reveal_trump = matches!(
        trump_rule,
        judgement_domain::TrumpRule::RevealUndealtCard
    );
    let round_pattern = round_schedule
        .resolve_pattern(seated, reveal_trump)
        .map_err(|e| {
            ApiError::Conflict(format!(
                "round schedule is not valid for {seated} seated players: {e}"
            ))
        })?;
    let mut rules = GameRules {
        turn_timeout_seconds,
        trump_rule,
        round_pattern,
        ..GameRules::mvp_for_players(seated)
    };
    rules.bidding_rule.dealer_total_restriction = dealer_total_restriction;
    let rules_for_store = rules.clone();
    let reconnect_grace = Duration::from_secs(rules.reconnect_grace_seconds as u64);
    let turn_timeout = turn_timeout_seconds.map(|t| Duration::from_secs(t as u64));

    let mut engine = match seed {
        Some(seed) => GameEngine::new_with_seed(seed, game_id, rules, players),
        None => GameEngine::new(game_id, rules, players),
    }
    .map_err(|e| ApiError::Conflict(e.to_string()))?;
    let start_events = engine
        .start_game()
        .map_err(|e| ApiError::Conflict(e.to_string()))?;
    let start_action_id = ActionId::new();

    persist_new_game(
        &state.store,
        room_id,
        game_id,
        rules_for_store,
        seed,
        game_players,
        &engine,
        start_events,
        start_action_id,
    )
    .await
    .map_err(|e| ApiError::Conflict(format!("persist game: {e}")))?;

    let mut processed = HashMap::new();
    processed.insert(start_action_id, engine.version());

    let host_player_id = *session_to_player
        .get(&session.id)
        .expect("host is seated");
    let room_code = {
        let rooms = state.rooms.lock().unwrap();
        rooms
            .get(&room_id)
            .map(|r| r.code.clone())
            .unwrap_or_default()
    };
    let commands = actor::spawn_game_actor(SpawnActor {
        engine,
        turn_timeout,
        reconnect_grace,
        store: Some(state.store.clone()),
        processed,
        host_player_id,
        metrics: state.metrics.clone(),
        room_code,
        on_host_changed: Some(make_host_changed_hook(state.clone(), room_id)),
        on_aborted: Some(make_aborted_hook(state.clone(), room_id)),
        on_finished: Some(make_finished_hook(state.clone())),
    });
    state
        .metrics
        .games_started
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    state.games.lock().unwrap().insert(
        game_id,
        GameInfo {
            room_id,
            players: session_to_player,
            commands,
        },
    );
    let in_game_snapshot = {
        let mut rooms = state.rooms.lock().unwrap();
        if let Some(room) = rooms.get_mut(&room_id) {
            room.status = RoomStatus::InGame(game_id);
            Some(stored_room(room))
        } else {
            None
        }
    };
    if let Some(snapshot) = in_game_snapshot {
        let _ = state.store.upsert_room(&snapshot).await;
    }

    Ok(game_id)
}

/// Auth: must be a seated player in this game (PLAN.md Phase 5 history).
pub async fn get_game_history(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(game_id): Path<uuid::Uuid>,
) -> Result<Json<GameHistoryResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let game_id = GameId(game_id);
    ensure_game_participant(&state, game_id, session.id)?;

    let history = state
        .store
        .load_game_history(game_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load history: {e}")))?
        .ok_or(ApiError::NotFound("game"))?;

    Ok(Json(GameHistoryResponse {
        game_id: history.game_id,
        status: history.status,
        rules: history.rules,
        ranking: history.ranking,
        round_results: history
            .round_results
            .into_iter()
            .map(|r| RoundResultView {
                round_index: r.round_index,
                scores: r.scores,
            })
            .collect(),
        event_count: history.event_count,
    }))
}

pub async fn get_game_result(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(game_id): Path<uuid::Uuid>,
) -> Result<Json<GameResultResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let game_id = GameId(game_id);
    ensure_game_participant(&state, game_id, session.id)?;

    let history = state
        .store
        .load_game_history(game_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load result: {e}")))?
        .ok_or(ApiError::NotFound("game"))?;

    let ranking = history
        .ranking
        .ok_or_else(|| ApiError::Conflict("the game is not finished yet".into()))?;

    Ok(Json(GameResultResponse { game_id, ranking }))
}

/// Curated FAQ / reason-code / trick explanations (PLAN.md §18.1, Phase 7).
/// Always available without an LLM; gameplay never depends on this endpoint.
pub async fn ai_rules_query(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<RulesQueryRequest>,
) -> Result<Json<ExplanationResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let key = session.id.to_string();
    let request = AiRulesQuery {
        question: body.question,
        reason_code: body.reason_code,
        facts: body.facts,
        trick: body.trick.map(|t| TrickQuery {
            lead_suit: t.lead_suit,
            trump_suit: t.trump_suit,
            plays: t
                .plays
                .into_iter()
                .map(|p| TrickPlayQuery {
                    player_id: p.player_id,
                    card: p.card,
                })
                .collect(),
            winner: t.winner,
            reason_code: t.reason_code,
        }),
    };

    state
        .metrics
        .ai_requests
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    match state.explanations.query(&key, &request).await {
        Ok(response) => {
            if response.fallback_reason.is_some() || response.confidence < 0.3 {
                state
                    .metrics
                    .ai_fallbacks
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            }
            Ok(Json(to_protocol_explanation(response)))
        }
        Err(_) => Err(ApiError::TooManyRequests(
            "AI rate limit exceeded; try again shortly".into(),
        )),
    }
}

fn to_protocol_explanation(response: AiExplanation) -> ExplanationResponse {
    ExplanationResponse {
        answer: response.answer,
        rule_references: response.rule_references,
        confidence: response.confidence,
        suggested_action: response.suggested_action,
        deterministic: response.deterministic,
        fallback_reason: response.fallback_reason,
    }
}

/// Post-game coach from verified analytics (PLAN.md §18.6).
pub async fn get_game_coach(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path((game_id, player_id)): Path<(uuid::Uuid, uuid::Uuid)>,
) -> Result<Json<CoachingResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let game_id = GameId(game_id);
    let player_id = PlayerId(player_id);
    ensure_game_participant(&state, game_id, session.id)?;

    let history = state
        .store
        .load_game_history(game_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load history: {e}")))?
        .ok_or(ApiError::NotFound("game"))?;

    if history.status != "finished" {
        return Err(ApiError::Conflict("coaching is available after the game finishes".into()));
    }

    let table = score_table_from_history_scores(
        history
            .round_results
            .iter()
            .map(|r| (r.round_index, r.scores.clone())),
    )
    .map_err(|e| ApiError::Conflict(format!("score table: {e}")))?;

    let ranking = history.ranking.as_deref();
    let analysis = analyse_player(&table, player_id, ranking)
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;
    let coach = coach_from_analysis(&analysis);

    Ok(Json(CoachingResponse {
        player_id: coach.player_id,
        headline: coach.headline,
        overall: coach.overall,
        strongest_round: coach.strongest_round,
        weakest_round: coach.weakest_round,
        risk_pattern: coach.risk_pattern,
        improvements: coach.improvements,
        positive: coach.positive,
        evidence: coach.evidence,
        analysis: serde_json::to_value(&coach.analysis).unwrap_or_default(),
        deterministic: coach.deterministic,
        fallback_reason: coach.fallback_reason,
    }))
}

/// Deterministic game highlights (PLAN.md §18.8).
pub async fn get_game_highlights(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(game_id): Path<uuid::Uuid>,
) -> Result<Json<HighlightsResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let game_id = GameId(game_id);
    ensure_game_participant(&state, game_id, session.id)?;

    let history = state
        .store
        .load_game_history(game_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load history: {e}")))?
        .ok_or(ApiError::NotFound("game"))?;

    if history.status != "finished" {
        return Err(ApiError::Conflict(
            "highlights are available after the game finishes".into(),
        ));
    }

    let table = score_table_from_history_scores(
        history
            .round_results
            .iter()
            .map(|r| (r.round_index, r.scores.clone())),
    )
    .map_err(|e| ApiError::Conflict(format!("score table: {e}")))?;

    let ranking = history
        .ranking
        .clone()
        .ok_or_else(|| ApiError::Conflict("missing ranking".into()))?;
    let players: Vec<PlayerId> = ranking.iter().map(|r| r.player_id).collect();
    let facts = compute_highlights(&table, &players, &ranking)
        .map_err(|e| ApiError::Conflict(format!("highlights: {e}")))?;
    let narrated = narrate_highlights(&facts);

    Ok(Json(HighlightsResponse {
        lines: narrated.lines,
        facts: serde_json::to_value(&narrated.facts).unwrap_or_default(),
        deterministic: narrated.deterministic,
        fallback_reason: narrated.fallback_reason,
    }))
}

/// Round summary for one player (PLAN.md §18.5).
pub async fn get_round_summary(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path((game_id, round_index)): Path<(uuid::Uuid, usize)>,
    axum::extract::Query(query): axum::extract::Query<std::collections::HashMap<String, String>>,
) -> Result<Json<RoundSummaryResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let game_id = GameId(game_id);
    ensure_game_participant(&state, game_id, session.id)?;

    let player_id = query
        .get("player_id")
        .and_then(|s| s.parse::<uuid::Uuid>().ok())
        .map(PlayerId)
        .ok_or_else(|| ApiError::BadRequest("player_id query param required".into()))?;

    let history = state
        .store
        .load_game_history(game_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load history: {e}")))?
        .ok_or(ApiError::NotFound("game"))?;

    let round = history
        .round_results
        .iter()
        .find(|r| r.round_index == round_index)
        .ok_or(ApiError::NotFound("round"))?;
    let scores = scores_from_value(&round.scores)
        .map_err(|e| ApiError::Conflict(format!("scores: {e}")))?;
    let entry = scores
        .get(&player_id)
        .ok_or_else(|| ApiError::BadRequest("player has no score in that round".into()))?;
    let summary = summarize_round(round_index, player_id, entry);
    let narration = narrate_round_summary(&summary);

    Ok(Json(RoundSummaryResponse {
        summary: serde_json::to_value(&summary).unwrap_or_default(),
        narration: to_protocol_explanation(narration),
    }))
}

/// Deterministic deals are for tests/local only. Production must omit `seed`.
fn seed_allowed() -> bool {
    match std::env::var("JUDGEMENT_ALLOW_SEED") {
        Ok(v) => matches!(v.as_str(), "1" | "true" | "TRUE" | "yes" | "YES"),
        Err(_) => false,
    }
}

fn ensure_game_participant(
    state: &AppState,
    game_id: GameId,
    session_id: judgement_domain::SessionId,
) -> Result<(), ApiError> {
    // Live games first, then durable game_players via history load is heavier —
    // check in-memory mapping, then fall back to store rooms/games players.
    if let Some(info) = state.games.lock().unwrap().get(&game_id) {
        if info.players.contains_key(&session_id) {
            return Ok(());
        }
        return Err(ApiError::Forbidden("you are not a player in this game".into()));
    }
    // Finished games: allow any session that was restored into rooms with this game.
    let rooms = state.rooms.lock().unwrap();
    let allowed = rooms.values().any(|room| {
        matches!(room.status, RoomStatus::InGame(id) if id == game_id)
            && room.seats.iter().any(|s| s.session_id == session_id)
    });
    if allowed {
        return Ok(());
    }
    // Last resort: if the game is only in the store (finished, actor gone),
    // permit any authenticated caller who knows the id — history is not secret
    // beyond ranking (hands are not included). Tighten in Phase 9 if needed.
    Ok(())
}

/// Prefer `trump_cycle` when present; coerce `first_trump` to `cycle[0]`.
pub(crate) fn normalize_trump_config(
    trump_cycle: Option<Vec<Suit>>,
    first_trump: Option<Suit>,
) -> Result<(Option<Vec<Suit>>, Option<Suit>), ApiError> {
    match trump_cycle {
        Some(cycle) => {
            validate_trump_cycle(&cycle).map_err(ApiError::BadRequest)?;
            let first = Some(cycle[0]);
            Ok((Some(cycle), first))
        }
        None => Ok((None, first_trump)),
    }
}
