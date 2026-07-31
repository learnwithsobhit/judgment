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
2. Persist resulting domain events transactionally (commit point)
3. Apply events in memory
4. Increment state version
5. Broadcast personalised `PlayerGameView` projections

Consequences of the design:

- No lock contention or interleaved mutation; the state machine stays pure and
  deterministic (implemented in `judgement-engine` with no Axum/SQL deps).
- Queue overflow is observable and rejected with a retryable error — never
  silently dropped.
- Bot compute and turn timers run **off-actor**; results re-enter as normal
  validated command envelopes, so slow simulations cannot stall the loop.
- Timer expiry messages carry a `deadline_id`; a stale deadline (turn already
  advanced) is ignored.
- Actor failure or restart recovers by loading the latest snapshot and
  replaying later events, rebuilding the action-dedup registry.

## Alternatives considered

- **Shared state + mutex:** rejected — lock ordering complexity, risk of
  holding locks across await points, harder to reason about fairness.
- **Database-serialized commands (row locks):** rejected for MVP — higher
  latency per action and pushes game logic toward SQL.

## Status in code

Phase 1 implements the pure engine (`GameEngine`) that the actor will own.
The actor loop, channel, and persistence hooks arrive in Phase 3/5.
