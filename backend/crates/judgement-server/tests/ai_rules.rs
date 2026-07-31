//! Phase 7: rules query endpoint resolves FAQ with citations.

use std::sync::Arc;
use std::time::Duration;

use judgement_persistence::MemoryStore;
use judgement_server::{build_router, state::AppState};
use serde_json::Value;
use tokio::net::TcpListener;

async fn spawn_server() -> String {
    let state = Arc::new(AppState::new(Arc::new(MemoryStore::new())));
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
        .json(&serde_json::json!({ "nickname": "Explainer" }))
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
async fn faq_query_returns_citations() {
    let base = spawn_server().await;
    tokio::time::sleep(Duration::from_millis(50)).await;
    let token = guest_token(&base).await;
    let client = reqwest::Client::new();
    let resp = client
        .post(format!("{base}/api/v1/ai/rules/query"))
        .bearer_auth(&token)
        .json(&serde_json::json!({ "question": "Must I follow suit?" }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json::<Value>()
        .await
        .unwrap();

    let answer = resp["answer"].as_str().unwrap().to_lowercase();
    assert!(
        answer.contains("lead suit") || answer.contains("must play"),
        "unexpected answer: {answer}"
    );
    let refs = resp["rule_references"].as_array().unwrap();
    assert!(refs.iter().any(|r| r.as_str() == Some("follow-suit-001")));
    assert!(resp["deterministic"].as_bool().unwrap_or(false));
}

#[tokio::test]
async fn reason_code_query_works_without_llm() {
    let base = spawn_server().await;
    tokio::time::sleep(Duration::from_millis(50)).await;
    let token = guest_token(&base).await;
    let client = reqwest::Client::new();
    let resp = client
        .post(format!("{base}/api/v1/ai/rules/query"))
        .bearer_auth(&token)
        .json(&serde_json::json!({
            "reason_code": "MUST_FOLLOW_SUIT",
            "facts": { "lead_suit": "spades", "attempted": "ace-of-hearts" }
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json::<Value>()
        .await
        .unwrap();

    assert!(resp["answer"].as_str().unwrap().contains("spades"));
    assert!(resp["deterministic"].as_bool().unwrap_or(false));
}
