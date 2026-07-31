//! Embedding providers. Default is a local deterministic hasher (no network).
//! Optional Rig/OpenAI path is feature-gated (ADR 0002).

use async_trait::async_trait;

use crate::error::RagError;

/// Fixed dimension for `rule_chunks.embedding vector(64)`.
pub const EMBEDDING_DIM: usize = 64;

/// Version string stored beside every embedding; retrieval must filter on it.
pub const DETERMINISTIC_EMBEDDING_MODEL_VERSION: &str = "deterministic-hash-v1";

#[async_trait]
pub trait Embedder: Send + Sync {
    fn model_version(&self) -> &str;
    async fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>, RagError>;
}

/// Local bag-of-hashed-tokens embedder. Stable across runs; good enough for
/// retrieval evaluation and offline ingest without an API key.
#[derive(Debug, Default, Clone, Copy)]
pub struct DeterministicHashEmbedder;

#[async_trait]
impl Embedder for DeterministicHashEmbedder {
    fn model_version(&self) -> &str {
        DETERMINISTIC_EMBEDDING_MODEL_VERSION
    }

    async fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>, RagError> {
        Ok(texts.iter().map(|t| hash_embed(t)).collect())
    }
}

fn hash_embed(text: &str) -> Vec<f32> {
    let mut vec = vec![0.0_f32; EMBEDDING_DIM];
    let tokens = tokenize(text);
    if tokens.is_empty() {
        return normalize(&mut vec);
    }
    for token in &tokens {
        let h = fnv1a64(token);
        let idx = (h as usize) % EMBEDDING_DIM;
        let sign = if h & 1 == 0 { 1.0 } else { -1.0 };
        vec[idx] += sign;
        // Bigram boost
        let h2 = fnv1a64(&format!("#{token}"));
        let idx2 = (h2 as usize) % EMBEDDING_DIM;
        vec[idx2] += 0.5 * if h2 & 1 == 0 { 1.0 } else { -1.0 };
    }
    normalize(&mut vec)
}

fn tokenize(text: &str) -> Vec<String> {
    text.chars()
        .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .filter(|t| t.len() > 1)
        .map(|t| t.to_string())
        .collect()
}

fn normalize(v: &mut [f32]) -> Vec<f32> {
    let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 0.0 {
        for x in v.iter_mut() {
            *x /= norm;
        }
    }
    v.to_vec()
}

fn fnv1a64(s: &str) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for b in s.as_bytes() {
        hash ^= u64::from(*b);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

pub fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }
    let mut dot = 0.0;
    let mut na = 0.0;
    let mut nb = 0.0;
    for i in 0..a.len() {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    let denom = na.sqrt() * nb.sqrt();
    if denom == 0.0 {
        0.0
    } else {
        dot / denom
    }
}

#[cfg(feature = "rig")]
pub mod rig_openai {
    use async_trait::async_trait;
    use rig::embeddings::EmbeddingModel;
    use rig::providers::openai;

    use super::{Embedder, EMBEDDING_DIM};
    use crate::error::RagError;

    pub const OPENAI_EMBEDDING_MODEL_VERSION: &str = "text-embedding-3-small@64";

    /// OpenAI embeddings via Rig, requested at 64 dimensions to match the schema.
    pub struct RigOpenAiEmbedder {
        model: openai::EmbeddingModel,
    }

    impl RigOpenAiEmbedder {
        pub fn from_env() -> Result<Self, RagError> {
            let key = std::env::var("OPENAI_API_KEY")
                .map_err(|_| RagError::Embed("OPENAI_API_KEY unset".into()))?;
            if key.trim().is_empty() {
                return Err(RagError::Embed("OPENAI_API_KEY empty".into()));
            }
            let client = openai::Client::new(&key);
            // text-embedding-3-small supports shortened dimensions.
            let model = client.embedding_model_with_ndims("text-embedding-3-small", EMBEDDING_DIM);
            Ok(Self { model })
        }
    }

    #[async_trait]
    impl Embedder for RigOpenAiEmbedder {
        fn model_version(&self) -> &str {
            OPENAI_EMBEDDING_MODEL_VERSION
        }

        async fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>, RagError> {
            let mut out = Vec::with_capacity(texts.len());
            for text in texts {
                let embedding = self
                    .model
                    .embed_text(text)
                    .await
                    .map_err(|e| RagError::Embed(e.to_string()))?;
                let mut vals = embedding.vec;
                if vals.len() != EMBEDDING_DIM {
                    return Err(RagError::Embed(format!(
                        "expected {EMBEDDING_DIM} dims, got {}",
                        vals.len()
                    )));
                }
                out.push(std::mem::take(&mut vals));
            }
            Ok(out)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn similar_texts_score_higher() {
        let emb = DeterministicHashEmbedder;
        let vectors = emb
            .embed(&[
                "you must follow the lead suit".into(),
                "follow suit when you hold the lead suit".into(),
                "how is exact bid scoring calculated".into(),
            ])
            .await
            .unwrap();
        let sim_close = cosine_similarity(&vectors[0], &vectors[1]);
        let sim_far = cosine_similarity(&vectors[0], &vectors[2]);
        assert!(sim_close > sim_far, "close={sim_close} far={sim_far}");
    }
}
