//! WebSocket endpoint for live gameplay (PLAN.md §13.2, Phase 6 reconnect).

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Path, Query, State};
use axum::response::Response;
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio::sync::mpsc;
use tokio::time::Instant;

use judgement_domain::{GameId, PlayerId};
use judgement_protocol::{ClientEnvelope, RejectReason, ServerMessage};

use crate::actor::{ActorMessage, CLIENT_BUFFER_CAPACITY};
use crate::error::ApiError;
use crate::persist::stored_session;
use crate::state::AppState;

pub const MAX_WS_MESSAGE_BYTES: usize = 64 * 1024;
pub const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(10);
pub const LIVENESS_TIMEOUT: Duration = Duration::from_secs(45);

static NEXT_CONN_GEN: AtomicU64 = AtomicU64::new(1);

/// Why a live game WebSocket ended — logged at disconnect for RCA.
#[derive(Debug, Clone, Copy)]
enum WsDisconnectReason {
    /// No inbound frame (including Pong) within [`LIVENESS_TIMEOUT`].
    LivenessTimeout,
    /// Client sent a WebSocket Close frame.
    ClientClose,
    /// Underlying socket read failed.
    SocketError,
    /// Stream ended without an explicit Close frame (proxy/network drop).
    StreamEnded,
    /// Game actor command channel closed (game gone / actor dead).
    ActorClosed,
    /// Connect handoff to the actor failed before the read loop started.
    ActorConnectFailed,
}

