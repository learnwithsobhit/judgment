//! Player identity and presence types.

use serde::{Deserialize, Serialize};

use crate::ids::PlayerId;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionStatus {
    Connected,
    Disconnected,
    BotControlled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlayerState {
    pub id: PlayerId,
    pub nickname: String,
    /// Seat index `0..player_count`, clockwise around the table.
    pub seat: u8,
    pub is_bot: bool,
    pub connection_status: ConnectionStatus,
}

impl PlayerState {
    pub fn human(id: PlayerId, nickname: impl Into<String>, seat: u8) -> Self {
        Self {
            id,
            nickname: nickname.into(),
            seat,
            is_bot: false,
            connection_status: ConnectionStatus::Connected,
        }
    }

    pub fn bot(id: PlayerId, nickname: impl Into<String>, seat: u8) -> Self {
        Self {
            id,
            nickname: nickname.into(),
            seat,
            is_bot: true,
            connection_status: ConnectionStatus::BotControlled,
        }
    }
}
