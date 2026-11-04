//! In-memory store for unit tests and DATABASE_URL-less local runs.
//! Persistence still follows the same commit API as Postgres.

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;

use chrono::Utc;

use async_trait::async_trait;
use judgement_domain::{ActionId, EventId, GameId, PlayerId, RoomId, SessionId};
use judgement_engine::GameEvent;
use uuid::Uuid;

use crate::error::PersistError;
use crate::fair_play::{
    fair_play_board_key, fair_play_enabled, FairPlayGameTotal, FairPlayLeaderboardRow,
    FairPlayRating, FairPlayRosterSeat, FairPlayStatsRow,
};
use crate::models::*;
use crate::stats::{
    apply_finish, match_pulse, medals_from_finishes, stats_enabled, to_leaderboard_row,
    PulseFinish, SeatFinish, UserStatsRow,
};
use crate::GameStore;

#[derive(Default)]
pub struct MemoryStore {
    inner: Mutex<MemoryInner>,
}

#[derive(Default)]
struct MemoryInner {
    sessions: HashMap<SessionKey, StoredSession>,
    rooms: HashMap<RoomId, StoredRoom>,
    games: HashMap<GameId, StoredGame>,
    scheduled_events: HashMap<EventId, StoredScheduledEvent>,
    users: HashMap<Uuid, StoredUser>,
    /// `(provider, subject)` so the same subject string on two providers
    /// stays two accounts.
    identities: HashMap<(String, String), Uuid>,
    stats: HashMap<Uuid, UserStatsRow>,
    /// (game_id, user_id) already applied. Survives delete_game.
    recorded: HashSet<(Uuid, Uuid)>,
    /// Counted finishes kept so a local run can answer the same pulse as Postgres.
    pulse: Vec<PulseFinish>,
    fair_play_rosters: HashMap<Uuid, Vec<FairPlayRosterSeat>>,
    fair_play_submissions: HashSet<(Uuid, Uuid)>,
    /// (game_id, voter, target) → points
    fair_play_ballots: HashMap<(Uuid, Uuid, Uuid), i16>,
    fair_play_stats: HashMap<Uuid, FairPlayStatsRow>,
}

type SessionKey = uuid::Uuid;

struct StoredGame {
    record: NewGameMeta,
    players: Vec<NewGamePlayer>,
    events: Vec<StoredEvent>,
    /// version → state
    snapshots: HashMap<u64, InternalStateBlob>,
    round_results: Vec<RoundResultRecord>,
    game_result: Option<GameResultRecord>,
    status: String,
    pace: Vec<StoredPlayerPace>,
}

struct NewGameMeta {
    room_id: RoomId,
    rules: judgement_domain::GameRules,
    seed: Option<u64>,
    created_at: chrono::DateTime<Utc>,
}

#[allow(dead_code)]
struct StoredEvent {
    state_version: u64,
    event_index: u16,
    action_id: Option<ActionId>,
    payload: GameEvent,
}

type InternalStateBlob = judgement_engine::InternalGameState;

impl MemoryStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// Seed counted finishes so tests can exercise `load_latest_game`
    /// without playing a full table.
    pub fn seed_counted_finishes(&self, finishes: Vec<PulseFinish>) {
        self.inner.lock().unwrap().pulse.extend(finishes);
    }
}

#[async_trait]
impl GameStore for MemoryStore {
    async fn upsert_session(&self, session: &StoredSession) -> Result<(), PersistError> {
        self.inner
            .lock()
            .unwrap()
            .sessions
            .insert(session.session_id.0, session.clone());
        Ok(())
    }

    async fn upsert_room(&self, room: &StoredRoom) -> Result<(), PersistError> {
        self.inner
            .lock()
            .unwrap()
            .rooms
            .insert(room.room_id, room.clone());
        Ok(())
    }

    async fn delete_room(&self, room_id: RoomId) -> Result<(), PersistError> {
        self.inner.lock().unwrap().rooms.remove(&room_id);
        Ok(())
    }

    async fn load_sessions(&self) -> Result<Vec<StoredSession>, PersistError> {
        Ok(self
            .inner
            .lock()
            .unwrap()
            .sessions
            .values()
            .cloned()
            .collect())
    }

    async fn load_rooms(&self) -> Result<Vec<StoredRoom>, PersistError> {
        Ok(self.inner.lock().unwrap().rooms.values().cloned().collect())
    }

