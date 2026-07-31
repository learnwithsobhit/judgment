//! Optional Phase 7b RAG bootstrap. Flag off ⇒ identical to Phase 7.

use std::sync::Arc;

use judgement_ai::ExplanationService;
use judgement_rag::{
    default_migrations_dir, default_rules_dir, ensure_ingested, ChunkStore, DeterministicHashEmbedder,
    Embedder, MemoryChunkStore, PostgresChunkStore, RetrievalFilter, VectorRuleRetriever,
    DEFAULT_RULESET_VERSION,
};

/// `RAG_ENABLED=1|true|yes` turns on vector retrieval after FAQ miss.
pub fn rag_enabled_from_env() -> bool {
    match std::env::var("RAG_ENABLED") {
        Ok(v) => matches!(
            v.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "on"
        ),
        Err(_) => false,
    }
}

/// Build the explanation service, optionally with an ingested RAG retriever.
pub async fn build_explanation_service(
    database_url: Option<&str>,
) -> ExplanationService {
    let base = ExplanationService::default();
    if !rag_enabled_from_env() {
        tracing::info!("RAG_ENABLED unset/false — Phase 7 FAQ/templates only");
        return base;
    }

    let rules_dir = match default_rules_dir() {
        Some(p) => p,
        None => {
            tracing::warn!("RAG_ENABLED but rules/ not found — continuing without RAG");
            return base;
        }
    };

    let embedder: Arc<dyn Embedder> = Arc::new(DeterministicHashEmbedder);
    let store: Arc<dyn ChunkStore> = match database_url {
        Some(url) => match PostgresChunkStore::connect(url).await {
            Ok(pg) => {
                if let Some(migrations) = default_migrations_dir() {
                    if let Err(err) = pg.migrate(&migrations).await {
                        tracing::error!(error = %err, "RAG migration failed — continuing without RAG");
                        return base;
                    }
                } else {
                    tracing::warn!("RAG migrations dir missing — continuing without RAG");
                    return base;
                }
                Arc::new(pg)
            }
            Err(err) => {
                tracing::error!(error = %err, "RAG postgres connect failed — using memory store");
                Arc::new(MemoryChunkStore::new())
            }
        },
        None => {
            tracing::warn!("RAG_ENABLED without DATABASE_URL — using in-memory chunk store");
            Arc::new(MemoryChunkStore::new())
        }
    };

    if let Err(err) = ensure_ingested(
        &rules_dir,
        embedder.clone(),
        store.clone(),
        DEFAULT_RULESET_VERSION,
    )
    .await
    {
        tracing::error!(error = %err, "RAG ingest failed — continuing without RAG");
        return base;
    }

    let retriever = Arc::new(VectorRuleRetriever::new(embedder, store));
    tracing::info!("RAG enabled (deterministic-hash-v1 embeddings, ruleset mvp-1)");
    base.with_retriever(retriever).with_retrieval_filter(RetrievalFilter {
        ruleset_version: DEFAULT_RULESET_VERSION.to_string(),
        embedding_model_version: judgement_rag::DETERMINISTIC_EMBEDDING_MODEL_VERSION.to_string(),
        top_k: 3,
        min_score: 0.12,
    })
}
