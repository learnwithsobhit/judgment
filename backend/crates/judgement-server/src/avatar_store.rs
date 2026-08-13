//! Avatar object storage: local disk (dev) or AWS S3 (prod).
//!
//! Pattern ported from Sabarimala Yatra (`media_store` + SigV4 presign):
//! client `presign` → `PUT` with signed headers → `confirm` → store public URL.

use std::collections::BTreeMap;
use std::path::PathBuf;

use chrono::Utc;
use tokio::fs;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use crate::s3_presign::{
    encode_s3_object_path, path_style_object_path, presign_delete_url, presign_put_url,
};

const PRESIGN_TTL_SECS: u64 = 900;
const UNCONFIRMED_TAG: &str = "state=unconfirmed";

#[derive(Clone, Debug)]
pub struct S3Config {
    pub bucket: String,
    pub region: String,
    pub access_key: String,
    pub secret_key: String,
    pub endpoint: Option<String>,
    pub public_base: String,
}

#[derive(Clone)]
pub enum AvatarStore {
    Local { upload_dir: String },
    S3 { cfg: S3Config },
    /// Uploads disabled (guest/pack-only).
    Disabled,
}

#[derive(Debug, serde::Serialize)]
pub struct PresignedUpload {
    pub method: String,
    pub upload_url: String,
    pub headers: BTreeMap<String, String>,
    pub key: String,
    pub public_url: String,
    pub expires_in_sec: i64,
}

impl AvatarStore {
    pub fn from_env() -> Self {
        let backend = std::env::var("MEDIA_BACKEND").unwrap_or_else(|_| "disabled".into());
        if !backend.eq_ignore_ascii_case("s3") && !backend.eq_ignore_ascii_case("local") {
            return AvatarStore::Disabled;
        }
        if backend.eq_ignore_ascii_case("local") {
            let upload_dir =
                std::env::var("UPLOAD_DIR").unwrap_or_else(|_| "./uploads/avatars".into());
            return AvatarStore::Local { upload_dir };
        }
        let bucket = match std::env::var("S3_BUCKET") {
            Ok(v) if !v.trim().is_empty() => v,
            _ => {
                tracing::warn!("MEDIA_BACKEND=s3 but S3_BUCKET unset — avatar uploads disabled");
                return AvatarStore::Disabled;
            }
        };
        let access_key = match std::env::var("AWS_ACCESS_KEY_ID") {
            Ok(v) if !v.trim().is_empty() => v,
            _ => {
                tracing::warn!("AWS_ACCESS_KEY_ID unset — avatar uploads disabled");
                return AvatarStore::Disabled;
            }
        };
        let secret_key = match std::env::var("AWS_SECRET_ACCESS_KEY") {
            Ok(v) if !v.trim().is_empty() => v,
            _ => {
                tracing::warn!("AWS_SECRET_ACCESS_KEY unset — avatar uploads disabled");
                return AvatarStore::Disabled;
            }
        };
        let public_base = std::env::var("MEDIA_PUBLIC_BASE_URL")
            .ok()
            .or_else(|| std::env::var("S3_PUBLIC_URL").ok())
            .map(|b| b.trim_end_matches('/').to_string())
            .filter(|b| !b.is_empty());
        let Some(public_base) = public_base else {
            tracing::warn!("MEDIA_PUBLIC_BASE_URL unset — avatar uploads disabled");
            return AvatarStore::Disabled;
        };
        AvatarStore::S3 {
            cfg: S3Config {
                bucket,
                region: std::env::var("AWS_REGION").unwrap_or_else(|_| "ap-south-1".into()),
                access_key,
                secret_key,
                endpoint: std::env::var("S3_ENDPOINT").ok().filter(|s| !s.trim().is_empty()),
                public_base,
            },
        }
    }

    pub fn enabled(&self) -> bool {
        !matches!(self, AvatarStore::Disabled)
    }

    pub fn build_key(&self, user_id: Uuid, content_type: &str) -> String {
        let ext = match content_type {
            "image/png" => "png",
            "image/webp" => "webp",
            _ => "jpg",
        };
        format!("avatars/{}/{}.{}", user_id, Uuid::new_v4(), ext)
    }

    pub fn key_belongs_to_user(&self, key: &str, user_id: Uuid) -> bool {
        !key.contains("..") && key.starts_with(&format!("avatars/{}/", user_id))
    }

    pub fn read_url(&self, key: &str) -> String {
        match self {
            AvatarStore::Local { .. } => format!("/api/v1/me/avatar/files/{key}"),
            AvatarStore::S3 { cfg, .. } => format!("{}/{}", cfg.public_base, key),
            AvatarStore::Disabled => String::new(),
        }
    }

