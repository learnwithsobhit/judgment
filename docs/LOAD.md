# Load targets (Phase 9)

## Smoke target (CI / laptop)

HTTP smoke: [`deployment/load/smoke.sh`](../deployment/load/smoke.sh)

| Check | Target |
|-------|--------|
| `/healthz` successes | ≥ 100 |
| Guest session creates | ≥ 50 concurrent-ish (xargs -P 20) |
| `/readyz` | 200 |
| `/metrics` | exposes `judgement_http_requests_total` |

WS soak (k6): [`deployment/load/run.sh`](../deployment/load/run.sh) — see [`runbooks/load_testing.md`](runbooks/load_testing.md).

| Ladder | Tables × seats | Where |
|--------|----------------|-------|
| `smoke_ws` | 2×6 | Every-push CI (ephemeral API+Postgres) |
| `smoke_prod` | 1×6 | Manual GitHub only → Fly prod |
| `comfort` | 20×6 | Nightly ephemeral / laptop |
| `target` | 30×6 | Laptop / staging (strict thresholds) |
| `stress` | 40×6 | Cliff finding (ephemeral) |

```bash
# one command: Postgres + API + smoke + k6
./deployment/load/local.sh
./deployment/load/local.sh comfort
```

## Production aspirational target

| Metric | Target |
|--------|--------|
| Concurrent WebSockets | 200 |
| Active game actors | soft cap **100** (`MAX_ACTIVE_GAMES`; further starts rejected) |
| p95 command latency | < 100 ms (in-memory actor path) |
| Persist p95 | < 50 ms on managed Postgres (`judgement_persist_commit_duration_milliseconds`) |
| Error rate (non-429) | < 0.1% under smoke |
| sqlx pool | max **10** connections per API process |

Scrape `/metrics` for `judgement_persist_commit_duration_milliseconds_*`,
`judgement_db_write_failures_total`, `judgement_games_admission_rejected_total`,
`judgement_active_game_actors` — or `./deployment/load/scrape_metrics.sh`.

**Hard UX fail (k6):** action RTT p95 &gt; 500ms, p99 &gt; 1500ms, WS connect errors &gt; 1%, non-retryable rejects &gt; 0.1% (ephemeral `ci` profile). Comfort band for `target`: p95 &lt; 250ms.

Production Fly is never hit from push/PR CI. Manual prod smoke uses loose `prod_remote` thresholds (GitHub → `sin` RTT is noisy).

See also: [`game_estimation.md`](game_estimation.md), [`runbooks/load_testing.md`](runbooks/load_testing.md).
