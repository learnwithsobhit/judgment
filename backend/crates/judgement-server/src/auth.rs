//! Firebase ID-token verification and account profile routes.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use axum::extract::State;
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use judgement_persistence::{StoredUser, StoredUserIdentity};
use judgement_protocol::{
    AuthSessionResponse, AvatarConfirmRequest, AvatarConfirmResponse, AvatarPresignRequest,
    AvatarPresignResponse, FirebaseAuthRequest, MeResponse, PatchMeRequest, SessionView,
    UserProfile,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::avatar_store::{allowed_avatar_content_type, AvatarStore};
use crate::emotes::is_allowed_avatar;
use crate::error::ApiError;
use crate::persist::{stored_room, stored_session};
use crate::state::{AppState, Session};

const MAX_AVATAR_BYTES: u64 = 2 * 1024 * 1024;
const JWKS_URL: &str =
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";
const JWKS_TTL: Duration = Duration::from_secs(3600);

#[derive(Debug, Clone)]
pub struct FirebaseIdentity {
    pub subject: String,
    pub email: Option<String>,
    pub name: Option<String>,
    pub provider: String,
}

#[derive(Deserialize)]
struct JwkSet {
    keys: Vec<Jwk>,
}

#[derive(Deserialize)]
struct Jwk {
    kid: String,
    n: String,
    e: String,
}

#[derive(Debug, Deserialize)]
struct FirebaseClaims {
    sub: String,
    #[serde(default)]
    email: Option<String>,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    firebase: Option<FirebaseMeta>,
    #[allow(dead_code)]
    aud: String,
    #[allow(dead_code)]
    iss: String,
    exp: i64,
}

#[derive(Debug, Deserialize)]
struct FirebaseMeta {
    #[serde(default)]
    sign_in_provider: Option<String>,
}

struct CachedJwks {
    fetched_at: Instant,
    keys: HashMap<String, DecodingKey>,
}

fn jwks_cache() -> &'static Mutex<Option<CachedJwks>> {
    static CACHE: OnceLock<Mutex<Option<CachedJwks>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(None))
}

fn map_provider(raw: &str) -> Result<&'static str, ApiError> {
    match raw {
        "google.com" | "google" => Ok("google"),
        "apple.com" | "apple" => Ok("apple"),
        other => Err(ApiError::BadRequest(format!(
            "unsupported sign-in provider: {other}"
        ))),
    }
}

async fn load_decoding_key(kid: &str) -> Result<DecodingKey, ApiError> {
    {
        let guard = jwks_cache().lock().unwrap();
        if let Some(cache) = guard.as_ref() {
            if cache.fetched_at.elapsed() < JWKS_TTL {
                if let Some(key) = cache.keys.get(kid) {
                    return Ok(key.clone());
                }
            }
        }
    }

    let set: JwkSet = reqwest::Client::new()
        .get(JWKS_URL)
        .send()
        .await
        .map_err(|e| ApiError::Conflict(format!("fetch firebase jwks: {e}")))?
        .error_for_status()
        .map_err(|e| ApiError::Conflict(format!("firebase jwks status: {e}")))?
        .json()
        .await
        .map_err(|e| ApiError::Conflict(format!("parse firebase jwks: {e}")))?;

    let mut keys = HashMap::new();
    for jwk in set.keys {
        if let Ok(key) = DecodingKey::from_rsa_components(&jwk.n, &jwk.e) {
            keys.insert(jwk.kid, key);
        }
    }
    let chosen = keys
        .get(kid)
        .cloned()
        .ok_or_else(|| ApiError::Unauthorized)?;
    *jwks_cache().lock().unwrap() = Some(CachedJwks {
        fetched_at: Instant::now(),
        keys,
    });
    Ok(chosen)
}

