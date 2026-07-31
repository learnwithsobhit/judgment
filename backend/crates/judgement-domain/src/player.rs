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
    /// Built-in avatar pack id (cosmetic; not used by rules).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub avatar_id: Option<String>,
}

impl PlayerState {
    pub fn human(id: PlayerId, nickname: impl Into<String>, seat: u8) -> Self {
        Self {
            id,
            nickname: nickname.into(),
            seat,
            is_bot: false,
            connection_status: ConnectionStatus::Connected,
            avatar_id: None,
        }
    }

    pub fn bot(id: PlayerId, nickname: impl Into<String>, seat: u8) -> Self {
        Self {
            id,
            nickname: nickname.into(),
            seat,
            is_bot: true,
            connection_status: ConnectionStatus::BotControlled,
            avatar_id: None,
        }
    }

    pub fn with_avatar(mut self, avatar_id: impl Into<String>) -> Self {
        self.avatar_id = Some(avatar_id.into());
        self
    }
}
