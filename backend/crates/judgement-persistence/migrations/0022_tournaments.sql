-- Competitive points-series tournaments. Results stamp survives delete_game.

CREATE TABLE IF NOT EXISTS tournaments (
    tournament_id   UUID PRIMARY KEY,
    slug            TEXT NOT NULL UNIQUE,
    title           TEXT NOT NULL,
    blurb           TEXT NOT NULL DEFAULT '',
    format          TEXT NOT NULL DEFAULT 'points'
                    CHECK (format IN ('points', 'finals_cut', 'bracket')),
    status          TEXT NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft', 'live', 'closed')),
    starts_at       TIMESTAMPTZ,
    ends_at         TIMESTAMPTZ,
    created_by      UUID REFERENCES users (user_id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS tournaments_status_idx
    ON tournaments (status, updated_at DESC);

ALTER TABLE rooms
    ADD COLUMN IF NOT EXISTS tournament_id UUID REFERENCES tournaments (tournament_id)
        ON DELETE SET NULL;

ALTER TABLE user_game_results
    ADD COLUMN IF NOT EXISTS tournament_id UUID REFERENCES tournaments (tournament_id)
        ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS user_game_results_tournament_idx
    ON user_game_results (tournament_id)
    WHERE tournament_id IS NOT NULL;
