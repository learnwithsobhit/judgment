//! Boot-time restoration of sessions, rooms, and active game actors
//! (PLAN.md §14.2 Phase 5 exit criteria).

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use judgement_domain::{GameId, PlayerId};
use judgement_engine::GameEngine;
use judgement_persistence::{GameStore, RestoredGame};

use crate::actor::{spawn_game_actor, SpawnActor};
use crate::cleanup::{make_aborted_hook, make_finished_hook, make_host_changed_hook};
use crate::state::{AppState, GameInfo, Room, RoomSeat, RoomStatus, ScheduledEvent, Session};

/// Reload durable state into memory and respawn actors for active games.
pub async fn restore_from_store(
    state: &Arc<AppState>,
) -> Result<usize, judgement_persistence::PersistError> {
    let sessions = state.store.load_sessions().await?;
    {
        let mut session_map = state.sessions.lock().unwrap();
        let mut tokens = state.tokens.lock().unwrap();
        for session in sessions {
            tokens.insert(session.token.clone(), session.session_id);
            session_map.insert(
                session.session_id,
                Session {
                    id: session.session_id,
                    nickname: session.nickname,
                    token: session.token,
                    avatar_id: session.avatar_id,
                },
            );
        }
    }

    let rooms = state.store.load_rooms().await?;
    {
        let mut room_map = state.rooms.lock().unwrap();
        let mut codes = state.room_codes.lock().unwrap();
        for stored in rooms {
            codes.insert(stored.code.clone(), stored.room_id);
            let status = match stored.game_id {
                Some(game_id) if stored.phase == "in_game" => RoomStatus::InGame(game_id),
                _ => RoomStatus::Lobby,
            };
            room_map.insert(
                stored.room_id,
                Room {
                    id: stored.room_id,
                    code: stored.code,
                    host_session: stored.host_session_id,
                    seats: stored
                        .players
                        .into_iter()
                        .map(|p| RoomSeat {
                            session_id: p.session_id,
                            player_id: p.player_id,
                            nickname: p.nickname,
                            seat: p.seat,
                            ready: p.ready,
                            joined_at: p.joined_at,
                            avatar_id: p.avatar_id,
                        })
                        .collect(),
                    status,
                    max_players: stored.max_players,
                    turn_timeout_seconds: stored.turn_timeout_seconds,
                    first_trump: stored.first_trump,
                    round_schedule: stored.round_schedule,
                    dealer_total_restriction: stored.dealer_total_restriction,
                    spectators_allowed: false,
                    list_on_live_now: false,
                },
            );
        }
    }

    let scheduled = state.store.load_scheduled_events().await?;
    {
        let mut events = state.events.lock().unwrap();
        for stored in scheduled {
            let event = ScheduledEvent::from_stored(stored);
            events.insert(event.id, event);
        }
    }

    let active = state.store.load_active_games().await?;
    let restored = active.len();
    for game in active {
        let game_id = game.game_id;
        spawn_restored_actor(state, game)?;
        tracing::info!(game = %game_id, "restored active game actor");
    }

    Ok(restored)
}

/// Respawn a single active game actor from the tip snapshot (reaper / crash recovery).
pub async fn respawn_game_actor(
    state: &Arc<AppState>,
    game_id: GameId,
) -> Result<bool, judgement_persistence::PersistError> {
    let Some(game) = state.store.load_active_game(game_id).await? else {
        return Ok(false);
    };
    spawn_restored_actor(state, game)?;
    state
        .metrics
        .actors_respawned
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    tracing::warn!(game = %game_id, "respawned dead game actor from tip snapshot");
    Ok(true)
}

fn spawn_restored_actor(
    state: &Arc<AppState>,
    game: RestoredGame,
) -> Result<(), judgement_persistence::PersistError> {
    let game_id = game.game_id;
    let engine = GameEngine::from_restored_state(game.state);
    // Always restore with a fresh secure shuffler. Re-seeding ChaCha from
    // the original seed would reshuffle future deals as if from round 1
    // (Phase 5 audit). The current deal is already in the snapshot.
    let _ = game.seed;
    engine
        .check_invariants()
        .map_err(|e| {
            judgement_persistence::PersistError::Conflict(format!(
                "restored game {game_id} failed invariants: {e}"
            ))
        })?;

    let turn_timeout = game
        .rules
        .turn_timeout_seconds
        .map(|t| Duration::from_secs(t as u64));
    let reconnect_grace = Duration::from_secs(game.rules.reconnect_grace_seconds as u64);
    let processed: HashMap<_, _> = game.processed_actions.into_iter().collect();

    let host_player_id = resolve_host_player_id(state, game.room_id, &game.players);
    let room_code = {
        let rooms = state.rooms.lock().unwrap();
        rooms
            .get(&game.room_id)
            .map(|r| r.code.clone())
            .unwrap_or_default()
    };
    let commands = spawn_game_actor(SpawnActor {
        engine,
        turn_timeout,
        reconnect_grace,
        store: Some(state.store.clone()),
        processed,
        host_player_id,
        metrics: state.metrics.clone(),
        room_code,
        on_host_changed: Some(make_host_changed_hook(state.clone(), game.room_id)),
        on_aborted: Some(make_aborted_hook(state.clone(), game.room_id)),
        on_finished: Some(make_finished_hook(state.clone())),
    });

    let players: HashMap<_, _> = game
        .players
        .into_iter()
        .map(|p| (p.session_id, p.player_id))
        .collect();

    state.games.lock().unwrap().insert(
        game_id,
        GameInfo {
            room_id: game.room_id,
            players,
            spectators: HashMap::new(),
            commands,
        },
    );
    Ok(())
}

/// Prefer room host_session → seated player; fall back to lowest seat.
fn resolve_host_player_id(
    state: &AppState,
    room_id: judgement_domain::RoomId,
    players: &[judgement_persistence::NewGamePlayer],
) -> PlayerId {
    let host_session = {
        let rooms = state.rooms.lock().unwrap();
        rooms.get(&room_id).map(|r| r.host_session)
    };
    if let Some(host_session) = host_session {
        if let Some(p) = players.iter().find(|p| p.session_id == host_session) {
            return p.player_id;
        }
    }
    players
        .first()
        .map(|p| p.player_id)
        .expect("restored game has players")
}

/// Convenience for tests: build AppState and restore in one step.
pub async fn bootstrap(
    store: Arc<dyn GameStore>,
) -> Result<Arc<AppState>, judgement_persistence::PersistError> {
    let state = Arc::new(AppState::new(store));
    restore_from_store(&state).await?;
    Ok(state)
}
