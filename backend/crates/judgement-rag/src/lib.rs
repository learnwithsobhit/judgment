//! Feature-flagged vector RAG over curated rule docs (PLAN.md Phase 7b, ADR 0002).
//!
//! When disabled, callers must not construct a [`RuleRetriever`] — behaviour
//! stays identical to Phase 7 (FAQ + reason-code templates only).

pub mod chunk;
pub mod embed;
pub mod error;
pub mod ingest;
#[cfg(feature = "postgres")]
pub mod postgres;
pub mod retrieve;
pub mod store;

pub use chunk::{chunk_markdown, chunk_rules_dir, RuleChunk, DEFAULT_RULESET_VERSION};
pub use embed::{
    cosine_similarity, DeterministicHashEmbedder, Embedder, DETERMINISTIC_EMBEDDING_MODEL_VERSION,
    EMBEDDING_DIM,
};
pub use error::RagError;
pub use ingest::{ensure_ingested, ingest_rules_dir};
#[cfg(feature = "postgres")]
pub use postgres::PostgresChunkStore;
pub use retrieve::{RetrievedAnswer, RuleRetriever, VectorRuleRetriever};
pub use store::{
    ChunkStore, EmbeddedChunk, MemoryChunkStore, RetrievalFilter, ScoredChunk,
};

/// Resolve the curated `rules/` directory relative to common workspace layouts.
pub fn default_rules_dir() -> Option<std::path::PathBuf> {
    let candidates = [
        std::path::PathBuf::from("rules"),
        std::path::PathBuf::from("../rules"),
        std::path::PathBuf::from("../../rules"),
        std::path::PathBuf::from("../../../rules"),
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../rules"),
    ];
    candidates.into_iter().find(|p| p.is_dir())
}

/// Resolve this crate's SQL migrations directory.
pub fn default_migrations_dir() -> Option<std::path::PathBuf> {
    let candidates = [
        std::path::PathBuf::from("crates/judgement-rag/migrations"),
        std::path::PathBuf::from("backend/crates/judgement-rag/migrations"),
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("migrations"),
    ];
    candidates.into_iter().find(|p| p.is_dir())
}
