# ADR 0007 — Tournament points series (dual-credit standings)

**Status:** Accepted (2026-11-12)
**Amends:** Competitive tagging beside Top players; does not change medal math,
fair play, Who’s free, or ADR 0005 scheduled RSVP events.

## Context

Hosts want a multi-table night with a shared standings board. Classic knockout
brackets do not map cleanly onto 3–8 player Judgement tables. Finished games are
**hard-deleted** after results persist, so standings cannot join live `games`
rows after finish.

## Decision

1. **v1 format** is a **points series**: satellite tables optionally attach to a
   **live** tournament; medal points accumulate with the same
   `MedalRecord::key` ordering as Top players (Gold 500 / Silver 100 / Bronze 20).
2. **Dual credit:** every counted finish still feeds Top players. Tournament
   boards filter `user_game_results` where `tournament_id` is set.
3. **Authoritative stamp:** at finish, idempotent insert of
   `user_game_results` also writes nullable `tournament_id` from the game actor
   (copied from the lobby at start). Rooms may carry the id for lobby UX only.
4. **Admin create/manage** via `ADMIN_EMAILS` / `user_is_admin` (same as festival).
   Status: Draft → Live → Closed. Closed blocks new attaches; standings remain
   readable. Reopen is an explicit admin `PATCH` to `live`.
5. **Attach:** any signed-in host may attach a new room to a live tournament;
   guests never see the control; default None. Missing tournament list must not
   break Create room.
6. **Reads** are eventual / rate-limited like other boards. Do not put standings
   refresh on the hot command path. Soft in-memory cache (~45s) is optional
   v1.1 if load rises.
7. **Non-goals v1:** bracket engine, buy-ins, Elo, auto-attach every room,
   coupling to ADR 0005 calendar invites.

## Consequences

- Migration adds `tournaments`, `rooms.tournament_id`, and indexed
  `user_game_results.tournament_id`.
- Public `GET /api/v1/tournaments` and detail+standings; admin
  `POST/PATCH /api/v1/admin/tournaments`.
- Flutter: admin sheet, create-room Event attach, leaderboard Tournament tab,
  quiet lobby/result lines.
