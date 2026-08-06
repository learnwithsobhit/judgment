use axum::body::Body;
use axum::http::{Request, StatusCode};
use dehla_server::{build_router, AppState};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tower::ServiceExt;

async fn json_request(
    app: axum::Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        builder = builder.header("Authorization", format!("Bearer {t}"));
    }
    if body.is_some() {
        builder = builder.header("Content-Type", "application/json");
    }
    let req = builder
        .body(Body::from(
            body.map(|b| b.to_string()).unwrap_or_default(),
        ))
        .unwrap();
    let res = app.oneshot(req).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let val: Value = if bytes.is_empty() {
        json!({})
    } else {
        serde_json::from_slice(&bytes).unwrap_or(json!({}))
    };
    (status, val)
}

#[tokio::test]
async fn four_players_random_partners_and_start() {
    let state = AppState::memory();
    let app = build_router(state);

    let mut tokens = Vec::new();
    for i in 0..4 {
        let (st, body) = json_request(
            app.clone(),
            "POST",
            "/api/v1/guest-sessions",
            None,
            Some(json!({ "nickname": format!("P{i}") })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        tokens.push(body["token"].as_str().unwrap().to_string());
    }

    let (st, created) = json_request(
        app.clone(),
        "POST",
        "/api/v1/rooms",
        Some(&tokens[0]),
        Some(json!({
            "trump_method": "announced_trump",
            "partnership_mode": "random_opposite",
            "kots_to_win": 1
        })),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let code = created["room"]["code"].as_str().unwrap().to_string();

    for t in tokens.iter().skip(1) {
        let (st, _) = json_request(
            app.clone(),
            "POST",
            &format!("/api/v1/rooms/{code}/join"),
            Some(t),
            Some(json!({})),
        )
        .await;
        assert_eq!(st, StatusCode::OK, "join failed");
    }

    let (st, room) = json_request(
        app.clone(),
        "GET",
        &format!("/api/v1/rooms/{code}"),
        None,
        None,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(room["phase"], "partnership");
    assert_eq!(room["seats"].as_array().unwrap().len(), 4);
    assert!(room["seats"][0]["team"].is_string());

    for t in &tokens {
        let (st, _) = json_request(
            app.clone(),
            "POST",
            &format!("/api/v1/rooms/{code}/ready"),
            Some(t),
            Some(json!({ "ready": true })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
    }

    let (st, started) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/start"),
        Some(&tokens[0]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "{started}");
    assert!(started["game_id"].is_string());
}

#[tokio::test]
async fn leave_lobby_removes_seat_and_transfers_host() {
    let state = AppState::memory();
    let app = build_router(state);

    let mut tokens = Vec::new();
    for i in 0..2 {
        let (st, body) = json_request(
            app.clone(),
            "POST",
            "/api/v1/guest-sessions",
            None,
            Some(json!({ "nickname": format!("P{i}") })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        tokens.push(body["token"].as_str().unwrap().to_string());
    }

    let (st, created) = json_request(
        app.clone(),
        "POST",
        "/api/v1/rooms",
        Some(&tokens[0]),
        Some(json!({ "kots_to_win": 1 })),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let code = created["room"]["code"].as_str().unwrap().to_string();

    let (st, _) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/join"),
        Some(&tokens[1]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // Host leaves → room remains with P1 as host.
    let (st, left) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/leave"),
        Some(&tokens[0]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "{left}");
    assert_eq!(left["seats"].as_array().unwrap().len(), 1);
    assert_eq!(left["seats"][0]["nickname"], "P1");
    assert_eq!(left["seats"][0]["is_host"], true);
}

#[tokio::test]
async fn leave_in_game_then_claim_vacant_seat() {
    let state = AppState::memory();
    let app = build_router(state);

    let mut tokens = Vec::new();
    let mut player_ids = Vec::new();
    for i in 0..4 {
        let (st, body) = json_request(
            app.clone(),
            "POST",
            "/api/v1/guest-sessions",
            None,
            Some(json!({ "nickname": format!("P{i}") })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        tokens.push(body["token"].as_str().unwrap().to_string());
    }

    let (st, created) = json_request(
        app.clone(),
        "POST",
        "/api/v1/rooms",
        Some(&tokens[0]),
        Some(json!({
            "trump_method": "announced_trump",
            "partnership_mode": "random_opposite",
            "kots_to_win": 1
        })),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let code = created["room"]["code"].as_str().unwrap().to_string();
    player_ids.push(created["player_id"].as_str().unwrap().to_string());

    for t in tokens.iter().skip(1) {
        let (st, joined) = json_request(
            app.clone(),
            "POST",
            &format!("/api/v1/rooms/{code}/join"),
            Some(t),
            Some(json!({})),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        player_ids.push(joined["player_id"].as_str().unwrap().to_string());
    }

    for t in &tokens {
        let (st, _) = json_request(
            app.clone(),
            "POST",
            &format!("/api/v1/rooms/{code}/ready"),
            Some(t),
            Some(json!({ "ready": true })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
    }

    let (st, started) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/start"),
        Some(&tokens[0]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "{started}");
    let game_id = started["game_id"].as_str().unwrap().to_string();
    let vacant_player = player_ids[3].clone();

    // P3 leaves mid-game → seat vacant (immediate).
    let (st, _) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/leave"),
        Some(&tokens[3]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // Replacement claims preferred vacant seat.
    let (st, replacer) = json_request(
        app.clone(),
        "POST",
        "/api/v1/guest-sessions",
        None,
        Some(json!({ "nickname": "Replacer" })),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let replacer_token = replacer["token"].as_str().unwrap().to_string();

    let (st, claimed) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/claim"),
        Some(&replacer_token),
        Some(json!({ "player_id": vacant_player })),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "{claimed}");
    assert_eq!(claimed["player_id"], vacant_player);
    assert_eq!(claimed["game_id"], game_id);
    assert_eq!(claimed["room"]["seats"].as_array().unwrap().len(), 4);
    let claimed_seat = claimed["room"]["seats"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["player_id"] == vacant_player)
        .unwrap();
    assert_eq!(claimed_seat["nickname"], "Replacer");
}

#[tokio::test]
async fn host_restart_after_leave_returns_to_lobby() {
    let state = AppState::memory();
    let app = build_router(state);

    let mut tokens = Vec::new();
    for i in 0..4 {
        let (st, body) = json_request(
            app.clone(),
            "POST",
            "/api/v1/guest-sessions",
            None,
            Some(json!({ "nickname": format!("P{i}") })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        tokens.push(body["token"].as_str().unwrap().to_string());
    }

    let (st, created) = json_request(
        app.clone(),
        "POST",
        "/api/v1/rooms",
        Some(&tokens[0]),
        Some(json!({
            "trump_method": "announced_trump",
            "partnership_mode": "random_opposite",
            "kots_to_win": 1
        })),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let code = created["room"]["code"].as_str().unwrap().to_string();

    for t in tokens.iter().skip(1) {
        let (st, _) = json_request(
            app.clone(),
            "POST",
            &format!("/api/v1/rooms/{code}/join"),
            Some(t),
            Some(json!({})),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
    }

    for t in &tokens {
        let (st, _) = json_request(
            app.clone(),
            "POST",
            &format!("/api/v1/rooms/{code}/ready"),
            Some(t),
            Some(json!({ "ready": true })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
    }

    let (st, started) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/start"),
        Some(&tokens[0]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "{started}");

    let (st, _) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/leave"),
        Some(&tokens[3]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // Non-host cannot restart.
    let (st, denied) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/restart"),
        Some(&tokens[1]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::FORBIDDEN, "{denied}");

    let (st, restarted) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/restart"),
        Some(&tokens[0]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "{restarted}");
    assert_eq!(restarted["returned_to_lobby"], true);
    assert!(restarted["game_id"].is_null());

    let (st, room) = json_request(
        app.clone(),
        "GET",
        &format!("/api/v1/rooms/{code}"),
        Some(&tokens[0]),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(room["phase"], "lobby");
    assert_eq!(room["seats"].as_array().unwrap().len(), 3);

    // Host can end while in-game with a vacancy.
    // Re-fill and start again briefly to exercise /end.
    let (st, p3) = json_request(
        app.clone(),
        "POST",
        "/api/v1/guest-sessions",
        None,
        Some(json!({ "nickname": "P3b" })),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let t3 = p3["token"].as_str().unwrap().to_string();
    let (st, _) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/join"),
        Some(&t3),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // Random partners again when full.
    let (st, _) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/partnership"),
        Some(&tokens[0]),
        Some(json!({ "mode": "random_opposite" })),
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    for t in [&tokens[0], &tokens[1], &tokens[2], &t3] {
        let (st, _) = json_request(
            app.clone(),
            "POST",
            &format!("/api/v1/rooms/{code}/ready"),
            Some(t),
            Some(json!({ "ready": true })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
    }
    let (st, _) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/start"),
        Some(&tokens[0]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    let (st, _) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/leave"),
        Some(&t3),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    let (st, ended) = json_request(
        app.clone(),
        "POST",
        &format!("/api/v1/rooms/{code}/end"),
        Some(&tokens[0]),
        Some(json!({})),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "{ended}");
    assert_eq!(ended["aborted"], true);

    let (st, room) = json_request(
        app.clone(),
        "GET",
        &format!("/api/v1/rooms/{code}"),
        Some(&tokens[0]),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(room["phase"], "lobby");
    assert_eq!(room["seats"].as_array().unwrap().len(), 3);
}

#[tokio::test]
async fn metrics_exposes_gauges() {
    let state = AppState::memory();
    let app = build_router(state);
    let req = Request::builder()
        .method("GET")
        .uri("/metrics")
        .body(Body::empty())
        .unwrap();
    let res = app.oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let text = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(text.contains("dehla_tables"));
    assert!(text.contains("dehla_ws_connections"));
    assert!(text.contains("dehla_tips_saved"));
}
