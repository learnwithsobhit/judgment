//! sqlx-backed PostgreSQL tip store.

use std::path::Path;

use async_trait::async_trait;
use dehla_domain::GameId;
use dehla_engine::GameState;
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Row};

use crate::{GameStore, PersistError};

#[derive(Clone)]
pub struct PostgresStore {
    pool: PgPool,
}

impl PostgresStore {
    pub async fn connect(database_url: &str) -> Result<Self, PersistError> {
        let pool = PgPoolOptions::new()
            .max_connections(10)
            .acquire_timeout(std::time::Duration::from_secs(2))
            .idle_timeout(std::time::Duration::from_secs(60))
            .max_lifetime(std::time::Duration::from_secs(30 * 60))
            .test_before_acquire(true)
            .after_connect(|conn, _meta| {
                Box::pin(async move {
                    sqlx::query("SET statement_timeout = '3s'")
                        .execute(&mut *conn)
                        .await?;
                    Ok(())
                })
            })
            .connect(database_url)
            .await?;
        Ok(Self { pool })
    }

    pub fn from_pool(pool: PgPool) -> Self {
        Self { pool }
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }

    /// Run SQL migrations from `crates/dehla-persistence/migrations`.
    pub async fn migrate(&self, migrations_dir: impl AsRef<Path>) -> Result<(), PersistError> {
        let migrator = sqlx::migrate::Migrator::new(migrations_dir.as_ref())
            .await
            .map_err(|e| PersistError::Conflict(format!("migration load failed: {e}")))?;
        migrator
            .run(&self.pool)
            .await
            .map_err(|e| PersistError::Conflict(format!("migration failed: {e}")))?;
        Ok(())
    }
}

#[async_trait]
impl GameStore for PostgresStore {
    async fn ping(&self) -> Result<(), PersistError> {
        sqlx::query("SELECT 1").execute(&self.pool).await?;
        Ok(())
    }

    async fn save_tip(&self, game_id: GameId, state: &GameState) -> Result<(), PersistError> {
        let tip = serde_json::to_value(state)?;
        sqlx::query(
            r#"
            INSERT INTO game_tips (game_id, tip, updated_at)
            VALUES ($1, $2, NOW())
            ON CONFLICT (game_id) DO UPDATE
            SET tip = EXCLUDED.tip, updated_at = NOW()
            "#,
        )
        .bind(game_id)
        .bind(tip)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn load_tip(&self, game_id: GameId) -> Result<Option<GameState>, PersistError> {
        let row = sqlx::query("SELECT tip FROM game_tips WHERE game_id = $1")
            .bind(game_id)
            .fetch_optional(&self.pool)
            .await?;
        match row {
            None => Ok(None),
            Some(r) => {
                let tip: serde_json::Value = r.get("tip");
                Ok(Some(serde_json::from_value(tip)?))
            }
        }
    }
}
