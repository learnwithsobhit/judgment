-- Profile photos from Google / Telegram. Never stored in avatar_id.

ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE guest_sessions ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE room_players ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE fair_play_rosters ADD COLUMN IF NOT EXISTS photo_url TEXT;
