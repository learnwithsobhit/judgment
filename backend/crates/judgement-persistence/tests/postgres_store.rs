//! Requires DATABASE_URL. Skipped when unset.
//!
//!   docker compose up -d
//!   DATABASE_URL=postgres://judgement:judgement@127.0.0.1:5433/judgement \
//!     cargo test -p judgement-persistence --test postgres_store -- --ignored

use chrono::Utc;
use judgement_domain::{
    ActionId, GameId, GameRules, PlayerId, PlayerState, RoomId, SessionId, Suit, TrumpRule,
};
use judgement_engine::GameEngine;
use judgement_persistence::{
    CommandCommit, GameStore, NewGame, NewGamePlayer, PostgresStore, StoredRoom, StoredRoomPlayer,
    StoredSession,
};

fn migrations_dir() -> std::path::PathBuf {
    std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("migrations")
}

#[tokio::test]
#[ignore = "requires DATABASE_URL pointing at a running Postgres"]
async fn postgres_persists_and_restores_a_game() {
    let url = std::env::var("DATABASE_URL").expect("DATABASE_URL");
    let store = PostgresStore::connect(&url).await.unwrap();
    store.migrate(migrations_dir()).await.unwrap();

    let session_id = SessionId::new();
    store
        .upsert_session(&StoredSession {
            session_id,
            nickname: "Ada".into(),
            token: format!("tok-{}", session_id),
            created_at: Utc::now(),
        })
        .await
        .unwrap();

    let room_id = RoomId::new();
    let mut seats = Vec::new();
    let mut players = Vec::new();
    let mut game_players = Vec::new();
    for seat in 0..4u8 {
        let sid = SessionId::new();
        store
            .upsert_session(&StoredSession {
                session_id: sid,
                nickname: format!("P{seat}"),
                token: format!("tok-{sid}"),
                created_at: Utc::now(),
            })
            .await
            .unwrap();
        let pid = PlayerId::new();
        seats.push(StoredRoomPlayer {
            session_id: sid,
            player_id: pid,
            nickname: format!("P{seat}"),
            seat,
            ready: true,
            joined_at: Utc::now(),
        });
        players.push(PlayerState::human(pid, format!("P{seat}"), seat));
        game_players.push(NewGamePlayer {
            player_id: pid,
            session_id: sid,
            nickname: format!("P{seat}"),
            seat,
        });
    }

    store
        .upsert_room(&StoredRoom {
            room_id,
            code: format!("{}", &room_id.to_string()[..6]).to_uppercase(),
            host_session_id: seats[0].session_id,
            max_players: 4,
            turn_timeout_seconds: None,
            first_trump: Some(Suit::Spades),
            round_schedule: Default::default(),
            phase: "lobby".into(),
            game_id: None,
            players: seats,
            created_at: Utc::now(),
        })
        .await
        .unwrap();

    let game_id = GameId::new();
    let rules = GameRules {
        trump_rule: TrumpRule::rotating_from(Suit::Spades),
        turn_timeout_seconds: None,
        ..GameRules::mvp_for_players(4)
    };
    let mut engine = GameEngine::new_with_seed(99, game_id, rules.clone(), players).unwrap();
    let events = engine.start_game().unwrap();
    let start_action = ActionId::new();
    store
        .create_game(&NewGame {
            game_id,
            room_id,
            rules,
            seed: Some(99),
            players: game_players,
            initial_state: engine.state().clone(),
            initial_events: events,
            start_action_id: start_action,
        })
        .await
        .unwrap();

    let bidder = engine.state().current_round.as_ref().unwrap().current_turn;
    let bid = engine.legal_bids(bidder)[0];
    let action = ActionId::new();
    let events = engine.place_bid(bidder, bid).unwrap();
    store
        .commit_command(&CommandCommit {
            game_id,
            action_id: action,
            events,
            state: engine.state().clone(),
            round_result: None,
            game_result: None,
        })
        .await
        .unwrap();

    let active = store.load_active_games().await.unwrap();
    let restored = active
        .into_iter()
        .find(|g| g.game_id == game_id)
        .expect("game restored");
    assert_eq!(restored.state.version, engine.version());
    assert!(restored
        .processed_actions
        .iter()
        .any(|(a, _)| *a == start_action));
    assert!(restored.processed_actions.iter().any(|(a, _)| *a == action));
    GameEngine::from_restored_state(restored.state)
        .check_invariants()
        .unwrap();

    let history = store.load_game_history(game_id).await.unwrap().unwrap();
    assert_eq!(history.status, "active");
    assert!(history.event_count >= 2);

    let _ = session_id;
}
