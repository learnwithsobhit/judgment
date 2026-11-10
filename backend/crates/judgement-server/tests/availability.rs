//! Public free-to-play list and the signed-in switch.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use jsonwebtoken::{encode, EncodingKey, Header};
use judgement_persistence::MemoryStore;
use judgement_server::{build_router, state::AppState};
use serde::Serialize;
use serde_json::Value;
use tokio::net::TcpListener;

#[derive(Serialize)]
struct DevFirebase {
    sign_in_provider: String,
}

#[derive(Serialize)]
struct DevClaims {
    sub: String,
    iss: String,
    exp: usize,
    name: String,
    email: Option<String>,
    firebase: Option<DevFirebase>,
}

fn google_token(secret: &str, subject: &str, name: &str) -> String {
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
            email: Some(format!("{subject}@example.com")),
            firebase: Some(DevFirebase {
                sign_in_provider: "google.com".into(),
            }),
        },
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .unwrap()
}

async fn serve() -> String {
    let app = build_router(Arc::new(AppState::new(Arc::new(MemoryStore::new()))));
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{addr}")
}

async fn sign_in(
    client: &reqwest::Client,
    base: &str,
    secret: &str,
    subject: &str,
    name: &str,
) -> (String, String) {
    let body: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": google_token(secret, subject, name),
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
    (
        body["token"].as_str().unwrap().to_string(),
        body["user"]["user_id"].as_str().unwrap().to_string(),
    )
}

async fn board(client: &reqwest::Client, base: &str) -> Value {
    client
        .get(format!("{base}/api/v1/availability"))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap()
}

#[tokio::test]
async fn guest_cannot_mark_available() {
    let base = serve().await;
    let client = reqwest::Client::new();
    let guest: Value = client
        .post(format!("{base}/api/v1/guest-sessions"))
        .json(&serde_json::json!({ "nickname": "Guest" }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let res = client
        .put(format!("{base}/api/v1/me/availability"))
        .bearer_auth(guest["token"].as_str().unwrap())
        .json(&serde_json::json!({ "available": true }))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 401);
}

#[tokio::test]
async fn signed_in_put_then_public_get_and_ready_at_three() {
    let secret = "test-firebase-dev-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    let base = serve().await;
    let client = reqwest::Client::new();

    let empty = board(&client, &base).await;
    assert_eq!(empty["count"], 0);
    assert_eq!(empty["ready"], false);
    assert!(empty["players"].as_array().unwrap().is_empty());

    let (ada_token, ada_id) = sign_in(&client, &base, secret, "ada", "Ada").await;
    client
        .put(format!("{base}/api/v1/me/availability"))
        .bearer_auth(&ada_token)
        .json(&serde_json::json!({ "available": true }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();

    let one = board(&client, &base).await;
    assert_eq!(one["count"], 1);
    assert_eq!(one["ready"], false);
    assert_eq!(one["players"][0]["user_id"], ada_id);
    assert_eq!(one["players"][0]["display_name"], "Ada");
    assert!(one["players"][0]["email"].is_null());

    let (grace_token, _) = sign_in(&client, &base, secret, "grace", "Grace").await;
    client
        .put(format!("{base}/api/v1/me/availability"))
        .bearer_auth(&grace_token)
        .json(&serde_json::json!({ "available": true }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
    let two = board(&client, &base).await;
    assert_eq!(two["count"], 2);
    assert_eq!(two["ready"], false);

    let (beena_token, _) = sign_in(&client, &base, secret, "beena", "Beena").await;
    client
        .put(format!("{base}/api/v1/me/availability"))
        .bearer_auth(&beena_token)
        .json(&serde_json::json!({ "available": true }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
    let three = board(&client, &base).await;
    assert_eq!(three["count"], 3);
    assert_eq!(three["ready"], true);

    client
        .put(format!("{base}/api/v1/me/availability"))
        .bearer_auth(&ada_token)
        .json(&serde_json::json!({ "available": false }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
    let after = board(&client, &base).await;
    assert_eq!(after["count"], 2);
    assert_eq!(after["ready"], false);
}
