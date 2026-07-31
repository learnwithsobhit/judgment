//! One sequential actor per active game (PLAN.md §9.1, ADR 0001).
//!
//! Phase 5: persist-before-broadcast with rollback.
//! Phase 6: presence, pause/grace, bot takeover, host migration hooks.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use judgement_bot::{BotStrategy, RuleBasedBot};
use judgement_domain::{ActionId, CardId, ConnectionStatus, GameError, GameId, PlayerId};
use judgement_engine::{GameEngine, GameEvent, GamePhase};
use judgement_persistence::GameStore;
use judgement_protocol::{
    ClientCommand, ClientEnvelope, RejectReason, ServerMessage, TimerEvent, PROTOCOL_VERSION,
};
use tokio::sync::mpsc;

use crate::metrics::Metrics;
use crate::persist::command_commit_from;

pub const COMMAND_QUEUE_CAPACITY: usize = 256;
pub const CLIENT_BUFFER_CAPACITY: usize = 64;

#[derive(Debug)]
pub enum ActorMessage {
    Connect {
        player_id: PlayerId,
        outbound: mpsc::Sender<ServerMessage>,
        /// Optional rotated token to push to the client (Phase 6 §15.1).
        rotated_token: Option<String>,
    },
    Disconnect {
        player_id: PlayerId,
    },
    Command {
        player_id: PlayerId,
        envelope: ClientEnvelope,
    },
    Timeout { deadline_id: u64 },
    /// Reconnect-grace window expired for a seat (PLAN.md §15).
    GraceExpired {
        player_id: PlayerId,
        grace_id: u64,
    },
    /// Bot decision computed off-actor; applied through normal validation.
    BotAction {
        player_id: PlayerId,
        action: BotActionKind,
    },
}

#[derive(Debug, Clone)]
pub enum BotActionKind {
    Bid(u8),
    Card(CardId),
}

pub struct SpawnActor {
    pub engine: GameEngine,
    pub turn_timeout: Option<Duration>,
    pub reconnect_grace: Duration,
    pub store: Option<Arc<dyn GameStore>>,
    pub processed: HashMap<ActionId, u64>,
    pub host_player_id: PlayerId,
    pub metrics: Arc<Metrics>,
}

pub fn spawn_game_actor(config: SpawnActor) -> mpsc::Sender<ActorMessage> {
    let (tx, rx) = mpsc::channel(COMMAND_QUEUE_CAPACITY);
    let game_id = config.engine.state().game_id;
    let actor = GameActor {
        game_id,
        engine: config.engine,
        rx,
        self_tx: tx.clone(),
        clients: HashMap::new(),
        processed: config.processed,
        deadline_seq: 0,
        grace_seq: 0,
        turn_timeout: config.turn_timeout,
        reconnect_grace: config.reconnect_grace,
        store: config.store,
        host_player_id: config.host_player_id,
        grace_ids: HashMap::new(),
        paused: false,
        metrics: config.metrics,
    };
    tokio::spawn(actor.run());
    tx
}

struct GameActor {
    game_id: GameId,
    engine: GameEngine,
    rx: mpsc::Receiver<ActorMessage>,
    self_tx: mpsc::Sender<ActorMessage>,
    clients: HashMap<PlayerId, mpsc::Sender<ServerMessage>>,
    processed: HashMap<ActionId, u64>,
    deadline_seq: u64,
    grace_seq: u64,
    turn_timeout: Option<Duration>,
    reconnect_grace: Duration,
    metrics: Arc<Metrics>,
    store: Option<Arc<dyn GameStore>>,
    host_player_id: PlayerId,
    /// player → active grace id (stale-id guard, same pattern as turn deadlines).
    grace_ids: HashMap<PlayerId, u64>,
    paused: bool,
}

impl GameActor {
    async fn run(mut self) {
        self.schedule_deadline();
        self.maybe_request_bot_turn();

        while let Some(message) = self.rx.recv().await {
            match message {
                ActorMessage::Connect {
                    player_id,
                    outbound,
                    rotated_token,
                } => {
                    self.handle_connect(player_id, outbound, rotated_token);
                }
                ActorMessage::Disconnect { player_id } => {
                    self.handle_disconnect(player_id);
                }
                ActorMessage::Command { player_id, envelope } => {
                    self.handle_command(player_id, envelope).await;
                }
                ActorMessage::Timeout { deadline_id } => {
                    self.handle_timeout(deadline_id).await;
                }
                ActorMessage::GraceExpired {
                    player_id,
                    grace_id,
                } => {
                    self.handle_grace_expired(player_id, grace_id).await;
                }
                ActorMessage::BotAction { player_id, action } => {
                    self.handle_bot_action(player_id, action).await;
                }
            }
        }
    }

