//! WebSocket message schema (PLAN.md §13.3–§13.5).

use serde::{Deserialize, Serialize};

use judgement_domain::{ActionId, GameError, GameId, PlayerId};
use judgement_engine::PlayerGameView;

/// Every client command travels in this envelope (PLAN.md §13.4).
///
/// - `action_id` prevents duplicate processing
/// - `expected_state_version` detects stale clients
/// - `protocol_version` supports future upgrades
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClientEnvelope {
    pub protocol_version: u16,
    pub action_id: ActionId,
    pub game_id: GameId,
    pub expected_state_version: u64,
    pub action: ClientCommand,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "type")]
pub enum ClientCommand {
    Ready,
    Unready,
    StartGame,
    PlaceBid { bid: u8 },
    PlayCard { card_id: judgement_domain::CardId },
    RequestStateSync,
    LeaveGame,
    /// Built-in avatar pack id (cosmetic).
    SetAvatar { avatar_id: String },
    /// Quick emoji reaction (ephemeral table event).
    SendReaction {
        emoji: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        target: Option<PlayerId>,
    },
    /// Free-text vibe; server broadcasts resolved emoji burst (client may also resolve).
    SendEmoteText { text: String },
    /// Manual avatar flash mood: cheer | laugh | facepalm | fire
    AvatarFlash { mood: String },
}

/// Why a command was rejected: either a domain rule or a protocol-level
/// condition. `retryable` tells the client whether resending (with the same
/// `action_id`) may succeed.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "kind")]
pub enum RejectReason {
    Game { error: GameError },
    UnsupportedProtocolVersion { supported: u16, received: u16 },
    MalformedMessage { detail: String },
    MessageTooLarge,
    /// Actor command queue is full — backpressure; retry shortly.
    QueueFull,
    WrongGame,
    /// The command is not available in this phase of the MVP (e.g. lobby
    /// commands over the game socket).
    UnsupportedCommand,
}

impl RejectReason {
    pub fn retryable(&self) -> bool {
        matches!(self, RejectReason::QueueFull)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TimerEvent {
    pub deadline_id: u64,
    /// Remaining duration plus server "now" so clients reconcile clock skew
    /// and browser suspend (PLAN.md §16).
    pub remaining_ms: u64,
    pub server_now_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "type")]
pub enum ServerMessage {
    CommandAccepted {
        action_id: ActionId,
        new_state_version: u64,
    },
    CommandRejected {
        action_id: Option<ActionId>,
        reason: RejectReason,
        retryable: bool,
        message: String,
    },
    /// Full personalised snapshot after every accepted command
    /// (locked decision 6 — no deltas in MVP).
    StateSnapshot { view: PlayerGameView },
    PlayerConnected { player_id: PlayerId },
    PlayerDisconnected { player_id: PlayerId },
    HostChanged { new_host: PlayerId },
    TimerUpdated { timer: TimerEvent },
    /// The table is paused while a disconnected human is within the reconnect
    /// grace window (PLAN.md §15).
    GamePaused {
        reason: String,
        remaining_ms: u64,
    },
    GameResumed,
    BotTookOver { player_id: PlayerId },
    PlayerResumedControl { player_id: PlayerId },
    /// Issued on successful WebSocket reconnect (PLAN.md §15.1).
    TokenRotated { token: String },
    /// Ephemeral table engagement (reactions / cheers). Not stored in engine.
    TableEvent {
        kind: String,
        from: PlayerId,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        target: Option<PlayerId>,
        #[serde(default)]
        emojis: Vec<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        text: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        mood: Option<String>,
        /// Curated cartoon sticker id for hybrid text blasts (cosmetic).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        sticker_id: Option<String>,
        ttl_ms: u32,
    },
}

#[cfg(test)]
mod tests {
    use judgement_domain::CardId;
    use uuid::Uuid;

    use super::*;

    #[test]
    fn envelope_matches_plan_wire_shape() {
        let envelope = ClientEnvelope {
            protocol_version: 1,
            action_id: ActionId(Uuid::nil()),
            game_id: GameId(Uuid::nil()),
            expected_state_version: 84,
            action: ClientCommand::PlayCard { card_id: "ace-of-hearts".parse().unwrap() },
        };
        let json = serde_json::to_value(&envelope).unwrap();
        assert_eq!(json["protocol_version"], 1);
        assert_eq!(json["expected_state_version"], 84);
        assert_eq!(json["action"]["type"], "play_card");
        assert_eq!(json["action"]["card_id"], "ace-of-hearts");

        let back: ClientEnvelope = serde_json::from_value(json).unwrap();
        assert_eq!(back, envelope);
    }

    #[test]
    fn commands_round_trip() {
        let commands = [
            ClientCommand::Ready,
            ClientCommand::Unready,
            ClientCommand::StartGame,
            ClientCommand::PlaceBid { bid: 3 },
            ClientCommand::PlayCard { card_id: CardId { suit: judgement_domain::Suit::Spades, rank: judgement_domain::Rank::Seven } },
            ClientCommand::RequestStateSync,
            ClientCommand::LeaveGame,
            ClientCommand::SetAvatar {
                avatar_id: "fox".into(),
            },
            ClientCommand::SendReaction {
                emoji: "🔥".into(),
                target: None,
            },
            ClientCommand::SendEmoteText {
                text: "nice".into(),
            },
            ClientCommand::AvatarFlash {
                mood: "cheer".into(),
            },
        ];
        for command in commands {
            let json = serde_json::to_string(&command).unwrap();
            let back: ClientCommand = serde_json::from_str(&json).unwrap();
            assert_eq!(back, command);
        }
    }

    #[test]
    fn unknown_command_type_is_rejected() {
        let result: Result<ClientCommand, _> =
            serde_json::from_str(r#"{"type":"hack_the_deck"}"#);
        assert!(result.is_err());
    }

    #[test]
    fn missing_fields_are_rejected() {
        let result: Result<ClientEnvelope, _> = serde_json::from_str(
            r#"{"protocol_version":1,"action":{"type":"ready"}}"#,
        );
        assert!(result.is_err());
    }

    #[test]
    fn reject_reason_round_trips_with_game_error() {
        let reason = RejectReason::Game {
            error: judgement_domain::GameError::StaleState { expected_version: 3, actual_version: 7 },
        };
        let json = serde_json::to_string(&reason).unwrap();
        let back: RejectReason = serde_json::from_str(&json).unwrap();
        assert_eq!(back, reason);
        assert!(!reason.retryable());
        assert!(RejectReason::QueueFull.retryable());
    }
}
