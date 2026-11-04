//! Fair play awards: private peer ratings, public aggregates only.

use chrono::{DateTime, Duration, Utc};
use uuid::Uuid;

/// Unset or any value other than `0` / `false` enables fair play.
pub fn fair_play_enabled() -> bool {
    match std::env::var("FAIR_PLAY_ENABLED") {
        Ok(value) => {
            let value = value.trim();
            value != "0" && !value.eq_ignore_ascii_case("false")
        }
        Err(_) => true,
    }
}

pub const VOTE_WINDOW: Duration = Duration::hours(24);

#[derive(Debug, Clone)]
pub struct FairPlayRosterSeat {
    pub game_id: Uuid,
    pub user_id: Uuid,
    pub player_id: Uuid,
    pub display_name: String,
    pub avatar_id: Option<String>,
    pub finished_at: DateTime<Utc>,
}

#[derive(Debug, Clone)]
pub struct FairPlayRating {
    pub target_user_id: Uuid,
    pub points: i16,
}

#[derive(Debug, Clone)]
pub struct FairPlayGameTotal {
    pub user_id: Uuid,
    pub display_name: String,
    pub avatar_id: Option<String>,
    pub points: i32,
    pub ratings: i32,
}

#[derive(Debug, Clone)]
pub struct FairPlayLeaderboardRow {
    pub user_id: Uuid,
    pub display_name: String,
    pub avatar_id: Option<String>,
    pub points_received: i32,
    pub ratings_received: i32,
    pub games_rated: i32,
}

#[derive(Debug, Clone, Default)]
pub struct FairPlayStatsRow {
    pub points_received: i32,
    pub ratings_received: i32,
    pub games_rated: i32,
}

/// Higher sorts first: average×1e6, then matches rated in, then rating count.
pub fn fair_play_board_key(row: &FairPlayStatsRow) -> (i64, i32, i32) {
    let average = if row.ratings_received == 0 {
        0
    } else {
        i64::from(row.points_received) * 1_000_000 / i64::from(row.ratings_received)
    };
    (average, row.games_rated, row.ratings_received)
}

pub fn average_points(points: i32, ratings: i32) -> f64 {
    if ratings <= 0 {
        0.0
    } else {
        f64::from(points) / f64::from(ratings)
    }
}

pub fn vote_window_open(finished_at: DateTime<Utc>, now: DateTime<Utc>) -> bool {
    now <= finished_at + VOTE_WINDOW
}

/// Validate a full ballot set against the roster (excluding the voter).
pub fn validate_ratings(
    voter: Uuid,
    roster: &[FairPlayRosterSeat],
    ratings: &[FairPlayRating],
) -> Result<(), &'static str> {
    let targets: Vec<_> = roster
        .iter()
        .filter(|seat| seat.user_id != voter)
        .map(|seat| seat.user_id)
        .collect();
    if targets.is_empty() {
        return Err("no one else to rate");
    }
    if ratings.len() != targets.len() {
        return Err("rate every other signed-in player");
    }
    let mut seen = std::collections::HashSet::new();
    for rating in ratings {
        if rating.target_user_id == voter {
            return Err("you cannot rate yourself");
        }
        if !(0..=10).contains(&rating.points) {
            return Err("points must be 0 to 10");
        }
        if !targets.contains(&rating.target_user_id) {
            return Err("unknown player");
        }
        if !seen.insert(rating.target_user_id) {
            return Err("duplicate rating");
        }
    }
    if seen.len() != targets.len() {
        return Err("rate every other signed-in player");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seat(user: u8, name: &str) -> FairPlayRosterSeat {
        FairPlayRosterSeat {
            game_id: Uuid::nil(),
            user_id: Uuid::from_u128(user as u128),
            player_id: Uuid::from_u128(100 + user as u128),
            display_name: name.into(),
            avatar_id: None,
            finished_at: Utc::now(),
        }
    }

    #[test]
    fn full_ballot_is_valid() {
        let roster = vec![seat(1, "A"), seat(2, "B"), seat(3, "C")];
        let voter = Uuid::from_u128(1);
        let ratings = vec![
            FairPlayRating {
                target_user_id: Uuid::from_u128(2),
                points: 8,
            },
            FairPlayRating {
                target_user_id: Uuid::from_u128(3),
                points: 10,
            },
        ];
        assert!(validate_ratings(voter, &roster, &ratings).is_ok());
    }

    #[test]
    fn self_vote_rejected() {
        let roster = vec![seat(1, "A"), seat(2, "B")];
        let voter = Uuid::from_u128(1);
        let ratings = vec![FairPlayRating {
            target_user_id: voter,
            points: 10,
        }];
        assert!(validate_ratings(voter, &roster, &ratings).is_err());
    }
}