    fn handle_connect(
        &mut self,
        player_id: PlayerId,
        outbound: mpsc::Sender<ServerMessage>,
        rotated_token: Option<String>,
    ) {
        self.clients.insert(player_id, outbound);
        let previous_status = self
            .engine
            .state()
            .players
            .iter()
            .find(|p| p.id == player_id)
            .map(|p| p.connection_status);
        let _ = self
            .engine
            .set_connection_status(player_id, ConnectionStatus::Connected);

        let was_paused = self.paused;
        // Returning from grace or bot control restores human control at a safe
        // boundary (actor is idle between messages — PLAN.md §15).
        self.grace_ids.remove(&player_id);
        self.recompute_pause();
        if matches!(
            previous_status,
            Some(ConnectionStatus::BotControlled | ConnectionStatus::Disconnected)
        ) {
            self.metrics
                .reconnects
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            self.broadcast(ServerMessage::PlayerResumedControl { player_id });
        }

        self.broadcast_except(player_id, ServerMessage::PlayerConnected { player_id });
        if let Some(token) = rotated_token {
            self.send_to(player_id, ServerMessage::TokenRotated { token });
        }
        self.send_snapshot(player_id);
        self.send_timer(player_id);
        // Others need an updated connection_status projection.
        for &other in self.clients.keys() {
            if other != player_id {
                self.send_snapshot(other);
            }
        }
        if was_paused && !self.paused {
            self.broadcast(ServerMessage::GameResumed);
            self.schedule_deadline();
            self.maybe_request_bot_turn();
        }
    }

    fn handle_disconnect(&mut self, player_id: PlayerId) {
        if self.clients.remove(&player_id).is_none() {
            return;
        }
        let _ = self
            .engine
            .set_connection_status(player_id, ConnectionStatus::Disconnected);
        self.broadcast(ServerMessage::PlayerDisconnected { player_id });

        // Start reconnect grace; pause the table while any seat is in grace.
        self.grace_seq += 1;
        let grace_id = self.grace_seq;
        self.grace_ids.insert(player_id, grace_id);
        self.recompute_pause();

        let remaining_ms = self.reconnect_grace.as_millis() as u64;
        self.broadcast(ServerMessage::GamePaused {
            reason: format!("{player_id} disconnected — reconnect grace"),
            remaining_ms,
        });
        self.broadcast_snapshots();

        // Cancel turn deadlines while paused.
        self.deadline_seq += 1;

        let tx = self.self_tx.clone();
        let grace = self.reconnect_grace;
        tokio::spawn(async move {
            tokio::time::sleep(grace).await;
            let _ = tx
                .send(ActorMessage::GraceExpired {
                    player_id,
                    grace_id,
                })
                .await;
        });

        // Host migration if the host seat dropped (locked decision 5).
        if player_id == self.host_player_id {
            self.migrate_host();
        }
    }

    async fn handle_grace_expired(&mut self, player_id: PlayerId, grace_id: u64) {
        if self.grace_ids.get(&player_id) != Some(&grace_id) {
            return; // stale — player already reconnected
        }
        self.grace_ids.remove(&player_id);
        let _ = self
            .engine
            .set_connection_status(player_id, ConnectionStatus::BotControlled);
        self.metrics
            .bot_takeovers
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        self.broadcast(ServerMessage::BotTookOver { player_id });
        self.recompute_pause();
        self.broadcast_snapshots();
        if !self.paused {
            self.broadcast(ServerMessage::GameResumed);
            self.schedule_deadline();
            self.maybe_request_bot_turn();
        }
    }

    fn recompute_pause(&mut self) {
        // Paused while any seated human is within the grace window
        // (disconnected, not yet bot-controlled).
        self.paused = !self.grace_ids.is_empty();
    }

