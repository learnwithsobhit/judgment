//! Same-origin proxy for Telegram portraits.
//!
//! Flutter web cannot paint `telesco.pe` / `t.me` (no CORS). Google's CDN can,
//! so those URLs stay direct. This endpoint only fetches allowlisted Telegram
//! https URLs and never follows a redirect off that list.

use std::sync::OnceLock;
use std::time::Duration;

use axum::extract::Query;
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use reqwest::redirect::Policy;
use serde::Deserialize;

use crate::emotes::{
    is_telegram_photo_host, sanitize_photo_url, strip_photo_revision, PhotoSource,
};

const MAX_PHOTO_BYTES: usize = 512 * 1024;

#[derive(Debug, Deserialize)]
pub struct PhotoQuery {
    /// Stored Telegram `picture` URL. Rejected unless it is on the allow-list.
    pub u: Option<String>,
}

pub async fn proxy_photo(Query(query): Query<PhotoQuery>) -> Response {
    let Some(url) = query
        .u
        .as_deref()
        .and_then(|raw| sanitize_photo_url(PhotoSource::Telegram, Some(raw)))
    else {
        return StatusCode::NOT_FOUND.into_response();
    };

    // `jrev` only changes the browser cache key. Telegram must see its own URL.
    let upstream = strip_photo_revision(&url);
    let response = match photo_client().get(&upstream).send().await {
        Ok(response) if response.status().is_success() => response,
        Ok(_) | Err(_) => return StatusCode::BAD_GATEWAY.into_response(),
    };

    let declared = response
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("application/octet-stream")
        .to_string();

    let bytes = match response.bytes().await {
        Ok(bytes) if !bytes.is_empty() && bytes.len() <= MAX_PHOTO_BYTES => bytes,
        _ => return StatusCode::BAD_GATEWAY.into_response(),
    };

    let Some(mime) = image_mime(&declared, &bytes) else {
        return StatusCode::BAD_GATEWAY.into_response();
    };

    let mut headers = HeaderMap::new();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static(mime));
    headers.insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("private, no-cache"),
    );
    headers.insert(
        header::HeaderName::from_static("cross-origin-resource-policy"),
        HeaderValue::from_static("cross-origin"),
    );
    (StatusCode::OK, headers, bytes).into_response()
}

fn photo_client() -> &'static reqwest::Client {
    static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .connect_timeout(Duration::from_secs(3))
            .redirect(Policy::custom(|attempt| {
                if attempt.previous().len() >= 5 {
                    return attempt.error("too many redirects");
                }
                let url = attempt.url();
                let host = url.host_str().unwrap_or("");
                if url.scheme() == "https" && is_telegram_photo_host(host) {
                    attempt.follow()
                } else {
                    attempt.error("redirect host not allowed")
                }
            }))
            .user_agent("Judgement/1.0 (+https://judgment-railway-test.web.app)")
            .build()
            .expect("telegram photo client")
    })
}

fn image_mime(content_type: &str, bytes: &[u8]) -> Option<&'static str> {
    if bytes.len() >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
        return Some("image/jpeg");
    }
    if bytes.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
        return Some("image/png");
    }
    if bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        return Some("image/webp");
    }
    if bytes.starts_with(b"GIF8") {
        return Some("image/gif");
    }
    match content_type
        .split(';')
        .next()?
        .trim()
        .to_ascii_lowercase()
        .as_str()
    {
        "image/jpeg" | "image/jpg" => Some("image/jpeg"),
        "image/png" => Some("image/png"),
        "image/webp" => Some("image/webp"),
        "image/gif" => Some("image/gif"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sniffs_jpeg_png_and_rejects_html() {
        assert_eq!(
            image_mime("text/html", &[0xFF, 0xD8, 0xFF, 0xE0]),
            Some("image/jpeg")
        );
        assert_eq!(
            image_mime("application/octet-stream", &[0x89, 0x50, 0x4E, 0x47]),
            Some("image/png")
        );
        assert_eq!(image_mime("text/html", b"<html>nope"), None);
    }
}
