//! Minimal AWS SigV4 presigned URLs for S3-compatible endpoints (no AWS SDK).
//!
//! Ported from the Gopal Mandir API. Supports presigned `PUT` (upload) and
//! `DELETE` (cleanup) requests against real AWS S3 (virtual-hosted style) or an
//! S3-compatible endpoint such as MinIO (path style).

use chrono::Utc;
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

type HmacSha256 = Hmac<Sha256>;

fn sha256_hex(data: impl AsRef<[u8]>) -> String {
    let mut h = Sha256::new();
    h.update(data.as_ref());
    hex::encode(h.finalize())
}

fn sign_hmac(key: &[u8], msg: &[u8]) -> Vec<u8> {
    let mut mac = HmacSha256::new_from_slice(key).expect("HMAC key length");
    mac.update(msg);
    mac.finalize().into_bytes().to_vec()
}

fn signing_key(secret: &str, date_stamp: &str, region: &str, service: &str) -> Vec<u8> {
    let k_date = sign_hmac(format!("AWS4{}", secret).as_bytes(), date_stamp.as_bytes());
    let k_region = sign_hmac(&k_date, region.as_bytes());
    let k_service = sign_hmac(&k_region, service.as_bytes());
    sign_hmac(&k_service, b"aws4_request")
}

/// Build a presigned `PUT` URL. `host` is the HTTP Host header value.
/// `canonical_uri` must start with `/` and use URI-encoded path segments.
/// The client MUST send back every signed header verbatim: `Content-Type`,
/// and, when set, `Cache-Control` and `x-amz-tagging` (e.g. `state=unconfirmed`).
#[allow(clippy::too_many_arguments)]
pub fn presign_put_url(
    host: &str,
    canonical_uri: &str,
    region: &str,
    access_key: &str,
    secret_key: &str,
    content_type: &str,
    cache_control: Option<&str>,
    tagging: Option<&str>,
    expires_secs: u64,
    use_https: bool,
) -> Result<String, &'static str> {
    if !canonical_uri.starts_with('/') {
        return Err("canonical_uri must start with /");
    }
    let now = Utc::now();
    let amz_date = now.format("%Y%m%dT%H%M%SZ").to_string();
    let date_stamp = now.format("%Y%m%d").to_string();
    let credential_scope = format!("{}/{}/s3/aws4_request", date_stamp, region);
    let credential = format!("{}/{}", access_key, credential_scope);

    // Collect headers, then sort by name so canonical order is correct.
    let mut header_pairs: Vec<(&str, String)> = vec![
        ("content-type", content_type.trim().to_string()),
        ("host", host.trim().to_string()),
    ];
    if let Some(cc) = cache_control.map(str::trim).filter(|s| !s.is_empty()) {
        header_pairs.push(("cache-control", cc.to_string()));
    }
    if let Some(tag) = tagging.map(str::trim).filter(|s| !s.is_empty()) {
        header_pairs.push(("x-amz-tagging", tag.to_string()));
    }
    header_pairs.sort_by(|a, b| a.0.cmp(b.0));

    let signed_headers = header_pairs
        .iter()
        .map(|(k, _)| *k)
        .collect::<Vec<_>>()
        .join(";");
    let canonical_headers = header_pairs
        .iter()
        .map(|(k, v)| format!("{}:{}\n", k, v))
        .collect::<String>();

    let params = base_params(&credential, &amz_date, expires_secs, &signed_headers);
    let canonical_qs = encode_params(&params);

    finalize(
        "PUT",
        host,
        canonical_uri,
        region,
        secret_key,
        &date_stamp,
        &amz_date,
        &credential_scope,
        &signed_headers,
        &canonical_headers,
        &canonical_qs,
        params,
        use_https,
    )
}