/// Verify a Firebase ID token for `project_id`, or a HS256 dev token when
/// `JUDGEMENT_FIREBASE_DEV_SECRET` is set (local/tests only).
pub async fn verify_firebase_id_token(
    project_id: &str,
    id_token: &str,
) -> Result<FirebaseIdentity, ApiError> {
    if let Ok(secret) = std::env::var("JUDGEMENT_FIREBASE_DEV_SECRET") {
        if !secret.is_empty() {
            if let Ok(identity) = verify_dev_token(&secret, id_token) {
                return Ok(identity);
            }
        }
    }

    let header = decode_header(id_token).map_err(|_| ApiError::Unauthorized)?;
    let kid = header.kid.ok_or(ApiError::Unauthorized)?;
    let key = load_decoding_key(&kid).await?;

    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_audience(&[project_id]);
    validation.set_issuer(&[format!(
        "https://securetoken.google.com/{project_id}"
    )]);

    let token = decode::<FirebaseClaims>(id_token, &key, &validation)
        .map_err(|_| ApiError::Unauthorized)?;
    let claims = token.claims;
    if claims.exp < Utc::now().timestamp() {
        return Err(ApiError::Unauthorized);
    }
    let raw_provider = claims
        .firebase
        .as_ref()
        .and_then(|f| f.sign_in_provider.as_deref())
        .unwrap_or("google.com");
    let provider = map_provider(raw_provider)?.to_string();
    Ok(FirebaseIdentity {
        subject: claims.sub,
        email: claims.email,
        name: claims.name,
        provider,
    })
}

#[derive(Debug, Deserialize)]
struct DevClaims {
    sub: String,
    #[serde(default)]
    email: Option<String>,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    provider: Option<String>,
}

fn verify_dev_token(secret: &str, id_token: &str) -> Result<FirebaseIdentity, ApiError> {
    let mut validation = Validation::new(Algorithm::HS256);
    validation.validate_aud = false;
    validation.set_required_spec_claims(&["sub", "exp"]);
    let key = DecodingKey::from_secret(secret.as_bytes());
    let token = decode::<DevClaims>(id_token, &key, &validation).map_err(|_| ApiError::Unauthorized)?;
    let provider = map_provider(token.claims.provider.as_deref().unwrap_or("google"))?.to_string();
    Ok(FirebaseIdentity {
        subject: token.claims.sub,
        email: token.claims.email,
        name: token.claims.name,
        provider,
    })
}

fn session_view(session: &Session) -> SessionView {
    SessionView {
        session_id: session.id,
        nickname: session.nickname.clone(),
        token: session.token.clone(),
        avatar_id: session.avatar_id.clone(),
        avatar_url: session.avatar_url.clone(),
        user_id: session.user_id,
    }
}

fn user_profile(user: &StoredUser, provider: Option<String>) -> UserProfile {
    UserProfile {
        user_id: user.user_id,
        display_name: user.display_name.clone(),
        avatar_kind: user.avatar_kind.clone(),
        avatar_id: user.avatar_id.clone(),
        avatar_url: user.avatar_url.clone(),
        provider,
    }
}

fn validate_display_name(name: &str) -> Result<String, ApiError> {
    let nickname = name.trim().to_string();
    if nickname.is_empty() || nickname.chars().count() > 24 {
        return Err(ApiError::BadRequest(
            "display_name must be 1-24 characters".into(),
        ));
    }
    Ok(nickname)
}

async fn persist_session_and_seats(state: &AppState, session: &Session) -> Result<(), ApiError> {
    state
        .store
        .upsert_session(&stored_session(session))
        .await
        .map_err(|e| ApiError::Conflict(format!("persist session: {e}")))?;
    let room_snapshots: Vec<_> = {
        let rooms = state.rooms.lock().unwrap();
        rooms
            .values()
            .filter(|r| r.seats.iter().any(|s| s.session_id == session.id))
            .map(stored_room)
            .collect()
    };
    for snapshot in room_snapshots {
        state
            .store
            .upsert_room(&snapshot)
            .await
            .map_err(|e| ApiError::Conflict(format!("persist room: {e}")))?;
    }
    Ok(())
}

