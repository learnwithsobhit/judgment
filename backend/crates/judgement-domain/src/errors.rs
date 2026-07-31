//! Deterministic domain errors with stable reason codes (PLAN.md §18.2).

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::cards::{CardId, Suit};

/// Rejection reasons for player commands. Each variant maps to a stable
/// SCREAMING_SNAKE reason code consumed by explanation templates.
#[derive(Debug, Clone, PartialEq, Eq, Error, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "code")]
pub enum GameError {
    #[error("it is not your turn")]
    NotYourTurn,
    #[error("this action is not allowed in the current phase")]
    WrongPhase,
    #[error("card {card} is not in your hand")]
    CardNotInHand { card: CardId },
    #[error("you must follow the lead suit ({lead_suit})")]
    MustFollowSuit { lead_suit: Suit, attempted: CardId },
    #[error("bid {bid} is outside the allowed range 0..={max}")]
    BidOutOfRange { bid: u8, max: u8 },
    #[error("as dealer you cannot bid {bid}: total bids would equal the {tricks_available} tricks available")]
    DealerBidRestriction { bid: u8, tricks_available: u8 },
    #[error("you have already placed a bid this round")]
    BidAlreadyPlaced,
    #[error("your client state is stale; resynchronise")]
    StaleState { expected_version: u64, actual_version: u64 },
    #[error("this action was already processed")]
    ActionAlreadyProcessed,
    #[error("player is not part of this game")]
    PlayerNotInGame,
    #[error("the game is already finished")]
    GameAlreadyFinished,
    #[error("the game requires exactly {required} players but has {actual}")]
    InvalidPlayerCount { required: u8, actual: u8 },
}

impl GameError {
    /// Stable machine-readable reason code.
    pub fn reason_code(&self) -> &'static str {
        match self {
            GameError::NotYourTurn => "NOT_YOUR_TURN",
            GameError::WrongPhase => "WRONG_PHASE",
            GameError::CardNotInHand { .. } => "CARD_NOT_IN_HAND",
            GameError::MustFollowSuit { .. } => "MUST_FOLLOW_SUIT",
            GameError::BidOutOfRange { .. } => "BID_OUT_OF_RANGE",
            GameError::DealerBidRestriction { .. } => "DEALER_BID_RESTRICTION",
            GameError::BidAlreadyPlaced => "BID_ALREADY_PLACED",
            GameError::StaleState { .. } => "STALE_STATE",
            GameError::ActionAlreadyProcessed => "ACTION_ALREADY_PROCESSED",
            GameError::PlayerNotInGame => "PLAYER_NOT_IN_GAME",
            GameError::GameAlreadyFinished => "GAME_ALREADY_FINISHED",
            GameError::InvalidPlayerCount { .. } => "INVALID_PLAYER_COUNT",
        }
    }
}

/// Errors from the pure trick evaluator (PLAN.md §5.7).
#[derive(Debug, Clone, PartialEq, Eq, Error, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "code")]
pub enum TrickEvaluationError {
    #[error("cannot evaluate an empty trick")]
    EmptyTrick,
    #[error("no card of the lead suit or trump was played")]
    NoEligibleCard,
}
