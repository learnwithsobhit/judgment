//! WebSocket message schema (PLAN.md §13.3–§13.5).

use std::sync::Arc;

use serde::{Deserialize, Serialize};

use judgement_domain::{ActionId, GameError, GameId, PlayerId};
use judgement_engine::{PlayerGameView, SpectatorGameView};

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
    /// Host ends a game paused for vacant seats (replace-or-end).
    EndGame,
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
    /// Curated soundboard clip (asset id only; clients hold the bytes).
    SendSoundboard { sound_id: String },
    /// Short ephemeral voice note (Opus/WebM base64; not persisted).
    SendVoiceNote {
        mime: String,
        duration_ms: u32,
        audio_b64: String,
    },
    /// Audience-only text comment (spectators only; never mutates game).
    AudienceComment { text: String },
    /// Soft cheer reaction from audience → player table blasts.
    AudienceReaction { emoji: String },
    /// Audience-only voice note (spectators only).
    AudienceVoiceNote {
        mime: String,
        duration_ms: u32,
        audio_b64: String,
    },
    /// Audience winner prediction (upsert until last round starts).
    SetWinnerPrediction { player_id: PlayerId },
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
    /// Persist timed out or DB unavailable — retry shortly.
    PersistUnavailable,
    WrongGame,
    /// The command is not available in this phase of the MVP (e.g. lobby
    /// commands over the game socket).
    UnsupportedCommand,
    /// Audience messaging / prediction rate limit exceeded.
    AudienceRateLimited { channel: String },
}

impl RejectReason {
    pub fn retryable(&self) -> bool {
        matches!(
            self,
            RejectReason::QueueFull | RejectReason::PersistUnavailable
        )
    }
}

/// Aggregate crowd winner-prediction tally (shared with players + audience).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CrowdPredictionTally {
    pub player_id: PlayerId,
    pub count: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CrowdPredictionView {
    pub locked: bool,
    pub tallies: Vec<CrowdPredictionTally>,
    pub total_voters: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub my_pick: Option<PlayerId>,
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
    /// Hand-free snapshot for audience WebSocket clients.
    SpectatorStateSnapshot { view: SpectatorGameView },
    /// Coalesced crowd prediction update (players + spectators).
    CrowdPredictionUpdated { prediction: CrowdPredictionView },
    /// Audience-only comment fan-out.
    AudienceCommentEvent {
        from_nickname: String,
        text: String,
        ttl_ms: u32,
    },
    /// Audience-only voice note fan-out.
    AudienceVoiceNoteEvent {
        from_nickname: String,
        mime: String,
        duration_ms: u32,
        audio_b64: Arc<str>,
        ttl_ms: u32,
    },
    /// Host revoked spectating or game ended for watchers.
    SpectatingClosed { reason: String },
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
    /// Seat open after grace/leave — another human may claim via room code.
    SeatVacant {
        player_id: PlayerId,
        room_code: String,
    },
    SeatClaimed {
        player_id: PlayerId,
        nickname: String,
    },
    /// Host or vacancy-timeout ended the game before natural completion.
    GameEnded {
        reason: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        aborted: Option<bool>,
    },
    /// Host restarted: same room, new `game_id` — clients must switch WS.
    GameRestarted { game_id: GameId },
    /// Legacy wire name; no longer emitted for live disconnect (kept for older clients).
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
        /// Curated soundboard id (`kind == "soundboard"`).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        sound_id: Option<String>,
        ttl_ms: u32,
        /// True when the blast originated from an audience watcher.
        #[serde(default)]
        from_audience: bool,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        audience_nickname: Option<String>,
    },
    /// Ephemeral freeform voice note. Not stored in engine or DB.
    VoiceNote {
        from: PlayerId,
        mime: String,
        duration_ms: u32,
        /// Shared across fan-out clones to avoid N× payload copies.
        audio_b64: Arc<str>,
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
            ClientCommand::EndGame,
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
            ClientCommand::SendSoundboard {
                sound_id: "laugh".into(),
            },
            ClientCommand::SendVoiceNote {
                mime: "audio/webm;codecs=opus".into(),
                duration_ms: 1200,
                audio_b64: "AAAA".into(),
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
