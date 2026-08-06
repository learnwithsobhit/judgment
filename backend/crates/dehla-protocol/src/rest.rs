use dehla_domain::{
    GameId, PartnershipMode, PlayerId, RoomId, RulePack, SessionId, TensTieRule, TrumpMethod,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthResponse {
    pub ok: bool,
    pub service: &'static str,
    pub protocol_version: u16,
}

impl HealthResponse {
    pub fn ok() -> Self {
        Self {
            ok: true,
            service: "dehla-server",
            protocol_version: crate::PROTOCOL_VERSION,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateGuestSessionRequest {
    pub nickname: String,
    #[serde(default)]
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateGuestSessionResponse {
    pub session_id: SessionId,
    pub nickname: String,
    pub token: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRoomRequest {
    #[serde(default)]
    pub rule_pack: RulePack,
    #[serde(default)]
    pub trump_method: TrumpMethod,
    #[serde(default)]
    pub partnership_mode: PartnershipMode,
    #[serde(default)]
    pub tens_tie_rule: TensTieRule,
    /// First to N Kots (default 1 = Quick).
    #[serde(default = "default_kots")]
    pub kots_to_win: u8,
}

fn default_kots() -> u8 {
    1
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRoomResponse {
    pub room: RoomView,
    pub player_id: PlayerId,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct JoinRoomRequest {
    /// Optional reclaim hint when joining an in-progress game (ADR 0004):
    /// preferred vacant `player_id` if the client still holds a reclaim store.
    /// Lobby joins ignore this field.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub player_id: Option<PlayerId>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ClaimSeatRequest {
    /// Optional specific vacant `player_id`; omitted ⇒ nickname match or first vacant.
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
pub struct JoinRoomResponse {
    pub room: RoomView,
    pub player_id: PlayerId,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReadyRequest {
    pub ready: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetPartnershipRequest {
    pub mode: PartnershipMode,
    /// Required when mode is ChoosePartners: two pairs of player ids.
    pub pairs: Option<Vec<[PlayerId; 2]>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StartGameResponse {
    pub game_id: GameId,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EndGameResponse {
    pub game_id: GameId,
    pub aborted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RestartGameResponse {
    pub old_game_id: GameId,
    /// Present when the host restart could auto-start (4 seated).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub game_id: Option<GameId>,
    /// True when leavers were dropped and remaining players returned to lobby.
    #[serde(default)]
    pub returned_to_lobby: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RoomPhase {
    Lobby,
    Partnership,
    InGame,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SeatView {
    pub player_id: PlayerId,
    pub nickname: String,
    pub seat: u8,
    pub ready: bool,
    pub is_host: bool,
    pub team: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomView {
    pub room_id: RoomId,
    pub code: String,
    pub phase: RoomPhase,
    pub game_id: Option<GameId>,
    pub rule_pack: RulePack,
    pub trump_method: TrumpMethod,
    pub partnership_mode: PartnershipMode,
    pub tens_tie_rule: TensTieRule,
    pub kots_to_win: u8,
    pub seats: Vec<SeatView>,
}
