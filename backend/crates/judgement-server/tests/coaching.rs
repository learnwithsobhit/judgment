//! Phase 8: coach / highlights endpoints use verified analytics only.

use std::sync::Arc;
use std::time::Duration;

use chrono::Utc;
use judgement_domain::{
    ActionId, GameId, GameRules, PlayerId, PlayerState, RoomId, RoundPattern, SessionId, Suit,
    TrumpRule,
};
use judgement_engine::{GameEngine, GameEvent, GamePhase};
use judgement_persistence::{
    CommandCommit, GameResultRecord, GameStore, MemoryStore, NewGame, NewGamePlayer,
    RoundResultRecord, StoredRoom, StoredRoomPlayer, StoredSession,
};
use judgement_server::{build_router, state::AppState};
use serde_json::Value;
use tokio::net::TcpListener;

async fn finish_one_round_game(store: &MemoryStore) -> (GameId, PlayerId, String) {
    let token = "coach-token".to_string();
    let session_ids: Vec<_> = (0..4).map(|_| SessionId::new()).collect();
    for (i, &session_id) in session_ids.iter().enumerate() {
        store
            .upsert_session(&StoredSession {
                session_id,
                nickname: format!("P{i}"),
                token: if i == 0 { token.clone() } else { format!("tok-{i}") },
                created_at: Utc::now(),
            })
            .await
            .unwrap();
    }

    let room_id = RoomId::new();
    let players: Vec<PlayerState> = (0..4)
        .map(|seat| PlayerState::human(PlayerId::new(), format!("P{seat}"), seat))
        .collect();
    let focus = players[0].id;
    let game_players: Vec<NewGamePlayer> = players
        .iter()
        .zip(session_ids.iter())
        .map(|(p, &session_id)| NewGamePlayer {
            player_id: p.id,
            session_id,
            nickname: p.nickname.clone(),
            seat: p.seat,
        })
        .collect();

    store
        .upsert_room(&StoredRoom {
            room_id,
            code: "COACH1".into(),
            host_session_id: session_ids[0],
            max_players: 4,
            turn_timeout_seconds: None,
            first_trump: Some(Suit::Clubs),
            round_schedule: Default::default(),
            phase: "in_game".into(),
            game_id: None,
            players: game_players
                .iter()
                .map(|p| StoredRoomPlayer {
                    session_id: p.session_id,
                    player_id: p.player_id,
                    nickname: p.nickname.clone(),
                    seat: p.seat,
                    ready: true,
                    joined_at: Utc::now(),
                })
                .collect(),
            created_at: Utc::now(),
        })
        .await
        .unwrap();

    let game_id = GameId::new();
    let rules = GameRules {
        trump_rule: TrumpRule::rotating_from(Suit::Clubs),
        turn_timeout_seconds: None,
        round_pattern: RoundPattern::Custom { rounds: vec![1] },
        ..GameRules::mvp_for_players(4)
    };
    let mut engine = GameEngine::new_with_seed(11, game_id, rules.clone(), players).unwrap();
    let events = engine.start_game().unwrap();
    store
        .create_game(&NewGame {
            game_id,
            room_id,
            rules,
            seed: Some(11),
            players: game_players,
            initial_state: engine.state().clone(),
            initial_events: events,
            start_action_id: ActionId::new(),
        })
        .await
        .unwrap();

    while engine.phase() == GamePhase::Bidding {
        let turn = engine.state().current_round.as_ref().unwrap().current_turn;
        let bid = engine.legal_bids(turn)[0];
        let events = engine.place_bid(turn, bid).unwrap();
        store
            .commit_command(&to_commit(game_id, ActionId::new(), &events, engine.state()))
            .await
            .unwrap();
    }
    while !engine.is_finished() {
        let turn = engine.state().current_round.as_ref().unwrap().current_turn;
        let card = engine.legal_cards(turn)[0];
        let events = engine.play_card(turn, card).unwrap();
        store
            .commit_command(&to_commit(game_id, ActionId::new(), &events, engine.state()))
            .await
            .unwrap();
    }

    (game_id, focus, token)
}

fn to_commit(
    game_id: GameId,
    action_id: ActionId,
    events: &[GameEvent],
    state: &judgement_engine::InternalGameState,
) -> CommandCommit {
    let round_result = events.iter().find_map(|e| match e {
        GameEvent::RoundCompleted { round_index } => Some(RoundResultRecord {
            round_index: *round_index,
            scores: serde_json::to_value(
                state
                    .score_table
                    .rounds
                    .get(*round_index)
                    .cloned()
                    .unwrap_or_default(),
            )
            .unwrap_or_default(),
        }),
        _ => None,
    });
    let game_result = events.iter().find_map(|e| match e {
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

async fn spawn(store: Arc<MemoryStore>) -> (String, Arc<AppState>) {
    let state = Arc::new(AppState::new(store));
    // Mirror durable sessions into AppState auth maps.
    for session in state.store.load_sessions().await.unwrap() {
        state.sessions.lock().unwrap().insert(
            session.session_id,
            judgement_server::state::Session {
                id: session.session_id,
                nickname: session.nickname.clone(),
                token: session.token.clone(),
            },
        );
        state
            .tokens
            .lock()
            .unwrap()
            .insert(session.token, session.session_id);
    }

    let app = build_router(state.clone());
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    (format!("http://{addr}"), state)
}

#[tokio::test]
async fn coach_and_highlights_are_deterministic() {
    let store = Arc::new(MemoryStore::new());
    let (game_id, player_id, token) = finish_one_round_game(&store).await;
    let (base, _) = spawn(store).await;
    tokio::time::sleep(Duration::from_millis(40)).await;

    let client = reqwest::Client::new();
    let coach: Value = client
        .get(format!("{base}/api/v1/games/{game_id}/coach/{player_id}"))
        .bearer_auth(&token)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();

    assert!(coach["deterministic"].as_bool().unwrap());
    assert!(coach["fallback_reason"].is_null());
    assert!(coach["headline"].as_str().unwrap().contains("Bid accuracy"));
    assert!(!coach["improvements"].as_array().unwrap().is_empty());
    assert_eq!(
        coach["analysis"]["total_rounds"].as_u64().unwrap(),
        1
    );
    let exact = coach["analysis"]["exact_bid_rounds"].as_u64().unwrap();
    let over = coach["analysis"]["overbid_rounds"].as_u64().unwrap();
    let under = coach["analysis"]["underbid_rounds"].as_u64().unwrap();
    assert_eq!(exact + over + under, 1);

    let highlights: Value = client
        .get(format!("{base}/api/v1/games/{game_id}/highlights"))
        .bearer_auth(&token)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(highlights["deterministic"].as_bool().unwrap());
    assert!(!highlights["lines"].as_array().unwrap().is_empty());
    assert!(highlights["facts"]["facts"].as_array().unwrap().len() >= 1);

    let summary: Value = client
        .get(format!(
            "{base}/api/v1/games/{game_id}/rounds/0/summary?player_id={player_id}"
        ))
        .bearer_auth(&token)
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap()
        .json()
        .await
        .unwrap();
    assert!(summary["narration"]["deterministic"].as_bool().unwrap());
    assert_eq!(summary["summary"]["round_index"].as_u64().unwrap(), 0);
}
