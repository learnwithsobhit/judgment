-- Phase 5 schema (PLAN.md §14). Guest-first MVP: no `users` table yet.

CREATE TABLE guest_sessions (
    session_id  UUID PRIMARY KEY,
    nickname    TEXT NOT NULL,
    token       TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rooms (
    room_id                 UUID PRIMARY KEY,
    code                    TEXT NOT NULL UNIQUE,
    host_session_id         UUID NOT NULL REFERENCES guest_sessions (session_id),
    max_players             SMALLINT NOT NULL CHECK (max_players BETWEEN 3 AND 8),
    turn_timeout_seconds    SMALLINT,
    first_trump             TEXT,
    phase                   TEXT NOT NULL CHECK (phase IN ('lobby', 'in_game')),
    game_id                 UUID,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE room_players (
    room_id     UUID NOT NULL REFERENCES rooms (room_id) ON DELETE CASCADE,
    session_id  UUID NOT NULL REFERENCES guest_sessions (session_id),
    player_id   UUID NOT NULL,
    nickname    TEXT NOT NULL,
    seat        SMALLINT NOT NULL,
    ready       BOOLEAN NOT NULL DEFAULT false,
    joined_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (room_id, session_id),
    UNIQUE (room_id, seat),
    UNIQUE (room_id, player_id)
);

CREATE TABLE games (
    game_id         UUID PRIMARY KEY,
    room_id         UUID NOT NULL REFERENCES rooms (room_id),
    -- Fully-resolved GameRules snapshot for this game (PLAN.md §9.2).
    rules           JSONB NOT NULL,
    seed            BIGINT,
    status          TEXT NOT NULL CHECK (status IN ('active', 'finished')),
    state_version   BIGINT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ
);

CREATE TABLE game_players (
    game_id     UUID NOT NULL REFERENCES games (game_id) ON DELETE CASCADE,
    player_id   UUID NOT NULL,
    session_id  UUID NOT NULL REFERENCES guest_sessions (session_id),
    nickname    TEXT NOT NULL,
    seat        SMALLINT NOT NULL,
    PRIMARY KEY (game_id, player_id),
    UNIQUE (game_id, session_id),
    UNIQUE (game_id, seat)
);

-- Domain events produced by one accepted command share the same
-- (game_id, state_version) and differ by event_index. action_id is required
-- for client/timeout commands so the dedup registry rebuilds on restart.
CREATE TABLE game_events (
    game_id         UUID NOT NULL REFERENCES games (game_id) ON DELETE CASCADE,
    state_version   BIGINT NOT NULL,
    event_index     SMALLINT NOT NULL,
    action_id       UUID,
    payload         JSONB NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (game_id, state_version, event_index)
);

CREATE UNIQUE INDEX game_events_action_uniq
    ON game_events (game_id, action_id)
    WHERE action_id IS NOT NULL AND event_index = 0;

CREATE TABLE game_snapshots (
    game_id         UUID NOT NULL REFERENCES games (game_id) ON DELETE CASCADE,
    state_version   BIGINT NOT NULL,
    state           JSONB NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (game_id, state_version)
);

CREATE TABLE round_results (
    game_id         UUID NOT NULL REFERENCES games (game_id) ON DELETE CASCADE,
    round_index     INT NOT NULL,
    scores          JSONB NOT NULL,
    PRIMARY KEY (game_id, round_index)
);

CREATE TABLE game_results (
    game_id         UUID PRIMARY KEY REFERENCES games (game_id) ON DELETE CASCADE,
    ranking         JSONB NOT NULL,
    finished_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX games_status_idx ON games (status);
CREATE INDEX game_snapshots_latest_idx ON game_snapshots (game_id, state_version DESC);
