//! Abandonment GC for idle lobbies, vacant games, and finished-game TTL.

use std::sync::Arc;
use std::time::Duration;

use chrono::{Duration as ChronoDuration, Utc};

use crate::state::{AppState, RoomStatus};

/// Lobby rooms that never start are reaped after this TTL.
pub const LOBBY_TTL: Duration = Duration::from_secs(60 * 60);
/// Finished/aborted games are hard-deleted after this TTL.
pub const FINISHED_GAME_TTL: Duration = Duration::from_secs(24 * 60 * 60);
/// Orphan guest sessions older than this are deleted.
pub const ORPHAN_SESSION_TTL: Duration = Duration::from_secs(7 * 24 * 60 * 60);
/// How often the reaper scans.
pub const REAPER_INTERVAL: Duration = Duration::from_secs(30);

pub fn spawn_reaper(state: Arc<AppState>) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(REAPER_INTERVAL);
        loop {
            ticker.tick().await;
            reap_once(&state).await;
        }
    });
}

async fn reap_once(state: &AppState) {
    let now = Utc::now();
    let mut rooms_reaped = 0u64;
    let mut games_abandoned = 0u64;
    let mut games_purged = 0u64;

    // Snapshot candidates under the lock, mutate outside.
    let stale_lobbies: Vec<_> = {
        let rooms = state.rooms.lock().unwrap();
        rooms
            .values()
            .filter(|room| {
                matches!(room.status, RoomStatus::Lobby)
                    && now
                        .signed_duration_since(
                            room.seats
                                .iter()
                                .map(|s| s.joined_at)
                                .min()
                                .unwrap_or(now),
                        )
                        .to_std()
                        .unwrap_or_default()
                        >= LOBBY_TTL
            })
            .map(|r| (r.id, r.code.clone()))
            .collect()
    };

    for (room_id, code) in stale_lobbies {
        {
            let mut rooms = state.rooms.lock().unwrap();
            rooms.remove(&room_id);
        }
        state.room_codes.lock().unwrap().remove(&code);
        let _ = state.store.delete_room(room_id).await;
        rooms_reaped += 1;
    }

    // Drop closed game actor handles.
    let abandoned: Vec<_> = {
        let games = state.games.lock().unwrap();
        games
            .iter()
            .filter(|(_, info)| info.commands.is_closed())
            .map(|(id, info)| (*id, info.room_id))
            .collect()
    };
    for (game_id, _room_id) in abandoned {
        state.games.lock().unwrap().remove(&game_id);
        games_abandoned += 1;
    }

    // TTL purge finished/aborted games, then orphan in_game rooms.
    let cutoff = now - ChronoDuration::from_std(FINISHED_GAME_TTL).unwrap_or_default();
    if let Ok(terminal) = state.store.list_terminal_games_older_than(cutoff).await {
        for (game_id, room_id) in terminal {
            state.games.lock().unwrap().remove(&game_id);
            if let Err(error) = state.store.delete_game(game_id).await {
                tracing::warn!(%error, game = %game_id, "purge delete_game failed");
                continue;
            }
            games_purged += 1;

            let code = {
                let mut rooms = state.rooms.lock().unwrap();
                if let Some(room) = rooms.get(&room_id) {
                    if matches!(room.status, RoomStatus::InGame(id) if id == game_id) {
                        let code = room.code.clone();
                        rooms.remove(&room_id);
                        Some(code)
                    } else {
                        None
                    }
                } else {
                    None
                }
            };
            if let Some(code) = code {
                state.room_codes.lock().unwrap().remove(&code);
                let _ = state.store.delete_room(room_id).await;
                rooms_reaped += 1;
            }
        }
    }

    // Orphan in-game rooms with no live actor and no active DB game.
    let orphan_rooms: Vec<_> = {
        let rooms = state.rooms.lock().unwrap();
        let games = state.games.lock().unwrap();
        rooms
            .values()
            .filter_map(|room| match room.status {
                RoomStatus::InGame(game_id) if !games.contains_key(&game_id) => {
                    Some((room.id, room.code.clone(), game_id))
                }
                _ => None,
            })
            .collect()
    };
    for (room_id, code, game_id) in orphan_rooms {
        // Best-effort delete leftover game row.
        let _ = state.store.delete_game(game_id).await;
        state.rooms.lock().unwrap().remove(&room_id);
        state.room_codes.lock().unwrap().remove(&code);
        let _ = state.store.delete_room(room_id).await;
        rooms_reaped += 1;
    }

    let session_cutoff =
        now - ChronoDuration::from_std(ORPHAN_SESSION_TTL).unwrap_or_default();
    if let Ok(n) = state.store.delete_orphan_sessions(session_cutoff).await {
        if n > 0 {
            tracing::info!(deleted = n, "orphan guest_sessions purged");
        }
    }

    if rooms_reaped > 0 {
        state
            .metrics
            .rooms_reaped
            .fetch_add(rooms_reaped, std::sync::atomic::Ordering::Relaxed);
    }
    if games_abandoned > 0 {
        state
            .metrics
            .games_abandoned
            .fetch_add(games_abandoned, std::sync::atomic::Ordering::Relaxed);
    }
    if games_purged > 0 {
        state
            .metrics
            .games_purged
            .fetch_add(games_purged, std::sync::atomic::Ordering::Relaxed);
    }
    if rooms_reaped > 0 || games_abandoned > 0 || games_purged > 0 {
        tracing::info!(rooms_reaped, games_abandoned, games_purged, "reaper pass complete");
    }
}
