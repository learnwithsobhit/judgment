//! Join room lists waiting tables from memory. A signed-in account sits at one.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use jsonwebtoken::{encode, EncodingKey, Header};
use judgement_persistence::MemoryStore;
use judgement_server::{build_router, state::AppState};
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

async fn create_room(http: &reqwest::Client, base: &str, token: &str, listed: bool) -> Value {
    http.post(format!("{base}/api/v1/rooms"))
        .bearer_auth(token)
        .json(&serde_json::json!({
            "max_players": 4,
            "listed": listed
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
async fn a_signed_in_player_sees_waiting_tables_and_one_seat() {
    let secret = "test-firebase-dev-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    let base = serve().await;
    let http = reqwest::Client::new();

    let ada = sign_in(&http, &base, secret, "ada-open", "Ada Lovelace").await;
    let ada_token = ada["token"].as_str().unwrap();
    let ada_nick = ada["nickname"].as_str().unwrap();
    let created = create_room(&http, &base, ada_token, true).await;
    let room_id = created["room"]["room_id"].as_str().unwrap();
    let code = created["room"]["code"].as_str().unwrap();

    let guest: Value = http
        .post(format!("{base}/api/v1/guest-sessions"))
        .json(&serde_json::json!({ "nickname": "Guest" }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let guest_token = guest["token"].as_str().unwrap();
    http.post(format!("{base}/api/v1/rooms"))
        .bearer_auth(guest_token)
        .json(&serde_json::json!({ "max_players": 4 }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();

    let open: Value = http
        .get(format!("{base}/api/v1/rooms/open"))
        .bearer_auth(ada_token)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    let tables = open["tables"].as_array().unwrap();
    assert_eq!(
        tables.len(),
        1,
        "guest-only rooms stay off the list: {open}"
    );
    assert!(tables[0].get("code").is_none());
    assert_eq!(tables[0]["room_id"], room_id);
    assert_eq!(tables[0]["host_nickname"], ada_nick);
    assert_eq!(tables[0]["seated"], 1);
    assert_eq!(tables[0]["max_players"], 4);
    assert_eq!(tables[0]["seats_open"], 3);
    assert_eq!(tables[0]["yours"], true);

    let beena = sign_in(&http, &base, secret, "beena-open", "Beena").await;
    let beena_token = beena["token"].as_str().unwrap();
    let beena_room = create_room(&http, &base, beena_token, true).await;
    let beena_id = beena_room["room"]["room_id"].as_str().unwrap();
    let joined: Value = http
        .post(format!("{base}/api/v1/rooms/{room_id}/join"))
        .bearer_auth(beena_token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(joined["room"]["seats"].as_array().unwrap().len(), 2);
    let both: Value = http
        .get(format!("{base}/api/v1/rooms/open"))
        .bearer_auth(beena_token)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    let hers: Vec<_> = both["tables"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|row| row["yours"] == true)
        .map(|row| row["room_id"].as_str().unwrap())
        .collect();
    assert!(hers.contains(&room_id), "the joined table stays: {hers:?}");
    assert!(
        hers.contains(&beena_id),
        "the first table stays too: {hers:?}"
    );

    let again = sign_in(&http, &base, secret, "ada-open", "Ada Lovelace").await;
    let second: Value = http
        .post(format!("{base}/api/v1/rooms/{room_id}/join"))
        .bearer_auth(again["token"].as_str().unwrap())
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(
        second["room"]["seats"].as_array().unwrap().len(),
        2,
        "a second phone takes the same seat"
    );

    let private_room = create_room(&http, &base, beena_token, false).await;
    let private_id = private_room["room"]["room_id"].as_str().unwrap();
    let listed: Value = http
        .get(format!("{base}/api/v1/rooms/open"))
        .bearer_auth(ada_token)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let ids: Vec<_> = listed["tables"]
        .as_array()
        .unwrap()
        .iter()
        .map(|row| row["room_id"].as_str().unwrap())
        .collect();
    assert!(!ids.contains(&private_id));
    assert!(ids.contains(&room_id));

    let guest_join = http
        .post(format!("{base}/api/v1/rooms/{code}/join"))
        .bearer_auth(guest_token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap();
    assert!(guest_join.status().is_success());
}
