//! Optional Google sign-in. Guest routes stay available when this is unset.
//!
//! Production verifies Firebase ID tokens (RS256 + cached Google JWKS).
//! Tests mint HS256 tokens with `JUDGEMENT_FIREBASE_DEV_SECRET`.

use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use axum::extract::{Query, State};
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use jsonwebtoken::jwk::JwkSet;
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use judgement_persistence::{StoredIdentity, StoredUser};
use judgement_protocol::{
    AuthSessionResponse, FirebaseAuthRequest, LeaderboardEntry, LeaderboardResponse, MeResponse,
    MeStatsResponse, PatchMeRequest, PublicUser,
};
use serde::Deserialize;
use std::sync::Arc;

use crate::emotes::is_allowed_avatar;
use crate::error::ApiError;
use crate::persist::stored_session;
use crate::state::AppState;

const STATS_MEMO: Duration = Duration::from_secs(30);

pub async fn auth_firebase(
    State(state): State<Arc<AppState>>,
    Json(body): Json<FirebaseAuthRequest>,
) -> Result<Json<AuthSessionResponse>, ApiError> {
    let identity = verify_id_token(&body.id_token).await?;
    let now = Utc::now();
    let existing = state
        .store
        .find_user_by_google_subject(&identity.subject)
        .await
        .map_err(|e| ApiError::Conflict(format!("lookup account: {e}")))?;

    let user_id = existing
        .as_ref()
        .map(|user| user.user_id)
        .unwrap_or_else(uuid::Uuid::new_v4);
    let display_name = clip_chars(
        &body
            .display_name
            .as_deref()
            .map(str::trim)
            .filter(|name| !name.is_empty())
            .map(str::to_string)
            .or_else(|| existing.as_ref().map(|user| user.display_name.clone()))
            .or(identity.name)
            .filter(|name| !name.is_empty())
            .unwrap_or_else(|| "Player".into()),
        40,
    );
    let avatar_id = existing.as_ref().and_then(|user| user.avatar_id.clone());
    let legal_version = body
        .legal_version
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .or_else(|| {
            existing
                .as_ref()
                .and_then(|user| user.legal_version.clone())
        });

    let user = StoredUser {
        user_id,
        display_name: display_name.clone(),
        avatar_id: avatar_id.clone(),
        legal_version,
        created_at: existing.as_ref().map(|user| user.created_at).unwrap_or(now),
        updated_at: now,
        last_seen_at: now,
    };
    state
        .store
        .upsert_user(&user)
        .await
        .map_err(|e| ApiError::Conflict(format!("save account: {e}")))?;
    state
        .store
        .upsert_identity(&StoredIdentity {
            user_id,
            provider: "google".into(),
            subject: identity.subject,
            email: identity.email,
        })
        .await
        .map_err(|e| ApiError::Conflict(format!("save identity: {e}")))?;

    let nickname = table_nickname_from_display(&display_name);
    let session = state.create_session_for_user(nickname, user_id, avatar_id.clone());
    state
        .store
        .upsert_session(&stored_session(&session))
        .await
        .map_err(|e| ApiError::Conflict(format!("persist session: {e}")))?;

    Ok(Json(AuthSessionResponse {
        session_id: session.id,
        nickname: session.nickname,
        token: session.token,
        user: PublicUser {
            user_id: user_id.to_string(),
            display_name,
            avatar_id,
        },
    }))
}

