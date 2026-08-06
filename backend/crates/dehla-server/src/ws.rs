use std::sync::atomic::Ordering;
use std::sync::Arc;

use axum::extract::ws::{Message, WebSocket};
use axum::extract::{Path, Query, State, WebSocketUpgrade};
use axum::response::IntoResponse;
use dehla_domain::{GameId, PlayerId};
use dehla_protocol::{ClientEnvelope, ServerMessage};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio::sync::mpsc;

use crate::actor::ActorMessage;
use crate::capacity::{is_full, CAPACITY_FULL_MESSAGE};
use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct WsQuery {
    pub token: String,
}

pub async fn ws_upgrade(
    State(state): State<Arc<AppState>>,
    Path(game_id): Path<GameId>,
    Query(q): Query<WsQuery>,
    ws: WebSocketUpgrade,
) -> Result<impl IntoResponse, ApiError> {
    if is_full(&state) {
        return Err(ApiError::capacity_full(CAPACITY_FULL_MESSAGE));
    }

    let session_id = state
        .tokens
        .lock()
        .unwrap()
        .get(&q.token)
        .copied()
        .ok_or_else(ApiError::unauthorized)?;
    let player_id = {
        let games = state.games.lock().unwrap();
        let info = games
            .get(&game_id)
            .ok_or_else(|| ApiError::not_found("game not found"))?;
        *info
            .players
            .get(&session_id)
            .ok_or_else(|| ApiError::forbidden("not a player in this game"))?
    };

    // Rotate token
    let new_token = crate::state::generate_token();
    {
        let mut sessions = state.sessions.lock().unwrap();
        let mut tokens = state.tokens.lock().unwrap();
        if let Some(sess) = sessions.get_mut(&session_id) {
            tokens.remove(&sess.token);
            sess.token = new_token.clone();
            tokens.insert(new_token.clone(), session_id);
        }
    }

    state.ws_count.fetch_add(1, Ordering::Relaxed);

    Ok(ws.on_upgrade(move |socket| {
        handle_socket(state, game_id, player_id, socket, new_token)
    }))
}

async fn handle_socket(
    state: Arc<AppState>,
    game_id: GameId,
    player_id: PlayerId,
    socket: WebSocket,
    new_token: String,
) {
    let (mut sink, mut stream) = socket.split();
    let (out_tx, mut out_rx) = mpsc::channel::<ServerMessage>(64);

    let cmd_tx = {
        let games = state.games.lock().unwrap();
        match games.get(&game_id) {
            Some(g) => g.commands.clone(),
            None => {
                dec_ws(&state);
                return;
            }
        }
    };

    let _ = out_tx
        .send(ServerMessage::TokenRotated { token: new_token })
        .await;
    let _ = cmd_tx
        .send(ActorMessage::Connect {
            player_id,
            outbound: out_tx,
        })
        .await;

    let writer = tokio::spawn(async move {
        while let Some(msg) = out_rx.recv().await {
            if let Ok(text) = serde_json::to_string(&msg) {
                if sink.send(Message::Text(text.into())).await.is_err() {
                    break;
                }
            }
        }
    });

    while let Some(Ok(msg)) = stream.next().await {
        match msg {
            Message::Text(text) => {
                if let Ok(envelope) = serde_json::from_str::<ClientEnvelope>(&text) {
                    let _ = cmd_tx
                        .send(ActorMessage::Command {
                            player_id,
                            envelope,
                        })
                        .await;
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    let _ = cmd_tx
        .send(ActorMessage::Disconnect { player_id })
        .await;
    writer.abort();
    dec_ws(&state);
}

fn dec_ws(state: &AppState) {
    let _ = state.ws_count.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| {
        Some(n.saturating_sub(1))
    });
}
