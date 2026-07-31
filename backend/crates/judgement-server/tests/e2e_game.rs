//! Phase 3 exit criteria (PLAN.md §27 Phase 3):
//! - six test clients complete a game over WebSockets
//! - duplicate actions do not apply twice
//! - stale clients resynchronise correctly
//! - timer expiry applies a legal automatic action

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

use judgement_domain::{ActionId, GameId, PlayerId};
use judgement_engine::{GamePhase, PlayerGameView};
use judgement_protocol::{
    ClientCommand, ClientEnvelope, CreateGuestSessionResponse, CreateRoomResponse,
    JoinRoomResponse, RejectReason, ServerMessage, StartGameResponse, PROTOCOL_VERSION,
};
use judgement_persistence::MemoryStore;
use judgement_server::{build_router, state::AppState};

const READ_TIMEOUT: Duration = Duration::from_secs(10);

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

struct TestClient {
    nickname: String,
    token: String,
    player_id: PlayerId,
    ws: Option<WebSocketStream<MaybeTlsStream<TcpStream>>>,
    view: Option<PlayerGameView>,
}

struct Harness {
    addr: SocketAddr,
    http: reqwest::Client,
    game_id: Option<GameId>,
    clients: Vec<TestClient>,
}

impl Harness {
    async fn new(addr: SocketAddr) -> Self {
        Self { addr, http: reqwest::Client::new(), game_id: None, clients: Vec::new() }
    }

    fn url(&self, path: &str) -> String {
        format!("http://{}{}", self.addr, path)
    }

    async fn create_session(&self, nickname: &str) -> CreateGuestSessionResponse {
        self.http
            .post(self.url("/api/v1/guest-sessions"))
            .json(&serde_json::json!({ "nickname": nickname }))
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap()
    }

    /// Create a room + five joiners, everyone ready, host starts with `seed`.
    async fn start_six_player_game(&mut self, turn_timeout_seconds: u16, seed: u64) {
        let host = self.create_session("Host").await;
        let create: CreateRoomResponse = self
            .http
            .post(self.url("/api/v1/rooms"))
            .bearer_auth(&host.token)
            .json(&serde_json::json!({ "turn_timeout_seconds": turn_timeout_seconds }))
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        let room_code = create.room.code.clone();
        self.clients.push(TestClient {
            nickname: "Host".into(),
            token: host.token,
            player_id: create.player_id,
            ws: None,
            view: None,
        });

        for index in 2..=6 {
            let nickname = format!("P{index}");
            let session = self.create_session(&nickname).await;
            let join: JoinRoomResponse = self
                .http
                .post(self.url(&format!("/api/v1/rooms/{room_code}/join")))
                .bearer_auth(&session.token)
                .json(&serde_json::json!({}))
                .send()
                .await
                .unwrap()
                .json()
                .await
                .unwrap();
            self.clients.push(TestClient {
                nickname,
                token: session.token,
                player_id: join.player_id,
                ws: None,
                view: None,
            });
        }

        for client in &self.clients {
            let response = self
                .http
                .post(self.url(&format!("/api/v1/rooms/{room_code}/ready")))
                .bearer_auth(&client.token)
                .json(&serde_json::json!({ "ready": true }))
                .send()
                .await
                .unwrap();
            assert!(response.status().is_success(), "ready failed for {}", client.nickname);
        }

        let start: StartGameResponse = self
            .http
            .post(self.url(&format!("/api/v1/rooms/{room_code}/start")))
            .bearer_auth(&self.clients[0].token)
            .json(&serde_json::json!({ "seed": seed }))
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        self.game_id = Some(start.game_id);
    }

