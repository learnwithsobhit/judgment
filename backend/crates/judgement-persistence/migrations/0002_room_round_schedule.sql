-- Host-configurable round schedule (automatic descending vs manual steps).
ALTER TABLE rooms
    ADD COLUMN round_schedule JSONB NOT NULL DEFAULT '{"mode":"automatic"}'::jsonb;
