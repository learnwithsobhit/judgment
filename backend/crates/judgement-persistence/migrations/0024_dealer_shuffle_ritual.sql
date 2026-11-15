-- Optional dealer-visible shuffle before each deal (default off).
ALTER TABLE rooms
    ADD COLUMN IF NOT EXISTS dealer_shuffle_ritual BOOLEAN NOT NULL DEFAULT FALSE;
