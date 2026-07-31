//! Scheduled game events (ADR 0005): RSVP meetups + ICS calendar export.

use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue};
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Duration, Utc};
use judgement_domain::{
    EventId, PlayerId, RoomId, RsvpId, EVENT_SEAT_CAP, EVENT_WAITLIST_CAP, MAX_PLAYERS, MIN_PLAYERS,
};
use judgement_persistence::{StoredEventRsvp, StoredScheduledEvent};
use judgement_protocol::{
    CancelRsvpRequest, CancelRsvpResponse, CreateGameEventRequest, CreateGameEventResponse,
    CreateRsvpRequest, CreateRsvpResponse, GameEventManageView, GameEventPublicView,
    GameEventStatus, OpenLobbyResponse, RsvpHostView,
};
use rand::distr::Alphanumeric;
use rand::Rng;
use sha2::{Digest, Sha256};

use crate::error::ApiError;
use crate::persist::stored_room;
use crate::state::{generate_room_code, AppState, Room, RoomSeat, RoomStatus, ScheduledEvent};

pub fn hash_token(token: &str) -> String {
    let digest = Sha256::digest(token.as_bytes());
    hex::encode(digest)
}

pub fn generate_secret() -> String {
    rand::rng()
        .sample_iter(&Alphanumeric)
        .take(40)
        .map(char::from)
        .collect()
}

pub fn generate_slug() -> String {
    const ALPHABET: &[u8] = b"abcdefghjkmnpqrstuvwxyz23456789";
    let mut rng = rand::rng();
    (0..8)
        .map(|_| ALPHABET[rng.random_range(0..ALPHABET.len())] as char)
        .collect()
}

/// India-friendly mobile normalisation → E.164.
pub fn normalize_mobile(raw: &str) -> Result<String, ApiError> {
    let trimmed = raw.trim();
    let digits: String = trimmed.chars().filter(|c| c.is_ascii_digit()).collect();
    let e164 = if trimmed.starts_with('+') {
        format!("+{digits}")
    } else if digits.len() == 10 && digits.chars().next().is_some_and(|c| matches!(c, '6'..='9')) {
        format!("+91{digits}")
    } else if digits.len() == 12 && digits.starts_with("91") {
        format!("+{digits}")
    } else if digits.len() >= 10 && digits.len() <= 15 {
        format!("+{digits}")
    } else {
        return Err(ApiError::BadRequest(
            "mobile must be a valid phone number (10-digit India or E.164)".into(),
        ));
    };
    if e164.len() < 12 || e164.len() > 16 {
        return Err(ApiError::BadRequest("mobile number length is invalid".into()));
    }
    Ok(e164)
}

fn status_from_str(s: &str) -> GameEventStatus {
    match s {
        "lobby_open" => GameEventStatus::LobbyOpen,
        "started" => GameEventStatus::Started,
        "cancelled" => GameEventStatus::Cancelled,
        "expired" => GameEventStatus::Expired,
        _ => GameEventStatus::Open,
    }
}

fn status_to_str(s: GameEventStatus) -> &'static str {
    match s {
        GameEventStatus::Open => "open",
        GameEventStatus::LobbyOpen => "lobby_open",
        GameEventStatus::Started => "started",
        GameEventStatus::Cancelled => "cancelled",
        GameEventStatus::Expired => "expired",
    }
}

impl ScheduledEvent {
    pub fn going_rsvps(&self) -> impl Iterator<Item = &crate::state::EventRsvp> {
        self.rsvps.iter().filter(|r| r.status == "going")
    }

    pub fn waitlisted_rsvps(&self) -> impl Iterator<Item = &crate::state::EventRsvp> {
        self.rsvps.iter().filter(|r| r.status == "waitlisted")
    }