    fn migrate_host(&mut self) {
        // Longest-connected occupied seat: prefer Connected humans, then any
        // remaining seated player (including bot-controlled).
        let candidates: Vec<_> = self
            .engine
            .state()
            .players
            .iter()
            .filter(|p| p.id != self.host_player_id)
            .collect();
        let next = candidates
            .iter()
            .find(|p| p.connection_status == ConnectionStatus::Connected)
            .or_else(|| candidates.first())
            .map(|p| p.id);
        if let Some(new_host) = next {
            self.host_player_id = new_host;
            self.broadcast(ServerMessage::HostChanged { new_host });
        }
    }

    async fn handle_command(&mut self, player_id: PlayerId, envelope: ClientEnvelope) {
        let action_id = envelope.action_id;

        if envelope.protocol_version != PROTOCOL_VERSION {
            self.reject(
                player_id,
                Some(action_id),
                RejectReason::UnsupportedProtocolVersion {
                    supported: PROTOCOL_VERSION,
                    received: envelope.protocol_version,
                },
            );
            return;
        }

        if matches!(envelope.action, ClientCommand::RequestStateSync) {
            self.send_snapshot(player_id);
            self.send_timer(player_id);
            return;
        }

        if matches!(envelope.action, ClientCommand::LeaveGame) {
            // Permanent leave: immediate bot takeover (PLAN.md §15).
            if self.clients.remove(&player_id).is_some() {
                self.grace_ids.remove(&player_id);
                let _ = self
                    .engine
                    .set_connection_status(player_id, ConnectionStatus::BotControlled);
                self.broadcast(ServerMessage::PlayerDisconnected { player_id });
                self.metrics
                    .bot_takeovers
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                self.broadcast(ServerMessage::BotTookOver { player_id });
                if player_id == self.host_player_id {
                    self.migrate_host();
                }
                self.recompute_pause();
                self.broadcast_snapshots();
                if !self.paused {
                    self.schedule_deadline();
                    self.maybe_request_bot_turn();
                }
            }
            return;
        }

        if let Some(&version) = self.processed.get(&action_id) {
            self.send_to(
                player_id,
                ServerMessage::CommandAccepted {
                    action_id,
                    new_state_version: version,
                },
            );
            self.send_snapshot(player_id);
            return;
        }

        // Reject human commands while the seat is bot-controlled or the table
        // is paused for someone else's grace window (own reconnect clears pause).
        if self.paused && !self.grace_ids.contains_key(&player_id) {
            self.reject(
                player_id,
                Some(action_id),
                RejectReason::Game {
                    error: GameError::WrongPhase,
                },
            );
            return;
        }
        if self.engine.state().players.iter().any(|p| {
            p.id == player_id && p.connection_status == ConnectionStatus::BotControlled
        }) {
            self.reject(
                player_id,
                Some(action_id),
                RejectReason::Game {
                    error: GameError::WrongPhase,
                },
            );
            return;
        }

        let current_version = self.engine.version();
        if envelope.expected_state_version != current_version {
            self.reject(
                player_id,
                Some(action_id),
                RejectReason::Game {
                    error: GameError::StaleState {
                        expected_version: envelope.expected_state_version,
                        actual_version: current_version,
                    },
                },
            );
            self.send_snapshot(player_id);
            return;
        }

        let previous = self.engine.state().clone();
        let result = match &envelope.action {
            ClientCommand::PlaceBid { bid } => self.engine.place_bid(player_id, *bid),
            ClientCommand::PlayCard { card_id } => self.engine.play_card(player_id, *card_id),
            ClientCommand::Ready | ClientCommand::Unready | ClientCommand::StartGame => {
                self.reject(player_id, Some(action_id), RejectReason::UnsupportedCommand);
                return;
            }
            ClientCommand::LeaveGame | ClientCommand::RequestStateSync => unreachable!(),
        };

        match result {
            Ok(events) => {
                if !Self::persist_accepted(
                    &self.store,
                    self.game_id,
                    action_id,
                    &events,
                    self.engine.state(),
                    &self.metrics,
                )
                .await
                {
                    self.engine.replace_state(previous);
                    self.reject(player_id, Some(action_id), RejectReason::QueueFull);
                    return;
                }
                let new_state_version = self.engine.version();
                self.processed.insert(action_id, new_state_version);
                self.send_to(
                    player_id,
                    ServerMessage::CommandAccepted {
                        action_id,
                        new_state_version,
                    },
                );
                self.broadcast_snapshots();
                self.schedule_deadline();
                self.maybe_request_bot_turn();
            }
            Err(error) => {
                self.reject(player_id, Some(action_id), RejectReason::Game { error });
            }
        }
    }

