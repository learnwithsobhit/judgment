-- Scheduled meetups (ADR 0005). Named `scheduled_events` so we do not collide
-- with the engine `game_events` append-only history table.

CREATE TABLE scheduled_events (
    event_id                UUID PRIMARY KEY,
    slug                    TEXT NOT NULL UNIQUE,
    manage_token_hash       TEXT NOT NULL,
    host_nickname           TEXT NOT NULL,
    host_session_id         UUID REFERENCES guest_sessions (session_id),
    title                   TEXT NOT NULL,
    starts_at               TIMESTAMPTZ NOT NULL,
    timezone                TEXT NOT NULL,
    duration_minutes        SMALLINT NOT NULL CHECK (duration_minutes BETWEEN 30 AND 240),
    max_players             SMALLINT NOT NULL CHECK (max_players BETWEEN 3 AND 8),
    turn_timeout_seconds    SMALLINT,
    first_trump             TEXT,
    round_schedule          JSONB NOT NULL DEFAULT '{"mode":"automatic"}'::jsonb,
    status                  TEXT NOT NULL CHECK (status IN (
        'open', 'lobby_open', 'started', 'cancelled', 'expired'
    )),
    room_id                 UUID REFERENCES rooms (room_id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE scheduled_event_rsvps (
    rsvp_id             UUID PRIMARY KEY,
    event_id            UUID NOT NULL REFERENCES scheduled_events (event_id) ON DELETE CASCADE,
    display_name        TEXT NOT NULL,
    mobile_e164         TEXT NOT NULL,
    status              TEXT NOT NULL CHECK (status IN ('going', 'waitlisted', 'cancelled')),
    manage_token_hash   TEXT NOT NULL,
    contact_consent     BOOLEAN NOT NULL DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX scheduled_event_rsvps_active_mobile
    ON scheduled_event_rsvps (event_id, mobile_e164)
    WHERE status IN ('going', 'waitlisted');
