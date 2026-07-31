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

#[tokio::test]
async fn memory_store_finishes_game_and_records_history() {
    let store = MemoryStore::new();

    let session_ids: Vec<_> = (0..4).map(|_| SessionId::new()).collect();
    for (i, &session_id) in session_ids.iter().enumerate() {
        store
            .upsert_session(&StoredSession {
                session_id,
                nickname: format!("P{i}"),
                token: format!("tok-{i}"),
                created_at: Utc::now(),
            })
            .await
            .unwrap();
    }

    let room_id = RoomId::new();
    let players: Vec<PlayerState> = (0..4)
        .map(|seat| PlayerState::human(PlayerId::new(), format!("P{seat}"), seat))
        .collect();
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
            code: "ABCD12".into(),
            host_session_id: session_ids[0],
            max_players: 4,
            turn_timeout_seconds: None,
            first_trump: Some(Suit::Clubs),
            round_schedule: Default::default(),
            phase: "lobby".into(),
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
    let mut engine = GameEngine::new_with_seed(7, game_id, rules.clone(), players).unwrap();
    let events = engine.start_game().unwrap();
    let start_action = ActionId::new();

    store
        .create_game(&NewGame {
            game_id,
            room_id,
            rules,
            seed: Some(7),
            players: game_players,
            initial_state: engine.state().clone(),
            initial_events: events,
            start_action_id: start_action,
        })
        .await
        .unwrap();

    while engine.phase() == GamePhase::Bidding {
        let turn = engine.state().current_round.as_ref().unwrap().current_turn;
        let bid = engine.legal_bids(turn)[0];
        let action_id = ActionId::new();
        let events = engine.place_bid(turn, bid).unwrap();
        store
            .commit_command(&to_commit(game_id, action_id, &events, engine.state()))
            .await
            .unwrap();
    }
    while !engine.is_finished() {
        let turn = engine.state().current_round.as_ref().unwrap().current_turn;
        let card = engine.legal_cards(turn)[0];
        let action_id = ActionId::new();
        let events = engine.play_card(turn, card).unwrap();
        store
            .commit_command(&to_commit(game_id, action_id, &events, engine.state()))
            .await
            .unwrap();
    }

    let history = store.load_game_history(game_id).await.unwrap().unwrap();
    assert_eq!(history.status, "finished");
    assert_eq!(history.round_results.len(), 1);
    assert_eq!(history.ranking.as_ref().unwrap().len(), 4);
    assert!(store.load_active_games().await.unwrap().is_empty());

    let dedup = store.load_processed_actions(game_id).await.unwrap();
    assert!(dedup.iter().any(|(a, _)| *a == start_action));
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
            .unwrap(),
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
