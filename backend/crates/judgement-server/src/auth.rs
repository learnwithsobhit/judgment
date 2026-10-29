//! Optional account sign-in. Guest routes stay available when this is unset.
//!
//! Firebase ID tokens for Google and email/password are checked here. Production
//! verifies RS256 against Google's JWKS. Tests mint HS256 tokens with
//! `JUDGEMENT_FIREBASE_DEV_SECRET`.
//!
//! Telegram is a separate token. Production verifies RS256 against
//! `https://oauth.telegram.org`. Tests mint HS256 tokens with
//! `JUDGEMENT_TELEGRAM_DEV_SECRET`.

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
    MeStatsResponse, PatchMeRequest, PublicUser, TelegramAuthRequest,
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
    open_account_session(&state, identity, body.display_name, body.legal_version).await
}

pub async fn auth_telegram(
    State(state): State<Arc<AppState>>,
    Json(body): Json<TelegramAuthRequest>,
) -> Result<Json<AuthSessionResponse>, ApiError> {
    let identity = verify_telegram_token(&body.id_token).await?;
    open_account_session(&state, identity, body.display_name, body.legal_version).await
}

async fn open_account_session(
    state: &AppState,
    identity: VerifiedAccount,
    requested_name: Option<String>,
    requested_legal: Option<String>,
) -> Result<Json<AuthSessionResponse>, ApiError> {
    let now = Utc::now();
    let existing = state
        .store
        .find_user_by_identity(&identity.provider, &identity.subject)
        .await
        .map_err(|e| ApiError::Conflict(format!("lookup account: {e}")))?;

    let user_id = existing
        .as_ref()
        .map(|user| user.user_id)
        .unwrap_or_else(uuid::Uuid::new_v4);
    let display_name = clip_chars(
        &requested_name
            .as_deref()
            .map(str::trim)
            .filter(|name| !name.is_empty())
            .map(str::to_string)
            .or_else(|| existing.as_ref().map(|user| user.display_name.clone()))
            .or(identity.name.clone())
            .or_else(|| email_local_part(identity.email.as_deref()))
            .filter(|name| !name.is_empty())
            .unwrap_or_else(|| "Player".into()),
        40,
    );
    let avatar_id = existing.as_ref().and_then(|user| user.avatar_id.clone());
    let legal_version = requested_legal
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
            provider: identity.provider,
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
    let rows = state.leaderboard.lock().unwrap().clone();
    let limit = match query.limit {
        Some(n) => n.clamp(1, 10_000) as usize,
        None => rows.len(),
    };
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
    let pulse = state.table_pulse.lock().unwrap().clone();
    Json(LeaderboardResponse { players, pulse })
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

struct VerifiedAccount {
    provider: String,
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

async fn verify_id_token(token: &str) -> Result<VerifiedAccount, ApiError> {
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

fn verify_dev_token(token: &str, secret: &str) -> Result<VerifiedAccount, ApiError> {
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

async fn verify_firebase_token(token: &str, project_id: &str) -> Result<VerifiedAccount, ApiError> {
    let header =
        decode_header(token).map_err(|_| ApiError::BadRequest("invalid Google token".into()))?;
    let kid = header
        .kid
        .ok_or_else(|| ApiError::BadRequest("invalid Google token".into()))?;
    let jwks = cached_jwks(GOOGLE_JWKS, google_jwks_cache(), "Google").await?;
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

fn accept_claims(claims: TokenClaims) -> Result<VerifiedAccount, ApiError> {
    let provider = match claims.firebase.sign_in_provider.as_deref() {
        None | Some("google.com") => "google",
        Some("password") => "email",
        Some(_) => {
            return Err(ApiError::BadRequest(
                "this sign-in method is not enabled".into(),
            ));
        }
    };
    if claims.sub.trim().is_empty() {
        return Err(ApiError::BadRequest("invalid Google token".into()));
    }
    Ok(VerifiedAccount {
        provider: provider.into(),
        subject: claims.sub,
        email: claims.email.filter(|email| !email.is_empty()),
        name: claims.name.filter(|name| !name.is_empty()),
    })
}

#[derive(Debug, Deserialize)]
struct TelegramClaims {
    #[serde(deserialize_with = "json_string")]
    sub: String,
    #[serde(default)]
    aud: serde_json::Value,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    given_name: Option<String>,
    #[serde(default)]
    family_name: Option<String>,
    #[serde(default)]
    preferred_username: Option<String>,
}

fn json_string<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let value = serde_json::Value::deserialize(deserializer)?;
    match value {
        serde_json::Value::String(text) => Ok(text),
        serde_json::Value::Number(number) => Ok(number.to_string()),
        _ => Err(serde::de::Error::custom("expected string")),
    }
}

fn audience_matches(aud: &serde_json::Value, client_id: &str) -> bool {
    match aud {
        serde_json::Value::String(value) => value == client_id,
        serde_json::Value::Number(value) => value.to_string() == client_id,
        serde_json::Value::Array(values) => values
            .iter()
            .any(|value| audience_matches(value, client_id)),
        _ => false,
    }
}

const TELEGRAM_JWKS: &str = "https://oauth.telegram.org/.well-known/jwks.json";
const GOOGLE_JWKS: &str =
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";

async fn verify_telegram_token(token: &str) -> Result<VerifiedAccount, ApiError> {
    let header =
        decode_header(token).map_err(|_| ApiError::BadRequest("invalid Telegram token".into()))?;
    if header.alg == Algorithm::HS256 {
        let secret = std::env::var("JUDGEMENT_TELEGRAM_DEV_SECRET")
            .map_err(|_| ApiError::BadRequest("Telegram sign-in is not configured".into()))?;
        return verify_telegram_dev_token(token, &secret);
    }
    let client_id = std::env::var("TELEGRAM_CLIENT_ID")
        .map_err(|_| ApiError::BadRequest("Telegram sign-in is not configured".into()))?;
    let kid = header
        .kid
        .ok_or_else(|| ApiError::BadRequest("invalid Telegram token".into()))?;
    let jwks = cached_jwks(TELEGRAM_JWKS, telegram_jwks_cache(), "Telegram").await?;
    let jwk = jwks
        .find(&kid)
        .ok_or_else(|| ApiError::BadRequest("invalid Telegram token".into()))?;
    let key = DecodingKey::from_jwk(jwk)
        .map_err(|_| ApiError::BadRequest("invalid Telegram token".into()))?;
    if !matches!(
        header.alg,
        Algorithm::RS256 | Algorithm::ES256 | Algorithm::EdDSA
    ) {
        return Err(ApiError::BadRequest("invalid Telegram token".into()));
    }
    let mut validation = Validation::new(header.alg);
    validation.validate_aud = false;
    validation.set_issuer(&["https://oauth.telegram.org"]);
    let data = decode::<TelegramClaims>(token, &key, &validation).map_err(|err| {
        tracing::warn!(error = %err, "telegram token rejected");
        ApiError::BadRequest("invalid Telegram token".into())
    })?;
    if !audience_matches(&data.claims.aud, &client_id) {
        return Err(ApiError::BadRequest("invalid Telegram token".into()));
    }
    telegram_account(data.claims)
}

fn verify_telegram_dev_token(token: &str, secret: &str) -> Result<VerifiedAccount, ApiError> {
    let mut validation = Validation::new(Algorithm::HS256);
    validation.validate_aud = false;
    validation.set_issuer(&["judgement-dev-telegram"]);
    let data = decode::<TelegramClaims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &validation,
    )
    .map_err(|_| ApiError::BadRequest("invalid Telegram token".into()))?;
    telegram_account(data.claims)
}

fn telegram_account(claims: TelegramClaims) -> Result<VerifiedAccount, ApiError> {
    if claims.sub.trim().is_empty() {
        return Err(ApiError::BadRequest("invalid Telegram token".into()));
    }
    let name = telegram_name(&claims);
    Ok(VerifiedAccount {
        provider: "telegram".into(),
        subject: claims.sub,
        email: None,
        name,
    })
}

fn telegram_name(claims: &TelegramClaims) -> Option<String> {
    let direct = claims
        .name
        .as_deref()
        .map(str::trim)
        .filter(|name| !name.is_empty());
    if let Some(name) = direct {
        return Some(name.to_string());
    }
    let given = claims.given_name.as_deref().unwrap_or("").trim();
    let family = claims.family_name.as_deref().unwrap_or("").trim();
    let combined = format!("{given} {family}").trim().to_string();
    if !combined.is_empty() {
        return Some(combined);
    }
    claims
        .preferred_username
        .as_deref()
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(str::to_string)
}

struct CachedJwks {
    fetched: Instant,
    set: JwkSet,
}

fn google_jwks_cache() -> &'static Mutex<Option<CachedJwks>> {
    static CACHE: OnceLock<Mutex<Option<CachedJwks>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

fn telegram_jwks_cache() -> &'static Mutex<Option<CachedJwks>> {
    static CACHE: OnceLock<Mutex<Option<CachedJwks>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

async fn cached_jwks(
    url: &str,
    cache: &Mutex<Option<CachedJwks>>,
    who: &str,
) -> Result<JwkSet, ApiError> {
    if let Some(cached) = cache.lock().unwrap().as_ref() {
        if cached.fetched.elapsed() < Duration::from_secs(60 * 60) {
            return Ok(cached.set.clone());
        }
    }
    let response = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .build()
        .map_err(|_| ApiError::Conflict(format!("could not reach {who}")))?
        .get(url)
        .send()
        .await
        .map_err(|_| ApiError::Conflict(format!("could not reach {who}")))?;
    let body = response
        .text()
        .await
        .map_err(|_| ApiError::Conflict(format!("could not read {who} keys")))?;
    let set = jwk_set_from_json(&body).map_err(|err| {
        tracing::warn!(error = %err, %who, "jwks parse failed");
        ApiError::Conflict(format!("could not read {who} keys"))
    })?;
    *cache.lock().unwrap() = Some(CachedJwks {
        fetched: Instant::now(),
        set: set.clone(),
    });
    Ok(set)
}

/// Telegram publishes ES256K keys this crate cannot decode. Drop those
/// before parsing so one unused key does not reject the whole set.
fn jwk_set_from_json(body: &str) -> Result<JwkSet, serde_json::Error> {
    let mut value: serde_json::Value = serde_json::from_str(body)?;
    if let Some(keys) = value.get_mut("keys").and_then(|keys| keys.as_array_mut()) {
        keys.retain(|key| {
            matches!(
                key.get("alg").and_then(|alg| alg.as_str()),
                Some("RS256" | "ES256" | "EdDSA")
            )
        });
    }
    serde_json::from_value(value)
}

fn email_local_part(email: Option<&str>) -> Option<String> {
    let local = email?.split('@').next()?.trim();
    if local.is_empty() {
        None
    } else {
        Some(local.to_string())
    }
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
    fn telegram_jwks_ignores_unsupported_es256k_keys() {
        let set = super::jwk_set_from_json(
            r#"{"keys":[
                {"kty":"RSA","alg":"RS256","kid":"oidc-1","n":"sQ","e":"AQAB"},
                {"kty":"EC","alg":"ES256K","kid":"oidc-es256k-1","crv":"secp256k1","x":"a","y":"b"}
            ]}"#,
        )
        .expect("supported keys parse");
        assert_eq!(set.keys.len(), 1);
        assert_eq!(set.keys[0].common.key_id.as_deref(), Some("oidc-1"));
    }

    #[test]
    fn telegram_audience_accepts_the_bot_client_id() {
        assert!(super::audience_matches(
            &serde_json::json!("8994800560"),
            "8994800560"
        ));
        assert!(super::audience_matches(
            &serde_json::json!(8_994_800_560_i64),
            "8994800560"
        ));
        assert!(super::audience_matches(
            &serde_json::json!(["8994800560"]),
            "8994800560"
        ));
        assert!(!super::audience_matches(
            &serde_json::json!("other"),
            "8994800560"
        ));
    }

    #[test]
    fn telegram_subject_accepts_a_numeric_id() {
        let claims: super::TelegramClaims =
            serde_json::from_value(serde_json::json!({"sub": 424242, "name": "Ada"})).unwrap();
        assert_eq!(claims.sub, "424242");
    }

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
