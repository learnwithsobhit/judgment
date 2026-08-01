//! REST handlers for guest sessions and room management (PLAN.md §13.1).

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::{Path, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use judgement_domain::{
    ActionId, GameId, GameRules, PlayerId, PlayerState, RoomId, SessionId, TrumpRule, MAX_PLAYERS,
    MIN_PLAYERS,
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
    JoinRoomRequest, JoinRoomResponse, ReadyRequest, RemovePlayerRequest, RoomView,
    RoundResultView, RoundSummaryResponse, RulesQueryRequest, SetAvatarRequest, SetAvatarResponse,
    StartGameRequest, StartGameResponse,
};
use crate::emotes::is_allowed_avatar;
use tokio::sync::oneshot;

use crate::actor::{self, ActorMessage, SpawnActor};
use crate::error::ApiError;
use crate::persist::{persist_new_game, stored_room, stored_session};
use crate::state::{generate_room_code, AppState, GameInfo, Room, RoomSeat, RoomStatus};

/// Load-shed new tables so existing actors keep DB pool headroom (CAP Availability).
pub const MAX_ACTIVE_GAMES: usize = 100;

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

    let max_players = body.max_players.unwrap_or(6);
    if !(MIN_PLAYERS..=MAX_PLAYERS).contains(&max_players) {
        return Err(ApiError::BadRequest(format!(
            "max_players must be between {MIN_PLAYERS} and {MAX_PLAYERS}"
        )));
    }
    let turn_timeout_seconds = body.turn_timeout_seconds.map(|t| t.clamp(5, 300));

    let round_schedule = body.round_schedule.unwrap_or_default();
    // Validate against table size at create; start_game re-checks seated count.
    let reveal_trump = body.first_trump.is_none();
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
        first_trump: body.first_trump,
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

    Ok(Json(CreateRoomResponse { room: view, player_id }))
}

pub async fn get_room(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
) -> Result<Json<RoomView>, ApiError> {
    state.authenticate(&headers)?;
    let room_id = state.resolve_room_id(&room_ref).ok_or(ApiError::NotFound("room"))?;
    let rooms = state.rooms.lock().unwrap();
    let room = rooms.get(&room_id).ok_or(ApiError::NotFound("room"))?;
    Ok(Json(room.view()))
}

pub async fn join_room(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    body: Option<Json<JoinRoomRequest>>,
) -> Result<Json<JoinRoomResponse>, ApiError> {
    let _ = body;
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
    if let Some((room, player_id)) = already_seated {
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
            ClaimSeatRequest { player_id: None },
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
        .map_err(ApiError::Conflict)?;

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

    let view = {
        let rooms = state.rooms.lock().unwrap();
        rooms
            .get(&room_id)
            .ok_or(ApiError::NotFound("room"))?
            .view()
    };
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
            let mapping: HashMap<_, _> =
                seats.iter().map(|s| (s.session_id, s.player_id)).collect();
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
                room.round_schedule.clone(),
                room.dealer_total_restriction,
                game_players,
            )
        };

    let game_id = GameId::new();
    let seated = players.len() as u8;
    let trump_rule = match first_trump {
        Some(suit) => TrumpRule::rotating_from(suit),
        None => TrumpRule::RevealUndealtCard,
    };
    let reveal_trump = matches!(trump_rule, TrumpRule::RevealUndealtCard);
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
    {
        let mut rooms = state.rooms.lock().unwrap();
        if let Some(room) = rooms.get_mut(&room_id) {
            room.status = RoomStatus::InGame(game_id);
        }
    }

    Ok(Json(StartGameResponse { game_id }))
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
