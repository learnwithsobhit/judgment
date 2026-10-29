//! Background Top 10 snapshot. Landing reads the copy and does not query Postgres.

use std::sync::Arc;
use std::time::Duration;

use judgement_persistence::{LeaderboardRow, MatchPulse};
use judgement_protocol::{LeaderboardPulse, RoomView};
use uuid::Uuid;

use crate::state::{AppState, RoomStatus};

/// Board place shown as a cap. Only the first three rows qualify.
pub fn ladder_rank(user_id: Uuid, board: &[LeaderboardRow]) -> Option<u8> {
    board
        .iter()
        .take(3)
        .enumerate()
        .find_map(|(index, row)| (row.user_id == user_id).then_some(index as u8 + 1))
}

/// Fill each lobby seat from the account sitting there. Guests stay unset.
/// Also marks which seats are signed in (account status, not online).
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
        seat.signed_in = user_id.is_some();
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

/// A lobby with someone seated and a free chair. An empty room is not filling up.
pub fn is_open_table(lobby: bool, seated: usize, max_players: u8) -> bool {
    lobby && seated > 0 && seated < usize::from(max_players)
}

fn open_table_count(state: &AppState) -> i64 {
    let rooms = state.rooms.lock().unwrap();
    rooms
        .values()
        .filter(|room| {
            is_open_table(
                matches!(room.status, RoomStatus::Lobby),
                room.seats.len(),
                room.max_players,
            )
        })
        .count() as i64
}

/// A failed count leaves the previous pulse. `loaded` is `None` in that case.
pub fn store_pulse(
    current: &mut Option<LeaderboardPulse>,
    loaded: Option<MatchPulse>,
    open_tables: i64,
) {
    let Some(loaded) = loaded else {
        return;
    };
    *current = Some(LeaderboardPulse {
        games_today: loaded.games_today,
        games_week: loaded.games_week,
        games_last_week: loaded.games_last_week,
        games_all: loaded.games_all,
        players_week: loaded.players_week,
        since: loaded.since,
        week_leader_name: loaded.week_leader_name,
        week_leader_wins: loaded.week_leader_wins,
        last_week_leader_name: loaded.last_week_leader_name,
        last_week_leader_wins: loaded.last_week_leader_wins,
        open_tables,
    });
}

pub async fn refresh_leaderboard(state: &AppState) {
    match state.store.load_leaderboard(0).await {
        Ok(rows) => {
            *state.leaderboard.lock().unwrap() = Arc::new(rows);
        }
        Err(error) => tracing::warn!(%error, "leaderboard refresh failed"),
    }
    let loaded = match state.store.load_match_pulse().await {
        Ok(pulse) => Some(pulse),
        Err(error) => {
            tracing::warn!(%error, "match pulse refresh failed");
            None
        }
    };
    let open_tables = open_table_count(state);
    let mut current = state.table_pulse.lock().unwrap();
    store_pulse(&mut current, loaded, open_tables);
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

    #[test]
    fn an_empty_lobby_is_not_a_table_filling_up() {
        assert!(!is_open_table(true, 0, 4));
        assert!(is_open_table(true, 1, 4));
        assert!(!is_open_table(true, 4, 4));
        assert!(!is_open_table(false, 1, 4));
    }

    #[test]
    fn a_failed_pulse_keeps_the_previous_one() {
        let previous = LeaderboardPulse {
            games_today: 2,
            games_week: 5,
            games_last_week: 11,
            games_all: 9,
            players_week: 4,
            since: None,
            week_leader_name: Some("Ankit".into()),
            week_leader_wins: 3,
            last_week_leader_name: Some("Beena".into()),
            last_week_leader_wins: 4,
            open_tables: 1,
        };
        let mut current = Some(previous.clone());
        store_pulse(&mut current, None, 0);
        let kept = current.as_ref().expect("previous pulse");
        assert_eq!(kept.games_all, 9);
        assert_eq!(kept.week_leader_name.as_deref(), Some("Ankit"));
        assert_eq!(kept.open_tables, 1);

        store_pulse(
            &mut current,
            Some(MatchPulse {
                games_all: 10,
                games_today: 1,
                games_week: 6,
                players_week: 4,
                ..MatchPulse::default()
            }),
            0,
        );
        let updated = current.expect("new pulse");
        assert_eq!(updated.games_all, 10);
        assert_eq!(updated.open_tables, 0);
        assert!(updated.week_leader_name.is_none());
    }
}
