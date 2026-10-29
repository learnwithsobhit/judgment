-- Whether Join room may show this table. Existing rooms stay listed.
-- A guest-only table is still hidden, because the list requires a signed-in player.

ALTER TABLE rooms
    ADD COLUMN IF NOT EXISTS listed BOOLEAN NOT NULL DEFAULT true;
