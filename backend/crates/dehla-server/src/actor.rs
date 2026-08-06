//! One sequential actor per active Dehla game (ADR 0001).
//!
//! Presence (ADR 0004): reconnect grace → vacant seat; claim via room code.
//! Persist tip before broadcast (CP).

use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::Duration;

use dehla_domain::PlayerId;
use dehla_engine::{
    apply, project_with_presence, Command, GameState, PresenceOverlay,
};
use dehla_persistence::GameStore;
use dehla_protocol::{ClientCommand, ClientEnvelope, ServerMessage, PROTOCOL_VERSION};
use tokio::sync::{mpsc, oneshot};
use uuid::Uuid;

use crate::metrics::Metrics;

/// Default reconnect grace before a seat becomes vacant (~15s).
pub const RECONNECT_GRACE: Duration = Duration::from_secs(15);
/// Hard bound so a dead DB cannot freeze the actor loop indefinitely.
pub const PERSIST_TIMEOUT: Duration = Duration::from_secs(3);

pub enum ActorMessage {
    Connect {
        player_id: PlayerId,
        outbound: mpsc::Sender<ServerMessage>,
    },
    Disconnect {
        player_id: PlayerId,
    },
    Command {
        player_id: PlayerId,
        envelope: ClientEnvelope,
    },
    /// Reconnect-grace window expired for a seat.
    GraceExpired {
        player_id: PlayerId,
        grace_id: u64,
    },
    /// REST leave while in-game: mark vacant immediately (skip grace).
    LeaveGame {
        player_id: PlayerId,
    },
    /// REST claim: bind a new human identity onto a vacant seat.
    ClaimVacantSeat {
        preferred: Option<PlayerId>,
        nickname: String,
        avatar_id: Option<String>,
        reply: oneshot::Sender<Result<PlayerId, String>>,
    },
    QueryPresence {
        reply: oneshot::Sender<PresenceSnapshot>,
    },
    EndGame {
        requesting_player_id: PlayerId,
        reason: String,
        reply: oneshot::Sender<Result<AbortedCleanup, String>>,
    },
    AbortForRestart {
        requesting_player_id: PlayerId,
        reply: oneshot::Sender<Result<AbortedCleanup, String>>,
    },
    NotifyRestarted {
        new_game_id: dehla_domain::GameId,
    },
}

#[derive(Debug, Clone)]
pub struct PresenceSnapshot {
    pub host_player_id: PlayerId,
    pub vacant_player_ids: Vec<PlayerId>,
    pub seated_count: usize,
    pub ended: bool,
}

#[derive(Debug, Clone)]
pub struct AbortedCleanup {
    pub game_id: dehla_domain::GameId,
    pub host_player_id: PlayerId,
    pub vacant_player_ids: Vec<PlayerId>,
}

pub struct SpawnActor {
    pub state: GameState,
    pub store: Arc<dyn GameStore>,
    pub metrics: Arc<Metrics>,
    pub host_player_id: PlayerId,
}

pub fn spawn_game_actor(spawn: SpawnActor) -> mpsc::Sender<ActorMessage> {
    let (tx, rx) = mpsc::channel(256);
    tokio::spawn(
        GameActor {
            state: spawn.state,
            rx,
            self_tx: tx.clone(),
            clients: HashMap::new(),
            seen_actions: HashMap::new(),
            vacant: HashSet::new(),
            grace_ids: HashMap::new(),
            grace_seq: 0,
            store: spawn.store,
            metrics: spawn.metrics,
            host_player_id: spawn.host_player_id,
            ended: false,
        }
        .run(),
    );
    tx
}

struct GameActor {
    state: GameState,
    rx: mpsc::Receiver<ActorMessage>,
    self_tx: mpsc::Sender<ActorMessage>,
    clients: HashMap<PlayerId, mpsc::Sender<ServerMessage>>,
    seen_actions: HashMap<Uuid, u64>,
    vacant: HashSet<PlayerId>,
    /// player → active grace id (stale-id guard).
    grace_ids: HashMap<PlayerId, u64>,
    grace_seq: u64,
    store: Arc<dyn GameStore>,
    metrics: Arc<Metrics>,
    host_player_id: PlayerId,
    ended: bool,
}

