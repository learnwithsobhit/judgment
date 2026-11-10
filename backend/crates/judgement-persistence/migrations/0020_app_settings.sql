-- Site-wide settings (festival skin, later banners). Single-row keys.

CREATE TABLE IF NOT EXISTS app_settings (
    key         TEXT PRIMARY KEY,
    value       JSONB NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO app_settings (key, value)
VALUES ('festival', '{"id":"off"}'::jsonb)
ON CONFLICT (key) DO NOTHING;
