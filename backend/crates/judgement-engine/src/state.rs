//! Authoritative internal game state (PLAN.md §6, §7.3, §7.4).
//!
//! `InternalGameState` must never be serialized to clients; clients receive
//! personalised [`crate::projection::PlayerGameView`] projections only.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use judgement_domain::{Card, GameId, GameRules, PlayerId, PlayerState, ScoreTable, Suit};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GamePhase {
    Lobby,
    RoundSetup,
    Dealing,
    Bidding,
    Playing,
    RoundScoring,
    GameScoring,
    Finished,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlayedCard {
    pub player_id: PlayerId,
    pub card: Card,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompletedTrick {
    pub trick_index: u32,
    pub lead_suit: Suit,
    pub plays: Vec<PlayedCard>,
    pub winner: PlayerId,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoundState {
    pub round_index: usize,
    pub cards_per_player: u8,
    /// Clockwise from the dealer's left; the dealer is always last.
    pub bidding_order: Vec<PlayerId>,
    pub bids: HashMap<PlayerId, u8>,
    pub hands: HashMap<PlayerId, Vec<Card>>,
    pub current_trick: Vec<PlayedCard>,
    pub completed_tricks: Vec<CompletedTrick>,
    pub current_turn: PlayerId,
    pub tricks_won: HashMap<PlayerId, u8>,
}

impl RoundState {
    pub fn lead_suit(&self) -> Option<Suit> {
        self.current_trick.first().map(|play| play.card.suit)
    }

    pub fn all_bids_placed(&self, player_count: usize) -> bool {
        self.bids.len() == player_count
    }

    pub fn all_tricks_complete(&self) -> bool {
        self.completed_tricks.len() == self.cards_per_player as usize
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InternalGameState {
    pub game_id: GameId,
    /// Incremented on every accepted mutating command.
    pub version: u64,
    pub phase: GamePhase,
    pub rules: GameRules,
    pub dealer: PlayerId,
    /// Seat order is table order; index == seat for MVP.
    pub players: Vec<PlayerState>,
    /// Undealt remainder of the deck (excluding the revealed trump card).
    pub deck: Vec<Card>,
    /// The effective trump suit for the current round, however it was decided
    /// (revealed card or fixed rotation — ADR 0003).
    pub trump: Option<Suit>,
    /// The revealed card whose suit is trump (revealed-card mode only);
    /// out of play for the round.
    pub trump_card: Option<Card>,
    pub current_round: Option<RoundState>,
    pub score_table: ScoreTable,
}

impl InternalGameState {
    pub fn player_ids(&self) -> Vec<PlayerId> {
        self.players.iter().map(|p| p.id).collect()
    }

    pub fn contains_player(&self, player_id: PlayerId) -> bool {
        self.players.iter().any(|p| p.id == player_id)
    }

    /// The next player clockwise from `player_id` in seat order.
    pub fn next_clockwise(&self, player_id: PlayerId) -> PlayerId {
        let index = self
            .players
            .iter()
            .position(|p| p.id == player_id)
            .expect("player must be seated");
        self.players[(index + 1) % self.players.len()].id
    }

    pub fn trump_suit(&self) -> Option<Suit> {
        self.trump
    }
}
