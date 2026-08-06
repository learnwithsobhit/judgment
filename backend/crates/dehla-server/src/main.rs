use std::path::PathBuf;
use std::sync::Arc;

use dehla_persistence::{GameStore, MemoryStore, PostgresStore};
use dehla_server::{build_router, AppState};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8081);

    let state = match std::env::var("DATABASE_URL") {
        Ok(url) => {
            let store = PostgresStore::connect(&url)
                .await
                .expect("failed to connect to DATABASE_URL");
            store
                .migrate(migrations_dir())
                .await
                .expect("failed to run migrations");
            tracing::info!("using PostgreSQL tip store");
            let store: Arc<dyn GameStore> = Arc::new(store);
            AppState::new(store)
        }
        Err(_) => {
            tracing::warn!("DATABASE_URL unset — using in-memory tip store");
            AppState::new(Arc::new(MemoryStore::new()))
        }
    };

    let router = build_router(state);
    let listener = tokio::net::TcpListener::bind(("0.0.0.0", port))
        .await
        .expect("failed to bind port");
    tracing::info!(port, "dehla server listening");
    axum::serve(listener, router).await.expect("server error");
}

fn migrations_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("DEHLA_MIGRATIONS_DIR") {
        return PathBuf::from(dir);
    }
    let candidates = [
        PathBuf::from("crates/dehla-persistence/migrations"),
        PathBuf::from("backend/crates/dehla-persistence/migrations"),
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../dehla-persistence/migrations"),
    ];
    candidates
        .into_iter()
        .find(|p| p.exists())
        .expect("could not locate dehla-persistence/migrations")
}
