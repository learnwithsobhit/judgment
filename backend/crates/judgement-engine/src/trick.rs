//! Pure trick-winner evaluation (PLAN.md §5.7) and explanation facts (§18.3).

use serde::{Deserialize, Serialize};

use judgement_domain::{CardId, PlayerId, Suit, TrickEvaluationError};

use crate::state::PlayedCard;

/// Stable reason codes for trick-winner explanations (PLAN.md §18.3).
pub mod trick_reason {
    pub const TRUMP_BEATS_LEAD_SUIT: &str = "TRUMP_BEATS_LEAD_SUIT";
    pub const HIGHEST_TRUMP_WINS: &str = "HIGHEST_TRUMP_WINS";
    pub const HIGHEST_LEAD_SUIT_WINS: &str = "HIGHEST_LEAD_SUIT_WINS";
}

/// Deterministic facts describing why a completed trick was won.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TrickWinnerExplanation {
    pub lead_suit: Suit,
    pub trump_suit: Option<Suit>,
    pub plays: Vec<(PlayerId, CardId)>,
    pub winner: PlayerId,
    pub reason_code: String,
}

/// Determine the winner of a completed trick.
///
/// 1. If one or more trump cards were played, the highest trump wins.
/// 2. Otherwise the highest card of the lead suit wins.
/// 3. Cards outside the lead suit and trump cannot win.
pub fn determine_trick_winner(
    lead_suit: Suit,
    trump: Option<Suit>,
    plays: &[PlayedCard],
) -> Result<PlayerId, TrickEvaluationError> {
    Ok(explain_trick_winner(lead_suit, trump, plays)?.winner)
}

/// Winner plus structured reason facts for explanation templates (§18.3).
pub fn explain_trick_winner(
    lead_suit: Suit,
    trump: Option<Suit>,
    plays: &[PlayedCard],
) -> Result<TrickWinnerExplanation, TrickEvaluationError> {
    if plays.is_empty() {
        return Err(TrickEvaluationError::EmptyTrick);
    }

    let play_ids: Vec<(PlayerId, CardId)> =
        plays.iter().map(|p| (p.player_id, p.card.id())).collect();

    if let Some(trump_suit) = trump {
        let trumps: Vec<_> = plays
            .iter()
            .filter(|play| play.card.suit == trump_suit)
            .collect();
        if let Some(best_trump) = trumps.iter().max_by_key(|play| play.card.rank) {
            let reason_code = if lead_suit == trump_suit {
                trick_reason::HIGHEST_TRUMP_WINS
            } else if trumps.len() == 1 {
                trick_reason::TRUMP_BEATS_LEAD_SUIT
            } else {
                trick_reason::HIGHEST_TRUMP_WINS
            };
            return Ok(TrickWinnerExplanation {
                lead_suit,
                trump_suit: Some(trump_suit),
                plays: play_ids,
                winner: best_trump.player_id,
                reason_code: reason_code.to_string(),
            });
        }
    }

    let winner = plays
        .iter()
        .filter(|play| play.card.suit == lead_suit)
        .max_by_key(|play| play.card.rank)
        .map(|play| play.player_id)
        .ok_or(TrickEvaluationError::NoEligibleCard)?;

    Ok(TrickWinnerExplanation {
        lead_suit,
        trump_suit: trump,
        plays: play_ids,
        winner,
        reason_code: trick_reason::HIGHEST_LEAD_SUIT_WINS.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use judgement_domain::{Card, Rank};

    use super::*;

    fn play(player: PlayerId, suit: Suit, rank: Rank) -> PlayedCard {
        PlayedCard { player_id: player, card: Card::new(suit, rank) }
    }

    #[test]
    fn empty_trick_is_an_error() {
        assert_eq!(
            determine_trick_winner(Suit::Clubs, None, &[]),
            Err(TrickEvaluationError::EmptyTrick)
        );
    }

    #[test]
    fn highest_lead_suit_wins_without_trump() {
        let (a, b, c) = (PlayerId::new(), PlayerId::new(), PlayerId::new());
        let plays = [
            play(a, Suit::Clubs, Rank::Ten),
            play(b, Suit::Clubs, Rank::Ace),
            play(c, Suit::Hearts, Rank::Ace), // off-suit ace cannot win
        ];
        assert_eq!(determine_trick_winner(Suit::Clubs, None, &plays), Ok(b));
    }

    #[test]
    fn lowest_trump_beats_highest_lead_suit() {
        let (a, b, c) = (PlayerId::new(), PlayerId::new(), PlayerId::new());
        let plays = [
            play(a, Suit::Clubs, Rank::Ace),
            play(b, Suit::Hearts, Rank::Two),
            play(c, Suit::Clubs, Rank::King),
        ];
        assert_eq!(
            determine_trick_winner(Suit::Clubs, Some(Suit::Hearts), &plays),
            Ok(b)
        );
    }

    #[test]
    fn highest_trump_wins_among_multiple_trumps() {
        let (a, b, c) = (PlayerId::new(), PlayerId::new(), PlayerId::new());
        let plays = [
            play(a, Suit::Spades, Rank::Queen),
            play(b, Suit::Hearts, Rank::Five),
            play(c, Suit::Hearts, Rank::Jack),
        ];
        assert_eq!(
            determine_trick_winner(Suit::Spades, Some(Suit::Hearts), &plays),
            Ok(c)
        );
    }

    #[test]
    fn trump_suit_equal_to_lead_suit_still_picks_highest() {
        let (a, b) = (PlayerId::new(), PlayerId::new());
        let plays = [
            play(a, Suit::Hearts, Rank::King),
            play(b, Suit::Hearts, Rank::Ace),
        ];
        assert_eq!(
            determine_trick_winner(Suit::Hearts, Some(Suit::Hearts), &plays),
            Ok(b)
        );
    }

    #[test]
    fn ace_is_high_within_suit() {
        let (a, b) = (PlayerId::new(), PlayerId::new());
        let plays = [
            play(a, Suit::Diamonds, Rank::Ace),
            play(b, Suit::Diamonds, Rank::Two),
        ];
        assert_eq!(determine_trick_winner(Suit::Diamonds, None, &plays), Ok(a));
    }

    #[test]
    fn explain_emits_trump_beats_lead_reason() {
        let (a, b, c) = (PlayerId::new(), PlayerId::new(), PlayerId::new());
        let plays = [
            play(a, Suit::Clubs, Rank::Ace),
            play(b, Suit::Hearts, Rank::Two),
            play(c, Suit::Clubs, Rank::King),
        ];
        let explanation =
            explain_trick_winner(Suit::Clubs, Some(Suit::Hearts), &plays).expect("ok");
        assert_eq!(explanation.winner, b);
        assert_eq!(explanation.reason_code, trick_reason::TRUMP_BEATS_LEAD_SUIT);
        assert_eq!(explanation.plays.len(), 3);
    }

    #[test]
    fn explain_emits_highest_lead_suit_reason() {
        let (a, b) = (PlayerId::new(), PlayerId::new());
        let plays = [
            play(a, Suit::Clubs, Rank::Ten),
            play(b, Suit::Clubs, Rank::Ace),
        ];
        let explanation = explain_trick_winner(Suit::Clubs, None, &plays).expect("ok");
        assert_eq!(explanation.winner, b);
        assert_eq!(explanation.reason_code, trick_reason::HIGHEST_LEAD_SUIT_WINS);
    }
}
