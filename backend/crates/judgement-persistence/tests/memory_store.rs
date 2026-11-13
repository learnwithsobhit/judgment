use chrono::Utc;
use judgement_domain::{
    ActionId, GameId, GameRules, PlayerId, PlayerState, RoomId, RoundPattern, SessionId, Suit,
    TrumpRule,
};
use judgement_engine::{GameEngine, GameEvent, GamePhase};
use judgement_persistence::{
    stats::PulseFinish, CommandCommit, GameResultRecord, GameStore, MemoryStore, NewGame,
    NewGamePlayer, RoundResultRecord, StoredRoom, StoredRoomPlayer, StoredSession,
    StoredTournament, StoredUser, TournamentStatus,
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
                avatar_id: None,
                photo_url: None,
                user_id: None,
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
            user_id: None,
        })
        .collect();

    store
        .upsert_room(&StoredRoom {
            room_id,
            code: "ABCD12".into(),
            host_session_id: session_ids[0],
            max_players: 4,
            turn_timeout_seconds: None,
            bid_timeout_seconds: None,
            first_trump: Some(Suit::Clubs),
            trump_cycle: None,
            round_schedule: Default::default(),
            dealer_total_restriction: false,
            open_start: false,
            tournament_id: None,
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
                    avatar_id: None,
                    photo_url: None,
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
        bid_timeout_seconds: None,
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
        match engine.phase() {
            GamePhase::Playing => {
                let turn = engine.state().current_round.as_ref().unwrap().current_turn;
                let card = engine.legal_cards(turn)[0];
                let action_id = ActionId::new();
                let events = engine.play_card(turn, card).unwrap();
                store
                    .commit_command(&to_commit(game_id, action_id, &events, engine.state()))
                    .await
                    .unwrap();
            }
            GamePhase::RoundScoring => {
                let action_id = ActionId::new();
                let events = engine.advance_from_round_scoring().unwrap();
                store
                    .commit_command(&to_commit(game_id, action_id, &events, engine.state()))
                    .await
                    .unwrap();
            }
            other => panic!("unexpected phase while playing out: {other:?}"),
        }
    }

    let history = store.load_game_history(game_id).await.unwrap().unwrap();
    assert_eq!(history.status, "finished");
    assert_eq!(history.round_results.len(), 1);
    assert_eq!(history.ranking.as_ref().unwrap().len(), 4);
    assert!(store.load_active_games().await.unwrap().is_empty());

    let dedup = store.load_processed_actions(game_id).await.unwrap();
    assert!(dedup.iter().any(|(a, _)| *a == start_action));
}

/// Commit-uncertainty: after a durable commit, `action_committed` must be true
/// even if a later client path thought the write failed.
#[tokio::test]
async fn action_committed_detects_durable_action_id() {
    let store = MemoryStore::new();
    let session_ids: Vec<_> = (0..4).map(|_| SessionId::new()).collect();
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
            user_id: None,
        })
        .collect();
    let room_id = RoomId::new();
    store
        .upsert_room(&StoredRoom {
            room_id,
            code: "TEST01".into(),
            host_session_id: session_ids[0],
            max_players: 4,
            turn_timeout_seconds: None,
            bid_timeout_seconds: None,
            first_trump: Some(Suit::Clubs),
            trump_cycle: None,
            round_schedule: Default::default(),
            dealer_total_restriction: false,
            open_start: false,
            tournament_id: None,
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
                    avatar_id: None,
                    photo_url: None,
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
        bid_timeout_seconds: None,
        round_pattern: RoundPattern::Custom { rounds: vec![1] },
        ..GameRules::mvp_for_players(4)
    };
    let mut engine = GameEngine::new_with_seed(1, game_id, rules.clone(), players).unwrap();
    let events = engine.start_game().unwrap();
    let start_action = ActionId::new();
    store
        .create_game(&NewGame {
            game_id,
            room_id,
            rules,
            seed: Some(1),
            players: game_players,
            initial_state: engine.state().clone(),
            initial_events: events,
            start_action_id: start_action,
        })
        .await
        .unwrap();

    assert!(store.action_committed(game_id, start_action).await.unwrap());
    assert!(!store
        .action_committed(game_id, ActionId::new())
        .await
        .unwrap());

    let turn = engine.state().current_round.as_ref().unwrap().current_turn;
    let bid = engine.legal_bids(turn)[0];
    let action_id = ActionId::new();
    let events = engine.place_bid(turn, bid).unwrap();
    store
        .commit_command(&to_commit(game_id, action_id, &events, engine.state()))
        .await
        .unwrap();
    // Idempotent re-commit (simulates timeout retry after success).
    store
        .commit_command(&to_commit(game_id, action_id, &events, engine.state()))
        .await
        .unwrap();
    assert!(store.action_committed(game_id, action_id).await.unwrap());
    assert!(store.load_active_game(game_id).await.unwrap().is_some());
}

