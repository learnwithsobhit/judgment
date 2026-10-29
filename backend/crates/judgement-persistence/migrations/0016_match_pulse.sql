-- Serves the background count of ranked games. The per-player index does not.
CREATE INDEX IF NOT EXISTS user_game_results_counted_finished_idx
    ON user_game_results (finished_at)
    WHERE counted;
