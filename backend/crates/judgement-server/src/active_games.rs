//! Public snapshot of games in progress. The actor writes it; HTTP only reads it.
//!
//! The payload is nicknames, avatars, completed-round totals, and the round
//! phase. Hands, bids, the current trick, and the room code stay on the table.

use std::sync::Arc;

use axum::extract::State;
use axum::Json;
use chrono::{DateTime, Utc};
use judgement_domain::GameId;
use judgement_engine::{GamePhase, InternalGameState};
use judgement_protocol::{ActiveGame, ActiveGameSeat, ActiveGamesResponse};

use crate::state::AppState;

pub fn board_from_state(state: &InternalGameState, now: DateTime<Utc>) -> ActiveGame {
    let total_rounds = state.rules.round_pattern.rounds().len().max(1) as i32;
    let completed = state.score_table.rounds.len() as i32;
    let round_index = if matches!(state.phase, GamePhase::Finished | GamePhase::GameScoring) {
        total_rounds
    } else {
        (completed + 1).min(total_rounds).max(1)
    };
    let mut seats: Vec<ActiveGameSeat> = state
        .players
        .iter()
        .map(|player| ActiveGameSeat {
            display_name: if player.nickname.is_empty() {
                "Player".into()
            } else {
                player.nickname.clone()
            },
            avatar_id: player.avatar_id.clone(),
            total_score: state.score_table.total_score(player.id),
        })
        .collect();
    seats.sort_by(|a, b| {
        b.total_score
            .cmp(&a.total_score)
            .then_with(|| a.display_name.cmp(&b.display_name))
    });
    ActiveGame {
        game_id: state.game_id.to_string(),
        updated_at: now,
        round_index,
        total_rounds,
        phase: phase_word(state.phase).into(),
        seats,
    }
}

pub fn phase_word(phase: GamePhase) -> &'static str {
    match phase {
        GamePhase::Bidding => "bidding",
        GamePhase::Playing => "playing",
        GamePhase::RoundScoring | GamePhase::GameScoring | GamePhase::Finished => "scoring",
        GamePhase::Lobby | GamePhase::RoundSetup | GamePhase::Dealing => "dealing",
    }
}

pub fn publish_board(state: &AppState, game_id: GameId, board: ActiveGame) {
    state.active_games.lock().unwrap().insert(game_id, board);
}

pub fn clear_board(state: &AppState, game_id: GameId) {
    state.active_games.lock().unwrap().remove(&game_id);
}

pub async fn get_active_games(State(state): State<Arc<AppState>>) -> Json<ActiveGamesResponse> {
    let mut games: Vec<ActiveGame> = state
        .active_games
        .lock()
        .unwrap()
        .values()
        .cloned()
        .collect();
    games.sort_by(|a, b| {
        b.updated_at
            .cmp(&a.updated_at)
            .then(a.game_id.cmp(&b.game_id))
    });
    Json(ActiveGamesResponse { games })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    use judgement_domain::{
        GameRules, PlayerId, PlayerState, RoundPattern, RoundScoreEntry, Suit, TrumpRule,
    };
    use judgement_engine::GameEngine;

    fn started(names: &[&str], rounds: Vec<u8>) -> InternalGameState {
        let players: Vec<_> = names
            .iter()
            .enumerate()
            .map(|(seat, name)| {
                PlayerState::human(PlayerId::new(), (*name).to_string(), seat as u8)
            })
            .collect();
        let rules = GameRules {
            trump_rule: TrumpRule::rotating_from(Suit::Clubs),
            turn_timeout_seconds: None,
            round_pattern: RoundPattern::Custom { rounds },
            ..GameRules::mvp_for_players(names.len() as u8)
        };
        let mut engine = GameEngine::new_with_seed(7, GameId::new(), rules, players).unwrap();
        engine.start_game().unwrap();
        engine.state().clone()
    }

    #[test]
    fn before_any_scored_round_everyone_is_on_round_one_at_zero() {
        let state = started(
            &["Cara", "Ankit", "Beena"],
            vec![1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        );
        let board = board_from_state(&state, Utc::now());
        assert_eq!(board.round_index, 1);
        assert_eq!(board.total_rounds, 12);
        assert_eq!(board.phase, "bidding");
        assert!(board.seats.iter().all(|seat| seat.total_score == 0));
        assert_eq!(
            board
                .seats
                .iter()
                .map(|seat| seat.display_name.as_str())
                .collect::<Vec<_>>(),
            vec!["Ankit", "Beena", "Cara"]
        );
    }

    #[test]
    fn higher_scores_sort_first_and_names_break_a_tie() {
        let mut state = started(
            &["Cara", "Beena", "Ankit"],
            vec![1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
        );
        let mut round = HashMap::new();
        for player in &state.players {
            let score = if player.nickname == "Cara" { 0 } else { 10 };
            round.insert(
                player.id,
                RoundScoreEntry {
                    bid: 1,
                    tricks_won: 1,
                    score,
                },
            );
        }
        state.score_table.record_round(round);
        state.phase = GamePhase::Playing;
        let board = board_from_state(&state, Utc::now());
        assert_eq!(board.round_index, 2);
        assert_eq!(board.phase, "playing");
        assert_eq!(board.seats[0].display_name, "Ankit");
        assert_eq!(board.seats[0].total_score, 10);
        assert_eq!(board.seats[1].display_name, "Beena");
        assert_eq!(board.seats[1].total_score, 10);
        assert_eq!(board.seats[2].display_name, "Cara");
        assert_eq!(board.seats[2].total_score, 0);
    }

    #[test]
    fn phase_words_stay_on_the_public_list() {
        assert_eq!(phase_word(GamePhase::Dealing), "dealing");
        assert_eq!(phase_word(GamePhase::Bidding), "bidding");
        assert_eq!(phase_word(GamePhase::Playing), "playing");
        assert_eq!(phase_word(GamePhase::RoundScoring), "scoring");
    }

    #[test]
    fn the_public_board_has_no_room_code_or_cards() {
        let state = started(&["Ada", "Bea", "Cal"], vec![1]);
        let board = board_from_state(&state, Utc::now());
        let text = serde_json::to_string(&board).unwrap();
        assert!(!text.contains("\"code\""));
        assert!(!text.contains("card"));
        assert!(!text.contains("\"bid\""));
        assert!(!text.contains("player_id"));
    }

    #[test]
    fn finishing_or_aborting_drops_the_snapshot() {
        use judgement_domain::{PlayerId, RoomId};
        use judgement_persistence::MemoryStore;

        use crate::actor::AbortedCleanup;
        use crate::cleanup::{apply_aborted_cleanup, apply_finished_cleanup};

        let state = AppState::new(Arc::new(MemoryStore::new()));
        let finished = GameId::new();
        publish_board(
            &state,
            finished,
            board_from_state(&started(&["Ada", "Bea", "Cal"], vec![1]), Utc::now()),
        );
        apply_finished_cleanup(&state, finished);
        assert!(state.active_games.lock().unwrap().is_empty());

        let aborted = GameId::new();
        publish_board(
            &state,
            aborted,
            board_from_state(&started(&["Ada", "Bea", "Cal"], vec![1]), Utc::now()),
        );
        apply_aborted_cleanup(
            &state,
            RoomId::new(),
            &AbortedCleanup {
                game_id: aborted,
                vacant_player_ids: vec![],
                host_player_id: PlayerId::new(),
            },
        );
        assert!(state.active_games.lock().unwrap().is_empty());
    }
}
