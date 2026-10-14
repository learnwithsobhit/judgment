//! Pure stat increments. Stores apply these only after an idempotent insert.

use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct SeatFinish {
    pub user_id: Uuid,
    pub finish_rank: i32,
    pub total_score: i32,
    pub exact_bid_rounds: i32,
    pub tricks_missed: i32,
}

#[derive(Debug, Clone, Default)]
pub struct UserStatsRow {
    pub games_played: i32,
    pub wins: i32,
    pub ranked_wins: i32,
    pub ranked_games: i32,
    pub lifetime_points: i64,
    pub ranked_points: i64,
    pub rounds_played: i32,
    pub exact_bid_rounds: i32,
    pub ranked_rounds: i32,
    pub ranked_exact: i32,
}

/// Unset or any value other than `0` / `false` records stats.
pub fn stats_enabled() -> bool {
    match std::env::var("STATS_ENABLED") {
        Ok(value) => {
            let value = value.trim();
            value != "0" && !value.eq_ignore_ascii_case("false")
        }
        Err(_) => true,
    }
}

pub fn apply_finish(row: &mut UserStatsRow, seat: &SeatFinish, rounds: i32, counted: bool) {
    row.games_played += 1;
    if seat.finish_rank == 1 {
        row.wins += 1;
    }
    row.lifetime_points += i64::from(seat.total_score);
    row.rounds_played += rounds;
    row.exact_bid_rounds += seat.exact_bid_rounds;
    if counted {
        row.ranked_games += 1;
        if seat.finish_rank == 1 {
            row.ranked_wins += 1;
        }
        row.ranked_points += i64::from(seat.total_score);
        row.ranked_rounds += rounds;
        row.ranked_exact += seat.exact_bid_rounds;
    }
}

/// Higher sorts first: wins, then exact-bid rate, then average score.
pub fn ladder_key(row: &UserStatsRow) -> (i32, i64, i64) {
    let strike = if row.ranked_rounds == 0 {
        0
    } else {
        i64::from(row.ranked_exact) * 1_000_000 / i64::from(row.ranked_rounds)
    };
    let average = if row.ranked_games == 0 {
        0
    } else {
        row.ranked_points / i64::from(row.ranked_games)
    };
    (row.ranked_wins, strike, average)
}

pub fn exact_percent(exact: i32, rounds: i32) -> i32 {
    if rounds <= 0 {
        0
    } else {
        exact.saturating_mul(100) / rounds
    }
}

pub fn average_score(points: i64, games: i32) -> i32 {
    if games <= 0 {
        0
    } else {
        (points / i64::from(games)) as i32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counted_finish_moves_ranked_and_lifetime() {
        let mut row = UserStatsRow::default();
        apply_finish(
            &mut row,
            &SeatFinish {
                user_id: Uuid::nil(),
                finish_rank: 1,
                total_score: 40,
                exact_bid_rounds: 3,
                tricks_missed: 1,
            },
            5,
            true,
        );
        assert_eq!(row.games_played, 1);
        assert_eq!(row.wins, 1);
        assert_eq!(row.ranked_wins, 1);
        assert_eq!(row.lifetime_points, 40);
        assert_eq!(exact_percent(row.exact_bid_rounds, row.rounds_played), 60);
    }

    #[test]
    fn short_table_stays_off_the_board() {
        let mut row = UserStatsRow::default();
        apply_finish(
            &mut row,
            &SeatFinish {
                user_id: Uuid::nil(),
                finish_rank: 1,
                total_score: 10,
                exact_bid_rounds: 1,
                tricks_missed: 0,
            },
            1,
            false,
        );
        assert_eq!(row.wins, 1);
        assert_eq!(row.ranked_wins, 0);
        assert_eq!(row.ranked_games, 0);
    }
}
