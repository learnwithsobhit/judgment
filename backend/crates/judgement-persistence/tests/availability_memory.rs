use chrono::{Duration, Utc};
use judgement_persistence::{GameStore, MemoryStore, StoredUser};
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

#[tokio::test]
async fn set_list_expire_and_clear_availability() {
    let store = MemoryStore::new();
    let ada = Uuid::new_v4();
    let grace = Uuid::new_v4();
    store.upsert_user(&user(ada, "Ada")).await.unwrap();
    store.upsert_user(&user(grace, "Grace")).await.unwrap();

    let now = Utc::now();
    store
        .set_availability(ada, now + Duration::minutes(90))
        .await
        .unwrap();
    store
        .set_availability(grace, now + Duration::minutes(90))
        .await
        .unwrap();

    let listed = store.list_available(now).await.unwrap();
    assert_eq!(listed.len(), 2);
    assert_eq!(listed[0].display_name, "Ada");
    assert_eq!(listed[1].display_name, "Grace");
    assert!(listed
        .iter()
        .all(|p| p.avatar_id.as_deref() == Some("face_01")));

    store.clear_availability(ada).await.unwrap();
    let after_clear = store.list_available(now).await.unwrap();
    assert_eq!(after_clear.len(), 1);
    assert_eq!(after_clear[0].display_name, "Grace");

    let expired = store
        .list_available(now + Duration::minutes(91))
        .await
        .unwrap();
    assert!(expired.is_empty());
}