    pub fn presign_put(&self, key: &str, content_type: &str) -> Result<PresignedUpload, String> {
        let mut headers = BTreeMap::new();
        headers.insert("Content-Type".to_string(), content_type.to_string());
        match self {
            AvatarStore::Disabled => Err("avatar uploads are not configured".into()),
            AvatarStore::Local { .. } => Ok(PresignedUpload {
                method: "PUT".into(),
                upload_url: format!("/api/v1/me/avatar/blob/{key}"),
                headers,
                key: key.to_string(),
                public_url: self.read_url(key),
                expires_in_sec: PRESIGN_TTL_SECS as i64,
            }),
            AvatarStore::S3 { cfg, .. } => {
                let (host, uri, https) = s3_target(cfg, key)?;
                let upload_url = presign_put_url(
                    &host,
                    &uri,
                    &cfg.region,
                    &cfg.access_key,
                    &cfg.secret_key,
                    content_type,
                    None,
                    Some(UNCONFIRMED_TAG),
                    PRESIGN_TTL_SECS,
                    https,
                )
                .map_err(|e| e.to_string())?;
                headers.insert("x-amz-tagging".to_string(), UNCONFIRMED_TAG.to_string());
                Ok(PresignedUpload {
                    method: "PUT".into(),
                    upload_url,
                    headers,
                    key: key.to_string(),
                    public_url: self.read_url(key),
                    expires_in_sec: PRESIGN_TTL_SECS as i64,
                })
            }
        }
    }

    pub async fn put_local_bytes(&self, key: &str, bytes: &[u8]) -> Result<(), String> {
        let AvatarStore::Local { upload_dir } = self else {
            return Err("local upload only".into());
        };
        let full = PathBuf::from(upload_dir).join(key);
        if let Some(parent) = full.parent() {
            fs::create_dir_all(parent)
                .await
                .map_err(|e| e.to_string())?;
        }
        let mut f = fs::File::create(&full).await.map_err(|e| e.to_string())?;
        f.write_all(bytes).await.map_err(|e| e.to_string())?;
        let _ = Utc::now();
        Ok(())
    }

    pub async fn mark_confirmed(&self, key: &str) -> Result<(), String> {
        let AvatarStore::S3 { cfg } = self else {
            return Ok(());
        };
        let (host, uri, https) = s3_target(cfg, key)?;
        let url = presign_delete_url(
            &host,
            &uri,
            &cfg.region,
            &cfg.access_key,
            &cfg.secret_key,
            PRESIGN_TTL_SECS,
            https,
            Some("tagging"),
        )
        .map_err(|e| e.to_string())?;
        let client = reqwest::Client::new();
        for attempt in 0..2 {
            match client.delete(&url).send().await {
                Ok(resp) if resp.status().is_success() => return Ok(()),
                Ok(resp) => tracing::warn!(status = %resp.status(), key, "untag attempt failed"),
                Err(e) => tracing::warn!(error = %e, key, "untag request error"),
            }
            if attempt == 0 {
                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
            }
        }
        Err(format!("failed to clear unconfirmed tag for {key}"))
    }

    pub async fn delete(&self, key: &str) -> Result<(), String> {
        match self {
            AvatarStore::Disabled => Ok(()),
            AvatarStore::Local { upload_dir } => {
                let path = PathBuf::from(upload_dir).join(key);
                let _ = fs::remove_file(path).await;
                Ok(())
            }
            AvatarStore::S3 { cfg } => {
                let (host, uri, https) = s3_target(cfg, key)?;
                let url = presign_delete_url(
                    &host,
                    &uri,
                    &cfg.region,
                    &cfg.access_key,
                    &cfg.secret_key,
                    PRESIGN_TTL_SECS,
                    https,
                    None,
                )
                .map_err(|e| e.to_string())?;
                let _ = reqwest::Client::new().delete(&url).send().await;
                Ok(())
            }
        }
    }
}

fn s3_target(cfg: &S3Config, key: &str) -> Result<(String, String, bool), String> {
    if let Some(ep) = cfg.endpoint.as_ref().filter(|e| !e.trim().is_empty()) {
        let u = url::Url::parse(ep.trim()).map_err(|e| format!("invalid S3_ENDPOINT: {e}"))?;
        let https = u.scheme() == "https";
        let host = u
            .host_str()
            .ok_or_else(|| "S3_ENDPOINT has no host".to_string())?
            .to_string();
        let host_header = match u.port() {
            Some(p) => format!("{host}:{p}"),
            None => host,
        };
        let uri = path_style_object_path(&cfg.bucket, key);
        Ok((host_header, uri, https))
    } else {
        let host_header = format!(
            "{}.s3.{}.amazonaws.com",
            cfg.bucket.trim(),
            cfg.region.trim()
        );
        let uri = encode_s3_object_path(key);
        Ok((host_header, uri, true))
    }
}

pub fn allowed_avatar_content_type(ct: &str) -> bool {
    matches!(ct, "image/jpeg" | "image/jpg" | "image/png" | "image/webp")
}
