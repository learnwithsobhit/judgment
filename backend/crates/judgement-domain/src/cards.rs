//! Cards, suits, and ranks (PLAN.md §7.1).
//!
//! Within a suit, rank order is Two (low) … Ace (high). There is no ranking
//! across suits except via trump and lead-suit rules in the engine.

use std::fmt;
use std::str::FromStr;

use serde::{de, Deserialize, Deserializer, Serialize, Serializer};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Suit {
    Hearts,
    Diamonds,
    Clubs,
    Spades,
}

impl Suit {
    pub const ALL: [Suit; 4] = [Suit::Hearts, Suit::Diamonds, Suit::Clubs, Suit::Spades];

    pub fn name(self) -> &'static str {
        match self {
            Suit::Hearts => "hearts",
            Suit::Diamonds => "diamonds",
            Suit::Clubs => "clubs",
            Suit::Spades => "spades",
        }
    }

    pub fn symbol(self) -> &'static str {
        match self {
            Suit::Hearts => "♥",
            Suit::Diamonds => "♦",
            Suit::Clubs => "♣",
            Suit::Spades => "♠",
        }
    }
}

impl fmt::Display for Suit {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

impl FromStr for Suit {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "hearts" => Ok(Suit::Hearts),
            "diamonds" => Ok(Suit::Diamonds),
            "clubs" => Ok(Suit::Clubs),
            "spades" => Ok(Suit::Spades),
            other => Err(format!("unknown suit: {other}")),
        }
    }
}

/// Derived `Ord` follows declaration order: Two is lowest, Ace is highest.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
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

    pub fn name(self) -> &'static str {
        match self {
            Rank::Two => "two",
            Rank::Three => "three",
            Rank::Four => "four",
            Rank::Five => "five",
            Rank::Six => "six",
            Rank::Seven => "seven",
            Rank::Eight => "eight",
            Rank::Nine => "nine",
            Rank::Ten => "ten",
            Rank::Jack => "jack",
            Rank::Queen => "queen",
            Rank::King => "king",
            Rank::Ace => "ace",
        }
    }
}

impl fmt::Display for Rank {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

impl FromStr for Rank {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Rank::ALL
            .into_iter()
            .find(|r| r.name() == s)
            .ok_or_else(|| format!("unknown rank: {s}"))
    }
}

/// A playing card. Identity is fully determined by suit and rank; the
/// canonical wire identifier is [`CardId`] (e.g. `"ace-of-hearts"`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct Card {
    pub suit: Suit,
    pub rank: Rank,
}

impl Card {
    pub fn new(suit: Suit, rank: Rank) -> Self {
        Self { suit, rank }
    }

    pub fn id(self) -> CardId {
        CardId { suit: self.suit, rank: self.rank }
    }
}

impl fmt::Display for Card {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}{}", self.rank, self.suit.symbol())
    }
}

/// Canonical card identifier, serialized as `"<rank>-of-<suit>"`
/// (e.g. `"seven-of-spades"`), matching the protocol examples in PLAN.md §18.1.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct CardId {
    pub suit: Suit,
    pub rank: Rank,
}

impl CardId {
    pub fn card(self) -> Card {
        Card { suit: self.suit, rank: self.rank }
    }
}

impl From<Card> for CardId {
    fn from(card: Card) -> Self {
        card.id()
    }
}

impl fmt::Display for CardId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}-of-{}", self.rank, self.suit)
    }
}

impl FromStr for CardId {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let (rank, suit) = s
            .split_once("-of-")
            .ok_or_else(|| format!("invalid card id: {s}"))?;
        Ok(CardId { suit: suit.parse()?, rank: rank.parse()? })
    }
}

impl Serialize for CardId {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for CardId {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let s = String::deserialize(deserializer)?;
        s.parse().map_err(de::Error::custom)
    }
}

/// The full 52-card deck in a deterministic canonical order (unshuffled).
pub fn full_deck() -> Vec<Card> {
    let mut deck = Vec::with_capacity(52);
    for suit in Suit::ALL {
        for rank in Rank::ALL {
            deck.push(Card::new(suit, rank));
        }
    }
    deck
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    #[test]
    fn full_deck_has_52_unique_cards() {
        let deck = full_deck();
        assert_eq!(deck.len(), 52);
        let unique: HashSet<Card> = deck.iter().copied().collect();
        assert_eq!(unique.len(), 52);
    }

    #[test]
    fn rank_order_is_two_low_ace_high() {
        assert!(Rank::Two < Rank::Three);
        assert!(Rank::Ten < Rank::Jack);
        assert!(Rank::King < Rank::Ace);
        assert_eq!(Rank::ALL.iter().max(), Some(&Rank::Ace));
        assert_eq!(Rank::ALL.iter().min(), Some(&Rank::Two));
    }

    #[test]
    fn card_id_round_trips_via_string() {
        for card in full_deck() {
            let id = card.id();
            let text = id.to_string();
            let parsed: CardId = text.parse().unwrap();
            assert_eq!(parsed, id);
            assert_eq!(parsed.card(), card);
        }
    }

    #[test]
    fn card_id_serde_round_trip() {
        let id: CardId = "seven-of-spades".parse().unwrap();
        let json = serde_json::to_string(&id).unwrap();
        assert_eq!(json, "\"seven-of-spades\"");
        let back: CardId = serde_json::from_str(&json).unwrap();
        assert_eq!(back, id);
    }
}
