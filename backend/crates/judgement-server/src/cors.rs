//! Explicit CORS / origin allow-list (PLAN.md §21, Phase 9).

use tower_http::cors::{AllowOrigin, CorsLayer};

/// Build a CORS layer from `ALLOWED_ORIGINS`.
///
/// - Unset / empty / `*` → permissive (local development); logs a warning.
/// - Comma-separated absolute origins → strict allow-list.
pub fn cors_layer_from_env() -> CorsLayer {
    match std::env::var("ALLOWED_ORIGINS") {
        Ok(raw) => {
            let trimmed = raw.trim();
            if trimmed.is_empty() || trimmed == "*" {
                tracing::warn!("ALLOWED_ORIGINS is permissive — set explicit origins in production");
                return CorsLayer::permissive();
            }
            let origins: Vec<_> = trimmed
                .split(',')
                .map(|s| s.trim())
                .filter(|s| !s.is_empty())
                .filter_map(|s| s.parse().ok())
                .collect();
            if origins.is_empty() {
                tracing::warn!("ALLOWED_ORIGINS had no valid origins — falling back to permissive");
                return CorsLayer::permissive();
            }
            tracing::info!(count = origins.len(), "CORS allow-list enabled");
            CorsLayer::new()
                .allow_origin(AllowOrigin::list(origins))
                .allow_methods([
                    axum::http::Method::GET,
                    axum::http::Method::POST,
                    axum::http::Method::OPTIONS,
                ])
                .allow_headers([
                    axum::http::header::AUTHORIZATION,
                    axum::http::header::CONTENT_TYPE,
                    axum::http::header::ACCEPT,
                ])
                .allow_credentials(true)
        }
        Err(_) => {
            tracing::warn!("ALLOWED_ORIGINS unset — permissive CORS (dev only)");
            CorsLayer::permissive()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_without_panic() {
        // Smoke: constructing the layer must not panic regardless of env.
        let _ = cors_layer_from_env();
    }
}
