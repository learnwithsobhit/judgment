//! Structured rule configuration (PLAN.md §5).

use serde::{Deserialize, Serialize};

use crate::cards::Suit;

/// Minimum and maximum seats at a table (ADR 0003, amended: min 3).
pub const MIN_PLAYERS: u8 = 3;
pub const MAX_PLAYERS: u8 = 8;

/// Scheduled-event FCFS going seats (always the full table max).
pub const EVENT_SEAT_CAP: u8 = MAX_PLAYERS;
/// Overflow RSVPs after seats are full (ADR 0005 waitlist).
pub const EVENT_WAITLIST_CAP: u8 = 5;

/// `max_cards = floor((52 - 1) / player_count)` — one card always stays
/// undealt (it is the revealed trump in `RevealUndealtCard` mode). Never
/// hardcode the result (PLAN.md §5.2).
pub fn max_cards_per_player(player_count: u8) -> u8 {
    assert!(player_count > 0, "player_count must be non-zero");
    (52 - 1) / player_count
}

/// The classic trump rotation order (ADR 0003): ♠ → ♦ → ♣ → ♥.
pub const TRUMP_ROTATION: [Suit; 4] = [Suit::Spades, Suit::Diamonds, Suit::Clubs, Suit::Hearts];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "type")]
pub enum RoundPattern {
    Descending { max_cards: u8 },
    Ascending { max_cards: u8 },
    Mountain { max_cards: u8 },
    Custom { rounds: Vec<u8> },
}

impl RoundPattern {
    /// MVP pattern for a given player count: descending from the derived
    /// maximum down to 1 (e.g. `8 → 7 → … → 1` for six players).
    pub fn descending_for_players(player_count: u8) -> Self {
        RoundPattern::Descending { max_cards: max_cards_per_player(player_count) }
    }

    /// The number of cards dealt per player in each round, in order.
    pub fn rounds(&self) -> Vec<u8> {
        match self {
            RoundPattern::Descending { max_cards } => (1..=*max_cards).rev().collect(),
            RoundPattern::Ascending { max_cards } => (1..=*max_cards).collect(),
            RoundPattern::Mountain { max_cards } => {
                let up = 1..=*max_cards;
                let down = (1..*max_cards).rev();
                up.chain(down).collect()
            }
            RoundPattern::Custom { rounds } => rounds.clone(),
        }
    }
}

/// How the host chooses the per-round card schedule at room create.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum RoundScheduleMode {
    #[default]
    Automatic,
    Manual,
}

/// One authoring step: deal `cards` per player, repeated `repeat` consecutive rounds.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ManualRoundStep {
    pub cards: u8,
    pub repeat: u8,
}

/// Host-configured round schedule stored on the room; resolved into
/// [`RoundPattern`] when the game starts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoundSchedule {
    pub mode: RoundScheduleMode,
    /// Required when `mode == Manual`; ignored for Automatic.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub steps: Option<Vec<ManualRoundStep>>,
}

impl Default for RoundSchedule {
    fn default() -> Self {
        Self {
            mode: RoundScheduleMode::Automatic,
            steps: None,
        }
    }
}

pub const MAX_MANUAL_REPEAT: u8 = 8;
pub const MAX_MANUAL_ROUNDS: usize = 64;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum RoundScheduleError {
    #[error("manual schedule requires at least one step")]
    EmptySteps,
    #[error("cards per round must be between 1 and {max} for {player_count} players")]
    CardsOutOfRange { max: u8, player_count: u8 },
    #[error("repeat must be between 1 and {MAX_MANUAL_REPEAT}")]
    RepeatOutOfRange,
    #[error("expanded schedule must have between 1 and {MAX_MANUAL_ROUNDS} rounds")]
    RoundCountOutOfRange,
    #[error("dealing {cards} cards to {player_count} players exceeds the deck ({max_dealt} max)")]
    DeckOverflow { cards: u8, player_count: u8, max_dealt: u8 },
}

