//! Scoring strategies (PLAN.md §5.8).

use judgement_domain::ScoringRule;

/// Context passed to scoring so future progressive / zero-bid bonuses do not
/// require a breaking trait change.
#[derive(Debug, Clone, Copy)]
pub struct ScoringContext {
    pub round_index: usize,
    pub cards_in_round: u8,
}

pub trait ScoringStrategy: Send + Sync {
    fn score_round(&self, ctx: &ScoringContext, bid: u8, tricks_won: u8) -> i32;
}

/// Default MVP scoring: exact bid scores `bonus + bid`, missed bid scores 0.
pub struct ExactBidScoring {
    pub bonus: i32,
}

impl ScoringStrategy for ExactBidScoring {
    fn score_round(&self, _ctx: &ScoringContext, bid: u8, tricks_won: u8) -> i32 {
        if bid == tricks_won {
            self.bonus + bid as i32
        } else {
            0
        }
    }
}

pub fn scoring_strategy_for(rule: &ScoringRule) -> Box<dyn ScoringStrategy> {
    match rule {
        ScoringRule::ExactBidBonusPlusBid { bonus } => Box::new(ExactBidScoring { bonus: *bonus }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_bid_scores_bonus_plus_bid() {
        let scoring = ExactBidScoring { bonus: 10 };
        let ctx = ScoringContext { round_index: 0, cards_in_round: 8 };
        assert_eq!(scoring.score_round(&ctx, 2, 2), 12);
        assert_eq!(scoring.score_round(&ctx, 0, 0), 10);
        assert_eq!(scoring.score_round(&ctx, 8, 8), 18);
    }

    #[test]
    fn missed_bid_scores_zero() {
        let scoring = ExactBidScoring { bonus: 10 };
        let ctx = ScoringContext { round_index: 3, cards_in_round: 5 };
        assert_eq!(scoring.score_round(&ctx, 2, 3), 0);
        assert_eq!(scoring.score_round(&ctx, 3, 0), 0);
    }
}
