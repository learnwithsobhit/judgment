//! Presence: grace → vacant seat → claim or end-game; host migration.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use judgement_domain::{ActionId, ConnectionStatus, GameId, PlayerId};
use judgement_engine::{GamePhase, PlayerGameView};
use judgement_persistence::MemoryStore;
use judgement_protocol::{
    ClaimSeatResponse, ClientCommand, ClientEnvelope, CreateGuestSessionResponse,
    CreateRoomResponse, JoinRoomResponse, ServerMessage, StartGameResponse, PROTOCOL_VERSION,
};
use judgement_server::restore::bootstrap;
use judgement_server::{build_router, state::AppState};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

const READ_TIMEOUT: Duration = Duration::from_secs(5);

async fn spawn_with(state: Arc<AppState>) -> SocketAddr {
    std::env::set_var("JUDGEMENT_ALLOW_SEED", "1");
    let router = build_router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    tokio::time::sleep(Duration::from_millis(20)).await;
    addr
}

struct Client {
    token: String,
    player_id: PlayerId,
    ws: Option<WebSocketStream<MaybeTlsStream<TcpStream>>>,
    last: Option<PlayerGameView>,
}

impl Client {
    async fn guest(base: &str, nickname: &str) -> Self {
        let http = reqwest::Client::new();
        let session: CreateGuestSessionResponse = http
            .post(format!("{base}/api/v1/guest-sessions"))
            .json(&serde_json::json!({ "nickname": nickname }))
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        Self {
            token: session.token,
            player_id: PlayerId::new(),
            ws: None,
            last: None,
        }
    }

    fn headers(&self) -> reqwest::header::HeaderMap {
        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(
            reqwest::header::AUTHORIZATION,
            format!("Bearer {}", self.token).parse().unwrap(),
        );
        headers
    }

    async fn connect_ws(&mut self, base: &str, game_id: GameId) {
        let host = base.trim_start_matches("http://");
        let url = format!("ws://{host}/api/v1/games/{game_id}/ws?token={}", self.token);
        let (ws, _) = tokio_tungstenite::connect_async(url).await.unwrap();
        self.ws = Some(ws);
        self.drain_until_snapshot().await;
    }

    async fn drain_until_snapshot(&mut self) {
        let ws = self.ws.as_mut().unwrap();
        let deadline = tokio::time::Instant::now() + READ_TIMEOUT;
        while tokio::time::Instant::now() < deadline {
            let msg = tokio::time::timeout(Duration::from_millis(200), ws.next()).await;
            let Ok(Some(Ok(Message::Text(text)))) = msg else {
                continue;
            };
            let server: ServerMessage = serde_json::from_str(&text).unwrap();
            match server {
                ServerMessage::StateSnapshot { view } => {
                    self.last = Some(view);
                    return;
                }
                ServerMessage::TokenRotated { token } => self.token = token,
                _ => {}
            }
        }
        panic!("no snapshot");
    }
}

