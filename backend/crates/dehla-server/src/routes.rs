use std::collections::HashMap;
use std::sync::Arc;

use axum::extract::{Path, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use dehla_domain::{PartnershipMode, PlayerId, TABLE_SEATS};
use dehla_engine::{
    new_game_id, seats_for_partners, start_game, GameConfig, SeatPlayer, StartGame,
};
use dehla_protocol::{
    ClaimSeatRequest, ClaimSeatResponse, CreateGuestSessionRequest, CreateGuestSessionResponse,
    CreateRoomRequest, CreateRoomResponse, EndGameResponse, JoinRoomRequest, JoinRoomResponse,
    ReadyRequest, RestartGameResponse, RoomView, SetPartnershipRequest, StartGameResponse,
};
use tokio::sync::oneshot;
use uuid::Uuid;

use crate::actor::{spawn_game_actor, AbortedCleanup, ActorMessage, SpawnActor};
use crate::capacity::{is_full, CAPACITY_FULL_MESSAGE};
use crate::error::ApiError;
use crate::state::{
    generate_room_code, generate_token, validate_nickname, AppState, GameInfo, Room, RoomSeat,
    RoomStatus, Session, SEATS,
};

pub async fn create_guest_session(
    State(state): State<Arc<AppState>>,
    Json(body): Json<CreateGuestSessionRequest>,
) -> Result<Json<CreateGuestSessionResponse>, ApiError> {
    let nickname = validate_nickname(&body.nickname)?;
    let id = Uuid::new_v4();
    let token = generate_token();
    let session = Session {
        id,
        nickname: nickname.clone(),
        token: token.clone(),
        avatar_id: body.avatar_id.filter(|a| !a.is_empty()),
    };
    state.sessions.lock().unwrap().insert(id, session);
    state.tokens.lock().unwrap().insert(token.clone(), id);
    Ok(Json(CreateGuestSessionResponse {
        session_id: id,
        nickname,
        token,
    }))
}

pub async fn create_room(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<CreateRoomRequest>,
) -> Result<Json<CreateRoomResponse>, ApiError> {
    if is_full(&state) {
        return Err(ApiError::capacity_full(CAPACITY_FULL_MESSAGE));
    }
    let session = state.session_from_headers(&headers)?;
    if body.kots_to_win == 0 || body.kots_to_win > 9 {
        return Err(ApiError::bad("INVALID_KOTS", "kots_to_win must be 1–9"));
    }

    let room_id = Uuid::new_v4();
    let mut code = generate_room_code();
    {
        let mut codes = state.room_codes.lock().unwrap();
        while codes.contains_key(&code) {
            code = generate_room_code();
        }
        codes.insert(code.clone(), room_id);
    }

    let player_id = Uuid::new_v4();
    let seat = RoomSeat {
        session_id: session.id,
        player_id,
        nickname: session.nickname.clone(),
        seat: 0,
        ready: false,
        joined_at: Utc::now(),
        avatar_id: session.avatar_id.clone(),
    };
    let room = Room {
        id: room_id,
        code,
        host_session: session.id,
        seats: vec![seat],
        status: RoomStatus::Lobby,
        rule_pack: body.rule_pack,
        trump_method: body.trump_method,
        partnership_mode: body.partnership_mode,
        tens_tie_rule: body.tens_tie_rule,
        kots_to_win: body.kots_to_win,
        partners_confirmed: false,
    };
    let view = room.view();
    state.rooms.lock().unwrap().insert(room_id, room);
    Ok(Json(CreateRoomResponse {
        room: view,
        player_id,
    }))
}

pub async fn get_room(
    State(state): State<Arc<AppState>>,
    Path(room_ref): Path<String>,
) -> Result<Json<RoomView>, ApiError> {
    let id = state.resolve_room_id(&room_ref)?;
    let rooms = state.rooms.lock().unwrap();
    let room = rooms
        .get(&id)
        .ok_or_else(|| ApiError::not_found("room not found"))?;
    Ok(Json(room.view()))
}

pub async fn join_room(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    Json(body): Json<JoinRoomRequest>,
) -> Result<Json<JoinRoomResponse>, ApiError> {
    let session = state.session_from_headers(&headers)?;
    let id = state.resolve_room_id(&room_ref)?;

    let in_game = {
        let rooms = state.rooms.lock().unwrap();
        rooms
            .get(&id)
            .map(|r| matches!(r.status, RoomStatus::InGame(_)))
            .unwrap_or(false)
    };
    if in_game {
        let claimed = claim_seat_inner(
            &state,
            &session,
            id,
            ClaimSeatRequest {
                player_id: body.player_id,
            },
        )
        .await?;
        return Ok(Json(JoinRoomResponse {
            player_id: claimed.player_id,
            room: claimed.room,
        }));
    }

    let mut rooms = state.rooms.lock().unwrap();
    let room = rooms
        .get_mut(&id)
        .ok_or_else(|| ApiError::not_found("room not found"))?;

    if !matches!(room.status, RoomStatus::Lobby | RoomStatus::Partnership) {
        return Err(ApiError::conflict("GAME_STARTED", "game already started"));
    }
    if let Some(existing) = room.seat_of(session.id) {
        return Ok(Json(JoinRoomResponse {
            player_id: existing.player_id,
            room: room.view(),
        }));
    }
    if room.seats.len() >= SEATS as usize {
        return Err(ApiError::conflict("ROOM_FULL", "table is full"));
    }
    let used: Vec<u8> = room.seats.iter().map(|s| s.seat).collect();
    let seat_no = (0..SEATS).find(|s| !used.contains(s)).unwrap();
    let player_id = Uuid::new_v4();
    room.seats.push(RoomSeat {
        session_id: session.id,
        player_id,
        nickname: session.nickname.clone(),
        seat: seat_no,
        ready: false,
        joined_at: Utc::now(),
        avatar_id: session.avatar_id.clone(),
    });

    // Auto-enter partnership phase when full
    if room.seats.len() == TABLE_SEATS as usize {
        room.status = RoomStatus::Partnership;
        if room.partnership_mode == PartnershipMode::RandomOpposite {
            apply_random_partners(room);
        }
    }

    Ok(Json(JoinRoomResponse {
        player_id,
        room: room.view(),
    }))
}

fn apply_random_partners(room: &mut Room) {
    let ids_vec: Vec<PlayerId> = room.seats.iter().map(|s| s.player_id).collect();
    let ids: [PlayerId; 4] = ids_vec.try_into().expect("4 players");
    let seed = Utc::now().timestamp_millis() as u64;
    let ordered = seats_for_partners(PartnershipMode::RandomOpposite, ids, None, seed)
        .expect("random partners");
    let by_id: HashMap<PlayerId, RoomSeat> =
        room.seats.drain(..).map(|s| (s.player_id, s)).collect();
    for (seat, pid) in ordered.into_iter().enumerate() {
        let mut s = by_id.get(&pid).expect("player").clone();
        s.seat = seat as u8;
        s.ready = false;
        room.seats.push(s);
    }
    room.partners_confirmed = true;
    room.partnership_mode = PartnershipMode::RandomOpposite;
}

pub async fn set_partnership(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    Json(body): Json<SetPartnershipRequest>,
) -> Result<Json<RoomView>, ApiError> {
    let session = state.session_from_headers(&headers)?;
    let id = state.resolve_room_id(&room_ref)?;
    let mut rooms = state.rooms.lock().unwrap();
    let room = rooms
        .get_mut(&id)
        .ok_or_else(|| ApiError::not_found("room not found"))?;
    if room.host_session != session.id {
        return Err(ApiError::forbidden("host only"));
    }
    if room.seats.len() != TABLE_SEATS as usize {
        return Err(ApiError::bad("NOT_FULL", "need 4 players"));
    }
    if !matches!(room.status, RoomStatus::Partnership | RoomStatus::Lobby) {
        return Err(ApiError::conflict("BAD_PHASE", "cannot set partners now"));
    }
    room.status = RoomStatus::Partnership;
    room.partnership_mode = body.mode;
    match body.mode {
        PartnershipMode::RandomOpposite => {
            apply_random_partners(room);
        }
        PartnershipMode::ChoosePartners => {
            let pairs = body
                .pairs
                .ok_or_else(|| ApiError::bad("PAIRS_REQUIRED", "pairs required"))?;
            if pairs.len() != 2 {
                return Err(ApiError::bad("PAIRS_REQUIRED", "need exactly two pairs"));
            }
            let chosen = [(pairs[0][0], pairs[0][1]), (pairs[1][0], pairs[1][1])];
            let ids = [
                room.seats[0].player_id,
                room.seats[1].player_id,
                room.seats[2].player_id,
                room.seats[3].player_id,
            ];
            let ordered = seats_for_partners(
                PartnershipMode::ChoosePartners,
                ids,
                Some(chosen),
                0,
            )
            .map_err(|e| ApiError::bad("INVALID_PAIRS", e.to_string()))?;
            let by_id: HashMap<PlayerId, RoomSeat> =
                room.seats.drain(..).map(|s| (s.player_id, s)).collect();
            for (seat, pid) in ordered.into_iter().enumerate() {
                let mut s = by_id
                    .get(&pid)
                    .ok_or_else(|| ApiError::bad("INVALID_PAIRS", "unknown player in pairs"))?
                    .clone();
                s.seat = seat as u8;
                s.ready = false;
                room.seats.push(s);
            }
            room.partners_confirmed = true;
        }
    }
    Ok(Json(room.view()))
}

pub async fn ready(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    Json(body): Json<ReadyRequest>,
) -> Result<Json<RoomView>, ApiError> {
    let session = state.session_from_headers(&headers)?;
    let id = state.resolve_room_id(&room_ref)?;
    let mut rooms = state.rooms.lock().unwrap();
    let room = rooms
        .get_mut(&id)
        .ok_or_else(|| ApiError::not_found("room not found"))?;
    if !matches!(room.status, RoomStatus::Lobby | RoomStatus::Partnership) {
        return Err(ApiError::conflict("BAD_PHASE", "not in lobby"));
    }
    let seat = room
        .seats
        .iter_mut()
        .find(|s| s.session_id == session.id)
        .ok_or_else(|| ApiError::forbidden("not seated"))?;
    seat.ready = body.ready;
    Ok(Json(room.view()))
}

pub async fn leave_room(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
) -> Result<Json<RoomView>, ApiError> {
    let session = state.session_from_headers(&headers)?;
    let room_id = state.resolve_room_id(&room_ref)?;

    let in_game = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get(&room_id)
            .ok_or_else(|| ApiError::not_found("room not found"))?;
        match room.status {
            RoomStatus::InGame(game_id) => {
                let seat = room
                    .seat_of(session.id)
                    .ok_or_else(|| ApiError::forbidden("not seated"))?;
                Some((game_id, seat.player_id))
            }
            _ => None,
        }
    };

    if let Some((game_id, player_id)) = in_game {
        let commands = {
            let games = state.games.lock().unwrap();
            games
                .get(&game_id)
                .map(|g| g.commands.clone())
                .ok_or_else(|| ApiError::conflict("NO_ACTOR", "game actor not found"))?
        };
        commands
            .send(ActorMessage::LeaveGame { player_id })
            .await
            .map_err(|_| ApiError::conflict("NO_ACTOR", "game actor unavailable"))?;
        let rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get(&room_id)
            .ok_or_else(|| ApiError::not_found("room not found"))?;
        return Ok(Json(room.view()));
    }

    // Lobby / partnership: remove seat; host transfer; delete if empty.
    let mut rooms = state.rooms.lock().unwrap();
    let room = rooms
        .get_mut(&room_id)
        .ok_or_else(|| ApiError::not_found("room not found"))?;
    if !matches!(room.status, RoomStatus::Lobby | RoomStatus::Partnership) {
        return Err(ApiError::conflict("BAD_PHASE", "cannot leave in this phase"));
    }
    let before = room.seats.len();
    room.seats.retain(|s| s.session_id != session.id);
    if room.seats.len() == before {
        return Err(ApiError::forbidden("not seated"));
    }
    if matches!(room.status, RoomStatus::Partnership) {
        room.status = RoomStatus::Lobby;
        room.partners_confirmed = false;
        for s in &mut room.seats {
            s.ready = false;
        }
    }
    if room.seats.is_empty() {
        let code = room.code.clone();
        rooms.remove(&room_id);
        state.room_codes.lock().unwrap().remove(&code);
        return Err(ApiError::not_found("room deleted"));
    }
    if room.host_session == session.id {
        if let Some(oldest) = room.seats.iter().min_by_key(|s| s.joined_at) {
            room.host_session = oldest.session_id;
        }
    }
    Ok(Json(room.view()))
}

