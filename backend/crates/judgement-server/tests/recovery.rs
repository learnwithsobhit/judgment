//! Phase 5 exit criteria: restart mid-game, restore actor + dedup, continue.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use judgement_domain::{ActionId, GameId, PlayerId};
use judgement_engine::{GamePhase, PlayerGameView};
use judgement_persistence::{GameStore, MemoryStore};
use judgement_protocol::{
    ClientCommand, ClientEnvelope, CreateGuestSessionResponse, CreateRoomResponse,
    JoinRoomResponse, ServerMessage, StartGameResponse, PROTOCOL_VERSION,
};
use judgement_server::restore::bootstrap;
use judgement_server::{build_router, state::AppState};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

const READ_TIMEOUT: Duration = Duration::from_secs(10);

async fn spawn_with(state: Arc<AppState>) -> SocketAddr {
    let router = build_router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    // Let the listener come up.
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
            player_id: PlayerId::new(), // overwritten on join
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
        let url = format!(
            "ws://{}/api/v1/games/{}/ws?token={}",
            base.trim_start_matches("http://"),
            game_id,
            self.token
        );
        let (ws, _) = tokio_tungstenite::connect_async(url).await.unwrap();
        self.ws = Some(ws);
        self.wait_snapshot().await;
    }

    async fn wait_snapshot(&mut self) -> PlayerGameView {
        let ws = self.ws.as_mut().unwrap();
        let deadline = tokio::time::Instant::now() + READ_TIMEOUT;
        loop {
            let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
            let msg = tokio::time::timeout(remaining, ws.next())
                .await
                .expect("timeout waiting for snapshot")
                .expect("ws closed")
                .unwrap();
            if let Message::Text(text) = msg {
                let server: ServerMessage = serde_json::from_str(&text).unwrap();
                match server {
                    ServerMessage::StateSnapshot { view } => {
                        self.last = Some(view.clone());
                        return view;
                    }
                    ServerMessage::TokenRotated { token } => {
                        self.token = token;
                    }
                    _ => {}
                }
            }
        }
    }

    async fn act(&mut self, action: ClientCommand) {
        let view = self.last.as_ref().unwrap();
        let envelope = ClientEnvelope {
            protocol_version: PROTOCOL_VERSION,
            action_id: ActionId::new(),
            game_id: view.game_id,
            expected_state_version: view.state_version,
            action,
        };
        let ws = self.ws.as_mut().unwrap();
        ws.send(Message::Text(serde_json::to_string(&envelope).unwrap().into()))
            .await
            .unwrap();
        // Drain until we see our version advance (or a rejection).
        let before = view.state_version;
        let deadline = tokio::time::Instant::now() + READ_TIMEOUT;
        while tokio::time::Instant::now() < deadline {
            let msg = tokio::time::timeout(Duration::from_millis(200), ws.next()).await;
            let Ok(Some(Ok(Message::Text(text)))) = msg else {
                continue;
            };
            let server: ServerMessage = serde_json::from_str(&text).unwrap();
            match server {
                ServerMessage::StateSnapshot { view } => {
                    self.last = Some(view.clone());
                    if view.state_version > before {
                        return;
                    }
                }
                ServerMessage::CommandRejected { message, .. } => {
                    panic!("command rejected: {message}");
                }
                _ => {}
            }
        }
        panic!("did not observe state advance");
    }
}

