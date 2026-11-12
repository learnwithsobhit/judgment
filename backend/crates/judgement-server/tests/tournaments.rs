//! Admin create/live + public standings + create-room attach.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use jsonwebtoken::{encode, EncodingKey, Header};
use judgement_persistence::{
    stats::PulseFinish, GameStore, MemoryStore, StoredTournament, StoredUser, TournamentStatus,
};
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

async fn serve_with(store: MemoryStore, admin_email: &str) -> String {
    let mut state = AppState::new(Arc::new(store));
    state.admin_emails = vec![admin_email.to_string()];
    let app = build_router(Arc::new(state));
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
    email: &str,
) -> String {
    let body: Value = client
        .post(format!("{base}/api/v1/auth/firebase"))
        .json(&serde_json::json!({
            "id_token": google_token(secret, subject, name, email),
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
async fn admin_create_go_live_attach_and_standings() {
    let secret = "tournament-firebase-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    let store = MemoryStore::new();
    let base = serve_with(store, "admin@example.com").await;
    let client = reqwest::Client::new();

    let admin = sign_in(
        &client,
        &base,
        secret,
        "admin-1",
        "Admin",
        "admin@example.com",
    )
    .await;
    let host = sign_in(
        &client,
        &base,
        secret,
        "host-1",
        "Host",
        "host@example.com",
    )
    .await;

    let created: Value = client
        .post(format!("{base}/api/v1/admin/tournaments"))
        .bearer_auth(&admin)
        .json(&serde_json::json!({
            "title": "Friday Night",
            "blurb": "Points series",
            "status": "draft",
            "starts_at": "2026-11-14T14:30:00Z"
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(created["status"], "draft");
    assert_eq!(created["starts_at"], "2026-11-14T14:30:00Z");
    let tournament_id = created["tournament_id"].as_str().unwrap().to_string();

    let public: Value = client
        .get(format!("{base}/api/v1/tournaments"))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(public["tournaments"].as_array().unwrap().is_empty());

    let live: Value = client
        .patch(format!("{base}/api/v1/admin/tournaments/{tournament_id}"))
        .bearer_auth(&admin)
        .json(&serde_json::json!({ "status": "live" }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(live["status"], "live");

    let reject = client
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host)
        .json(&serde_json::json!({
            "max_players": 4,
            "tournament_id": "00000000-0000-0000-0000-000000000000"
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(reject.status(), 400);

    let room: Value = client
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host)
        .json(&serde_json::json!({
            "max_players": 4,
            "tournament_id": tournament_id
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(room["room"]["tournament_id"], tournament_id);
    assert_eq!(room["room"]["tournament_title"], "Friday Night");

    let code = room["room"]["code"].as_str().unwrap().to_string();
    let guest: Value = client
        .post(format!("{base}/api/v1/guest-sessions"))
        .json(&serde_json::json!({ "nickname": "Joiner" }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    let joined: Value = client
        .post(format!("{base}/api/v1/rooms/{code}/join"))
        .bearer_auth(guest["token"].as_str().unwrap())
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(joined["room"]["tournament_id"], tournament_id);
    assert_eq!(joined["room"]["tournament_title"], "Friday Night");

    client
        .patch(format!("{base}/api/v1/admin/tournaments/{tournament_id}"))
        .bearer_auth(&admin)
        .json(&serde_json::json!({ "status": "closed" }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();

    let blocked = client
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host)
        .json(&serde_json::json!({
            "max_players": 4,
            "tournament_id": tournament_id
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(blocked.status(), 400);

    let detail: Value = client
        .get(format!("{base}/api/v1/tournaments/{tournament_id}"))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(detail["tournament"]["status"], "closed");
    assert!(detail["players"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn admin_delete_removes_tournament() {
    // Same secret as other tests in this file — env is process-global.
    let secret = "tournament-firebase-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    let store = MemoryStore::new();
    let base = serve_with(store, "admin@example.com").await;
    let client = reqwest::Client::new();

    let admin = sign_in(
        &client,
        &base,
        secret,
        "admin-del",
        "Admin",
        "admin@example.com",
    )
    .await;
    let host = sign_in(
        &client,
        &base,
        secret,
        "host-del",
        "Host",
        "host@example.com",
    )
    .await;

    let created: Value = client
        .post(format!("{base}/api/v1/admin/tournaments"))
        .bearer_auth(&admin)
        .json(&serde_json::json!({
            "title": "Test cleanup",
            "status": "live",
            "starts_at": "2026-01-01T12:00:00Z"
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    let tournament_id = created["tournament_id"].as_str().unwrap().to_string();

    let room: Value = client
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host)
        .json(&serde_json::json!({
            "max_players": 4,
            "tournament_id": tournament_id
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(room["room"]["tournament_id"], tournament_id);

    let forbidden = client
        .delete(format!("{base}/api/v1/admin/tournaments/{tournament_id}"))
        .bearer_auth(&host)
        .send()
        .await
        .unwrap();
    assert_eq!(forbidden.status(), 403);

    let deleted = client
        .delete(format!("{base}/api/v1/admin/tournaments/{tournament_id}"))
        .bearer_auth(&admin)
        .send()
        .await
        .unwrap();
    assert_eq!(deleted.status(), 204);

    let missing = client
        .get(format!("{base}/api/v1/tournaments/{tournament_id}"))
        .send()
        .await
        .unwrap();
    assert_eq!(missing.status(), 404);

    let admin_list: Value = client
        .get(format!("{base}/api/v1/admin/tournaments"))
        .bearer_auth(&admin)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(admin_list["tournaments"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn standings_use_result_stamp_not_live_games() {
    let store = MemoryStore::new();
    let now = chrono::Utc::now();
    let tournament_id = uuid::Uuid::new_v4();
    store
        .upsert_tournament(&StoredTournament {
            tournament_id,
            slug: "stamp-test".into(),
            title: "Stamp".into(),
            blurb: "".into(),
            format: "points".into(),
            status: TournamentStatus::Live,
            starts_at: None,
            ends_at: None,
            created_by: None,
            created_at: now,
            updated_at: now,
        })
        .await
        .unwrap();
    let user_id = uuid::Uuid::new_v4();
    store
        .upsert_user(&StoredUser {
            user_id,
            display_name: "Ada".into(),
            avatar_id: None,
            photo_url: None,
            legal_version: None,
            created_at: now,
            updated_at: now,
            last_seen_at: now,
        })
        .await
        .unwrap();
    store.seed_counted_finishes(vec![PulseFinish {
        game_id: uuid::Uuid::new_v4(),
        user_id,
        finished_at: now,
        finish_rank: 1,
        exact_bid_rounds: 2,
        rounds_played: 4,
        total_score: 40,
        tournament_id: Some(tournament_id),
    }]);

    let base = serve_with(store, "nobody@example.com").await;
    let client = reqwest::Client::new();
    let detail: Value = client
        .get(format!("{base}/api/v1/tournaments/{tournament_id}"))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(detail["players"].as_array().unwrap().len(), 1);
    assert_eq!(detail["players"][0]["display_name"], "Ada");
    assert_eq!(detail["players"][0]["medal_points"], 500);
    assert_eq!(detail["tournament"]["finished_tables"], 1);
}
