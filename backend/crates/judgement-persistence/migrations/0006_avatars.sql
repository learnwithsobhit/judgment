-- Cosmetic avatar pack ids on sessions and lobby seats.

ALTER TABLE guest_sessions
    ADD COLUMN IF NOT EXISTS avatar_id TEXT;

ALTER TABLE room_players
    ADD COLUMN IF NOT EXISTS avatar_id TEXT;
