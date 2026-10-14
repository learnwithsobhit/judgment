-- Optional Google accounts. Guest sessions stay valid with user_id NULL.
-- Deleting an account clears the link; it does not delete the guest row.

CREATE TABLE IF NOT EXISTS users (
    user_id            UUID PRIMARY KEY,
    display_name       TEXT NOT NULL,
    avatar_id          TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    legal_accepted_at  TIMESTAMPTZ,
    legal_version      TEXT
);

CREATE TABLE IF NOT EXISTS user_identities (
    user_id     UUID NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    provider    TEXT NOT NULL CHECK (provider IN ('google')),
    subject     TEXT NOT NULL,
    email       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, subject)
);

CREATE INDEX IF NOT EXISTS user_identities_user_id_idx
    ON user_identities (user_id);

ALTER TABLE guest_sessions
    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users (user_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS guest_sessions_user_id_idx
    ON guest_sessions (user_id)
    WHERE user_id IS NOT NULL;
