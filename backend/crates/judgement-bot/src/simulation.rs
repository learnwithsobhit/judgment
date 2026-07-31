//! Seeded full-game simulation with invariant checking (PLAN.md §23.3, §23.4).

use std::collections::HashMap;

use judgement_domain::{GameError, GameId, GameRules, PlayerId, PlayerState, RankedPlayer};
use judgement_engine::{GameEngine, GameEvent, GamePhase};
use thiserror::Error;
use uuid::Uuid;

use crate::{BotError, BotStrategy, RandomBot};

#[derive(Debug, Error)]
pub enum SimulationError {
    #[error("engine rejected a bot command (seed {seed}, version {version}): {source}")]
    Rejected {
        seed: u64,
        version: u64,
        #[source]
        source: GameError,
    },
    #[error("bot failed to choose an action (seed {seed}, version {version}): {source}")]
    Bot {
        seed: u64,
        version: u64,
        #[source]
        source: BotError,
    },
    #[error("invariant violated (seed {seed}, version {version}): {message}")]
    InvariantViolation { seed: u64, version: u64, message: String },
    #[error("simulation exceeded {limit} commands without finishing (seed {seed})")]
    NoTermination { seed: u64, limit: u64 },
}

#[derive(Debug)]
pub struct SimulationOutcome {
    pub seed: u64,
    pub commands_processed: u64,
    pub events: Vec<GameEvent>,
    pub ranking: Vec<RankedPlayer>,
    pub nicknames: HashMap<PlayerId, String>,
}

/// Run one complete six-player game with random bots. See
/// [`simulate_game_with_players`] for other table sizes.
pub fn simulate_game(seed: u64) -> Result<SimulationOutcome, SimulationError> {
    simulate_game_with_players(seed, 6)
}

/// Run one complete game with `player_count` random bots (3–8),
/// checking engine invariants after every accepted command. Fully
/// deterministic per seed.
pub fn simulate_game_with_players(
    seed: u64,
    player_count: u8,
) -> Result<SimulationOutcome, SimulationError> {
    // Player ids are derived from the seed so the entire game — including
    // ids inside events — reproduces exactly (PLAN.md §23.3).
    let players: Vec<PlayerState> = (0..player_count)
        .map(|seat| {
            let id = PlayerId(Uuid::from_u64_pair(seed, seat as u64 + 1));
            PlayerState::bot(id, format!("Bot {}", seat + 1), seat)
        })
        .collect();
    let nicknames: HashMap<PlayerId, String> =
        players.iter().map(|p| (p.id, p.nickname.clone())).collect();

    let rules = GameRules::mvp_for_players(player_count);
    let game_id = GameId(Uuid::from_u64_pair(seed, 0));
    let mut engine = GameEngine::new_with_seed(seed, game_id, rules, players.clone())
        .expect("player count is within the supported table sizes");

    let mut bots: HashMap<PlayerId, RandomBot> = players
        .iter()
        .enumerate()
        .map(|(index, p)| (p.id, RandomBot::new(seed.wrapping_add(index as u64 + 1))))
        .collect();

    let mut events = engine.start_game().map_err(|source| SimulationError::Rejected {
        seed,
        version: engine.version(),
        source,
    })?;
    let mut commands_processed = 1u64;

    // Even the largest game (4 players, 12 rounds) is well under this cap;
    // exceeding it means the state machine stopped making progress.
    const COMMAND_LIMIT: u64 = 10_000;

    while !engine.is_finished() {
        if commands_processed > COMMAND_LIMIT {
            return Err(SimulationError::NoTermination { seed, limit: COMMAND_LIMIT });
        }

        let current = engine
            .state()
            .current_round
            .as_ref()
            .expect("an unfinished started game always has a round")
            .current_turn;
        let view = engine.view_for(current).expect("current player is seated");
        let bot = bots.get_mut(&current).expect("every seat has a bot");

        let new_events = match engine.phase() {
            GamePhase::Bidding => {
                let bid = bot.choose_bid(&view).map_err(|source| SimulationError::Bot {
                    seed,
                    version: engine.version(),
                    source,
                })?;
                engine.place_bid(current, bid)
            }
            GamePhase::Playing => {
                let card = bot.choose_card(&view).map_err(|source| SimulationError::Bot {
                    seed,
                    version: engine.version(),
                    source,
                })?;
                engine.play_card(current, card)
            }
            other => unreachable!("simulation loop should never observe phase {other:?}"),
        }
        .map_err(|source| SimulationError::Rejected { seed, version: engine.version(), source })?;

        events.extend(new_events);
        commands_processed += 1;

        engine.check_invariants().map_err(|message| SimulationError::InvariantViolation {
            seed,
            version: engine.version(),
            message,
        })?;
    }

    let ranking = engine
        .state()
        .score_table
        .final_ranking(&engine.state().player_ids());

    Ok(SimulationOutcome { seed, commands_processed, events, ranking, nicknames })
}