    pub fn public_view(&self, room_code: Option<String>) -> GameEventPublicView {
        let mut going: Vec<_> = self.going_rsvps().collect();
        going.sort_by_key(|r| r.created_at);
        let mut waitlisted: Vec<_> = self.waitlisted_rsvps().collect();
        waitlisted.sort_by_key(|r| r.created_at);
        let going_count = going.len() as u8;
        let waitlisted_count = waitlisted.len() as u8;
        GameEventPublicView {
            event_id: self.id,
            slug: self.slug.clone(),
            title: self.title.clone(),
            host_nickname: self.host_nickname.clone(),
            starts_at: self.starts_at,
            timezone: self.timezone.clone(),
            duration_minutes: self.duration_minutes,
            max_players: EVENT_SEAT_CAP,
            turn_timeout_seconds: self.turn_timeout_seconds,
            first_trump: self.first_trump,
            round_schedule: self.round_schedule.clone(),
            // Summary for the eventual lobby size (going, or seat cap if empty).
            round_schedule_summary: self.round_schedule.summary(
                going_count.clamp(MIN_PLAYERS, EVENT_SEAT_CAP).max(MIN_PLAYERS),
            ),
            status: self.status,
            going_count,
            seats_left: EVENT_SEAT_CAP.saturating_sub(going_count),
            waitlisted_count,
            waitlist_left: EVENT_WAITLIST_CAP.saturating_sub(waitlisted_count),
            room_code,
            room_id: self.room_id,
            going_names: going.iter().map(|r| r.display_name.clone()).collect(),
            waitlisted_names: waitlisted.iter().map(|r| r.display_name.clone()).collect(),
        }
    }

    pub fn share_text(&self, origin: &str) -> String {
        let when = format_starts_at_in_timezone(self.starts_at, &self.timezone);
        format!(
            "Judgement on {when}\n{}\nRSVP (up to {EVENT_SEAT_CAP} players, {EVENT_WAITLIST_CAP} waitlist): {origin}/e/{}\nAdd to calendar from that page for a reminder.",
            self.title, self.slug
        )
    }

    pub fn to_stored(&self) -> StoredScheduledEvent {
        StoredScheduledEvent {
            event_id: self.id,
            slug: self.slug.clone(),
            manage_token_hash: self.manage_token_hash.clone(),
            host_nickname: self.host_nickname.clone(),
            host_session_id: self.host_session_id,
            title: self.title.clone(),
            starts_at: self.starts_at,
            timezone: self.timezone.clone(),
            duration_minutes: self.duration_minutes,
            max_players: self.max_players,
            turn_timeout_seconds: self.turn_timeout_seconds,
            first_trump: self.first_trump,
            round_schedule: self.round_schedule.clone(),
            status: status_to_str(self.status).into(),
            room_id: self.room_id,
            rsvps: self
                .rsvps
                .iter()
                .map(|r| StoredEventRsvp {
                    rsvp_id: r.id,
                    display_name: r.display_name.clone(),
                    mobile_e164: r.mobile_e164.clone(),
                    status: r.status.clone(),
                    manage_token_hash: r.manage_token_hash.clone(),
                    contact_consent: r.contact_consent,
                    created_at: r.created_at,
                })
                .collect(),
            created_at: self.created_at,
            updated_at: self.updated_at,
        }
    }

    pub fn from_stored(stored: StoredScheduledEvent) -> Self {
        Self {
            id: stored.event_id,
            slug: stored.slug,
            manage_token_hash: stored.manage_token_hash,
            host_nickname: stored.host_nickname,
            host_session_id: stored.host_session_id,
            title: stored.title,
            starts_at: stored.starts_at,
            timezone: stored.timezone,
            duration_minutes: stored.duration_minutes,
            max_players: stored.max_players,
            turn_timeout_seconds: stored.turn_timeout_seconds,
            first_trump: stored.first_trump,
            round_schedule: stored.round_schedule,
            status: status_from_str(&stored.status),
            room_id: stored.room_id,
            rsvps: stored
                .rsvps
                .into_iter()
                .map(|r| crate::state::EventRsvp {
                    id: r.rsvp_id,
                    display_name: r.display_name,
                    mobile_e164: r.mobile_e164,
                    status: r.status,
                    manage_token_hash: r.manage_token_hash,
                    contact_consent: r.contact_consent,
                    created_at: r.created_at,
                })
                .collect(),
            created_at: stored.created_at,
            updated_at: stored.updated_at,
        }
    }
}

