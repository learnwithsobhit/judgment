use std::path::PathBuf;
use std::sync::Arc;

use judgement_persistence::{MemoryStore, PostgresStore};
use judgement_server::rag_boot::build_explanation_service;
use judgement_server::reaper::spawn_reaper;
use judgement_server::restore::restore_from_store;
use judgement_server::{build_router, state::AppState};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);

    let database_url = std::env::var("DATABASE_URL").ok();
    let explanations = build_explanation_service(database_url.as_deref()).await;

    let state = match database_url.as_deref() {
        Some(url) => {
            let store = PostgresStore::connect(url)
                .await
                .expect("failed to connect to DATABASE_URL");
            store
                .migrate(migrations_dir())
                .await
                .expect("failed to run migrations");
            tracing::info!("using PostgreSQL persistence");
            let store: Arc<dyn judgement_persistence::GameStore> = Arc::new(store);
            let state = Arc::new(AppState::with_explanations(store, explanations));
            let restored = restore_from_store(&state)
                .await
                .expect("failed to restore durable state");
            tracing::info!(restored, "restored active games from database");
            state
        }
        None => {
            tracing::warn!("DATABASE_URL unset — using in-memory store (games lost on restart)");
            Arc::new(AppState::with_explanations(
                Arc::new(MemoryStore::new()),
                explanations,
            ))
        }
    };

    spawn_reaper(state.clone());

    let router = build_router(state);
    let listener = tokio::net::TcpListener::bind(("0.0.0.0", port))
        .await
        .expect("failed to bind port");
    tracing::info!(port, "judgement server listening");
    axum::serve(listener, router).await.expect("server error");
}

fn migrations_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("JUDGEMENT_MIGRATIONS_DIR") {
        return PathBuf::from(dir);
    }
    let candidates = [
        PathBuf::from("crates/judgement-persistence/migrations"),
        PathBuf::from("backend/crates/judgement-persistence/migrations"),
        PathBuf::from("/srv/migrations/persistence"),
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../judgement-persistence/migrations"),
    ];
    candidates
        .into_iter()
        .find(|p| p.exists())
        .expect("could not locate judgement-persistence/migrations")
}