    async fn create_game(&self, record: &NewGame) -> Result<(), PersistError> {
        let mut inner = self.inner.lock().unwrap();
        if inner.games.contains_key(&record.game_id) {
            return Err(PersistError::Conflict(format!(
                "game {} already exists",
                record.game_id
            )));
        }

        let mut events = Vec::new();
        for (index, payload) in record.initial_events.iter().enumerate() {
            events.push(StoredEvent {
                state_version: record.initial_state.version,
                event_index: index as u16,
                action_id: Some(record.start_action_id),
                payload: payload.clone(),
            });
        }

        let mut snapshots = HashMap::new();
        snapshots.insert(record.initial_state.version, record.initial_state.clone());

        inner.games.insert(
            record.game_id,
            StoredGame {
                record: NewGameMeta {
                    room_id: record.room_id,
                    rules: record.rules.clone(),
                    seed: record.seed,
                    created_at: Utc::now(),
                },
                players: record.players.clone(),
                events,
                snapshots,
                round_results: Vec::new(),
                game_result: None,
                status: "active".into(),
                pace: Vec::new(),
            },
        );

        if let Some(room) = inner.rooms.get_mut(&record.room_id) {
            room.phase = "in_game".into();
            room.game_id = Some(record.game_id);
        }
        Ok(())
    }

    async fn commit_command(&self, commit: &CommandCommit) -> Result<(), PersistError> {
        let mut inner = self.inner.lock().unwrap();
        let players = {
            let game = inner
                .games
                .get(&commit.game_id)
                .ok_or_else(|| PersistError::NotFound(format!("game {}", commit.game_id)))?;
            if game
                .events
                .iter()
                .any(|e| e.action_id == Some(commit.action_id))
            {
                return Ok(());
            }
            game.players.clone()
        };

        {
            let game = inner.games.get_mut(&commit.game_id).unwrap();
            for (index, payload) in commit.events.iter().enumerate() {
                game.events.push(StoredEvent {
                    state_version: commit.state.version,
                    event_index: index as u16,
                    action_id: Some(commit.action_id),
                    payload: payload.clone(),
                });
            }
            game.snapshots.clear();
            game.snapshots
                .insert(commit.state.version, commit.state.clone());

            if let Some(round) = &commit.round_result {
                game.round_results
                    .retain(|r| r.round_index != round.round_index);
                game.round_results.push(round.clone());
            }
            if commit.game_result.is_some() {
                game.game_result = commit.game_result.clone();
                game.status = "finished".into();
            }
            game.pace = commit.pace.clone();
        }

        if stats_enabled() {
            if let Some(result) = &commit.game_result {
                record_finishes(&mut inner, commit, &players, result);
            }
        }
        if fair_play_enabled() && commit.game_result.is_some() {
            record_fair_play_roster_memory(&mut inner, commit, &players);
        }
        Ok(())
    }

    async fn action_committed(
        &self,
        game_id: GameId,
        action_id: ActionId,
    ) -> Result<bool, PersistError> {
        let inner = self.inner.lock().unwrap();
        let Some(game) = inner.games.get(&game_id) else {
            return Ok(false);
        };
        Ok(game.events.iter().any(|e| e.action_id == Some(action_id)))
    }

    async fn load_active_games(&self) -> Result<Vec<RestoredGame>, PersistError> {
        let inner = self.inner.lock().unwrap();
        let mut out = Vec::new();
        for (game_id, game) in &inner.games {
            if game.status != "active" {
                continue;
            }
            let version = *game.snapshots.keys().max().unwrap_or(&0);
            let state = game
                .snapshots
                .get(&version)
                .cloned()
                .ok_or_else(|| PersistError::NotFound(format!("snapshot for {game_id}")))?;
            let processed_actions = dedup_from_events(&game.events);
            out.push(RestoredGame {
                game_id: *game_id,
                room_id: game.record.room_id,
                rules: game.record.rules.clone(),
                seed: game.record.seed,
                state,
                players: game.players.clone(),
                processed_actions,
                created_at: game.record.created_at,
                pace: game.pace.clone(),
            });
        }
        Ok(out)
    }

