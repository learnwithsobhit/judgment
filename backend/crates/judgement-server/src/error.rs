//! Uniform REST error responses.

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use thiserror::Error;

use judgement_protocol::{ApiErrorBody, ApiErrorDetail};

#[derive(Debug, Clone, Error)]
pub enum ApiError {
    #[error("missing or invalid credentials")]
    Unauthorized,
    #[error("{0} not found")]
    NotFound(&'static str),
    #[error("{0}")]
    Forbidden(String),
    #[error("{0}")]
    Conflict(String),
    #[error("{0}")]
    BadRequest(String),
    #[error("{0}")]
    TooManyRequests(String),
    /// Product capacity gate — new rooms/starts rejected; live games untouched.
    #[error("{0}")]
    CapacityFull(String),
    /// Preferred reclaim `player_id` is not currently vacant.
    #[error("{0}")]
    SeatNotVacant(String),
}

impl ApiError {
    fn status(&self) -> StatusCode {
        match self {
            ApiError::Unauthorized => StatusCode::UNAUTHORIZED,
            ApiError::NotFound(_) => StatusCode::NOT_FOUND,
            ApiError::Forbidden(_) => StatusCode::FORBIDDEN,
            ApiError::Conflict(_) => StatusCode::CONFLICT,
            ApiError::BadRequest(_) => StatusCode::BAD_REQUEST,
            ApiError::TooManyRequests(_) => StatusCode::TOO_MANY_REQUESTS,
            ApiError::CapacityFull(_) => StatusCode::SERVICE_UNAVAILABLE,
            ApiError::SeatNotVacant(_) => StatusCode::CONFLICT,
        }
    }

    fn code(&self) -> &'static str {
        match self {
            ApiError::Unauthorized => "UNAUTHORIZED",
            ApiError::NotFound(_) => "NOT_FOUND",
            ApiError::Forbidden(_) => "FORBIDDEN",
            ApiError::Conflict(_) => "CONFLICT",
            ApiError::BadRequest(_) => "BAD_REQUEST",
            ApiError::TooManyRequests(_) => "RATE_LIMITED",
            ApiError::CapacityFull(_) => "CAPACITY_FULL",
            ApiError::SeatNotVacant(_) => "SEAT_NOT_VACANT",
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let body = ApiErrorBody {
            error: ApiErrorDetail {
                code: self.code().to_string(),
                message: self.to_string(),
            },
        };
        (self.status(), Json(body)).into_response()
    }
}