impl RoundSchedule {
    /// Short lobby summary, e.g. `Automatic (12→1)` or `Manual: 20 rounds`.
    pub fn summary(&self, player_count: u8) -> String {
        match self.mode {
            RoundScheduleMode::Automatic => {
                let max = max_cards_per_player(player_count);
                format!("Automatic ({max}→1)")
            }
            RoundScheduleMode::Manual => match self.steps.as_deref().map(Self::expand_steps) {
                Some(Ok(rounds)) if !rounds.is_empty() => {
                    format!("Manual: {} rounds", rounds.len())
                }
                _ => "Manual".into(),
            },
        }
    }

    /// Expand manual steps without validating against a table size (UI preview).
    pub fn expand_steps(steps: &[ManualRoundStep]) -> Result<Vec<u8>, RoundScheduleError> {
        if steps.is_empty() {
            return Err(RoundScheduleError::EmptySteps);
        }
        let mut out = Vec::new();
        for step in steps {
            if step.cards == 0 {
                return Err(RoundScheduleError::CardsOutOfRange {
                    max: 1,
                    player_count: 0,
                });
            }
            if !(1..=MAX_MANUAL_REPEAT).contains(&step.repeat) {
                return Err(RoundScheduleError::RepeatOutOfRange);
            }
            for _ in 0..step.repeat {
                out.push(step.cards);
            }
        }
        if out.is_empty() || out.len() > MAX_MANUAL_ROUNDS {
            return Err(RoundScheduleError::RoundCountOutOfRange);
        }
        Ok(out)
    }

    /// Validate (and for Manual, expand) against a concrete seat count + trump mode.
    ///
    /// `reveal_undealt_trump`: when true, one card is reserved for the trump reveal
    /// so at most 51 cards may be dealt.
    pub fn resolve_pattern(
        &self,
        player_count: u8,
        reveal_undealt_trump: bool,
    ) -> Result<RoundPattern, RoundScheduleError> {
        match self.mode {
            // Automatic ignores any leftover steps from the client.
            RoundScheduleMode::Automatic => {
                Ok(RoundPattern::descending_for_players(player_count))
            }
            RoundScheduleMode::Manual => {
                let rounds = self.expand_and_validate(player_count, reveal_undealt_trump)?;
                Ok(RoundPattern::Custom { rounds })
            }
        }
    }

    pub fn expand_and_validate(
        &self,
        player_count: u8,
        reveal_undealt_trump: bool,
    ) -> Result<Vec<u8>, RoundScheduleError> {
        let steps = self.steps.as_ref().ok_or(RoundScheduleError::EmptySteps)?;
        if steps.is_empty() {
            return Err(RoundScheduleError::EmptySteps);
        }
        let max_cards = max_cards_per_player(player_count);
        let max_dealt = if reveal_undealt_trump { 51u8 } else { 52u8 };
        let mut out = Vec::new();
        for step in steps {
            if !(1..=max_cards).contains(&step.cards) {
                return Err(RoundScheduleError::CardsOutOfRange {
                    max: max_cards,
                    player_count,
                });
            }
            if !(1..=MAX_MANUAL_REPEAT).contains(&step.repeat) {
                return Err(RoundScheduleError::RepeatOutOfRange);
            }
            let dealt = step.cards.saturating_mul(player_count);
            if dealt > max_dealt {
                return Err(RoundScheduleError::DeckOverflow {
                    cards: step.cards,
                    player_count,
                    max_dealt,
                });
            }
            for _ in 0..step.repeat {
                out.push(step.cards);
            }
        }
        if out.is_empty() || out.len() > MAX_MANUAL_ROUNDS {
            return Err(RoundScheduleError::RoundCountOutOfRange);
        }
        Ok(out)
    }