pub async fn claim_seat(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
    body: Option<Json<ClaimSeatRequest>>,
) -> Result<Json<ClaimSeatResponse>, ApiError> {
    let session = state.session_from_headers(&headers)?;
    let room_id = state.resolve_room_id(&room_ref)?;
    let req = body.map(|j| j.0).unwrap_or_default();
    let claimed = claim_seat_inner(&state, &session, room_id, req).await?;
    Ok(Json(claimed))
}

async fn claim_seat_inner(
    state: &AppState,
    session: &Session,
    room_id: uuid::Uuid,
    req: ClaimSeatRequest,
) -> Result<ClaimSeatResponse, ApiError> {
    let (game_id, commands) = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get(&room_id)
            .ok_or_else(|| ApiError::not_found("room not found"))?;
        let RoomStatus::InGame(game_id) = room.status else {
            return Err(ApiError::conflict(
                "NOT_IN_GAME",
                "claim is only available for in-progress games with a vacant seat",
            ));
        };
        if room.seat_of(session.id).is_some() {
            return Err(ApiError::conflict(
                "ALREADY_SEATED",
                "you are already seated in this room",
            ));
        }
        let games = state.games.lock().unwrap();
        let info = games
            .get(&game_id)
            .ok_or_else(|| ApiError::conflict("NO_ACTOR", "game actor not found"))?;
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
        .map_err(|_| ApiError::conflict("NO_ACTOR", "game actor unavailable"))?;
    let player_id = reply_rx
        .await
        .map_err(|_| ApiError::conflict("CLAIM_DROPPED", "claim reply dropped"))?
        .map_err(map_claim_error)?;

    // Remap session → player in GameInfo and room seats.
    {
        let mut games = state.games.lock().unwrap();
        let info = games
            .get_mut(&game_id)
            .ok_or_else(|| ApiError::conflict("NO_ACTOR", "game actor not found"))?;
        info.players.retain(|_, pid| *pid != player_id);
        info.players.insert(session.id, player_id);

        let mut rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get_mut(&room_id)
            .ok_or_else(|| ApiError::not_found("room not found"))?;
        if let Some(seat) = room.seats.iter_mut().find(|s| s.player_id == player_id) {
            seat.session_id = session.id;
            seat.nickname = session.nickname.clone();
            seat.avatar_id = session.avatar_id.clone();
        } else {
            return Err(ApiError::conflict(
                "SEAT_MISSING",
                "vacant seat missing from room",
            ));
        }
    }

    let view = {
        let rooms = state.rooms.lock().unwrap();
        rooms
            .get(&room_id)
            .ok_or_else(|| ApiError::not_found("room not found"))?
            .view()
    };
    Ok(ClaimSeatResponse {
        room: view,
        player_id,
        game_id,
    })
}