async fn start_four_player_game(base: &str, clients: &mut [Client]) -> (GameId, String) {
    let http = reqwest::Client::new();
    let created: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .headers(clients[0].headers())
        .json(&serde_json::json!({
            "max_players": 4,
            "turn_timeout_seconds": null,
            "first_trump": "spades"
        }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    clients[0].player_id = created.player_id;
    let code = created.room.code.clone();
    let room_id = created.room.room_id;

    for client in clients.iter_mut().skip(1) {
        let joined: JoinRoomResponse = http
            .post(format!("{base}/api/v1/rooms/{code}/join"))
            .headers(client.headers())
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        client.player_id = joined.player_id;
    }
    for client in clients.iter() {
        http.post(format!("{base}/api/v1/rooms/{room_id}/ready"))
            .headers(client.headers())
            .json(&serde_json::json!({ "ready": true }))
            .send()
            .await
            .unwrap();
    }
    let started: StartGameResponse = http
        .post(format!("{base}/api/v1/rooms/{room_id}/start"))
        .headers(clients[0].headers())
        .json(&serde_json::json!({ "seed": 11 }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    (started.game_id, code)
}

#[tokio::test]
async fn leave_marks_seat_vacant_then_claim_restores() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");

    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let (game_id, code) = start_four_player_game(&base, &mut clients).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }

    let vacant_player = clients[0].player_id;
    {
        let view = clients[0].last.as_ref().unwrap();
        let envelope = ClientEnvelope {
            protocol_version: PROTOCOL_VERSION,
            action_id: ActionId::new(),
            game_id,
            expected_state_version: view.state_version,
            action: ClientCommand::LeaveGame,
        };
        let ws = clients[0].ws.as_mut().unwrap();
        ws.send(Message::Text(serde_json::to_string(&envelope).unwrap().into()))
            .await
            .unwrap();
        clients[0].ws = None;
    }

    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    let mut saw_vacant = false;
    while tokio::time::Instant::now() < deadline {
        let ws = clients[1].ws.as_mut().unwrap();
        if let Ok(Some(Ok(Message::Text(text)))) =
            tokio::time::timeout(Duration::from_millis(100), ws.next()).await
        {
            let msg: ServerMessage = serde_json::from_str(&text).unwrap();
            match msg {
                ServerMessage::SeatVacant { player_id, room_code } => {
                    assert_eq!(player_id, vacant_player);
                    assert_eq!(room_code, code);
                    saw_vacant = true;
                }
                ServerMessage::StateSnapshot { view } => {
                    clients[1].last = Some(view.clone());
                    if view.opponents.iter().any(|o| {
                        o.player_id == vacant_player
                            && o.connection_status == ConnectionStatus::Vacant
                    }) {
                        saw_vacant = true;
                        break;
                    }
                }
                _ => {}
            }
        }
        if saw_vacant {
            break;
        }
    }
    assert!(saw_vacant, "seat should be vacant after LeaveGame");

    // Replacement joins via room code claim.
    let mut replacer = Client::guest(&base, "E").await;
    let http = reqwest::Client::new();
    let claimed: ClaimSeatResponse = http
        .post(format!("{base}/api/v1/rooms/{code}/claim"))
        .headers(replacer.headers())
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(claimed.player_id, vacant_player);
    assert_eq!(claimed.game_id, game_id);
    replacer.player_id = claimed.player_id;
    replacer.connect_ws(&base, game_id).await;
    let view = replacer.last.as_ref().unwrap();
    assert_eq!(view.phase, GamePhase::Bidding);

    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    let mut saw_name = false;
    while tokio::time::Instant::now() < deadline {
        let ws = clients[1].ws.as_mut().unwrap();
        if let Ok(Some(Ok(Message::Text(text)))) =
            tokio::time::timeout(Duration::from_millis(100), ws.next()).await
        {
            let msg: ServerMessage = serde_json::from_str(&text).unwrap();
            match msg {
                ServerMessage::StateSnapshot { view } => {
                    let ok = view.opponents.iter().any(|o| {
                        o.player_id == vacant_player && o.nickname == "E"
                    });
                    clients[1].last = Some(view);
                    if ok {
                        saw_name = true;
                        break;
                    }
                }
                ServerMessage::SeatClaimed { player_id, nickname } => {
                    assert_eq!(player_id, vacant_player);
                    assert_eq!(nickname, "E");
                    saw_name = true;
                    break;
                }
                _ => {}
            }
        }
    }
    assert!(saw_name, "claimed seat should show new nickname to peers");
}

#[tokio::test]
async fn host_can_end_game_while_vacant() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");

    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let (game_id, _code) = start_four_player_game(&base, &mut clients).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }

    // Non-host leaves → vacant.
    {
        let view = clients[1].last.as_ref().unwrap();
        let envelope = ClientEnvelope {
            protocol_version: PROTOCOL_VERSION,
            action_id: ActionId::new(),
            game_id,
            expected_state_version: view.state_version,
            action: ClientCommand::LeaveGame,
        };
        let ws = clients[1].ws.as_mut().unwrap();
        ws.send(Message::Text(serde_json::to_string(&envelope).unwrap().into()))
            .await
            .unwrap();
        clients[1].ws = None;
    }
    tokio::time::sleep(Duration::from_millis(100)).await;

    // Host ends game.
    {
        let view = clients[0].last.as_ref().unwrap();
        let envelope = ClientEnvelope {
            protocol_version: PROTOCOL_VERSION,
            action_id: ActionId::new(),
            game_id,
            expected_state_version: view.state_version,
            action: ClientCommand::EndGame,
        };
        let ws = clients[0].ws.as_mut().unwrap();
        ws.send(Message::Text(serde_json::to_string(&envelope).unwrap().into()))
            .await
            .unwrap();
    }

    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    let mut saw_ended = false;
    while tokio::time::Instant::now() < deadline {
        let ws = clients[2].ws.as_mut().unwrap();
        if let Ok(Some(Ok(Message::Text(text)))) =
            tokio::time::timeout(Duration::from_millis(100), ws.next()).await
        {
            let msg: ServerMessage = serde_json::from_str(&text).unwrap();
            if matches!(msg, ServerMessage::GameEnded { .. }) {
                saw_ended = true;
                break;
            }
        }
    }
    assert!(saw_ended, "clients should observe GameEnded");
}

#[tokio::test]
async fn host_leave_promotes_another_seat() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");

    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let (game_id, _) = start_four_player_game(&base, &mut clients).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }

    clients[0].ws.as_mut().unwrap().close(None).await.unwrap();
    clients[0].ws = None;

    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    let mut new_host = None;
    while tokio::time::Instant::now() < deadline {
        let ws = clients[1].ws.as_mut().unwrap();
        if let Ok(Some(Ok(Message::Text(text)))) =
            tokio::time::timeout(Duration::from_millis(100), ws.next()).await
        {
            let msg: ServerMessage = serde_json::from_str(&text).unwrap();
            if let ServerMessage::HostChanged { new_host: id } = msg {
                new_host = Some(id);
                break;
            }
        }
    }
    assert!(new_host.is_some());
    assert_ne!(new_host.unwrap(), clients[0].player_id);
}
