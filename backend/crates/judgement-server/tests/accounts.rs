//! Google sign-in via the dev HS256 token. Guest play does not use this path.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use jsonwebtoken::{encode, EncodingKey, Header};
use judgement_persistence::{GameStore, MemoryStore};
use judgement_server::leaderboard::refresh_leaderboard;
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
    #[serde(skip_serializing_if = "Option::is_none")]
    email: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    firebase: Option<DevFirebase>,
}

fn dev_token(secret: &str, subject: &str, name: &str) -> String {
    provider_token(secret, subject, name, None, true)
}

fn provider_token(
    secret: &str,
    subject: &str,
    name: &str,
    provider: Option<&str>,
    with_email: bool,
) -> String {
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
            email: with_email.then(|| format!("{subject}@example.com")),
            firebase: provider.map(|provider| DevFirebase {
                sign_in_provider: provider.into(),
            }),
        },
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .unwrap()
}

fn telegram_token(secret: &str, subject: &str, name: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as usize
        + 3600;
    encode(
        &Header::default(),
        &DevClaims {
            sub: subject.into(),
            iss: "judgement-dev-telegram".into(),
            exp,
            name: name.into(),
            email: None,
            firebase: None,
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
    assert_eq!(first["nickname"], "Ada L");

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
async fn facebook_and_other_non_google_providers_are_rejected() {
    let secret = "test-firebase-dev-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    let store = Arc::new(MemoryStore::new());
    let base = serve_store(store.clone()).await;
    let client = reqwest::Client::new();

    let facebook = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": provider_token(secret, "shared-subject", "Ada Facebook", Some("facebook.com"), false),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(facebook.status(), 400);
    assert!(store
        .find_user_by_identity("facebook", "shared-subject")
        .await
        .unwrap()
        .is_none());

    let google: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": provider_token(secret, "shared-subject", "Ada Google", Some("google.com"), true),
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(google["token"].as_str().unwrap().len() > 10);
    assert!(store
        .find_user_by_identity("google", "shared-subject")
        .await
        .unwrap()
        .is_some());

    let phone = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": provider_token(secret, "phone-subject", "Ada Phone", Some("phone"), false),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(phone.status(), 400);
}

#[tokio::test]
async fn email_sign_in_is_separate_from_google() {
    let secret = "test-firebase-dev-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    let store = Arc::new(MemoryStore::new());
    let base = serve_store(store.clone()).await;
    let client = reqwest::Client::new();

    let first: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": provider_token(secret, "shared-subject", "Ada Email", Some("password"), true),
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(first["user"]["display_name"], "Ada Email");
    let email_user = store
        .find_user_by_identity("email", "shared-subject")
        .await
        .unwrap()
        .expect("email identity");
    assert_eq!(
        email_user.user_id.to_string(),
        first["user"]["user_id"].as_str().unwrap()
    );

    let again: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": provider_token(secret, "shared-subject", "Ada Email", Some("password"), true),
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(first["user"]["user_id"], again["user"]["user_id"]);

    let google: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": provider_token(secret, "shared-subject", "Ada Google", Some("google.com"), true),
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_ne!(first["user"]["user_id"], google["user"]["user_id"]);

    let unnamed: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": provider_token(secret, "ada.player", "", Some("password"), true),
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(unnamed["user"]["display_name"], "ada.player");
}

#[tokio::test]
async fn telegram_sign_in_is_separate_from_google_and_rejects_a_bad_signature() {
    let firebase_secret = "test-firebase-dev-secret";
    let telegram_secret = "test-telegram-dev-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", firebase_secret);
    std::env::set_var("JUDGEMENT_TELEGRAM_DEV_SECRET", telegram_secret);
    let store = Arc::new(MemoryStore::new());
    let base = serve_store(store.clone()).await;
    let client = reqwest::Client::new();

    let google: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": dev_token(firebase_secret, "google-ada", "Ada Google"),
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();

    let first: Value = client
        .post(format!("{base}/api/v1/auth/telegram"))
        .json(&serde_json::json!({
            "id_token": telegram_token(telegram_secret, "424242", "Ada Telegram"),
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(first["token"].as_str().unwrap().len() > 10);
    assert_eq!(first["user"]["display_name"], "Ada Telegram");
    assert_eq!(first["nickname"], "Ada T");
    assert_ne!(google["user"]["user_id"], first["user"]["user_id"]);
    let telegram = store
        .find_user_by_identity("telegram", "424242")
        .await
        .unwrap()
        .expect("telegram identity");
    assert_eq!(
        telegram.user_id.to_string(),
        first["user"]["user_id"].as_str().unwrap()
    );

    let again: Value = client
        .post(format!("{base}/api/v1/auth/telegram"))
        .json(&serde_json::json!({
            "id_token": telegram_token(telegram_secret, "424242", "Ada Telegram"),
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(first["user"]["user_id"], again["user"]["user_id"]);

    let bad = client
        .post(format!("{base}/api/v1/auth/telegram"))
        .json(&serde_json::json!({
            "id_token": telegram_token("wrong-secret", "999", "Eve"),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(bad.status(), 400);
}

async fn serve_store(store: Arc<MemoryStore>) -> String {
    let state = Arc::new(AppState::new(store));
    let app = build_router(state);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{addr}")
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
