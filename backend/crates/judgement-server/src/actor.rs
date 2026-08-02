//! One sequential actor per active game (PLAN.md §9.1, ADR 0001).
//!
//! Phase 5: persist-before-broadcast with rollback.
//! Presence: reconnect grace → vacant seat (claim via room code) or host end.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use judgement_domain::{ActionId, ConnectionStatus, GameError, GameId, PlayerId};
use judgement_engine::{GameEngine, GameEvent, GamePhase};
use judgement_persistence::{GameStore, PersistError};
use judgement_protocol::{
    ClientCommand, ClientEnvelope, RejectReason, ServerMessage, TimerEvent, PROTOCOL_VERSION,
};
use tokio::sync::{mpsc, oneshot};

use crate::emotes::{
    is_allowed_avatar, is_allowed_emoji, is_allowed_mood, resolve_emote_text, MAX_EMOTE_TEXT_LEN,
    REACTION_COOLDOWN_MS,
};
use crate::metrics::Metrics;
use crate::persist::command_commit_from;

pub const COMMAND_QUEUE_CAPACITY: usize = 256;
pub const CLIENT_BUFFER_CAPACITY: usize = 64;
/// Hard bound so a dead DB cannot freeze the actor loop indefinitely.
pub const PERSIST_TIMEOUT: Duration = Duration::from_secs(3);
/// After grace, how long a vacant seat waits for a human claim before auto-end.
pub const VACANCY_TTL: Duration = Duration::from_secs(10 * 60);

/// Pause after the last trick of a round so clients can hold the reveal
/// (~1.6s) before the next deal or game-over screen.
pub const ROUND_REVEAL_DELAY: Duration = Duration::from_millis(1800);

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
    /// Fire after [`ROUND_REVEAL_DELAY`] while phase is `RoundScoring`.
    AdvanceAfterRoundReveal { advance_id: u64 },
    /// Reconnect-grace window expired for a seat.
    GraceExpired {
        player_id: PlayerId,
        grace_id: u64,
    },
    /// Vacant seat waited too long for a claim.
    VacancyExpired {
        player_id: PlayerId,
        vacancy_id: u64,
    },
    /// REST claim: bind a new human identity onto a vacant seat.
    ClaimVacantSeat {
        preferred: Option<PlayerId>,
        nickname: String,
        avatar_id: Option<String>,
        reply: oneshot::Sender<Result<PlayerId, String>>,
    },
    /// Host (or vacancy timeout via internal reason) ends the game.
    EndGame {
        requesting_player_id: Option<PlayerId>,
        reason: String,
        reply: oneshot::Sender<Result<(), String>>,
    },
}

pub struct SpawnActor {
    pub engine: GameEngine,
    pub turn_timeout: Option<Duration>,
    pub reconnect_grace: Duration,
    pub store: Option<Arc<dyn GameStore>>,
    pub processed: HashMap<ActionId, u64>,
    pub host_player_id: PlayerId,
    pub metrics: Arc<Metrics>,
    pub room_code: String,
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
        round_advance_seq: 0,
        grace_seq: 0,
        vacancy_seq: 0,
        turn_timeout: config.turn_timeout,
        reconnect_grace: config.reconnect_grace,
        store: config.store,
        host_player_id: config.host_player_id,
        room_code: config.room_code,
        grace_ids: HashMap::new(),
        vacancy_ids: HashMap::new(),
        dirty_clients: HashSet::new(),
        paused: false,
        ended: false,
        metrics: config.metrics,
        last_emote_at: HashMap::new(),
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
    /// Cancels stale end-of-round reveal timers (same pattern as turn deadlines).
    round_advance_seq: u64,
    grace_seq: u64,
    vacancy_seq: u64,
    turn_timeout: Option<Duration>,
    reconnect_grace: Duration,
    metrics: Arc<Metrics>,
    store: Option<Arc<dyn GameStore>>,
    host_player_id: PlayerId,
    room_code: String,
    /// player → active grace id (stale-id guard, same pattern as turn deadlines).
    grace_ids: HashMap<PlayerId, u64>,
    /// player → active vacancy id.
    vacancy_ids: HashMap<PlayerId, u64>,
    /// Clients whose outbound buffer dropped a snapshot — force resync.
    dirty_clients: HashSet<PlayerId>,
    paused: bool,
    ended: bool,
    /// Rate-limit cosmetic emotes (player → last emit millis).
    last_emote_at: HashMap<PlayerId, u64>,
}

