//! Vector stores with mandatory ruleset + embedding-model version filters.

use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use crate::chunk::RuleChunk;
use crate::embed::cosine_similarity;
use crate::error::RagError;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmbeddedChunk {
    pub chunk: RuleChunk,
    pub embedding_model_version: String,
    pub embedding: Vec<f32>,
}

#[derive(Debug, Clone)]
pub struct RetrievalFilter {
    pub ruleset_version: String,
    pub embedding_model_version: String,
    pub top_k: usize,
    pub min_score: f32,
}

impl Default for RetrievalFilter {
    fn default() -> Self {
        Self {
            ruleset_version: crate::chunk::DEFAULT_RULESET_VERSION.to_string(),
            embedding_model_version: crate::embed::DETERMINISTIC_EMBEDDING_MODEL_VERSION
                .to_string(),
            top_k: 3,
            min_score: 0.15,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ScoredChunk {
    pub chunk: RuleChunk,
    pub score: f32,
    pub embedding_model_version: String,
}

#[async_trait]
pub trait ChunkStore: Send + Sync {
    async fn upsert(&self, chunks: &[EmbeddedChunk]) -> Result<(), RagError>;
    async fn search(
        &self,
        query_embedding: &[f32],
        filter: &RetrievalFilter,
    ) -> Result<Vec<ScoredChunk>, RagError>;
    async fn count(
        &self,
        ruleset_version: &str,
        embedding_model_version: &str,
    ) -> Result<usize, RagError>;
}

/// In-memory store used when RAG is enabled without Postgres, and in unit tests.
#[derive(Debug, Default)]
pub struct MemoryChunkStore {
    inner: std::sync::Mutex<Vec<EmbeddedChunk>>,
}

impl MemoryChunkStore {
    pub fn new() -> Self {
        Self::default()
    }
}

#[async_trait]
impl ChunkStore for MemoryChunkStore {
    async fn upsert(&self, chunks: &[EmbeddedChunk]) -> Result<(), RagError> {
        let mut guard = self.inner.lock().map_err(|_| RagError::Store("lock".into()))?;
        for incoming in chunks {
            if let Some(existing) = guard.iter_mut().find(|c| {
                c.chunk.chunk_id == incoming.chunk.chunk_id
                    && c.embedding_model_version == incoming.embedding_model_version
            }) {
                *existing = incoming.clone();
            } else {
                guard.push(incoming.clone());
            }
        }
        Ok(())
    }

    async fn search(
        &self,
        query_embedding: &[f32],
        filter: &RetrievalFilter,
    ) -> Result<Vec<ScoredChunk>, RagError> {
        let guard = self.inner.lock().map_err(|_| RagError::Store("lock".into()))?;
        let mut scored: Vec<ScoredChunk> = guard
            .iter()
            .filter(|c| {
                c.chunk.ruleset_version == filter.ruleset_version
                    && c.embedding_model_version == filter.embedding_model_version
            })
            .map(|c| ScoredChunk {
                chunk: c.chunk.clone(),
                score: cosine_similarity(query_embedding, &c.embedding),
                embedding_model_version: c.embedding_model_version.clone(),
            })
            .filter(|s| s.score >= filter.min_score)
            .collect();
        scored.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
        scored.truncate(filter.top_k);
        Ok(scored)
    }

    async fn count(
        &self,
        ruleset_version: &str,
        embedding_model_version: &str,
    ) -> Result<usize, RagError> {
        let guard = self.inner.lock().map_err(|_| RagError::Store("lock".into()))?;
        Ok(guard
            .iter()
            .filter(|c| {
                c.chunk.ruleset_version == ruleset_version
                    && c.embedding_model_version == embedding_model_version
            })
            .count())
    }
}