fn format_starts_at_in_timezone(starts_at: DateTime<Utc>, timezone: &str) -> String {
    match timezone.parse::<chrono_tz::Tz>() {
        Ok(tz) => {
            let local = starts_at.with_timezone(&tz);
            format!("{} ({timezone})", local.format("%a %d %b %Y %H:%M"))
        }
        Err(_) => {
            format!("{} UTC ({timezone})", starts_at.format("%a %d %b %Y %H:%M"))
        }
    }
}

fn public_origin() -> String {
    std::env::var("PUBLIC_WEB_ORIGIN").unwrap_or_else(|_| "http://localhost:3000".into())
}

/// Prefer `PUBLIC_WEB_ORIGIN`, then the browser `Origin` header (Flutter web
/// random ports), then the default localhost:3000.
fn resolve_public_origin(headers: &HeaderMap) -> String {
    if let Ok(origin) = std::env::var("PUBLIC_WEB_ORIGIN") {
        if !origin.is_empty() {
            return origin;
        }
    }
    if let Some(origin) = headers
        .get(axum::http::header::ORIGIN)
        .and_then(|v| v.to_str().ok())
        .filter(|o| !o.is_empty())
    {
        return origin.to_string();
    }
    if let Some(referer) = headers
        .get(axum::http::header::REFERER)
        .and_then(|v| v.to_str().ok())
        .and_then(|r| url_origin(r))
    {
        return referer;
    }
    public_origin()
}

fn url_origin(url: &str) -> Option<String> {
    let rest = url.split_once("://")?;
    let scheme = rest.0;
    let host_path = rest.1;
    let host = host_path.split('/').next().filter(|h| !h.is_empty())?;
    Some(format!("{scheme}://{host}"))
}

fn extract_manage_token(headers: &HeaderMap, query_token: Option<&str>) -> Result<String, ApiError> {
    if let Some(t) = query_token.filter(|s| !s.is_empty()) {
        return Ok(t.to_string());
    }
    headers
        .get("x-manage-token")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string())
        .ok_or_else(|| ApiError::Unauthorized)
}

fn require_host(event: &ScheduledEvent, token: &str) -> Result<(), ApiError> {
    if hash_token(token) != event.manage_token_hash {
        return Err(ApiError::Forbidden("invalid manage token".into()));
    }
    Ok(())
}

async fn persist_event(state: &AppState, event: &ScheduledEvent) -> Result<(), ApiError> {
    state
        .store
        .upsert_scheduled_event(&event.to_stored())
        .await
        .map_err(|e| ApiError::Conflict(format!("persist event: {e}")))
}

fn room_code_for(state: &AppState, room_id: Option<RoomId>) -> Option<String> {
    let room_id = room_id?;
    state.rooms.lock().unwrap().get(&room_id).map(|r| r.code.clone())
}

pub async fn create_event(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<CreateGameEventRequest>,
) -> Result<Json<CreateGameEventResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let title = body.title.trim().to_string();
    if title.is_empty() || title.chars().count() > 80 {
        return Err(ApiError::BadRequest("title must be 1-80 characters".into()));
    }
    let timezone = body.timezone.trim().to_string();
    if timezone.is_empty() || timezone.len() > 64 {
        return Err(ApiError::BadRequest("timezone is required".into()));
    }
    let min_start = Utc::now() + Duration::minutes(15);
    if body.starts_at < min_start {
        return Err(ApiError::BadRequest(
            "starts_at must be at least 15 minutes in the future".into(),
        ));
    }
    if !(30..=240).contains(&body.duration_minutes) {
        return Err(ApiError::BadRequest(
            "duration_minutes must be between 30 and 240".into(),
        ));
    }
    // Host no longer chooses table size; seat pool is always EVENT_SEAT_CAP.
    let _ = body.max_players;
    let turn_timeout_seconds = body.turn_timeout_seconds.map(|t| t.clamp(5, 300));
    let round_schedule = body.round_schedule.unwrap_or_default();
    // Validate deal schedule against the largest possible table (8).
    round_schedule
        .resolve_pattern(EVENT_SEAT_CAP, body.first_trump.is_none())
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    let manage_token = generate_secret();
    let mut slug = generate_slug();
    {
        let events = state.events.lock().unwrap();
        while events.values().any(|e| e.slug == slug) {
            slug = generate_slug();
        }
    }

    let now = Utc::now();
    let event = ScheduledEvent {
        id: EventId::new(),
        slug: slug.clone(),
        manage_token_hash: hash_token(&manage_token),
        host_nickname: session.nickname.clone(),
        host_session_id: Some(session.id),
        title,
        starts_at: body.starts_at,
        timezone,
        duration_minutes: body.duration_minutes,
        max_players: EVENT_SEAT_CAP,
        turn_timeout_seconds,
        first_trump: body.first_trump,
        round_schedule,
        status: GameEventStatus::Open,
        room_id: None,
        rsvps: Vec::new(),
        created_at: now,
        updated_at: now,
    };
    let view = event.public_view(None);
    persist_event(&state, &event).await?;
    state.events.lock().unwrap().insert(event.id, event);

    Ok(Json(CreateGameEventResponse {
        event: view,
        manage_token,
        manage_path: format!("/e/{slug}/manage"),
        invite_path: format!("/e/{slug}"),
    }))
}