pub async fn auth_firebase(
    State(state): State<std::sync::Arc<AppState>>,
    Json(body): Json<FirebaseAuthRequest>,
) -> Result<Json<AuthSessionResponse>, ApiError> {
    let project_id = state
        .firebase_project_id
        .as_deref()
        .ok_or_else(|| ApiError::BadRequest("FIREBASE_PROJECT_ID is not configured".into()))?;
    let identity = verify_firebase_id_token(project_id, &body.id_token).await?;

    let now = Utc::now();
    let existing = state
        .store
        .find_user_by_identity(&identity.provider, &identity.subject)
        .await
        .map_err(|e| ApiError::Conflict(format!("lookup user: {e}")))?;

    let display_name = if let Some(name) = body.display_name.as_deref() {
        validate_display_name(name)?
    } else if let Some(ref user) = existing {
        user.display_name.clone()
    } else {
        let fallback = identity
            .name
            .clone()
            .filter(|n| !n.trim().is_empty())
            .unwrap_or_else(|| "Player".into());
        validate_display_name(&fallback).unwrap_or_else(|_| "Player".into())
    };

    let user = if let Some(mut user) = existing {
        user.display_name = display_name;
        user.updated_at = now;
        user.last_seen_at = now;
        if body.legal_version.is_some() {
            user.legal_accepted_at = Some(now);
            user.legal_version = body.legal_version.clone();
        }
        user
    } else {
        StoredUser {
            user_id: Uuid::new_v4(),
            display_name,
            avatar_kind: "pack".into(),
            avatar_id: Some("fox".into()),
            avatar_url: None,
            avatar_storage_key: None,
            created_at: now,
            updated_at: now,
            last_seen_at: now,
            legal_accepted_at: body.legal_version.as_ref().map(|_| now),
            legal_version: body.legal_version.clone(),
        }
    };

    state
        .store
        .upsert_user(&user)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist user: {e}")))?;
    state
        .store
        .upsert_user_identity(&StoredUserIdentity {
            user_id: user.user_id,
            provider: identity.provider.clone(),
            subject: identity.subject.clone(),
            email: identity.email.clone(),
            created_at: now,
        })
        .await
        .map_err(|e| ApiError::Conflict(format!("persist identity: {e}")))?;

    let session = state.create_session_for_user(
        user.display_name.clone(),
        user.user_id,
        user.avatar_id.clone(),
        user.avatar_url.clone(),
    );
    state
        .store
        .upsert_session(&stored_session(&session))
        .await
        .map_err(|e| ApiError::Conflict(format!("persist session: {e}")))?;

    Ok(Json(AuthSessionResponse {
        session: session_view(&session),
        user: user_profile(&user, Some(identity.provider)),
    }))
}

pub async fn get_me(
    State(state): State<std::sync::Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<MeResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user = match session.user_id {
        Some(uid) => state
            .store
            .load_user(uid)
            .await
            .map_err(|e| ApiError::Conflict(format!("load user: {e}")))?
            .map(|u| user_profile(&u, None)),
        None => None,
    };
    Ok(Json(MeResponse {
        session: session_view(&session),
        user,
    }))
}

pub async fn patch_me(
    State(state): State<std::sync::Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<PatchMeRequest>,
) -> Result<Json<MeResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user_id = session
        .user_id
        .ok_or_else(|| ApiError::Forbidden("guest sessions cannot patch profile".into()))?;
    let display_name = validate_display_name(&body.display_name)?;

    let mut user = state
        .store
        .load_user(user_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load user: {e}")))?
        .ok_or(ApiError::NotFound("user"))?;
    user.display_name = display_name.clone();
    user.updated_at = Utc::now();
    user.last_seen_at = user.updated_at;
    state
        .store
        .upsert_user(&user)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist user: {e}")))?;

    state.update_session_nickname(session.id, display_name);
    let session = state
        .sessions
        .lock()
        .unwrap()
        .get(&session.id)
        .cloned()
        .ok_or(ApiError::Unauthorized)?;
    persist_session_and_seats(&state, &session).await?;

    Ok(Json(MeResponse {
        session: session_view(&session),
        user: Some(user_profile(&user, None)),
    }))
}

