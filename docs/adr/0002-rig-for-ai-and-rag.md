# ADR 0002 — Use Rig for the AI layer and the RAG pipeline

**Status:** Accepted
**Date:** 2026-07-30
**Relates to:** PLAN.md §18, §19, §20, §32, Phase 7 / Phase 7b

## Context

The plan requires:

- An **LLM client / provider abstraction** in `judgement-ai` (prompt templates,
  structured output, timeouts, cost caps, deterministic fallbacks).
- An optional, **feature-flagged vector RAG** pipeline in `judgement-rag` over
  the curated rule corpus, stored in **PostgreSQL + pgvector** with
  embedding-model versioning (Phase 7b).
- Hard boundaries: AI never mutates game state, never sees hidden cards, and
  gameplay must continue when AI is unavailable.

Writing provider clients, embedding plumbing, and vector-store adapters by hand
is undifferentiated work. [Rig](https://rig.rs) (`rig-core`) is a Rust LLM
framework with 20+ providers behind one API, provider-agnostic embeddings,
structured extraction, and 10+ vector-store adapters — including
[`rig-postgres`](https://crates.io/crates/rig-postgres), a pgvector-backed
store, which matches the plan's mandated storage exactly.

The same team already uses this pattern successfully in the booking-system
project: **Rig handles LLM I/O only; the deterministic core owns routing,
validation, and truth.**

## Decision

1. `judgement-ai` uses **`rig-core`** for LLM completions and embeddings:
   - Agents/preambles for the FAQ-rewrite, coaching, and highlights prompts.
   - Structured JSON output parsed and **validated by our code** — Rig returns
     text/JSON; legality, identifiers, and rule references are verified against
     the engine before anything reaches a client.
   - Optionally routed through a LiteLLM-style proxy for model cascades and
     cost control (as in the booking system), decided at deployment time.
2. `judgement-rag` (Phase 7b, feature-flagged) uses **`rig-postgres`**:
   - Rule documents chunked with metadata (`rule_id`, `ruleset_version`,
     `category`, `player_count`, `variant`).
   - Embeddings stored in pgvector with the **embedding-model version**;
     retrieval filters on ruleset version and embedding version.
   - The flag off means behaviour is identical to Phase 7 (curated FAQ only).
3. Rig is **not** used for:
   - Gameplay decisions (bots are pure Rust — engine/heuristics/Monte Carlo).
   - Tool execution or anything that mutates state — AI-suggested actions are
     advisory and pass through normal engine validation (PLAN.md §3.3).
   - The MVP explanation path, which stays deterministic (reason codes +
     templates + curated FAQ, locked decision 3).

## Consequences

- One dependency covers providers, embeddings, and pgvector retrieval; no
  bespoke HTTP clients per provider.
- The AI layer stays swappable: everything behind our own trait in
  `judgement-ai`, so Rig is an implementation detail, not a public contract.
- Timeouts, rate limits, cost caps, and deterministic fallbacks remain **our**
  responsibility (PLAN.md §20) — Rig does not provide them out of the box.
- Dependencies are added only when Phase 7 begins (PLAN.md §29.2: no
  infrastructure before it is needed). Versions at time of writing:
  `rig-core 0.36`, `rig-postgres 0.2`.
- **Phase 7b implementation note (2026-07-31):** `judgement-rag` owns chunking,
  metadata filters (`ruleset_version`, `embedding_model_version`), and storage.
  The default path uses a deterministic 64-d hasher + sqlx/pgvector so retrieval
  evaluation and local ingest work without an API key. Optional Rig OpenAI
  embeddings (`judgement-rag` feature `rig`, shortened to 64-d) remain available;
  runtime flag `RAG_ENABLED=1` gates the whole pipeline (flag off ≡ Phase 7).

## Alternatives considered

- **Hand-rolled provider clients (reqwest + serde):** rejected — repeated
  boilerplate per provider, no shared embedding/vector abstractions.
- **async-openai / provider-specific SDKs:** rejected — locks the code to one
  provider; the plan requires a provider abstraction.
- **External RAG service (Python/LangChain sidecar):** rejected for MVP scale —
  adds a deployment unit and crosses the language boundary for a small corpus.
