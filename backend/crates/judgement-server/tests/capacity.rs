//! Product capacity hard gate (create / start) while live games stay untouched.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;

use judgement_domain::GameId;
use judgement_persistence::MemoryStore;
use judgement_protocol::CreateGuestSessionResponse;
use judgement_server::capacity::{DEFAULT_HARD_ACTIVE_GAMES, CAPACITY_FULL_MESSAGE};
use judgement_server::restore::bootstrap;
use judgement_server::state::{AppState, GameInfo};
use judgement_server::{build_router};
use tokio::sync::mpsc;

async fn spawn_with(state: Arc<AppState>) -> SocketAddr {
    let router = build_router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    addr
}

fn fill_active_games(state: &AppState, n: usize) {
    let mut games = state.games.lock().unwrap();
    for _ in 0..n {
        let (tx, _rx) = mpsc::channel(1);
        games.insert(
            GameId::new(),
            GameInfo {
                room_id: judgement_domain::RoomId::new(),
                players: HashMap::new(),
                spectators: HashMap::new(),
                commands: tx,
            },
        );
    }
}

#[tokio::test]
async fn create_room_rejected_when_hard_capacity_full() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    fill_active_games(&state, DEFAULT_HARD_ACTIVE_GAMES);
    let addr = spawn_with(state.clone()).await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let session: CreateGuestSessionResponse = http
        .post(format!("{base}/api/v1/guest-sessions"))
        .json(&serde_json::json!({ "nickname": "Busy" }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();

    let resp = http
        .post(format!("{base}/api/v1/rooms"))
        .header("Authorization", format!("Bearer {}", session.token))
        .json(&serde_json::json!({ "max_players": 4 }))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), reqwest::StatusCode::SERVICE_UNAVAILABLE);
    let body: serde_json::Value = resp.json().await.unwrap();
    assert_eq!(body["error"]["code"], "CAPACITY_FULL");
    assert_eq!(body["error"]["message"], CAPACITY_FULL_MESSAGE);
    assert_eq!(
        state
            .metrics
            .capacity_full_rejected
            .load(std::sync::atomic::Ordering::Relaxed),
        1
    );
}

#[tokio::test]
async fn create_room_busy_flag_near_comfort() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    // Just under hard, at/above comfort (25).
    fill_active_games(&state, 25);
    let addr = spawn_with(state.clone()).await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let session: CreateGuestSessionResponse = http
        .post(format!("{base}/api/v1/guest-sessions"))
        .json(&serde_json::json!({ "nickname": "Near" }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();

    let resp = http
        .post(format!("{base}/api/v1/rooms"))
        .header("Authorization", format!("Bearer {}", session.token))
        .json(&serde_json::json!({ "max_players": 4 }))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), reqwest::StatusCode::OK);
    let body: serde_json::Value = resp.json().await.unwrap();
    assert_eq!(body["capacity"], "busy");
    assert_eq!(
        state
            .metrics
            .capacity_busy
            .load(std::sync::atomic::Ordering::Relaxed),
        1
    );
}
