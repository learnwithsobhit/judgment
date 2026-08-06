-- Host-defined trump suit cycle (permutation of four suits).
ALTER TABLE rooms
    ADD COLUMN IF NOT EXISTS trump_cycle JSONB;

ALTER TABLE scheduled_events
    ADD COLUMN IF NOT EXISTS trump_cycle JSONB;
