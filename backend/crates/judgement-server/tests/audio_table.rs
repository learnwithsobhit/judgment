//! Soundboard + voice-note cosmetic commands (no persist).

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use judgement_persistence::MemoryStore;
use judgement_protocol::{CreateGuestSessionResponse, RoomView};
use judgement_server::restore::bootstrap;
use judgement_server::{build_router};
use serde_json::Value;
use tokio_tungstenite::tungstenite::Message;

async fn spawn_api(state: Arc<judgement_server::state::AppState>) -> SocketAddr {
    let router = build_router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    tokio::time::sleep(Duration::from_millis(20)).await;
    addr
}

async fn guest(http: &reqwest::Client, base: &str, nick: &str) -> CreateGuestSessionResponse {
    http.post(format!("{base}/api/v1/guest-sessions"))
        .json(&serde_json::json!({ "nickname": nick }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap()
}

#[tokio::test]
async fn soundboard_broadcasts_without_persist() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_api(state.clone()).await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let host = guest(&http, &base, "Host").await;
    let room: serde_json::Value = http
        .post(format!("{base}/api/v1/rooms"))
        .header("Authorization", format!("Bearer {}", host.token))
        .json(&serde_json::json!({ "max_players": 4 }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let room_id = room["room"]["room_id"].as_str().unwrap().to_string();
    let code = room["room"]["code"].as_str().unwrap().to_string();

    let p2 = guest(&http, &base, "P2").await;
    http.post(format!("{base}/api/v1/rooms/{code}/join"))
        .header("Authorization", format!("Bearer {}", p2.token))
        .send()
        .await
        .unwrap();
    let p3 = guest(&http, &base, "P3").await;
    http.post(format!("{base}/api/v1/rooms/{code}/join"))
        .header("Authorization", format!("Bearer {}", p3.token))
        .send()
        .await
        .unwrap();

    for (token, ready) in [
        (&host.token, true),
        (&p2.token, true),
        (&p3.token, true),
    ] {
        http.post(format!("{base}/api/v1/rooms/{room_id}/ready"))
            .header("Authorization", format!("Bearer {token}"))
            .json(&serde_json::json!({ "ready": ready }))
            .send()
            .await
            .unwrap();
    }

    let start: Value = http
        .post(format!("{base}/api/v1/rooms/{room_id}/start"))
        .header("Authorization", format!("Bearer {}", host.token))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let game_id = start["game_id"].as_str().unwrap();

    let room_view: RoomView = http
        .get(format!("{base}/api/v1/rooms/{room_id}"))
        .header("Authorization", format!("Bearer {}", host.token))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let host_player = room_view
        .seats
        .iter()
        .find(|s| s.nickname == "Host")
        .unwrap()
        .player_id;

    let ws_url = format!("ws://{addr}/api/v1/games/{game_id}/ws?token={}", host.token);
    let (mut ws, _) = tokio_tungstenite::connect_async(ws_url).await.unwrap();

    // Drain until connected / snapshot settles.
    for _ in 0..8 {
        let _ = tokio::time::timeout(Duration::from_millis(200), ws.next()).await;
    }

    let action_id = uuid::Uuid::new_v4();
    let envelope = serde_json::json!({
        "protocol_version": 1,
        "action_id": action_id,
        "game_id": game_id,
        "expected_state_version": 0,
        "action": { "type": "send_soundboard", "sound_id": "laugh" }
    });
    ws.send(Message::Text(envelope.to_string().into()))
        .await
        .unwrap();

    let mut saw_soundboard = false;
    for _ in 0..12 {
        let Ok(Some(Ok(Message::Text(text)))) =
            tokio::time::timeout(Duration::from_millis(500), ws.next()).await
        else {
            continue;
        };
        let v: Value = serde_json::from_str(&text).unwrap();
        if v["type"] == "table_event" && v["kind"] == "soundboard" {
            assert_eq!(v["sound_id"], "laugh");
            assert_eq!(v["from"], host_player.to_string());
            saw_soundboard = true;
            break;
        }
    }
    assert!(saw_soundboard, "expected soundboard table_event");
    assert_eq!(
        state
            .metrics
            .soundboard_broadcast
            .load(std::sync::atomic::Ordering::Relaxed),
        1
    );
}

#[tokio::test]
async fn voice_note_rejects_oversized_payload() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_api(state.clone()).await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let host = guest(&http, &base, "VHost").await;
    let room: Value = http
        .post(format!("{base}/api/v1/rooms"))
        .header("Authorization", format!("Bearer {}", host.token))
        .json(&serde_json::json!({ "max_players": 4 }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let room_id = room["room"]["room_id"].as_str().unwrap();
    let code = room["room"]["code"].as_str().unwrap();

    let p2 = guest(&http, &base, "V2").await;
    http.post(format!("{base}/api/v1/rooms/{code}/join"))
        .header("Authorization", format!("Bearer {}", p2.token))
        .send()
        .await
        .unwrap();
    let p3 = guest(&http, &base, "V3").await;
    http.post(format!("{base}/api/v1/rooms/{code}/join"))
        .header("Authorization", format!("Bearer {}", p3.token))
        .send()
        .await
        .unwrap();
    for token in [&host.token, &p2.token, &p3.token] {
        http.post(format!("{base}/api/v1/rooms/{room_id}/ready"))
            .header("Authorization", format!("Bearer {token}"))
            .json(&serde_json::json!({ "ready": true }))
            .send()
            .await
            .unwrap();
    }
    let start: Value = http
        .post(format!("{base}/api/v1/rooms/{room_id}/start"))
        .header("Authorization", format!("Bearer {}", host.token))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let game_id = start["game_id"].as_str().unwrap();

    let ws_url = format!("ws://{addr}/api/v1/games/{game_id}/ws?token={}", host.token);
    let (mut ws, _) = tokio_tungstenite::connect_async(ws_url).await.unwrap();
    for _ in 0..8 {
        let _ = tokio::time::timeout(Duration::from_millis(200), ws.next()).await;
    }

    let huge = format!("GkXf{}", "A".repeat(50_000));
    let envelope = serde_json::json!({
        "protocol_version": 1,
        "action_id": uuid::Uuid::new_v4(),
        "game_id": game_id,
        "expected_state_version": 0,
        "action": {
            "type": "send_voice_note",
            "mime": "audio/webm;codecs=opus",
            "duration_ms": 1200,
            "audio_b64": huge
        }
    });
    ws.send(Message::Text(envelope.to_string().into()))
        .await
        .unwrap();

    let mut rejected = false;
    for _ in 0..12 {
        let Ok(Some(Ok(Message::Text(text)))) =
            tokio::time::timeout(Duration::from_millis(500), ws.next()).await
        else {
            continue;
        };
        let v: Value = serde_json::from_str(&text).unwrap();
        if v["type"] == "command_rejected" {
            rejected = true;
            break;
        }
    }
    assert!(rejected);
    assert!(
        state
            .metrics
            .audio_rejected
            .load(std::sync::atomic::Ordering::Relaxed)
            >= 1
    );
}