impl WsDisconnectReason {
    fn metrics_label(self) -> &'static str {
        match self {
            Self::LivenessTimeout => "liveness",
            Self::ClientClose => "client_close",
            Self::SocketError => "socket_error",
            Self::StreamEnded => "stream_ended",
            Self::ActorClosed => "actor_closed",
            Self::ActorConnectFailed => "actor_connect_failed",
        }
    }
}

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
    let conn_gen = NEXT_CONN_GEN.fetch_add(1, Ordering::Relaxed);
    let (outbound_tx, mut outbound_rx) = mpsc::channel::<ServerMessage>(CLIENT_BUFFER_CAPACITY);

    if commands
        .send(ActorMessage::Connect {
            player_id,
            outbound: outbound_tx.clone(),
            rotated_token,
            conn_gen,
        })
        .await
        .is_err()
    {
        tracing::warn!(
            %game_id,
            %player_id,
            conn_gen,
            reason = ?WsDisconnectReason::ActorConnectFailed,
            "websocket disconnected"
        );
        state
            .metrics
            .record_ws_disconnect(WsDisconnectReason::ActorConnectFailed.metrics_label());
        let _ = state.active_websockets.fetch_update(
            std::sync::atomic::Ordering::Relaxed,
            std::sync::atomic::Ordering::Relaxed,
            |n| Some(n.saturating_sub(1)),
        );
        return;
    }

    tracing::info!(
        %game_id,
        %player_id,
        conn_gen,
        "websocket connected"
    );

    let (mut ws_tx, mut ws_rx) = socket.split();

    let writer_game_id = game_id;
    let writer_player_id = player_id;
    let mut writer = tokio::spawn(async move {
        let mut heartbeat = tokio::time::interval(HEARTBEAT_INTERVAL);
        heartbeat.tick().await; // skip immediate fire; first keepalive at HEARTBEAT_INTERVAL
        loop {
            tokio::select! {
                message = outbound_rx.recv() => {
                    let Some(message) = message else { break };
                    let Ok(text) = serde_json::to_string(&message) else { break };
                    if ws_tx.send(Message::Text(text.into())).await.is_err() {
                        tracing::info!(
                            game_id = %writer_game_id,
                            player_id = %writer_player_id,
                            reason = "outbound_send_failed",
                            "websocket writer stopping"
                        );
                        break;
                    }
                }
                _ = heartbeat.tick() => {
                    if ws_tx.send(Message::Ping(Vec::new().into())).await.is_err() {
                        tracing::debug!(
                            game_id = %writer_game_id,
                            player_id = %writer_player_id,
                            reason = "ping_send_failed",
                            "websocket writer stopping"
                        );
                        break;
                    }
                    // Text frame so HTTP/2 / Railway edges count traffic (Ping is often ignored).
                    let Ok(keep_alive) = serde_json::to_string(&ServerMessage::KeepAlive) else {
                        break;
                    };
                    if ws_tx.send(Message::Text(keep_alive.into())).await.is_err() {
                        tracing::debug!(
                            game_id = %writer_game_id,
                            player_id = %writer_player_id,
                            reason = "keep_alive_send_failed",
                            "websocket writer stopping"
                        );
                        break;
                    }
                }
            }
        }
    });

    let mut last_seen = Instant::now();
    let (disconnect_reason, disconnect_detail) = loop {
        tokio::select! {
            _ = &mut writer => {
                break (
                    WsDisconnectReason::StreamEnded,
                    "writer_stopped".into(),
                );
            }
            frame = tokio::time::timeout(LIVENESS_TIMEOUT, ws_rx.next()) => {
        let message = match frame {
            Err(_elapsed) => {
                let idle = last_seen.elapsed();
                if idle > LIVENESS_TIMEOUT {
                    break (
                        WsDisconnectReason::LivenessTimeout,
                        format!("idle_ms={}", idle.as_millis()),
                    );
                }
                continue;
            }
            Ok(None) => {
                break (
                    WsDisconnectReason::StreamEnded,
                    "read stream ended".into(),
                );
            }
            Ok(Some(Err(error))) => {
                let error_text = error.to_string();
                if error_text.to_lowercase().contains("capacity") {
                    send_rejection(&outbound_tx, None, RejectReason::MessageTooLarge);
                }
                break (WsDisconnectReason::SocketError, error_text);
            }
            Ok(Some(Ok(message))) => message,
        };
        last_seen = Instant::now();

        match message {
            Message::Text(text) => {
                if is_client_keep_alive(&text) {
                    continue;
                }
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
                    Err(mpsc::error::TrySendError::Closed(_)) => {
                        break (
                            WsDisconnectReason::ActorClosed,
                            "actor command channel closed".into(),
                        );
                    }
                }
            }
            Message::Close(frame) => {
                let detail = match frame {
                    Some(frame) => format!(
                        "code={} reason={}",
                        u16::from(frame.code),
                        frame.reason
                    ),
                    None => "close frame without code".into(),
                };
                break (WsDisconnectReason::ClientClose, detail);
            }
            _ => {}
        }
            }
        }
    };

    tracing::info!(
        %game_id,
        %player_id,
        conn_gen,
        reason = ?disconnect_reason,
        detail = %disconnect_detail,
        idle_ms = last_seen.elapsed().as_millis(),
        "websocket disconnected"
    );

    let _ = commands
        .send(ActorMessage::Disconnect {
            player_id,
            conn_gen,
        })
        .await;
    writer.abort();
    state
        .metrics
        .record_ws_disconnect(disconnect_reason.metrics_label());
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
        other => format!("{other:?}"),
    };
    let _ = outbound.try_send(ServerMessage::CommandRejected {
        action_id,
        reason,
        retryable,
        message,
    });
}

/// Client→server keepalive (`{"type":"keep_alive"}` only). Not a command envelope.
fn is_client_keep_alive(text: &str) -> bool {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(text.trim()) else {
        return false;
    };
    let Some(obj) = value.as_object() else {
        return false;
    };
    if obj.get("type").and_then(|v| v.as_str()) != Some("keep_alive") {
        return false;
    }
    // Reject anything that looks like a partial ClientEnvelope.
    !obj.contains_key("action_id")
        && !obj.contains_key("protocol_version")
        && !obj.contains_key("expected_state_version")
        && !obj.contains_key("game_id")
        && !obj.contains_key("action")
}

#[cfg(test)]
mod tests {
    use super::is_client_keep_alive;

    #[test]
    fn client_keep_alive_is_recognized() {
        assert!(is_client_keep_alive(r#"{"type":"keep_alive"}"#));
        assert!(is_client_keep_alive("  {\"type\":\"keep_alive\"}  "));
    }

    #[test]
    fn client_envelope_is_not_keep_alive() {
        assert!(!is_client_keep_alive(
            r#"{"type":"keep_alive","action_id":"x","protocol_version":1,"game_id":"00000000-0000-0000-0000-000000000001","expected_state_version":0,"action":{"type":"request_state_sync"}}"#
        ));
        assert!(!is_client_keep_alive(r#"{"type":"ready","protocol_version":1}"#));
    }
}
