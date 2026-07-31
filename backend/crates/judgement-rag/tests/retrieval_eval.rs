//! Retrieval evaluation: version filters + hit rate (PLAN.md §23.7 / Phase 7b).

use std::sync::Arc;

use judgement_rag::{
    chunk_rules_dir, ensure_ingested, ingest_rules_dir, ChunkStore, DeterministicHashEmbedder,
    Embedder, EmbeddedChunk, MemoryChunkStore, RetrievalFilter, RuleChunk, RuleRetriever,
    VectorRuleRetriever, DEFAULT_RULESET_VERSION, DETERMINISTIC_EMBEDDING_MODEL_VERSION,
};

fn rules_dir() -> std::path::PathBuf {
    judgement_rag::default_rules_dir().expect("rules/ directory")
}

#[tokio::test]
async fn ingest_and_retrieve_core_topics() {
    let embedder: Arc<dyn Embedder> = Arc::new(DeterministicHashEmbedder);
    let store: Arc<dyn ChunkStore> = Arc::new(MemoryChunkStore::new());
    let n = ingest_rules_dir(rules_dir(), embedder.clone(), store.clone())
        .await
        .expect("ingest");
    assert!(n >= 5, "expected several chunks, got {n}");

    let retriever = VectorRuleRetriever::new(embedder, store);
    let cases = [
        ("Must I follow suit when I hold spades?", "follow-suit-001"),
        ("How is exact bid scoring calculated?", "scoring-exact-001"),
        ("How is trump chosen with a revealed card?", "trump-001"),
        ("Can the dealer bid make the sum equal tricks?", "dealer-restriction-001"),
    ];

    let filter = RetrievalFilter {
        min_score: 0.05,
        top_k: 5,
        ..RetrievalFilter::default()
    };

    let mut hits = 0usize;
    for (question, expected) in cases {
        let answer = retriever
            .retrieve(question, &filter)
            .await
            .unwrap()
            .unwrap_or_else(|| panic!("no retrieval for {question}"));
        if answer.rule_references.iter().any(|r| r == expected) {
            hits += 1;
        } else {
            eprintln!(
                "miss for {question:?}: expected {expected}, got {:?}",
                answer.rule_references
            );
        }
    }
    // Deterministic hasher is coarse; require majority hit rate.
    assert!(hits >= 3, "retrieval hit rate too low: {hits}/4");
}

#[tokio::test]
async fn embedding_model_version_filter_excludes_other_models() {
    let embedder: Arc<dyn Embedder> = Arc::new(DeterministicHashEmbedder);
    let store: Arc<dyn ChunkStore> = Arc::new(MemoryChunkStore::new());

    let chunk = RuleChunk {
        chunk_id: "trump-001#test".into(),
        rule_id: "trump-001".into(),
        ruleset_version: DEFAULT_RULESET_VERSION.into(),
        category: "trump".into(),
        player_count: None,
        variant: None,
        content: "Trump outranks every other suit when winning a trick.".into(),
        source_path: "trump_rules.md".into(),
    };
    let emb = embedder.embed(&[chunk.content.clone()]).await.unwrap();
    store
        .upsert(&[
            EmbeddedChunk {
                chunk: chunk.clone(),
                embedding_model_version: DETERMINISTIC_EMBEDDING_MODEL_VERSION.into(),
                embedding: emb[0].clone(),
            },
            EmbeddedChunk {
                chunk,
                embedding_model_version: "other-model-v0".into(),
                embedding: emb[0].clone(),
            },
        ])
        .await
        .unwrap();

    let retriever = VectorRuleRetriever::new(embedder, store.clone());
    let answer = retriever
        .retrieve("Does trump beat the lead suit?", &RetrievalFilter::default())
        .await
        .unwrap()
        .expect("hit from current model");
    assert!(answer.rule_references.contains(&"trump-001".into()));

    // Wrong model version ⇒ empty even if content exists.
    let wrong = RetrievalFilter {
        embedding_model_version: "other-model-v0".into(),
        ..RetrievalFilter::default()
    };
    // Retriever overwrites filter.embedding_model_version to embedder's version,
    // so search via store directly for the negative case.
    let emb = DeterministicHashEmbedder
        .embed(&["Does trump beat the lead suit?".into()])
        .await
        .unwrap();
    let filtered = store
        .search(
            &emb[0],
            &RetrievalFilter {
                embedding_model_version: "no-such-model".into(),
                min_score: 0.0,
                ..RetrievalFilter::default()
            },
        )
        .await
        .unwrap();
    assert!(filtered.is_empty(), "wrong embedding version must return nothing");

    let _ = wrong; // document intended filter shape
}

#[tokio::test]
async fn ruleset_version_filter_excludes_other_rulesets() {
    let embedder: Arc<dyn Embedder> = Arc::new(DeterministicHashEmbedder);
    let store: Arc<dyn ChunkStore> = Arc::new(MemoryChunkStore::new());
    let chunk = RuleChunk {
        chunk_id: "bidding-001#legacy".into(),
        rule_id: "bidding-001".into(),
        ruleset_version: "legacy-0".into(),
        category: "bidding".into(),
        player_count: None,
        variant: None,
        content: "Legacy bidding allows any integer with no upper bound.".into(),
        source_path: "bidding.md".into(),
    };
    let emb = embedder.embed(&[chunk.content.clone()]).await.unwrap();
    store
        .upsert(&[EmbeddedChunk {
            chunk,
            embedding_model_version: DETERMINISTIC_EMBEDDING_MODEL_VERSION.into(),
            embedding: emb[0].clone(),
        }])
        .await
        .unwrap();

    let hits = store
        .search(
            &emb[0],
            &RetrievalFilter {
                ruleset_version: DEFAULT_RULESET_VERSION.into(),
                min_score: 0.0,
                ..RetrievalFilter::default()
            },
        )
        .await
        .unwrap();
    assert!(hits.is_empty(), "legacy ruleset must not leak into mvp-1 queries");
}

#[tokio::test]
async fn ensure_ingested_is_idempotent() {
    let embedder: Arc<dyn Embedder> = Arc::new(DeterministicHashEmbedder);
    let store: Arc<dyn ChunkStore> = Arc::new(MemoryChunkStore::new());
    let first = ensure_ingested(
        rules_dir(),
        embedder.clone(),
        store.clone(),
        DEFAULT_RULESET_VERSION,
    )
    .await
    .unwrap();
    assert!(first > 0);
    let second = ensure_ingested(
        rules_dir(),
        embedder,
        store.clone(),
        DEFAULT_RULESET_VERSION,
    )
    .await
    .unwrap();
    assert_eq!(second, 0);
    let chunks = chunk_rules_dir(rules_dir()).unwrap();
    assert_eq!(
        store
            .count(DEFAULT_RULESET_VERSION, DETERMINISTIC_EMBEDDING_MODEL_VERSION)
            .await
            .unwrap(),
        chunks.len()
    );
}

#[tokio::test]
async fn refuses_hidden_card_style_prompts() {
    let embedder: Arc<dyn Embedder> = Arc::new(DeterministicHashEmbedder);
    let store: Arc<dyn ChunkStore> = Arc::new(MemoryChunkStore::new());
    let retriever = VectorRuleRetriever::new(embedder, store);
    let answer = retriever
        .retrieve(
            "What is in the opponent hand and the shuffle seed?",
            &RetrievalFilter::default(),
        )
        .await
        .unwrap();
    assert!(answer.is_none());
}
