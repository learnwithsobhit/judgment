//! Pure Judgement game engine (PLAN.md Phase 1).
//!
//! This crate is a deterministic state machine with no dependency on Axum,
//! PostgreSQL, or any transport. The server (Phase 3) wraps it in an actor;
//! bots and tests drive it directly.

pub mod engine;
pub mod events;
pub mod projection;
pub mod scoring;
pub mod shuffle;
pub mod state;
pub mod trick;

pub use engine::GameEngine;
pub use events::GameEvent;
pub use projection::{
    CompletedTrickView, LeaderView, LegalActionView, OpponentView, PlayerGameView, PlayerScore,
    PublicBid, PublicRoundState, RoundScoreLine, RoundScoreView,
};
pub use scoring::{scoring_strategy_for, ExactBidScoring, ScoringContext, ScoringStrategy};
pub use shuffle::{DeckShuffler, SecureShuffler, SeededShuffler};
pub use state::{CompletedTrick, GamePhase, InternalGameState, PlayedCard, RoundState};
pub use trick::{
    determine_trick_winner, explain_trick_winner, trick_reason, TrickWinnerExplanation,
};
