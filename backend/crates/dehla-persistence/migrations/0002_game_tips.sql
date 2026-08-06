-- Latest tip snapshot per active game (CP restore boundary).

CREATE TABLE IF NOT EXISTS game_tips (
    game_id UUID PRIMARY KEY,
    tip JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
