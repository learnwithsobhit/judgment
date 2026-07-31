//! Property-based invariants (PLAN.md §23.2).

use proptest::prelude::*;

use judgement_domain::{full_deck, max_cards_per_player, GameId, GameRules, PlayerId, PlayerState, RoundPattern, Suit};
use judgement_engine::{determine_trick_winner, GameEngine, GamePhase, PlayedCard};

fn six_players() -> Vec<PlayerState> {
    (0..6)
        .map(|seat| PlayerState::human(PlayerId::new(), format!("P{}", seat + 1), seat))
        .collect()
}

proptest! {
    /// Every non-empty trick has exactly one winner, and the winning card is
    /// the highest trump if any trump was played, otherwise the highest card
    /// of the lead suit.
    #[test]
    fn trick_winner_is_correct(
        cards in proptest::sample::subsequence(full_deck(), 1..=6),
        trump_index in proptest::option::of(0usize..4),
    ) {
        let players: Vec<PlayerId> = (0..cards.len()).map(|_| PlayerId::new()).collect();
        let plays: Vec<PlayedCard> = players
            .iter()
            .zip(cards.iter())
            .map(|(&player_id, &card)| PlayedCard { player_id, card })
            .collect();

        let lead_suit = plays[0].card.suit;
        let trump = trump_index.map(|i| Suit::ALL[i]);

        let winner = determine_trick_winner(lead_suit, trump, &plays).unwrap();
        let winning_play = plays.iter().find(|p| p.player_id == winner).unwrap();

        let trumps: Vec<&PlayedCard> = trump
            .map(|t| plays.iter().filter(|p| p.card.suit == t).collect())
            .unwrap_or_default();

        if !trumps.is_empty() {
            let best = trumps.iter().max_by_key(|p| p.card.rank).unwrap();
            prop_assert_eq!(winning_play.card, best.card);
        } else {
            let best = plays
                .iter()
                .filter(|p| p.card.suit == lead_suit)
                .max_by_key(|p| p.card.rank)
                .unwrap();
            prop_assert_eq!(winning_play.card, best.card);
        }
    }

    /// The dealer restriction removes exactly one option from `0..=cards`
    /// when the forbidden total is in range, so a legal bid always remains.
    #[test]
    fn dealer_always_has_a_legal_bid(
        seed in any::<u64>(),
        other_bids in proptest::collection::vec(0u8..=8, 5),
    ) {
        let mut engine = GameEngine::new_with_seed(
            seed,
            GameId::new(),
            GameRules::default_six_player(),
            six_players(),
        ).unwrap();
        engine.start_game().unwrap();

        for &bid in &other_bids {
            let player = engine.state().current_round.as_ref().unwrap().current_turn;
            engine.place_bid(player, bid).unwrap();
        }

        let dealer = engine.state().dealer;
        prop_assert_eq!(engine.state().current_round.as_ref().unwrap().current_turn, dealer);

        let legal = engine.legal_bids(dealer);
        prop_assert!(!legal.is_empty(), "a legal bid must always remain for the dealer");

        let others_total: u32 = other_bids.iter().map(|&b| b as u32).sum();
        if others_total <= 8 {
            let forbidden = (8 - others_total) as u8;
            prop_assert!(!legal.contains(&forbidden));
            prop_assert_eq!(legal.len(), 8, "exactly one option removed from 0..=8");
        } else {
            prop_assert_eq!(legal.len(), 9, "no option removed when total already exceeds tricks");
        }
    }

    /// Derived descending patterns respect `max_cards = floor(51 / players)`
    /// and the deal never exhausts the deck (one card always remains for trump).
    #[test]
    fn derived_pattern_fits_the_deck(player_count in 3u8..=8) {
        let max_cards = max_cards_per_player(player_count);
        prop_assert_eq!(max_cards, (52 - 1) / player_count);

        let pattern = RoundPattern::descending_for_players(player_count);
        let rounds = pattern.rounds();
        prop_assert_eq!(rounds.len(), max_cards as usize);
        for cards in rounds {
            prop_assert!(cards as u32 * player_count as u32 <= 51);
        }
    }

    /// Drive a partial game (bidding + a few tricks) from arbitrary seeds and
    /// verify structural invariants and projection safety along the way.
    #[test]
    fn invariants_hold_under_random_play(seed in any::<u64>(), plays in 1usize..=30) {
        let mut engine = GameEngine::new_with_seed(
            seed,
            GameId::new(),
            GameRules::default_six_player(),
            six_players(),
        ).unwrap();
        engine.start_game().unwrap();
        engine.check_invariants().unwrap();

        let mut remaining = plays;
        while remaining > 0 && !engine.is_finished() {
            let player = engine.state().current_round.as_ref().unwrap().current_turn;
            match engine.phase() {
                GamePhase::Bidding => {
                    let bids = engine.legal_bids(player);
                    prop_assert!(!bids.is_empty());
                    // Deterministic pseudo-random pick from the seed.
                    let bid = bids[(seed as usize + remaining) % bids.len()];
                    engine.place_bid(player, bid).unwrap();
                }
                GamePhase::Playing => {
                    let cards = engine.legal_cards(player);
                    prop_assert!(!cards.is_empty());
                    let card = cards[(seed as usize + remaining) % cards.len()];
                    engine.play_card(player, card).unwrap();
                }
                other => prop_assert!(false, "unexpected phase {:?}", other),
            }
            engine.check_invariants().map_err(TestCaseError::fail)?;
            remaining -= 1;
        }

        // No opponent hand may ever appear in a personalised view.
        let round = engine.state().current_round.as_ref().unwrap().clone();
        for player in engine.state().player_ids() {
            let view = engine.view_for(player).unwrap();
            for (owner, hand) in &round.hands {
                if *owner != player {
                    for card in hand {
                        prop_assert!(!view.own_hand.contains(card));
                    }
                }
            }
        }
    }
}
