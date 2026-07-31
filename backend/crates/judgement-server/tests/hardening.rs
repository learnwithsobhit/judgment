//! Phase 9: rate limit, metrics, readiness.

use std::sync::Arc;
use std::time::Duration;

use judgement_persistence::MemoryStore;
use judgement_server::{build_router, state::AppState};
use serde_json::Value;
use tokio::net::TcpListener;

async fn spawn_server() -> String {
    // HttpLimitConfig::default reads these env vars.
    std::env::set_var("HTTP_GUEST_RATE_LIMIT", "3");
    std::env::set_var("HTTP_RATE_LIMIT", "1000");
    std::env::set_var("HTTP_RATE_WINDOW_SECS", "60");

    let state = Arc::new(AppState::new(Arc::new(MemoryStore::new())));
    let app = build_router(state);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{addr}")
}

#[tokio::test]
async fn health_ready_metrics_and_guest_rate_limit() {
    let base = spawn_server().await;
    tokio::time::sleep(Duration::from_millis(40)).await;
    let client = reqwest::Client::new();

    assert_eq!(
        client
            .get(format!("{base}/healthz"))
            .send()
            .await
            .unwrap()
            .status(),
        200
    );
    assert_eq!(
        client
            .get(format!("{base}/readyz"))
            .send()
            .await
            .unwrap()
            .status(),
        200
    );

    let metrics = client
        .get(format!("{base}/metrics"))
        .send()
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    assert!(metrics.contains("judgement_http_requests_total"));
    assert!(metrics.contains("judgement_active_rooms"));

    for i in 0..3 {
        let status = client
            .post(format!("{base}/api/v1/guest-sessions"))
            .json(&serde_json::json!({ "nickname": format!("H{i}") }))
            .send()
            .await
            .unwrap()
            .status();
        assert_eq!(status, 200, "request {i}");
    }
    let limited = client
        .post(format!("{base}/api/v1/guest-sessions"))
        .json(&serde_json::json!({ "nickname": "Nope" }))
        .send()
        .await
        .unwrap();
    assert_eq!(limited.status(), 429);
    let body: Value = limited.json().await.unwrap();
    assert_eq!(body["error"]["code"], "RATE_LIMITED");
}
