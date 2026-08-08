//! Audience / spectator isolation smoke tests.

use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use judgement_persistence::MemoryStore;
use judgement_server::restore::bootstrap;
use judgement_server::state::AppState;
use judgement_server::build_router;
use serde_json::json;
use tokio_tungstenite::tungstenite::Message;

async fn spawn_with(state: Arc<AppState>) -> std::net::SocketAddr {
    let app = build_router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    tokio::time::sleep(Duration::from_millis(20)).await;
    addr
}

async fn guest(http: &reqwest::Client, base: &str, nick: &str) -> String {
    let resp = http
        .post(format!("{base}/api/v1/guest-sessions"))
        .json(&json!({ "nickname": nick }))
        .send()
        .await
        .unwrap();
    assert!(resp.status().is_success());
    let body: serde_json::Value = resp.json().await.unwrap();
    body["token"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn watch_requires_spectators_allowed_and_hides_hands() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let host = guest(&http, &base, "Host").await;
    let p2 = guest(&http, &base, "P2").await;
    let p3 = guest(&http, &base, "P3").await;
    let p4 = guest(&http, &base, "P4").await;
    let watcher = guest(&http, &base, "Fan").await;

    let create = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host)
        .json(&json!({ "max_players": 4 }))
        .send()
        .await
        .unwrap();
    let created: serde_json::Value = create.json().await.unwrap();
    let code = created["room"]["code"].as_str().unwrap().to_string();

    for token in [&p2, &p3, &p4] {
        let join = http
            .post(format!("{base}/api/v1/rooms/{code}/join"))
            .bearer_auth(token)
            .json(&json!({}))
            .send()
            .await
            .unwrap();
        assert!(join.status().is_success(), "{}", join.text().await.unwrap());
    }

    for token in [&host, &p2, &p3, &p4] {
        let ready = http
            .post(format!("{base}/api/v1/rooms/{code}/ready"))
            .bearer_auth(token)
            .json(&json!({ "ready": true }))
            .send()
            .await
            .unwrap();
        assert!(ready.status().is_success());
    }

    let start = http
        .post(format!("{base}/api/v1/rooms/{code}/start"))
        .bearer_auth(&host)
        .json(&json!({}))
        .send()
        .await
        .unwrap();
    assert!(start.status().is_success(), "{}", start.text().await.unwrap());
    let started: serde_json::Value = start.json().await.unwrap();
    let game_id = started["game_id"].as_str().unwrap().to_string();

    // Watch blocked before host opens audience.
    let blocked = http
        .post(format!("{base}/api/v1/rooms/{code}/watch"))
        .bearer_auth(&watcher)
        .json(&json!({}))
        .send()
        .await
        .unwrap();
    assert_eq!(blocked.status(), reqwest::StatusCode::FORBIDDEN);

    let settings = http
        .post(format!("{base}/api/v1/rooms/{code}/audience-settings"))
        .bearer_auth(&host)
        .json(&json!({
            "spectators_allowed": true,
            "list_on_live_now": true
        }))
        .send()
        .await
        .unwrap();
    assert!(settings.status().is_success(), "{}", settings.text().await.unwrap());

    let watch = http
        .post(format!("{base}/api/v1/rooms/{code}/watch"))
        .bearer_auth(&watcher)
        .json(&json!({ "nickname": "Fan" }))
        .send()
        .await
        .unwrap();
    assert!(watch.status().is_success(), "{}", watch.text().await.unwrap());

    let live = http
        .get(format!("{base}/api/v1/live-rooms"))
        .send()
        .await
        .unwrap();
    assert!(live.status().is_success());
    let live_body: serde_json::Value = live.json().await.unwrap();
    assert!(live_body["rooms"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["room_code"] == code));

    let ws_url = format!("ws://{addr}/api/v1/games/{game_id}/watch-ws?token={watcher}");
    let (mut ws, _) = tokio_tungstenite::connect_async(ws_url).await.unwrap();

    let mut saw_spectator_snapshot = false;
    for _ in 0..10 {
        let msg = tokio::time::timeout(Duration::from_secs(2), ws.next())
            .await
            .expect("timeout")
            .expect("ws closed")
            .unwrap();
        let Message::Text(text) = msg else { continue };
        let v: serde_json::Value = serde_json::from_str(&text).unwrap();
        if v["type"] == "spectator_state_snapshot" {
            saw_spectator_snapshot = true;
            assert!(v["view"].get("own_hand").is_none());
            assert!(v["view"].get("legal_actions").is_none());
            assert!(v["view"]["seats"].as_array().unwrap().len() >= 4);
            break;
        }
    }
    assert!(saw_spectator_snapshot, "expected SpectatorStateSnapshot");

    // Rate-limit: spam comments.
    for i in 0..4 {
        let envelope = json!({
            "protocol_version": 1,
            "action_id": uuid::Uuid::new_v4().to_string(),
            "game_id": game_id,
            "expected_state_version": 0,
            "action": { "type": "audience_comment", "text": format!("go {i}") }
        });
        ws.send(Message::Text(envelope.to_string().into()))
            .await
            .unwrap();
    }

    let mut saw_rate_limit = false;
    for _ in 0..12 {
        let msg = tokio::time::timeout(Duration::from_secs(2), ws.next())
            .await
            .ok()
            .and_then(|m| m);
        let Some(Ok(Message::Text(text))) = msg else { continue };
        let v: serde_json::Value = serde_json::from_str(&text).unwrap();
        if v["type"] == "command_rejected"
            && v["reason"]["kind"] == "audience_rate_limited"
        {
            saw_rate_limit = true;
            break;
        }
    }
    assert!(saw_rate_limit, "expected audience rate limit reject");
}