    /// Default manual schedule matching the common 4-player double-descent
    /// pattern (12×2 … 5×2, then 4,3,2,1), clamped to `player_count`.
    pub fn default_manual_for_players(player_count: u8) -> Self {
        let max = max_cards_per_player(player_count);
        let mut steps = Vec::new();
        // Double each count from max down through 5 (when max >= 5).
        let double_floor = 5u8.min(max);
        for cards in (double_floor..=max).rev() {
            steps.push(ManualRoundStep { cards, repeat: 2 });
        }
        for cards in (1..double_floor).rev() {
            steps.push(ManualRoundStep { cards, repeat: 1 });
        }
        if steps.is_empty() {
            steps.push(ManualRoundStep { cards: max.max(1), repeat: 1 });
        }
        Self {
            mode: RoundScheduleMode::Manual,
            steps: Some(steps),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "type")]
pub enum TrumpRule {
    /// MVP: reveal one card from the undealt deck; its suit is trump and the
    /// card itself remains out of play (PLAN.md §5.4).
    RevealUndealtCard,
    RotatingSuit,
    DealerChooses,
    RandomSuit,
    NoTrump,
    /// Trump for round `n` is `suits[n % suits.len()]`; no card is revealed.
    FixedSequence { suits: Vec<Suit> },
}

impl TrumpRule {
    /// ADR 0003: the chosen first trump, then the classic rotation
    /// ♠ → ♦ → ♣ → ♥ wrapping each round.
    pub fn rotating_from(first_trump: Suit) -> Self {
        let start = TRUMP_ROTATION
            .iter()
            .position(|&s| s == first_trump)
            .expect("every suit is in the rotation");
        let suits = (0..TRUMP_ROTATION.len())
            .map(|offset| TRUMP_ROTATION[(start + offset) % TRUMP_ROTATION.len()])
            .collect();
        TrumpRule::FixedSequence { suits }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BiddingRule {
    pub allow_zero: bool,
    pub bids_visible_immediately: bool,
    /// Parsed for forward compatibility; the engine forces this to `false`
    /// in MVP (PLAN.md §5.5).
    pub allow_edit_before_next_bid: bool,
    pub dealer_total_restriction: bool,
}

impl Default for BiddingRule {
    fn default() -> Self {
        Self {
            allow_zero: true,
            bids_visible_immediately: true,
            allow_edit_before_next_bid: false,
            dealer_total_restriction: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "type")]
pub enum ScoringRule {
    /// Exact bid scores `bonus + bid`; missed bid scores 0 (PLAN.md §5.8).
    ExactBidBonusPlusBid { bonus: i32 },
}

impl Default for ScoringRule {
    fn default() -> Self {
        ScoringRule::ExactBidBonusPlusBid { bonus: 10 }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GameRules {
    pub min_players: u8,
    pub max_players: u8,
    pub round_pattern: RoundPattern,
    pub trump_rule: TrumpRule,
    pub bidding_rule: BiddingRule,
    pub scoring_rule: ScoringRule,
    /// `None` disables the turn timer entirely (ADR 0003): no deadlines are
    /// scheduled and the server never auto-plays.
    pub turn_timeout_seconds: Option<u16>,
    pub reconnect_grace_seconds: u16,
    pub allow_bots: bool,
}

impl GameRules {
    /// MVP configuration for the actual number of seated players (3–8):
    /// descending `max → 1` rounds, revealed-card trump, dealer restriction
    /// on, 30-second timer.
    pub fn mvp_for_players(player_count: u8) -> Self {
        Self {
            min_players: MIN_PLAYERS,
            max_players: MAX_PLAYERS,
            round_pattern: RoundPattern::descending_for_players(player_count),
            trump_rule: TrumpRule::RevealUndealtCard,
            bidding_rule: BiddingRule::default(),
            scoring_rule: ScoringRule::default(),
            turn_timeout_seconds: Some(30),
            reconnect_grace_seconds: 60,
            allow_bots: true,
        }
    }

    /// The original six-player MVP configuration.
    pub fn default_six_player() -> Self {
        Self::mvp_for_players(6)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn max_cards_derivation() {
        // 3 players: 17×3 = 51 dealt, 1 undealt for revealed trump.
        assert_eq!(max_cards_per_player(3), 17);
        assert_eq!(max_cards_per_player(4), 12);
        assert_eq!(max_cards_per_player(5), 10);
        assert_eq!(max_cards_per_player(6), 8);
        assert_eq!(max_cards_per_player(7), 7);
        assert_eq!(max_cards_per_player(8), 6);
    }

    #[test]
    fn three_player_descending_fits_deck() {
        let pattern = RoundPattern::descending_for_players(3);
        assert_eq!(pattern.rounds().first().copied(), Some(17));
        assert_eq!(pattern.rounds().last().copied(), Some(1));
        assert_eq!(pattern.rounds().len(), 17);
        for cards in pattern.rounds() {
            assert!(cards * 3 <= 51, "{cards}×3 must fit revealed-trump deal");
        }
    }

    #[test]
    fn rotating_trump_starts_at_chosen_suit_and_follows_order() {
        let TrumpRule::FixedSequence { suits } = TrumpRule::rotating_from(Suit::Clubs) else {
            panic!("rotating_from must produce a fixed sequence");
        };
        assert_eq!(suits, vec![Suit::Clubs, Suit::Hearts, Suit::Spades, Suit::Diamonds]);

        let TrumpRule::FixedSequence { suits } = TrumpRule::rotating_from(Suit::Spades) else {
            panic!("rotating_from must produce a fixed sequence");
        };
        assert_eq!(suits, TRUMP_ROTATION.to_vec());
    }

    #[test]
    fn six_player_descending_pattern() {
        let pattern = RoundPattern::descending_for_players(6);
        assert_eq!(pattern.rounds(), vec![8, 7, 6, 5, 4, 3, 2, 1]);
    }

    #[test]
    fn mountain_pattern() {
        let pattern = RoundPattern::Mountain { max_cards: 4 };
        assert_eq!(pattern.rounds(), vec![1, 2, 3, 4, 3, 2, 1]);
    }

    #[test]
    fn ascending_pattern() {
        let pattern = RoundPattern::Ascending { max_cards: 3 };
        assert_eq!(pattern.rounds(), vec![1, 2, 3]);
    }

    #[test]
    fn manual_schedule_expands_repeats() {
        let schedule = RoundSchedule {
            mode: RoundScheduleMode::Manual,
            steps: Some(vec![
                ManualRoundStep { cards: 12, repeat: 2 },
                ManualRoundStep { cards: 11, repeat: 2 },
                ManualRoundStep { cards: 1, repeat: 1 },
            ]),
        };
        let rounds = schedule.expand_and_validate(4, true).unwrap();
        assert_eq!(rounds, vec![12, 12, 11, 11, 1]);
        let pattern = schedule.resolve_pattern(4, true).unwrap();
        assert_eq!(
            pattern,
            RoundPattern::Custom {
                rounds: vec![12, 12, 11, 11, 1]
            }
        );
    }

    #[test]
    fn default_manual_four_players_matches_example() {
        let schedule = RoundSchedule::default_manual_for_players(4);
        let rounds = schedule.expand_and_validate(4, true).unwrap();
        assert_eq!(
            rounds,
            vec![12, 12, 11, 11, 10, 10, 9, 9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 3, 2, 1]
        );
        assert_eq!(schedule.summary(4), "Manual: 20 rounds");
    }

    #[test]
    fn manual_rejects_oversized_cards_and_empty() {
        let empty = RoundSchedule {
            mode: RoundScheduleMode::Manual,
            steps: Some(vec![]),
        };
        assert_eq!(empty.expand_and_validate(4, true), Err(RoundScheduleError::EmptySteps));

        let oversized = RoundSchedule {
            mode: RoundScheduleMode::Manual,
            steps: Some(vec![ManualRoundStep { cards: 13, repeat: 1 }]),
        };
        assert!(matches!(
            oversized.expand_and_validate(4, true),
            Err(RoundScheduleError::CardsOutOfRange { max: 12, .. })
        ));
    }

    #[test]
    fn automatic_resolves_to_descending() {
        let schedule = RoundSchedule::default();
        assert_eq!(
            schedule.resolve_pattern(6, true).unwrap(),
            RoundPattern::descending_for_players(6)
        );
        assert_eq!(schedule.summary(6), "Automatic (8→1)");
    }
}