fn map_claim_error(detail: String) -> ApiError {
    if detail.starts_with("SEAT_NOT_VACANT") {
        ApiError::conflict("SEAT_NOT_VACANT", detail)
    } else if detail.contains("persist") {
        ApiError::conflict("PERSIST_UNAVAILABLE", detail)
    } else {
        ApiError::conflict("CLAIM_FAILED", detail)
    }
}

pub async fn start_game_route(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
) -> Result<Json<StartGameResponse>, ApiError> {
    if is_full(&state) {
        return Err(ApiError::capacity_full(CAPACITY_FULL_MESSAGE));
    }
    let session = state.session_from_headers(&headers)?;
    let id = state.resolve_room_id(&room_ref)?;

    let (game_id, spawn_state, players_map) = {
        let mut rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get_mut(&id)
            .ok_or_else(|| ApiError::not_found("room not found"))?;
        if room.host_session != session.id {
            return Err(ApiError::forbidden("host only"));
        }
        if room.seats.len() != TABLE_SEATS as usize {
            return Err(ApiError::bad("NOT_FULL", "need 4 players"));
        }
        if !room.partners_confirmed {
            return Err(ApiError::bad(
                "PARTNERS_REQUIRED",
                "confirm partnership (random or choose) first",
            ));
        }
        if !room.seats.iter().all(|s| s.ready) {
            return Err(ApiError::bad("NOT_READY", "all players must be ready"));
        }
        if matches!(room.status, RoomStatus::InGame(_)) {
            return Err(ApiError::conflict("ALREADY_STARTED", "already started"));
        }

        let game_id = new_game_id();
        let mut players: Vec<SeatPlayer> = room
            .seats
            .iter()
            .map(|s| SeatPlayer {
                player_id: s.player_id,
                nickname: s.nickname.clone(),
                seat: s.seat,
                avatar_id: s.avatar_id.clone(),
            })
            .collect();
        players.sort_by_key(|p| p.seat);

        let config = GameConfig {
            rule_pack: room.rule_pack,
            trump_method: room.trump_method,
            partnership_mode: room.partnership_mode,
            tens_tie_rule: room.tens_tie_rule,
            kots_to_win: room.kots_to_win,
        };
        let seed = Utc::now().timestamp_millis() as u64;
        let engine_state = start_game(StartGame {
            game_id,
            config,
            players,
            seed,
        })
        .map_err(|e| ApiError::bad("ENGINE", e.to_string()))?;

        let players_map: HashMap<_, _> = room
            .seats
            .iter()
            .map(|s| (s.session_id, s.player_id))
            .collect();
        room.status = RoomStatus::InGame(game_id);
        (game_id, engine_state, players_map)
    };

    // Initial tip before clients observe the table (CP).
    if let Err(e) = state.store.save_tip(game_id, &spawn_state).await {
        let mut rooms = state.rooms.lock().unwrap();
        if let Some(room) = rooms.get_mut(&id) {
            room.status = RoomStatus::Partnership;
        }
        return Err(ApiError::conflict(
            "PERSIST_UNAVAILABLE",
            format!("save tip: {e}"),
        ));
    }
    state
        .metrics
        .tips_saved
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    let host_player_id = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms.get(&id).ok_or_else(|| ApiError::not_found("room not found"))?;
        room.seats
            .iter()
            .find(|s| s.session_id == room.host_session)
            .map(|s| s.player_id)
            .ok_or_else(|| ApiError::conflict("NO_HOST", "host seat missing"))?
    };

    let commands = spawn_game_actor(SpawnActor {
        state: spawn_state,
        store: state.store.clone(),
        metrics: state.metrics.clone(),
        host_player_id,
    });
    state.games.lock().unwrap().insert(
        game_id,
        GameInfo {
            room_id: id,
            players: players_map,
            commands,
        },
    );

    Ok(Json(StartGameResponse { game_id }))
}