pub async fn get_event(
    State(state): State<Arc<AppState>>,
    Path(slug): Path<String>,
) -> Result<Json<GameEventPublicView>, ApiError> {
    let events = state.events.lock().unwrap();
    let event = events
        .values()
        .find(|e| e.slug == slug)
        .ok_or(ApiError::NotFound("event"))?;
    let code = room_code_for(&state, event.room_id);
    Ok(Json(event.public_view(code)))
}

pub async fn create_rsvp(
    State(state): State<Arc<AppState>>,
    Path(slug): Path<String>,
    Json(body): Json<CreateRsvpRequest>,
) -> Result<Json<CreateRsvpResponse>, ApiError> {
    let display_name = body.display_name.trim().to_string();
    if display_name.is_empty() || display_name.chars().count() > 24 {
        return Err(ApiError::BadRequest(
            "display_name must be 1-24 characters".into(),
        ));
    }
    let mobile = normalize_mobile(&body.mobile)?;
    let rsvp_token = generate_secret();
    let rsvp_id = RsvpId::new();
    let now = Utc::now();

    let (view, stored, rsvp_status, waitlist_position) = {
        let mut events = state.events.lock().unwrap();
        let event = events
            .values_mut()
            .find(|e| e.slug == slug)
            .ok_or(ApiError::NotFound("event"))?;
        if event.status != GameEventStatus::Open {
            return Err(ApiError::Conflict(
                "this event is not accepting RSVPs".into(),
            ));
        }
        let grace_end = event.starts_at + Duration::hours(2);
        if Utc::now() > grace_end {
            event.status = GameEventStatus::Expired;
            event.updated_at = now;
            return Err(ApiError::Conflict("this event has expired".into()));
        }
        if event
            .rsvps
            .iter()
            .any(|r| r.mobile_e164 == mobile && (r.status == "going" || r.status == "waitlisted"))
        {
            return Err(ApiError::Conflict(
                "this mobile number is already registered".into(),
            ));
        }
        let going = event.going_rsvps().count() as u8;
        let waitlisted = event.waitlisted_rsvps().count() as u8;
        let (status, waitlist_position) = if going < EVENT_SEAT_CAP {
            ("going".to_string(), None)
        } else if waitlisted < EVENT_WAITLIST_CAP {
            ("waitlisted".to_string(), Some(waitlisted + 1))
        } else {
            return Err(ApiError::Conflict(
                "seats and waitlist are full (8 players + 5 waitlist)".into(),
            ));
        };
        event.rsvps.push(crate::state::EventRsvp {
            id: rsvp_id,
            display_name,
            mobile_e164: mobile,
            status: status.clone(),
            manage_token_hash: hash_token(&rsvp_token),
            contact_consent: body.contact_consent,
            created_at: now,
        });
        event.updated_at = now;
        (
            event.public_view(room_code_for(&state, event.room_id)),
            event.to_stored(),
            status,
            waitlist_position,
        )
    };
    state
        .store
        .upsert_scheduled_event(&stored)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist event: {e}")))?;

    Ok(Json(CreateRsvpResponse {
        rsvp_id,
        rsvp_token,
        rsvp_status,
        waitlist_position,
        event: view,
    }))
}

