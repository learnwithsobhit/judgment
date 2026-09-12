//! Singleton legal cards are auto-played after a short delay.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use judgement_domain::{ActionId, ConnectionStatus, GameId, PlayerId};
use judgement_engine::{GamePhase, PlayerGameView};
use judgement_persistence::MemoryStore;
use judgement_protocol::{
    ClientCommand, ClientEnvelope, CreateGuestSessionResponse, CreateRoomResponse,
    JoinRoomResponse, ServerMessage, StartGameResponse, PROTOCOL_VERSION,
};
use judgement_server::actor::{FORCED_PLAY_DELAY, POST_TRICK_FORCED_DELAY};
use judgement_server::restore::{bootstrap, bootstrap_with_reconnect_grace};
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

    async fn send(&mut self, game_id: GameId, action: ClientCommand) {
        let view = self.last.as_ref().unwrap();
        let envelope = ClientEnvelope {
            protocol_version: PROTOCOL_VERSION,
            action_id: ActionId::new(),
            game_id,
            expected_state_version: view.state_version,
            action,
        };
        let ws = self.ws.as_mut().unwrap();
        ws.send(Message::Text(
            serde_json::to_string(&envelope).unwrap().into(),
        ))
        .await
        .unwrap();
    }
}

struct Pump {
    paused: bool,
    pause_reason: Option<String>,
}

async fn pump_for(clients: &mut [Client], duration: Duration) -> Pump {
    let deadline = tokio::time::Instant::now() + duration;
    let mut out = Pump {
        paused: false,
        pause_reason: None,
    };
    while tokio::time::Instant::now() < deadline {
        let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
        let slice = remaining.min(Duration::from_millis(50));
        for client in clients.iter_mut() {
            let Some(ws) = client.ws.as_mut() else {
                continue;
            };
            if let Ok(Some(Ok(Message::Text(text)))) = tokio::time::timeout(slice, ws.next()).await
            {
                let msg: ServerMessage = serde_json::from_str(&text).unwrap();
                match msg {
                    ServerMessage::StateSnapshot { view } => client.last = Some(view),
                    ServerMessage::TokenRotated { token } => client.token = token,
                    ServerMessage::GamePaused { reason, .. } => {
                        out.paused = true;
                        out.pause_reason = Some(reason);
                    }
                    _ => {}
                }
            }
        }
    }
    out
}

fn current_index(clients: &[Client]) -> Option<usize> {
    clients.iter().position(|c| {
        c.last.as_ref().is_some_and(|v| {
            v.current_turn == Some(c.player_id)
                && (!v.legal_actions.legal_bids.is_empty()
                    || !v.legal_actions.playable_cards.is_empty())
        })
    })
}

