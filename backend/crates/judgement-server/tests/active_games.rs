//! Home card reads the in-memory snapshot and never sees a room code or a hand.

use std::sync::Arc;
use std::time::Duration;

use judgement_persistence::MemoryStore;
use judgement_server::{build_router, state::AppState};
use serde_json::Value;
use tokio::net::TcpListener;

#[tokio::test]
async fn a_started_game_is_public_without_its_code_or_cards() {
    let state = Arc::new(AppState::new(Arc::new(MemoryStore::new())));
    let app = build_router(state);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();

    let mut tokens = Vec::new();
    let mut host_player = None;
    let mut room_code = String::new();
    for (index, name) in ["Deepak", "Ankit", "shobhit"].iter().enumerate() {
        let session: Value = http
            .post(format!("{base}/api/v1/guest-sessions"))
            .json(&serde_json::json!({ "nickname": name }))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap()
            .json()
            .await
            .unwrap();
        let token = session["token"].as_str().unwrap().to_string();
        if index == 0 {
            let created: Value = http
                .post(format!("{base}/api/v1/rooms"))
                .bearer_auth(&token)
                .json(&serde_json::json!({ "max_players": 3 }))
                .send()
                .await
                .unwrap()
                .error_for_status()
                .unwrap()
                .json()
                .await
                .unwrap();
            room_code = created["room"]["code"].as_str().unwrap().to_string();
            host_player = Some(created["player_id"].clone());
        } else {
            http.post(format!("{base}/api/v1/rooms/{room_code}/join"))
                .bearer_auth(&token)
                .json(&serde_json::json!({}))
                .send()
                .await
                .unwrap()
                .error_for_status()
                .unwrap();
        }
        tokens.push(token);
    }

    for token in &tokens {
        http.post(format!("{base}/api/v1/rooms/{room_code}/ready"))
            .bearer_auth(token)
            .json(&serde_json::json!({ "ready": true }))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap();
    }
    http.post(format!("{base}/api/v1/rooms/{room_code}/start"))
        .bearer_auth(&tokens[0])
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .error_for_status()
        .unwrap();

    let mut body = Value::Null;
    for _ in 0..15 {
        body = http
            .get(format!("{base}/api/v1/active-games"))
            .send()
            .await
            .unwrap()
            .error_for_status()
            .unwrap()
            .json()
            .await
            .unwrap();
        if body["games"]
            .as_array()
            .is_some_and(|games| !games.is_empty())
        {
            break;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }

    let games = body["games"].as_array().expect("games");
    assert_eq!(
        games.len(),
        1,
        "started table should be on the card: {body}"
    );
    let game = &games[0];
    let text = serde_json::to_string(game).unwrap();
    assert!(!text.contains("\"code\""), "{text}");
    assert!(!text.contains(&room_code), "{text}");
    assert!(!text.contains("card"), "{text}");
    assert!(!text.contains("\"bid\""), "{text}");
    assert_eq!(game["round_index"], 1);
    assert!(game["total_rounds"].as_i64().unwrap() >= 1);
    assert_eq!(game["phase"], "bidding");
    let names: Vec<_> = game["seats"]
        .as_array()
        .unwrap()
        .iter()
        .map(|seat| seat["display_name"].as_str().unwrap())
        .collect();
    assert_eq!(names, vec!["Ankit", "Deepak", "shobhit"]);
    assert!(game["seats"]
        .as_array()
        .unwrap()
        .iter()
        .all(|seat| seat["total_score"] == 0));
    let _ = host_player;
}
