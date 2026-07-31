# ADR 0004 — Phase 6 presence, grace, and bot takeover

**Status:** Accepted (2026-07-30)
**Amends:** PLAN.md §15 disconnect policy details.

## Decisions

1. **Whole-table pause** while any seat is inside the reconnect grace window
   (`GameRules.reconnect_grace_seconds`, default 60). Turn deadlines are
   cancelled for the pause duration.
2. **Grace expiry ⇒ bot takeover** even when the room has no turn timer
   (ADR 0003 optional timer is independent of disconnect bots).
3. **`LeaveGame` ⇒ immediate permanent bot takeover** (skips grace).
4. **Safe restore boundary** = actor idle between messages; reconnect always
   restores human control immediately.
5. **Takeover bot** = `RuleBasedBot` (lowest legal bid/card) — engine-validated.
6. **Token rotation** on every successful game WebSocket upgrade; prior bearer
   invalidated; new token pushed as `TokenRotated` and persisted.
7. **Host migration** on host WS disconnect / leave: prefer a Connected human,
   else any remaining seat; emit `HostChanged`.
8. **Abandonment GC**: lobby rooms idle ≥ 1 hour are deleted; game actors whose
   command channel has closed are dropped from the in-memory registry.
