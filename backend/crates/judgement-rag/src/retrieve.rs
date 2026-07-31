//! Retrieval façade used by `judgement-ai` when RAG is enabled.

use std::sync::Arc;

use async_trait::async_trait;

use crate::embed::Embedder;
use crate::error::RagError;
use crate::store::{ChunkStore, RetrievalFilter, ScoredChunk};

#[derive(Debug, Clone)]
pub struct RetrievedAnswer {
    pub answer: String,
    pub rule_references: Vec<String>,
    pub confidence: f32,
    pub chunk_ids: Vec<String>,
}

/// Optional RAG backend. Implementations must never see hidden game cards.
#[async_trait]
pub trait RuleRetriever: Send + Sync {
    async fn retrieve(
        &self,
        question: &str,
        filter: &RetrievalFilter,
    ) -> Result<Option<RetrievedAnswer>, RagError>;
}

pub struct VectorRuleRetriever {
    embedder: Arc<dyn Embedder>,
    store: Arc<dyn ChunkStore>,
}

impl VectorRuleRetriever {
    pub fn new(embedder: Arc<dyn Embedder>, store: Arc<dyn ChunkStore>) -> Self {
        Self { embedder, store }
    }
}

#[async_trait]
impl RuleRetriever for VectorRuleRetriever {
    async fn retrieve(
        &self,
        question: &str,
        filter: &RetrievalFilter,
    ) -> Result<Option<RetrievedAnswer>, RagError> {
        // Defence: never accept payloads that look like private hand dumps.
        if looks_like_hidden_card_leak(question) {
            return Ok(None);
        }

        let mut query_filter = filter.clone();
        // Always constrain to this embedder's model version (exit criterion).
        query_filter.embedding_model_version = self.embedder.model_version().to_string();

        let vectors = self.embedder.embed(&[question.to_string()]).await?;
        let query_vec = vectors
            .into_iter()
            .next()
            .ok_or_else(|| RagError::Embed("empty embedding".into()))?;

        let hits = self.store.search(&query_vec, &query_filter).await?;
        Ok(hits_to_answer(hits))
    }
}

fn hits_to_answer(hits: Vec<ScoredChunk>) -> Option<RetrievedAnswer> {
    let top = hits.first()?;
    let mut refs = Vec::new();
    let mut chunk_ids = Vec::new();
    let mut parts = Vec::new();
    for hit in &hits {
        if !refs.contains(&hit.chunk.rule_id) {
            refs.push(hit.chunk.rule_id.clone());
        }
        chunk_ids.push(hit.chunk.chunk_id.clone());
        parts.push(hit.chunk.content.clone());
    }
    // Prefer the top chunk as the answer body; citations cover the set.
    let answer = parts.first().cloned().unwrap_or_default();
    Some(RetrievedAnswer {
        answer,
        rule_references: refs,
        confidence: top.score.clamp(0.0, 0.99),
        chunk_ids,
    })
}

fn looks_like_hidden_card_leak(question: &str) -> bool {
    let q = question.to_ascii_lowercase();
    q.contains("opponent hand")
        || q.contains("hidden card")
        || q.contains("undealt deck")
        || q.contains("shuffle seed")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::chunk::RuleChunk;
    use crate::embed::DeterministicHashEmbedder;
    use crate::store::{EmbeddedChunk, MemoryChunkStore};

    #[tokio::test]
    async fn retrieves_follow_suit_chunk() {
        let embedder: Arc<dyn Embedder> = Arc::new(DeterministicHashEmbedder);
        let store: Arc<dyn ChunkStore> = Arc::new(MemoryChunkStore::new());
        let chunk = RuleChunk {
            chunk_id: "follow-suit-001#must-follow".into(),
            rule_id: "follow-suit-001".into(),
            ruleset_version: "mvp-1".into(),
            category: "play".into(),
            player_count: None,
            variant: None,
            content: "You must follow the lead suit when you hold that suit.".into(),
            source_path: "following_suit.md".into(),
        };
        let emb = embedder.embed(&[chunk.content.clone()]).await.unwrap();
        store
            .upsert(&[EmbeddedChunk {
                chunk,
                embedding_model_version: embedder.model_version().into(),
                embedding: emb[0].clone(),
            }])
            .await
            .unwrap();

        let retriever = VectorRuleRetriever::new(embedder, store);
        let answer = retriever
            .retrieve("Must I follow suit?", &RetrievalFilter::default())
            .await
            .unwrap()
            .expect("hit");
        assert!(answer.rule_references.contains(&"follow-suit-001".into()));
        assert!(answer.confidence >= 0.15);
    }
}
