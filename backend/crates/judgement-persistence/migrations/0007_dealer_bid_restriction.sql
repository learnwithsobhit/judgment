-- Optional classic dealer bid restriction (default off).

ALTER TABLE rooms
    ADD COLUMN IF NOT EXISTS dealer_total_restriction BOOLEAN NOT NULL DEFAULT false;
