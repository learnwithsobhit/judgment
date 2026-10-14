# ADR 0006 — Optional Google accounts and a wins ladder

**Status:** Accepted (2026-10-14)
**Amends:** Identity stays guest-first. Does not change bids, card play, timers, or the dealer restriction.

## Context

Players asked for a profile and a public Top 10. A previous draft (`docs/RANKING_PLAN.md`) required a device key and an Elo rating. That would have made every guest a ranked account and would have changed how a night is scored in public.

Guests still need to create a room and join from an invite without an account. Google sign-in has to be optional, and a failed popup must leave the table form usable.

## Decision

1. **Guest play stays the default.** `POST /api/v1/guest-sessions` is unchanged. Google is an extra control under Create room / Join game.
2. **A new bearer, not an upgrade.** `POST /api/v1/auth/firebase` mints a session with `user_id`. It does not attach that user to an existing guest token.
3. **Only a signed-in natural finish is recorded.** Aborts, host-end, and guest seats write nothing. Tables with fewer than 3 seats update lifetime columns and stay off the public board.
4. **Order the board by wins, then exact-bid rate, then average score.** Shared first place counts as a win for each tied player. Accounts with no ranked games are hidden.
5. **Copy `user_id` onto `game_players` at start.** The finish commit reads that column. Two seats with the same user insert one result row. Stats SQL runs in a savepoint so it cannot fail the game commit.
6. **Do not initialize Firebase before the first frame.** The web client loads it after Sign in is tapped.
7. **The board shows the profile name and pack avatar.** Email and the Google photo stay off the board and off the table. The seat nickname is still the name typed at the table.

## Consequences

- Production needs `FIREBASE_PROJECT_ID` on the API and the Firebase web defines on the client. Without them, sign-in fails and guest play still works.
- `STATS_ENABLED=0` turns capture off. Unset means on.
- Apple sign-in, uploaded avatars, and merging a mid-game guest seat into an account are out of scope.
- The legal agreement version is not bumped. The Google control carries its own consent line, and the accepted version is stored on the user row.
