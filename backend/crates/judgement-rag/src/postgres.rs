//! pgvector-backed chunk store (ADR 0002 / PLAN.md Phase 7b).

use std::path::Path;

use async_trait::async_trait;
use pgvector::Vector;
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Row};

use crate::chunk::RuleChunk;
use crate::error::RagError;
use crate::store::{ChunkStore, EmbeddedChunk, RetrievalFilter, ScoredChunk};

#[derive(Clone)]
pub struct PostgresChunkStore {
    pool: PgPool,
}

impl PostgresChunkStore {
    pub async fn connect(database_url: &str) -> Result<Self, RagError> {
        let pool = PgPoolOptions::new()
            .max_connections(5)
            .connect(database_url)
            .await
            .map_err(|e| RagError::Store(e.to_string()))?;
        Ok(Self { pool })
    }

    pub fn from_pool(pool: PgPool) -> Self {
        Self { pool }
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }

    pub async fn migrate(&self, migrations_dir: impl AsRef<Path>) -> Result<(), RagError> {
        let migrator = sqlx::migrate::Migrator::new(migrations_dir.as_ref())
            .await
            .map_err(|e| RagError::Store(format!("migration load: {e}")))?;
        migrator
            .run(&self.pool)
            .await
            .map_err(|e| RagError::Store(format!("migration: {e}")))?;
        Ok(())
    }
}

#[async_trait]
impl ChunkStore for PostgresChunkStore {
    async fn upsert(&self, chunks: &[EmbeddedChunk]) -> Result<(), RagError> {
        for item in chunks {
            let embedding = Vector::from(item.embedding.clone());
            sqlx::query(
                r#"
                INSERT INTO rule_chunks (
                    chunk_id, rule_id, ruleset_version, category, player_count, variant,
                    embedding_model_version, content, source_path, embedding
                ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
                ON CONFLICT (chunk_id, embedding_model_version) DO UPDATE SET
                    rule_id = EXCLUDED.rule_id,
                    ruleset_version = EXCLUDED.ruleset_version,
                    category = EXCLUDED.category,
                    player_count = EXCLUDED.player_count,
                    variant = EXCLUDED.variant,
                    content = EXCLUDED.content,
                    source_path = EXCLUDED.source_path,
                    embedding = EXCLUDED.embedding
                "#,
            )
            .bind(&item.chunk.chunk_id)
            .bind(&item.chunk.rule_id)
            .bind(&item.chunk.ruleset_version)
            .bind(&item.chunk.category)
            .bind(item.chunk.player_count.map(|n| n as i16))
            .bind(&item.chunk.variant)
            .bind(&item.embedding_model_version)
            .bind(&item.chunk.content)
            .bind(&item.chunk.source_path)
            .bind(embedding)
            .execute(&self.pool)
            .await
            .map_err(|e| RagError::Store(e.to_string()))?;
        }
        Ok(())
    }

    async fn search(
        &self,
        query_embedding: &[f32],
        filter: &RetrievalFilter,
    ) -> Result<Vec<ScoredChunk>, RagError> {
        let embedding = Vector::from(query_embedding.to_vec());
        let limit = filter.top_k as i64;
        let rows = sqlx::query(
            r#"
            SELECT chunk_id, rule_id, ruleset_version, category, player_count, variant,
                   embedding_model_version, content, source_path,
                   1 - (embedding <=> $1) AS score
            FROM rule_chunks
            WHERE ruleset_version = $2
              AND embedding_model_version = $3
              AND 1 - (embedding <=> $1) >= $4
            ORDER BY embedding <=> $1
            LIMIT $5
            "#,
        )
        .bind(embedding)
        .bind(&filter.ruleset_version)
        .bind(&filter.embedding_model_version)
        .bind(filter.min_score)
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .map_err(|e| RagError::Store(e.to_string()))?;

        Ok(rows
            .into_iter()
            .map(|row| {
                let player_count: Option<i16> = row.get("player_count");
                ScoredChunk {
                    chunk: RuleChunk {
                        chunk_id: row.get("chunk_id"),
                        rule_id: row.get("rule_id"),
                        ruleset_version: row.get("ruleset_version"),
                        category: row.get("category"),
                        player_count: player_count.map(|n| n as u8),
                        variant: row.get("variant"),
                        content: row.get("content"),
                        source_path: row.get("source_path"),
                    },
                    score: row.get::<f64, _>("score") as f32,
                    embedding_model_version: row.get("embedding_model_version"),
                }
            })
            .collect())
    }

    async fn count(
        &self,
        ruleset_version: &str,
        embedding_model_version: &str,
    ) -> Result<usize, RagError> {
        let row = sqlx::query(
            r#"
            SELECT COUNT(*)::bigint AS n
            FROM rule_chunks
            WHERE ruleset_version = $1 AND embedding_model_version = $2
            "#,
        )
        .bind(ruleset_version)
        .bind(embedding_model_version)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| RagError::Store(e.to_string()))?;
        let n: i64 = row.get("n");
        Ok(n as usize)
    }
}