#[tokio::test]
async fn signed_in_finish_is_counted_once_and_survives_delete() {
    let store = MemoryStore::new();
    let user_id = uuid::Uuid::new_v4();
    let now = Utc::now();
    store
        .upsert_user(&StoredUser {
            user_id,
            display_name: "Ada".into(),
            avatar_id: Some("face_01".into()),
            photo_url: None,
            legal_version: Some("2026-08-03".into()),
            created_at: now,
            updated_at: now,
            last_seen_at: now,
        })
        .await
        .unwrap();

    let session_ids: Vec<_> = (0..4).map(|_| SessionId::new()).collect();
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
            user_id: if p.seat <= 1 { Some(user_id) } else { None },
        })
        .collect();

    let game_id = GameId::new();
    let rules = GameRules {
        trump_rule: TrumpRule::rotating_from(Suit::Clubs),
        turn_timeout_seconds: None,
        bid_timeout_seconds: None,
        round_pattern: RoundPattern::Custom { rounds: vec![1] },
        ..GameRules::mvp_for_players(4)
    };
    let mut engine = GameEngine::new_with_seed(11, game_id, rules.clone(), players).unwrap();
    let events = engine.start_game().unwrap();
    store
        .create_game(&NewGame {
            game_id,
            room_id: RoomId::new(),
            rules,
            seed: Some(11),
            players: game_players,
            initial_state: engine.state().clone(),
            initial_events: events,
            start_action_id: ActionId::new(),
        })
        .await
        .unwrap();

    let mut finish_commit = None;
    while !engine.is_finished() {
        let action_id = ActionId::new();
        let events = match engine.phase() {
            GamePhase::Bidding => {
                let turn = engine.state().current_round.as_ref().unwrap().current_turn;
                let bid = engine.legal_bids(turn)[0];
                engine.place_bid(turn, bid).unwrap()
            }
            GamePhase::Playing => {
                let turn = engine.state().current_round.as_ref().unwrap().current_turn;
                let card = engine.legal_cards(turn)[0];
                engine.play_card(turn, card).unwrap()
            }
            GamePhase::RoundScoring => engine.advance_from_round_scoring().unwrap(),
            other => panic!("unexpected phase {other:?}"),
        };
        let commit = to_commit(game_id, action_id, &events, engine.state());
        if commit.game_result.is_some() {
            finish_commit = Some(commit.clone());
        }
        store.commit_command(&commit).await.unwrap();
    }

    let stats = store.load_user_stats(user_id).await.unwrap().unwrap();
    assert_eq!(stats.games_played, 1, "two seats of one account count once");
    assert_eq!(stats.ranked_games, 1);
    store
        .commit_command(&finish_commit.expect("finish"))
        .await
        .unwrap();
    let again = store.load_user_stats(user_id).await.unwrap().unwrap();
    assert_eq!(again.games_played, 1);
    store.delete_game(game_id).await.unwrap();
    let kept = store.load_user_stats(user_id).await.unwrap().unwrap();
    assert_eq!(kept.games_played, 1);
    assert_eq!(kept.display_name, "Ada");
    let board = store.load_leaderboard(10).await.unwrap();
    assert_eq!(board.len(), 1);
    assert_eq!(board[0].display_name, "Ada");
    assert!(board[0].avatar_id.is_some());
}

#[tokio::test]
async fn tournament_stamp_survives_delete_and_feeds_standings() {
    let store = MemoryStore::new();
    let now = Utc::now();
    let tournament_id = uuid::Uuid::new_v4();
    store
        .upsert_tournament(&StoredTournament {
            tournament_id,
            slug: "friday-night".into(),
            title: "Friday Night".into(),
            blurb: "".into(),
            format: "points".into(),
            status: TournamentStatus::Live,
            starts_at: None,
            ends_at: None,
            created_by: None,
            created_at: now,
            updated_at: now,
        })
        .await
        .unwrap();
    let listed = store.list_tournaments().await.unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].slug, "friday-night");

    let user_a = uuid::Uuid::new_v4();
    let user_b = uuid::Uuid::new_v4();
    for (user_id, name) in [(user_a, "Ada"), (user_b, "Bea")] {
        store
            .upsert_user(&StoredUser {
                user_id,
                display_name: name.into(),
                avatar_id: None,
                photo_url: None,
                legal_version: None,
                created_at: now,
                updated_at: now,
                last_seen_at: now,
            })
            .await
            .unwrap();
    }
    let game_id = uuid::Uuid::new_v4();
    store.seed_counted_finishes(vec![
        PulseFinish {
            game_id,
            user_id: user_a,
            finished_at: now,
            finish_rank: 1,
            exact_bid_rounds: 2,
            rounds_played: 4,
            total_score: 40,
            tournament_id: Some(tournament_id),
        },
        PulseFinish {
            game_id,
            user_id: user_b,
            finished_at: now,
            finish_rank: 2,
            exact_bid_rounds: 1,
            rounds_played: 4,
            total_score: 20,
            tournament_id: Some(tournament_id),
        },
        PulseFinish {
            game_id: uuid::Uuid::new_v4(),
            user_id: user_a,
            finished_at: now,
            finish_rank: 1,
            exact_bid_rounds: 1,
            rounds_played: 3,
            total_score: 30,
            tournament_id: None,
        },
    ]);

    let overall = store.load_leaderboard(10).await.unwrap();
    assert_eq!(overall.len(), 2);
    assert_eq!(overall[0].user_id, user_a);
    assert_eq!(overall[0].gold, 2);

    let standings = store
        .load_tournament_standings(tournament_id, 50)
        .await
        .unwrap();
    assert_eq!(standings.len(), 2);
    assert_eq!(standings[0].user_id, user_a);
    assert_eq!(standings[0].gold, 1);
    assert_eq!(standings[0].medal_points, 500);
    assert_eq!(standings[1].user_id, user_b);
    assert_eq!(standings[1].medal_points, 100);
    assert_eq!(
        store.count_tournament_tables(tournament_id).await.unwrap(),
        1
    );
}

