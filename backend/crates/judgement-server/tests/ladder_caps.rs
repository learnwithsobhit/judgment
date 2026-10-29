//! Overall top-3 caps follow the account, never the nickname.

use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use futures_util::{SinkExt, StreamExt};
use jsonwebtoken::{encode, EncodingKey, Header};
use judgement_domain::{ActionId, PlayerId};
use judgement_engine::PlayerGameView;
use judgement_persistence::{LeaderboardRow, MemoryStore};
use judgement_protocol::{
    AuthSessionResponse, ClaimSeatRequest, ClaimSeatResponse, ClientCommand, ClientEnvelope,
    CreateGuestSessionResponse, CreateRoomRequest, CreateRoomResponse, JoinRoomRequest,
    JoinRoomResponse, ReadyRequest, RoomView, ServerMessage, StartGameRequest, StartGameResponse,
    PROTOCOL_VERSION,
};
use judgement_server::build_router;
use judgement_server::state::AppState;
use serde::Serialize;
use tokio::net::TcpListener;
use tokio_tungstenite::tungstenite::Message;

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

fn row(user_id: uuid::Uuid, name: &str, wins: i32) -> LeaderboardRow {
    LeaderboardRow {
        user_id,
        display_name: name.into(),
        avatar_id: None,
        wins,
        games: 10,
        exact_percent: 50,
        average_score: 20,
    }
}

fn seat_rank(room: &RoomView, player_id: PlayerId) -> Option<u8> {
    room.seats
        .iter()
        .find(|seat| seat.player_id == player_id)
        .and_then(|seat| seat.ladder_rank)
}

async fn ok(response: reqwest::Response) -> reqwest::Response {
    let status = response.status();
    if status.is_success() {
        return response;
    }
    let body = response.text().await.unwrap_or_default();
    panic!("{status}: {body}");
}

async fn next_snapshot(
    ws: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
) -> Option<PlayerGameView> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    while tokio::time::Instant::now() < deadline {
        let message = tokio::time::timeout(Duration::from_millis(200), ws.next()).await;
        let Ok(Some(Ok(Message::Text(text)))) = message else {
            continue;
        };
        if let Ok(ServerMessage::StateSnapshot { view, .. }) = serde_json::from_str(text.as_ref()) {
            return Some(view);
        }
    }
    None
}

