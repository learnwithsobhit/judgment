//! HTTP request rate limiting (PLAN.md Phase 9 / §21).
//!
//! Separate from AI cost caps in `judgement-ai`. Keyed by bearer token when
//! present, otherwise by `X-Forwarded-For` / `X-Real-IP` / anonymous.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use axum::body::Body;
use axum::extract::State;
use axum::http::{HeaderMap, Request, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use axum::Json;

use crate::state::AppState;

#[derive(Debug, Clone, Copy)]
pub struct HttpLimitConfig {
    pub max_requests_per_window: u32,
    pub window: Duration,
    /// Stricter limit for unauthenticated guest-session creation.
    pub guest_max_per_window: u32,
}

impl Default for HttpLimitConfig {
    fn default() -> Self {
        Self {
            max_requests_per_window: env_u32("HTTP_RATE_LIMIT", 120),
            window: Duration::from_secs(u64::from(env_u32("HTTP_RATE_WINDOW_SECS", 60))),
            guest_max_per_window: env_u32("HTTP_GUEST_RATE_LIMIT", 20),
        }
    }
}

fn env_u32(name: &str, default: u32) -> u32 {
    std::env::var(name)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

#[derive(Debug, Default)]
struct Bucket {
    events: Vec<Instant>,
}

#[derive(Debug)]
pub struct HttpRateLimiter {
    config: HttpLimitConfig,
    buckets: Mutex<HashMap<String, Bucket>>,
}

impl HttpRateLimiter {
    pub fn new(config: HttpLimitConfig) -> Self {
        Self {
            config,
            buckets: Mutex::new(HashMap::new()),
        }
    }

    pub fn check(&self, key: &str, max: u32) -> bool {
        let mut guard = self.buckets.lock().expect("http rate limiter");
        let bucket = guard.entry(key.to_string()).or_default();
        let now = Instant::now();
        bucket.events.retain(|t| now.duration_since(*t) < self.config.window);
        if bucket.events.len() as u32 >= max {
            return false;
        }
        bucket.events.push(now);
        true
    }

    pub fn config(&self) -> HttpLimitConfig {
        self.config
    }
}

pub async fn rate_limit_middleware(
    State(state): State<std::sync::Arc<AppState>>,
    req: Request<Body>,
    next: Next,
) -> Response {
    let path = req.uri().path().to_string();
    // Health/metrics must remain reachable under load (for probes & scrapers).
    // Live Now catalog is intentionally polled; keep it off the shared game REST budget.
    if path == "/healthz"
        || path == "/readyz"
        || path == "/metrics"
        || path == "/api/v1/live-rooms"
    {
        return next.run(req).await;
    }

    let key = client_key(req.headers());
    let max = if path == "/api/v1/guest-sessions" {
        state.http_limiter.config().guest_max_per_window
    } else {
        state.http_limiter.config().max_requests_per_window
    };

    if !state.http_limiter.check(&key, max) {
        state
            .metrics
            .rate_limited
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let body = judgement_protocol::ApiErrorBody {
            error: judgement_protocol::ApiErrorDetail {
                code: "RATE_LIMITED".into(),
                message: "HTTP rate limit exceeded; try again shortly".into(),
            },
        };
        return (StatusCode::TOO_MANY_REQUESTS, Json(body)).into_response();
    }

    state
        .metrics
        .http_requests
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    next.run(req).await
}

fn client_key(headers: &HeaderMap) -> String {
    if let Some(auth) = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
    {
        // Do not store the raw token in metrics/logs; hash-ish truncation is enough as a key.
        return format!("tok:{}", &auth[..auth.len().min(16)]);
    }
    if let Some(fwd) = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next())
    {
        return format!("ip:{}", fwd.trim());
    }
    if let Some(real) = headers.get("x-real-ip").and_then(|v| v.to_str().ok()) {
        return format!("ip:{real}");
    }
    "anon".into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enforces_limit() {
        let limiter = HttpRateLimiter::new(HttpLimitConfig {
            max_requests_per_window: 2,
            window: Duration::from_secs(60),
            guest_max_per_window: 2,
        });
        assert!(limiter.check("a", 2));
        assert!(limiter.check("a", 2));
        assert!(!limiter.check("a", 2));
        assert!(limiter.check("b", 2));
    }
}