impl GameActor {
    fn presence(&self) -> PresenceOverlay {
        let vacant_seats: Vec<u8> = self
            .state
            .players
            .iter()
            .filter(|p| self.vacant.contains(&p.player_id))
            .map(|p| p.seat)
            .collect();
        let paused = !self.grace_ids.is_empty() || !vacant_seats.is_empty();
        PresenceOverlay {
            paused,
            vacant_seats,
        }
    }

    async fn run(mut self) {
        while let Some(msg) = self.rx.recv().await {
            match msg {
                ActorMessage::Connect {
                    player_id,
                    outbound,
                } => {
                    self.handle_connect(player_id, outbound).await;
                }
                ActorMessage::Disconnect { player_id } => {
                    self.handle_disconnect(player_id).await;
                }
                ActorMessage::GraceExpired {
                    player_id,
                    grace_id,
                } => {
                    self.handle_grace_expired(player_id, grace_id).await;
                }
                ActorMessage::LeaveGame { player_id } => {
                    self.handle_leave_game(player_id).await;
                }
                ActorMessage::ClaimVacantSeat {
                    preferred,
                    nickname,
                    avatar_id,
                    reply,
                } => {
                    let result = self
                        .handle_claim_vacant(preferred, nickname, avatar_id)
                        .await;
                    let _ = reply.send(result);
                }
                ActorMessage::QueryPresence { reply } => {
                    let _ = reply.send(self.presence_snapshot());
                }
                ActorMessage::EndGame {
                    requesting_player_id,
                    reason,
                    reply,
                } => {
                    let result = self.handle_abort(requesting_player_id, reason).await;
                    let _ = reply.send(result);
                }
                ActorMessage::AbortForRestart {
                    requesting_player_id,
                    reply,
                } => {
                    let result = self
                        .handle_abort(requesting_player_id, "host restarted".into())
                        .await;
                    let _ = reply.send(result);
                }
                ActorMessage::NotifyRestarted { new_game_id } => {
                    self.broadcast_raw(ServerMessage::GameRestarted {
                        game_id: new_game_id,
                    })
                    .await;
                }
                ActorMessage::Command {
                    player_id,
                    envelope,
                } => {
                    self.handle_command(player_id, envelope).await;
                }
            }
        }
    }

    fn presence_snapshot(&self) -> PresenceSnapshot {
        PresenceSnapshot {
            host_player_id: self.host_player_id,
            vacant_player_ids: self.vacant.iter().copied().collect(),
            seated_count: self.state.players.len(),
            ended: self.ended,
        }
    }

    async fn handle_abort(
        &mut self,
        requesting_player_id: PlayerId,
        reason: String,
    ) -> Result<AbortedCleanup, String> {
        if self.ended {
            return Err("game is already over".into());
        }
        if requesting_player_id != self.host_player_id {
            return Err("only the host can end or restart the game".into());
        }
        self.ended = true;
        self.grace_ids.clear();
        let vacant_player_ids: Vec<PlayerId> = self.vacant.iter().copied().collect();
        let cleanup = AbortedCleanup {
            game_id: self.state.game_id,
            host_player_id: self.host_player_id,
            vacant_player_ids,
        };
        self.broadcast_raw(ServerMessage::GameEnded {
            reason,
            aborted: true,
        })
        .await;
        Ok(cleanup)
    }

    async fn broadcast_raw(&self, msg: ServerMessage) {
        for tx in self.clients.values() {
            let _ = tx.send(msg.clone()).await;
        }
    }

    async fn handle_connect(
        &mut self,
        player_id: PlayerId,
        outbound: mpsc::Sender<ServerMessage>,
    ) {
        self.clients.insert(player_id, outbound);
        self.grace_ids.remove(&player_id);
        self.vacant.remove(&player_id);
        self.broadcast().await;
    }

