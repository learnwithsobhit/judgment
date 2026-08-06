use dehla_domain::{Card, GameId, Suit};
use dehla_engine::PlayerGameView;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientEnvelope {
    pub protocol_version: u16,
    pub action_id: Uuid,
    pub game_id: GameId,
    pub expected_state_version: u64,
    pub action: ClientCommand,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientCommand {
    AnnounceTrump { suit: Suit },
    PlayCard { card: Card },
    StartNextHand,
    Rematch,
    RequestStateSync,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMessage {
    StateSnapshot { view: PlayerGameView },
    Reject { reason: String, retryable: bool },
    TokenRotated { token: String },
    /// Host ended the match or returned the table to lobby after vacancy.
    GameEnded {
        reason: String,
        #[serde(default)]
        aborted: bool,
    },
    /// Host restart auto-started a new game (only when 4 seats remain).
    GameRestarted { game_id: GameId },
}
