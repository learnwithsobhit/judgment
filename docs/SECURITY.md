# Security checklist (Phase 9)

Last reviewed: 2026-07-31

## Authentication & sessions

- [x] Guest sessions use opaque bearer tokens (not logged)
- [x] WebSocket token rotation on reconnect (ADR 0004)
- [x] Tokens never appear in structured log fields (§22)
- [x] Client never receives opponent hidden hands

## Transport & origins

- [x] `ALLOWED_ORIGINS` configures CORS allow-list (unset = permissive **dev only**)
- [x] Production TLS termination at Railway (API/WSS) and Firebase Hosting (web)
- [x] Secrets (`DATABASE_URL`, `OPENAI_API_KEY`, deploy tokens) via Railway / GitHub
  Actions secrets — never baked into images (see `docs/runbooks/deploy.md`)

## Abuse controls

- [x] HTTP rate limits (`HTTP_RATE_LIMIT`, `HTTP_GUEST_RATE_LIMIT`)
- [x] AI per-session rate limits + cost caps (Phase 7)
- [x] WebSocket max message size + actor backpressure
- [x] Action-id deduplication + state-version checks

## Data

- [x] Server-side shuffle; seed not logged before game completion
- [x] Postgres persistence with restore-on-boot
- [x] Daily backup + restore verification scripts under `deployment/scripts/`
- [x] Managed DB automated backups — enable in Railway Postgres plugin UI
  (operator checklist; confirm before first public launch)

## AI boundaries (ADR 0002)

- [x] AI never mutates game state
- [x] AI must not receive hidden cards / shuffle seeds / tokens
- [x] Gameplay continues when AI / RAG unavailable
- [x] Retrieved rule text treated as untrusted data (FAQ/RAG citations only)

## Production gate

Before promoting a release (see also `docs/runbooks/deploy.md`):

1. `ALLOWED_ORIGINS` set to the real Firebase Hosting origins  
2. `DATABASE_URL` points at managed Postgres with TLS (Railway plugin)  
3. `PUBLIC_WEB_ORIGIN` set to the primary Firebase URL  
4. `/readyz` returns 200 and `/metrics` scrapes cleanly  
5. GitHub Actions `CI` green; Deploy smoke curls succeed  
6. Railway Postgres automated backups confirmed in the dashboard  
7. This checklist re-checked for any new endpoints  

