//! Print a complete seeded six-player game to stdout.
//!
//! Usage: `cargo run -p judgement-bot --bin simulate -- [seed]`

use judgement_bot::simulate_game;
use judgement_engine::GameEvent;

fn main() {
    let seed: u64 = std::env::args()
        .nth(1)
        .map(|arg| arg.parse().expect("seed must be a u64"))
        .unwrap_or(42);

    let outcome = match simulate_game(seed) {
        Ok(outcome) => outcome,
        Err(error) => {
            eprintln!("simulation failed: {error}");
            std::process::exit(1);
        }
    };

    let name = |player_id| outcome.nicknames.get(player_id).map(String::as_str).unwrap_or("?");

    println!("=== Judgement simulation (seed {seed}) ===");
    for event in &outcome.events {
        match event {
            GameEvent::GameStarted { dealer } => {
                println!("Game started. Dealer: {}", name(dealer));
            }
            GameEvent::RoundStarted { round_index, cards_per_player, dealer } => {
                println!();
                println!(
                    "--- Round {} ({cards_per_player} cards, dealer {}) ---",
                    round_index + 1,
                    name(dealer)
                );
            }
            GameEvent::CardsDealt { .. } => {}
            GameEvent::TrumpSelected { trump, trump_card, .. } => match trump_card {
                Some(card) => println!("Trump: {trump} (revealed {card})"),
                None => println!("Trump: {trump} (rotation)"),
            },
            GameEvent::BidPlaced { player_id, bid } => {
                println!("  {} bids {bid}", name(player_id));
            }
            GameEvent::CardPlayed { player_id, card } => {
                println!("    {} plays {card}", name(player_id));
            }
            GameEvent::TrickCompleted { trick_index, winner } => {
                println!("  Trick {} won by {}", trick_index + 1, name(winner));
            }
            GameEvent::RoundCompleted { round_index } => {
                println!("Round {} complete.", round_index + 1);
            }
            GameEvent::DealerRotated { new_dealer } => {
                println!("Dealer rotates to {}", name(new_dealer));
            }
            GameEvent::GameCompleted { .. } => {
                println!();
                println!("=== Game complete ===");
            }
        }
    }

    println!();
    println!("Final ranking:");
    println!("{:<6} {:<8} {:>6} {:>12} {:>14}", "rank", "player", "score", "exact rounds", "tricks missed");
    for ranked in &outcome.ranking {
        println!(
            "{:<6} {:<8} {:>6} {:>12} {:>14}",
            ranked.rank,
            name(&ranked.player_id),
            ranked.total_score,
            ranked.exact_bid_rounds,
            ranked.total_tricks_missed
        );
    }
    println!();
    println!("Commands processed: {}", outcome.commands_processed);
}