    async fn persist_accepted(
        store: &Option<Arc<dyn GameStore>>,
        game_id: GameId,
        action_id: ActionId,
        events: &[GameEvent],
        state: &judgement_engine::InternalGameState,
        metrics: &Metrics,
    ) -> bool {
        let Some(store) = store.clone() else {
            if events
                .iter()
                .any(|e| matches!(e, GameEvent::GameCompleted { .. }))
            {
                metrics
                    .games_completed
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            }
            return true;
        };
        let commit = command_commit_from(game_id, action_id, events, state);
        match store.commit_command(&commit).await {
            Ok(()) => {
                if events
                    .iter()
                    .any(|e| matches!(e, GameEvent::GameCompleted { .. }))
                {
                    metrics
                        .games_completed
                        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                }
                true
            }
            Err(error) => {
                metrics
                    .db_write_failures
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                tracing::error!(%error, game = %game_id, "persist commit failed");
                false
            }
        }
    }

    fn schedule_deadline(&mut self) {
        self.deadline_seq += 1;
        if self.paused {
            return;
        }
        let Some(timeout) = self.turn_timeout else {
            return;
        };
        if self.engine.is_finished()
            || !matches!(
                self.engine.phase(),
                GamePhase::Bidding | GamePhase::Playing
            )
        {
            return;
        }

        let deadline_id = self.deadline_seq;
        let tx = self.self_tx.clone();
        tokio::spawn(async move {
            tokio::time::sleep(timeout).await;
            let _ = tx.send(ActorMessage::Timeout { deadline_id }).await;
        });
        if let Some(timer) = self.current_timer_event() {
            self.broadcast(ServerMessage::TimerUpdated { timer });
        }
    }

    async fn handle_timeout(&mut self, deadline_id: u64) {
        if deadline_id != self.deadline_seq || self.engine.is_finished() || self.paused {
            return;
        }
        let Some(current) = self
            .engine
            .state()
            .current_round
            .as_ref()
            .map(|r| r.current_turn)
        else {
            return;
        };

        // Prefer the bot strategy for bot-controlled seats; otherwise lowest legal.
        let is_bot = self.engine.state().players.iter().any(|p| {
            p.id == current && p.connection_status == ConnectionStatus::BotControlled
        });
        if is_bot {
            self.maybe_request_bot_turn();
            return;
        }

        let previous = self.engine.state().clone();
        let result = match self.engine.phase() {
            GamePhase::Bidding => {
                let bid = *self.engine.legal_bids(current).first().expect("legal bid");
                self.engine.place_bid(current, bid)
            }
            GamePhase::Playing => {
                let card = *self
                    .engine
                    .legal_cards(current)
                    .iter()
                    .min_by_key(|c| c.rank)
                    .expect("legal card");
                self.engine.play_card(current, card)
            }
            _ => return,
        };
        match result {
            Ok(events) => {
                let action_id = ActionId::new();
                if !Self::persist_accepted(
                    &self.store,
                    self.game_id,
                    action_id,
                    &events,
                    self.engine.state(),
                    &self.metrics,
                )
                .await
                {
                    self.engine.replace_state(previous);
                    return;
                }
                self.processed.insert(action_id, self.engine.version());
                self.broadcast_snapshots();
                self.schedule_deadline();
                self.maybe_request_bot_turn();
            }
            Err(error) => tracing::error!(%error, "timeout auto-action rejected"),
        }
    }

    fn maybe_request_bot_turn(&self) {
        if self.paused || self.engine.is_finished() {
            return;
        }
        let Some(current) = self
            .engine
            .state()
            .current_round
            .as_ref()
            .map(|r| r.current_turn)
        else {
            return;
        };
        let bot_seat = self.engine.state().players.iter().any(|p| {
            p.id == current && p.connection_status == ConnectionStatus::BotControlled
        });
        if !bot_seat {
            return;
        }
        let Ok(view) = self.engine.view_for(current) else {
            return;
        };
        let phase = self.engine.phase();
        let tx = self.self_tx.clone();
        tokio::spawn(async move {
            let mut bot = RuleBasedBot;
            let action = match phase {
                GamePhase::Bidding => bot.choose_bid(&view).ok().map(BotActionKind::Bid),
                GamePhase::Playing => bot.choose_card(&view).ok().map(BotActionKind::Card),
                _ => None,
            };
            if let Some(action) = action {
                let _ = tx
                    .send(ActorMessage::BotAction {
                        player_id: current,
                        action,
                    })
                    .await;
            }
        });
    }