    async fn load_active_game(
        &self,
        game_id: GameId,
    ) -> Result<Option<RestoredGame>, PersistError> {
        let inner = self.inner.lock().unwrap();
        let Some(game) = inner.games.get(&game_id) else {
            return Ok(None);
        };
        if game.status != "active" {
            return Ok(None);
        }
        let version = *game.snapshots.keys().max().unwrap_or(&0);
        let state = game
            .snapshots
            .get(&version)
            .cloned()
            .ok_or_else(|| PersistError::NotFound(format!("snapshot for {game_id}")))?;
        Ok(Some(RestoredGame {
            game_id,
            room_id: game.record.room_id,
            rules: game.record.rules.clone(),
            seed: game.record.seed,
            state,
            players: game.players.clone(),
            processed_actions: dedup_from_events(&game.events),
            created_at: game.record.created_at,
            pace: game.pace.clone(),
        }))
    }

    async fn load_processed_actions(
        &self,
        game_id: GameId,
    ) -> Result<Vec<(ActionId, u64)>, PersistError> {
        let inner = self.inner.lock().unwrap();
        let game = inner
            .games
            .get(&game_id)
            .ok_or_else(|| PersistError::NotFound(format!("game {game_id}")))?;
        Ok(dedup_from_events(&game.events))
    }

    async fn load_game_history(
        &self,
        game_id: GameId,
    ) -> Result<Option<GameHistory>, PersistError> {
        let inner = self.inner.lock().unwrap();
        let Some(game) = inner.games.get(&game_id) else {
            return Ok(None);
        };
        Ok(Some(GameHistory {
            game_id,
            status: game.status.clone(),
            rules: game.record.rules.clone(),
            ranking: game.game_result.as_ref().map(|r| r.ranking.clone()),
            round_results: game.round_results.clone(),
            event_count: game.events.len() as u64,
        }))
    }

    async fn upsert_scheduled_event(
        &self,
        event: &StoredScheduledEvent,
    ) -> Result<(), PersistError> {
        self.inner
            .lock()
            .unwrap()
            .scheduled_events
            .insert(event.event_id, event.clone());
        Ok(())
    }

    async fn load_scheduled_events(&self) -> Result<Vec<StoredScheduledEvent>, PersistError> {
        Ok(self
            .inner
            .lock()
            .unwrap()
            .scheduled_events
            .values()
            .cloned()
            .collect())
    }

    async fn remap_game_player_session(
        &self,
        game_id: GameId,
        player_id: PlayerId,
        new_session_id: SessionId,
        nickname: &str,
        user_id: Option<Uuid>,
    ) -> Result<(), PersistError> {
        let mut inner = self.inner.lock().unwrap();
        let game = inner
            .games
            .get_mut(&game_id)
            .ok_or_else(|| PersistError::NotFound(format!("game {game_id}")))?;
        let player = game
            .players
            .iter_mut()
            .find(|p| p.player_id == player_id)
            .ok_or_else(|| PersistError::NotFound(format!("player {player_id}")))?;
        player.session_id = new_session_id;
        player.nickname = nickname.to_string();
        player.user_id = user_id;
        Ok(())
    }

    async fn abort_game(&self, game_id: GameId) -> Result<(), PersistError> {
        let mut inner = self.inner.lock().unwrap();
        let game = inner
            .games
            .get_mut(&game_id)
            .ok_or_else(|| PersistError::NotFound(format!("game {game_id}")))?;
        if game.status != "active" {
            return Err(PersistError::NotFound(format!("active game {game_id}")));
        }
        game.status = "aborted".into();
        Ok(())
    }

    async fn compact_finished_game(&self, game_id: GameId) -> Result<(), PersistError> {
        let mut inner = self.inner.lock().unwrap();
        let game = inner
            .games
            .get_mut(&game_id)
            .ok_or_else(|| PersistError::NotFound(format!("game {game_id}")))?;
        game.events.clear();
        if let Some((&version, state)) = game.snapshots.iter().max_by_key(|(v, _)| *v) {
            let state = state.clone();
            game.snapshots.clear();
            game.snapshots.insert(version, state);
        }
        Ok(())
    }

    async fn delete_game(&self, game_id: GameId) -> Result<(), PersistError> {
        self.inner.lock().unwrap().games.remove(&game_id);
        Ok(())
    }

    async fn list_terminal_games_older_than(
        &self,
        _older_than: chrono::DateTime<chrono::Utc>,
    ) -> Result<Vec<(GameId, RoomId)>, PersistError> {
        // Memory store has no finished_at timestamps; purge is a no-op in tests.
        Ok(Vec::new())
    }

    async fn delete_orphan_sessions(
        &self,
        _older_than: chrono::DateTime<chrono::Utc>,
    ) -> Result<u64, PersistError> {
        Ok(0)
    }