    async fn connect_all(&mut self) {
        let game_id = self.game_id.unwrap();
        for client in &mut self.clients {
            let url = format!(
                "ws://{}/api/v1/games/{}/ws?token={}",
                self.addr, game_id, client.token
            );
            let (ws, _response) = tokio_tungstenite::connect_async(url).await.unwrap();
            client.ws = Some(ws);
        }
        // Every client receives an initial snapshot on connect; also apply
        // TokenRotated and drain late snapshots from peers connecting after us.
        for index in 0..self.clients.len() {
            let messages = self.read_until_snapshot(index).await;
            for message in &messages {
                if let ServerMessage::TokenRotated { token } = message {
                    self.clients[index].token = token.clone();
                }
            }
        }
        // Drain any additional peer-driven snapshots so command tests start clean.
        for index in 0..self.clients.len() {
            loop {
                let client = &mut self.clients[index];
                let ws = client.ws.as_mut().unwrap();
                match tokio::time::timeout(Duration::from_millis(30), ws.next()).await {
                    Ok(Some(Ok(Message::Text(text)))) => {
                        let message: ServerMessage = serde_json::from_str(text.as_str()).unwrap();
                        if let ServerMessage::StateSnapshot { view } = message {
                            client.view = Some(view);
                        } else if let ServerMessage::TokenRotated { token } = message {
                            client.token = token;
                        }
                    }
                    _ => break,
                }
            }
        }
        self.wait_until_ready().await;
    }

    /// Block until every client has a view and either the game is finished or
    /// exactly one seat has legal actions.
    async fn wait_until_ready(&mut self) {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
        while tokio::time::Instant::now() < deadline {
            if self.clients.iter().all(|c| c.view.is_some()) {
                let max_v = self
                    .clients
                    .iter()
                    .filter_map(|c| c.view.as_ref().map(|v| v.state_version))
                    .max()
                    .unwrap_or(0);
                let aligned = self
                    .clients
                    .iter()
                    .all(|c| c.view.as_ref().is_some_and(|v| v.state_version == max_v));
                if aligned {
                    if self.phase() == GamePhase::Finished || self.current_actor().is_some() {
                        return;
                    }
                }
            }
            for index in 0..self.clients.len() {
                let client = &mut self.clients[index];
                let ws = client.ws.as_mut().unwrap();
                if let Ok(Some(Ok(Message::Text(text)))) =
                    tokio::time::timeout(Duration::from_millis(20), ws.next()).await
                {
                    let message: ServerMessage = serde_json::from_str(text.as_str()).unwrap();
                    if let ServerMessage::StateSnapshot { view } = message {
                        client.view = Some(view);
                    } else if let ServerMessage::TokenRotated { token } = message {
                        client.token = token;
                    }
                }
            }
        }
        panic!(
            "clients not ready; versions={:?} phase={:?}",
            self.clients
                .iter()
                .map(|c| c.view.as_ref().map(|v| v.state_version))
                .collect::<Vec<_>>(),
            self.clients[0].view.as_ref().map(|v| v.phase)
        );
    }

    /// Read messages until a `StateSnapshot` arrives; returns every message
    /// seen on the way (snapshot last).
    async fn read_until_snapshot(&mut self, index: usize) -> Vec<ServerMessage> {
        let client = &mut self.clients[index];
        let ws = client.ws.as_mut().unwrap();
        let mut seen = Vec::new();
        loop {
            let frame = tokio::time::timeout(READ_TIMEOUT, ws.next())
                .await
                .unwrap_or_else(|_| panic!("timeout waiting for snapshot for {}", client.nickname))
                .expect("socket closed")
                .expect("socket error");
            let Message::Text(text) = frame else { continue };
            let message: ServerMessage = serde_json::from_str(text.as_str()).unwrap();
            let is_snapshot = matches!(message, ServerMessage::StateSnapshot { .. });
            if let ServerMessage::StateSnapshot { view } = &message {
                client.view = Some(view.clone());
            }
            seen.push(message);
            if is_snapshot {
                return seen;
            }
        }
    }

    /// Read one protocol message (skipping timers/presence noise is up to the caller).
    async fn read_message(&mut self, index: usize) -> ServerMessage {
        let client = &mut self.clients[index];
        let ws = client.ws.as_mut().unwrap();
        loop {
            let frame = tokio::time::timeout(READ_TIMEOUT, ws.next())
                .await
                .expect("timeout waiting for message")
                .expect("socket closed")
                .expect("socket error");
            if let Message::Text(text) = frame {
                return serde_json::from_str(text.as_str()).unwrap();
            }
        }
    }

