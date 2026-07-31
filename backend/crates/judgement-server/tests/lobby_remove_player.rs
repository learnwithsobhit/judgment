//! Host may remove seated lobby players before the game starts.

use std::net::SocketAddr;
use std::sync::Arc;

use judgement_persistence::MemoryStore;
use judgement_protocol::{CreateGuestSessionResponse, CreateRoomResponse, JoinRoomResponse, RoomView};
use judgement_server::{build_router, state::AppState};

async fn spawn_server() -> SocketAddr {
    std::env::set_var("JUDGEMENT_ALLOW_SEED", "1");
    let state = Arc::new(AppState::new(Arc::new(MemoryStore::new())));
    let router = build_router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
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
async fn host_can_remove_guest_from_lobby() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let host = guest(&http, &base, "Host").await;
    let created: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({ "max_players": 4 }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let code = created.room.code.clone();
    let guest_session = guest(&http, &base, "Guest").await;
    let joined: JoinRoomResponse = http
        .post(format!("{base}/api/v1/rooms/{code}/join"))
        .bearer_auth(&guest_session.token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();

    let room: RoomView = http
        .post(format!("{base}/api/v1/rooms/{code}/remove-player"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({ "player_id": joined.player_id }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();

    assert_eq!(room.seats.len(), 1);
    assert!(!room.seats.iter().any(|s| s.player_id == joined.player_id));
    assert!(room.seats.iter().any(|s| s.is_host && s.player_id == created.player_id));
}

#[tokio::test]
async fn non_host_forbidden() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let host = guest(&http, &base, "Host").await;
    let created: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({ "max_players": 4 }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let code = created.room.code.clone();
    let guest_session = guest(&http, &base, "Guest").await;
    http.post(format!("{base}/api/v1/rooms/{code}/join"))
        .bearer_auth(&guest_session.token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();

    let resp = http
        .post(format!("{base}/api/v1/rooms/{code}/remove-player"))
        .bearer_auth(&guest_session.token)
        .json(&serde_json::json!({ "player_id": created.player_id }))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 403);
}

#[tokio::test]
async fn host_cannot_remove_self() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let host = guest(&http, &base, "Host").await;
    let created: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({ "max_players": 4 }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let guest_session = guest(&http, &base, "Guest").await;
    http.post(format!(
        "{base}/api/v1/rooms/{}/join",
        created.room.code
    ))
    .bearer_auth(&guest_session.token)
    .json(&serde_json::json!({}))
    .send()
    .await
    .unwrap()
    .error_for_status()
    .unwrap();

    let resp = http
        .post(format!(
            "{base}/api/v1/rooms/{}/remove-player",
            created.room.code
        ))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({ "player_id": created.player_id }))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 403);
}

#[tokio::test]
async fn remove_after_start_conflicts() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let host = guest(&http, &base, "Host").await;
    let created: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({
            "max_players": 3,
            "turn_timeout_seconds": null
        }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let code = created.room.code.clone();
    let mut tokens = vec![host.token.clone()];
    let mut guest_player_id = None;
    for i in 2..=3 {
        let s = guest(&http, &base, &format!("P{i}")).await;
        let joined: JoinRoomResponse = http
            .post(format!("{base}/api/v1/rooms/{code}/join"))
            .bearer_auth(&s.token)
            .json(&serde_json::json!({}))
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        if i == 2 {
            guest_player_id = Some(joined.player_id);
        }
        tokens.push(s.token);
    }
    for token in &tokens {
        http.post(format!("{base}/api/v1/rooms/{code}/ready"))
            .bearer_auth(token)
            .json(&serde_json::json!({ "ready": true }))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap();
    }
    http.post(format!("{base}/api/v1/rooms/{code}/start"))
        .bearer_auth(&tokens[0])
        .json(&serde_json::json!({ "seed": 7 }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();

    let resp = http
        .post(format!("{base}/api/v1/rooms/{code}/remove-player"))
        .bearer_auth(&tokens[0])
        .json(&serde_json::json!({ "player_id": guest_player_id.unwrap() }))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 409);
}
