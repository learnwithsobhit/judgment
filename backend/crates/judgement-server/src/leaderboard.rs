//! Background Top 10 snapshot. Landing reads the copy and does not query Postgres.

use std::sync::Arc;
use std::time::Duration;

use crate::state::AppState;

pub const REFRESH_INTERVAL: Duration = Duration::from_secs(45);

pub fn spawn_leaderboard_refresh(state: Arc<AppState>) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(REFRESH_INTERVAL);
        loop {
            ticker.tick().await;
            refresh_leaderboard(&state).await;
        }
    });
}

pub async fn refresh_leaderboard(state: &AppState) {
    match state.store.load_leaderboard(10).await {
        Ok(rows) => {
            *state.leaderboard.lock().unwrap() = Arc::new(rows);
        }
        Err(error) => tracing::warn!(%error, "leaderboard refresh failed"),
    }
}