    async fn send_envelope(&mut self, index: usize, envelope: &ClientEnvelope) {
        let client = &mut self.clients[index];
        let ws = client.ws.as_mut().unwrap();
        let json = serde_json::to_string(envelope).unwrap();
        ws.send(Message::Text(json.into())).await.unwrap();
    }

    fn envelope(&self, index: usize, action: ClientCommand) -> ClientEnvelope {
        let view = self.clients[index].view.as_ref().expect("client has a view");
        ClientEnvelope {
            protocol_version: PROTOCOL_VERSION,
            action_id: ActionId::new(),
            game_id: self.game_id.unwrap(),
            expected_state_version: view.state_version,
            action,
        }
    }

    /// The index of the client whose view says it is their turn with legal
    /// actions available.
    fn current_actor(&self) -> Option<usize> {
        self.clients.iter().position(|c| {
            c.view.as_ref().is_some_and(|v| {
                v.current_turn == Some(c.player_id)
                    && (!v.legal_actions.legal_bids.is_empty()
                        || !v.legal_actions.playable_cards.is_empty())
            })
        })
    }

    /// Drive one command from the current actor and wait for the resulting
    /// snapshot on every client.
    async fn step(&mut self) {
        let index = self.current_actor().expect("someone must have a legal action");
        let view = self.clients[index].view.as_ref().unwrap();
        let action = if !view.legal_actions.legal_bids.is_empty() {
            ClientCommand::PlaceBid { bid: view.legal_actions.legal_bids[0] }
        } else {
            ClientCommand::PlayCard { card_id: view.legal_actions.playable_cards[0] }
        };
        let envelope = self.envelope(index, action);
        self.send_envelope(index, &envelope).await;

        // Sender gets CommandAccepted; peer snapshots may arrive first.
        let mut accepted = false;
        let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
        while !accepted && tokio::time::Instant::now() < deadline {
            for message in self.read_until_snapshot(index).await {
                match message {
                    ServerMessage::CommandAccepted { action_id, .. } => {
                        assert_eq!(action_id, envelope.action_id);
                        accepted = true;
                    }
                    ServerMessage::CommandRejected { message, .. } => {
                        panic!("command unexpectedly rejected: {message}");
                    }
                    _ => {}
                }
            }
        }
        assert!(accepted, "expected CommandAccepted");

        for other in 0..self.clients.len() {
            if other != index {
                // Drain until this peer reaches at least the actor's version.
                let target = self.clients[index]
                    .view
                    .as_ref()
                    .map(|v| v.state_version)
                    .unwrap_or(0);
                let deadline = tokio::time::Instant::now() + Duration::from_secs(2);
                while tokio::time::Instant::now() < deadline {
                    let peer_v = self.clients[other]
                        .view
                        .as_ref()
                        .map(|v| v.state_version)
                        .unwrap_or(0);
                    if peer_v >= target {
                        break;
                    }
                    self.read_until_snapshot(other).await;
                }
            }
        }
        self.wait_until_ready().await;
    }

    fn phase(&self) -> GamePhase {
        self.clients[0].view.as_ref().unwrap().phase
    }
}

#[tokio::test]
async fn six_clients_complete_a_full_game() {
    let addr = spawn_server().await;
    let mut harness = Harness::new(addr).await;
    harness.start_six_player_game(300, 42).await;
    harness.connect_all().await;

    let mut steps = 0;
    while harness.phase() != GamePhase::Finished {
        harness.step().await;
        steps += 1;
        assert!(steps <= 264, "game did not finish within the expected command count");
    }
    assert_eq!(steps, 264, "8 rounds = 48 bids + 216 card plays");

    // Every client sees the final scoreboard; scores are consistent.
    let reference: Vec<_> = {
        let mut scores = harness.clients[0].view.as_ref().unwrap().scores.clone();
        scores.sort_by_key(|s| s.player_id);
        scores
    };
    for client in &harness.clients {
        let view = client.view.as_ref().unwrap();
        assert_eq!(view.phase, GamePhase::Finished);
        let mut scores = view.scores.clone();
        scores.sort_by_key(|s| s.player_id);
        assert_eq!(scores, reference);
        assert!(view.own_hand.is_empty(), "all cards were played");
    }
}

