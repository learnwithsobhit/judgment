-- Signed-in players who are free to play right now. One row per account.

CREATE TABLE IF NOT EXISTS player_availability (
    user_id          UUID PRIMARY KEY REFERENCES users (user_id) ON DELETE CASCADE,
    available_until  TIMESTAMPTZ NOT NULL,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS player_availability_until_idx
    ON player_availability (available_until);
