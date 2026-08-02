# ADR 0004 — Phase 6 presence, grace, vacant seat, and end-game

**Status:** Amended (2026-08-02)  
**Amends:** PLAN.md §15 disconnect policy details.  
**Supersedes:** live bot takeover after grace/leave.

## Decisions

1. **Whole-table pause** while any seat is inside the reconnect grace window
   **or** marked `Vacant`. Default `GameRules.reconnect_grace_seconds` is
   **0** (immediate vacant on WS drop). Non-zero grace remains supported.
2. **Grace expiry / zero-grace disconnect ⇒ seat Vacant** (not bot). Table
   stays paused. Emit `SeatVacant { player_id, room_code }` so peers can
   invite a replacement (or the same player can reclaim).
3. **`LeaveGame` ⇒ immediate Vacant** (skips grace).
4. **Claim via room code:** `POST /api/v1/rooms/{code}/claim` (also used by
   `join` when the room is already in-game). Binds a new session to the same
   `player_id` / seat / hand / scores; nickname/avatar update; resume when no
   vacancies remain.
5. **End game:** host may `EndGame` (WS) or `POST .../end` while paused for
   vacancy. Vacancy older than **10 minutes** auto-ends the game (`aborted`).
6. **No live `RuleBasedBot` playout** for disconnects. Bots remain for offline
   simulation/tests only. Optional turn-timer auto-move for a *connected*
   slow human is separate.
7. **Safe restore boundary** = actor idle between messages; reconnect during
   a non-zero grace restores control. After Vacant, the seat is claimed via
   room code (original or replacement player).
8. **Token rotation** on every successful game WebSocket upgrade.
9. **Host migration** on host WS disconnect / leave: prefer a Connected human.
10. **Abandonment GC:** lobby TTL 1h; finished/aborted games purged after 24h;
    orphan in-game rooms and guest sessions cleaned by the reaper.

## Consequences

- Stops bot→DB write storms that froze tables under Postgres resource pressure.
- Games may pause until a human claims or the host ends — product-correct for
  invite-only tables.
