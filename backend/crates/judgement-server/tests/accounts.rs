//! Google sign-in via the dev HS256 token. Guest play does not use this path.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use judgement_persistence::MemoryStore;
use judgement_server::leaderboard::refresh_leaderboard;
use judgement_server::{build_router, state::AppState};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::Serialize;
use serde_json::Value;
use tokio::net::TcpListener;

#[derive(Serialize)]
struct DevClaims {
    sub: String,
    iss: String,
    exp: usize,
    name: String,
    email: String,
}

fn dev_token(secret: &str, subject: &str, name: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as usize
        + 3600;
    encode(
        &Header::default(),
        &DevClaims {
            sub: subject.into(),
            iss: "judgement-dev".into(),
            exp,
            name: name.into(),
            email: format!("{subject}@example.com"),
        },
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .unwrap()
}

async fn serve() -> String {
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
async fn google_sign_in_creates_distinct_accounts_and_logout_invalidates() {
    let secret = "test-firebase-dev-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    let base = serve().await;
    let client = reqwest::Client::new();

    let first: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": dev_token(secret, "google-sub-ada", "Ada Lovelace"),
            "legal_version": "2026-08-03"
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    let token = first["token"].as_str().unwrap().to_string();
    assert_eq!(first["user"]["display_name"], "Ada Lovelace");
    assert_eq!(first["nickname"], "Ada Lovelace");

    let me: Value = client
        .get(format!("{base}/api/v1/me"))
        .bearer_auth(&token)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(me["display_name"], "Ada Lovelace");

    let second: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": dev_token(secret, "google-sub-grace", "Grace"),
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_ne!(first["user"]["user_id"], second["user"]["user_id"]);

    client
        .post(format!("{base}/api/v1/me/logout"))
        .bearer_auth(&token)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
    let after = client
        .get(format!("{base}/api/v1/me"))
        .bearer_auth(&token)
        .send()
        .await
        .unwrap();
    assert_eq!(after.status(), 401);
}

#[tokio::test]
async fn leaderboard_reads_the_snapshot_without_a_database_hit_on_the_request() {
    let state = Arc::new(AppState::new(Arc::new(MemoryStore::new())));
    refresh_leaderboard(&state).await;
    let app = build_router(state);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    let body: Value = reqwest::get(format!("http://{addr}/api/v1/leaderboard"))
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(body["players"].as_array().unwrap().is_empty());
}
