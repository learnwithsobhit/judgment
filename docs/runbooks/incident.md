# Incident runbook (Phase 9)

## Severity

| Level | Meaning | Example |
|-------|---------|---------|
| SEV-1 | Players cannot play | API 5xx, DB down, mass disconnects |
| SEV-2 | Degraded | High latency, AI outages, elevated rate-limits |
| SEV-3 | Cosmetic / single-room | One stuck lobby, bad FAQ answer |

## Quick triage

1. Check `/healthz` (process up) and `/readyz` (DB reachable).  
2. Scrape `/metrics` — look at `judgement_db_write_failures_total`, `judgement_persist_commit_duration_milliseconds_*` (p95 via histogram), `judgement_http_rate_limited_total`, `judgement_active_game_actors`, `judgement_active_websockets`, `judgement_capacity_full_rejected_total`, `judgement_capacity_busy_total`, `judgement_games_admission_rejected_total`, `judgement_actors_respawned_total`.  
3. Check reverse-proxy / container logs for panic or OOM.  
4. Confirm Postgres connectivity and disk.

### Alert thresholds (practical)

| Signal | Worry when |
|--------|------------|
| `judgement_db_write_failures_total` | Sustained increase over 5m |
| Persist histogram | Most samples above `le="100"` (p95 ≫ 50ms) |
| `/readyz` | Not 200 for >1m |
| `judgement_capacity_full_rejected_total` | Climbing while actors ≈ 35 or WS ≈ 200 — expected under load; if sustained, scale API **1GB→2GB** (~+$5) before raising hard gate |
| `judgement_games_admission_rejected_total` | Climbing while actors ≈ 100 — emergency backstop; scale API/DB only after measuring |
| API OOM / restarts | Raise `judgment-api` memory (config target **1GB**; next step **2GB**) |

## Common incidents

### Database unavailable / mid-game table freeze

Symptoms: every seat appears frozen; `/readyz` → 503 or flaky; `db_write_failures` climbing;
logs show `persist commit failed` / sqlx EOF; Fly Postgres health reports memory/IO limits.

Cause: game actor **awaits** durable persist before broadcasting — a stalled DB blocks the whole table.

Actions:

1. Check Fly Postgres VM memory (minimum **1024 MB** for `judgment-db`).  
2. Fail over / restart managed Postgres; confirm health checks pass.  
3. Verify `DATABASE_URL`; restart `judgement-server` after DB is healthy (restore-on-boot).  
4. Watch `judgement_db_write_failures_total` and slow-persist warnings.  
5. If corrupted, restore from last verified backup (`deployment/scripts/restore_verify.sh` pattern).  
6. Enable backups if unset: `fly pg backup enable -a judgment-db` (interactive ToS).

### Rate-limit storm

Symptoms: many `429 RATE_LIMITED`; clients see transient failures.

Actions:

1. Confirm not a self-inflicted load test.  
2. Temporarily raise `HTTP_RATE_LIMIT` / `HTTP_GUEST_RATE_LIMIT` if legitimate traffic.  
3. Block abusive IPs at the reverse proxy.  
4. AI-only storms: AI caps are independent — gameplay should continue.

### AI / RAG outage

Symptoms: rules assistant slow/empty; `ai_fallbacks` up. Gameplay unaffected by design.

Actions:

1. Set `RAG_ENABLED=0` if vector path misbehaves.  
2. Leave FAQ/templates on (default).  
3. Investigate provider keys only if Rig rewrite is enabled.

### Stuck or abandoned rooms

Symptoms: idle lobbies / finished rooms consuming memory; `active_rooms` much larger than actors.

Actions:

1. Reaper: 1h lobby TTL; **24h** finished/aborted game purge; orphan room GC — check `rooms_reaped`, `games_purged`.  
2. Manual backfill: `deployment/scripts/purge_finished_games.sql` against Postgres.  
3. Restart server only if needed (in-memory lobbies lost; durable rooms reload from DB).

### Vacant seat / paused table (expected product state)

Symptoms: pause banner; `SeatVacant`; peers asked to share room code.

Actions:

1. Share room code so a replacement can join/claim.  
2. Host taps **End game** (or wait ~10 minutes for vacancy timeout).  
3. Metrics: `seat_vacancies`, `seat_claims`, `games_ended_vacancy`.

### Mass WebSocket disconnects

Symptoms: reconnect storms; seats go vacant (not bot-filled).

Actions:

1. Check proxy idle timeouts (must exceed heartbeats: 15s ping / 45s liveness).  
2. Confirm clients handle `TokenRotated`.  
3. Watch `judgement_reconnects_total` vs `seat_vacancies_total`.

## Rollback

1. Deploy previous container image tag.  
2. Do **not** run destructive down-migrations unless the release notes require it.  
3. Confirm `/readyz` and a single guest-session + room create.

## Contacts / ownership

Fill in for your deployment:

- On-call: _TBD_  
- Hosting project: _TBD_  
- Status page: _TBD_  
