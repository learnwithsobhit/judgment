use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum AnalyticsError {
    #[error("invalid round scores JSON: {0}")]
    InvalidScores(String),
    #[error("player not found in score table")]
    PlayerNotFound,
    #[error("round {0} not found")]
    RoundNotFound(usize),
    #[error("no rounds recorded for this game")]
    EmptyGame,
}
