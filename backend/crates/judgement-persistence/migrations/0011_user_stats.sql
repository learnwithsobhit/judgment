-- Lifetime stats survive delete_game: game_id has no foreign key.
-- Ranked columns feed the public Top 10. Lifetime columns feed the profile.

ALTER TABLE game_players
    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users (user_id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS user_game_results (
    game_id           UUID NOT NULL,
    user_id           UUID NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    finished_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    table_size        SMALLINT NOT NULL,
    rounds_played     SMALLINT NOT NULL,
    finish_rank       SMALLINT NOT NULL,
    total_score       INT NOT NULL,
    exact_bid_rounds  SMALLINT NOT NULL,
    tricks_missed     INT NOT NULL,
    counted           BOOLEAN NOT NULL,
    PRIMARY KEY (game_id, user_id)
);

CREATE INDEX IF NOT EXISTS user_game_results_user_idx
    ON user_game_results (user_id, finished_at DESC);

CREATE TABLE IF NOT EXISTS user_stats (
    user_id            UUID PRIMARY KEY REFERENCES users (user_id) ON DELETE CASCADE,
    games_played       INT NOT NULL DEFAULT 0,
    wins               INT NOT NULL DEFAULT 0,
    ranked_wins        INT NOT NULL DEFAULT 0,
    ranked_games       INT NOT NULL DEFAULT 0,
    lifetime_points    BIGINT NOT NULL DEFAULT 0,
    ranked_points      BIGINT NOT NULL DEFAULT 0,
    rounds_played      INT NOT NULL DEFAULT 0,
    exact_bid_rounds   INT NOT NULL DEFAULT 0,
    ranked_rounds      INT NOT NULL DEFAULT 0,
    ranked_exact       INT NOT NULL DEFAULT 0,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_stats_ladder_idx
    ON user_stats (ranked_wins DESC, ranked_games DESC);
