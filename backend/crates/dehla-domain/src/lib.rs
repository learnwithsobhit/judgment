//! Dehla Pakad domain types (IDs, cards, rule-pack labels).
//!
//! No networking or persistence. Judgement domain is intentionally separate
//! (ADR 0006 — copy/redevelop, do not modify Judgement crates).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub type PlayerId = Uuid;
pub type GameId = Uuid;
pub type RoomId = Uuid;
pub type SessionId = Uuid;

/// Fixed table size for classic partnership play.
pub const TABLE_SEATS: u8 = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Suit {
    Spades,
    Hearts,
    Diamonds,
    Clubs,
}

impl Suit {
    pub const ALL: [Suit; 4] = [Suit::Spades, Suit::Hearts, Suit::Diamonds, Suit::Clubs];
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Rank {
    Two,
    Three,
    Four,
    Five,
    Six,
    Seven,
    Eight,
    Nine,
    Ten,
    Jack,
    Queen,
    King,
    Ace,
}

impl Rank {
    pub const ALL: [Rank; 13] = [
        Rank::Two,
        Rank::Three,
        Rank::Four,
        Rank::Five,
        Rank::Six,
        Rank::Seven,
        Rank::Eight,
        Rank::Nine,
        Rank::Ten,
        Rank::Jack,
        Rank::Queen,
        Rank::King,
        Rank::Ace,
    ];

    /// A > K > … > 2
    pub fn strength(self) -> u8 {
        match self {
            Rank::Two => 2,
            Rank::Three => 3,
            Rank::Four => 4,
            Rank::Five => 5,
            Rank::Six => 6,
            Rank::Seven => 7,
            Rank::Eight => 8,
            Rank::Nine => 9,
            Rank::Ten => 10,
            Rank::Jack => 11,
            Rank::Queen => 12,
            Rank::King => 13,
            Rank::Ace => 14,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Card {
    pub suit: Suit,
    pub rank: Rank,
}

impl Card {
    pub fn is_ten(self) -> bool {
        matches!(self.rank, Rank::Ten)
    }
}

pub fn standard_deck() -> Vec<Card> {
    let mut cards = Vec::with_capacity(52);
    for suit in Suit::ALL {
        for rank in Rank::ALL {
            cards.push(Card { suit, rank });
        }
    }
    cards
}

/// Named rule packs — never apply silently (product plan §1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum RulePack {
    #[default]
    DehlaPakadClassic,
    MendikotClassic,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TrumpMethod {
    #[default]
    CutTrump,
    AnnouncedTrump,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum PartnershipMode {
    #[default]
    RandomOpposite,
    ChoosePartners,
}

/// 2–2 tens tie resolution (Classic default: non-dealing team).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TensTieRule {
    #[default]
    NonDealerWins,
    MostTricks,
    Draw,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TeamId {
    A,
    B,
}

impl TeamId {
    pub fn other(self) -> Self {
        match self {
            TeamId::A => TeamId::B,
            TeamId::B => TeamId::A,
        }
    }
}

/// Seats numbered 0..3 anticlockwise; next player = (seat + 1) % 4.
pub fn next_seat(seat: u8) -> u8 {
    (seat + 1) % TABLE_SEATS
}

/// Opposite partners: (0,2) and (1,3).
pub fn team_for_seat(seat: u8) -> TeamId {
    if seat % 2 == 0 {
        TeamId::A
    } else {
        TeamId::B
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DomainError {
    #[error("invalid seat")]
    InvalidSeat,
    #[error("table requires exactly {TABLE_SEATS} players")]
    WrongPlayerCount,
}
