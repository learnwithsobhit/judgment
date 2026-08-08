//! WebSocket endpoint for live gameplay (PLAN.md §13.2, Phase 6 reconnect).

use std::sync::Arc;
use std::time::Duration;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Path, Query, State};
use axum::response::Response;
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio::sync::mpsc;
use tokio::time::Instant;

use judgement_domain::{GameId, PlayerId, SessionId};
use judgement_protocol::{ClientEnvelope, RejectReason, ServerMessage};

use crate::actor::{ActorMessage, CLIENT_BUFFER_CAPACITY};
use crate::audience::{admit_spectator, flags as audience_flags, SPECTATOR_BUFFER_CAPACITY};
use crate::error::ApiError;
use crate::persist::stored_session;
use crate::state::AppState;

pub const MAX_WS_MESSAGE_BYTES: usize = 64 * 1024;
pub const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(15);
pub const LIVENESS_TIMEOUT: Duration = Duration::from_secs(45);

#[derive(Debug, Deserialize)]
pub struct WsQuery {
    token: String,
}

pub async fn game_ws(
    State(state): State<Arc<AppState>>,
    Path(game_id): Path<uuid::Uuid>,
    Query(query): Query<WsQuery>,
    ws: WebSocketUpgrade,
) -> Result<Response, ApiError> {
    let session = state
        .session_for_token(&query.token)
        .ok_or(ApiError::Unauthorized)?;
    let game_id = GameId(game_id);

    let (commands, player_id) = {
        let games = state.games.lock().unwrap();
        let info = games.get(&game_id).ok_or(ApiError::NotFound("game"))?;
        let player_id = *info
            .players
            .get(&session.id)
            .ok_or_else(|| ApiError::Forbidden("you are not a player in this game".into()))?;
        (info.commands.clone(), player_id)
    };

    // Rotate the reconnect token on every successful WS upgrade (§15.1).
    let rotated_token = state.rotate_token(session.id);
    if let Some(ref token) = rotated_token {
        if let Some(updated) = state.session_for_token(token) {
            let _ = state.store.upsert_session(&stored_session(&updated)).await;
        }
    }

    state
        .metrics
        .ws_connected
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    state
        .active_websockets
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    let state_for_socket = state.clone();
    Ok(ws
        .max_message_size(MAX_WS_MESSAGE_BYTES)
        .on_upgrade(move |socket| {
            handle_socket(
                socket,
                commands,
                player_id,
                game_id,
                rotated_token,
                state_for_socket,
            )
        }))
}

