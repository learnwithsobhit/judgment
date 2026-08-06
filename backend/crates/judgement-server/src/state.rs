//! In-memory application state: sessions, rooms, running games.
//!
//! Phase 3 keeps everything in memory; PostgreSQL persistence and recovery
//! arrive in Phase 5.

use std::collections::HashMap;
use std::sync::Arc;
use std::sync::Mutex;
use std::time::Instant;

use axum::http::HeaderMap;
use rand::distr::Alphanumeric;
use rand::Rng;
use tokio::sync::mpsc;

use judgement_ai::ExplanationService;
use chrono::{DateTime, Utc};
use judgement_domain::{
    EventId, GameId, PlayerId, RoomId, RoundSchedule, RsvpId, SessionId, Suit, MIN_PLAYERS,
};
use judgement_persistence::GameStore;
use judgement_protocol::{GameEventStatus, RoomPhase, RoomView, SeatView};

use crate::actor::ActorMessage;
use crate::error::ApiError;
use crate::http_limit::{HttpLimitConfig, HttpRateLimiter};
use crate::metrics::Metrics;

#[derive(Debug, Clone)]
pub struct Session {
    pub id: SessionId,
    pub nickname: String,
    /// Opaque bearer token. Never logged (PLAN.md §22).
    pub token: String,
    /// Built-in avatar pack id (cosmetic).
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone)]
pub struct RoomSeat {
    pub session_id: SessionId,
    pub player_id: PlayerId,
    pub nickname: String,
    pub seat: u8,
    pub ready: bool,
    /// Connection order, used for host promotion (locked decision 5).
    pub joined_at: DateTime<Utc>,
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RoomStatus {
    Lobby,
    InGame(GameId),
}

#[derive(Debug)]
pub struct Room {
    pub id: RoomId,
    pub code: String,
    pub host_session: SessionId,
    pub seats: Vec<RoomSeat>,
    pub status: RoomStatus,
    /// Table size chosen by the host, 3–8.
    pub max_players: u8,
    /// `None` disables the turn timer (ADR 0003).
    pub turn_timeout_seconds: Option<u16>,
    /// `None` ⇒ revealed-card trump; `Some` ⇒ rotation from this suit
    /// (or `trump_cycle[0]` when a custom cycle is set).
    pub first_trump: Option<Suit>,
    /// Custom 4-suit cycle when set; `None` ⇒ legacy first_trump / reveal.
    pub trump_cycle: Option<Vec<Suit>>,
    /// Resolved into `GameRules.round_pattern` at start.
    pub round_schedule: RoundSchedule,
    /// Classic Oh Hell: dealer cannot make totals equal tricks (default off).
    pub dealer_total_restriction: bool,
}

impl Room {
    pub fn seat_of(&self, session_id: SessionId) -> Option<&RoomSeat> {
        self.seats.iter().find(|s| s.session_id == session_id)
    }

    pub fn view(&self) -> RoomView {
        let (phase, game_id) = match self.status {
            RoomStatus::Lobby => (RoomPhase::Lobby, None),
            RoomStatus::InGame(game_id) => (RoomPhase::InGame, Some(game_id)),
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
                avatar_id: s.avatar_id.clone(),
                vacant: false,
            })
            .collect();
        seats.sort_by_key(|s| s.seat);
        RoomView {
            room_id: self.id,
            code: self.code.clone(),
            phase,
            game_id,
            max_players: self.max_players,
            min_players: MIN_PLAYERS,
            turn_timeout_seconds: self.turn_timeout_seconds,
            first_trump: self.first_trump,
            trump_cycle: self.trump_cycle.clone(),
            round_schedule: self.round_schedule.clone(),
            round_schedule_summary: self.round_schedule.summary(self.max_players),
            dealer_total_restriction: self.dealer_total_restriction,
            seats,
        }
    }
}

/// Handle to a running game actor plus the session → player mapping used to
/// authorise WebSocket connections.
#[derive(Debug, Clone)]
pub struct GameInfo {
    pub room_id: RoomId,
    pub players: HashMap<SessionId, PlayerId>,
    pub commands: mpsc::Sender<ActorMessage>,
}

#[derive(Debug, Clone)]
pub struct EventRsvp {
    pub id: RsvpId,
    pub display_name: String,
    pub mobile_e164: String,
    pub status: String,
    pub manage_token_hash: String,
    pub contact_consent: bool,
    pub created_at: DateTime<Utc>,
}

