//! Domain events emitted by accepted commands (PLAN.md §14.1, Phase 1 subset).

use serde::{Deserialize, Serialize};

use judgement_domain::{Card, PlayerId, RankedPlayer, Suit};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "type")]
pub enum GameEvent {
    GameStarted {
        dealer: PlayerId,
    },
    RoundStarted {
        round_index: usize,
        cards_per_player: u8,
        dealer: PlayerId,
    },
    CardsDealt {
        round_index: usize,
    },
    TrumpSelected {
        round_index: usize,
        trump: Suit,
        /// Present only in revealed-card mode (ADR 0003).
        trump_card: Option<Card>,
    },
    BidPlaced {
        player_id: PlayerId,
        bid: u8,
    },
    CardPlayed {
        player_id: PlayerId,
        card: Card,
    },
    TrickCompleted {
        trick_index: u32,
        winner: PlayerId,
    },
    RoundCompleted {
        round_index: usize,
    },
    DealerRotated {
        new_dealer: PlayerId,
    },
    GameCompleted {
        ranking: Vec<RankedPlayer>,
    },
}