/// Build a presigned `DELETE` URL (host-only signed headers). When
/// `subresource` is set (e.g. `"tagging"`) it deletes that subresource instead
/// of the object itself — used to drop the `state=unconfirmed` tag on confirm.
#[allow(clippy::too_many_arguments)]
pub fn presign_delete_url(
    host: &str,
    canonical_uri: &str,
    region: &str,
    access_key: &str,
    secret_key: &str,
    expires_secs: u64,
    use_https: bool,
    subresource: Option<&str>,
) -> Result<String, &'static str> {
    if !canonical_uri.starts_with('/') {
        return Err("canonical_uri must start with /");
    }
    let now = Utc::now();
    let amz_date = now.format("%Y%m%dT%H%M%SZ").to_string();
    let date_stamp = now.format("%Y%m%d").to_string();
    let credential_scope = format!("{}/{}/s3/aws4_request", date_stamp, region);
    let credential = format!("{}/{}", access_key, credential_scope);
    let signed_headers = "host";

    let mut params = base_params(&credential, &amz_date, expires_secs, signed_headers);
    if let Some(sr) = subresource.map(str::trim).filter(|s| !s.is_empty()) {
        params.insert(sr.to_string(), String::new());
    }
    let canonical_qs = encode_params(&params);
    let canonical_headers = format!("host:{}\n", host.trim());

    finalize(
        "DELETE",
        host,
        canonical_uri,
        region,
        secret_key,
        &date_stamp,
        &amz_date,
        &credential_scope,
        signed_headers,
        &canonical_headers,
        &canonical_qs,
        params,
        use_https,
    )
}

fn base_params(
    credential: &str,
    amz_date: &str,
    expires_secs: u64,
    signed_headers: &str,
) -> BTreeMap<String, String> {
    let mut params: BTreeMap<String, String> = BTreeMap::new();
    params.insert("X-Amz-Algorithm".into(), "AWS4-HMAC-SHA256".into());
    params.insert("X-Amz-Credential".into(), credential.to_string());
    params.insert("X-Amz-Date".into(), amz_date.to_string());
    params.insert("X-Amz-Expires".into(), expires_secs.to_string());
    params.insert("X-Amz-SignedHeaders".into(), signed_headers.to_string());
    params
}

fn encode_params(params: &BTreeMap<String, String>) -> String {
    params
        .iter()
        .map(|(k, v)| format!("{}={}", utf8_encode(k), utf8_encode(v)))
        .collect::<Vec<_>>()
        .join("&")
}

#[allow(clippy::too_many_arguments)]
fn finalize(
    method: &str,
    host: &str,
    canonical_uri: &str,
    region: &str,
    secret_key: &str,
    date_stamp: &str,
    amz_date: &str,
    credential_scope: &str,
    signed_headers: &str,
    canonical_headers: &str,
    canonical_qs: &str,
    mut params: BTreeMap<String, String>,
    use_https: bool,
) -> Result<String, &'static str> {
    let payload_hash = "UNSIGNED-PAYLOAD";
    let canonical_request = format!(
        "{}\n{}\n{}\n{}\n{}\n{}",
        method, canonical_uri, canonical_qs, canonical_headers, signed_headers, payload_hash
    );
    let hashed_request = sha256_hex(canonical_request.as_bytes());
    let string_to_sign = format!(
        "AWS4-HMAC-SHA256\n{}\n{}\n{}",
        amz_date, credential_scope, hashed_request
    );
    let key = signing_key(secret_key, date_stamp, region, "s3");
    let sig = hex::encode(sign_hmac(&key, string_to_sign.as_bytes()));

    params.insert("X-Amz-Signature".into(), sig);
    let query = encode_params(&params);

    let scheme = if use_https { "https" } else { "http" };
    Ok(format!(
        "{}://{}{}?{}",
        scheme,
        host.trim(),
        canonical_uri,
        query
    ))
}

fn utf8_encode(s: &str) -> String {
    urlencoding::encode(s).replace('+', "%20")
}

/// Virtual-hosted-style object path (`/key/segments`) for real AWS S3.
pub fn encode_s3_object_path(key: &str) -> String {
    let mut out = String::from("/");
    let parts: Vec<&str> = key.split('/').filter(|p| !p.is_empty()).collect();
    for (i, p) in parts.iter().enumerate() {
        if i > 0 {
            out.push('/');
        }
        out.push_str(&utf8_encode(p));
    }
    out
}

/// Path-style object path (`/bucket/key/segments`) for MinIO / custom endpoints.
pub fn path_style_object_path(bucket: &str, key: &str) -> String {
    let mut segs: Vec<&str> = vec![bucket.trim()];
    segs.extend(key.split('/').map(str::trim).filter(|s| !s.is_empty()));
    let mut out = String::new();
    for s in segs {
        out.push('/');
        out.push_str(&utf8_encode(s));
    }
    out
}
