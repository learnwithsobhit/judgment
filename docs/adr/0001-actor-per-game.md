# ADR 0001 — One sequential actor per active game

**Status:** Accepted
**Date:** 2026-07-30
**Relates to:** PLAN.md §9.1

## Context

A multiplayer card game is a distributed state machine with private
information, sequential actions, and unreliable clients. Concurrent mutation of
game state would allow races (two cards played "simultaneously", double
scoring, dedup bypass).

## Decision

Each active game is owned by exactly one sequential command processor (a Tokio
task reading from a **bounded** `mpsc` channel). All mutations flow through it:

1. Validate command against authoritative state
2. **Apply** the mutation in the in-memory `GameEngine` (clone prior state for rollback)
3. **Persist** resulting domain events + tip snapshot transactionally (commit point)
4. On persist success: broadcast personalised `PlayerGameView` projections
5. On persist failure: if `action_id` is **not** already durable, `replace_state(previous)` and reject with retryable `PersistUnavailable`; if it *is* durable (timeout ambiguity), keep the applied state and treat as success

Consequences of the design:

- No lock contention or interleaved mutation; the state machine stays pure and
  deterministic (implemented in `judgement-engine` with no Axum/SQL deps).
- Clients never observe an accepted command that is not durable (CP for table authority).
- Queue overflow is observable and rejected with a retryable error — never
  silently dropped.
- Turn timers run **off-actor**; results re-enter as normal validated command
  envelopes, so sleeps cannot stall the loop.
- Timer expiry messages carry a `deadline_id`; a stale deadline (turn already
  advanced) is ignored.
- Actor failure or restart recovers by loading the latest tip snapshot and
  rebuilding the action-dedup registry; the reaper respawns dead actors for
  still-active games.

## Alternatives considered

- **Shared state + mutex:** rejected — lock ordering complexity, risk of
  holding locks across await points, harder to reason about fairness.
- **Database-serialized commands (row locks):** rejected for MVP — higher
  latency per action and pushes game logic toward SQL.
- **Accept before persist (AP):** rejected — seats could diverge on DB failure.

## Status in code

Implemented in `judgement-server` (`actor.rs`) with `judgement-persistence`
as the durable commit point.
