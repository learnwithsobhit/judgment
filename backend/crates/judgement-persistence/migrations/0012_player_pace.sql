-- Thinking time per seat, restored with the game so every client
-- still agrees on the fastest and slowest player after a restart.

ALTER TABLE games
    ADD COLUMN IF NOT EXISTS player_pace JSONB NOT NULL DEFAULT '[]'::jsonb;
