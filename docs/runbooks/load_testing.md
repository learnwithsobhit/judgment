# Load testing runbook

k6 suite under [`deployment/load/`](../../deployment/load/) exercises lobby REST + 6-seat WebSocket bid/play with hard UX thresholds.

## Safety

| Target | How |
|--------|-----|
| Local / CI ephemeral | Default. `API_BASE=http://127.0.0.1:8080` |
| Production Fly | **Manual only.** Requires `ALLOW_PROD_LOAD=1` and scenario `smoke_prod` |
| Push/PR CI | Always ephemeral — never sets `ALLOW_PROD_LOAD` |

`deployment/load/run.sh` refuses `*.fly.dev` unless `ALLOW_PROD_LOAD=1`, and on prod hosts only allows `smoke_prod`.

## Scenarios

| Scenario | Tables × seats | Typical use |
|----------|----------------|-------------|
| `smoke_ws` | 2×6 | Every-push CI + laptop sanity |
| `smoke_prod` | 1×6 | Manual GitHub → `judgment-api.fly.dev` |
| `comfort` | 20×6 | Nightly ephemeral / laptop |
| `target` | 30×6 | Laptop capacity (strict RTT) |
| `stress` | 40×6 | Find cliff (ephemeral) |
| `admission` | start until 409 | Prove `MAX_ACTIVE_GAMES=100` (ephemeral) |

Short manual schedule (2 rounds × 3 cards) is default so CI finishes quickly. Full automatic schedule: `FULL_SCHEDULE=1`.

## Threshold profiles

| Profile | When | Action RTT gate |
|---------|------|-----------------|
| `ci` | Ephemeral GitHub | p95 &lt; 500ms, p99 &lt; 1500ms |
| `strict` | Laptop / staging `target` | p95 &lt; 250ms, p99 &lt; 500ms |
| `prod_remote` | Manual Fly from GH | Loose RTT; fail WS / hard rejects |

## Local (one command)

```bash
# Postgres + API + HTTP smoke + k6 smoke_ws, then stop API
./deployment/load/local.sh

# Other scenarios
./deployment/load/local.sh comfort
THRESHOLDS_PROFILE=strict ./deployment/load/local.sh target
./deployment/load/local.sh admission

# Options
./deployment/load/local.sh --memory smoke_ws   # skip Postgres (in-memory store)
./deployment/load/local.sh --reset-db comfort  # wipe stale local compose volume
./deployment/load/local.sh --keep-api smoke_ws # leave API up after
./deployment/load/local.sh --http-only         # smoke.sh only
```

If the API panics with `migration 1 was previously applied but has been modified`, the local Docker volume has an old migration checksum. Use `--reset-db` (safe for local compose only — not Fly).


`local.sh` starts `docker compose` Postgres if needed, builds a release API, waits for `/readyz`, runs tests, scrapes metrics, and stops the API it started (unless `--keep-api`). If something is already listening on `:8080` and ready, it reuses it.

Manual two-terminal flow (optional):

```bash
# Terminal A
cd backend
DATABASE_URL=postgres://judgement:judgement@127.0.0.1:5434/judgement \
  JUDGEMENT_ALLOW_SEED=1 HTTP_GUEST_RATE_LIMIT=10000 HTTP_RATE_LIMIT=100000 \
  cargo run -p judgement-server

# Terminal B
./deployment/load/smoke.sh
./deployment/load/run.sh smoke_ws
```

Install k6: `brew install k6` (or https://grafana.com/docs/k6/latest/set-up/install-k6/).

## GitHub Actions

1. **Every push/PR** — job `load-smoke-ws` in [`ci.yml`](../../.github/workflows/ci.yml): Postgres service + release binary + `smoke.sh` + k6 `smoke_ws`.
2. **Nightly / manual ephemeral** — [`load-nightly.yml`](../../.github/workflows/load-nightly.yml): default `comfort`; dispatch can pick `target` / `stress` / `admission`.
3. **Manual prod smoke** — [`load-prod-smoke.yml`](../../.github/workflows/load-prod-smoke.yml):
   - Trigger: **Run workflow** only (no schedule).
   - Environment: `prod-load` (configure required reviewers in GitHub Settings → Environments).
   - Hits `https://judgment-api.fly.dev` with 1×6 seats, no seed.
   - Run in a quiet window; guest rate limit is 20/min/IP by default.

## Interpreting results

- Soft product capacity ≈ last green ladder step (expect ~30×6 ≈ 180 WS).
- `MAX_ACTIVE_GAMES=100` is a backstop, not a marketing number.
- After a run: check persist p95 via `scrape_metrics.sh` and `db_write_failures` delta.
- Prod remote smoke proves “prod still plays”; it does **not** validate the 200 WS LOAD target (use laptop → Fly or ephemeral `target`/`stress`).

See also: [`LOAD.md`](../LOAD.md), [`game_estimation.md`](../game_estimation.md), [`incident.md`](incident.md).
