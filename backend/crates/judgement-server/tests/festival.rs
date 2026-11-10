//! Public config and the admin festival switch.

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

fn google_token(secret: &str, subject: &str, name: &str, email: &str) -> String {
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
            email: Some(email.into()),
            firebase: Some(DevFirebase {
                sign_in_provider: "google.com".into(),
            }),
        },
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .unwrap()
}

async fn serve(state: AppState) -> String {
    let app = build_router(Arc::new(state));
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{addr}")
}

async fn sign_in(client: &reqwest::Client, base: &str, secret: &str, email: &str) -> String {
    let body: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": google_token(secret, email, "Ada", email),
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
    body["token"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn public_config_defaults_to_off() {
    let base = serve(AppState::new(Arc::new(MemoryStore::new()))).await;
    let body: Value = reqwest::Client::new()
        .get(format!("{base}/api/v1/config"))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(body["festival_id"], "off");
}

#[tokio::test]
async fn guest_cannot_set_festival() {
    let base = serve(AppState::new(Arc::new(MemoryStore::new()))).await;
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
    let token = guest["token"].as_str().unwrap();
    let res = client
        .patch(format!("{base}/api/v1/admin/festival"))
        .bearer_auth(token)
        .json(&serde_json::json!({ "id": "diwali" }))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 401);
}

#[tokio::test]
async fn signed_in_non_admin_is_forbidden() {
    let secret = "festival-firebase-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    let mut state = AppState::new(Arc::new(MemoryStore::new()));
    state.admin_emails = vec!["admin@example.com".into()];
    let base = serve(state).await;
    let client = reqwest::Client::new();
    let token = sign_in(&client, &base, secret, "player@example.com").await;
    let me: Value = client
        .get(format!("{base}/api/v1/me"))
        .bearer_auth(&token)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(me["is_admin"], false);
    let res = client
        .patch(format!("{base}/api/v1/admin/festival"))
        .bearer_auth(&token)
        .json(&serde_json::json!({ "id": "diwali" }))
        .send()
        .await
        .unwrap();
    assert_eq!(res.status(), 403);
}

#[tokio::test]
async fn admin_sets_festival_and_config_follows() {
    let secret = "festival-firebase-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    let mut state = AppState::new(Arc::new(MemoryStore::new()));
    state.admin_emails = vec!["chaturvedi99@gmail.com".into()];
    let base = serve(state).await;
    let client = reqwest::Client::new();
    let token = sign_in(&client, &base, secret, "chaturvedi99@gmail.com").await;
    let me: Value = client
        .get(format!("{base}/api/v1/me"))
        .bearer_auth(&token)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(me["is_admin"], true);

    let unknown = client
        .patch(format!("{base}/api/v1/admin/festival"))
        .bearer_auth(&token)
        .json(&serde_json::json!({ "id": "songkran" }))
        .send()
        .await
        .unwrap();
    assert_eq!(unknown.status(), 400);

    let set: Value = client
        .patch(format!("{base}/api/v1/admin/festival"))
        .bearer_auth(&token)
        .json(&serde_json::json!({ "id": "diwali" }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(set["festival_id"], "diwali");

    let config: Value = client
        .get(format!("{base}/api/v1/config"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(config["festival_id"], "diwali");
}
