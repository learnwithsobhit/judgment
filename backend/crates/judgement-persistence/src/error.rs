use thiserror::Error;

#[derive(Debug, Error)]
pub enum PersistError {
    #[error("database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("serialization error: {0}")]
    Serde(#[from] serde_json::Error),

    #[error("{0}")]
    Conflict(String),

    #[error("{0}")]
    NotFound(String),
}
