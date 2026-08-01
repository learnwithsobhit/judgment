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
| Active game actors | soft cap **100** (`MAX_ACTIVE_GAMES`; further starts rejected) |
| p95 command latency | < 100 ms (in-memory actor path) |
| Persist p95 | < 50 ms on managed Postgres (`judgement_persist_commit_duration_milliseconds`) |
| Error rate (non-429) | < 0.1% under smoke |
| sqlx pool | max **10** connections per API process |

Scrape `/metrics` for `judgement_persist_commit_duration_milliseconds_*`,
`judgement_db_write_failures_total`, `judgement_games_admission_rejected_total`,
`judgement_active_game_actors`.

Full multiplayer soak (six seats × N rooms) is deferred to an external k6 suite;
the smoke script gates Phase 9 exit criterion “load target met” for MVP.