pub async fn get_me(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<MeResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user_id = session.user_id.ok_or(ApiError::NotFound("profile"))?;
    let user = state
        .store
        .load_user(user_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load account: {e}")))?
        .ok_or(ApiError::NotFound("profile"))?;
    Ok(Json(MeResponse {
        user_id: user.user_id.to_string(),
        display_name: user.display_name,
        avatar_id: user.avatar_id,
        session_id: session.id,
        nickname: session.nickname,
    }))
}

pub async fn patch_me(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<PatchMeRequest>,
) -> Result<Json<MeResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user_id = session.user_id.ok_or(ApiError::NotFound("profile"))?;
    let mut user = state
        .store
        .load_user(user_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load account: {e}")))?
        .ok_or(ApiError::NotFound("profile"))?;

    if let Some(name) = body.display_name.as_deref() {
        let name = clip_chars(name.trim(), 40);
        if name.is_empty() {
            return Err(ApiError::BadRequest("display name is empty".into()));
        }
        user.display_name = name;
    }
    if let Some(avatar_id) = body.avatar_id.as_deref() {
        if !is_allowed_avatar(avatar_id) {
            return Err(ApiError::BadRequest("unknown avatar_id".into()));
        }
        user.avatar_id = Some(avatar_id.to_string());
        state
            .set_avatar(session.id, avatar_id.to_string())
            .ok_or(ApiError::Unauthorized)?;
    }
    if let Some(nickname) = body.table_nickname.as_deref() {
        let nickname = clip_chars(nickname.trim(), 24);
        if nickname.is_empty() {
            return Err(ApiError::BadRequest(
                "nickname must be 1-24 characters".into(),
            ));
        }
        if !state.set_table_nickname(session.id, nickname) {
            return Err(ApiError::Unauthorized);
        }
    }
    user.updated_at = Utc::now();
    user.last_seen_at = user.updated_at;
    state
        .store
        .upsert_user(&user)
        .await
        .map_err(|e| ApiError::Conflict(format!("save account: {e}")))?;

    let session = state
        .sessions
        .lock()
        .unwrap()
        .get(&session.id)
        .cloned()
        .ok_or(ApiError::Unauthorized)?;
    state
        .store
        .upsert_session(&stored_session(&session))
        .await
        .map_err(|e| ApiError::Conflict(format!("persist session: {e}")))?;

    Ok(Json(MeResponse {
        user_id: user.user_id.to_string(),
        display_name: user.display_name,
        avatar_id: user.avatar_id,
        session_id: session.id,
        nickname: session.nickname,
    }))
}

pub async fn logout_me(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>, ApiError> {
    let session = state.authenticate(&headers)?;
    let _ = state.rotate_token(session.id);
    Ok(Json(serde_json::json!({ "ok": true })))
}

pub async fn delete_me(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user_id = session.user_id.ok_or(ApiError::NotFound("profile"))?;
    state
        .store
        .delete_user(user_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("delete account: {e}")))?;
    state.forget_user_sessions(user_id);
    state.stats_memo.lock().unwrap().remove(&user_id);
    Ok(Json(serde_json::json!({ "ok": true })))
}

pub async fn get_me_stats(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<MeStatsResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user_id = session.user_id.ok_or(ApiError::NotFound("profile"))?;
    if let Some(cached) = state.stats_memo.lock().unwrap().get(&user_id) {
        if cached.0.elapsed() < STATS_MEMO {
            return Ok(Json(stats_response(&cached.1)));
        }
    }
    let view = state
        .store
        .load_user_stats(user_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load stats: {e}")))?
        .ok_or(ApiError::NotFound("profile"))?;
    state
        .stats_memo
        .lock()
        .unwrap()
        .insert(user_id, (Instant::now(), view.clone()));
    Ok(Json(stats_response(&view)))
}

pub async fn get_leaderboard(
    State(state): State<Arc<AppState>>,
    Query(query): Query<LimitQuery>,
) -> Json<LeaderboardResponse> {
    let limit = query.limit.unwrap_or(10).clamp(1, 10) as usize;
    let rows = state.leaderboard.lock().unwrap().clone();
    let players = rows
        .iter()
        .take(limit)
        .enumerate()
        .map(|(index, row)| LeaderboardEntry {
            rank: index as i32 + 1,
            display_name: row.display_name.clone(),
            avatar_id: row.avatar_id.clone(),
            wins: row.wins,
            games: row.games,
            exact_percent: row.exact_percent,
            average_score: row.average_score,
        })
        .collect();
    Json(LeaderboardResponse { players })
}

fn stats_response(view: &judgement_persistence::UserStatsView) -> MeStatsResponse {
    use judgement_persistence::stats::{average_score, exact_percent};
    MeStatsResponse {
        display_name: view.display_name.clone(),
        avatar_id: view.avatar_id.clone(),
        games_played: view.games_played,
        wins: view.wins,
        losses: view.games_played.saturating_sub(view.wins),
        exact_percent: exact_percent(view.exact_bid_rounds, view.rounds_played),
        average_score: average_score(view.lifetime_points, view.games_played),
        rank: view.rank,
    }
}

#[derive(Debug, Deserialize)]
pub struct LimitQuery {
    pub limit: Option<i64>,
}

struct VerifiedGoogle {
    subject: String,
    email: Option<String>,
    name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct TokenClaims {
    sub: String,
    #[serde(default)]
    email: Option<String>,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    firebase: FirebaseClaim,
}

#[derive(Debug, Default, Deserialize)]
struct FirebaseClaim {
    #[serde(default)]
    sign_in_provider: Option<String>,
}

async fn verify_id_token(token: &str) -> Result<VerifiedGoogle, ApiError> {
    let header =
        decode_header(token).map_err(|_| ApiError::BadRequest("invalid Google token".into()))?;
    if header.alg == Algorithm::HS256 {
        let secret = std::env::var("JUDGEMENT_FIREBASE_DEV_SECRET")
            .map_err(|_| ApiError::BadRequest("Google sign-in is not configured".into()))?;
        return verify_dev_token(token, &secret);
    }
    let project = std::env::var("FIREBASE_PROJECT_ID")
        .map_err(|_| ApiError::BadRequest("Google sign-in is not configured".into()))?;
    verify_firebase_token(token, &project).await
}

fn verify_dev_token(token: &str, secret: &str) -> Result<VerifiedGoogle, ApiError> {
    let mut validation = Validation::new(Algorithm::HS256);
    validation.validate_aud = false;
    validation.set_issuer(&["judgement-dev"]);
    let data = decode::<TokenClaims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &validation,
    )
    .map_err(|_| ApiError::BadRequest("invalid Google token".into()))?;
    accept_claims(data.claims)
}

async fn verify_firebase_token(token: &str, project_id: &str) -> Result<VerifiedGoogle, ApiError> {
    let header =
        decode_header(token).map_err(|_| ApiError::BadRequest("invalid Google token".into()))?;
    let kid = header
        .kid
        .ok_or_else(|| ApiError::BadRequest("invalid Google token".into()))?;
    let jwks = cached_jwks().await?;
    let jwk = jwks
        .find(&kid)
        .ok_or_else(|| ApiError::BadRequest("invalid Google token".into()))?;
    let key = DecodingKey::from_jwk(jwk)
        .map_err(|_| ApiError::BadRequest("invalid Google token".into()))?;
    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_audience(&[project_id]);
    validation.set_issuer(&[format!("https://securetoken.google.com/{project_id}")]);
    let data = decode::<TokenClaims>(token, &key, &validation)
        .map_err(|_| ApiError::BadRequest("invalid Google token".into()))?;
    accept_claims(data.claims)
}

fn accept_claims(claims: TokenClaims) -> Result<VerifiedGoogle, ApiError> {
    if let Some(provider) = claims.firebase.sign_in_provider.as_deref() {
        if provider != "google.com" {
            return Err(ApiError::BadRequest(
                "only Google sign-in is enabled".into(),
            ));
        }
    }
    if claims.sub.trim().is_empty() {
        return Err(ApiError::BadRequest("invalid Google token".into()));
    }
    Ok(VerifiedGoogle {
        subject: claims.sub,
        email: claims.email.filter(|email| !email.is_empty()),
        name: claims.name.filter(|name| !name.is_empty()),
    })
}

struct CachedJwks {
    fetched: Instant,
    set: JwkSet,
}

fn jwks_cache() -> &'static Mutex<Option<CachedJwks>> {
    static CACHE: OnceLock<Mutex<Option<CachedJwks>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

async fn cached_jwks() -> Result<JwkSet, ApiError> {
    if let Some(cached) = jwks_cache().lock().unwrap().as_ref() {
        if cached.fetched.elapsed() < Duration::from_secs(60 * 60) {
            return Ok(cached.set.clone());
        }
    }
    let response = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .build()
        .map_err(|_| ApiError::Conflict("could not reach Google".into()))?
        .get("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com")
        .send()
        .await
        .map_err(|_| ApiError::Conflict("could not reach Google".into()))?;
    let set: JwkSet = response
        .json()
        .await
        .map_err(|_| ApiError::Conflict("could not read Google keys".into()))?;
    *jwks_cache().lock().unwrap() = Some(CachedJwks {
        fetched: Instant::now(),
        set: set.clone(),
    });
    Ok(set)
}

fn clip_chars(value: &str, max: usize) -> String {
    value.chars().take(max).collect()
}

/// Seat label from a Google display name: first word, plus the next word's initial.
/// `Ankit Sunil Chaturvedi` becomes `Ankit S`. The profile keeps the full name.
fn table_nickname_from_display(name: &str) -> String {
    let mut parts = name.split_whitespace().filter(|part| !part.is_empty());
    let Some(first) = parts.next() else {
        return "Player".into();
    };
    let short = match parts.next().and_then(|word| word.chars().next()) {
        Some(ch) => {
            let letter: String = ch.to_uppercase().collect();
            format!("{first} {letter}")
        }
        None => first.to_string(),
    };
    clip_chars(&short, 16)
}

#[cfg(test)]
mod tests {
    use super::table_nickname_from_display;

    #[test]
    fn table_nickname_uses_first_name_and_next_initial() {
        assert_eq!(
            table_nickname_from_display("Ankit Sunil Chaturvedi"),
            "Ankit S"
        );
        assert_eq!(
            table_nickname_from_display("shobhit chaturvedi"),
            "shobhit C"
        );
        assert_eq!(table_nickname_from_display("Madonna"), "Madonna");
        assert_eq!(table_nickname_from_display("   "), "Player");
        let clipped = table_nickname_from_display("Abcdefghijklmnop Qrst");
        assert_eq!(clipped, "Abcdefghijklmnop");
        assert_eq!(clipped.chars().count(), 16);
    }
}