#[tokio::test]
async fn finish_commit_stamps_tournament_id_into_standings() {
    let store = MemoryStore::new();
    let now = Utc::now();
    let tournament_id = uuid::Uuid::new_v4();
    store
        .upsert_tournament(&StoredTournament {
            tournament_id,
            slug: "live-stamp".into(),
            title: "Live Stamp".into(),
            blurb: "".into(),
            format: "points".into(),
            status: TournamentStatus::Live,
            starts_at: None,
            ends_at: None,
            created_by: None,
            created_at: now,
            updated_at: now,
        })
        .await
        .unwrap();
    let users: Vec<_> = (0..3).map(|_| uuid::Uuid::new_v4()).collect();
    for (i, user_id) in users.iter().enumerate() {
        store
            .upsert_user(&StoredUser {
                user_id: *user_id,
                display_name: format!("P{i}"),
                avatar_id: None,
                photo_url: None,
                legal_version: None,
                created_at: now,
                updated_at: now,
                last_seen_at: now,
            })
            .await
            .unwrap();
    }

    let session_ids: Vec<_> = (0..3).map(|_| SessionId::new()).collect();
    let players: Vec<PlayerState> = (0..3)
        .map(|seat| PlayerState::human(PlayerId::new(), format!("P{seat}"), seat))
        .collect();
    let game_players: Vec<NewGamePlayer> = players
        .iter()
        .zip(session_ids.iter())
        .zip(users.iter())
        .map(|((p, &session_id), &user_id)| NewGamePlayer {
            player_id: p.id,
            session_id,
            nickname: p.nickname.clone(),
            seat: p.seat,
            user_id: Some(user_id),
        })
        .collect();

    let game_id = GameId::new();
    let rules = GameRules {
        trump_rule: TrumpRule::rotating_from(Suit::Clubs),
        turn_timeout_seconds: None,
        bid_timeout_seconds: None,
        round_pattern: RoundPattern::Custom { rounds: vec![1] },
        ..GameRules::mvp_for_players(3)
    };
    let mut engine = GameEngine::new_with_seed(7, game_id, rules.clone(), players).unwrap();
    let events = engine.start_game().unwrap();
    store
        .create_game(&NewGame {
            game_id,
            room_id: RoomId::new(),
            rules,
            seed: Some(7),
            players: game_players,
            initial_state: engine.state().clone(),
            initial_events: events,
            start_action_id: ActionId::new(),
        })
        .await
        .unwrap();

    while !engine.is_finished() {
        let action_id = ActionId::new();
        let events = match engine.phase() {
            GamePhase::Bidding => {
                let turn = engine.state().current_round.as_ref().unwrap().current_turn;
                let bid = engine.legal_bids(turn)[0];
                engine.place_bid(turn, bid).unwrap()
            }
            GamePhase::Playing => {
                let turn = engine.state().current_round.as_ref().unwrap().current_turn;
                let card = engine.legal_cards(turn)[0];
                engine.play_card(turn, card).unwrap()
            }
            GamePhase::RoundScoring => engine.advance_from_round_scoring().unwrap(),
            other => panic!("unexpected phase {other:?}"),
        };
        let mut commit = to_commit(game_id, action_id, &events, engine.state());
        commit.tournament_id = Some(tournament_id);
        store.commit_command(&commit).await.unwrap();
    }

    store.delete_game(game_id).await.unwrap();
    let standings = store
        .load_tournament_standings(tournament_id, 50)
        .await
        .unwrap();
    assert_eq!(standings.len(), 3);
    assert_eq!(
        store.count_tournament_tables(tournament_id).await.unwrap(),
        1
    );
    let overall = store.load_leaderboard(10).await.unwrap();
    assert_eq!(overall.len(), 3, "dual credit still feeds Top players");
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
        pace: Vec::new(),
        tournament_id: None,
    }
}
