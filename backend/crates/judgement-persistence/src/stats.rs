//! Pure stat increments. Stores apply these only after an idempotent insert.

use std::cmp::Reverse;
use std::collections::{HashMap, HashSet};

use chrono::{DateTime, Datelike, Days, FixedOffset, Utc};
use uuid::Uuid;

use crate::{LeaderboardRow, MatchPulse};

pub const GOLD_POINTS: i64 = 500;
pub const SILVER_POINTS: i64 = 100;
pub const BRONZE_POINTS: i64 = 20;

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

/// One signed-in player's counted finishes. Guests and 2-player tables are absent.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MedalRecord {
    pub gold: i32,
    pub silver: i32,
    pub bronze: i32,
    pub games: i32,
    pub exact: i32,
    pub rounds: i32,
    pub score_points: i64,
    pub display_name: String,
}

impl MedalRecord {
    pub fn add(&mut self, finish_rank: i32, exact: i32, rounds: i32, score: i32) {
        self.games += 1;
        match finish_rank {
            1 => self.gold += 1,
            2 => self.silver += 1,
            3 => self.bronze += 1,
            _ => {}
        }
        self.exact = self.exact.saturating_add(exact);
        self.rounds = self.rounds.saturating_add(rounds);
        self.score_points += i64::from(score);
    }

    pub fn points(&self) -> i64 {
        medal_points(self.gold, self.silver, self.bronze)
    }

    pub fn has_podium(&self) -> bool {
        self.gold > 0 || self.silver > 0 || self.bronze > 0
    }

    /// Higher sorts first: points, gold, silver, bronze, gold%, bid%, then name A–Z.
    ///
    /// Gold% and bid% are exact ratios scaled by 1_000_000, so 15.3% stays above
    /// 15.2% even when the card rounds both to 15.3%. Postgres `ORDER BY` in
    /// `load_leaderboard` and the week-leader pick must use this same order.
    pub fn key(&self) -> (i64, i32, i32, i32, i64, i64, Reverse<&str>) {
        (
            self.points(),
            self.gold,
            self.silver,
            self.bronze,
            rate(self.gold, self.games),
            rate(self.exact, self.rounds),
            Reverse(self.display_name.as_str()),
        )
    }
}

pub fn medal_points(gold: i32, silver: i32, bronze: i32) -> i64 {
    i64::from(gold) * GOLD_POINTS
        + i64::from(silver) * SILVER_POINTS
        + i64::from(bronze) * BRONZE_POINTS
}

pub fn rate(numer: i32, denom: i32) -> i64 {
    if denom <= 0 {
        0
    } else {
        i64::from(numer) * 1_000_000 / i64::from(denom)
    }
}

/// Fold counted finishes into one record per signed-in player.
pub fn medals_from_finishes(
    finishes: &[PulseFinish],
    names: &HashMap<Uuid, String>,
) -> HashMap<Uuid, MedalRecord> {
    let mut by_user: HashMap<Uuid, MedalRecord> = HashMap::new();
    for finish in finishes {
        let rec = by_user.entry(finish.user_id).or_default();
        rec.add(
            finish.finish_rank,
            finish.exact_bid_rounds,
            finish.rounds_played,
            finish.total_score,
        );
    }
    for (user_id, rec) in &mut by_user {
        if let Some(name) = names.get(user_id) {
            rec.display_name = name.clone();
        }
    }
    by_user
}

