-- Fair play awards survive delete_game: game_id has no foreign key to games.
-- Ballots are never exposed on public APIs; only aggregates are.

CREATE TABLE IF NOT EXISTS fair_play_rosters (
    game_id       UUID NOT NULL,
    user_id       UUID NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    player_id     UUID NOT NULL,
    display_name  TEXT NOT NULL,
    avatar_id     TEXT,
    finished_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (game_id, user_id)
);

CREATE INDEX IF NOT EXISTS fair_play_rosters_user_idx
    ON fair_play_rosters (user_id, finished_at DESC);

CREATE TABLE IF NOT EXISTS fair_play_submissions (
    game_id         UUID NOT NULL,
    voter_user_id   UUID NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (game_id, voter_user_id)
);

CREATE TABLE IF NOT EXISTS fair_play_ballots (
    game_id          UUID NOT NULL,
    voter_user_id    UUID NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    target_user_id   UUID NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    points           SMALLINT NOT NULL CHECK (points >= 0 AND points <= 10),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (game_id, voter_user_id, target_user_id),
    CHECK (voter_user_id <> target_user_id)
);

CREATE INDEX IF NOT EXISTS fair_play_ballots_target_idx
    ON fair_play_ballots (target_user_id);

CREATE TABLE IF NOT EXISTS fair_play_stats (
    user_id            UUID PRIMARY KEY REFERENCES users (user_id) ON DELETE CASCADE,
    points_received    INT NOT NULL DEFAULT 0,
    ratings_received   INT NOT NULL DEFAULT 0,
    games_rated        INT NOT NULL DEFAULT 0,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS fair_play_stats_board_idx
    ON fair_play_stats (points_received DESC, ratings_received DESC);
