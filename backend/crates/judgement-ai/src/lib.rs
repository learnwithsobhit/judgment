//! Explanations and curated FAQ (PLAN.md Phase 7, ADR 0002).
//!
//! Critical path is deterministic: engine reason codes → templates / FAQ map →
//! structured citations. Optional Rig rewrite is feature-gated (`rig`) and must
//! never decide legality or see hidden cards.

pub mod coach;
pub mod faq;
pub mod rate_limit;
pub mod rewrite;
pub mod service;
pub mod templates;
pub mod types;

pub use coach::{
    coach_from_analysis, coaching_timeout_fallback, highlights_timeout_fallback,
    narrate_highlights, narrate_round_summary, CoachingResponse, HighlightsResponse,
};
pub use faq::FaqIndex;
pub use rate_limit::{AiLimits, AiRateLimiter, RateLimitError};
pub use rewrite::{IdentityRewriter, ToneRewriter};
pub use service::ExplanationService;
pub use templates::{explain_game_error, explain_reason_code, explain_trick};
pub use types::{
    ExplanationResponse, RulesQueryRequest, TrickPlayQuery, TrickQuery,
};