fn apply_abort_to_lobby(room: &mut Room, cleanup: &AbortedCleanup) {
    room.seats
        .retain(|s| !cleanup.vacant_player_ids.contains(&s.player_id));
    room.seats.sort_by_key(|s| s.seat);
    for (idx, seat) in room.seats.iter_mut().enumerate() {
        seat.seat = idx as u8;
        seat.ready = false;
    }
    if let Some(host_seat) = room
        .seats
        .iter()
        .find(|s| s.player_id == cleanup.host_player_id)
        .or_else(|| room.seats.first())
    {
        room.host_session = host_seat.session_id;
    }
    room.partners_confirmed = false;
    room.status = RoomStatus::Lobby;
}

pub async fn end_game(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
) -> Result<Json<EndGameResponse>, ApiError> {
    let session = state.session_from_headers(&headers)?;
    let room_id = state.resolve_room_id(&room_ref)?;

    let (game_id, player_id, commands) = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get(&room_id)
            .ok_or_else(|| ApiError::not_found("room not found"))?;
        if room.host_session != session.id {
            return Err(ApiError::forbidden("only the host can end the game"));
        }
        let RoomStatus::InGame(game_id) = room.status else {
            return Err(ApiError::conflict("NO_GAME", "no active game to end"));
        };
        let seat = room
            .seat_of(session.id)
            .ok_or_else(|| ApiError::forbidden("not seated"))?;
        let games = state.games.lock().unwrap();
        let info = games
            .get(&game_id)
            .ok_or_else(|| ApiError::conflict("NO_ACTOR", "game actor not found"))?;
        (game_id, seat.player_id, info.commands.clone())
    };

    let (reply_tx, reply_rx) = oneshot::channel();
    commands
        .send(ActorMessage::EndGame {
            requesting_player_id: player_id,
            reason: "host ended the game".into(),
            reply: reply_tx,
        })
        .await
        .map_err(|_| ApiError::conflict("NO_ACTOR", "game actor unavailable"))?;
    let cleanup = reply_rx
        .await
        .map_err(|_| ApiError::conflict("END_DROPPED", "end-game reply dropped"))?
        .map_err(|e| ApiError::conflict("END_FAILED", e))?;

    {
        let mut rooms = state.rooms.lock().unwrap();
        if let Some(room) = rooms.get_mut(&room_id) {
            if room.status == RoomStatus::InGame(game_id) {
                apply_abort_to_lobby(room, &cleanup);
            }
        }
    }
    state.games.lock().unwrap().remove(&game_id);

    Ok(Json(EndGameResponse {
        game_id,
        aborted: true,
    }))
}

