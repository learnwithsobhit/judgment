//! Chunk + embed + upsert pipeline.

use std::path::Path;
use std::sync::Arc;

use crate::chunk::chunk_rules_dir;
use crate::embed::Embedder;
use crate::error::RagError;
use crate::store::{ChunkStore, EmbeddedChunk};

/// Ingest all curated rule docs under `rules_dir` for the embedder's model version.
pub async fn ingest_rules_dir(
    rules_dir: impl AsRef<Path>,
    embedder: Arc<dyn Embedder>,
    store: Arc<dyn ChunkStore>,
) -> Result<usize, RagError> {
    let chunks = chunk_rules_dir(rules_dir)?;
    if chunks.is_empty() {
        return Ok(0);
    }

    let texts: Vec<String> = chunks.iter().map(|c| c.content.clone()).collect();
    let embeddings = embedder.embed(&texts).await?;
    if embeddings.len() != chunks.len() {
        return Err(RagError::Embed("embedding count mismatch".into()));
    }

    let model = embedder.model_version().to_string();
    let embedded: Vec<EmbeddedChunk> = chunks
        .into_iter()
        .zip(embeddings)
        .map(|(chunk, embedding)| EmbeddedChunk {
            chunk,
            embedding_model_version: model.clone(),
            embedding,
        })
        .collect();

    let n = embedded.len();
    store.upsert(&embedded).await?;
    Ok(n)
}

/// Ingest when the store has no rows for this ruleset + embedding version.
pub async fn ensure_ingested(
    rules_dir: impl AsRef<Path>,
    embedder: Arc<dyn Embedder>,
    store: Arc<dyn ChunkStore>,
    ruleset_version: &str,
) -> Result<usize, RagError> {
    let model = embedder.model_version().to_string();
    let existing = store.count(ruleset_version, &model).await?;
    if existing > 0 {
        tracing::info!(
            existing,
            ruleset_version,
            embedding_model_version = %model,
            "rule chunks already ingested"
        );
        return Ok(0);
    }
    let n = ingest_rules_dir(rules_dir, embedder, store).await?;
    tracing::info!(n, ruleset_version, embedding_model_version = %model, "ingested rule chunks");
    Ok(n)
}
