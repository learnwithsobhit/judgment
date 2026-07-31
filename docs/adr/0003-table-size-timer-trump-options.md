# ADR 0003 — Variable table size, optional turn timer, chosen-trump rotation

**Status:** Accepted (2026-07-30)
**Amends:** PLAN.md §0 locked decision "exactly six players for MVP",
`docs/RULES.md` players/trump sections. Implemented before Phase 5.

## Context

Play-testing after Phase 4 surfaced three product requests:

1. The turn timer should be optional — casual games with friends do not want
   auto-play on timeout.
2. Tables should support **3 to 8 players**, not exactly 6.
3. Instead of always revealing an undealt card, the **first trump can be
   chosen** when the room is created, after which trump **follows a fixed
   suit order** every round.

## Decision

### 1. Optional turn timer

- `turn_timeout_seconds` becomes `Option<u16>` in `GameRules`, the room
  configuration, and the REST protocol. **Omitted or `null` means no timer.**
- With no timer the actor schedules no deadlines, sends no `TimerUpdated`
  messages, and never auto-plays. Clients that receive no timer events simply
  render no countdown (this already falls out of the Phase 4 UI).
- When a timeout is provided it is clamped to `5..=300` seconds.

### 2. Table size 3–8

- The host chooses `max_players` (3–8, default 6) at room creation.
- The game may **start when every seated player is ready and at least
  `MIN_PLAYERS = 3` are seated** — a room configured for 8 can start with 3.
  *(Originally 4–8; minimum lowered to 3. For 3 players,
  `max_cards = floor(51/3) = 17`, so automatic rounds are 17→1.)*
- All rule quantities stay derived from the *actual* player count at start:
  `max_cards = floor((52 − 1) / players)`, rounds descending `max → 1`
  (4 players: 12→1, 5: 10→1, 6: 8→1, 7: 7→1, 8: 6→1). One card always
  remains undealt, so the revealed-card trump rule works at every size.
- Seat numbers may be non-contiguous at start (players can leave the lobby),
  so the projection now includes `own_seat`; clients must not infer their
  seat from the opponents' seat numbers.

### 3. Chosen first trump with fixed rotation

- Room creation accepts an optional `first_trump` suit.
  - **Absent** → existing MVP behaviour: reveal one undealt card per round;
    its suit is trump (`TrumpRule::RevealUndealtCard`).
  - **Present** → `TrumpRule::FixedSequence`: round 1 uses the chosen suit,
    then trump follows the classic order **♠ spades → ♦ diamonds →
    ♣ clubs → ♥ hearts**, wrapping, one step per round. No trump card is
    revealed in this mode (the projection's `trump_card` stays `null`; the
    `trump` suit is always present during a round).
- The engine records the effective trump suit in state rather than deriving
  it from the revealed card, so both modes flow through the same
  trick-evaluation path.

## Consequences

- `PROTOCOL` additions are backward-compatible for the WS layer
  (`PlayerGameView` gains `own_seat`; `trump` semantics unchanged), but the
  REST `CreateRoomRequest`/`RoomView` change shape (nullable timeout, new
  `max_players`/`first_trump`). Pre-release, no migration needed.
- `GameEvent::TrumpSelected` now carries the suit plus an optional revealed
  card instead of a mandatory card.
- Bot simulations and property tests are parameterised over 3–8 players,
  which widens invariant coverage.
- Scoring, bidding restriction, tie-breaks, dealing order, and dealer
  rotation are untouched — they were already player-count agnostic.
