use std::collections::HashMap;
use std::sync::Mutex;

use async_trait::async_trait;
use dehla_domain::GameId;
use dehla_engine::GameState;

use crate::{GameStore, PersistError};

/// In-memory tip store for local `dehla-server` without DATABASE_URL.
pub struct MemoryStore {
    tips: Mutex<HashMap<GameId, GameState>>,
}

impl MemoryStore {
    pub fn new() -> Self {
        Self {
            tips: Mutex::new(HashMap::new()),
        }
    }
}

impl Default for MemoryStore {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl GameStore for MemoryStore {
    async fn ping(&self) -> Result<(), PersistError> {
        Ok(())
    }

    async fn save_tip(&self, game_id: GameId, state: &GameState) -> Result<(), PersistError> {
        self.tips
            .lock()
            .map_err(|_| PersistError::Conflict("memory store poisoned".into()))?
            .insert(game_id, state.clone());
        Ok(())
    }

    async fn load_tip(&self, game_id: GameId) -> Result<Option<GameState>, PersistError> {
        Ok(self
            .tips
            .lock()
            .map_err(|_| PersistError::Conflict("memory store poisoned".into()))?
            .get(&game_id)
            .cloned())
    }
}
