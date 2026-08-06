//! Custom trump_cycle create + validation + legacy first_trump.

use std::net::SocketAddr;
use std::sync::Arc;

use judgement_domain::Suit;
use judgement_persistence::MemoryStore;
use judgement_protocol::{CreateGuestSessionResponse, CreateRoomResponse};
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

#[tokio::test]
async fn custom_trump_cycle_echoed_and_invalid_rejected() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let host = guest(&http, &base, "Host").await;
    let create: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({
            "max_players": 3,
            "trump_cycle": ["spades", "clubs", "hearts", "diamonds"]
        }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();

    assert_eq!(
        create.room.trump_cycle,
        Some(vec![
            Suit::Spades,
            Suit::Clubs,
            Suit::Hearts,
            Suit::Diamonds
        ])
    );
    assert_eq!(create.room.first_trump, Some(Suit::Spades));

    let bad = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({
            "trump_cycle": ["spades", "clubs"]
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(bad.status(), reqwest::StatusCode::BAD_REQUEST);

    let dup = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({
            "trump_cycle": ["spades", "spades", "hearts", "diamonds"]
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(dup.status(), reqwest::StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn legacy_first_trump_still_builds_without_cycle() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;
    let create: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({ "first_trump": "clubs" }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(create.room.trump_cycle.is_none());
    assert_eq!(create.room.first_trump, Some(Suit::Clubs));
}
