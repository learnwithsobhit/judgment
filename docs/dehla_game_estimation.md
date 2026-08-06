# Dehla Pakad — game capacity estimation

Ballpark capacity, latency, availability, and scalability for the **Dehla**
service. Mirrors Judgement’s posture in [`game_estimation.md`](game_estimation.md)
and ADR 0006. Figures are engineering targets — **not** contractual SLOs unless
labeled otherwise.

Related: ADR 0001 (actor-per-game), ADR 0004 (presence), ADR 0006 (multi-game),
[`dehla_pakad_digital_product_plan.md`](../dehla_pakad_digital_product_plan.md).

---

## 1. Executive summary

| Metric | Ballpark (MVP topology) |
|--------|-------------------------|
| CAP class | **CP** table authority (durable tip before observe) |
| Topology | **1** API process + **1** Postgres (colocated); separate from Judgement |
| Product **hard** gate (initial) | ~**40** tables **or** ~**160** WS (4 seats × 40) → `CAPACITY_FULL` |
| Emergency start cap | ~**100** actors (shed-load; not a promise) |
| Perceived action latency (India, healthy) | **~100–200 ms** p50 |
| Persist p95 target | **&lt; 50 ms** |
| Server apply p95 | **&lt; 100 ms** (in-memory actor path) |
| Hard UX fail (load) | action RTT p95 **&gt; 500 ms** / p99 **&gt; 1.5 s** |
| Availability class | Single-node **CP**; ~**99.0–99.5%** if API+DB healthy — **not** a contract |
| Binding limit | **WebSocket / API memory** (same as Judgement) |
| Cheapest scale-up | API RAM bump, then raise hard gate — **not** a 2nd writer yet |
| Bots / matchmaking queues | **Out of MVP** — private rooms, human seats only |

---

## 2. CAP stance

| Concern | Choice |
|---------|--------|
| Table authority | **CP** — persist tip before broadcast |
| Partition | Prefer consistency; retryable reject on persist failure |
| Presence | In-process; process death drops WS; tip restore + ADR 0004 reclaim |
| Horizontal writers | **Forbidden** until ownership leases + sticky WS |
| Shared Redis | **Deferred** — no MVP tip/presence dependency |

Do **not** autoscale API machine count without leases (split-brain).

---

## 3. Baseline assumptions (MVP)

| Resource | Initial value |
|----------|----------------|
| Seats per table | **4** (fixed partnerships) |
| sqlx pool | **10** / API process |
| Actor command queue | **256** / table |
| WS client buffer | **64** |
| Persist timeout | **3 s** (up to 2 attempts) — match Judgement pattern when implemented |
| Region | Railway test first; API+DB colocated |

---

## 4. Latency budget

| Segment | Budget |
|---------|--------|
| Player network RTT | Excluded from server SLI |
| WS command → actor apply | typically &lt; 5–20 ms |
| Persist tip | p95 &lt; 50 ms |
| Broadcast (4 personalized views) | &lt; ~10–30 ms |
| Emotes / voice (later) | Ephemeral WS; off persist critical path |

Colocate API and Postgres. Do not move DB alone to another region.

---

## 5. Availability

| Aspect | Behavior |
|--------|----------|
| Process death | All WS drop; tip snapshots restore actors on boot; players reclaim |
| Presence | ADR 0004 vacant + pause; human reclaim; **no bot fill** |
| Monthly class | ~99.0–99.5% if platform healthy — **not** 99.9% MVP claim |
| Multi-game | Dehla outage must not take Judgement tables down (separate service+DB) |

Levers: admission gates, pool sizing, retryable rejects, client retry, actor
respawn from tip, `/healthz` `/readyz` `/metrics`.

---

## 6. Cost-first scale ladder

| Step | When | Notes |
|------|------|-------|
| Hard admission ~40 / ~160 WS | Always | Protects in-progress tables |
| API RAM 1→2 GB | Full rejects; persist OK | Then raise hard gate |
| Postgres RAM bump | Persist p95 / write fails under modest load | Measure first |
| Second API writer | Only after leases + sticky WS | Eng-heavy; deferred |

**Anti-patterns:** Redis “because the plan said so”; merging Dehla into
`judgement-server` to save money (couples failure domains).

---

## 7. Independence from Judgement

- Separate Railway service, Dockerfile, migrations, metrics prefix (`dehla_*`).
- Separate Firebase dart-define `DEHLA_API_BASE`.
- Capacity meters are **not** shared with Judgement.
