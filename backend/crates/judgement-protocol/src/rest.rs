//! REST request/response models for non-live operations (PLAN.md §13.1).

use serde::{Deserialize, Serialize};

use chrono::{DateTime, Utc};

use judgement_domain::{
    EventId, GameId, PlayerId, RoomId, RoundSchedule, RsvpId, SessionId, Suit,
};

// ---------------------------------------------------------------------------
// Guest sessions
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateGuestSessionRequest {
    pub nickname: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateGuestSessionResponse {
    pub session_id: SessionId,
    pub nickname: String,
    /// Opaque bearer token for REST calls and WebSocket auth. Never logged.
    pub token: String,
}

// ---------------------------------------------------------------------------
// Rooms
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CreateRoomRequest {
    /// Table size, 3–8. Defaults to 6.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_players: Option<u8>,
    /// Turn timer in seconds. **Omitted or `null` disables the timer**
    /// (ADR 0003): no deadlines, no auto-play.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_timeout_seconds: Option<u16>,
    /// Trump for round 1; later rounds follow the fixed rotation
    /// ♠ → ♦ → ♣ → ♥ (ADR 0003). Omitted ⇒ revealed-card trump each round.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_trump: Option<Suit>,
    /// Automatic (default) or Manual step list expanded at game start.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub round_schedule: Option<RoundSchedule>,
    /// When true, dealer may not make total bids equal tricks (classic Oh Hell).
    /// Default `false` — matching totals are allowed.
    #[serde(default)]
    pub dealer_total_restriction: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRoomResponse {
    pub room: RoomView,
    /// The creator's seat assignment.
    pub player_id: PlayerId,
    /// `comfort` | `busy` | `full` — soft signal when tables are congested.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capacity: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct JoinRoomRequest {}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JoinRoomResponse {
    pub room: RoomView,
    pub player_id: PlayerId,
}

/// Claim a vacant in-game seat (replace-or-end presence).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ClaimSeatRequest {
    /// Optional specific vacant `player_id`; omitted ⇒ first vacant seat.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub player_id: Option<PlayerId>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaimSeatResponse {
    pub room: RoomView,
    pub player_id: PlayerId,
    pub game_id: GameId,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EndGameResponse {
    pub game_id: GameId,
    pub aborted: bool,
}

/// Host rematch: abort vacant seats, return to lobby briefly, start a new game.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RestartGameResponse {
    pub old_game_id: GameId,
    pub game_id: GameId,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadyRequest {
    pub ready: bool,
}

/// Host removes a seated player from the lobby before the game starts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemovePlayerRequest {
    pub player_id: PlayerId,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct StartGameRequest {
    /// Deterministic shuffle seed for dev/test rooms. Production clients omit
    /// it; the server then uses OS-backed secure randomness.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub seed: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StartGameResponse {
    pub game_id: GameId,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RoomPhase {
    Lobby,
    InGame,
}

/// Public room state. Identities are `PlayerId`s only — session ids and
/// tokens are never exposed (PLAN.md §8).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomView {
    pub room_id: RoomId,
    pub code: String,
    pub phase: RoomPhase,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub game_id: Option<GameId>,
    pub max_players: u8,
    pub min_players: u8,
    /// `None` means the room has no turn timer (ADR 0003).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_timeout_seconds: Option<u16>,
    /// `None` means revealed-card trump; `Some` means rotation from this suit.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_trump: Option<Suit>,
    /// Host-chosen round schedule (default Automatic when omitted on older clients).
    #[serde(default)]
    pub round_schedule: RoundSchedule,
    /// Human-readable summary for the lobby, e.g. `Automatic (12→1)`.
    pub round_schedule_summary: String,
    /// Classic dealer bid restriction (default off).
    #[serde(default)]
    pub dealer_total_restriction: bool,
    /// Host allows audience watchers (watch link / watch WS).
    #[serde(default)]
    pub spectators_allowed: bool,
    /// Appear on the public Live Now catalog (requires spectators_allowed).
    #[serde(default)]
    pub list_on_live_now: bool,
    pub seats: Vec<SeatView>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateAudienceSettingsRequest {
    pub spectators_allowed: bool,
    #[serde(default)]
    pub list_on_live_now: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WatchRoomRequest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub nickname: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WatchRoomResponse {
    pub game_id: GameId,
    pub room_code: String,
    pub room_id: RoomId,
}

/// Compact card for the public Live Now browse screen.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveRoomCard {
    pub room_code: String,
    pub game_id: GameId,
    pub host_nickname: String,
    pub player_count: u8,
    pub max_players: u8,
    pub phase: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub round_index: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total_rounds: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cards_per_player: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trump: Option<Suit>,
    pub viewer_count: u32,
    /// Soft engagement pulse (recent audience activity).
    #[serde(default)]
    pub energy: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveRoomsResponse {
    pub rooms: Vec<LiveRoomCard>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SeatView {
    pub player_id: PlayerId,
    pub nickname: String,
    pub seat: u8,
    pub ready: bool,
    pub is_host: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetAvatarRequest {
    pub avatar_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetAvatarResponse {
    pub avatar_id: String,
}

/// Uniform error body for REST endpoints.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiErrorBody {
    pub error: ApiErrorDetail,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiErrorDetail {
    pub code: String,
    pub message: String,
}

/// Finished-game ranking (PLAN.md Phase 5).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameResultResponse {
    pub game_id: GameId,
    pub ranking: Vec<judgement_domain::RankedPlayer>,
}

/// Game history: rounds + optional final ranking (PLAN.md Phase 5).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameHistoryResponse {
    pub game_id: GameId,
    pub status: String,
    pub rules: judgement_domain::GameRules,
    pub ranking: Option<Vec<judgement_domain::RankedPlayer>>,
    pub round_results: Vec<RoundResultView>,
    pub event_count: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoundResultView {
    pub round_index: usize,
    pub scores: serde_json::Value,
}

// ---------------------------------------------------------------------------
// AI / rules assistant (PLAN.md §13.1, §18.1)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct RulesQueryRequest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub question: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason_code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub facts: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trick: Option<TrickExplainRequest>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrickExplainRequest {
    pub lead_suit: Suit,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trump_suit: Option<Suit>,
    pub plays: Vec<TrickPlayView>,
    pub winner: PlayerId,
    pub reason_code: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrickPlayView {
    pub player_id: PlayerId,
    pub card: judgement_domain::CardId,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExplanationResponse {
    pub answer: String,
    pub rule_references: Vec<String>,
    pub confidence: f32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub suggested_action: Option<String>,
    #[serde(default)]
    pub deterministic: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fallback_reason: Option<String>,
}

// ---------------------------------------------------------------------------
// Coaching / highlights (PLAN.md §13.1, §18.5–18.8)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CoachingResponse {
    pub player_id: PlayerId,
    pub headline: String,
    pub overall: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub strongest_round: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weakest_round: Option<String>,
    pub risk_pattern: String,
    pub improvements: Vec<String>,
    pub positive: String,
    pub evidence: Vec<String>,
    pub analysis: serde_json::Value,
    pub deterministic: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fallback_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HighlightsResponse {
    pub lines: Vec<String>,
    pub facts: serde_json::Value,
    pub deterministic: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fallback_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoundSummaryResponse {
    pub summary: serde_json::Value,
    pub narration: ExplanationResponse,
}

// ---------------------------------------------------------------------------
// Scheduled game events (ADR 0005)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GameEventStatus {
    Open,
    LobbyOpen,
    Started,
    Cancelled,
    Expired,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateGameEventRequest {
    pub title: String,
    pub starts_at: DateTime<Utc>,
    /// IANA timezone for display, e.g. `Asia/Kolkata`.
    pub timezone: String,
    #[serde(default = "default_duration_minutes")]
    pub duration_minutes: u16,
    /// Ignored — seat pool is always 8 (FCFS). Kept for backward-compatible clients.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_players: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_timeout_seconds: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_trump: Option<Suit>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub round_schedule: Option<RoundSchedule>,
}

fn default_duration_minutes() -> u16 {
    90
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateGameEventResponse {
    pub event: GameEventPublicView,
    /// Host secret — shown once; never returned again by public endpoints.
    pub manage_token: String,
    pub manage_path: String,
    pub invite_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameEventPublicView {
    pub event_id: EventId,
    pub slug: String,
    pub title: String,
    pub host_nickname: String,
    pub starts_at: DateTime<Utc>,
    pub timezone: String,
    pub duration_minutes: u16,
    /// Fixed seat pool size (always 8); not a host-chosen table size.
    pub max_players: u8,
    pub turn_timeout_seconds: Option<u16>,
    pub first_trump: Option<Suit>,
    #[serde(default)]
    pub round_schedule: RoundSchedule,
    pub round_schedule_summary: String,
    pub status: GameEventStatus,
    pub going_count: u8,
    /// Open FCFS seats remaining (0 when 8 going).
    pub seats_left: u8,
    pub waitlisted_count: u8,
    /// Remaining waitlist slots (0 when 5 waitlisted).
    pub waitlist_left: u8,
    /// Set once the host opens a live lobby.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub room_code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub room_id: Option<RoomId>,
    /// First names only on the public page.
    pub going_names: Vec<String>,
    #[serde(default)]
    pub waitlisted_names: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRsvpRequest {
    pub display_name: String,
    pub mobile: String,
    /// Consent to be contacted about this game (stored for future messaging).
    #[serde(default)]
    pub contact_consent: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRsvpResponse {
    pub rsvp_id: RsvpId,
    /// Opaque token to cancel this RSVP.
    pub rsvp_token: String,
    /// `going` or `waitlisted`.
    pub rsvp_status: String,
    /// 1-based position in the waitlist when `rsvp_status == waitlisted`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub waitlist_position: Option<u8>,
    pub event: GameEventPublicView,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CancelRsvpRequest {
    pub rsvp_token: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CancelRsvpResponse {
    pub event: GameEventPublicView,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub promoted_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RsvpHostView {
    pub rsvp_id: RsvpId,
    pub display_name: String,
    pub mobile_e164: String,
    /// `going` or `waitlisted`.
    pub status: String,
    pub contact_consent: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameEventManageView {
    pub event: GameEventPublicView,
    pub rsvps: Vec<RsvpHostView>,
    pub share_text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpenLobbyResponse {
    pub event: GameEventPublicView,
    pub room: RoomView,
    pub player_id: PlayerId,
    /// `comfort` | `busy` | `full` — soft signal when tables are congested.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capacity: Option<String>,
}

