//! Scheduled game events (ADR 0005) — FCFS seats + waitlist.

use std::net::SocketAddr;
use std::sync::Arc;

use chrono::{Duration, Utc};
use judgement_persistence::MemoryStore;
use judgement_protocol::{
    CancelRsvpResponse, CreateGameEventResponse, CreateGuestSessionResponse, CreateRsvpResponse,
    GameEventManageView, GameEventPublicView, OpenLobbyResponse,
};
use judgement_server::{build_router, state::AppState};

async fn spawn_server() -> SocketAddr {
    let state = Arc::new(AppState::new(Arc::new(MemoryStore::new())));
    let router = build_router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    addr
}

async fn guest(http: &reqwest::Client, base: &str, nick: &str) -> CreateGuestSessionResponse {
    http.post(format!("{base}/api/v1/guest-sessions"))
        .json(&serde_json::json!({ "nickname": nick }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap()
}

async fn create_event(
    http: &reqwest::Client,
    base: &str,
    token: &str,
) -> CreateGameEventResponse {
    let starts = Utc::now() + Duration::hours(2);
    http.post(format!("{base}/api/v1/events"))
        .bearer_auth(token)
        .json(&serde_json::json!({
            "title": "Friday Judgement",
            "starts_at": starts.to_rfc3339(),
            "timezone": "Asia/Kolkata",
            "duration_minutes": 90,
            "first_trump": "spades"
        }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap()
}

async fn rsvp(
    http: &reqwest::Client,
    base: &str,
    slug: &str,
    name: &str,
    mobile: &str,
) -> reqwest::Response {
    http.post(format!("{base}/api/v1/events/{slug}/rsvps"))
        .json(&serde_json::json!({
            "display_name": name,
            "mobile": mobile,
            "contact_consent": true
        }))
        .send()
        .await
        .unwrap()
}

#[tokio::test]
async fn create_without_max_players_uses_seat_cap_eight() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;
    let created = create_event(&http, &base, &host.token).await;
    assert_eq!(created.event.max_players, 8);
    assert_eq!(created.event.seats_left, 8);
    assert_eq!(created.event.waitlist_left, 5);
}

#[tokio::test]
async fn ninth_rsvp_waitlisted_fourteenth_rejected() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;
    let created = create_event(&http, &base, &host.token).await;
    let slug = created.event.slug;

    for i in 0..8 {
        let resp = rsvp(&http, &base, &slug, &format!("P{i}"), &format!("900000000{i}")).await;
        assert!(resp.status().is_success(), "{i}: {}", resp.status());
        let body: CreateRsvpResponse = resp.json().await.unwrap();
        assert_eq!(body.rsvp_status, "going");
    }

    let ninth = rsvp(&http, &base, &slug, "Wait1", "9111111111").await;
    assert!(ninth.status().is_success());
    let ninth_body: CreateRsvpResponse = ninth.json().await.unwrap();
    assert_eq!(ninth_body.rsvp_status, "waitlisted");
    assert_eq!(ninth_body.waitlist_position, Some(1));
    assert_eq!(ninth_body.event.waitlisted_count, 1);
    assert_eq!(ninth_body.event.going_count, 8);

    for i in 0..4 {
        let resp = rsvp(
            &http,
            &base,
            &slug,
            &format!("W{i}"),
            &format!("922222222{i}"),
        )
        .await;
        assert!(resp.status().is_success(), "waitlist {i}");
    }
    assert_eq!(
        rsvp(&http, &base, &slug, "Overflow", "9333333333")
            .await
            .status(),
        reqwest::StatusCode::CONFLICT
    );
}

#[tokio::test]
async fn cancel_going_promotes_oldest_waitlisted() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;
    let created = create_event(&http, &base, &host.token).await;
    let slug = created.event.slug;

    let mut going_tokens = Vec::new();
    for i in 0..8 {
        let body: CreateRsvpResponse = rsvp(&http, &base, &slug, &format!("P{i}"), &format!("900000000{i}"))
            .await
            .json()
            .await
            .unwrap();
        going_tokens.push(body.rsvp_token);
    }
    let wait: CreateRsvpResponse = rsvp(&http, &base, &slug, "WaitA", "9111111111")
        .await
        .json()
        .await
        .unwrap();
    assert_eq!(wait.rsvp_status, "waitlisted");

    let cancelled: CancelRsvpResponse = http
        .post(format!("{base}/api/v1/events/{slug}/rsvps/me"))
        .json(&serde_json::json!({ "rsvp_token": going_tokens[0] }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(cancelled.promoted_name.as_deref(), Some("WaitA"));
    assert_eq!(cancelled.event.going_count, 8);
    assert_eq!(cancelled.event.waitlisted_count, 0);
    assert!(cancelled.event.going_names.contains(&"WaitA".to_string()));
}

#[tokio::test]
async fn open_lobby_requires_three_going_and_sizes_room() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;
    let created = create_event(&http, &base, &host.token).await;
    let slug = created.event.slug;
    let token = &created.manage_token;

    for i in 0..2 {
        rsvp(&http, &base, &slug, &format!("P{i}"), &format!("900000000{i}"))
            .await
            .error_for_status()
            .unwrap();
    }
    let too_few = http
        .post(format!("{base}/api/v1/events/{slug}/open-lobby?token={token}"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap();
    assert_eq!(too_few.status(), reqwest::StatusCode::CONFLICT);

    for i in 2..5 {
        rsvp(&http, &base, &slug, &format!("P{i}"), &format!("900000000{i}"))
            .await
            .error_for_status()
            .unwrap();
    }
    let opened: OpenLobbyResponse = http
        .post(format!("{base}/api/v1/events/{slug}/open-lobby?token={token}"))
        .bearer_auth(&host.token)
        .json(&serde_json::json!({}))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(opened.room.max_players, 5);
    assert_eq!(
        opened.event.status,
        judgement_protocol::GameEventStatus::LobbyOpen
    );
}

#[tokio::test]
async fn public_hides_mobiles_manage_shows_status() {
    let addr = spawn_server().await;
    let base = format!("http://{addr}");
    let http = reqwest::Client::new();
    let host = guest(&http, &base, "Host").await;
    let created = create_event(&http, &base, &host.token).await;
    let slug = created.event.slug;

    rsvp(&http, &base, &slug, "Ada", "9876543210")
        .await
        .error_for_status()
        .unwrap();

    let public: GameEventPublicView = http
        .get(format!("{base}/api/v1/events/{slug}"))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let public_json = serde_json::to_string(&public).unwrap();
    assert!(!public_json.contains("9876543210"));
    assert!(!public_json.contains("+919876543210"));

    let manage: GameEventManageView = http
        .get(format!(
            "{base}/api/v1/events/{slug}/manage?token={}",
            created.manage_token
        ))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    assert_eq!(manage.rsvps.len(), 1);
    assert_eq!(manage.rsvps[0].status, "going");
    assert_eq!(manage.rsvps[0].mobile_e164, "+919876543210");

    let ics = http
        .get(format!("{base}/api/v1/events/{slug}/calendar.ics"))
        .send()
        .await
        .unwrap()
        .text()
        .await
        .unwrap();
    assert!(ics.contains("BEGIN:VEVENT"));
    assert!(ics.contains("BEGIN:VALARM"));
}
