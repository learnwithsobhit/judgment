//! Core domain types for the Judgement card game.
//!
//! This crate is pure data: cards, identifiers, rule configuration, errors,
//! and score bookkeeping. It has no dependency on networking, persistence,
//! or the game engine itself (see PLAN.md §9.3).

pub mod cards;
pub mod errors;
pub mod ids;
pub mod player;
pub mod rules;
pub mod score;

pub use cards::{full_deck, Card, CardId, Rank, Suit};
pub use errors::{GameError, TrickEvaluationError};
pub use ids::{
    ActionId, EventId, GameId, PlayerId, RoomId, RoundId, RsvpId, SessionId, TrickId,
};
pub use player::{ConnectionStatus, PlayerState};
pub use rules::{
    max_cards_per_player, BiddingRule, GameRules, ManualRoundStep, RoundPattern, RoundSchedule,
    RoundScheduleError, RoundScheduleMode, ScoringRule, TrumpRule, EVENT_SEAT_CAP,
    EVENT_WAITLIST_CAP, MAX_MANUAL_REPEAT, MAX_MANUAL_ROUNDS, MAX_PLAYERS, MIN_PLAYERS,
    TRUMP_ROTATION,
};
pub use score::{RankedPlayer, RoundScoreEntry, ScoreTable};
