# ADR 0006 — Multi-game platform (Judgement + Dehla Pakad)

**Status:** Accepted  
**Date:** 2026-08-06  
**Relates to:** `dehla_pakad_digital_product_plan.md`, ADR 0001, ADR 0004

## Context

Judgement is a live, server-authoritative multiplayer product. We are adding
**Dehla Pakad / Mendikot** as a second game. Goals:

- one monorepo for delivery speed;
- one Flutter Web entry (game picker) for players;
- independent runtimes so either game can fail without taking the other down;
- **zero regressions** to existing Judgement play paths.

## Decision

### 1. Separate game backends

- New crates: `dehla-domain`, `dehla-engine`, `dehla-protocol`,
  `dehla-persistence`, `dehla-server`.
- Separate Railway (test) / later prod process + **own Postgres**.
- Do **not** host both engines in `judgement-server`.
- Copy Judgement patterns (actor-per-table, CP tip-before-observe); do not
  modify Judgement crates to share code until a later, Judgement-only extract PR.

### 2. Frontend packages + shell

```text
frontend/
  shell_flutter/       # deployable host: game picker + deep-link router
  judgement_flutter/   # Judgement (unchanged game logic)
  dehla_flutter/       # Dehla-only package (screens, protocol, API, tests)
```

- Dehla UI lives only under `dehla_flutter`.
- Shell routes: `/` picker; Judgement `/r/*`, `/e/*`; Dehla `/dp/*`.
- `API_BASE` (Judgement) and `DEHLA_API_BASE` (Dehla) are separate dart-defines.
- Reclaim / localStorage keys are **namespaced per game**.

### 3. Judgement non-regression (must follow)

Ship Dehla by **addition and copy**. Do not modify Judgement game engine,
protocol, persistence, actor, or table/lobby UI for Dehla features. If a change
seems to require editing Judgement internals, redevelop the equivalent under
`dehla-*` / `dehla_flutter` instead.

Merge gate: Judgement tests remain green; Judgement deep-link behavior for
`/r/*` and `/e/*` unchanged when Judgement is the active module.

### 4. Presence and partners

- Presence: ADR 0004 vacant + pause + human reclaim; **no bot fill** at MVP.
- Partnership: after four seated, default **random opposite partners**; optional
  **choose partners** before start.

### 5. CAP / NFR (Judgement-aligned)

- **CP** for table authority (persist tip before clients observe accepts).
- Single-writer API until ownership leases + sticky WS exist.
- Availability class ~99.0–99.5% if API+DB healthy — not a contractual 99.9% SLO.
- Cost-first scale: admission gates → API RAM → DB → only then multi-writer eng.
- Redis deferred; in-process presence like Judgement.

See [`docs/dehla_game_estimation.md`](../dehla_game_estimation.md).

## Consequences

- Two capacity meters, two deploy pipelines, two migration trees.
- Slight duplication of platform patterns (CORS, capacity, reclaim) until a
  shared extract is justified.
- Shell composition must not break Judgement’s existing Firebase deploy until
  shell is deliberately cut over.

## Alternatives rejected

- Single API process with both rule engines (coupled failure + capacity).
- Nesting Dehla under `judgement_flutter/lib/dehla/` (poor isolation/debug).
- Two Firebase sites for MVP (breaks one-entry UX).
- Bot takeover on disconnect (conflicts with ADR 0004 product choice).
