//! In-memory store for unit tests and DATABASE_URL-less local runs.
//! Persistence still follows the same commit API as Postgres.

use std::collections::HashMap;
use std::sync::Mutex;

use async_trait::async_trait;
use judgement_domain::{ActionId, EventId, GameId, PlayerId, RoomId, SessionId};
use judgement_engine::GameEvent;

use crate::error::PersistError;
use crate::models::*;
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
}

struct NewGameMeta {
    room_id: RoomId,
    rules: judgement_domain::GameRules,
    seed: Option<u64>,
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
        self.inner.lock().unwrap().rooms.insert(room.room_id, room.clone());
        Ok(())
    }

    async fn delete_room(&self, room_id: RoomId) -> Result<(), PersistError> {
        self.inner.lock().unwrap().rooms.remove(&room_id);
        Ok(())
    }

    async fn load_sessions(&self) -> Result<Vec<StoredSession>, PersistError> {
        Ok(self.inner.lock().unwrap().sessions.values().cloned().collect())
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
                },
                players: record.players.clone(),
                events,
                snapshots,
                round_results: Vec::new(),
                game_result: None,
                status: "active".into(),
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
        let game = inner
            .games
            .get_mut(&commit.game_id)
            .ok_or_else(|| PersistError::NotFound(format!("game {}", commit.game_id)))?;

        if game.events.iter().any(|e| e.action_id == Some(commit.action_id)) {
            return Ok(()); // idempotent
        }

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
            game.round_results.retain(|r| r.round_index != round.round_index);
            game.round_results.push(round.clone());
        }
        if let Some(result) = &commit.game_result {
            game.game_result = Some(result.clone());
            game.status = "finished".into();
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
        Ok(game
            .events
            .iter()
            .any(|e| e.action_id == Some(action_id)))
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

    async fn load_game_history(&self, game_id: GameId) -> Result<Option<GameHistory>, PersistError> {
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

    async fn upsert_scheduled_event(&self, event: &StoredScheduledEvent) -> Result<(), PersistError> {
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