/// In-memory scheduled meetup (ADR 0005).
#[derive(Debug, Clone)]
pub struct ScheduledEvent {
    pub id: EventId,
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
    pub trump_cycle: Option<Vec<Suit>>,
    pub round_schedule: RoundSchedule,
    pub status: GameEventStatus,
    pub room_id: Option<RoomId>,
    pub rsvps: Vec<EventRsvp>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

pub struct AppState {
    pub sessions: Mutex<HashMap<SessionId, Session>>,
    pub tokens: Mutex<HashMap<String, SessionId>>,
    pub rooms: Mutex<HashMap<RoomId, Room>>,
    pub room_codes: Mutex<HashMap<String, RoomId>>,
    pub games: Mutex<HashMap<GameId, GameInfo>>,
    /// Scheduled meetups keyed by event id (ADR 0005).
    pub events: Mutex<HashMap<EventId, ScheduledEvent>>,
    /// Durable store. Always present — `MemoryStore` when DATABASE_URL is unset.
    pub store: Arc<dyn GameStore>,
    /// Deterministic FAQ / reason-code explanations (Phase 7). Optional RAG (7b).
    /// Never blocks gameplay.
    pub explanations: Arc<ExplanationService>,
    pub http_limiter: HttpRateLimiter,
    pub metrics: Arc<Metrics>,
    /// Approximate active WebSocket count (Phase 9 gauges).
    pub active_websockets: std::sync::atomic::AtomicU64,
    /// Per-room last host-restart time (load guard).
    pub restart_limits: Mutex<HashMap<RoomId, Instant>>,
}

impl AppState {
    pub fn new(store: Arc<dyn GameStore>) -> Self {
        Self::with_explanations(store, ExplanationService::default())
    }

    pub fn with_explanations(store: Arc<dyn GameStore>, explanations: ExplanationService) -> Self {
        Self {
            sessions: Mutex::default(),
            tokens: Mutex::default(),
            rooms: Mutex::default(),
            room_codes: Mutex::default(),
            games: Mutex::default(),
            events: Mutex::default(),
            store,
            explanations: Arc::new(explanations),
            http_limiter: HttpRateLimiter::new(HttpLimitConfig::default()),
            metrics: Arc::new(Metrics::default()),
            active_websockets: std::sync::atomic::AtomicU64::new(0),
            restart_limits: Mutex::default(),
        }
    }

    pub fn create_session(&self, nickname: String) -> Session {
        let session = Session {
            id: SessionId::new(),
            nickname,
            token: generate_token(),
            avatar_id: None,
        };
        self.sessions.lock().unwrap().insert(session.id, session.clone());
        self.tokens.lock().unwrap().insert(session.token.clone(), session.id);
        session
    }

    /// Persist a built-in avatar choice on the guest session (and any lobby seat).
    pub fn set_avatar(&self, session_id: SessionId, avatar_id: String) -> Option<String> {
        {
            let mut sessions = self.sessions.lock().unwrap();
            let session = sessions.get_mut(&session_id)?;
            session.avatar_id = Some(avatar_id.clone());
        }
        let mut rooms = self.rooms.lock().unwrap();
        for room in rooms.values_mut() {
            if let Some(seat) = room.seats.iter_mut().find(|s| s.session_id == session_id) {
                seat.avatar_id = Some(avatar_id.clone());
            }
        }
        Some(avatar_id)
    }

    /// Resolve the bearer token from `Authorization: Bearer <token>`.
    pub fn authenticate(&self, headers: &HeaderMap) -> Result<Session, ApiError> {
        let token = headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or(ApiError::Unauthorized)?;
        self.session_for_token(token).ok_or(ApiError::Unauthorized)
    }

    pub fn session_for_token(&self, token: &str) -> Option<Session> {
        let session_id = *self.tokens.lock().unwrap().get(token)?;
        self.sessions.lock().unwrap().get(&session_id).cloned()
    }

    /// Rotate the bearer token for a session (PLAN.md §15.1). Returns the new
    /// token; the previous token is invalidated immediately.
    pub fn rotate_token(&self, session_id: SessionId) -> Option<String> {
        let mut sessions = self.sessions.lock().unwrap();
        let mut tokens = self.tokens.lock().unwrap();
        let session = sessions.get_mut(&session_id)?;
        tokens.remove(&session.token);
        let new_token = generate_token();
        session.token = new_token.clone();
        tokens.insert(new_token.clone(), session_id);
        Some(new_token)
    }

    /// Resolve a room by UUID or by join code.
    pub fn resolve_room_id(&self, room_ref: &str) -> Option<RoomId> {
        if let Ok(uuid) = room_ref.parse::<uuid::Uuid>() {
            return Some(RoomId(uuid));
        }
        self.room_codes
            .lock()
            .unwrap()
            .get(&room_ref.to_ascii_uppercase())
            .copied()
    }
}

pub fn generate_token() -> String {
    rand::rng()
        .sample_iter(&Alphanumeric)
        .take(48)
        .map(char::from)
        .collect()
}

/// Six characters, skipping easily-confused ones (0/O, 1/I/L).
pub fn generate_room_code() -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    let mut rng = rand::rng();
    (0..6)
        .map(|_| ALPHABET[rng.random_range(0..ALPHABET.len())] as char)
        .collect()
}
