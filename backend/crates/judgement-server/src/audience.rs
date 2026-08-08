//! Audience / spectator rate limits, caps, and feature flags.

use std::collections::HashMap;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use judgement_domain::SessionId;

/// Global hard cap on connected spectator WebSockets (separate from player WS).
pub const DEFAULT_HARD_SPECTATOR_WEBSOCKETS: u64 = 150;
/// Max watchers attached to a single game actor.
pub const DEFAULT_MAX_SPECTATORS_PER_GAME: usize = 25;

pub const SPECTATOR_BUFFER_CAPACITY: usize = 32;

pub const AUDIENCE_COMMENT_COOLDOWN: Duration = Duration::from_secs(2);
pub const AUDIENCE_REACTION_COOLDOWN: Duration = Duration::from_secs(2);
pub const AUDIENCE_VOICE_COOLDOWN: Duration = Duration::from_secs(15);
pub const AUDIENCE_PREDICTION_COOLDOWN: Duration = Duration::from_secs(1);

pub const AUDIENCE_ROOM_COMMENT_WINDOW: Duration = Duration::from_secs(10);
pub const AUDIENCE_ROOM_COMMENT_CAP: u32 = 30;
pub const AUDIENCE_ROOM_REACTION_WINDOW: Duration = Duration::from_secs(10);
pub const AUDIENCE_ROOM_REACTION_CAP: u32 = 20;
pub const AUDIENCE_ROOM_VOICE_WINDOW: Duration = Duration::from_secs(30);
pub const AUDIENCE_ROOM_VOICE_CAP: u32 = 4;
pub const AUDIENCE_ROOM_PREDICTION_WINDOW: Duration = Duration::from_secs(10);
pub const AUDIENCE_ROOM_PREDICTION_CAP: u32 = 60;

pub const MAX_AUDIENCE_COMMENT_LEN: usize = 120;
pub const MAX_AUDIENCE_VOICE_DURATION_MS: u32 = 4_000;
pub const MAX_AUDIENCE_VOICE_B64_BYTES: usize = 28_000;

pub const SPECTATOR_CAPACITY_MESSAGE: &str =
    "Too many people are watching right now. Please try again shortly.";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AudienceChannel {
    Comment,
    Reaction,
    Voice,
    Prediction,
}

impl AudienceChannel {
    pub fn as_str(self) -> &'static str {
        match self {
            AudienceChannel::Comment => "comment",
            AudienceChannel::Reaction => "reaction",
            AudienceChannel::Voice => "voice",
            AudienceChannel::Prediction => "prediction",
        }
    }
}

fn env_bool(key: &str, default: bool) -> bool {
    match std::env::var(key) {
        Ok(v) => matches!(
            v.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "on"
        ),
        Err(_) => default,
    }
}

fn env_u64(key: &str, default: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn env_usize(key: &str, default: usize) -> usize {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

#[derive(Debug, Clone, Copy)]
pub struct AudienceFlags {
    pub audience_enabled: bool,
    pub audience_voice_enabled: bool,
    pub live_now_enabled: bool,
    pub hard_spectator_websockets: u64,
    pub max_spectators_per_game: usize,
}

impl AudienceFlags {
    pub fn from_env() -> Self {
        Self {
            audience_enabled: env_bool("AUDIENCE_ENABLED", true),
            audience_voice_enabled: env_bool("AUDIENCE_VOICE_ENABLED", true),
            live_now_enabled: env_bool("LIVE_NOW_ENABLED", true),
            hard_spectator_websockets: env_u64(
                "JUDGEMENT_HARD_SPECTATOR_WEBSOCKETS",
                DEFAULT_HARD_SPECTATOR_WEBSOCKETS,
            ),
            max_spectators_per_game: env_usize(
                "JUDGEMENT_MAX_SPECTATORS_PER_GAME",
                DEFAULT_MAX_SPECTATORS_PER_GAME,
            ),
        }
    }
}

static FLAGS: OnceLock<AudienceFlags> = OnceLock::new();

pub fn flags() -> AudienceFlags {
    *FLAGS.get_or_init(AudienceFlags::from_env)
}

pub fn admit_spectator(global: u64, per_game: usize) -> Result<(), &'static str> {
    let f = flags();
    if !f.audience_enabled {
        return Err("audience watching is temporarily disabled");
    }
    if global >= f.hard_spectator_websockets {
        return Err(SPECTATOR_CAPACITY_MESSAGE);
    }
    if per_game >= f.max_spectators_per_game {
        return Err(SPECTATOR_CAPACITY_MESSAGE);
    }
    Ok(())
}

/// Sliding-window + per-session cooldown tracker for audience writes.
#[derive(Debug, Default)]
pub struct AudienceRateLimiter {
    last_by_session: HashMap<(SessionId, AudienceChannel), Instant>,
    room_hits: HashMap<AudienceChannel, Vec<Instant>>,
}

impl AudienceRateLimiter {
    pub fn check(
        &mut self,
        session_id: SessionId,
        channel: AudienceChannel,
    ) -> Result<(), AudienceChannel> {
        let now = Instant::now();
        let cooldown = match channel {
            AudienceChannel::Comment => AUDIENCE_COMMENT_COOLDOWN,
            AudienceChannel::Reaction => AUDIENCE_REACTION_COOLDOWN,
            AudienceChannel::Voice => AUDIENCE_VOICE_COOLDOWN,
            AudienceChannel::Prediction => AUDIENCE_PREDICTION_COOLDOWN,
        };
        let key = (session_id, channel);
        if let Some(last) = self.last_by_session.get(&key) {
            if now.duration_since(*last) < cooldown {
                return Err(channel);
            }
        }

        let (window, cap) = match channel {
            AudienceChannel::Comment => (AUDIENCE_ROOM_COMMENT_WINDOW, AUDIENCE_ROOM_COMMENT_CAP),
            AudienceChannel::Reaction => (AUDIENCE_ROOM_REACTION_WINDOW, AUDIENCE_ROOM_REACTION_CAP),
            AudienceChannel::Voice => (AUDIENCE_ROOM_VOICE_WINDOW, AUDIENCE_ROOM_VOICE_CAP),
            AudienceChannel::Prediction => (
                AUDIENCE_ROOM_PREDICTION_WINDOW,
                AUDIENCE_ROOM_PREDICTION_CAP,
            ),
        };
        let hits = self.room_hits.entry(channel).or_default();
        hits.retain(|t| now.duration_since(*t) < window);
        if hits.len() as u32 >= cap {
            return Err(channel);
        }

        hits.push(now);
        self.last_by_session.insert(key, now);
        Ok(())
    }
}
