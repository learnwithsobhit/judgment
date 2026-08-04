//! PostgreSQL persistence for games, rooms, and sessions (PLAN.md Phase 5).
//!
//! Commit ordering (PLAN.md §9.2): the actor applies in memory then persists;
//! on persist failure it rolls the engine state back so the commit point is
//! still "nothing observed by clients until durable".

pub mod error;
pub mod memory;
pub mod models;
pub mod postgres;

pub use error::PersistError;
pub use memory::MemoryStore;
pub use models::*;
pub use postgres::PostgresStore;

use async_trait::async_trait;
use judgement_domain::{ActionId, GameId, PlayerId, RoomId, SessionId};
use judgement_engine::GameEvent;

/// Durable store used by the server and game actors.
#[async_trait]
pub trait GameStore: Send + Sync {
    async fn upsert_session(&self, session: &StoredSession) -> Result<(), PersistError>;

    async fn upsert_room(&self, room: &StoredRoom) -> Result<(), PersistError>;

    async fn delete_room(&self, room_id: RoomId) -> Result<(), PersistError>;

    async fn load_sessions(&self) -> Result<Vec<StoredSession>, PersistError>;

    async fn load_rooms(&self) -> Result<Vec<StoredRoom>, PersistError>;

    /// Create the game row, players, and the initial post-`start_game` snapshot.
    async fn create_game(&self, record: &NewGame) -> Result<(), PersistError>;

    /// Persist one accepted command: events + latest snapshot (+ optional
    /// round/game results). This is the commit point.
    async fn commit_command(&self, commit: &CommandCommit) -> Result<(), PersistError>;

    /// True if `action_id` already has a durable event row (commit-uncertainty).
    async fn action_committed(
        &self,
        game_id: GameId,
        action_id: ActionId,
    ) -> Result<bool, PersistError>;

    async fn load_active_games(&self) -> Result<Vec<RestoredGame>, PersistError>;

    /// Load a single active game for actor respawn, if still `status = active`.
    async fn load_active_game(
        &self,
        game_id: GameId,
    ) -> Result<Option<RestoredGame>, PersistError>;

    async fn load_processed_actions(
        &self,
        game_id: GameId,
    ) -> Result<Vec<(ActionId, u64)>, PersistError>;

    async fn load_game_history(&self, game_id: GameId) -> Result<Option<GameHistory>, PersistError>;

    /// Upsert a scheduled meetup and its RSVPs (ADR 0005).
    async fn upsert_scheduled_event(&self, event: &StoredScheduledEvent) -> Result<(), PersistError>;

    async fn load_scheduled_events(&self) -> Result<Vec<StoredScheduledEvent>, PersistError>;

    /// Bind a new session to an existing in-game seat (seat claim).
    async fn remap_game_player_session(
        &self,
        game_id: GameId,
        player_id: PlayerId,
        new_session_id: SessionId,
        nickname: &str,
    ) -> Result<(), PersistError>;

    /// Mark an active game aborted (host end / vacancy timeout).
    async fn abort_game(&self, game_id: GameId) -> Result<(), PersistError>;

    /// Drop mid-game events and non-latest snapshots (ops/backfill only;
    /// live finish/abort calls [`Self::delete_game`] immediately).
    async fn compact_finished_game(&self, game_id: GameId) -> Result<(), PersistError>;

    /// Hard-delete a game row (cascades events/snapshots/results).
    async fn delete_game(&self, game_id: GameId) -> Result<(), PersistError>;

    /// Leftover finished/aborted games older than `older_than` (reaper backstop).
    async fn list_terminal_games_older_than(
        &self,
        older_than: chrono::DateTime<chrono::Utc>,
    ) -> Result<Vec<(GameId, RoomId)>, PersistError>;

    /// Guest sessions with no room/game references older than cutoff.
    async fn delete_orphan_sessions(
        &self,
        older_than: chrono::DateTime<chrono::Utc>,
    ) -> Result<u64, PersistError>;

    /// Lightweight readiness probe (Phase 9). Memory store always succeeds;
    /// Postgres runs `SELECT 1`.
    async fn ping(&self) -> Result<(), PersistError>;
}

/// Round / game completion events also warrant keeping an explicit historical
/// snapshot row (the latest state is always written by `commit_command`).
pub fn should_keep_historical_snapshot(events: &[GameEvent]) -> bool {
    events.iter().any(|event| {
        matches!(
            event,
            GameEvent::RoundCompleted { .. } | GameEvent::GameCompleted { .. }
        )
    })
}
