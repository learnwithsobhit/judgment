use thiserror::Error;

#[derive(Debug, Error)]
pub enum RagError {
    #[error("{0}")]
    Message(String),
    #[error("embedding failed: {0}")]
    Embed(String),
    #[error("store error: {0}")]
    Store(String),
}

impl RagError {
    pub fn msg(s: impl Into<String>) -> Self {
        Self::Message(s.into())
    }
}