    async fn ping(&self) -> Result<(), PersistError> {
        Ok(())
    }

    async fn upsert_user(&self, user: &StoredUser) -> Result<(), PersistError> {
        self.inner
            .lock()
            .unwrap()
            .users
            .insert(user.user_id, user.clone());
        Ok(())
    }

    async fn upsert_identity(&self, identity: &StoredIdentity) -> Result<(), PersistError> {
        let mut inner = self.inner.lock().unwrap();
        inner.identities.insert(
            (identity.provider.clone(), identity.subject.clone()),
            identity.user_id,
        );
        Ok(())
    }

    async fn find_user_by_identity(
        &self,
        provider: &str,
        subject: &str,
    ) -> Result<Option<StoredUser>, PersistError> {
        let inner = self.inner.lock().unwrap();
        Ok(inner
            .identities
            .get(&(provider.to_string(), subject.to_string()))
            .and_then(|id| inner.users.get(id).cloned()))
    }

    async fn load_user(&self, user_id: Uuid) -> Result<Option<StoredUser>, PersistError> {
        Ok(self.inner.lock().unwrap().users.get(&user_id).cloned())
    }

    async fn delete_user(&self, user_id: Uuid) -> Result<(), PersistError> {
        let mut inner = self.inner.lock().unwrap();
        inner.users.remove(&user_id);
        inner.identities.retain(|_, id| *id != user_id);
        inner.stats.remove(&user_id);
        inner.recorded.retain(|(_, uid)| *uid != user_id);
        for session in inner.sessions.values_mut() {
            if session.user_id == Some(user_id) {
                session.user_id = None;
            }
        }
        Ok(())
    }

    async fn set_user_avatar(&self, user_id: Uuid, avatar_id: &str) -> Result<(), PersistError> {
        let mut inner = self.inner.lock().unwrap();
        if let Some(user) = inner.users.get_mut(&user_id) {
            user.avatar_id = Some(avatar_id.to_string());
        }
        Ok(())
    }

    async fn load_leaderboard(&self, limit: i64) -> Result<Vec<LeaderboardRow>, PersistError> {
        let inner = self.inner.lock().unwrap();
        Ok(memory_board(&inner, limit))
    }

    async fn load_user_stats(&self, user_id: Uuid) -> Result<Option<UserStatsView>, PersistError> {
        let inner = self.inner.lock().unwrap();
        let Some(user) = inner.users.get(&user_id) else {
            return Ok(None);
        };
        let row = inner.stats.get(&user_id).cloned().unwrap_or_default();
        let rank = memory_board(&inner, 0)
            .iter()
            .position(|entry| entry.user_id == user_id)
            .map(|index| index as i32 + 1);
        Ok(Some(UserStatsView {
            user_id,
            display_name: user.display_name.clone(),
            avatar_id: user.avatar_id.clone(),
            games_played: row.games_played,
            wins: row.wins,
            lifetime_points: row.lifetime_points,
            rounds_played: row.rounds_played,
            exact_bid_rounds: row.exact_bid_rounds,
            ranked_games: row.ranked_games,
            rank,
        }))
    }

    async fn load_match_pulse(&self) -> Result<MatchPulse, PersistError> {
        let inner = self.inner.lock().unwrap();
        let names = inner
            .users
            .iter()
            .map(|(id, user)| (*id, user.display_name.clone()))
            .collect();
        Ok(match_pulse(&inner.pulse, Utc::now(), &names))
    }

    async fn load_latest_game(&self) -> Result<Option<LatestGame>, PersistError> {
        let inner = self.inner.lock().unwrap();
        let Some(latest) = inner
            .pulse
            .iter()
            .max_by_key(|finish| (finish.finished_at, finish.game_id))
        else {
            return Ok(None);
        };
        let game_id = latest.game_id;
        let finished_at = latest.finished_at;
        let rounds_played = latest.rounds_played;
        let mut seats: Vec<LatestGameSeat> = inner
            .pulse
            .iter()
            .filter(|finish| finish.game_id == game_id)
            .map(|finish| {
                let user = inner.users.get(&finish.user_id);
                LatestGameSeat {
                    user_id: finish.user_id,
                    display_name: user
                        .map(|u| u.display_name.clone())
                        .unwrap_or_else(|| "Player".into()),
                    avatar_id: user.and_then(|u| u.avatar_id.clone()),
                    finish_rank: finish.finish_rank,
                    total_score: finish.total_score,
                    exact_bid_rounds: finish.exact_bid_rounds,
                }
            })
            .collect();
        seats.sort_by(|a, b| {
            a.finish_rank
                .cmp(&b.finish_rank)
                .then(b.total_score.cmp(&a.total_score))
                .then(a.display_name.cmp(&b.display_name))
        });
        Ok(Some(LatestGame {
            game_id,
            finished_at,
            table_size: seats.len() as i32,
            rounds_played,
            seats,
        }))
    }

