use std::collections::HashMap;
use std::sync::atomic::AtomicUsize;
use std::sync::{Arc, Mutex};

use axum::http::HeaderMap;
use chrono::{DateTime, Utc};
use dehla_domain::{
    team_for_seat, GameId, PartnershipMode, PlayerId, RoomId, RulePack, SessionId, TensTieRule,
    TrumpMethod, TABLE_SEATS,
};
use dehla_persistence::{GameStore, MemoryStore};
use dehla_protocol::{RoomPhase, RoomView, SeatView};
use rand::distr::Alphanumeric;
use rand::Rng;
use tokio::sync::mpsc;
use uuid::Uuid;

use crate::actor::ActorMessage;
use crate::error::ApiError;
use crate::metrics::Metrics;

#[derive(Debug, Clone)]
pub struct Session {
    pub id: SessionId,
    pub nickname: String,
    pub token: String,
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone)]
pub struct RoomSeat {
    pub session_id: SessionId,
    pub player_id: PlayerId,
    pub nickname: String,
    pub seat: u8,
    pub ready: bool,
    pub joined_at: DateTime<Utc>,
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoomStatus {
    Lobby,
    Partnership,
    InGame(GameId),
}

#[derive(Debug)]
pub struct Room {
    pub id: RoomId,
    pub code: String,
    pub host_session: SessionId,
    pub seats: Vec<RoomSeat>,
    pub status: RoomStatus,
    pub rule_pack: RulePack,
    pub trump_method: TrumpMethod,
    pub partnership_mode: PartnershipMode,
    pub tens_tie_rule: TensTieRule,
    pub kots_to_win: u8,
    /// When ChoosePartners: pairs confirmed.
    pub partners_confirmed: bool,
}

impl Room {
    pub fn view(&self) -> RoomView {
        let (phase, game_id) = match self.status {
            RoomStatus::Lobby => (RoomPhase::Lobby, None),
            RoomStatus::Partnership => (RoomPhase::Partnership, None),
            RoomStatus::InGame(g) => (RoomPhase::InGame, Some(g)),
        };
        let mut seats: Vec<SeatView> = self
            .seats
            .iter()
            .map(|s| SeatView {
                player_id: s.player_id,
                nickname: s.nickname.clone(),
                seat: s.seat,
                ready: s.ready,
                is_host: s.session_id == self.host_session,
                team: if self.partners_confirmed || matches!(self.status, RoomStatus::InGame(_)) {
                    Some(match team_for_seat(s.seat) {
                        dehla_domain::TeamId::A => "A".into(),
                        dehla_domain::TeamId::B => "B".into(),
                    })
                } else {
                    None
                },
                avatar_id: s.avatar_id.clone(),
            })
            .collect();
        seats.sort_by_key(|s| s.seat);
        RoomView {
            room_id: self.id,
            code: self.code.clone(),
            phase,
            game_id,
            rule_pack: self.rule_pack,
            trump_method: self.trump_method,
            partnership_mode: self.partnership_mode,
            tens_tie_rule: self.tens_tie_rule,
            kots_to_win: self.kots_to_win,
            seats,
        }
    }

    pub fn seat_of(&self, session_id: SessionId) -> Option<&RoomSeat> {
        self.seats.iter().find(|s| s.session_id == session_id)
    }
}

#[derive(Debug, Clone)]
pub struct GameInfo {
    pub room_id: RoomId,
    pub players: HashMap<SessionId, PlayerId>,
    pub commands: mpsc::Sender<ActorMessage>,
}

pub struct AppState {
    pub sessions: Mutex<HashMap<SessionId, Session>>,
    pub tokens: Mutex<HashMap<String, SessionId>>,
    pub rooms: Mutex<HashMap<RoomId, Room>>,
    pub room_codes: Mutex<HashMap<String, RoomId>>,
    pub games: Mutex<HashMap<GameId, GameInfo>>,
    pub store: Arc<dyn GameStore>,
    pub metrics: Arc<Metrics>,
    pub ws_count: AtomicUsize,
}

impl AppState {
    pub fn new(store: Arc<dyn GameStore>) -> Arc<Self> {
        Arc::new(Self {
            sessions: Mutex::default(),
            tokens: Mutex::default(),
            rooms: Mutex::default(),
            room_codes: Mutex::default(),
            games: Mutex::default(),
            store,
            metrics: Arc::new(Metrics::new()),
            ws_count: AtomicUsize::new(0),
        })
    }

    pub fn memory() -> Arc<Self> {
        Self::new(Arc::new(MemoryStore::new()))
    }

    pub fn session_from_headers(&self, headers: &HeaderMap) -> Result<Session, ApiError> {
        let token = headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or_else(ApiError::unauthorized)?;
        let sid = self
            .tokens
            .lock()
            .unwrap()
            .get(token)
            .copied()
            .ok_or_else(ApiError::unauthorized)?;
        self.sessions
            .lock()
            .unwrap()
            .get(&sid)
            .cloned()
            .ok_or_else(ApiError::unauthorized)
    }

    pub fn resolve_room_id(&self, room_ref: &str) -> Result<RoomId, ApiError> {
        if let Ok(id) = Uuid::parse_str(room_ref) {
            return Ok(id);
        }
        let code = room_ref.to_ascii_uppercase();
        self.room_codes
            .lock()
            .unwrap()
            .get(&code)
            .copied()
            .ok_or_else(|| ApiError::not_found("room not found"))
    }
}

pub fn generate_room_code() -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    let mut rng = rand::rng();
    (0..6)
        .map(|_| {
            let i = rng.random_range(0..ALPHABET.len());
            ALPHABET[i] as char
        })
        .collect()
}

pub fn generate_token() -> String {
    rand::rng()
        .sample_iter(&Alphanumeric)
        .take(48)
        .map(char::from)
        .collect()
}

pub fn validate_nickname(raw: &str) -> Result<String, ApiError> {
    let n = raw.trim();
    if n.is_empty() || n.len() > 24 {
        return Err(ApiError::bad("INVALID_NICKNAME", "nickname must be 1–24 chars"));
    }
    Ok(n.to_string())
}

pub const SEATS: u8 = TABLE_SEATS;
