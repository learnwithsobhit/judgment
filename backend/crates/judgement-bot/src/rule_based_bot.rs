//! Heuristic bot for disconnect takeover (PLAN.md §15 / §17).
//!
//! Chooses only from the published legal-action list — never invents moves —
//! so every action remains engine-validated. Prefer lowest legal bid / card
//! for safe playout (Level-1 rule-based, not random).

use judgement_domain::CardId;
use judgement_engine::PlayerGameView;

use crate::{BotError, BotStrategy};

#[derive(Debug, Default)]
pub struct RuleBasedBot;

impl BotStrategy for RuleBasedBot {
    fn choose_bid(&mut self, view: &PlayerGameView) -> Result<u8, BotError> {
        // Prefer a conservative bid: the lowest legal option (often 0).
        view.legal_actions
            .legal_bids
            .iter()
            .copied()
            .min()
            .ok_or(BotError::NoLegalAction)
    }

    fn choose_card(&mut self, view: &PlayerGameView) -> Result<CardId, BotError> {
        // Dump the lowest-ranked legal card; keeps high cards for later tricks.
        view.legal_actions
            .playable_cards
            .iter()
            .min_by_key(|c| (c.rank, c.suit))
            .copied()
            .ok_or(BotError::NoLegalAction)
    }
}
