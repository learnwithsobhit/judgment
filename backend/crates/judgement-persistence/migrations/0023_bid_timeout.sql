-- Independent optional bidding timer (ADR 0003 amend).
-- Absent/legacy clients mirrored turn_timeout; explicit null means bid timer off.

ALTER TABLE rooms
    ADD COLUMN IF NOT EXISTS bid_timeout_seconds SMALLINT;

ALTER TABLE scheduled_events
    ADD COLUMN IF NOT EXISTS bid_timeout_seconds SMALLINT;

-- Preserve pre-feature behavior: turn timer also timed bids.
UPDATE rooms
SET bid_timeout_seconds = turn_timeout_seconds
WHERE turn_timeout_seconds IS NOT NULL
  AND bid_timeout_seconds IS NULL;

UPDATE scheduled_events
SET bid_timeout_seconds = turn_timeout_seconds
WHERE turn_timeout_seconds IS NOT NULL
  AND bid_timeout_seconds IS NULL;
