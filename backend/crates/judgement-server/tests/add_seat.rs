//! The host can open one more lobby seat. The join code stays the same.

use std::net::SocketAddr;
use std::sync::Arc;

use judgement_persistence::MemoryStore;
use judgement_protocol::{
    CreateGuestSessionResponse, CreateRoomResponse, JoinRoomResponse, RoomView,
};
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

async fn create(
    http: &reqwest::Client,
    base: &str,
    token: &str,
    body: serde_json::Value,
) -> CreateRoomResponse {
    http.post(format!("{base}/api/v1/rooms"))
        .bearer_auth(token)
        .json(&body)
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
async fn the_same_link_admits_one_more_player() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;
    let created = create(
        &http,
        &base,
        &host.token,
        serde_json::json!({ "max_players": 4 }),
    )
    .await;
    let code = created.room.code.clone();
    let host_player = created.player_id.expect("host is seated");

    for name in ["Beena", "Gagan", "Upavan"] {
        let person = guest(&http, &base, name).await;
        http.post(format!("{base}/api/v1/rooms/{code}/join"))
            .bearer_auth(&person.token)
            .json(&serde_json::json!({}))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap();
    }

    let extra = guest(&http, &base, "Fifth").await;
    let blocked = http
        .post(format!("{base}/api/v1/rooms/{code}/join"))
        .bearer_auth(&extra.token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap();
    assert_eq!(blocked.status(), 409);
    let blocked: serde_json::Value = blocked.json().await.unwrap();
    assert_eq!(
        blocked["error"]["message"],
        "This table is full. Ask the host to open a seat, then use the same link."
    );

    http.post(format!("{base}/api/v1/rooms/{code}/ready"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({ "ready": true }))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();

    let guest_seat = guest(&http, &base, "NotHost").await;
    http.post(format!("{base}/api/v1/rooms/{code}/join"))
        .bearer_auth(&guest_seat.token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap();
    let denied = http
        .post(format!("{base}/api/v1/rooms/{code}/seats"))
        .bearer_auth(&guest_seat.token)
        .send()
        .await
        .unwrap();
    assert_eq!(denied.status(), 403);

    let opened: RoomView = http
        .post(format!("{base}/api/v1/rooms/{code}/seats"))
        .bearer_auth(&host.token)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(opened.max_players, 5);
    assert_eq!(opened.code, code);
    assert!(opened
        .seats
        .iter()
        .any(|seat| seat.player_id == host_player && seat.ready));

    let joined: JoinRoomResponse = http
        .post(format!("{base}/api/v1/rooms/{code}/join"))
        .bearer_auth(&extra.token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(joined.room.max_players, 5);
    assert_eq!(joined.room.seats.len(), 5);
}

#[tokio::test]
async fn a_manual_list_that_does_not_fit_stays_unchanged() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;
    let created = create(
        &http,
        &base,
        &host.token,
        serde_json::json!({
            "max_players": 4,
            "round_schedule": {
                "mode": "manual",
                "steps": [{ "cards": 12, "repeat": 1 }]
            }
        }),
    )
    .await;
    let code = created.room.code.clone();
    let resp = http
        .post(format!("{base}/api/v1/rooms/{code}/seats"))
        .bearer_auth(&host.token)
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 409);
    let room: RoomView = http
        .get(format!("{base}/api/v1/rooms/{code}"))
        .bearer_auth(&host.token)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(room.max_players, 4);
    assert_eq!(room.seats.len(), 1);
}

#[tokio::test]
async fn a_started_game_and_an_eight_seat_table_cannot_grow() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;
    let wide = create(
        &http,
        &base,
        &host.token,
        serde_json::json!({ "max_players": 8 }),
    )
    .await;
    let wide_code = wide.room.code.clone();
    let capped = http
        .post(format!("{base}/api/v1/rooms/{wide_code}/seats"))
        .bearer_auth(&host.token)
        .send()
        .await
        .unwrap();
    assert_eq!(capped.status(), 409);
    let still: RoomView = http
        .get(format!("{base}/api/v1/rooms/{wide_code}"))
        .bearer_auth(&host.token)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(still.max_players, 8);

    let created = create(
        &http,
        &base,
        &host.token,
        serde_json::json!({ "max_players": 3 }),
    )
    .await;
    let code = created.room.code.clone();
    let mut tokens = vec![host.token.clone()];
    for name in ["Beena", "Gagan"] {
        let person = guest(&http, &base, name).await;
        http.post(format!("{base}/api/v1/rooms/{code}/join"))
            .bearer_auth(&person.token)
            .json(&serde_json::json!({}))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap();
        tokens.push(person.token);
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
        .bearer_auth(&host.token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();
    let late = http
        .post(format!("{base}/api/v1/rooms/{code}/seats"))
        .bearer_auth(&host.token)
        .send()
        .await
        .unwrap();
    assert_eq!(late.status(), 409);
    let late: serde_json::Value = late.json().await.unwrap();
    assert_eq!(late["error"]["message"], "the game has already started");
}