#[tokio::test]
async fn caps_follow_the_account_through_claim() {
    let secret = "test-firebase-dev-secret";
    std::env::set_var("JUDGEMENT_FIREBASE_DEV_SECRET", secret);
    std::env::set_var("JUDGEMENT_ALLOW_SEED", "1");

    let state = Arc::new(AppState::new(Arc::new(MemoryStore::new())));
    let app = build_router(state.clone());
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    async fn sign_in(
        client: &reqwest::Client,
        base: &str,
        secret: &str,
        subject: &str,
        name: &str,
    ) -> AuthSessionResponse {
        ok(client
            .post(format!("{base}/api/v1/auth/firebase"))
            .json(&serde_json::json!({
                "id_token": dev_token(secret, subject, name),
            }))
            .send()
            .await
            .unwrap())
        .await
        .json()
        .await
        .unwrap()
    }

    let gold = sign_in(&client, &base, secret, "cap-gold", "Gold Player").await;
    let silver = sign_in(&client, &base, secret, "cap-silver", "Silver Player").await;
    let fourth = sign_in(&client, &base, secret, "cap-fourth", "Fourth Player").await;
    let gold_id: uuid::Uuid = gold.user.user_id.parse().unwrap();
    let silver_id: uuid::Uuid = silver.user.user_id.parse().unwrap();
    let fourth_id: uuid::Uuid = fourth.user.user_id.parse().unwrap();

    *state.leaderboard.lock().unwrap() = Arc::new(vec![
        row(gold_id, "Gold", 9),
        row(silver_id, "Silver", 8),
        row(uuid::Uuid::new_v4(), "Bronze", 7),
        row(fourth_id, "Fourth", 1),
    ]);

    let guest: CreateGuestSessionResponse = ok(client
        .post(format!("{base}/api/v1/guest-sessions"))
        .json(&serde_json::json!({"nickname": "Guest"}))
        .send()
        .await
        .unwrap())
    .await
    .json()
    .await
    .unwrap();

    let created: CreateRoomResponse = ok(client
        .post(format!("{base}/api/v1/rooms"))
        .bearer_auth(&gold.token)
        .json(&CreateRoomRequest::default())
        .send()
        .await
        .unwrap())
    .await
    .json()
    .await
    .unwrap();
    let code = created.room.code.clone();
    let gold_player = created.player_id.expect("host is seated");

    async fn join(client: &reqwest::Client, base: &str, code: &str, token: &str) -> PlayerId {
        let joined: JoinRoomResponse = ok(client
            .post(format!("{base}/api/v1/rooms/{code}/join"))
            .bearer_auth(token)
            .json(&JoinRoomRequest::default())
            .send()
            .await
            .unwrap())
        .await
        .json()
        .await
        .unwrap();
        joined.player_id
    }

    let guest_player = join(&client, &base, &code, &guest.token).await;
    let fourth_player = join(&client, &base, &code, &fourth.token).await;

    for token in [&gold.token, &guest.token, &fourth.token] {
        ok(client
            .post(format!("{base}/api/v1/rooms/{code}/ready"))
            .bearer_auth(token)
            .json(&ReadyRequest { ready: true })
            .send()
            .await
            .unwrap())
        .await;
    }

    let lobby: RoomView = ok(client
        .get(format!("{base}/api/v1/rooms/{code}"))
        .bearer_auth(&gold.token)
        .send()
        .await
        .unwrap())
    .await
    .json()
    .await
    .unwrap();
    assert_eq!(seat_rank(&lobby, gold_player), Some(1));
    assert_eq!(seat_rank(&lobby, guest_player), None);
    assert_eq!(seat_rank(&lobby, fourth_player), None);

    let started: StartGameResponse = ok(client
        .post(format!("{base}/api/v1/rooms/{code}/start"))
        .bearer_auth(&gold.token)
        .json(&StartGameRequest { seed: Some(11) })
        .send()
        .await
        .unwrap())
    .await
    .json()
    .await
    .unwrap();

    let host = base.trim_start_matches("http://");
    let (mut guest_ws, _) = tokio_tungstenite::connect_async(format!(
        "ws://{host}/api/v1/games/{}/ws?token={}",
        started.game_id, guest.token
    ))
    .await
    .unwrap();
    let (mut gold_ws, _) = tokio_tungstenite::connect_async(format!(
        "ws://{host}/api/v1/games/{}/ws?token={}",
        started.game_id, gold.token
    ))
    .await
    .unwrap();

    let opening = next_snapshot(&mut guest_ws)
        .await
        .expect("opening snapshot");
    assert_eq!(opening.own_ladder_rank, None);
    assert!(!opening.own_signed_in);
    assert_eq!(
        opening
            .opponents
            .iter()
            .find(|opponent| opponent.player_id == gold_player)
            .and_then(|opponent| opponent.ladder_rank),
        Some(1)
    );
    assert!(
        opening
            .opponents
            .iter()
            .find(|opponent| opponent.player_id == gold_player)
            .is_some_and(|opponent| opponent.signed_in)
    );
    assert_eq!(
        opening
            .opponents
            .iter()
            .find(|opponent| opponent.player_id == fourth_player)
            .and_then(|opponent| opponent.ladder_rank),
        None
    );
    assert!(
        opening
            .opponents
            .iter()
            .find(|opponent| opponent.player_id == fourth_player)
            .is_some_and(|opponent| opponent.signed_in)
    );

    let leave = ClientEnvelope {
        protocol_version: PROTOCOL_VERSION,
        action_id: ActionId::new(),
        game_id: started.game_id,
        expected_state_version: opening.state_version,
        action: ClientCommand::LeaveGame,
    };
    // Gold reads their own snapshot so the leave uses the current version.
    let gold_view = next_snapshot(&mut gold_ws).await.expect("gold snapshot");
    let leave = ClientEnvelope {
        expected_state_version: gold_view.state_version,
        ..leave
    };
    gold_ws
        .send(Message::Text(serde_json::to_string(&leave).unwrap().into()))
        .await
        .unwrap();

    let mut claimed = None;
    let mut last_error = String::new();
    for _ in 0..40 {
        let response = client
            .post(format!("{base}/api/v1/rooms/{code}/claim"))
            .bearer_auth(&silver.token)
            .json(&ClaimSeatRequest {
                player_id: Some(gold_player),
            })
            .send()
            .await
            .unwrap();
        if response.status().is_success() {
            claimed = Some(response.json::<ClaimSeatResponse>().await.unwrap());
            break;
        }
        last_error = format!(
            "{} {}",
            response.status(),
            response.text().await.unwrap_or_default()
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    let claimed = claimed.unwrap_or_else(|| panic!("claim failed: {last_error}"));
    assert_eq!(seat_rank(&claimed.room, gold_player), Some(2));
    assert_eq!(seat_rank(&claimed.room, guest_player), None);

    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    let mut saw_transfer = false;
    while tokio::time::Instant::now() < deadline {
        let Some(view) = next_snapshot(&mut guest_ws).await else {
            break;
        };
        assert_eq!(view.own_ladder_rank, None);
        let gold_seat = view
            .opponents
            .iter()
            .find(|opponent| opponent.player_id == gold_player)
            .and_then(|opponent| opponent.ladder_rank);
        if gold_seat == Some(2) {
            saw_transfer = true;
            break;
        }
    }
    assert!(saw_transfer, "cap stayed with the player who left");
}
