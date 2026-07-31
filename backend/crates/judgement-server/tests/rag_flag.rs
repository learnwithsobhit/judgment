//! Phase 7b: flag off ≡ Phase 7; flag on can answer via retrieval after FAQ miss.

use std::sync::Arc;
use std::time::Duration;

use judgement_ai::ExplanationService;
use judgement_persistence::MemoryStore;
use judgement_rag::{
    default_rules_dir, ensure_ingested, ChunkStore, DeterministicHashEmbedder, Embedder,
    MemoryChunkStore, RetrievalFilter, VectorRuleRetriever, DEFAULT_RULESET_VERSION,
};
use judgement_server::{build_router, state::AppState};
use serde_json::Value;
use tokio::net::TcpListener;

async fn spawn_with(explanations: ExplanationService) -> String {
    let state = Arc::new(AppState::with_explanations(
        Arc::new(MemoryStore::new()),
        explanations,
    ));
    let app = build_router(state);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{addr}")
}

async fn guest_token(base: &str) -> String {
    let client = reqwest::Client::new();
    let resp = client
        .post(format!("{base}/api/v1/guest-sessions"))
        .json(&serde_json::json!({ "nickname": "RagTester" }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json::<Value>()
        .await
        .unwrap();
    resp["token"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn flag_off_unknown_question_stays_low_confidence() {
    let base = spawn_with(ExplanationService::default()).await;
    tokio::time::sleep(Duration::from_millis(40)).await;
    let token = guest_token(&base).await;
    let client = reqwest::Client::new();
    let resp = client
        .post(format!("{base}/api/v1/ai/rules/query"))
        .bearer_auth(&token)
        .json(&serde_json::json!({
            "question": "Explain the obscure regional nil variant in detail please"
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json::<Value>()
        .await
        .unwrap();
    assert!(resp["confidence"].as_f64().unwrap() <= 0.25);
    assert!(resp["answer"]
        .as_str()
        .unwrap()
        .contains("could not find"));
}

#[tokio::test]
async fn flag_on_retrieves_after_faq_miss() {
    let embedder: Arc<dyn Embedder> = Arc::new(DeterministicHashEmbedder);
    let store: Arc<dyn ChunkStore> = Arc::new(MemoryChunkStore::new());
    ensure_ingested(
        default_rules_dir().expect("rules/"),
        embedder.clone(),
        store.clone(),
        DEFAULT_RULESET_VERSION,
    )
    .await
    .unwrap();
    let retriever = Arc::new(VectorRuleRetriever::new(embedder, store));
    let service = ExplanationService::default()
        .with_retriever(retriever)
        .with_retrieval_filter(RetrievalFilter {
            min_score: 0.05,
            top_k: 5,
            ..RetrievalFilter::default()
        });

    let base = spawn_with(service).await;
    tokio::time::sleep(Duration::from_millis(40)).await;
    let token = guest_token(&base).await;
    let client = reqwest::Client::new();
    // Phrase unlikely to hit FAQ aliases but close to following_suit.md content.
    let resp = client
        .post(format!("{base}/api/v1/ai/rules/query"))
        .bearer_auth(&token)
        .json(&serde_json::json!({
            "question": "When a trick is led what suit am I required to play if I still hold that suit?"
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json::<Value>()
        .await
        .unwrap();

    let refs = resp["rule_references"].as_array().unwrap();
    assert!(
        refs.iter().any(|r| r.as_str() == Some("follow-suit-001")),
        "expected RAG citation, got {refs:?} answer={}",
        resp["answer"]
    );
    assert!(resp["confidence"].as_f64().unwrap() > 0.25);
}
