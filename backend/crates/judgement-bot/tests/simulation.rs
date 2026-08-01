//! Bot simulation tests (PLAN.md §23.4, Phase 2 exit criteria).

use judgement_bot::{simulate_game, simulate_game_with_players};
use judgement_domain::max_cards_per_player;

#[test]
fn seeded_simulation_is_deterministic() {
    let a = simulate_game(7).unwrap();
    let b = simulate_game(7).unwrap();
    assert_eq!(a.events, b.events, "same seed must reproduce the same game");
    assert_eq!(a.ranking, b.ranking);
    assert_eq!(a.ranking.len(), 6);
}

#[test]
fn five_hundred_random_games_complete_without_invariant_failures() {
    for seed in 0..500u64 {
        let outcome = simulate_game(seed)
            .unwrap_or_else(|error| panic!("simulation failed for seed {seed}: {error}"));

        assert_eq!(outcome.ranking.len(), 6, "seed {seed}: all six players ranked");
        assert_eq!(outcome.ranking[0].rank, 1, "seed {seed}: ranking starts at 1");

        // 1 start + 8 rounds * (6 bids + cards*6 plays + 1 round-scoring advance).
        let expected_commands: u64 = 1 + (1..=8).map(|c: u64| 6 + c * 6 + 1).sum::<u64>();
        assert_eq!(
            outcome.commands_processed, expected_commands,
            "seed {seed}: exact command count for a full game"
        );
    }
}

/// Every supported table size (3–8) completes full games with the
/// derived round pattern and no invariant violations.
#[test]
fn all_table_sizes_complete_full_games() {
    for player_count in 3u8..=8 {
        for seed in 0..40u64 {
            let outcome = simulate_game_with_players(seed, player_count).unwrap_or_else(|error| {
                panic!("simulation failed for {player_count} players, seed {seed}: {error}")
            });
            assert_eq!(outcome.ranking.len(), player_count as usize);

            // 1 start + per round (bids + cards * players + scoring advance), rounds max..1.
            let max_cards = max_cards_per_player(player_count) as u64;
            let players = player_count as u64;
            let expected: u64 =
                1 + (1..=max_cards).map(|c| players + c * players + 1).sum::<u64>();
            assert_eq!(
                outcome.commands_processed, expected,
                "{player_count} players, seed {seed}: exact command count"
            );
        }
    }
}

/// Phase 2 exit criterion: at least 10,000 games without invariant violations.
/// Run explicitly with `cargo test -p judgement-bot --release -- --ignored`.
#[test]
#[ignore = "long-running Phase 2 exit gate"]
fn ten_thousand_games_complete_without_invariant_failures() {
    for seed in 0..10_000u64 {
        simulate_game(seed)
            .unwrap_or_else(|error| panic!("simulation failed for seed {seed}: {error}"));
    }
}
