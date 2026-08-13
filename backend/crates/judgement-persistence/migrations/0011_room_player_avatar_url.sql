-- Lobby seats may carry uploaded avatar URLs (mirrored from guest_sessions / users).

ALTER TABLE room_players
    ADD COLUMN IF NOT EXISTS avatar_url TEXT;