/// Host rematch while vacant: drop leavers, return to lobby; auto-start only if 4 remain.
pub async fn restart_game(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(room_ref): Path<String>,
) -> Result<Json<RestartGameResponse>, ApiError> {
    let session = state.session_from_headers(&headers)?;
    let room_id = state.resolve_room_id(&room_ref)?;

    let (old_game_id, player_id, commands) = {
        let rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get(&room_id)
            .ok_or_else(|| ApiError::not_found("room not found"))?;
        if room.host_session != session.id {
            return Err(ApiError::forbidden("only the host can restart the game"));
        }
        let RoomStatus::InGame(game_id) = room.status else {
            return Err(ApiError::conflict("NO_GAME", "no active game to restart"));
        };
        let seat = room
            .seat_of(session.id)
            .ok_or_else(|| ApiError::forbidden("not seated"))?;
        let games = state.games.lock().unwrap();
        let info = games
            .get(&game_id)
            .ok_or_else(|| ApiError::conflict("NO_ACTOR", "game actor not found"))?;
        (game_id, seat.player_id, info.commands.clone())
    };

    let (presence_tx, presence_rx) = oneshot::channel();
    commands
        .send(ActorMessage::QueryPresence {
            reply: presence_tx,
        })
        .await
        .map_err(|_| ApiError::conflict("NO_ACTOR", "game actor unavailable"))?;
    let presence = presence_rx
        .await
        .map_err(|_| ApiError::conflict("PRESENCE_DROPPED", "presence reply dropped"))?;
    if presence.ended {
        return Err(ApiError::conflict("GAME_OVER", "game is already over"));
    }
    let remaining = presence
        .seated_count
        .saturating_sub(presence.vacant_player_ids.len());
    if remaining == 0 {
        return Err(ApiError::conflict(
            "NO_PLAYERS",
            "no seated players left to restart",
        ));
    }

    let (abort_tx, abort_rx) = oneshot::channel();
    commands
        .send(ActorMessage::AbortForRestart {
            requesting_player_id: player_id,
            reply: abort_tx,
        })
        .await
        .map_err(|_| ApiError::conflict("NO_ACTOR", "game actor unavailable"))?;
    let cleanup = abort_rx
        .await
        .map_err(|_| ApiError::conflict("RESTART_DROPPED", "restart abort reply dropped"))?
        .map_err(|e| ApiError::conflict("RESTART_FAILED", e))?;

    {
        let mut rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get_mut(&room_id)
            .ok_or_else(|| ApiError::not_found("room not found"))?;
        apply_abort_to_lobby(room, &cleanup);
        // Remaining players stay ready so the host can start once a 4th joins
        // and partnerships are set again.
        for seat in &mut room.seats {
            seat.ready = true;
        }
    }
    state.games.lock().unwrap().remove(&old_game_id);
    drop(commands);

    // Classic Dehla is fixed 4 — after a vacancy, always return to lobby so a
    // human can reclaim/claim the open seat, then host starts a new match.
    let _ = remaining;
    Ok(Json(RestartGameResponse {
        old_game_id,
        game_id: None,
        returned_to_lobby: true,
    }))
}