async fn start_game(base: &str, clients: &mut [Client], cards: u8, seed: u64) -> GameId {
    let http = reqwest::Client::new();
    let created: CreateRoomResponse = http
        .post(format!("{base}/api/v1/rooms"))
        .headers(clients[0].headers())
        .json(&serde_json::json!({
            "max_players": 4,
            "turn_timeout_seconds": null,
            "first_trump": "spades",
            "round_schedule": {
                "mode": "manual",
                "steps": [{ "cards": cards, "repeat": 1 }]
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
        .json(&serde_json::json!({ "seed": seed }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    started.game_id
}

async fn place_all_bids(clients: &mut [Client], game_id: GameId) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
    while tokio::time::Instant::now() < deadline {
        pump_for(clients, Duration::from_millis(20)).await;
        if clients.iter().all(|c| {
            c.last
                .as_ref()
                .is_some_and(|v| v.phase == GamePhase::Playing)
        }) {
            return;
        }
        let Some(index) = current_index(clients) else {
            continue;
        };
        let view = clients[index].last.as_ref().unwrap();
        if view.legal_actions.legal_bids.is_empty() {
            continue;
        }
        let bid = view.legal_actions.legal_bids[0];
        clients[index]
            .send(game_id, ClientCommand::PlaceBid { bid })
            .await;
        pump_for(clients, Duration::from_millis(80)).await;
    }
    panic!("did not finish bidding");
}

#[tokio::test]
async fn does_not_auto_bid() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");
    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let game_id = start_game(&base, &mut clients, 1, 11).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }
    pump_for(&mut clients, FORCED_PLAY_DELAY + Duration::from_millis(400)).await;
    let view = clients[0].last.as_ref().unwrap();
    assert_eq!(view.phase, GamePhase::Bidding);
    assert!(view.bids.is_empty());
}

#[tokio::test]
async fn singleton_auto_plays_after_delay() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");
    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let game_id = start_game(&base, &mut clients, 1, 11).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }
    place_all_bids(&mut clients, game_id).await;

    let before = clients[0].last.as_ref().unwrap().current_trick.len();
    assert_eq!(before, 0);
    pump_for(&mut clients, Duration::from_millis(200)).await;
    assert_eq!(
        clients[0].last.as_ref().unwrap().current_trick.len(),
        0,
        "must wait the forced-play beat"
    );
    pump_for(&mut clients, FORCED_PLAY_DELAY + Duration::from_millis(250)).await;
    let n = clients[0].last.as_ref().unwrap().current_trick.len();
    assert!(n >= 1, "singleton lead should auto-play, trick len={n}");
}

#[tokio::test]
async fn last_trick_plays_sequentially_not_in_one_tick() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");
    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let game_id = start_game(&base, &mut clients, 1, 11).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }
    place_all_bids(&mut clients, game_id).await;

    let mut sizes = Vec::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(6);
    while tokio::time::Instant::now() < deadline {
        pump_for(&mut clients, Duration::from_millis(40)).await;
        let n = clients[0]
            .last
            .as_ref()
            .map(|v| {
                if v.current_trick.is_empty() {
                    v.last_completed_trick
                        .as_ref()
                        .map(|t| t.plays.len())
                        .unwrap_or(0)
                } else {
                    v.current_trick.len()
                }
            })
            .unwrap_or(0);
        if sizes.last().copied() != Some(n) {
            sizes.push(n);
        }
        if n >= 4 {
            break;
        }
    }
    assert!(
        sizes.contains(&1) && sizes.contains(&2) && sizes.contains(&3),
        "last trick must appear card-by-card, got {sizes:?}"
    );
}

#[tokio::test]
async fn two_card_lead_is_not_forced() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");
    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let game_id = start_game(&base, &mut clients, 2, 11).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }
    place_all_bids(&mut clients, game_id).await;

    let index = current_index(&clients).expect("leader");
    let playable = clients[index]
        .last
        .as_ref()
        .unwrap()
        .legal_actions
        .playable_cards
        .len();
    assert!(playable >= 2, "opening lead of a 2-card round is a choice");
    pump_for(&mut clients, FORCED_PLAY_DELAY + Duration::from_millis(400)).await;
    assert!(
        clients[0].last.as_ref().unwrap().current_trick.is_empty(),
        "must not auto-play a real lead choice"
    );
}

#[tokio::test]
async fn tap_through_plays_immediately() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");
    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let game_id = start_game(&base, &mut clients, 1, 11).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }
    place_all_bids(&mut clients, game_id).await;

    let index = current_index(&clients).expect("leader");
    let card = clients[index]
        .last
        .as_ref()
        .unwrap()
        .legal_actions
        .playable_cards[0];
    clients[index]
        .send(game_id, ClientCommand::PlayCard { card_id: card })
        .await;
    pump_for(&mut clients, Duration::from_millis(250)).await;
    assert_eq!(
        clients[0].last.as_ref().unwrap().current_trick.len(),
        1,
        "tap-through should beat the forced delay"
    );
}