    async fn write_fair_play_roster(
        &self,
        seats: &[FairPlayRosterSeat],
    ) -> Result<(), PersistError> {
        let mut inner = self.inner.lock().unwrap();
        for seat in seats {
            let list = inner.fair_play_rosters.entry(seat.game_id).or_default();
            if !list.iter().any(|s| s.user_id == seat.user_id) {
                list.push(seat.clone());
            }
        }
        Ok(())
    }

    async fn load_fair_play_roster(
        &self,
        game_id: Uuid,
    ) -> Result<Vec<FairPlayRosterSeat>, PersistError> {
        let inner = self.inner.lock().unwrap();
        Ok(inner
            .fair_play_rosters
            .get(&game_id)
            .cloned()
            .unwrap_or_default())
    }

    async fn fair_play_already_submitted(
        &self,
        game_id: Uuid,
        voter_user_id: Uuid,
    ) -> Result<bool, PersistError> {
        let inner = self.inner.lock().unwrap();
        Ok(inner
            .fair_play_submissions
            .contains(&(game_id, voter_user_id)))
    }

    async fn submit_fair_play(
        &self,
        game_id: Uuid,
        voter_user_id: Uuid,
        ratings: &[FairPlayRating],
    ) -> Result<Vec<FairPlayGameTotal>, PersistError> {
        let mut inner = self.inner.lock().unwrap();
        if !inner.fair_play_submissions.insert((game_id, voter_user_id)) {
            return Err(PersistError::Conflict("already submitted".into()));
        }
        for rating in ratings {
            inner.fair_play_ballots.insert(
                (game_id, voter_user_id, rating.target_user_id),
                rating.points,
            );
            let prior = inner
                .fair_play_ballots
                .keys()
                .filter(|(g, _, t)| *g == game_id && *t == rating.target_user_id)
                .count();
            let row = inner
                .fair_play_stats
                .entry(rating.target_user_id)
                .or_default();
            row.points_received += i32::from(rating.points);
            row.ratings_received += 1;
            if prior == 1 {
                row.games_rated += 1;
            }
        }
        Ok(game_totals_locked(&inner, game_id))
    }

    async fn load_fair_play_game_totals(
        &self,
        game_id: Uuid,
    ) -> Result<Vec<FairPlayGameTotal>, PersistError> {
        let inner = self.inner.lock().unwrap();
        Ok(game_totals_locked(&inner, game_id))
    }

    async fn load_fair_play_leaderboard(
        &self,
        limit: i64,
    ) -> Result<Vec<FairPlayLeaderboardRow>, PersistError> {
        let inner = self.inner.lock().unwrap();
        let mut rows: Vec<_> = inner
            .fair_play_stats
            .iter()
            .filter(|(_, row)| row.ratings_received > 0)
            .map(|(user_id, row)| {
                let user = inner.users.get(user_id);
                (
                    fair_play_board_key(row),
                    FairPlayLeaderboardRow {
                        user_id: *user_id,
                        display_name: user
                            .map(|u| u.display_name.clone())
                            .unwrap_or_else(|| "Player".into()),
                        avatar_id: user.and_then(|u| u.avatar_id.clone()),
                        points_received: row.points_received,
                        ratings_received: row.ratings_received,
                        games_rated: row.games_rated,
                    },
                )
            })
            .collect();
        rows.sort_by(|a, b| b.0.cmp(&a.0));
        let limit = if limit > 0 {
            limit as usize
        } else {
            rows.len()
        };
        Ok(rows.into_iter().take(limit).map(|(_, row)| row).collect())
    }
}

