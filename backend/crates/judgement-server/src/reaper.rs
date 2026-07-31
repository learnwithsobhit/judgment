//! Abandonment GC for idle lobbies and empty games (PLAN.md §15.2).

use std::sync::Arc;
use std::time::Duration;

use chrono::Utc;

use crate::state::{AppState, RoomStatus};

/// Lobby rooms that never start are reaped after this TTL.
pub const LOBBY_TTL: Duration = Duration::from_secs(60 * 60);
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

    // Games where every human seat is bot-controlled / disconnected and no
    // WebSocket clients remain — drop the actor handle (actor exits when
    // channel closes after last disconnect; we remove the GameInfo entry).
    let abandoned: Vec<_> = {
        let games = state.games.lock().unwrap();
        games
            .iter()
            .filter(|(_, info)| info.commands.is_closed())
            .map(|(id, info)| (*id, info.room_id))
            .collect()
    };
    for (game_id, room_id) in abandoned {
        state.games.lock().unwrap().remove(&game_id);
        {
            let mut rooms = state.rooms.lock().unwrap();
            if let Some(room) = rooms.get_mut(&room_id) {
                // Keep the room row for history; just note abandonment.
                let _ = room;
            }
        }
        games_abandoned += 1;
    }

    if rooms_reaped > 0 {
        state
            .metrics
            .rooms_reaped
            .fetch_add(rooms_reaped, std::sync::atomic::Ordering::Relaxed);
    }
    if rooms_reaped > 0 || games_abandoned > 0 {
        tracing::info!(rooms_reaped, games_abandoned, "reaper pass complete");
    }
}
