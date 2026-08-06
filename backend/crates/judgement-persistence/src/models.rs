//! Serializable records exchanged with the store.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use judgement_domain::{
    ActionId, EventId, GameId, GameRules, PlayerId, RankedPlayer, RoomId, RoundSchedule, RsvpId,
    SessionId, Suit,
};
use judgement_engine::{GameEvent, InternalGameState};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredSession {
    pub session_id: SessionId,
    pub nickname: String,
    pub token: String,
    pub created_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredRoomPlayer {
    pub session_id: SessionId,
    pub player_id: PlayerId,
    pub nickname: String,
    pub seat: u8,
    pub ready: bool,
    pub joined_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredRoom {
    pub room_id: RoomId,
    pub code: String,
    pub host_session_id: SessionId,
    pub max_players: u8,
    pub turn_timeout_seconds: Option<u16>,
    pub first_trump: Option<Suit>,
    /// Custom 4-suit trump cycle when set.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trump_cycle: Option<Vec<Suit>>,
    /// Automatic descending or manual `{cards, repeat}` steps.
    #[serde(default)]
    pub round_schedule: RoundSchedule,
    #[serde(default)]
    pub dealer_total_restriction: bool,
    pub phase: String,
    pub game_id: Option<GameId>,
    pub players: Vec<StoredRoomPlayer>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone)]
pub struct NewGamePlayer {
    pub player_id: PlayerId,
    pub session_id: SessionId,
    pub nickname: String,
    pub seat: u8,
}

#[derive(Debug, Clone)]
pub struct NewGame {
    pub game_id: GameId,
    pub room_id: RoomId,
    pub rules: GameRules,
    pub seed: Option<u64>,
    pub players: Vec<NewGamePlayer>,
    /// State after `start_game` (version ≥ 1).
    pub initial_state: InternalGameState,
    pub initial_events: Vec<GameEvent>,
    /// Synthetic action id for the host's start (dedup rebuild).
    pub start_action_id: ActionId,
}

#[derive(Debug, Clone)]
pub struct CommandCommit {
    pub game_id: GameId,
    pub action_id: ActionId,
    pub events: Vec<GameEvent>,
    pub state: InternalGameState,
    pub round_result: Option<RoundResultRecord>,
    pub game_result: Option<GameResultRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoundResultRecord {
    pub round_index: usize,
    pub scores: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameResultRecord {
    pub ranking: Vec<RankedPlayer>,
}

#[derive(Debug, Clone)]
pub struct RestoredGame {
    pub game_id: GameId,
    pub room_id: RoomId,
    pub rules: GameRules,
    pub seed: Option<u64>,
    pub state: InternalGameState,
    pub players: Vec<NewGamePlayer>,
    pub processed_actions: Vec<(ActionId, u64)>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameHistory {
    pub game_id: GameId,
    pub status: String,
    pub rules: GameRules,
    pub ranking: Option<Vec<RankedPlayer>>,
    pub round_results: Vec<RoundResultRecord>,
    pub event_count: u64,
}

/// Durable scheduled meetup (ADR 0005). Distinct from engine `GameEvent`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredScheduledEvent {
    pub event_id: EventId,
    pub slug: String,
    pub manage_token_hash: String,
    pub host_nickname: String,
    pub host_session_id: Option<SessionId>,
    pub title: String,
    pub starts_at: DateTime<Utc>,
    pub timezone: String,
    pub duration_minutes: u16,
    pub max_players: u8,
    pub turn_timeout_seconds: Option<u16>,
    pub first_trump: Option<Suit>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trump_cycle: Option<Vec<Suit>>,
    #[serde(default)]
    pub round_schedule: RoundSchedule,
    pub status: String,
    pub room_id: Option<RoomId>,
    pub rsvps: Vec<StoredEventRsvp>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredEventRsvp {
    pub rsvp_id: RsvpId,
    pub display_name: String,
    pub mobile_e164: String,
    pub status: String,
    pub manage_token_hash: String,
    pub contact_consent: bool,
    pub created_at: DateTime<Utc>,
}
