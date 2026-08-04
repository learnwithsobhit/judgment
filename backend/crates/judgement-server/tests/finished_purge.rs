//! Natural finish deletes the game row and returns the room to Lobby.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use judgement_domain::{ActionId, GameId, PlayerId};
use judgement_engine::{GamePhase, PlayerGameView};
use judgement_persistence::{GameStore, MemoryStore};
use judgement_protocol::{
    ClientCommand, ClientEnvelope, CreateGuestSessionResponse, CreateRoomResponse,
    JoinRoomResponse, RoomPhase, RoomView, ServerMessage, StartGameResponse, PROTOCOL_VERSION,
};
use judgement_server::restore::bootstrap;
use judgement_server::state::RoomStatus;
use judgement_server::{build_router, state::AppState};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

const READ_TIMEOUT: Duration = Duration::from_secs(8);

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

#[tokio::test]
async fn natural_finish_deletes_game_and_returns_room_to_lobby() {
    let store = Arc::new(MemoryStore::new());
    let state = bootstrap(store.clone()).await.unwrap();
    let state_ref = state.clone();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }

    let created: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .headers(clients[0].headers())
        .json(&serde_json::json!({
            "max_players": 4,
            "turn_timeout_seconds": null,
            "first_trump": "spades",
            "round_schedule": {
                "mode": "manual",
                "steps": [{ "cards": 1, "repeat": 1 }]
            }
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
    for client in &clients {
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
        .json(&serde_json::json!({ "seed": 7 }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let game_id = started.game_id;

    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }

    // Play out the single 1-card round.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(20);
    while tokio::time::Instant::now() < deadline {
        if clients
            .iter()
            .all(|c| c.last.as_ref().is_some_and(|v| v.phase == GamePhase::Finished))
        {
            break;
        }

        let actor = clients.iter().position(|c| {
            c.last.as_ref().is_some_and(|v| {
                v.current_turn == Some(c.player_id)
                    && (!v.legal_actions.legal_bids.is_empty()
                        || !v.legal_actions.playable_cards.is_empty())
            })
        });
        let Some(index) = actor else {
            // Wait for round-reveal advance or peer snapshots.
            for client in &mut clients {
                let ws = client.ws.as_mut().unwrap();
                if let Ok(Some(Ok(Message::Text(text)))) =
                    tokio::time::timeout(Duration::from_millis(50), ws.next()).await
                {
                    let msg: ServerMessage = serde_json::from_str(&text).unwrap();
                    if let ServerMessage::StateSnapshot { view } = msg {
                        client.last = Some(view);
                    } else if let ServerMessage::TokenRotated { token } = msg {
                        client.token = token;
                    }
                }
            }
            continue;
        };

        let view = clients[index].last.as_ref().unwrap();
        let action = if !view.legal_actions.legal_bids.is_empty() {
            ClientCommand::PlaceBid {
                bid: view.legal_actions.legal_bids[0],
            }
        } else {
            ClientCommand::PlayCard {
                card_id: view.legal_actions.playable_cards[0],
            }
        };
        let envelope = ClientEnvelope {
            protocol_version: PROTOCOL_VERSION,
            action_id: ActionId::new(),
            game_id,
            expected_state_version: view.state_version,
            action,
        };
        let json = serde_json::to_string(&envelope).unwrap();
        clients[index]
            .ws
            .as_mut()
            .unwrap()
            .send(Message::Text(json.into()))
            .await
            .unwrap();

        // Drain snapshots for everyone briefly.
        for _ in 0..8 {
            for client in &mut clients {
                let ws = client.ws.as_mut().unwrap();
                if let Ok(Some(Ok(Message::Text(text)))) =
                    tokio::time::timeout(Duration::from_millis(80), ws.next()).await
                {
                    let msg: ServerMessage = serde_json::from_str(&text).unwrap();
                    match msg {
                        ServerMessage::StateSnapshot { view } => client.last = Some(view),
                        ServerMessage::TokenRotated { token } => client.token = token,
                        _ => {}
                    }
                }
            }
        }
    }

    assert!(
        clients[0]
            .last
            .as_ref()
            .is_some_and(|v| v.phase == GamePhase::Finished),
        "expected finished view"
    );
    assert!(
        clients[0]
            .last
            .as_ref()
            .unwrap()
            .final_ranking
            .as_ref()
            .is_some_and(|r| !r.is_empty()),
        "client keeps final ranking from WS"
    );

    // Allow async delete_game + lobby persist to settle.
    let settle = tokio::time::Instant::now() + Duration::from_secs(3);
    while tokio::time::Instant::now() < settle {
        let history = store.load_game_history(game_id).await.unwrap();
        let room_lobby = {
            let rooms = state_ref.rooms.lock().unwrap();
            matches!(
                rooms.get(&room_id).map(|r| &r.status),
                Some(RoomStatus::Lobby)
            )
        };
        let actor_gone = !state_ref.games.lock().unwrap().contains_key(&game_id);
        if history.is_none() && room_lobby && actor_gone {
            // Room poll should also show lobby.
            let room: RoomView = http
                .get(format!("{base}/api/v1/rooms/{code}"))
                .headers(clients[0].headers())
                .send()
                .await
                .unwrap()
                .json()
                .await
                .unwrap();
            assert_eq!(room.phase, RoomPhase::Lobby);
            assert!(room.game_id.is_none());
            return;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }

    panic!(
        "finish cleanup incomplete; history={:?} room={:?} actor={}",
        store.load_game_history(game_id).await.unwrap().map(|h| h.status),
        state_ref
            .rooms
            .lock()
            .unwrap()
            .get(&room_id)
            .map(|r| format!("{:?}", r.status)),
        state_ref.games.lock().unwrap().contains_key(&game_id)
    );
}