#[tokio::test]
async fn grace_singleton_auto_plays_without_pause_banner() {
    let state =
        bootstrap_with_reconnect_grace(Arc::new(MemoryStore::new()), Duration::from_secs(8))
            .await
            .unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");
    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let game_id = start_game(&base, &mut clients, 1, 11).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }
    place_all_bids(&mut clients, game_id).await;

    let index = current_index(&clients).expect("leader");
    clients[index]
        .ws
        .as_mut()
        .unwrap()
        .close(None)
        .await
        .unwrap();
    clients[index].ws = None;

    let pump = pump_for(&mut clients, FORCED_PLAY_DELAY + Duration::from_millis(500)).await;
    assert!(
        !pump.paused,
        "forced play must not freeze the table: {:?}",
        pump.pause_reason
    );
    let observer = clients.iter().find(|c| c.ws.is_some()).unwrap();
    let view = observer.last.as_ref().unwrap();
    assert_eq!(view.current_trick.len(), 1);
    assert!(view
        .opponents
        .iter()
        .any(|o| { o.connection_status == ConnectionStatus::Disconnected }));
}

#[tokio::test]
async fn vacant_singleton_does_not_auto_play() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");
    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let game_id = start_game(&base, &mut clients, 1, 11).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }
    place_all_bids(&mut clients, game_id).await;

    let index = current_index(&clients).expect("leader");
    clients[index].send(game_id, ClientCommand::LeaveGame).await;
    let pump = pump_for(&mut clients, FORCED_PLAY_DELAY + Duration::from_millis(500)).await;
    assert!(pump.paused, "vacant seat must pause the table");
    let observer = clients
        .iter()
        .find(|c| c.player_id != clients[index].player_id)
        .unwrap();
    let view = observer.last.as_ref().unwrap();
    assert!(
        view.current_trick.is_empty(),
        "must not play for a vacant seat"
    );
    assert!(view
        .opponents
        .iter()
        .any(|o| { o.connection_status == ConnectionStatus::Vacant }));
}

#[tokio::test]
async fn post_trick_forced_lead_waits_for_overlay() {
    let state = bootstrap(Arc::new(MemoryStore::new())).await.unwrap();
    let addr = spawn_with(state).await;
    let base = format!("http://{addr}");
    let mut clients = Vec::new();
    for name in ["A", "B", "C", "D"] {
        clients.push(Client::guest(&base, name).await);
    }
    let game_id = start_game(&base, &mut clients, 2, 11).await;
    for client in &mut clients {
        client.connect_ws(&base, game_id).await;
    }
    place_all_bids(&mut clients, game_id).await;

    // Play the first trick (tap-through when a seat is forced).
    let trick_deadline = tokio::time::Instant::now() + Duration::from_secs(8);
    while tokio::time::Instant::now() < trick_deadline {
        pump_for(&mut clients, Duration::from_millis(30)).await;
        let view = clients[0].last.as_ref().unwrap();
        if view.last_completed_trick.is_some() && view.current_trick.is_empty() {
            break;
        }
        let Some(index) = current_index(&clients) else {
            continue;
        };
        let view = clients[index].last.as_ref().unwrap();
        if view.phase != GamePhase::Playing || view.legal_actions.playable_cards.is_empty() {
            continue;
        }
        if view.legal_actions.playable_cards.len() == 1 {
            continue;
        }
        let card = view.legal_actions.playable_cards[0];
        clients[index]
            .send(game_id, ClientCommand::PlayCard { card_id: card })
            .await;
        pump_for(&mut clients, Duration::from_millis(80)).await;
    }
    let view = clients[0].last.as_ref().unwrap();
    assert!(
        view.last_completed_trick.is_some() && view.current_trick.is_empty(),
        "expected first trick to complete"
    );

    pump_for(&mut clients, Duration::from_millis(900)).await;
    assert!(
        clients[0].last.as_ref().unwrap().current_trick.is_empty(),
        "next forced lead must wait for the trick overlay"
    );
    pump_for(
        &mut clients,
        POST_TRICK_FORCED_DELAY - Duration::from_millis(900) + Duration::from_millis(400),
    )
    .await;
    let view = clients[0].last.as_ref().unwrap();
    assert!(
        !view.current_trick.is_empty()
            || view
                .last_completed_trick
                .as_ref()
                .is_some_and(|t| t.trick_index >= 1 && t.plays.len() == 4),
        "winner's last card should auto-lead after the overlay delay"
    );
}
