use chrono::{TimeZone, Utc};
use judgement_persistence::{stats::PulseFinish, GameStore, MemoryStore, StoredUser};
use uuid::Uuid;

fn user(id: Uuid, name: &str) -> StoredUser {
    let now = Utc::now();
    StoredUser {
        user_id: id,
        display_name: name.into(),
        avatar_id: Some("face_01".into()),
        photo_url: None,
        legal_version: Some("2026-08-03".into()),
        created_at: now,
        updated_at: now,
        last_seen_at: now,
    }
}

fn seat(
    game: Uuid,
    user_id: Uuid,
    at: chrono::DateTime<Utc>,
    rank: i32,
    score: i32,
) -> PulseFinish {
    PulseFinish {
        game_id: game,
        user_id,
        finished_at: at,
        finish_rank: rank,
        exact_bid_rounds: 2,
        rounds_played: 8,
        total_score: score,
        tournament_id: None,
    }
}

#[tokio::test]
async fn empty_memory_store_has_no_latest_game() {
    let store = MemoryStore::new();
    let latest = store.load_latest_game().await.unwrap();
    assert!(latest.is_none(), "empty store should report no latest game");
}

#[tokio::test]
async fn latest_game_picks_the_newest_counted_finish_and_orders_seats() {
    let store = MemoryStore::new();
    let older_game = Uuid::new_v4();
    let newer_game = Uuid::new_v4();
    let ankit = Uuid::new_v4();
    let beena = Uuid::new_v4();
    let cara = Uuid::new_v4();
    store.upsert_user(&user(ankit, "Ankit")).await.unwrap();
    store.upsert_user(&user(beena, "Beena")).await.unwrap();
    store.upsert_user(&user(cara, "Cara")).await.unwrap();

    let older = Utc.with_ymd_and_hms(2026, 10, 20, 12, 0, 0).unwrap();
    let newer = Utc.with_ymd_and_hms(2026, 10, 30, 15, 0, 0).unwrap();
    store.seed_counted_finishes(vec![
        seat(older_game, cara, older, 1, 90),
        seat(newer_game, ankit, newer, 2, 128),
        seat(newer_game, beena, newer, 1, 142),
    ]);

    let latest = store
        .load_latest_game()
        .await
        .unwrap()
        .expect("latest game");
    assert_eq!(latest.game_id, newer_game);
    assert_eq!(latest.finished_at, newer);
    assert_eq!(latest.rounds_played, 8);
    assert_eq!(latest.seats.len(), 2);
    assert_eq!(latest.seats[0].display_name, "Beena");
    assert_eq!(latest.seats[0].finish_rank, 1);
    assert_eq!(latest.seats[0].total_score, 142);
    assert_eq!(latest.seats[1].display_name, "Ankit");
    assert_eq!(latest.seats[1].finish_rank, 2);
}
