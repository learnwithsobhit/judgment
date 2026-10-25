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
use crate::models::*;
use crate::stats::{
    apply_finish, average_score, exact_percent, ladder_key, stats_enabled, SeatFinish, UserStatsRow,
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
        let mut rows: Vec<_> = inner
            .stats
            .iter()
            .filter(|(_, row)| row.ranked_games > 0)
            .filter_map(|(id, row)| {
                let user = inner.users.get(id)?;
                Some((ladder_key(row), user, row))
            })
            .collect();
        rows.sort_by(|a, b| b.0.cmp(&a.0));
        Ok(rows
            .into_iter()
            .take(limit.max(0) as usize)
            .map(|(_, user, row)| LeaderboardRow {
                user_id: user.user_id,
                display_name: user.display_name.clone(),
                avatar_id: user.avatar_id.clone(),
                wins: row.ranked_wins,
                games: row.ranked_games,
                exact_percent: exact_percent(row.ranked_exact, row.ranked_rounds),
                average_score: average_score(row.ranked_points, row.ranked_games),
            })
            .collect())
    }

    async fn load_user_stats(&self, user_id: Uuid) -> Result<Option<UserStatsView>, PersistError> {
        let inner = self.inner.lock().unwrap();
        let Some(user) = inner.users.get(&user_id) else {
            return Ok(None);
        };
        let row = inner.stats.get(&user_id).cloned().unwrap_or_default();
        let rank = if row.ranked_games == 0 {
            None
        } else {
            let mine = ladder_key(&row);
            let better = inner
                .stats
                .values()
                .filter(|other| other.ranked_games > 0 && ladder_key(other) > mine)
                .count();
            Some(better as i32 + 1)
        };
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
