# ADR 0005 — Scheduled game events (invite link + calendar reminders)

**Status:** Accepted (2026-07-31)
**Amends:** Product surface beyond live lobbies; does not change deal rules.

## Context

Hosts want to arrange a Judgement meetup for a future date, share an invite
(typically via WhatsApp), collect interest, and give invitees a calendar
reminder. Live `Room` lobbies expire after one hour and cannot hold a
Friday-night RSVP list.

Existing `round_schedule` means **deal pattern** (automatic vs manual card
counts), not calendar scheduling.

## Decision

1. Introduce a durable **`GameEvent`** entity separate from `Room`.
2. **Guest-first identity:** the creator gets an opaque **manage token** (no
   accounts). Invitees RSVP with **display name + mobile** (E.164).
3. **No host-chosen player count** on the event. Capacity is fixed:
   - First **8** RSVPs are `going` (FCFS by registration time).
   - Next **5** are `waitlisted`.
   - Further RSVPs are rejected.
4. Cancelling a `going` RSVP **promotes** the oldest waitlisted entry to
   `going`.
5. **Open lobby** creates a room with
   `max_players = going_count` (clamped to 3–8). Requires ≥ 3 going.
   Waitlisted guests do not join unless promoted first.
6. **v1 reminders:** public invite URL + downloadable **`.ics`** with
   `VALARM`. No WhatsApp Business, SMS, or email provider.
7. Store mobiles for the host manage view and future messaging; v1 does not
   send messages.

## Consequences

- New persistence tables / store APIs for events and RSVPs (`going` /
  `waitlisted` / `cancelled`).
- Flutter Schedule / Invite / Manage flows and web deep links `/e/{slug}`.
- SMS/WhatsApp delivery can later reuse RSVP rows without redesigning the
  invite model.
