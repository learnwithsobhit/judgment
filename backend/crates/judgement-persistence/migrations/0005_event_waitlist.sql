-- FCFS seats (8) + waitlist (5): allow waitlisted RSVP status.

ALTER TABLE scheduled_event_rsvps
    DROP CONSTRAINT IF EXISTS scheduled_event_rsvps_status_check;

ALTER TABLE scheduled_event_rsvps
    ADD CONSTRAINT scheduled_event_rsvps_status_check
    CHECK (status IN ('going', 'waitlisted', 'cancelled'));

DROP INDEX IF EXISTS scheduled_event_rsvps_going_mobile;

-- One active RSVP per mobile (going or waitlisted).
CREATE UNIQUE INDEX scheduled_event_rsvps_active_mobile
    ON scheduled_event_rsvps (event_id, mobile_e164)
    WHERE status IN ('going', 'waitlisted');