async fn handle_socket(
    socket: WebSocket,
    commands: mpsc::Sender<ActorMessage>,
    player_id: PlayerId,
    game_id: GameId,
    rotated_token: Option<String>,
    state: Arc<AppState>,
) {
    let (outbound_tx, mut outbound_rx) = mpsc::channel::<ServerMessage>(CLIENT_BUFFER_CAPACITY);

    if commands
        .send(ActorMessage::Connect {
            player_id,
            outbound: outbound_tx.clone(),
            rotated_token,
        })
        .await
        .is_err()
    {
        return;
    }

    let (mut ws_tx, mut ws_rx) = socket.split();

    let writer = tokio::spawn(async move {
        let mut heartbeat = tokio::time::interval(HEARTBEAT_INTERVAL);
        loop {
            tokio::select! {
                message = outbound_rx.recv() => {
                    let Some(message) = message else { break };
                    let Ok(text) = serde_json::to_string(&message) else { break };
                    if ws_tx.send(Message::Text(text.into())).await.is_err() {
                        break;
                    }
                }
                _ = heartbeat.tick() => {
                    if ws_tx.send(Message::Ping(Vec::new().into())).await.is_err() {
                        break;
                    }
                }
            }
        }
    });

    let mut last_seen = Instant::now();
    loop {
        let frame = tokio::time::timeout(LIVENESS_TIMEOUT, ws_rx.next()).await;
        let message = match frame {
            Err(_elapsed) => {
                if last_seen.elapsed() > LIVENESS_TIMEOUT {
                    tracing::debug!(%player_id, "closing websocket: liveness timeout");
                    break;
                }
                continue;
            }
            Ok(None) => break,
            Ok(Some(Err(error))) => {
                if error.to_string().to_lowercase().contains("capacity") {
                    send_rejection(&outbound_tx, None, RejectReason::MessageTooLarge);
                }
                break;
            }
            Ok(Some(Ok(message))) => message,
        };
        last_seen = Instant::now();

        match message {
            Message::Text(text) => {
                let envelope: ClientEnvelope = match serde_json::from_str(&text) {
                    Ok(envelope) => envelope,
                    Err(error) => {
                        send_rejection(
                            &outbound_tx,
                            None,
                            RejectReason::MalformedMessage {
                                detail: error.to_string(),
                            },
                        );
                        continue;
                    }
                };
                if envelope.game_id != game_id {
                    send_rejection(&outbound_tx, Some(envelope.action_id), RejectReason::WrongGame);
                    continue;
                }
                let action_id = envelope.action_id;
                match commands.try_send(ActorMessage::Command { player_id, envelope }) {
                    Ok(()) => {}
                    Err(mpsc::error::TrySendError::Full(_)) => {
                        send_rejection(&outbound_tx, Some(action_id), RejectReason::QueueFull);
                    }
                    Err(mpsc::error::TrySendError::Closed(_)) => break,
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    let _ = commands.send(ActorMessage::Disconnect { player_id }).await;
    writer.abort();
    state
        .metrics
        .ws_disconnected
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let _ = state.active_websockets.fetch_update(
        std::sync::atomic::Ordering::Relaxed,
        std::sync::atomic::Ordering::Relaxed,
        |n| Some(n.saturating_sub(1)),
    );
}

fn send_rejection(
    outbound: &mpsc::Sender<ServerMessage>,
    action_id: Option<judgement_domain::ActionId>,
    reason: RejectReason,
) {
    let retryable = reason.retryable();
    let message = match &reason {
        RejectReason::MalformedMessage { detail } => format!("malformed message: {detail}"),
        RejectReason::MessageTooLarge => "message exceeds the maximum size".to_string(),
        RejectReason::QueueFull => "server is busy; retry shortly".to_string(),
        RejectReason::WrongGame => "this connection belongs to a different game".to_string(),
        RejectReason::AudienceRateLimited { channel } => {
            format!("slow down — audience {channel} rate limit")
        }
        other => format!("{other:?}"),
    };
    let _ = outbound.try_send(ServerMessage::CommandRejected {
        action_id,
        reason,
        retryable,
        message,
    });
}

/// Audience watch WebSocket — never claims a seat; separate from player WS budget.
pub async fn watch_ws(
    State(state): State<Arc<AppState>>,
    Path(game_id): Path<uuid::Uuid>,
    Query(query): Query<WsQuery>,
    ws: WebSocketUpgrade,
) -> Result<Response, ApiError> {
    if !audience_flags().audience_enabled {
        return Err(ApiError::CapacityFull(
            "audience watching is temporarily disabled".into(),
        ));
    }

    let session = state
        .session_for_token(&query.token)
        .ok_or(ApiError::Unauthorized)?;
    let game_id = GameId(game_id);

    let (commands, nickname) = {
        let games = state.games.lock().unwrap();
        let info = games.get(&game_id).ok_or(ApiError::NotFound("game"))?;
        if info.players.contains_key(&session.id) {
            return Err(ApiError::Forbidden(
                "seated players must use the player table socket".into(),
            ));
        }
        let nickname = info
            .spectators
            .get(&session.id)
            .cloned()
            .ok_or_else(|| {
                ApiError::Forbidden("call POST /rooms/{code}/watch before connecting".into())
            })?;

        let global = state
            .active_spectator_websockets
            .load(std::sync::atomic::Ordering::Relaxed);
        // Approximate connected count ≈ map size is optimistic; actor enforces hard cap too.
        if let Err(msg) = admit_spectator(global, info.spectators.len().saturating_sub(1)) {
            state
                .metrics
                .spectator_capacity_rejected
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            return Err(ApiError::CapacityFull(msg.into()));
        }
        (info.commands.clone(), nickname)
    };

    // Confirm room still allows spectators.
    {
        let games = state.games.lock().unwrap();
        let info = games.get(&game_id).ok_or(ApiError::NotFound("game"))?;
        let rooms = state.rooms.lock().unwrap();
        let room = rooms
            .get(&info.room_id)
            .ok_or(ApiError::NotFound("room"))?;
        if !room.spectators_allowed {
            return Err(ApiError::Forbidden(
                "this table is not open for audience".into(),
            ));
        }
    }

    let rotated_token = state.rotate_token(session.id);
    if let Some(ref token) = rotated_token {
        if let Some(updated) = state.session_for_token(token) {
            let _ = state.store.upsert_session(&stored_session(&updated)).await;
        }
    }

    state
        .metrics
        .spectator_ws_connected
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    state
        .active_spectator_websockets
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);

    let state_for_socket = state.clone();
    let session_id = session.id;
    Ok(ws
        .max_message_size(MAX_WS_MESSAGE_BYTES)
        .on_upgrade(move |socket| {
            handle_watch_socket(
                socket,
                commands,
                session_id,
                nickname,
                game_id,
                rotated_token,
                state_for_socket,
            )
        }))
}

async fn handle_watch_socket(
    socket: WebSocket,
    commands: mpsc::Sender<ActorMessage>,
    session_id: SessionId,
    nickname: String,
    game_id: GameId,
    rotated_token: Option<String>,
    state: Arc<AppState>,
) {
    let (outbound_tx, mut outbound_rx) =
        mpsc::channel::<ServerMessage>(SPECTATOR_BUFFER_CAPACITY);

    if commands
        .send(ActorMessage::SpectatorConnect {
            session_id,
            nickname,
            outbound: outbound_tx.clone(),
            rotated_token,
        })
        .await
        .is_err()
    {
        let _ = state.active_spectator_websockets.fetch_update(
            std::sync::atomic::Ordering::Relaxed,
            std::sync::atomic::Ordering::Relaxed,
            |n| Some(n.saturating_sub(1)),
        );
        return;
    }

    let (mut ws_tx, mut ws_rx) = socket.split();

    let writer = tokio::spawn(async move {
        let mut heartbeat = tokio::time::interval(HEARTBEAT_INTERVAL);
        loop {
            tokio::select! {
                message = outbound_rx.recv() => {
                    let Some(message) = message else { break };
                    let Ok(text) = serde_json::to_string(&message) else { break };
                    if ws_tx.send(Message::Text(text.into())).await.is_err() {
                        break;
                    }
                }
                _ = heartbeat.tick() => {
                    if ws_tx.send(Message::Ping(Vec::new().into())).await.is_err() {
                        break;
                    }
                }
            }
        }
    });

    let mut last_seen = Instant::now();
    loop {
        let frame = tokio::time::timeout(LIVENESS_TIMEOUT, ws_rx.next()).await;
        let message = match frame {
            Err(_elapsed) => {
                if last_seen.elapsed() > LIVENESS_TIMEOUT {
                    break;
                }
                continue;
            }
            Ok(None) => break,
            Ok(Some(Err(_))) => break,
            Ok(Some(Ok(message))) => message,
        };
        last_seen = Instant::now();

        match message {
            Message::Text(text) => {
                let envelope: ClientEnvelope = match serde_json::from_str(&text) {
                    Ok(envelope) => envelope,
                    Err(error) => {
                        send_rejection(
                            &outbound_tx,
                            None,
                            RejectReason::MalformedMessage {
                                detail: error.to_string(),
                            },
                        );
                        continue;
                    }
                };
                if envelope.game_id != game_id {
                    send_rejection(&outbound_tx, Some(envelope.action_id), RejectReason::WrongGame);
                    continue;
                }
                let action_id = envelope.action_id;
                match commands.try_send(ActorMessage::SpectatorCommand {
                    session_id,
                    envelope,
                }) {
                    Ok(()) => {}
                    Err(mpsc::error::TrySendError::Full(_)) => {
                        send_rejection(&outbound_tx, Some(action_id), RejectReason::QueueFull);
                    }
                    Err(mpsc::error::TrySendError::Closed(_)) => break,
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    let _ = commands
        .send(ActorMessage::SpectatorDisconnect { session_id })
        .await;
    writer.abort();
    state
        .metrics
        .spectator_ws_disconnected
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let _ = state.active_spectator_websockets.fetch_update(
        std::sync::atomic::Ordering::Relaxed,
        std::sync::atomic::Ordering::Relaxed,
        |n| Some(n.saturating_sub(1)),
    );
}