pub async fn cancel_rsvp(
    State(state): State<Arc<AppState>>,
    Path(slug): Path<String>,
    Json(body): Json<CancelRsvpRequest>,
) -> Result<Json<CancelRsvpResponse>, ApiError> {
    let token_hash = hash_token(body.rsvp_token.trim());
    let (view, stored, promoted_name) = {
        let mut events = state.events.lock().unwrap();
        let event = events
            .values_mut()
            .find(|e| e.slug == slug)
            .ok_or(ApiError::NotFound("event"))?;
        let rsvp_idx = event
            .rsvps
            .iter()
            .position(|r| {
                r.manage_token_hash == token_hash
                    && (r.status == "going" || r.status == "waitlisted")
            })
            .ok_or(ApiError::NotFound("rsvp"))?;
        let was_going = event.rsvps[rsvp_idx].status == "going";
        event.rsvps[rsvp_idx].status = "cancelled".into();
        let mut promoted_name = None;
        if was_going {
            if let Some(next) = event
                .rsvps
                .iter_mut()
                .filter(|r| r.status == "waitlisted")
                .min_by_key(|r| r.created_at)
            {
                next.status = "going".into();
                promoted_name = Some(next.display_name.clone());
            }
        }
        event.updated_at = Utc::now();
        (
            event.public_view(room_code_for(&state, event.room_id)),
            event.to_stored(),
            promoted_name,
        )
    };
    state
        .store
        .upsert_scheduled_event(&stored)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist event: {e}")))?;
    Ok(Json(CancelRsvpResponse {
        event: view,
        promoted_name,
    }))
}

#[derive(Debug, serde::Deserialize)]
pub struct ManageQuery {
    pub token: Option<String>,
}

pub async fn manage_event(
    State(state): State<Arc<AppState>>,
    Path(slug): Path<String>,
    Query(query): Query<ManageQuery>,
    headers: HeaderMap,
) -> Result<Json<GameEventManageView>, ApiError> {
    let token = extract_manage_token(&headers, query.token.as_deref())?;
    let events = state.events.lock().unwrap();
    let event = events
        .values()
        .find(|e| e.slug == slug)
        .ok_or(ApiError::NotFound("event"))?;
    require_host(event, &token)?;
    let code = room_code_for(&state, event.room_id);
    let origin = resolve_public_origin(&headers);
    let mut active: Vec<_> = event
        .rsvps
        .iter()
        .filter(|r| r.status == "going" || r.status == "waitlisted")
        .collect();
    active.sort_by(|a, b| {
        // Going first, then waitlisted; each group by created_at.
        match (a.status.as_str(), b.status.as_str()) {
            ("going", "waitlisted") => std::cmp::Ordering::Less,
            ("waitlisted", "going") => std::cmp::Ordering::Greater,
            _ => a.created_at.cmp(&b.created_at),
        }
    });
    Ok(Json(GameEventManageView {
        share_text: event.share_text(&origin),
        rsvps: active
            .into_iter()
            .map(|r| RsvpHostView {
                rsvp_id: r.id,
                display_name: r.display_name.clone(),
                mobile_e164: r.mobile_e164.clone(),
                status: r.status.clone(),
                contact_consent: r.contact_consent,
                created_at: r.created_at,
            })
            .collect(),
        event: event.public_view(code),
    }))
}

