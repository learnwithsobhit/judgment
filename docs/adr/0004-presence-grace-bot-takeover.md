# ADR 0004 — Phase 6 presence, grace, vacant seat, end, and restart

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
4. **Rejoin / claim:** Same session may reclaim a vacant seat by reconnecting
   the game WebSocket. A **new** session uses `POST /api/v1/rooms/{code}/claim`
   (also used by `join` when in-game). Same `player_id` / seat / hand / scores;
   nickname/avatar update; resume when no vacancies remain.
5. **End game:** host may `EndGame` (WS) or `POST .../end`. Vacancy older than
   **10 minutes** auto-ends (`aborted`). Abort removes the actor from
   `state.games`, **hard-deletes** the game row (tip + events), and returns
   the room to **Lobby** (vacant seats dropped). Natural finish does the same
   delete + Lobby return; clients keep standings from the final WS snapshot.
6. **Restart (rematch):** host may `POST .../restart` while vacant if at least
   **3** players remain. Atomic path: abort + drop vacant seats → Lobby →
   auto-ready → new `game_id`. Broadcast `GameRestarted { game_id }`. Rate
   limited (30s per room). Metric `judgement_games_restarted_total` (not
   vacancy-end).
7. **No live `RuleBasedBot` playout** for disconnects. Bots remain for offline
   simulation/tests only. Optional turn-timer auto-move for a *connected*
   slow human is separate.
8. **Safe restore boundary** = actor idle between messages; reconnect during
   a non-zero grace restores control. After Vacant, same-session WS reclaim or
   claim via room code.
9. **Token rotation** on every successful game WebSocket upgrade.
10. **Host migration** on host WS disconnect / leave: prefer a Connected human;
    also sync `Room.host_session` so the new host can Start/Restart.
11. **Abandonment GC:** lobby TTL 1h; reaper **4h** TTL is a backstop for any
    leftover finished/aborted rows (primary delete is on finish/abort); orphan
    in-game rooms and guest sessions cleaned by the reaper.

## Consequences

- Stops bot→DB write storms that froze tables under Postgres resource pressure.
- Games may pause until a human rejoins, the host restarts (≥3), the host ends,
  or the 10m TTL fires.
- Abort/restart/finish free `MAX_ACTIVE_GAMES` slots immediately; finished tip
  snapshots are not retained for coaching.
