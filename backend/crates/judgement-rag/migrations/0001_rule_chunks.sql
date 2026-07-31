-- Phase 7b: curated rule chunks + pgvector embeddings (PLAN.md §18.1, ADR 0002).
-- Embedding dimension is fixed at 64 for both the deterministic local embedder
-- and shortened OpenAI text-embedding-3-small (dimensions=64).

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS rule_chunks (
    chunk_id                  TEXT NOT NULL,
    rule_id                   TEXT NOT NULL,
    ruleset_version           TEXT NOT NULL,
    category                  TEXT NOT NULL,
    player_count              SMALLINT,
    variant                   TEXT,
    embedding_model_version   TEXT NOT NULL,
    content                   TEXT NOT NULL,
    source_path               TEXT NOT NULL,
    embedding                 vector(64) NOT NULL,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (chunk_id, embedding_model_version)
);

CREATE INDEX IF NOT EXISTS rule_chunks_ruleset_embed_idx
    ON rule_chunks (ruleset_version, embedding_model_version);

CREATE INDEX IF NOT EXISTS rule_chunks_embedding_hnsw_idx
    ON rule_chunks USING hnsw (embedding vector_cosine_ops);
