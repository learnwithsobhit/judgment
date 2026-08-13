# ADR 0004 — Phase 6 presence, grace, vacant seat, end, and restart

**Status:** Amended (2026-08-13)  
**Amends:** PLAN.md §15 disconnect policy details.  
**Supersedes:** live bot takeover after grace/leave.

## Decisions

1. **Whole-table pause** while any seat is inside the reconnect grace window
   **or** marked `Vacant`. `GameRules.reconnect_grace_seconds` in
   `mvp_for_players` remains **0** for engine tests. Live games override via
   `RECONNECT_GRACE_SECONDS` (default **12**) at start; the value is persisted
   on the game rules so restore keeps the same window.
2. **TCP / proxy blips are not leaves.** On WS drop with non-zero grace: do
   **not** vacant, do **not** migrate host, and do **not** broadcast
   `GamePaused` for the first **3 seconds**. Same-session reconnect restores
   control with snapshots only (no resume flash if no banner was sent).
3. **Grace expiry / zero-grace disconnect ⇒ seat Vacant** (not bot). Host
   migration runs **on grace expiry** (or immediately on intentional
   `LeaveGame` / zero-grace drop), not on the first TCP reset. Table stays
   paused. Emit `SeatVacant { player_id, room_code }` so peers can invite a
   replacement (or the same player can reclaim).
4. **`LeaveGame` ⇒ immediate Vacant** (skips grace). Host migrates immediately.
5. **Rejoin / claim:** Same session may reclaim a vacant seat by reconnecting
   the game WebSocket. A **new** session uses `POST /api/v1/rooms/{code}/claim`
   (also used by `join` when in-game). Same `player_id` / seat / hand / scores;
   nickname/avatar update; resume when no vacancies remain.

   **Reclaim precedence** (client + server): (1) same-session token /
   `already_seated` / WS reclaim; (2) optional preferred `player_id` on
   `JoinRoomRequest` / claim (client reclaim store); (3) unique vacant
   nickname hint when preferred is omitted; (4) client seat picker when 2+
   seats are vacant and identity is ambiguous; (5) first vacant (true
   replacement / sole vacant). Preferred seat that is not vacant returns
   `SEAT_NOT_VACANT` (no silent remap). Client reclaim blob is kept across
   intentional leave until foreign claim, game end/abort/restart, or ~10m TTL.
6. **End game:** host may `EndGame` (WS) or `POST .../end`. Vacancy older than
   **10 minutes** auto-ends (`aborted`). Abort removes the actor from
   `state.games`, **hard-deletes** the game row (tip + events), and returns
   the room to **Lobby** (vacant seats dropped). Natural finish does the same
   delete + Lobby return; clients keep standings from the final WS snapshot.
7. **Restart (rematch):** host may `POST .../restart` while vacant if at least
   **3** players remain. Atomic path: abort + drop vacant seats → Lobby →
   auto-ready → new `game_id`. Broadcast `GameRestarted { game_id }`. Rate
   limited (30s per room). Metric `judgement_games_restarted_total` (not
   vacancy-end).
8. **No live `RuleBasedBot` playout** for disconnects. Bots remain for offline
   simulation/tests only. Optional turn-timer auto-move for a *connected*
   slow human is separate.
9. **Safe restore boundary** = actor idle between messages; reconnect during
   a non-zero grace restores control. After Vacant, same-session WS reclaim or
   claim via room code.
10. **Token rotation** on every successful game WebSocket upgrade.
11. **Host migration** on host **leave** or **grace expiry** (not on every WS
    flicker): prefer a Connected human; also sync `Room.host_session` so the
    new host can Start/Restart.
12. **Abandonment GC:** lobby TTL 1h; reaper **4h** TTL is a backstop for any
    leftover finished/aborted rows (primary delete is on finish/abort); orphan
    in-game rooms and guest sessions cleaned by the reaper.
13. **Application keepalive:** the WS writer sends Ping **and** a
    `{"type":"keep_alive"}` text frame every 10s so proxies that ignore Ping
    still see traffic. Keepalive is writer-local (no actor, no
    `state_version`). Clients ignore it.

## Consequences

- Stops bot→DB write storms that froze tables under Postgres resource pressure.
- A 1–3s Railway/phone blip should be invisible: no vacant, no host theft, no
  pause banner. A truly gone player still opens the seat after grace (~12s).
- Games may pause until a human rejoins, the host restarts (≥3), the host ends,
  or the 10m TTL fires.
- Abort/restart/finish free `MAX_ACTIVE_GAMES` slots immediately; finished tip
  snapshots are not retained for coaching.
- Mid-game leave→landing→rejoin should reclaim the leaver's own `player_id`
  when the client still has a reclaim store; multi-vacant joins without identity
  use the picker instead of silently claiming seat-order first vacant.