#[tokio::test]
async fn restart_restores_game_and_dedup_registry() {
    let store = Arc::new(MemoryStore::new());
    let state = bootstrap(store.clone()).await.unwrap();
    let addr = spawn_with(state.clone()).await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    // Four players, no timer, seeded deal.
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
            "first_trump": "clubs"
        }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    clients[0].player_id = created.player_id;
    let room_code = created.room.code.clone();
    let room_id = created.room.room_id;

    for client in clients.iter_mut().skip(1) {
        let joined: JoinRoomResponse = http
            .post(format!("{base}/api/v1/rooms/{room_code}/join"))
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
        .json(&serde_json::json!({ "seed": 42 }))
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

    // Play a few bids so state_version advances past the start snapshot.
    let mut bids_placed = 0;
    while bids_placed < 3 {
        // Refresh views.
        for client in &mut clients {
            let _ = tokio::time::timeout(Duration::from_millis(50), client.wait_snapshot()).await;
        }
        let actor_idx = clients.iter().position(|c| {
            let view = c.last.as_ref().unwrap();
            view.phase == GamePhase::Bidding && view.current_turn == Some(c.player_id)
        });
        let Some(idx) = actor_idx else {
            if bids_placed == 0 {
                // Still settling after connect.
                continue;
            }
            panic!("expected someone to bid");
        };
        let bid = clients[idx].last.as_ref().unwrap().legal_actions.legal_bids[0];
        clients[idx].act(ClientCommand::PlaceBid { bid }).await;
        bids_placed += 1;
        for (i, client) in clients.iter_mut().enumerate() {
            if i == idx {
                continue;
            }
            let _ = tokio::time::timeout(Duration::from_millis(100), client.wait_snapshot()).await;
        }
    }

    let version_before = clients[0].last.as_ref().unwrap().state_version;
    assert!(version_before > 1, "game should have progressed");

    // Capture an action_id that was already processed for dedup check later.
    let processed = store.load_processed_actions(game_id).await.unwrap();
    assert!(!processed.is_empty());
    let (dup_action, dup_version) = processed[0];

    // Simulate process restart: drop the live AppState/actors and bootstrap
    // a fresh one from the same durable store.
    drop(state);
    tokio::time::sleep(Duration::from_millis(50)).await;

    let restored_state = bootstrap(store.clone()).await.unwrap();
    let restored_count = restored_state.games.lock().unwrap().len();
    assert_eq!(restored_count, 1, "active game must be restored");
    let new_addr = spawn_with(restored_state).await;
    let new_base = format!("http://{new_addr}");

    // Reconnect with the same tokens (sessions restored).
    for client in &mut clients {
        client.ws = None;
        client.connect_ws(&new_base, game_id).await;
        assert_eq!(
            client.last.as_ref().unwrap().state_version,
            version_before,
            "restored state version must match"
        );
    }

    // Dedup: replaying a prior action_id must not advance state.
    {
        let client = &mut clients[0];
        let view = client.last.as_ref().unwrap().clone();
        let envelope = ClientEnvelope {
            protocol_version: PROTOCOL_VERSION,
            action_id: dup_action,
            game_id,
            expected_state_version: view.state_version,
            action: ClientCommand::PlaceBid { bid: 0 },
        };
        let ws = client.ws.as_mut().unwrap();
        ws.send(Message::Text(serde_json::to_string(&envelope).unwrap().into()))
            .await
            .unwrap();

        let deadline = tokio::time::Instant::now() + READ_TIMEOUT;
        let mut saw_accept = false;
        while tokio::time::Instant::now() < deadline {
            let msg = tokio::time::timeout(Duration::from_millis(200), ws.next()).await;
            let Ok(Some(Ok(Message::Text(text)))) = msg else {
                continue;
            };
            let server: ServerMessage = serde_json::from_str(&text).unwrap();
            if let ServerMessage::CommandAccepted {
                action_id,
                new_state_version,
            } = server
            {
                assert_eq!(action_id, dup_action);
                assert_eq!(new_state_version, dup_version);
                saw_accept = true;
                break;
            }
        }
        assert!(saw_accept, "duplicate action should be acknowledged with prior version");
        // State must not have moved past version_before from the duplicate.
        client.wait_snapshot().await;
        assert_eq!(client.last.as_ref().unwrap().state_version, version_before);
    }

    // Continue the game from the restored actor — place remaining bids/cards
    // until the round leaves bidding or a few more actions succeed.
    let mut progressed = false;
    for _ in 0..8 {
        for client in &mut clients {
            let view = client.last.clone().unwrap();
            if view.current_turn != Some(client.player_id) {
                continue;
            }
            if !view.legal_actions.legal_bids.is_empty() {
                let bid = view.legal_actions.legal_bids[0];
                client.act(ClientCommand::PlaceBid { bid }).await;
                progressed = true;
            } else if !view.legal_actions.playable_cards.is_empty() {
                let card_id = view.legal_actions.playable_cards[0];
                client.act(ClientCommand::PlayCard { card_id }).await;
                progressed = true;
            }
        }
        // Refresh snapshots
        for client in &mut clients {
            let _ = tokio::time::timeout(Duration::from_millis(50), client.wait_snapshot()).await;
        }
        if clients[0].last.as_ref().unwrap().state_version > version_before {
            progressed = true;
            break;
        }
    }
    assert!(progressed, "game must continue after restore");
    let _ = HashMap::<GameId, ()>::new();
}