pub async fn cancel_event(
    State(state): State<Arc<AppState>>,
    Path(slug): Path<String>,
    Query(query): Query<ManageQuery>,
    headers: HeaderMap,
) -> Result<Json<GameEventPublicView>, ApiError> {
    let token = extract_manage_token(&headers, query.token.as_deref())?;
    let (view, stored) = {
        let mut events = state.events.lock().unwrap();
        let event = events
            .values_mut()
            .find(|e| e.slug == slug)
            .ok_or(ApiError::NotFound("event"))?;
        require_host(event, &token)?;
        if !matches!(event.status, GameEventStatus::Open) {
            return Err(ApiError::Conflict(
                "only open events can be cancelled".into(),
            ));
        }
        event.status = GameEventStatus::Cancelled;
        event.updated_at = Utc::now();
        (event.public_view(None), event.to_stored())
    };
    state
        .store
        .upsert_scheduled_event(&stored)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist event: {e}")))?;
    Ok(Json(view))
}

pub async fn open_lobby(
    State(state): State<Arc<AppState>>,
    Path(slug): Path<String>,
    Query(query): Query<ManageQuery>,
    headers: HeaderMap,
) -> Result<Json<OpenLobbyResponse>, ApiError> {
    let token = extract_manage_token(&headers, query.token.as_deref())?;
    let session = state.authenticate(&headers)?;

    let (event_id, max_players, turn_timeout_seconds, first_trump, round_schedule) = {
        let events = state.events.lock().unwrap();
        let event = events
            .values()
            .find(|e| e.slug == slug)
            .ok_or(ApiError::NotFound("event"))?;
        require_host(event, &token)?;
        if event.status != GameEventStatus::Open {
            return Err(ApiError::Conflict(
                "lobby can only be opened from an open event".into(),
            ));
        }
        let going = event.going_rsvps().count() as u8;
        if going < MIN_PLAYERS {
            return Err(ApiError::Conflict(format!(
                "need at least {MIN_PLAYERS} going RSVPs to open the lobby (currently {going})"
            )));
        }
        let max_players = going.min(MAX_PLAYERS);
        // Re-validate deal schedule for the actual lobby size.
        event
            .round_schedule
            .resolve_pattern(max_players, event.first_trump.is_none())
            .map_err(|e| {
                ApiError::Conflict(format!(
                    "round schedule is not valid for {max_players} going players: {e}"
                ))
            })?;
        (
            event.id,
            max_players,
            event.turn_timeout_seconds,
            event.first_trump,
            event.round_schedule.clone(),
        )
    };

    let room_id = RoomId::new();
    let player_id = PlayerId::new();
    let mut code = generate_room_code();
    {
        let mut codes = state.room_codes.lock().unwrap();
        while codes.contains_key(&code) {
            code = generate_room_code();
        }
        codes.insert(code.clone(), room_id);
    }

    let room = Room {
        id: room_id,
        code: code.clone(),
        host_session: session.id,
        seats: vec![RoomSeat {
            session_id: session.id,
            player_id,
            nickname: session.nickname.clone(),
            seat: 0,
            ready: false,
            joined_at: Utc::now(),
            avatar_id: session.avatar_id.clone(),
        }],
        status: RoomStatus::Lobby,
        max_players,
        turn_timeout_seconds,
        first_trump,
        round_schedule: round_schedule.clone(),
        dealer_total_restriction: false,
    };
    let room_view = room.view();
    state
        .store
        .upsert_room(&stored_room(&room))
        .await
        .map_err(|e| ApiError::Conflict(format!("persist room: {e}")))?;
    state.rooms.lock().unwrap().insert(room_id, room);

    let (event_view, stored) = {
        let mut events = state.events.lock().unwrap();
        let event = events.get_mut(&event_id).ok_or(ApiError::NotFound("event"))?;
        event.status = GameEventStatus::LobbyOpen;
        event.room_id = Some(room_id);
        event.host_session_id = Some(session.id);
        event.updated_at = Utc::now();
        (event.public_view(Some(code)), event.to_stored())
    };
    state
        .store
        .upsert_scheduled_event(&stored)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist event: {e}")))?;

    Ok(Json(OpenLobbyResponse {
        event: event_view,
        room: room_view,
        player_id,
    }))
}

#[derive(Debug, serde::Deserialize)]
pub struct CalendarQuery {
    pub rsvp: Option<String>,
}

