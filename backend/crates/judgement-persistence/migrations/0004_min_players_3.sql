-- Allow 3–8 player tables (was 4–8).

ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_max_players_check;
ALTER TABLE rooms
    ADD CONSTRAINT rooms_max_players_check
    CHECK (max_players BETWEEN 3 AND 8);

ALTER TABLE scheduled_events DROP CONSTRAINT IF EXISTS scheduled_events_max_players_check;
ALTER TABLE scheduled_events
    ADD CONSTRAINT scheduled_events_max_players_check
    CHECK (max_players BETWEEN 3 AND 8);
