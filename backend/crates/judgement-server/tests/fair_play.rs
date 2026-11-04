//! Fair play HTTP: roster eligibility, no ballot leak, board updates.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use chrono::Utc;
use jsonwebtoken::{encode, EncodingKey, Header};
use judgement_persistence::{FairPlayRosterSeat, GameStore, MemoryStore};
use judgement_server::{build_router, state::AppState};
use serde::Serialize;
use serde_json::Value;
use tokio::net::TcpListener;
use uuid::Uuid;

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

async fn sign_in(http: &reqwest::Client, base: &str, secret: &str, sub: &str, name: &str) -> Value {
    http.post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": dev_token(secret, sub, name),
            "legal_version": "2026-08-03"
        }))
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
async fn fair_play_http_hides_ballots_and_ranks_totals() {
    let secret = "fair-play-http-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    let store = Arc::new(MemoryStore::new());
    let state = Arc::new(AppState::new(store.clone()));
    let app = build_router(state);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let alice = sign_in(&http, &base, secret, "fp-alice", "Alice").await;
    let bob = sign_in(&http, &base, secret, "fp-bob", "Bob").await;
    let cara = sign_in(&http, &base, secret, "fp-cara", "Cara").await;
    let alice_token = alice["token"].as_str().unwrap();
    let alice_user = Uuid::parse_str(alice["user"]["user_id"].as_str().unwrap()).unwrap();
    let bob_user = Uuid::parse_str(bob["user"]["user_id"].as_str().unwrap()).unwrap();
    let cara_user = Uuid::parse_str(cara["user"]["user_id"].as_str().unwrap()).unwrap();

    let game_id = Uuid::new_v4();
    let finished = Utc::now();
    store
        .write_fair_play_roster(&[
            FairPlayRosterSeat {
                game_id,
                user_id: alice_user,
                player_id: Uuid::new_v4(),
                display_name: "Alice".into(),
                avatar_id: None,
                finished_at: finished,
            },
            FairPlayRosterSeat {
                game_id,
                user_id: bob_user,
                player_id: Uuid::new_v4(),
                display_name: "Bob".into(),
                avatar_id: None,
                finished_at: finished,
            },
            FairPlayRosterSeat {
                game_id,
                user_id: cara_user,
                player_id: Uuid::new_v4(),
                display_name: "Cara".into(),
                avatar_id: None,
                finished_at: finished,
            },
        ])
        .await
        .unwrap();

    let view: Value = http
        .get(format!("{base}/api/v1/games/{game_id}/fair-play"))
        .bearer_auth(alice_token)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(view["can_vote"], true);
    assert!(view.get("totals").is_none() || view["totals"].is_null());
    assert_eq!(view["ratees"].as_array().unwrap().len(), 2);
    let body = serde_json::to_string(&view).unwrap();
    assert!(!body.contains("\"ballots\""));
    assert!(!body.contains("voter"));

    let submitted: Value = http
        .post(format!("{base}/api/v1/games/{game_id}/fair-play"))
        .bearer_auth(alice_token)
        .json(&serde_json::json!({
            "ratings": [
                {"user_id": bob_user.to_string(), "points": 10},
                {"user_id": cara_user.to_string(), "points": 8}
            ]
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(submitted["already_submitted"], true);
    assert_eq!(submitted["can_vote"], false);
    let totals = submitted["totals"].as_array().unwrap();
    assert!(totals
        .iter()
        .any(|t| t["display_name"] == "Bob" && t["points"] == 10));
    let again = http
        .post(format!("{base}/api/v1/games/{game_id}/fair-play"))
        .bearer_auth(alice_token)
        .json(&serde_json::json!({
            "ratings": [
                {"user_id": bob_user.to_string(), "points": 1},
                {"user_id": cara_user.to_string(), "points": 1}
            ]
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(again.status(), 409);

    let board: Value = http
        .get(format!("{base}/api/v1/fair-play/leaderboard"))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(board["players"][0]["display_name"], "Bob");
    assert_eq!(board["players"][0]["average"], 10.0);
    assert_eq!(board["players"][0]["games_rated"], 1);
}
