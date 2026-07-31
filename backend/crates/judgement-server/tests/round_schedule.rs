//! Manual vs automatic round schedules at room create / game start.

use std::net::SocketAddr;
use std::sync::Arc;

use judgement_domain::{RoundPattern, RoundScheduleMode};
use judgement_persistence::MemoryStore;
use judgement_protocol::{CreateGuestSessionResponse, CreateRoomResponse, GameHistoryResponse};
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
async fn create_manual_schedule_starts_with_custom_pattern() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let host = guest(&http, &base, "Host").await;
    let create: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({
            "max_players": 4,
            "turn_timeout_seconds": null,
            "first_trump": "spades",
            "round_schedule": {
                "mode": "manual",
                "steps": [
                    { "cards": 12, "repeat": 2 },
                    { "cards": 1, "repeat": 1 }
                ]
            }
        }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();

    assert_eq!(create.room.round_schedule.mode, RoundScheduleMode::Manual);
    assert!(create.room.round_schedule_summary.contains("Manual"));
    assert!(create.room.round_schedule_summary.contains("3 rounds"));

    let code = create.room.code.clone();
    let mut tokens = vec![host.token.clone()];
    for i in 2..=4 {
        let s = guest(&http, &base, &format!("P{i}")).await;
        http.post(format!("{base}/api/v1/rooms/{code}/join"))
            .bearer_auth(&s.token)
            .json(&serde_json::json!({}))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap();
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

    let start: serde_json::Value = http
        .post(format!("{base}/api/v1/rooms/{code}/start"))
        .bearer_auth(&tokens[0])
        .json(&serde_json::json!({ "seed": 42 }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let game_id = start["game_id"].as_str().unwrap();

    let history: GameHistoryResponse = http
        .get(format!("{base}/api/v1/games/{game_id}/history"))
        .bearer_auth(&tokens[0])
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();

    assert_eq!(
        history.rules.round_pattern,
        RoundPattern::Custom {
            rounds: vec![12, 12, 1]
        }
    );
}

#[tokio::test]
async fn create_rejects_manual_cards_above_table_max() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;

    let response = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({
            "max_players": 6,
            "round_schedule": {
                "mode": "manual",
                "steps": [{ "cards": 12, "repeat": 1 }]
            }
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn start_rejects_schedule_invalid_for_seated_count() {
    use chrono::Utc;
    use judgement_domain::{
        ManualRoundStep, PlayerId, RoomId, RoundSchedule, RoundScheduleMode,
    };
    use judgement_server::state::{Room, RoomSeat, RoomStatus};

    let state = Arc::new(AppState::new(Arc::new(MemoryStore::new())));
    let router = build_router(state.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    // Six seated players, but schedule still asks for 12 cards (only legal for ≤4).
    let room_id = RoomId::new();
    let code = "BADSCH".to_string();
    let mut seats = Vec::new();
    let mut tokens = Vec::new();
    for i in 0..6u8 {
        let session = guest(&http, &base, &format!("P{i}")).await;
        tokens.push(session.token);
        seats.push(RoomSeat {
            session_id: session.session_id,
            player_id: PlayerId::new(),
            nickname: format!("P{i}"),
            seat: i,
            ready: true,
            joined_at: Utc::now(),
            avatar_id: None,
        });
    }
    let host_session = seats[0].session_id;
    {
        let mut rooms = state.rooms.lock().unwrap();
        let mut codes = state.room_codes.lock().unwrap();
        rooms.insert(
            room_id,
            Room {
                id: room_id,
                code: code.clone(),
                host_session,
                seats,
                status: RoomStatus::Lobby,
                max_players: 6,
                turn_timeout_seconds: None,
                first_trump: Some(judgement_domain::Suit::Spades),
                round_schedule: RoundSchedule {
                    mode: RoundScheduleMode::Manual,
                    steps: Some(vec![ManualRoundStep { cards: 12, repeat: 1 }]),
                },
                dealer_total_restriction: false,
            },
        );
        codes.insert(code.clone(), room_id);
    }

    let response = http
        .post(format!("{base}/api/v1/rooms/{code}/start"))
        .bearer_auth(&tokens[0])
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::CONFLICT);
    let body: serde_json::Value = response.json().await.unwrap();
    let message = body["error"]["message"].as_str().unwrap_or_default();
    assert!(
        message.contains("round schedule"),
        "unexpected message: {message}"
    );
}

#[tokio::test]
async fn default_omitted_schedule_is_automatic() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;
    let create: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({ "max_players": 4 }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(create.room.round_schedule.mode, RoundScheduleMode::Automatic);
    assert_eq!(create.room.round_schedule_summary, "Automatic (12→1)");
}