pub fn to_leaderboard_row(
    user_id: Uuid,
    avatar_id: Option<String>,
    rec: &MedalRecord,
) -> LeaderboardRow {
    LeaderboardRow {
        user_id,
        display_name: rec.display_name.clone(),
        avatar_id,
        wins: rec.gold,
        games: rec.games,
        exact_percent: exact_percent(rec.exact, rec.rounds),
        average_score: average_score(rec.score_points, rec.games),
        gold: rec.gold,
        silver: rec.silver,
        bronze: rec.bronze,
        medal_points: rec.points(),
        exact: rec.exact,
        rounds: rec.rounds,
    }
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

/// One counted finish already stored. A 2-player or guest-only game is not a row.
#[derive(Debug, Clone)]
pub struct PulseFinish {
    pub game_id: Uuid,
    pub user_id: Uuid,
    pub finished_at: DateTime<Utc>,
    pub finish_rank: i32,
    pub exact_bid_rounds: i32,
    pub rounds_played: i32,
    pub total_score: i32,
}

fn india() -> FixedOffset {
    FixedOffset::east_opt(5 * 3600 + 30 * 60).expect("IST offset")
}

/// Today, this Monday, and the previous Monday, each at 00:00 India time as UTC.
pub fn india_bounds(now: DateTime<Utc>) -> (DateTime<Utc>, DateTime<Utc>, DateTime<Utc>) {
    let zone = india();
    let local = now.with_timezone(&zone);
    let today = local
        .date_naive()
        .and_hms_opt(0, 0, 0)
        .expect("midnight")
        .and_local_timezone(zone)
        .single()
        .expect("IST day")
        .with_timezone(&Utc);
    let back = u64::from(local.weekday().num_days_from_monday());
    let monday = local
        .date_naive()
        .checked_sub_days(Days::new(back))
        .expect("monday")
        .and_hms_opt(0, 0, 0)
        .expect("midnight")
        .and_local_timezone(zone)
        .single()
        .expect("IST week")
        .with_timezone(&Utc);
    let last_week = monday
        .checked_sub_days(Days::new(7))
        .expect("previous monday");
    (today, monday, last_week)
}

struct WeekTotals {
    games: HashSet<Uuid>,
    gold: i32,
    silver: i32,
    bronze: i32,
    exact: i32,
    rounds: i32,
}

impl Default for WeekTotals {
    fn default() -> Self {
        Self {
            games: HashSet::new(),
            gold: 0,
            silver: 0,
            bronze: 0,
            exact: 0,
            rounds: 0,
        }
    }
}

impl WeekTotals {
    fn to_medal(&self, display_name: String) -> MedalRecord {
        MedalRecord {
            gold: self.gold,
            silver: self.silver,
            bronze: self.bronze,
            games: self.games.len() as i32,
            exact: self.exact,
            rounds: self.rounds,
            score_points: 0,
            display_name,
        }
    }
}

/// Distinct ranked games. Three signed-in seats in one game count once.
pub fn match_pulse(
    finishes: &[PulseFinish],
    now: DateTime<Utc>,
    names: &HashMap<Uuid, String>,
) -> MatchPulse {
    let (today, week, last_week) = india_bounds(now);
    let mut all = HashSet::new();
    let mut today_games = HashSet::new();
    let mut week_games = HashSet::new();
    let mut last_week_games = HashSet::new();
    let mut week_players = HashSet::new();
    let mut since: Option<DateTime<Utc>> = None;
    let mut by_user: HashMap<Uuid, WeekTotals> = HashMap::new();
    let mut last_by_user: HashMap<Uuid, WeekTotals> = HashMap::new();

    for finish in finishes {
        all.insert(finish.game_id);
        if since.is_none_or(|earliest| finish.finished_at < earliest) {
            since = Some(finish.finished_at);
        }
        if finish.finished_at >= today {
            today_games.insert(finish.game_id);
        }
        if finish.finished_at >= week {
            week_games.insert(finish.game_id);
            week_players.insert(finish.user_id);
            record_week(&mut by_user, finish);
        } else if finish.finished_at >= last_week {
            last_week_games.insert(finish.game_id);
            record_week(&mut last_by_user, finish);
        }
    }

    let week_leader = pick_leader(&by_user, names);
    let last_leader = pick_leader(&last_by_user, names);

    MatchPulse {
        games_all: all.len() as i64,
        games_today: today_games.len() as i64,
        games_week: week_games.len() as i64,
        games_last_week: last_week_games.len() as i64,
        players_week: week_players.len() as i64,
        since,
        week_leader_name: week_leader.name,
        week_leader_wins: week_leader.gold,
        week_leader_points: week_leader.points,
        last_week_leader_name: last_leader.name,
        last_week_leader_wins: last_leader.gold,
        last_week_leader_points: last_leader.points,
    }
}

fn record_week(by_user: &mut HashMap<Uuid, WeekTotals>, finish: &PulseFinish) {
    let totals = by_user.entry(finish.user_id).or_default();
    totals.games.insert(finish.game_id);
    match finish.finish_rank {
        1 => totals.gold += 1,
        2 => totals.silver += 1,
        3 => totals.bronze += 1,
        _ => {}
    }
    totals.exact = totals.exact.saturating_add(finish.exact_bid_rounds);
    totals.rounds = totals.rounds.saturating_add(finish.rounds_played);
}

struct WeekLeader {
    name: Option<String>,
    gold: i64,
    points: i64,
}

fn pick_leader(by_user: &HashMap<Uuid, WeekTotals>, names: &HashMap<Uuid, String>) -> WeekLeader {
    let mut leader: Option<(MedalRecord, i64)> = None;
    for (user_id, totals) in by_user {
        let Some(name) = names.get(user_id).filter(|name| !name.is_empty()) else {
            continue;
        };
        let row = totals.to_medal(name.clone());
        if !row.has_podium() {
            continue;
        }
        let replace = match &leader {
            None => true,
            Some((current, _)) => row.key() > current.key(),
        };
        if replace {
            leader = Some((row, i64::from(totals.gold)));
        }
    }
    WeekLeader {
        name: leader.as_ref().map(|(row, _)| row.display_name.clone()),
        gold: leader.as_ref().map(|(_, gold)| *gold).unwrap_or(0),
        points: leader.as_ref().map(|(row, _)| row.points()).unwrap_or(0),
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

    fn medals(
        gold: i32,
        silver: i32,
        bronze: i32,
        games: i32,
        exact: i32,
        rounds: i32,
        name: &str,
    ) -> MedalRecord {
        MedalRecord {
            gold,
            silver,
            bronze,
            games,
            exact,
            rounds,
            score_points: 0,
            display_name: name.into(),
        }
    }

    #[test]
    fn one_gold_beats_four_silvers() {
        let gold = medals(1, 0, 0, 1, 0, 1, "A");
        let silvers = medals(0, 4, 0, 4, 0, 4, "B");
        assert_eq!(gold.points(), 500);
        assert_eq!(silvers.points(), 400);
        assert!(gold.key() > silvers.key());
    }

    #[test]
    fn equal_points_prefers_more_gold() {
        let one_gold = medals(1, 0, 0, 1, 0, 1, "A");
        let five_silver = medals(0, 5, 0, 5, 0, 5, "B");
        assert_eq!(one_gold.points(), five_silver.points());
        assert!(one_gold.key() > five_silver.key());
    }

    #[test]
    fn same_medals_break_on_gold_rate_then_bid_rate() {
        let higher_gold_rate = medals(2, 0, 0, 13, 0, 13, "A");
        let lower_gold_rate = medals(2, 0, 0, 14, 10, 14, "B");
        assert!(higher_gold_rate.key() > lower_gold_rate.key());

        let higher_bids = medals(2, 1, 1, 10, 8, 10, "Ada");
        let lower_bids = medals(2, 1, 1, 10, 5, 10, "Bea");
        assert!(higher_bids.key() > lower_bids.key());
    }

    #[test]
    fn equal_records_sort_by_name() {
        let ankit = medals(1, 0, 0, 1, 1, 1, "Ankit");
        let beena = medals(1, 0, 0, 1, 1, 1, "Beena");
        assert!(ankit.key() > beena.key());
    }

    #[test]
    fn board_rank_follows_gold_rate_when_medals_match() {
        let ada = Uuid::new_v4();
        let bea = Uuid::new_v4();
        let now = at(2026, 10, 20, 12, 0);
        let mut rows = Vec::new();
        for i in 0..10 {
            let game = Uuid::from_u128(i as u128 + 1);
            rows.push(seat(game, ada, now, if i < 2 { 1 } else { 4 }, 1, 8, 10));
        }
        for i in 0..20 {
            let game = Uuid::from_u128(i as u128 + 100);
            rows.push(seat(game, bea, now, if i < 2 { 1 } else { 4 }, 1, 8, 10));
        }
        let mut names = HashMap::new();
        names.insert(ada, "Ada".to_string());
        names.insert(bea, "Bea".to_string());
        let medals = medals_from_finishes(&rows, &names);
        let mut board: Vec<_> = medals.into_values().collect();
        board.sort_by(|a, b| b.key().cmp(&a.key()));
        assert_eq!(board[0].display_name, "Ada");
        assert_eq!(board[1].display_name, "Bea");
        assert_eq!(board[0].gold, 2);
        assert_eq!(board[1].gold, 2);
        assert!(board[0].games < board[1].games);
    }

    fn at(y: i32, m: u32, d: u32, h: u32, min: u32) -> DateTime<Utc> {
        chrono::NaiveDate::from_ymd_opt(y, m, d)
            .unwrap()
            .and_hms_opt(h, min, 0)
            .unwrap()
            .and_utc()
    }

    fn seat(
        game: Uuid,
        user: Uuid,
        at: DateTime<Utc>,
        rank: i32,
        exact: i32,
        rounds: i32,
        points: i32,
    ) -> PulseFinish {
        PulseFinish {
            game_id: game,
            user_id: user,
            finished_at: at,
            finish_rank: rank,
            exact_bid_rounds: exact,
            rounds_played: rounds,
            total_score: points,
        }
    }

    #[test]
    fn three_signed_in_seats_are_one_ranked_game() {
        let game = Uuid::new_v4();
        let when = at(2026, 10, 18, 12, 0);
        let rows = [
            seat(game, Uuid::new_v4(), when, 1, 1, 1, 10),
            seat(game, Uuid::new_v4(), when, 2, 0, 1, 0),
            seat(game, Uuid::new_v4(), when, 3, 0, 1, -5),
        ];
        let pulse = match_pulse(&rows, when, &HashMap::new());
        assert_eq!(pulse.games_all, 1);
        assert_eq!(pulse.since, Some(when));
    }

    #[test]
    fn midnight_in_india_splits_today_and_the_week() {
        // Tuesday 20 Oct 2026, 01:00 IST = 19 Oct 19:30 UTC.
        let now = at(2026, 10, 19, 19, 30);
        let (today, week, last_week) = india_bounds(now);
        assert_eq!(today, at(2026, 10, 19, 18, 30));
        // Monday 19 Oct 00:00 IST. Last week starts the Monday before.
        assert_eq!(week, at(2026, 10, 18, 18, 30));
        assert_eq!(last_week, at(2026, 10, 11, 18, 30));

        let game_today = Uuid::new_v4();
        let game_evening = Uuid::new_v4();
        let early = Uuid::new_v4();
        let monday = Uuid::new_v4();
        let ankit = Uuid::new_v4();
        let beena = Uuid::new_v4();
        // 00:30 IST Tuesday is today. 23:30 IST Monday is still Monday.
        let just_after_midnight = at(2026, 10, 19, 19, 0);
        let previous_evening = at(2026, 10, 19, 18, 0);
        // Sunday 18 Oct 23:00 IST is last week. Monday 00:30 IST is this week.
        let sunday_night = at(2026, 10, 18, 17, 30);
        let monday_morning = at(2026, 10, 18, 19, 0);
        let rows = [
            seat(game_today, ankit, just_after_midnight, 1, 4, 8, 40),
            seat(game_evening, ankit, previous_evening, 1, 4, 8, 20),
            seat(early, beena, sunday_night, 1, 8, 8, 30),
            seat(monday, ankit, monday_morning, 1, 4, 8, 10),
            seat(monday, beena, monday_morning, 2, 8, 8, 50),
        ];
        let mut names = HashMap::new();
        names.insert(ankit, "Ankit".to_string());
        names.insert(beena, "Beena".to_string());
        let pulse = match_pulse(&rows, now, &names);
        assert_eq!(pulse.games_all, 4);
        assert_eq!(pulse.games_today, 1);
        assert_eq!(pulse.games_week, 3);
        assert_eq!(pulse.games_last_week, 1);
        assert_eq!(pulse.players_week, 2);
        assert_eq!(pulse.since, Some(sunday_night));
        assert_eq!(pulse.week_leader_name.as_deref(), Some("Ankit"));
        assert_eq!(pulse.week_leader_wins, 3);
        assert_eq!(pulse.week_leader_points, 1_500);
        assert_eq!(pulse.last_week_leader_name.as_deref(), Some("Beena"));
        assert_eq!(pulse.last_week_leader_wins, 1);
        assert_eq!(pulse.last_week_leader_points, 500);
    }

    #[test]
    fn a_shared_first_counts_for_each_player_and_bids_break_the_tie() {
        let now = at(2026, 10, 21, 6, 30);
        let game = Uuid::new_v4();
        let when = at(2026, 10, 20, 4, 0);
        let ankit = Uuid::new_v4();
        let beena = Uuid::new_v4();
        let rows = [
            seat(game, ankit, when, 1, 2, 10, 10),
            seat(game, beena, when, 1, 8, 10, 10),
        ];
        let mut names = HashMap::new();
        names.insert(ankit, "Ankit".to_string());
        names.insert(beena, "Beena".to_string());
        let pulse = match_pulse(&rows, now, &names);
        assert_eq!(pulse.games_all, 1);
        assert_eq!(pulse.week_leader_name.as_deref(), Some("Beena"));
        assert_eq!(pulse.week_leader_wins, 1);
        assert_eq!(pulse.week_leader_points, 500);
    }

    #[test]
    fn a_bronze_only_week_still_has_a_leader() {
        let now = at(2026, 10, 21, 6, 30);
        let game = Uuid::new_v4();
        let when = at(2026, 10, 20, 4, 0);
        let cara = Uuid::new_v4();
        let rows = [seat(game, cara, when, 3, 1, 8, 10)];
        let mut names = HashMap::new();
        names.insert(cara, "Cara".to_string());
        let pulse = match_pulse(&rows, now, &names);
        assert_eq!(pulse.week_leader_name.as_deref(), Some("Cara"));
        assert_eq!(pulse.week_leader_wins, 0);
        assert_eq!(pulse.week_leader_points, 20);
    }

    #[test]
    fn a_week_with_no_podium_has_no_leader() {
        let now = at(2026, 10, 21, 6, 30);
        let game = Uuid::new_v4();
        let when = at(2026, 10, 20, 4, 0);
        let cara = Uuid::new_v4();
        let rows = [seat(game, cara, when, 4, 1, 8, 10)];
        let mut names = HashMap::new();
        names.insert(cara, "Cara".to_string());
        let pulse = match_pulse(&rows, now, &names);
        assert_eq!(pulse.games_week, 1);
        assert!(pulse.week_leader_name.is_none());
        assert_eq!(pulse.week_leader_points, 0);
    }

    #[test]
    fn no_stored_finish_has_no_leader_and_no_since() {
        let pulse = match_pulse(&[], at(2026, 10, 20, 0, 0), &HashMap::new());
        assert_eq!(pulse.games_all, 0);
        assert_eq!(pulse.games_today, 0);
        assert_eq!(pulse.games_week, 0);
        assert!(pulse.since.is_none());
        assert!(pulse.week_leader_name.is_none());
    }
}
