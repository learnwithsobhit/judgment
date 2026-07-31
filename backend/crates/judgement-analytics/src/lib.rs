//! Deterministic analytics for coaching and highlights (PLAN.md Phase 8).
//!
//! This crate never calls an LLM. AI layers may only narrate these facts.

pub mod error;
pub mod highlights;
pub mod player;
pub mod round;
pub mod score_table;

pub use error::AnalyticsError;
pub use highlights::{compute_highlights, GameHighlights, HighlightFact};
pub use player::{analyse_player, NotableRound, PlayerGameAnalysis};
pub use round::{summarize_round, RoundOutcome, RoundSummary};
pub use score_table::{
    score_table_from_history_scores, score_table_from_rounds, scores_from_value,
};