pub async fn calendar_ics(
    State(state): State<Arc<AppState>>,
    Path(slug): Path<String>,
    Query(query): Query<CalendarQuery>,
    headers: HeaderMap,
) -> Result<impl IntoResponse, ApiError> {
    let events = state.events.lock().unwrap();
    let event = events
        .values()
        .find(|e| e.slug == slug)
        .ok_or(ApiError::NotFound("event"))?;
    if matches!(
        event.status,
        GameEventStatus::Cancelled | GameEventStatus::Expired
    ) {
        return Err(ApiError::Conflict("event is not active".into()));
    }

    let origin = resolve_public_origin(&headers);
    let url = format!("{origin}/e/{}", event.slug);
    let mut description = format!(
        "Judgement — RSVP and join at {}\\nHost: {}",
        url, event.host_nickname
    );
    if let Some(code) = room_code_for(&state, event.room_id) {
        description.push_str(&format!("\\nRoom code: {code}"));
    }
    if let Some(rsvp_token) = query.rsvp.as_deref() {
        let hash = hash_token(rsvp_token);
        if let Some(rsvp) = event
            .rsvps
            .iter()
            .find(|r| r.manage_token_hash == hash && r.status == "going")
        {
            description.push_str(&format!(
                "\\nYour RSVP: {} ({})",
                rsvp.display_name, rsvp.mobile_e164
            ));
        }
    }

    let end = event.starts_at + Duration::minutes(event.duration_minutes as i64);
    let dtstart = event.starts_at.format("%Y%m%dT%H%M%SZ");
    let dtend = end.format("%Y%m%dT%H%M%SZ");
    let dtstamp = Utc::now().format("%Y%m%dT%H%M%SZ");
    let uid = format!("{}@judgement", event.id);
    let summary = ics_escape(&event.title);

    let ics = format!(
        "BEGIN:VCALENDAR\r\n\
VERSION:2.0\r\n\
PRODID:-//Judgement//Scheduled Event//EN\r\n\
CALSCALE:GREGORIAN\r\n\
METHOD:PUBLISH\r\n\
BEGIN:VEVENT\r\n\
UID:{uid}\r\n\
DTSTAMP:{dtstamp}\r\n\
DTSTART:{dtstart}\r\n\
DTEND:{dtend}\r\n\
SUMMARY:{summary}\r\n\
DESCRIPTION:{description}\r\n\
URL:{url}\r\n\
BEGIN:VALARM\r\n\
TRIGGER:-PT1H\r\n\
ACTION:DISPLAY\r\n\
DESCRIPTION:Judgement starts in 1 hour\r\n\
END:VALARM\r\n\
BEGIN:VALARM\r\n\
TRIGGER:-PT1D\r\n\
ACTION:DISPLAY\r\n\
DESCRIPTION:Judgement tomorrow\r\n\
END:VALARM\r\n\
END:VEVENT\r\n\
END:VCALENDAR\r\n"
    );

    let filename = format!("judgement-{}.ics", event.slug);
    let mut response = (
        [
            (
                header::CONTENT_TYPE,
                HeaderValue::from_static("text/calendar; charset=utf-8"),
            ),
            (
                header::CONTENT_DISPOSITION,
                HeaderValue::from_str(&format!("attachment; filename=\"{filename}\""))
                    .unwrap_or_else(|_| HeaderValue::from_static("attachment; filename=\"event.ics\"")),
            ),
        ],
        ics,
    )
        .into_response();
    let _ = &mut response;
    Ok(response)
}

fn ics_escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace(';', "\\;")
        .replace(',', "\\,")
        .replace('\n', "\\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn share_text_uses_event_timezone_wall_clock() {
        // 21:00 Asia/Kolkata == 15:30 UTC
        let starts = Utc.with_ymd_and_hms(2026, 8, 2, 15, 30, 0).unwrap();
        let when = format_starts_at_in_timezone(starts, "Asia/Kolkata");
        assert_eq!(when, "Sun 02 Aug 2026 21:00 (Asia/Kolkata)");
    }

    #[test]
    fn url_origin_strips_path() {
        assert_eq!(
            url_origin("http://localhost:63151/e/abc/manage?token=x"),
            Some("http://localhost:63151".into())
        );
    }
}
