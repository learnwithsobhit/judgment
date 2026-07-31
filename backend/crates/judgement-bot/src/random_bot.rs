//! Level 1 bot: uniformly random legal actions (PLAN.md §17.1).
//!
//! Used for tests, load generation, and simulation. Because it only ever
//! selects from `legal_actions` in its own view, every command it produces
//! must pass engine validation.

use judgement_domain::CardId;
use judgement_engine::PlayerGameView;
use rand::seq::IndexedRandom;
use rand::SeedableRng;
use rand_chacha::ChaCha8Rng;

use crate::{BotError, BotStrategy};

pub struct RandomBot {
    rng: ChaCha8Rng,
}

impl RandomBot {
    pub fn new(seed: u64) -> Self {
        Self { rng: ChaCha8Rng::seed_from_u64(seed) }
    }
}

impl BotStrategy for RandomBot {
    fn choose_bid(&mut self, view: &PlayerGameView) -> Result<u8, BotError> {
        view.legal_actions
            .legal_bids
            .choose(&mut self.rng)
            .copied()
            .ok_or(BotError::NoLegalAction)
    }

    fn choose_card(&mut self, view: &PlayerGameView) -> Result<CardId, BotError> {
        view.legal_actions
            .playable_cards
            .choose(&mut self.rng)
            .copied()
            .ok_or(BotError::NoLegalAction)
    }
}
