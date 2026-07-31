# Load targets (Phase 9)

## Smoke target (CI / laptop)

Script: `deployment/load/smoke.sh`

| Check | Target |
|-------|--------|
| `/healthz` successes | ≥ 100 |
| Guest session creates | ≥ 50 concurrent-ish (xargs -P 20) |
| `/readyz` | 200 |
| `/metrics` | exposes `judgement_http_requests_total` |

Run:

```bash
# server on :8080
./deployment/load/smoke.sh
```

## Production aspirational target

| Metric | Target |
|--------|--------|
| Concurrent WebSockets | 200 |
| p95 command latency | < 100 ms (in-memory actor path) |
| Persist p95 | < 50 ms on managed Postgres |
| Error rate (non-429) | < 0.1% under smoke |

Full multiplayer soak (six seats × N rooms) is deferred to an external k6 suite;
the smoke script gates Phase 9 exit criterion “load target met” for MVP.