fn game_totals_locked(inner: &MemoryInner, game_id: Uuid) -> Vec<FairPlayGameTotal> {
    let mut out = Vec::new();
    let Some(roster) = inner.fair_play_rosters.get(&game_id) else {
        return out;
    };
    for seat in roster {
        let mut points = 0;
        let mut ratings = 0;
        for ((g, _, target), pts) in &inner.fair_play_ballots {
            if *g == game_id && *target == seat.user_id {
                points += i32::from(*pts);
                ratings += 1;
            }
        }
        out.push(FairPlayGameTotal {
            user_id: seat.user_id,
            display_name: seat.display_name.clone(),
            avatar_id: seat.avatar_id.clone(),
            points,
            ratings,
        });
    }
    out.sort_by(|a, b| {
        b.points
            .cmp(&a.points)
            .then(b.ratings.cmp(&a.ratings))
            .then(a.display_name.cmp(&b.display_name))
    });
    out
}

fn record_fair_play_roster_memory(
    inner: &mut MemoryInner,
    commit: &CommandCommit,
    players: &[NewGamePlayer],
) {
    let finished_at = Utc::now();
    let mut seats = Vec::new();
    for player in players {
        let Some(user_id) = player.user_id else {
            continue;
        };
        let avatar_id = commit
            .state
            .players
            .iter()
            .find(|p| p.id == player.player_id)
            .and_then(|p| p.avatar_id.clone());
        seats.push(FairPlayRosterSeat {
            game_id: commit.game_id.0,
            user_id,
            player_id: player.player_id.0,
            display_name: player.nickname.clone(),
            avatar_id,
            finished_at,
        });
    }
    if !seats.is_empty() {
        inner
            .fair_play_rosters
            .entry(commit.game_id.0)
            .or_default()
            .extend(seats);
    }
}

fn memory_board(inner: &MemoryInner, limit: i64) -> Vec<LeaderboardRow> {
    let names = inner
        .users
        .iter()
        .map(|(id, user)| (*id, user.display_name.clone()))
        .collect();
    let medals = medals_from_finishes(&inner.pulse, &names);
    let mut rows: Vec<_> = medals
        .into_iter()
        .filter(|(user_id, _)| inner.users.contains_key(user_id))
        .map(|(user_id, rec)| {
            let avatar_id = inner.users.get(&user_id).and_then(|u| u.avatar_id.clone());
            (user_id, avatar_id, rec)
        })
        .collect();
    rows.sort_by(|a, b| b.2.key().cmp(&a.2.key()));
    if limit > 0 {
        rows.truncate(limit as usize);
    }
    rows.into_iter()
        .map(|(user_id, avatar_id, rec)| to_leaderboard_row(user_id, avatar_id, &rec))
        .collect()
}

fn record_finishes(
    inner: &mut MemoryInner,
    commit: &CommandCommit,
    players: &[NewGamePlayer],
    result: &GameResultRecord,
) {
    let rounds = commit.state.score_table.rounds.len() as i32;
    let counted = commit.state.players.len() >= 3;
    let mut by_user: HashMap<Uuid, SeatFinish> = HashMap::new();
    for ranked in &result.ranking {
        let Some(player) = players.iter().find(|p| p.player_id == ranked.player_id) else {
            continue;
        };
        let Some(user_id) = player.user_id else {
            continue;
        };
        let seat = SeatFinish {
            user_id,
            finish_rank: ranked.rank as i32,
            total_score: ranked.total_score,
            exact_bid_rounds: ranked.exact_bid_rounds as i32,
            tricks_missed: ranked.total_tricks_missed as i32,
        };
        match by_user.get(&user_id) {
            Some(existing) if existing.finish_rank <= seat.finish_rank => {}
            _ => {
                by_user.insert(user_id, seat);
            }
        }
    }
    let game_id = commit.game_id.0;
    for seat in by_user.into_values() {
        if !inner.recorded.insert((game_id, seat.user_id)) {
            continue;
        }
        let row = inner.stats.entry(seat.user_id).or_default();
        apply_finish(row, &seat, rounds, counted);
        if counted {
            inner.pulse.push(PulseFinish {
                game_id,
                user_id: seat.user_id,
                finished_at: Utc::now(),
                finish_rank: seat.finish_rank,
                exact_bid_rounds: seat.exact_bid_rounds,
                rounds_played: rounds,
                total_score: seat.total_score,
            });
        }
    }
}

fn dedup_from_events(events: &[StoredEvent]) -> Vec<(ActionId, u64)> {
    let mut map = HashMap::new();
    for event in events {
        if let Some(action_id) = event.action_id {
            map.insert(action_id, event.state_version);
        }
    }
    map.into_iter().collect()
}