pub async fn logout_me(
    State(state): State<std::sync::Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>, ApiError> {
    let session = state.authenticate(&headers)?;
    if state.session_in_active_game(session.id) {
        return Err(ApiError::Conflict(
            "leave or finish the game before logging out".into(),
        ));
    }
    state.invalidate_session(session.id);
    Ok(Json(serde_json::json!({ "ok": true })))
}

pub async fn delete_me(
    State(state): State<std::sync::Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user_id = session
        .user_id
        .ok_or_else(|| ApiError::Forbidden("guest sessions have no account to delete".into()))?;
    if state.session_in_active_game(session.id) {
        return Err(ApiError::Conflict(
            "leave or finish the game before deleting your account".into(),
        ));
    }

    if let Some(user) = state
        .store
        .load_user(user_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load user: {e}")))?
    {
        if let Some(key) = user.avatar_storage_key.as_deref() {
            let _ = state.avatar_store.delete(key).await;
        }
    }
    state.invalidate_user_sessions(user_id);
    state
        .store
        .delete_user(user_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("delete user: {e}")))?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

pub async fn presign_avatar(
    State(state): State<std::sync::Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<AvatarPresignRequest>,
) -> Result<Json<AvatarPresignResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user_id = session
        .user_id
        .ok_or_else(|| ApiError::Forbidden("sign in to upload an avatar".into()))?;
    if !state.avatar_store.enabled() {
        return Err(ApiError::BadRequest(
            "avatar uploads are not configured".into(),
        ));
    }
    let content_type = body.content_type.trim().to_ascii_lowercase();
    if !allowed_avatar_content_type(&content_type) {
        return Err(ApiError::BadRequest(
            "content_type must be image/jpeg, image/png, or image/webp".into(),
        ));
    }
    let key = state.avatar_store.build_key(user_id, &content_type);
    let upload = state
        .avatar_store
        .presign_put(&key, &content_type)
        .map_err(ApiError::BadRequest)?;
    Ok(Json(AvatarPresignResponse {
        method: upload.method,
        upload_url: upload.upload_url,
        headers: upload.headers,
        key: upload.key,
        public_url: upload.public_url,
        expires_in_sec: upload.expires_in_sec,
    }))
}

pub async fn confirm_avatar(
    State(state): State<std::sync::Arc<AppState>>,
    headers: HeaderMap,
    Json(body): Json<AvatarConfirmRequest>,
) -> Result<Json<AvatarConfirmResponse>, ApiError> {
    let session = state.authenticate(&headers)?;
    let user_id = session
        .user_id
        .ok_or_else(|| ApiError::Forbidden("sign in to upload an avatar".into()))?;
    if !state.avatar_store.key_belongs_to_user(&body.key, user_id) {
        return Err(ApiError::Forbidden("invalid avatar key".into()));
    }
    let content_type = body.content_type.trim().to_ascii_lowercase();
    if !allowed_avatar_content_type(&content_type) {
        return Err(ApiError::BadRequest("invalid content_type".into()));
    }
    if body.byte_size == 0 || body.byte_size > MAX_AVATAR_BYTES {
        return Err(ApiError::BadRequest(format!(
            "byte_size must be 1..{MAX_AVATAR_BYTES}"
        )));
    }

    let mut user = state
        .store
        .load_user(user_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load user: {e}")))?
        .ok_or(ApiError::NotFound("user"))?;

    if let Err(e) = state.avatar_store.mark_confirmed(&body.key).await {
        tracing::warn!(error = %e, key = %body.key, "avatar untag failed; lifecycle will clean up");
    }

    if let Some(old) = user.avatar_storage_key.take() {
        if old != body.key {
            let _ = state.avatar_store.delete(&old).await;
        }
    }

    let public_url = state.avatar_store.read_url(&body.key);
    user.avatar_kind = "upload".into();
    user.avatar_url = Some(public_url.clone());
    user.avatar_storage_key = Some(body.key.clone());
    user.updated_at = Utc::now();
    state
        .store
        .upsert_user(&user)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist user: {e}")))?;

    state.set_avatar_url(session.id, public_url.clone());
    let session = state
        .sessions
        .lock()
        .unwrap()
        .get(&session.id)
        .cloned()
        .ok_or(ApiError::Unauthorized)?;
    persist_session_and_seats(&state, &session).await?;

    Ok(Json(AvatarConfirmResponse {
        avatar_url: public_url,
    }))
}

/// After pack avatar is set via `/me/avatar`, also mirror onto the durable user.
pub async fn mirror_pack_avatar_to_user(
    state: &AppState,
    session: &Session,
    avatar_id: &str,
) -> Result<(), ApiError> {
    let Some(user_id) = session.user_id else {
        return Ok(());
    };
    if !is_allowed_avatar(avatar_id) {
        return Ok(());
    }
    let Some(mut user) = state
        .store
        .load_user(user_id)
        .await
        .map_err(|e| ApiError::Conflict(format!("load user: {e}")))?
    else {
        return Ok(());
    };
    if let Some(old) = user.avatar_storage_key.take() {
        let _ = state.avatar_store.delete(&old).await;
    }
    user.avatar_kind = "pack".into();
    user.avatar_id = Some(avatar_id.to_string());
    user.avatar_url = None;
    user.updated_at = Utc::now();
    state
        .store
        .upsert_user(&user)
        .await
        .map_err(|e| ApiError::Conflict(format!("persist user: {e}")))?;
    Ok(())
}

#[allow(dead_code)]
pub fn avatar_store_enabled(store: &AvatarStore) -> bool {
    store.enabled()
}
