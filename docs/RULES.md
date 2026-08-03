# Judgement — Rule Specification (MVP)

**Status:** Phase 0 deliverable, amended by ADR 0003 (variable table size,
optional turn timer, chosen-trump rotation). This document resolves all rule
ambiguities for the MVP. It reflects the locked decisions in `PLAN.md` §0;
do not re-open them without an ADR.

## Locked decisions

| # | Decision | Behaviour |
|---|----------|-----------|
| 1 | First-trick leader each round | Player clockwise-left of the dealer leads trick 1; thereafter the trick winner leads |
| 2 | Final ranking tie-break | Highest score, then most exact-bid rounds, then fewest total tricks missed; if still equal, shared rank |
| 3 | RAG in MVP | Deterministic reason codes + curated FAQ; pgvector RAG deferred, feature-flagged |
| 4 | Permanent leave | Rule-based bot plays out the remainder of the game for that seat |
| 5 | Host migration | Longest-connected occupied seat is auto-promoted to host |
| 6 | MVP state sync | Full `StateSnapshot` on every accepted command; deltas deferred |
| 7 | Table size (ADR 0003, min amended) | 3–8 players; host picks room size; start needs ≥ 3 seated, all ready |
| 8 | Turn timer (ADR 0003) | Optional; no timer ⇒ no deadlines and no auto-play |
| 9 | Trump mode (ADR 0003) | Host may choose the first trump; it then rotates ♠→♦→♣→♥ per round. Otherwise: revealed undealt card |
| 10 | Round schedule | Host may choose **Automatic** (descending max→1 for the seated count) or **Manual** (ordered steps of `{cards, repeat}` expanded to a custom deal list) at room creation |
| 11 | Scheduled events (ADR 0005) | Future meetup: FCFS **8 going** + **5 waitlist**; cancel promotes waitlist; lobby size = going count (≥3); `.ics` reminders |

## Scheduled game events

- Distinct from **round schedule** (deal pattern) and from live **rooms**.
- Anyone may create an event (guest nickname + manage link). **No host-chosen
  player count** — seats fill first-come-first-served: up to **8 going**, then
  up to **5 waitlisted**. Cancelling a going RSVP promotes the oldest waitlisted.
- Hosts share the invite link via WhatsApp themselves.
- **Reminders (v1):** download `.ics` with calendar alarms — no SMS/WhatsApp API.
- Opening the lobby requires ≥ **3 going** RSVPs and creates a room with
  `max_players = going_count` (≤ 8). Waitlisted guests join only after promotion.

## Players and deck

- **3 to 8 players** (host chooses the table size at room creation; default 6).
  The game can start when at least 3 players are seated and everyone seated is
  ready.
- Before start, the **host may remove** any other seated player from the lobby
  (the removed player may rejoin if a seat is free). The host cannot remove
  themselves; they leave via the normal leave action.
- Standard **52-card deck**, no jokers.
- Seats are fixed table positions; play proceeds **clockwise** (ascending
  seat order, wrapping). Seat numbers may be non-contiguous if players left
  the lobby before the start.

## Card ranking

Within a suit: `Two < Three < … < Ten < Jack < Queen < King < Ace` (**Ace high**).
There is no ranking across suits except via the trump and lead-suit rules.

## Rounds

- Maximum cards per player is **derived**, never hardcoded:
  `max_cards = floor((52 − 1) / player_count)` — one card always remains
  undealt. Per player count: 3 → 17, 4 → 12, 5 → 10, 6 → 8, 7 → 7, 8 → 6.
- **Automatic** (default): descending **max → 1** for the seated count
  (six players: 8 → 7 → … → 1).
- **Manual**: the host authors steps `{ cards, repeat }` (e.g. 12×2, 11×2, …,
  then 4, 3, 2, 1). The server expands these into a flat per-round deal list
  (`RoundPattern::Custom`) at start. Card counts must fit the seated table
  (`1..=max_cards`) and the deck; an incompatible schedule rejects start
  rather than clamping.
- The dealer for round 1 is the lowest occupied seat; the dealer **rotates
  clockwise** each round.

