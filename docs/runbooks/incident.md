# Incident runbook (Phase 9)

## Severity

| Level | Meaning | Example |
|-------|---------|---------|
| SEV-1 | Players cannot play | API 5xx, DB down, mass disconnects |
| SEV-2 | Degraded | High latency, AI outages, elevated rate-limits |
| SEV-3 | Cosmetic / single-room | One stuck lobby, bad FAQ answer |

## Quick triage

1. Check `/healthz` (process up) and `/readyz` (DB reachable).  
2. Scrape `/metrics` — look at `judgement_db_write_failures_total`, `judgement_http_rate_limited_total`, `judgement_active_game_actors`.  
3. Check reverse-proxy / container logs for panic or OOM.  
4. Confirm Postgres connectivity and disk.

## Common incidents

### Database unavailable

Symptoms: `/readyz` → 503; `db_write_failures` climbing; actors may reject commands.

Actions:

1. Fail over / restart managed Postgres.  
2. Verify `DATABASE_URL`.  
3. Restart `judgement-server` after DB is healthy (restore-on-boot reloads active games).  
4. If corrupted, restore from last verified backup (`deployment/scripts/restore_verify.sh` pattern).

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

Symptoms: idle lobbies consuming memory.

Actions:

1. Reaper runs every 30s with 1h lobby TTL — check `rooms_reaped` metric.  
2. Manual: restart server (in-memory lobbies lost; durable rooms reload from DB).

### Mass WebSocket disconnects

Symptoms: reconnect storms; bot takeovers spike.

Actions:

1. Check proxy idle timeouts (must exceed heartbeats: 15s ping / 45s liveness).  
2. Confirm clients handle `TokenRotated`.  
3. Watch `judgement_reconnects_total` vs `bot_takeovers_total`.

## Rollback

1. Deploy previous container image tag.  
2. Do **not** run destructive down-migrations unless the release notes require it.  
3. Confirm `/readyz` and a single guest-session + room create.

## Contacts / ownership

Fill in for your deployment:

- On-call: _TBD_  
- Hosting project: _TBD_  
- Status page: _TBD_  
