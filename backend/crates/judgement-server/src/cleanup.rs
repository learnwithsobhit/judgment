//! Post-abort room / actor cleanup (vacancy end, host end, restart prep).

use std::sync::Arc;
use std::time::{Duration, Instant};

use judgement_domain::{GameId, PlayerId, RoomId};

use crate::actor::AbortedCleanup;
use crate::persist::stored_room;
use crate::state::{AppState, RoomStatus};

/// Minimum gap between host restarts in the same room (load guard).
pub const RESTART_COOLDOWN: Duration = Duration::from_secs(30);

pub fn make_host_changed_hook(
    state: Arc<AppState>,
    room_id: RoomId,
) -> Arc<dyn Fn(PlayerId) + Send + Sync> {
    Arc::new(move |new_host: PlayerId| {
        let snapshot = {
            let mut rooms = state.rooms.lock().unwrap();
            let Some(room) = rooms.get_mut(&room_id) else {
                return;
            };
            let Some(seat) = room.seats.iter().find(|s| s.player_id == new_host) else {
                return;
            };
            room.host_session = seat.session_id;
            stored_room(room)
        };
        let store = state.store.clone();
        tokio::spawn(async move {
            if let Err(error) = store.upsert_room(&snapshot).await {
                tracing::warn!(%error, room = %room_id, "persist host_session after migrate failed");
            }
        });
    })
}

pub fn make_aborted_hook(
    state: Arc<AppState>,
    room_id: RoomId,
) -> Arc<dyn Fn(AbortedCleanup) + Send + Sync> {
    Arc::new(move |info: AbortedCleanup| {
        apply_aborted_cleanup(&state, room_id, &info);
    })
}

/// Drop actor map entry after natural finish (keeps room/result; frees admission).
pub fn make_finished_hook(state: Arc<AppState>) -> Arc<dyn Fn(GameId) + Send + Sync> {
    Arc::new(move |game_id: GameId| {
        if state.games.lock().unwrap().remove(&game_id).is_some() {
            state
                .metrics
                .games_removed
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
    })
}

/// Drop actor map entry, prune vacant seats, return room to Lobby, persist.
pub fn apply_aborted_cleanup(state: &AppState, room_id: RoomId, info: &AbortedCleanup) {
    state.games.lock().unwrap().remove(&info.game_id);
    state
        .metrics
        .games_removed
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    let snapshot = {
        let mut rooms = state.rooms.lock().unwrap();
        let Some(room) = rooms.get_mut(&room_id) else {
            return;
        };
        // Only clear InGame for this aborted game (ignore if already restarted).
        if room.status != RoomStatus::InGame(info.game_id) {
            return;
        }
        room.seats
            .retain(|s| !info.vacant_player_ids.contains(&s.player_id));
        // Compact seat numbers 0..n-1.
        room.seats.sort_by_key(|s| s.seat);
        for (idx, seat) in room.seats.iter_mut().enumerate() {
            seat.seat = idx as u8;
            seat.ready = false;
        }
        if let Some(host_seat) = room
            .seats
            .iter()
            .find(|s| s.player_id == info.host_player_id)
            .or_else(|| room.seats.first())
        {
            room.host_session = host_seat.session_id;
        }
        room.status = RoomStatus::Lobby;
        stored_room(room)
    };

    let store = state.store.clone();
    let room_id = room_id;
    tokio::spawn(async move {
        if let Err(error) = store.upsert_room(&snapshot).await {
            tracing::warn!(%error, room = %room_id, "persist lobby after abort failed");
        }
    });
}

/// Returns Err message if the room restarted too recently.
pub fn check_restart_rate_limit(state: &AppState, room_id: RoomId) -> Result<(), String> {
    let guard = state.restart_limits.lock().unwrap();
    let now = Instant::now();
    if let Some(last) = guard.get(&room_id) {
        if now.duration_since(*last) < RESTART_COOLDOWN {
            let wait = RESTART_COOLDOWN
                .checked_sub(now.duration_since(*last))
                .unwrap_or_default()
                .as_secs()
                .max(1);
            return Err(format!("restart available again in {wait}s"));
        }
    }
    Ok(())
}

pub fn record_restart(state: &AppState, room_id: RoomId) {
    let mut guard = state.restart_limits.lock().unwrap();
    let now = Instant::now();
    guard.insert(room_id, now);
    guard.retain(|_, t| now.duration_since(*t) < Duration::from_secs(600));
}