#[tokio::test]
async fn duplicate_actions_do_not_apply_twice() {
    let addr = spawn_server().await;
    let mut harness = Harness::new(addr).await;
    harness.start_six_player_game(300, 7).await;
    harness.connect_all().await;

    let index = harness.current_actor().unwrap();
    let view = harness.clients[index].view.as_ref().unwrap();
    let bid = view.legal_actions.legal_bids[0];
    let envelope = harness.envelope(index, ClientCommand::PlaceBid { bid });

    // First send: accepted normally.
    harness.send_envelope(index, &envelope).await;
    let mut first_version = None;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    while first_version.is_none() && tokio::time::Instant::now() < deadline {
        let messages = harness.read_until_snapshot(index).await;
        for m in &messages {
            match m {
                ServerMessage::CommandAccepted { new_state_version, .. } => {
                    first_version = Some(*new_state_version);
                }
                ServerMessage::CommandRejected { message, reason, .. } => {
                    panic!("first send rejected: {message} ({reason:?})");
                }
                _ => {}
            }
        }
    }
    let first_version = first_version.expect("first send is accepted");

    // Exact same envelope again (same action_id, now-stale expected version):
    // dedup returns the prior result and does not re-apply.
    harness.send_envelope(index, &envelope).await;
    let messages = harness.read_until_snapshot(index).await;
    let second_version = messages
        .iter()
        .find_map(|m| match m {
            ServerMessage::CommandAccepted { new_state_version, .. } => Some(*new_state_version),
            _ => None,
        })
        .expect("duplicate returns the prior CommandAccepted");
    assert_eq!(first_version, second_version);

    let view = harness.clients[index].view.as_ref().unwrap();
    assert_eq!(view.state_version, first_version, "state did not advance twice");
    let own_bid_count = view.bids.iter().filter(|b| b.player_id == harness.clients[index].player_id).count();
    assert_eq!(own_bid_count, 1, "the bid was recorded exactly once");
}

#[tokio::test]
async fn stale_clients_are_rejected_and_resynchronised() {
    let addr = spawn_server().await;
    let mut harness = Harness::new(addr).await;
    harness.start_six_player_game(300, 9).await;
    harness.connect_all().await;

    let index = harness.current_actor().unwrap();
    let view = harness.clients[index].view.as_ref().unwrap();
    let bid = view.legal_actions.legal_bids[0];
    let real_version = view.state_version;

    let mut envelope = harness.envelope(index, ClientCommand::PlaceBid { bid });
    envelope.expected_state_version = real_version + 100; // stale/incoherent client

    harness.send_envelope(index, &envelope).await;

    // Expect a StaleState rejection followed by a fresh snapshot.
    // Ignore leftover peer snapshots until the rejection arrives.
    let mut rejected = false;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    while tokio::time::Instant::now() < deadline {
        match harness.read_message(index).await {
            ServerMessage::CommandRejected { reason, retryable, .. } => {
                assert!(matches!(
                    reason,
                    RejectReason::Game { error: judgement_domain::GameError::StaleState { .. } }
                ));
                assert!(!retryable);
                rejected = true;
            }
            ServerMessage::StateSnapshot { view } if rejected => {
                assert_eq!(view.state_version, real_version, "resync snapshot is current");
                return;
            }
            _ => {}
        }
    }
    panic!("did not observe stale rejection + resync snapshot");
}

#[tokio::test]
async fn timer_expiry_applies_legal_automatic_actions() {
    let addr = spawn_server().await;
    let mut harness = Harness::new(addr).await;
    // 1-second turns; nobody acts.
    harness.start_six_player_game(1, 11).await;
    harness.connect_all().await;

    assert_eq!(harness.phase(), GamePhase::Bidding);

    // Six auto-bids should arrive without any client command; each produces a
    // snapshot broadcast. Wait until the game reaches Playing.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(30);
    while harness.phase() != GamePhase::Playing {
        assert!(tokio::time::Instant::now() < deadline, "auto-bids did not progress the game");
        harness.read_until_snapshot(0).await;
    }

    let view = harness.clients[0].view.as_ref().unwrap();
    assert_eq!(view.bids.len(), 6, "every seat auto-bid exactly once");
    assert_eq!(view.state_version, 7, "start + six auto-bids, no duplicates from stale deadlines");
}
