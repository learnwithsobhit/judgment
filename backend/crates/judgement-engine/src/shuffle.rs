//! Shuffle abstraction (PLAN.md §21, §23.3).
//!
//! Production uses OS-backed secure randomness; tests and simulations inject
//! a seed for full determinism.

use judgement_domain::Card;
use rand::rngs::StdRng;
use rand::seq::SliceRandom;
use rand::SeedableRng;
use rand_chacha::ChaCha8Rng;

pub trait DeckShuffler: Send + Sync {
    fn shuffle_deck(&mut self, deck: &mut [Card]);
}

/// Deterministic shuffler for tests, simulations, and bug reproduction.
pub struct SeededShuffler {
    rng: ChaCha8Rng,
}

impl SeededShuffler {
    pub fn new(seed: u64) -> Self {
        Self { rng: ChaCha8Rng::seed_from_u64(seed) }
    }
}

impl DeckShuffler for SeededShuffler {
    fn shuffle_deck(&mut self, deck: &mut [Card]) {
        deck.shuffle(&mut self.rng);
    }
}

/// Production shuffler seeded from OS entropy.
pub struct SecureShuffler {
    rng: StdRng,
}

impl SecureShuffler {
    #[allow(clippy::new_without_default)]
    pub fn new() -> Self {
        Self { rng: StdRng::from_os_rng() }
    }
}

impl DeckShuffler for SecureShuffler {
    fn shuffle_deck(&mut self, deck: &mut [Card]) {
        deck.shuffle(&mut self.rng);
    }
}

#[cfg(test)]
mod tests {
    use judgement_domain::full_deck;

    use super::*;

    #[test]
    fn seeded_shuffle_is_deterministic() {
        let mut a = full_deck();
        let mut b = full_deck();
        SeededShuffler::new(42).shuffle_deck(&mut a);
        SeededShuffler::new(42).shuffle_deck(&mut b);
        assert_eq!(a, b);

        let mut c = full_deck();
        SeededShuffler::new(43).shuffle_deck(&mut c);
        assert_ne!(a, c, "different seeds should produce different orders");
    }
}
