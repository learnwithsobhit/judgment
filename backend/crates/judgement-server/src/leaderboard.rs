//! Background Top 10 snapshot. Landing reads the copy and does not query Postgres.

use std::sync::Arc;
use std::time::Duration;

use judgement_persistence::LeaderboardRow;
use judgement_protocol::RoomView;
use uuid::Uuid;

use crate::state::AppState;

/// Board place shown as a cap. Only the first three rows qualify.
pub fn ladder_rank(user_id: Uuid, board: &[LeaderboardRow]) -> Option<u8> {
    board.iter().take(3).enumerate().find_map(|(index, row)| {
        (row.user_id == user_id).then_some(index as u8 + 1)
    })
}

/// Fill each lobby seat from the account sitting there. Guests stay unset.
pub fn stamp_room_ladder_ranks(state: &AppState, view: &mut RoomView) {
    let pairs: Vec<_> = {
        let rooms = state.rooms.lock().unwrap();
        let Some(room) = rooms.get(&view.room_id) else {
            return;
        };
        room.seats
            .iter()
            .map(|seat| (seat.player_id, seat.session_id))
            .collect()
    };
    let sessions = state.sessions.lock().unwrap();
    let board = state.leaderboard.lock().unwrap().clone();
    for seat in &mut view.seats {
        let user_id = pairs
            .iter()
            .find(|(player_id, _)| *player_id == seat.player_id)
            .and_then(|(_, session_id)| sessions.get(session_id))
            .and_then(|session| session.user_id);
        seat.ladder_rank = user_id.and_then(|id| ladder_rank(id, &board));
    }
}

pub const REFRESH_INTERVAL: Duration = Duration::from_secs(45);

pub fn spawn_leaderboard_refresh(state: Arc<AppState>) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(REFRESH_INTERVAL);
        loop {
            ticker.tick().await;
            refresh_leaderboard(&state).await;
        }
    });
}

pub async fn refresh_leaderboard(state: &AppState) {
    match state.store.load_leaderboard(10).await {
        Ok(rows) => {
            *state.leaderboard.lock().unwrap() = Arc::new(rows);
        }
        Err(error) => tracing::warn!(%error, "leaderboard refresh failed"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(user_id: Uuid) -> LeaderboardRow {
        LeaderboardRow {
            user_id,
            display_name: "Ada".into(),
            avatar_id: None,
            wins: 1,
            games: 1,
            exact_percent: 0,
            average_score: 0,
        }
    }

    #[test]
    fn only_the_first_three_rows_get_a_cap() {
        let first = Uuid::new_v4();
        let second = Uuid::new_v4();
        let third = Uuid::new_v4();
        let fourth = Uuid::new_v4();
        let guest = Uuid::new_v4();
        let board = vec![row(first), row(second), row(third), row(fourth)];
        assert_eq!(ladder_rank(first, &board), Some(1));
        assert_eq!(ladder_rank(second, &board), Some(2));
        assert_eq!(ladder_rank(third, &board), Some(3));
        assert_eq!(ladder_rank(fourth, &board), None);
        assert_eq!(ladder_rank(guest, &board), None);
    }
}
