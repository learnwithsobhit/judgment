# ADR 0008 — Optional dealer shuffle ritual

**Status:** Accepted (2026-11-14)
**Amends:** room create Pace options; dealing phase when host enables the
ritual. Complements ADR 0001 (actor-per-game), ADR 0003 (timers), ADR 0004
(presence).

## Context

Hosts asked for a visible, shared shuffle before each round so every seat
sees the same wash and the dealer taps **Deal** when ready. The animation is
trust theatre; card order must stay server-authored. Tables must never stall
if the dealer idles or disconnects.

## Decision

1. **Host flag** `dealer_shuffle_ritual` (default **false**) on room create,
   same Pace pattern as bid/play timers. Flag off keeps today’s one-shot
   shuffle+deal with no new phase chrome.
2. **Flag on:** enter `Dealing` with a pending deck; project
   `shuffle { shuffle_index, animation_seed, can_shuffle, can_deal }` (never
   the deck). Dealer may `ShuffleDeck` (rate-limited) and `DealCards`.
3. **Timers:** soft auto-deal (~12s, +4s per reshuffle, hard cap 30s) via the
   existing stale-id deadline path. Bid/play timers are **not** armed in the
   ritual. Pause holds the soft deadline; resume re-arms.
4. **Vacant dealer:** auto-commit deal immediately so a paused table cannot
   wedge on missing Deal. Reconnect grace still holds soft deadlines; on
   resume, an already-elapsed soft window re-arms a 100ms auto-deal fuse.
5. **Client:** shared `ShuffleStage` motion (≤900ms) driven by seed/index;
   never blocks WS. Reconnect catch-up skips replaying prior washes. Leaving
   the ritual clears any `TimerUpdated` countdown so a missing bid timer
   cannot show a phantom deal countdown. Rate-limited `ShuffleDeck` is
   `CommandAccepted` (same version) so pending commands never stick.

## Consequences

- Additive protocol; old clients treat missing flag as off.
- Persist/restore keeps pending deck when mid-ritual (or safe one-shot
  auto-deal on restore if serialization fails).
- Soft CAP stance unchanged: one actor writer; animation is presentation only.

## Architecture / CAP checklist

- [x] Default-off rooms match pre-change deal behavior (engine + e2e).
- [x] Actor never sleeps for client animation.
- [x] Bid/play deadlines not scheduled in ritual `Dealing`.
- [x] Pause holds soft auto-deal; vacant dealer still auto-deals.
- [x] Dealer disconnect mid-shuffle cannot freeze the match.
- [x] Pending deck restored or auto-dealt — no half-dealt hands.
- [x] Missing flag field → off.
- [x] No second writer; no client-authored card order.
