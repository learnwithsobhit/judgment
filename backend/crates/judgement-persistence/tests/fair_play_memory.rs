use chrono::Utc;
use judgement_persistence::{
    fair_play::validate_ratings, FairPlayRating, FairPlayRosterSeat, GameStore, MemoryStore,
};
use uuid::Uuid;

#[tokio::test]
async fn submit_updates_totals_without_exposing_peer_scores_in_storage_api() {
    let store = MemoryStore::new();
    let game = Uuid::new_v4();
    let alice = Uuid::new_v4();
    let bob = Uuid::new_v4();
    let cara = Uuid::new_v4();
    let finished = Utc::now();
    store
        .write_fair_play_roster(&[
            FairPlayRosterSeat {
                game_id: game,
                user_id: alice,
                player_id: Uuid::new_v4(),
                display_name: "Alice".into(),
                avatar_id: None,
                photo_url: None,
                finished_at: finished,
            },
            FairPlayRosterSeat {
                game_id: game,
                user_id: bob,
                player_id: Uuid::new_v4(),
                display_name: "Bob".into(),
                avatar_id: None,
                photo_url: None,
                finished_at: finished,
            },
            FairPlayRosterSeat {
                game_id: game,
                user_id: cara,
                player_id: Uuid::new_v4(),
                display_name: "Cara".into(),
                avatar_id: None,
                photo_url: None,
                finished_at: finished,
            },
        ])
        .await
        .unwrap();

    let ratings = vec![
        FairPlayRating {
            target_user_id: bob,
            points: 9,
        },
        FairPlayRating {
            target_user_id: cara,
            points: 7,
        },
    ];
    let roster = store.load_fair_play_roster(game).await.unwrap();
    assert!(validate_ratings(alice, &roster, &ratings).is_ok());

    let totals = store.submit_fair_play(game, alice, &ratings).await.unwrap();
    assert!(store
        .fair_play_already_submitted(game, alice)
        .await
        .unwrap());
    assert!(store.submit_fair_play(game, alice, &ratings).await.is_err());

    let bob_total = totals.iter().find(|t| t.user_id == bob).unwrap();
    assert_eq!(bob_total.points, 9);
    assert_eq!(bob_total.ratings, 1);

    let board = store.load_fair_play_leaderboard(10).await.unwrap();
    assert_eq!(board[0].user_id, bob);
    assert_eq!(board[0].points_received, 9);
    assert_eq!(board[0].games_rated, 1);

    // Lower total but higher average ranks first.
    let game2 = Uuid::new_v4();
    store
        .write_fair_play_roster(&[
            FairPlayRosterSeat {
                game_id: game2,
                user_id: alice,
                player_id: Uuid::new_v4(),
                display_name: "Alice".into(),
                avatar_id: None,
                photo_url: None,
                finished_at: finished,
            },
            FairPlayRosterSeat {
                game_id: game2,
                user_id: bob,
                player_id: Uuid::new_v4(),
                display_name: "Bob".into(),
                avatar_id: None,
                photo_url: None,
                finished_at: finished,
            },
            FairPlayRosterSeat {
                game_id: game2,
                user_id: cara,
                player_id: Uuid::new_v4(),
                display_name: "Cara".into(),
                avatar_id: None,
                photo_url: None,
                finished_at: finished,
            },
        ])
        .await
        .unwrap();
    store
        .submit_fair_play(
            game2,
            alice,
            &[
                FairPlayRating {
                    target_user_id: bob,
                    points: 5,
                },
                FairPlayRating {
                    target_user_id: cara,
                    points: 10,
                },
            ],
        )
        .await
        .unwrap();
    // Bob: 9+5=14 over 2 ratings → avg 7. Cara: 7+10=17 over 2 → avg 8.5.
    let board = store.load_fair_play_leaderboard(10).await.unwrap();
    assert_eq!(board[0].user_id, cara);
    assert_eq!(board[0].games_rated, 2);
    assert_eq!(board[1].user_id, bob);
}
