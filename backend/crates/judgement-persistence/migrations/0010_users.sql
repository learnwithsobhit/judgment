-- User accounts (Google / Apple) layered on guest_sessions.
-- Avatar uploads store a public HTTPS URL (AWS S3 / CloudFront).

CREATE TABLE users (
    user_id              UUID PRIMARY KEY,
    display_name         TEXT NOT NULL,
    avatar_kind          TEXT NOT NULL DEFAULT 'pack'
                         CHECK (avatar_kind IN ('pack', 'upload')),
    avatar_id            TEXT,
    avatar_url           TEXT,
    avatar_storage_key   TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    legal_accepted_at    TIMESTAMPTZ,
    legal_version        TEXT
);

CREATE TABLE user_identities (
    user_id     UUID NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    provider    TEXT NOT NULL CHECK (provider IN ('google', 'apple')),
    subject     TEXT NOT NULL,
    email       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, subject)
);

CREATE INDEX user_identities_user_id_idx ON user_identities (user_id);

ALTER TABLE guest_sessions
    ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users (user_id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS avatar_url TEXT;

CREATE INDEX IF NOT EXISTS guest_sessions_user_id_idx
    ON guest_sessions (user_id)
    WHERE user_id IS NOT NULL;
