//! Helpers that turn in-memory server types into durable records.

use std::sync::Arc;

use chrono::Utc;
use judgement_domain::{ActionId, GameId, GameRules, RoomId};
use judgement_engine::{GameEvent, GameEngine, InternalGameState};
use judgement_persistence::{
    CommandCommit, GameResultRecord, GameStore, NewGame, NewGamePlayer, RoundResultRecord,
    StoredRoom, StoredRoomPlayer, StoredSession,
};

use crate::state::{Room, RoomStatus, Session};

pub fn stored_session(session: &Session) -> StoredSession {
    StoredSession {
        session_id: session.id,
        nickname: session.nickname.clone(),
        token: session.token.clone(),
        created_at: Utc::now(),
        avatar_id: session.avatar_id.clone(),
    }
}

pub fn stored_room(room: &Room) -> StoredRoom {
    let (phase, game_id) = match room.status {
        RoomStatus::Lobby => ("lobby".to_string(), None),
        RoomStatus::InGame(id) => ("in_game".to_string(), Some(id)),
    };
    StoredRoom {
        room_id: room.id,
        code: room.code.clone(),
        host_session_id: room.host_session,
        max_players: room.max_players,
        turn_timeout_seconds: room.turn_timeout_seconds,
        first_trump: room.first_trump,
        round_schedule: room.round_schedule.clone(),
        dealer_total_restriction: room.dealer_total_restriction,
        phase,
        game_id,
        players: room
            .seats
            .iter()
            .map(|s| StoredRoomPlayer {
                session_id: s.session_id,
                player_id: s.player_id,
                nickname: s.nickname.clone(),
                seat: s.seat,
                ready: s.ready,
                joined_at: s.joined_at,
                avatar_id: s.avatar_id.clone(),
            })
            .collect(),
        created_at: Utc::now(),
    }
}

pub async fn persist_new_game(
    store: &Arc<dyn GameStore>,
    room_id: RoomId,
    game_id: GameId,
    rules: GameRules,
    seed: Option<u64>,
    players: Vec<NewGamePlayer>,
    engine: &GameEngine,
    events: Vec<GameEvent>,
    start_action_id: ActionId,
) -> Result<(), judgement_persistence::PersistError> {
    store
        .create_game(&NewGame {
            game_id,
            room_id,
            rules,
            seed,
            players,
            initial_state: engine.state().clone(),
            initial_events: events,
            start_action_id,
        })
        .await
}

pub fn command_commit_from(
    game_id: GameId,
    action_id: ActionId,
    events: &[GameEvent],
    state: &InternalGameState,
) -> CommandCommit {
    let round_result = events.iter().find_map(|event| match event {
        GameEvent::RoundCompleted { round_index } => {
            let scores = state
                .score_table
                .rounds
                .get(*round_index)
                .cloned()
                .unwrap_or_default();
            Some(RoundResultRecord {
                round_index: *round_index,
                scores: serde_json::to_value(scores).unwrap_or_default(),
            })
        }
        _ => None,
    });

    let game_result = events.iter().find_map(|event| match event {
        GameEvent::GameCompleted { ranking } => Some(GameResultRecord {
            ranking: ranking.clone(),
        }),
        _ => None,
    });

    CommandCommit {
        game_id,
        action_id,
        events: events.to_vec(),
        state: state.clone(),
        round_result,
        game_result,
    }
}
