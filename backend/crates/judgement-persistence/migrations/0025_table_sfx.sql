-- Optional shuffle/card-play SFX for the table (default off).
ALTER TABLE rooms
    ADD COLUMN IF NOT EXISTS table_sfx BOOLEAN NOT NULL DEFAULT FALSE;
