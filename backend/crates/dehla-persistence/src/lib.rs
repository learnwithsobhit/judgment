//! Tip-snapshot persistence for Dehla (Memory + Postgres).
//!
//! Commit point: actor applies in memory, then `save_tip` before broadcast.

mod memory;
mod postgres;

pub use memory::MemoryStore;
pub use postgres::PostgresStore;

use async_trait::async_trait;
use dehla_domain::GameId;
use dehla_engine::GameState;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum PersistError {
    #[error("not found")]
    NotFound,
    #[error("conflict: {0}")]
    Conflict(String),
    #[error("database: {0}")]
    Database(String),
    #[error("serde: {0}")]
    Serde(String),
}

impl From<serde_json::Error> for PersistError {
    fn from(e: serde_json::Error) -> Self {
        PersistError::Serde(e.to_string())
    }
}

impl From<sqlx::Error> for PersistError {
    fn from(e: sqlx::Error) -> Self {
        PersistError::Database(e.to_string())
    }
}

/// Durable store used by the server and game actors.
#[async_trait]
pub trait GameStore: Send + Sync {
    async fn ping(&self) -> Result<(), PersistError>;

    /// Upsert the latest tip snapshot for `game_id` (CP before observe).
    async fn save_tip(&self, game_id: GameId, state: &GameState) -> Result<(), PersistError>;

    /// Load tip if present.
    async fn load_tip(&self, game_id: GameId) -> Result<Option<GameState>, PersistError>;
}
