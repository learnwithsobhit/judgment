//! Bot strategies and full-game simulation (PLAN.md §17, Phase 2 seed).
//!
//! Bots receive the same personalised [`PlayerGameView`] as human clients —
//! never hidden opponent state — and their commands pass through the normal
//! engine validation path. The trait is synchronous here; the Phase 3 server
//! wraps bot compute in off-actor tasks (PLAN.md §9.1).

pub mod random_bot;
pub mod rule_based_bot;
pub mod simulation;

use judgement_domain::CardId;
use judgement_engine::PlayerGameView;
use thiserror::Error;

pub use random_bot::RandomBot;
pub use rule_based_bot::RuleBasedBot;
pub use simulation::{
    simulate_game, simulate_game_with_players, SimulationError, SimulationOutcome,
};

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum BotError {
    #[error("no legal action is available in the current view")]
    NoLegalAction,
}

pub trait BotStrategy: Send {
    fn choose_bid(&mut self, view: &PlayerGameView) -> Result<u8, BotError>;
    fn choose_card(&mut self, view: &PlayerGameView) -> Result<CardId, BotError>;
}