    async fn handle_disconnect(&mut self, player_id: PlayerId) {
        if self.clients.remove(&player_id).is_none() {
            return;
        }
        if !self.state.players.iter().any(|p| p.player_id == player_id) {
            return;
        }
        if self.vacant.contains(&player_id) {
            return;
        }

        self.grace_seq += 1;
        let grace_id = self.grace_seq;
        self.grace_ids.insert(player_id, grace_id);
        self.broadcast().await;

        let tx = self.self_tx.clone();
        tokio::spawn(async move {
            tokio::time::sleep(RECONNECT_GRACE).await;
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
            return;
        }
        self.grace_ids.remove(&player_id);
        if self.clients.contains_key(&player_id) {
            return;
        }
        self.vacant.insert(player_id);
        if !self.persist_tip().await {
            self.vacant.remove(&player_id);
            self.grace_ids.insert(player_id, grace_id);
            tracing::error!(
                game = %self.state.game_id,
                "tip save failed marking vacant — keeping grace"
            );
            return;
        }
        self.broadcast().await;
    }

    async fn handle_leave_game(&mut self, player_id: PlayerId) {
        self.clients.remove(&player_id);
        self.grace_ids.remove(&player_id);
        if !self.state.players.iter().any(|p| p.player_id == player_id) {
            return;
        }
        self.vacant.insert(player_id);
        if !self.persist_tip().await {
            self.vacant.remove(&player_id);
            tracing::error!(
                game = %self.state.game_id,
                "tip save failed on LeaveGame — not marking vacant"
            );
            return;
        }
        self.broadcast().await;
    }

    async fn handle_claim_vacant(
        &mut self,
        preferred: Option<PlayerId>,
        nickname: String,
        avatar_id: Option<String>,
    ) -> Result<PlayerId, String> {
        let vacant_players: Vec<_> = self
            .state
            .players
            .iter()
            .filter(|p| self.vacant.contains(&p.player_id))
            .cloned()
            .collect();
        let vacant_ids: Vec<PlayerId> = vacant_players.iter().map(|p| p.player_id).collect();
        let player_id = match preferred {
            Some(id) if vacant_ids.contains(&id) => id,
            Some(_) => return Err("SEAT_NOT_VACANT: that seat is not vacant".into()),
            None => {
                let nick = nickname.trim().to_ascii_lowercase();
                let nick_matches: Vec<PlayerId> = vacant_players
                    .iter()
                    .filter(|p| p.nickname.trim().to_ascii_lowercase() == nick)
                    .map(|p| p.player_id)
                    .collect();
                if nick_matches.len() == 1 {
                    nick_matches[0]
                } else {
                    *vacant_ids
                        .first()
                        .ok_or_else(|| "no vacant seats".to_string())?
                }
            }
        };

        let previous = self
            .state
            .players
            .iter()
            .find(|p| p.player_id == player_id)
            .map(|p| (p.nickname.clone(), p.avatar_id.clone()));

        if let Some(p) = self
            .state
            .players
            .iter_mut()
            .find(|p| p.player_id == player_id)
        {
            p.nickname = nickname;
            p.avatar_id = avatar_id;
        }
        self.vacant.remove(&player_id);
        self.grace_ids.remove(&player_id);
        self.state.state_version += 1;

        if !self.persist_tip().await {
            self.vacant.insert(player_id);
            if let Some((nick, avatar)) = previous {
                if let Some(p) = self
                    .state
                    .players
                    .iter_mut()
                    .find(|p| p.player_id == player_id)
                {
                    p.nickname = nick;
                    p.avatar_id = avatar;
                }
            }
            self.state.state_version = self.state.state_version.saturating_sub(1);
            return Err("persist unavailable".into());
        }
        self.broadcast().await;
        Ok(player_id)
    }

    async fn handle_command(&mut self, player_id: PlayerId, envelope: ClientEnvelope) {
        if self.ended {
            self.reject(player_id, "game is over", false).await;
            return;
        }
        if envelope.protocol_version != PROTOCOL_VERSION {
            self.reject(player_id, "unsupported protocol version", false)
                .await;
            return;
        }
        if envelope.game_id != self.state.game_id {
            self.reject(player_id, "wrong game_id", false).await;
            return;
        }
        if let Some(v) = self.seen_actions.get(&envelope.action_id) {
            if *v == self.state.state_version || *v < self.state.state_version {
                self.send_snapshot(player_id).await;
                return;
            }
        }
        if envelope.expected_state_version != self.state.state_version {
            self.reject(player_id, "stale state_version", true).await;
            self.send_snapshot(player_id).await;
            return;
        }

        let presence = self.presence();
        if presence.paused {
            match &envelope.action {
                ClientCommand::RequestStateSync => {
                    self.send_snapshot(player_id).await;
                    return;
                }
                _ => {
                    self.reject(
                        player_id,
                        "table paused — waiting for vacant seat to be reclaimed",
                        true,
                    )
                    .await;
                    self.send_snapshot(player_id).await;
                    return;
                }
            }
        }

        match envelope.action {
            ClientCommand::RequestStateSync => {
                self.send_snapshot(player_id).await;
            }
            ClientCommand::AnnounceTrump { suit } => {
                self.apply_cmd(player_id, envelope.action_id, &Command::AnnounceTrump { suit })
                    .await;
            }
            ClientCommand::PlayCard { card } => {
                self.apply_cmd(player_id, envelope.action_id, &Command::PlayCard { card })
                    .await;
            }
            ClientCommand::StartNextHand => {
                self.apply_cmd(player_id, envelope.action_id, &Command::StartNextHand)
                    .await;
            }
            ClientCommand::Rematch => {
                self.apply_cmd(player_id, envelope.action_id, &Command::Rematch)
                    .await;
            }
        }
    }

    async fn apply_cmd(&mut self, player_id: PlayerId, action_id: Uuid, cmd: &Command) {
        match apply(&self.state, player_id, cmd) {
            Ok(next) => {
                let previous = self.state.clone();
                self.state = next;
                if !self.persist_tip().await {
                    self.state = previous;
                    self.reject(player_id, "persist unavailable", true).await;
                    return;
                }
                self.seen_actions.insert(action_id, self.state.state_version);
                self.broadcast().await;
            }
            Err(e) => self.reject(player_id, e.to_string(), false).await,
        }
    }

    async fn persist_tip(&self) -> bool {
        let game_id = self.state.game_id;
        let store = self.store.clone();
        let state = self.state.clone();
        let result = tokio::time::timeout(PERSIST_TIMEOUT, store.save_tip(game_id, &state)).await;
        match result {
            Ok(Ok(())) => {
                self.metrics
                    .tips_saved
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                true
            }
            Ok(Err(error)) => {
                tracing::error!(%error, game = %game_id, "save_tip failed");
                false
            }
            Err(_) => {
                tracing::error!(game = %game_id, "save_tip timed out");
                false
            }
        }
    }

    async fn broadcast(&self) {
        for pid in self.clients.keys().copied().collect::<Vec<_>>() {
            self.send_snapshot(pid).await;
        }
    }

    async fn send_snapshot(&self, player_id: PlayerId) {
        let presence = self.presence();
        let Some(view) = project_with_presence(&self.state, player_id, &presence) else {
            return;
        };
        let Some(tx) = self.clients.get(&player_id) else {
            return;
        };
        let _ = tx.send(ServerMessage::StateSnapshot { view }).await;
    }

    async fn reject(&self, player_id: PlayerId, reason: impl Into<String>, retryable: bool) {
        if let Some(tx) = self.clients.get(&player_id) {
            let _ = tx
                .send(ServerMessage::Reject {
                    reason: reason.into(),
                    retryable,
                })
                .await;
        }
    }
}