## Dealing and trump

1. The server shuffles the full deck with secure randomness (seeded in tests).
2. Each player is dealt the round's card count, one at a time, starting
   clockwise-left of the dealer.
3. Trump for the round is decided by the room's trump mode (ADR 0003):
   - **Revealed card** (default): one card is revealed from the undealt
     remainder; **its suit is trump** and the revealed card is out of play
     for the round.
   - **Chosen rotation**: the host picked a first trump at room creation.
     Round 1 uses it; each later round advances one step in the fixed order
     **♠ → ♦ → ♣ → ♥**, wrapping. No card is revealed in this mode.

## Bidding

- Bidding starts with the player clockwise-left of the dealer and proceeds
  clockwise; **the dealer bids last**.
- Bid range is `0..=cards_in_round`; zero is allowed.
- Bids are visible immediately; an accepted bid cannot be changed.
- **Dealer restriction** (optional, **off by default**): when the host enables
  it at room create, the dealer may not bid a value that would make the total
  of all bids equal the number of tricks available. When enabled, this removes
  exactly one option from `0..=cards`, so the dealer always has a legal bid.

## Card play

- The first trick of each round is led by the player clockwise-left of the
  dealer; each subsequent trick is led by the previous trick's winner.
- Play proceeds clockwise. On your turn you must:
  - own the card you play, and
  - **follow the lead suit if you hold it**; otherwise any card is legal.
- Trick winner:
  1. If any trump card was played, the highest trump wins.
  2. Otherwise the highest card of the lead suit wins.
  3. Off-suit, non-trump cards can never win.

## Scoring

Default scoring (per round):

```text
Exact bid:  10 + bid
Missed bid: 0
```

Final ranking applies the locked tie-break: total score (desc) → exact-bid
rounds (desc) → total tricks missed `Σ|bid − won|` (asc) → shared rank
(competition ranking: 1, 1, 3).

## Error / reason codes

| Code | Meaning |
|------|---------|
| `NOT_YOUR_TURN` | Command from a player out of turn |
| `WRONG_PHASE` | Action not allowed in the current phase |
| `CARD_NOT_IN_HAND` | Player does not own the card |
| `MUST_FOLLOW_SUIT` | Player holds the lead suit but played another |
| `BID_OUT_OF_RANGE` | Bid outside `0..=cards_in_round` |
| `DEALER_BID_RESTRICTION` | Dealer bid would make totals equal tricks |
| `BID_ALREADY_PLACED` | Bid already accepted this round |
| `STALE_STATE` | Client's expected state version is outdated |
| `ACTION_ALREADY_PROCESSED` | Duplicate `action_id` |
| `PLAYER_NOT_IN_GAME` | Unknown player for this game |
| `GAME_ALREADY_FINISHED` | Game is complete |
| `INVALID_PLAYER_COUNT` | Game cannot start with this seat count |

## Disconnects (policy summary — implemented in Phase 6)

- On disconnect: seat becomes **vacant immediately**; table pauses.
- Rejoin via same-session WS or claim with room code; host may **restart**
  (remaining ≥ 3, new game same room) or **end**; else 10-minute vacancy TTL.
  (Legacy non-zero grace still possible via `reconnect_grace_seconds`.)
- Host leave: longest-connected occupied seat becomes host (`host_session` synced).

## Table engagement (cosmetic)

Reactions, avatar flashes, emoji bursts, and scoreboard UX are **presentation
only**. They do not change legal bids, playable cards, trick winners, or
scoring. Running **TOTAL** scores stay hidden until **halftime** of the
schedule (`⌈total_rounds / 2⌉` completed rounds), or once the table reaches
the ≤3-card phase; after that they stay visible for the rest of the game.
Works the same for Automatic and host-edited Manual schedules (`total_rounds`
is the expanded deal count).

After the last trick of a round, the server holds briefly in `RoundScoring`
(~1.8s) so clients can show the completed trick before the next deal or
game-over screen. Scoring for that round is already recorded; only the next
deal / finish is delayed.