    async fn handle_bot_action(&mut self, player_id: PlayerId, action: BotActionKind) {
        if self.paused || self.engine.is_finished() {
            return;
        }
        let still_bot = self.engine.state().players.iter().any(|p| {
            p.id == player_id && p.connection_status == ConnectionStatus::BotControlled
        });
        if !still_bot {
            return;
        }
        let Some(current) = self
            .engine
            .state()
            .current_round
            .as_ref()
            .map(|r| r.current_turn)
        else {
            return;
        };
        if current != player_id {
            return;
        }

        let previous = self.engine.state().clone();
        let result = match action {
            BotActionKind::Bid(bid) => self.engine.place_bid(player_id, bid),
            BotActionKind::Card(card_id) => self.engine.play_card(player_id, card_id),
        };
        match result {
            Ok(events) => {
                let action_id = ActionId::new();
                if !Self::persist_accepted(
                    &self.store,
                    self.game_id,
                    action_id,
                    &events,
                    self.engine.state(),
                    &self.metrics,
                )
                .await
                {
                    self.engine.replace_state(previous);
                    return;
                }
                self.processed.insert(action_id, self.engine.version());
                tracing::info!(player = %player_id, "bot action applied");
                self.broadcast_snapshots();
                self.schedule_deadline();
                self.maybe_request_bot_turn();
            }
            Err(error) => tracing::error!(%error, "bot action rejected"),
        }
    }

    fn current_timer_event(&self) -> Option<TimerEvent> {
        if self.paused {
            return None;
        }
        let timeout = self.turn_timeout?;
        Some(TimerEvent {
            deadline_id: self.deadline_seq,
            remaining_ms: timeout.as_millis() as u64,
            server_now_ms: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
        })
    }

    fn reject(&self, player_id: PlayerId, action_id: Option<ActionId>, reason: RejectReason) {
        self.metrics
            .invalid_actions
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let retryable = reason.retryable();
        let message = reject_message(&reason);
        self.send_to(
            player_id,
            ServerMessage::CommandRejected {
                action_id,
                reason,
                retryable,
                message,
            },
        );
    }

    fn send_snapshot(&self, player_id: PlayerId) {
        if let Ok(view) = self.engine.view_for(player_id) {
            self.send_to(player_id, ServerMessage::StateSnapshot { view });
        }
    }

    fn send_timer(&self, player_id: PlayerId) {
        if self.engine.is_finished() {
            return;
        }
        if let Some(timer) = self.current_timer_event() {
            self.send_to(player_id, ServerMessage::TimerUpdated { timer });
        }
    }

    fn broadcast_snapshots(&self) {
        for &player_id in self.clients.keys() {
            self.send_snapshot(player_id);
        }
    }

    fn broadcast(&self, message: ServerMessage) {
        for outbound in self.clients.values() {
            let _ = outbound.try_send(message.clone());
        }
    }

    fn broadcast_except(&self, skip: PlayerId, message: ServerMessage) {
        for (player_id, outbound) in &self.clients {
            if *player_id != skip {
                let _ = outbound.try_send(message.clone());
            }
        }
    }

    fn send_to(&self, player_id: PlayerId, message: ServerMessage) {
        if let Some(outbound) = self.clients.get(&player_id) {
            let _ = outbound.try_send(message);
        }
    }
}

fn reject_message(reason: &RejectReason) -> String {
    match reason {
        RejectReason::Game { error } => error.to_string(),
        RejectReason::UnsupportedProtocolVersion { supported, received } => {
            format!("protocol version {received} is not supported (server speaks {supported})")
        }
        RejectReason::MalformedMessage { detail } => format!("malformed message: {detail}"),
        RejectReason::MessageTooLarge => "message exceeds the maximum size".to_string(),
        RejectReason::QueueFull => "server is busy; retry shortly".to_string(),
        RejectReason::WrongGame => "this connection belongs to a different game".to_string(),
        RejectReason::UnsupportedCommand => {
            "this command is not available on the game socket".to_string()
        }
    }
}
