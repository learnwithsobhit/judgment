-- Rooms created for other people: the organizer is not seated.
-- Existing rooms stay host-seated (open_start false).

ALTER TABLE rooms
    ADD COLUMN IF NOT EXISTS open_start BOOLEAN NOT NULL DEFAULT false;