impl GameActor {
    async fn run(mut self) {
        self.schedule_deadline();
        self.schedule_round_reveal_advance();

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
                    self.handle_disconnect(player_id).await;
                }
                ActorMessage::Command { player_id, envelope } => {
                    self.handle_command(player_id, envelope).await;
                }
                ActorMessage::Timeout { deadline_id } => {
                    self.handle_timeout(deadline_id).await;
                }
                ActorMessage::AdvanceAfterRoundReveal { advance_id } => {
                    self.handle_advance_after_round_reveal(advance_id).await;
                }
                ActorMessage::GraceExpired {
                    player_id,
                    grace_id,
                } => {
                    self.handle_grace_expired(player_id, grace_id).await;
                }
                ActorMessage::VacancyExpired {
                    player_id,
                    vacancy_id,
                } => {
                    self.handle_vacancy_expired(player_id, vacancy_id).await;
                }
                ActorMessage::ClaimVacantSeat {
                    preferred,
                    nickname,
                    avatar_id,
                    reply,
                } => {
                    let result = self.handle_claim_vacant(preferred, nickname, avatar_id);
                    let _ = reply.send(result);
                }
                ActorMessage::EndGame {
                    requesting_player_id,
                    reason,
                    reply,
                } => {
                    let result = self
                        .handle_end_game(requesting_player_id, reason)
                        .await;
                    let _ = reply.send(result);
                }
            }
            self.flush_dirty_snapshots();
        }
    }

    fn handle_connect(
        &mut self,
        player_id: PlayerId,
        outbound: mpsc::Sender<ServerMessage>,
        rotated_token: Option<String>,
    ) {
        self.clients.insert(player_id, outbound);
        self.dirty_clients.remove(&player_id);
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
        // Returning from grace restores human control; vacant seats need claim path.
        self.grace_ids.remove(&player_id);
        if previous_status == Some(ConnectionStatus::Vacant) {
            // WS connect alone cannot steal a vacant seat — use claim REST first.
            let _ = self
                .engine
                .set_connection_status(player_id, ConnectionStatus::Vacant);
            self.send_to(
                player_id,
                ServerMessage::CommandRejected {
                    action_id: None,
                    reason: RejectReason::UnsupportedCommand,
                    retryable: false,
                    message: "seat is vacant — claim via room code first".into(),
                },
            );
            self.clients.remove(&player_id);
            return;
        }
        self.vacancy_ids.remove(&player_id);
        self.recompute_pause();
        if matches!(
            previous_status,
            Some(ConnectionStatus::Disconnected | ConnectionStatus::BotControlled)
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
        let others: Vec<_> = self
            .clients
            .keys()
            .copied()
            .filter(|id| *id != player_id)
            .collect();
        for other in others {
            self.send_snapshot(other);
        }
        if was_paused && !self.paused {
            self.broadcast(ServerMessage::GameResumed);
            self.resume_timers();
        }
    }

    async fn handle_disconnect(&mut self, player_id: PlayerId) {
        if self.clients.remove(&player_id).is_none() {
            return;
        }
        self.dirty_clients.remove(&player_id);
        let _ = self
            .engine
            .set_connection_status(player_id, ConnectionStatus::Disconnected);
        self.broadcast(ServerMessage::PlayerDisconnected { player_id });

        // Host migration if the host seat dropped (locked decision 5).
        if player_id == self.host_player_id {
            self.migrate_host();
        }

        // Zero grace ⇒ open seat for claim/replace immediately (no wait).
        if self.reconnect_grace.is_zero() {
            self.mark_seat_vacant(player_id).await;
            return;
        }

        // Start reconnect grace; pause the table while any seat is in grace.
        self.grace_seq += 1;
        let grace_id = self.grace_seq;
        self.grace_ids.insert(player_id, grace_id);
        self.recompute_pause();

        let remaining_ms = self.reconnect_grace.as_millis() as u64;
        let name = self.nickname_of(player_id);
        self.broadcast(ServerMessage::GamePaused {
            reason: format!("Waiting for {name} to reconnect…"),
            remaining_ms,
        });
        self.broadcast_snapshots();

        // Cancel turn / round-reveal timers while paused.
        self.deadline_seq += 1;
        self.round_advance_seq += 1;

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
    }

    async fn handle_grace_expired(&mut self, player_id: PlayerId, grace_id: u64) {
        if self.grace_ids.get(&player_id) != Some(&grace_id) {
            return; // stale — player already reconnected
        }
        self.grace_ids.remove(&player_id);
        self.mark_seat_vacant(player_id).await;
    }

    async fn handle_vacancy_expired(&mut self, player_id: PlayerId, vacancy_id: u64) {
        if self.vacancy_ids.get(&player_id) != Some(&vacancy_id) {
            return;
        }
        let _ = self
            .handle_end_game(None, "vacancy timeout — no replacement joined".into())
            .await;
    }

    async fn mark_seat_vacant(&mut self, player_id: PlayerId) {
        if self.ended || self.engine.is_finished() {
            return;
        }
        let _ = self
            .engine
            .set_connection_status(player_id, ConnectionStatus::Vacant);
        self.metrics
            .seat_vacancies
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        self.broadcast(ServerMessage::SeatVacant {
            player_id,
            room_code: self.room_code.clone(),
        });

        self.vacancy_seq += 1;
        let vacancy_id = self.vacancy_seq;
        self.vacancy_ids.insert(player_id, vacancy_id);
        self.recompute_pause();
        self.deadline_seq += 1;
        self.round_advance_seq += 1;
        let name = self.nickname_of(player_id);
        self.broadcast(ServerMessage::GamePaused {
            reason: format!("{name} left the table — share the room code so someone can take their seat"),
            remaining_ms: VACANCY_TTL.as_millis() as u64,
        });
        self.broadcast_snapshots();

        let tx = self.self_tx.clone();
        tokio::spawn(async move {
            tokio::time::sleep(VACANCY_TTL).await;
            let _ = tx
                .send(ActorMessage::VacancyExpired {
                    player_id,
                    vacancy_id,
                })
                .await;
        });
    }

    fn handle_claim_vacant(
        &mut self,
        preferred: Option<PlayerId>,
        nickname: String,
        avatar_id: Option<String>,
    ) -> Result<PlayerId, String> {
        if self.ended || self.engine.is_finished() {
            return Err("game is over".into());
        }
        let vacant: Vec<PlayerId> = self
            .engine
            .state()
            .players
            .iter()
            .filter(|p| p.connection_status == ConnectionStatus::Vacant)
            .map(|p| p.id)
            .collect();
        let player_id = match preferred {
            Some(id) if vacant.contains(&id) => id,
            Some(_) => return Err("that seat is not vacant".into()),
            None => *vacant.first().ok_or_else(|| "no vacant seats".to_string())?,
        };
        self.engine
            .set_seat_identity(player_id, nickname.clone(), avatar_id)
            .map_err(|e| e.to_string())?;
        self.vacancy_ids.remove(&player_id);
        self.grace_ids.remove(&player_id);
        self.metrics
            .seat_claims
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        self.broadcast(ServerMessage::SeatClaimed {
            player_id,
            nickname,
        });
        let was_paused = self.paused;
        self.recompute_pause();
        self.broadcast_snapshots();
        if was_paused && !self.paused {
            self.broadcast(ServerMessage::GameResumed);
            self.resume_timers();
        }
        Ok(player_id)
    }

    async fn handle_end_game(
        &mut self,
        requesting_player_id: Option<PlayerId>,
        reason: String,
    ) -> Result<(), String> {
        if self.ended || self.engine.is_finished() {
            return Err("game is already over".into());
        }
        if let Some(pid) = requesting_player_id {
            if pid != self.host_player_id {
                return Err("only the host can end the game".into());
            }
            // Host must still be connected (not vacant).
            let host_ok = self.engine.state().players.iter().any(|p| {
                p.id == pid && p.connection_status == ConnectionStatus::Connected
            });
            if !host_ok {
                return Err("host must be connected to end the game".into());
            }
        }
        self.ended = true;
        self.paused = true;
        self.grace_ids.clear();
        self.vacancy_ids.clear();
        self.deadline_seq += 1;
        self.round_advance_seq += 1;
        if let Some(store) = &self.store {
            if let Err(error) = store.abort_game(self.game_id).await {
                tracing::error!(%error, game = %self.game_id, "abort_game failed");
            } else {
                let _ = store.compact_finished_game(self.game_id).await;
            }
        }
        self.metrics
            .games_ended_vacancy
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        self.broadcast(ServerMessage::GameEnded {
            reason,
            aborted: Some(true),
        });
        Ok(())
    }

    fn resume_timers(&mut self) {
        self.schedule_deadline();
        self.schedule_round_reveal_advance();
    }

    fn recompute_pause(&mut self) {
        // Paused while any seat is in reconnect grace or vacant awaiting claim.
        self.paused = !self.grace_ids.is_empty()
            || self
                .engine
                .state()
                .players
                .iter()
                .any(|p| p.connection_status == ConnectionStatus::Vacant);
    }

    fn nickname_of(&self, player_id: PlayerId) -> String {
        self.engine
            .state()
            .players
            .iter()
            .find(|p| p.id == player_id)
            .map(|p| p.nickname.clone())
            .filter(|n| !n.trim().is_empty())
            .unwrap_or_else(|| "A player".into())
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
            // Permanent leave: seat becomes vacant (replace-or-end).
            if self.clients.remove(&player_id).is_some() {
                self.grace_ids.remove(&player_id);
                self.broadcast(ServerMessage::PlayerDisconnected { player_id });
                if player_id == self.host_player_id {
                    self.migrate_host();
                }
                self.mark_seat_vacant(player_id).await;
            }
            return;
        }

        if matches!(envelope.action, ClientCommand::EndGame) {
            match self.handle_end_game(Some(player_id), "host ended the game".into()).await {
                Ok(()) => {
                    self.send_to(
                        player_id,
                        ServerMessage::CommandAccepted {
                            action_id,
                            new_state_version: self.engine.version(),
                        },
                    );
                }
                Err(detail) => {
                    self.reject(
                        player_id,
                        Some(action_id),
                        RejectReason::MalformedMessage { detail },
                    );
                }
            }
            return;
        }

        // Cosmetic engagement: no engine rules, optional rate limit.
        if matches!(
            envelope.action,
            ClientCommand::SendReaction { .. }
                | ClientCommand::SendEmoteText { .. }
                | ClientCommand::AvatarFlash { .. }
        ) {
            self.handle_table_emote(player_id, envelope);
            return;
        }

        if let ClientCommand::SetAvatar { avatar_id } = &envelope.action {
            let avatar_id = avatar_id.clone();
            if !is_allowed_avatar(&avatar_id) {
                self.reject(
                    player_id,
                    Some(action_id),
                    RejectReason::MalformedMessage {
                        detail: "unknown avatar_id".into(),
                    },
                );
                return;
            }
            let previous = self.engine.state().clone();
            if self.engine.set_avatar(player_id, avatar_id).is_err() {
                self.reject(
                    player_id,
                    Some(action_id),
                    RejectReason::Game {
                        error: GameError::PlayerNotInGame,
                    },
                );
                return;
            }
            // Persist snapshot so mid-game avatar survives process restart.
            if !self
                .persist_with_uncertainty(action_id, &[], previous)
                .await
            {
                self.reject(player_id, Some(action_id), RejectReason::PersistUnavailable);
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

        // Reject human commands while the table is paused for grace/vacancy
        // (own reconnect clears pause; vacant seats cannot act).
        if self.engine.state().players.iter().any(|p| {
            p.id == player_id && p.connection_status == ConnectionStatus::Vacant
        }) {
            self.reject(
                player_id,
                Some(action_id),
                RejectReason::MalformedMessage {
                    detail: "seat is vacant".into(),
                },
            );
            return;
        }
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
            ClientCommand::LeaveGame
            | ClientCommand::EndGame
            | ClientCommand::RequestStateSync
            | ClientCommand::SetAvatar { .. }
            | ClientCommand::SendReaction { .. }
            | ClientCommand::SendEmoteText { .. }
            | ClientCommand::AvatarFlash { .. } => unreachable!(),
        };

        match result {
            Ok(events) => {
                if !self
                    .persist_with_uncertainty(action_id, &events, previous)
                    .await
                {
                    self.reject(player_id, Some(action_id), RejectReason::PersistUnavailable);
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
                self.emit_auto_cheers(&events);
                self.after_engine_events(&events);
            }
            Err(error) => {
                self.reject(player_id, Some(action_id), RejectReason::Game { error });
            }
        }
    }

    fn handle_table_emote(&mut self, player_id: PlayerId, envelope: ClientEnvelope) {
        let action_id = envelope.action_id;
        if !self.clients.contains_key(&player_id) {
            return;
        }
        if !self.allow_emote(player_id) {
            self.reject(
                player_id,
                Some(action_id),
                RejectReason::MalformedMessage {
                    detail: "slow down — reactions are rate limited".into(),
                },
            );
            return;
        }

        let event = match envelope.action {
            ClientCommand::SendReaction { emoji, target } => {
                if !is_allowed_emoji(&emoji) {
                    self.reject(
                        player_id,
                        Some(action_id),
                        RejectReason::MalformedMessage {
                            detail: "emoji not allowed".into(),
                        },
                    );
                    return;
                }
                ServerMessage::TableEvent {
                    kind: "reaction".into(),
                    from: player_id,
                    target,
                    emojis: vec![emoji],
                    text: None,
                    mood: None,
                    sticker_id: None,
                    ttl_ms: 1800,
                }
            }
            ClientCommand::SendEmoteText { text } => {
                let trimmed = text.trim();
                if trimmed.is_empty() || trimmed.chars().count() > MAX_EMOTE_TEXT_LEN {
                    self.reject(
                        player_id,
                        Some(action_id),
                        RejectReason::MalformedMessage {
                            detail: format!("emote text must be 1–{MAX_EMOTE_TEXT_LEN} characters"),
                        },
                    );
                    return;
                }
                let style = resolve_emote_text(trimmed);
                ServerMessage::TableEvent {
                    kind: "emote_text".into(),
                    from: player_id,
                    target: None,
                    emojis: style.emojis,
                    text: Some(trimmed.to_string()),
                    mood: Some(style.mood),
                    sticker_id: style.sticker_id,
                    ttl_ms: 2200,
                }
            }
            ClientCommand::AvatarFlash { mood } => {
                if !is_allowed_mood(&mood) {
                    self.reject(
                        player_id,
                        Some(action_id),
                        RejectReason::MalformedMessage {
                            detail: "unknown mood".into(),
                        },
                    );
                    return;
                }
                ServerMessage::TableEvent {
                    kind: "avatar_flash".into(),
                    from: player_id,
                    target: None,
                    emojis: Vec::new(),
                    text: None,
                    mood: Some(mood),
                    sticker_id: None,
                    ttl_ms: 1600,
                }
            }
            _ => unreachable!(),
        };

        self.send_to(
            player_id,
            ServerMessage::CommandAccepted {
                action_id,
                new_state_version: self.engine.version(),
            },
        );
        self.broadcast(event);
    }

    fn allow_emote(&mut self, player_id: PlayerId) -> bool {
        let now = now_ms();
        if let Some(&last) = self.last_emote_at.get(&player_id) {
            if now.saturating_sub(last) < REACTION_COOLDOWN_MS {
                return false;
            }
        }
        self.last_emote_at.insert(player_id, now);
        true
    }

    fn emit_auto_cheers(&mut self, events: &[judgement_engine::GameEvent]) {
        use judgement_engine::GameEvent;
        for event in events {
            match event {
                GameEvent::TrickCompleted { winner, .. } => {
                    self.broadcast(ServerMessage::TableEvent {
                        kind: "auto_cheer".into(),
                        from: *winner,
                        target: None,
                        emojis: vec!["👏".into(), "🔥".into()],
                        text: None,
                        mood: Some("cheer".into()),
                        sticker_id: Some("laugh".into()),
                        ttl_ms: 1600,
                    });
                }
                GameEvent::RoundCompleted { .. } => {
                    let state = self.engine.state();
                    let mut best: Option<(PlayerId, i32)> = None;
                    for p in &state.players {
                        let score = state.score_table.total_score(p.id);
                        best = match best {
                            Some((_, s)) if s >= score => best,
                            _ => Some((p.id, score)),
                        };
                    }
                    if let Some((from, _)) = best {
                        self.broadcast(ServerMessage::TableEvent {
                            kind: "auto_cheer".into(),
                            from,
                            target: None,
                            emojis: vec!["🎯".into(), "✨".into()],
                            text: None,
                            mood: Some("cheer".into()),
                            sticker_id: Some("crown".into()),
                            ttl_ms: 2000,
                        });
                    }
                }
                GameEvent::GameCompleted { ranking } => {
                    if let Some(winner) = ranking.first() {
                        self.broadcast(ServerMessage::TableEvent {
                            kind: "auto_cheer".into(),
                            from: winner.player_id,
                            target: None,
                            emojis: vec!["🙌".into(), "🔥".into(), "✨".into()],
                            text: None,
                            mood: Some("fire".into()),
                            sticker_id: Some("fire".into()),
                            ttl_ms: 2500,
                        });
                    }
                }
                _ => {}
            }
        }
    }

    /// Persist; on failure, only rollback if the action is not already durable.
    async fn persist_with_uncertainty(
        &mut self,
        action_id: ActionId,
        events: &[GameEvent],
        previous: judgement_engine::InternalGameState,
    ) -> bool {
        if Self::persist_accepted(
            &self.store,
            self.game_id,
            action_id,
            events,
            self.engine.state(),
            &self.metrics,
        )
        .await
        {
            return true;
        }
        // Commit-uncertainty: timeout/error may still mean the DB committed.
        if let Some(store) = &self.store {
            match store.action_committed(self.game_id, action_id).await {
                Ok(true) => {
                    tracing::warn!(
                        game = %self.game_id,
                        %action_id,
                        "persist reported failure but action is durable — keeping engine state"
                    );
                    return true;
                }
                Ok(false) => {}
                Err(error) => {
                    tracing::warn!(
                        %error,
                        game = %self.game_id,
                        "action_committed check failed after persist error"
                    );
                }
            }
        }
        self.engine.replace_state(previous);
        false
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
        let started = std::time::Instant::now();
        for attempt in 0..2u8 {
            let result = tokio::time::timeout(PERSIST_TIMEOUT, store.commit_command(&commit)).await;
            let elapsed_ms = started.elapsed().as_millis() as u64;
            match result {
                Ok(Ok(())) => {
                    metrics.observe_persist_ms(elapsed_ms);
                    if started.elapsed() > Duration::from_millis(100) {
                        tracing::warn!(
                            game = %game_id,
                            elapsed_ms,
                            "slow persist commit"
                        );
                    }
                    if events
                        .iter()
                        .any(|e| matches!(e, GameEvent::GameCompleted { .. }))
                    {
                        metrics
                            .games_completed
                            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    }
                    return true;
                }
                Ok(Err(error)) if attempt == 0 && is_transient_persist(&error) => {
                    tracing::warn!(%error, game = %game_id, "persist retry after transient error");
                    continue;
                }
                Ok(Err(error)) => {
                    metrics.observe_persist_ms(elapsed_ms);
                    metrics
                        .db_write_failures
                        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    tracing::error!(%error, game = %game_id, "persist commit failed");
                    return false;
                }
                Err(_elapsed) if attempt == 0 => {
                    tracing::warn!(game = %game_id, "persist timeout — retrying");
                    continue;
                }
                Err(_elapsed) => {
                    metrics.observe_persist_ms(elapsed_ms);
                    metrics
                        .db_write_failures
                        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    tracing::error!(game = %game_id, "persist commit timed out");
                    return false;
                }
            }
        }
        false
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

        // Turn-timer auto-play for a still-connected slow human only.
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
                if !self
                    .persist_with_uncertainty(action_id, &events, previous)
                    .await
                {
                    return;
                }
                self.processed.insert(action_id, self.engine.version());
                self.broadcast_snapshots();
                self.emit_auto_cheers(&events);
                self.after_engine_events(&events);
            }
            Err(error) => tracing::error!(%error, "timeout auto-action rejected"),
        }
    }

    fn after_engine_events(&mut self, events: &[GameEvent]) {
        self.schedule_deadline();
        if events
            .iter()
            .any(|e| matches!(e, GameEvent::RoundCompleted { .. }))
        {
            self.schedule_round_reveal_advance();
        }
        if events
            .iter()
            .any(|e| matches!(e, GameEvent::GameCompleted { .. }))
        {
            if let Some(store) = self.store.clone() {
                let game_id = self.game_id;
                let metrics = self.metrics.clone();
                tokio::spawn(async move {
                    if let Err(error) = store.compact_finished_game(game_id).await {
                        tracing::warn!(%error, game = %game_id, "compact_finished_game failed");
                    } else {
                        metrics
                            .games_compacted
                            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    }
                });
            }
        }
    }

    fn schedule_round_reveal_advance(&mut self) {
        if self.paused || self.engine.phase() != GamePhase::RoundScoring {
            return;
        }
        self.round_advance_seq += 1;
        let advance_id = self.round_advance_seq;
        let tx = self.self_tx.clone();
        tokio::spawn(async move {
            tokio::time::sleep(ROUND_REVEAL_DELAY).await;
            let _ = tx
                .send(ActorMessage::AdvanceAfterRoundReveal { advance_id })
                .await;
        });
    }

    async fn handle_advance_after_round_reveal(&mut self, advance_id: u64) {
        if advance_id != self.round_advance_seq {
            return;
        }
        if self.engine.phase() != GamePhase::RoundScoring {
            return;
        }
        if self.paused {
            // Reveal delay elapsed during pause; restart after resume.
            return;
        }

        let previous = self.engine.state().clone();
        let events = match self.engine.advance_from_round_scoring() {
            Ok(events) => events,
            Err(error) => {
                tracing::error!(%error, "round scoring advance rejected");
                return;
            }
        };
        let action_id = ActionId::new();
        if !self
            .persist_with_uncertainty(action_id, &events, previous)
            .await
        {
            // Retry shortly so a transient DB blip does not stall the table.
            self.schedule_round_reveal_advance();
            return;
        }
        self.processed.insert(action_id, self.engine.version());
        self.broadcast_snapshots();
        self.emit_auto_cheers(&events);
        self.after_engine_events(&events);
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

    fn reject(&mut self, player_id: PlayerId, action_id: Option<ActionId>, reason: RejectReason) {
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

    fn send_snapshot(&mut self, player_id: PlayerId) {
        if let Ok(view) = self.engine.view_for(player_id) {
            self.send_to(player_id, ServerMessage::StateSnapshot { view });
        }
    }

    fn send_timer(&mut self, player_id: PlayerId) {
        if self.engine.is_finished() {
            return;
        }
        if let Some(timer) = self.current_timer_event() {
            self.send_to(player_id, ServerMessage::TimerUpdated { timer });
        }
    }

    fn broadcast_snapshots(&mut self) {
        let players: Vec<_> = self.clients.keys().copied().collect();
        for player_id in players {
            self.send_snapshot(player_id);
        }
    }

    fn flush_dirty_snapshots(&mut self) {
        let dirty: Vec<_> = self.dirty_clients.iter().copied().collect();
        for player_id in dirty {
            if !self.clients.contains_key(&player_id) {
                self.dirty_clients.remove(&player_id);
                continue;
            }
            self.dirty_clients.remove(&player_id);
            self.send_snapshot(player_id);
            self.send_timer(player_id);
        }
    }

    fn broadcast(&mut self, message: ServerMessage) {
        let players: Vec<_> = self.clients.keys().copied().collect();
        for player_id in players {
            self.send_to(player_id, message.clone());
        }
    }

    fn broadcast_except(&mut self, skip: PlayerId, message: ServerMessage) {
        let players: Vec<_> = self.clients.keys().copied().collect();
        for player_id in players {
            if player_id != skip {
                self.send_to(player_id, message.clone());
            }
        }
    }

    fn send_to(&mut self, player_id: PlayerId, message: ServerMessage) {
        let Some(outbound) = self.clients.get(&player_id) else {
            return;
        };
        let is_snapshot = matches!(message, ServerMessage::StateSnapshot { .. });
        if outbound.try_send(message).is_err() {
            if is_snapshot {
                self.dirty_clients.insert(player_id);
                self.metrics
                    .outbound_snapshot_drops
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            }
        } else if is_snapshot {
            self.dirty_clients.remove(&player_id);
        }
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
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
        RejectReason::PersistUnavailable => {
            "database temporarily unavailable; retry shortly".to_string()
        }
        RejectReason::WrongGame => "this connection belongs to a different game".to_string(),
        RejectReason::UnsupportedCommand => {
            "this command is not available on the game socket".to_string()
        }
    }
}

fn is_transient_persist(error: &PersistError) -> bool {
    let msg = error.to_string().to_lowercase();
    msg.contains("eof")
        || msg.contains("connection")
        || msg.contains("broken pipe")
        || msg.contains("pool timed out")
        || msg.contains("pool closed")
        || msg.contains("timed out")
}
