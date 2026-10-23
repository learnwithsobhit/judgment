//! Setup-only rooms: the organizer is not seated and the first joiner is host.
//! Start matches a normal room: at least 3 ready players, table need not be full.

use std::net::SocketAddr;
use std::sync::Arc;

use judgement_persistence::MemoryStore;
use judgement_protocol::{CreateGuestSessionResponse, CreateRoomResponse, JoinRoomResponse};
use judgement_server::{build_router, state::AppState};

async fn spawn_server() -> SocketAddr {
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

async fn join(http: &reqwest::Client, base: &str, token: &str, code: &str) -> JoinRoomResponse {
    http.post(format!("{base}/api/v1/rooms/{code}/join"))
        .bearer_auth(token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap()
}

async fn ready(http: &reqwest::Client, base: &str, token: &str, code: &str) {
    http.post(format!("{base}/api/v1/rooms/{code}/ready"))
        .bearer_auth(token)
        .json(&serde_json::json!({ "ready": true }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
}

async fn start_status(http: &reqwest::Client, base: &str, token: &str, code: &str) -> u16 {
    http.post(format!("{base}/api/v1/rooms/{code}/start"))
        .bearer_auth(token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .status()
        .as_u16()
}

#[tokio::test]
async fn setup_room_starts_like_a_normal_lobby_once_three_are_ready() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let organizer = guest(&http, &base, "Organizer").await;
    let created: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&organizer.token)
        .json(&serde_json::json!({ "max_players": 4, "open_start": true }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();

    assert!(created.player_id.is_none());
    assert!(created.room.seats.is_empty());
    assert!(created.room.open_start);
    let code = created.room.code.clone();

    let first = guest(&http, &base, "First").await;
    let second = guest(&http, &base, "Second").await;
    let third = guest(&http, &base, "Third").await;

    let joined_first = join(&http, &base, &first.token, &code).await;
    assert!(joined_first.room.seats.iter().any(|s| {
        s.player_id == joined_first.player_id && s.is_host
    }));

    let joined_second = join(&http, &base, &second.token, &code).await;
    assert!(joined_second.room.seats.iter().any(|s| {
        s.player_id == joined_second.player_id && !s.is_host
    }));
    assert!(joined_second.room.seats.iter().any(|s| {
        s.player_id == joined_first.player_id && s.is_host
    }));

    assert_eq!(start_status(&http, &base, &first.token, &code).await, 409);
    assert_eq!(start_status(&http, &base, &second.token, &code).await, 403);

    let joined_third = join(&http, &base, &third.token, &code).await;
    assert_eq!(joined_third.room.seats.len(), 3);
    assert!(joined_third.room.seats.iter().all(|s| !s.ready));
    assert_eq!(start_status(&http, &base, &first.token, &code).await, 409);

    ready(&http, &base, &first.token, &code).await;
    ready(&http, &base, &second.token, &code).await;
    ready(&http, &base, &third.token, &code).await;

    assert_eq!(
        start_status(&http, &base, &organizer.token, &code).await,
        403
    );
    assert_eq!(start_status(&http, &base, &second.token, &code).await, 403);
    assert_eq!(start_status(&http, &base, &first.token, &code).await, 200);
}

#[tokio::test]
async fn normal_create_still_seats_the_host_and_rejects_a_guest_start() {
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
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();

    let host_player = created.player_id.expect("creator is seated");
    assert!(!created.room.open_start);
    assert!(created.room.seats.iter().any(|s| {
        s.player_id == host_player && s.is_host
    }));

    let other = guest(&http, &base, "Other").await;
    let code = created.room.code;
    join(&http, &base, &other.token, &code).await;
    assert_eq!(start_status(&http, &base, &other.token, &code).await, 403);
}
