# Security checklist (Phase 9)

Last reviewed: 2026-08-03

## Authentication & sessions

- [x] Guest sessions use opaque bearer tokens (not logged)
- [x] WebSocket token rotation on reconnect (ADR 0004)
- [x] Tokens never appear in structured log fields (§22)
- [x] Client never receives opponent hidden hands

## Transport & origins

- [x] `ALLOWED_ORIGINS` configures CORS allow-list (unset = permissive **dev only**)
- [x] Production TLS termination at Fly.io (API/WSS) and Firebase Hosting (web)
- [x] Secrets (`DATABASE_URL`, `OPENAI_API_KEY`, deploy tokens) via Fly secrets /
  GitHub Actions secrets — never baked into images (see `docs/runbooks/deploy.md`)

## Abuse controls

- [x] HTTP rate limits (`HTTP_RATE_LIMIT`, `HTTP_GUEST_RATE_LIMIT`)
- [x] AI per-session rate limits + cost caps (Phase 7)
- [x] WebSocket max message size + actor backpressure
- [x] Action-id deduplication + state-version checks
- [x] Deterministic `seed` on start-game rejected unless `JUDGEMENT_ALLOW_SEED=1`

## Data

- [x] Server-side shuffle; seed not logged before game completion
- [x] Postgres persistence with restore-on-boot
- [x] Daily backup + restore verification scripts under `deployment/scripts/`
- [x] Managed DB automated backups — enable Fly Postgres continuous backups
  (or provider equivalent); confirm before first public launch
- [x] Client legal gate: Create/Join (and event join/open lobby) require
  versioned Terms + Privacy acceptance (`kLegalAgreementVersion` in
  `frontend/judgement_flutter/lib/util/legal_consent.dart`; stored in
  browser `localStorage`). RSVP contact opt-in defaults off.

## AI boundaries (ADR 0002)

- [x] AI never mutates game state
- [x] AI must not receive hidden cards / shuffle seeds / tokens
- [x] Gameplay continues when AI / RAG unavailable
- [x] Retrieved rule text treated as untrusted data (FAQ/RAG citations only)

## Production gate

Before promoting a release (see also `docs/runbooks/deploy.md`):

1. `ALLOWED_ORIGINS` set to the real Firebase Hosting origins  
2. `DATABASE_URL` points at managed Postgres with TLS (Fly Postgres attach or Neon/Supabase)  
3. `PUBLIC_WEB_ORIGIN` set to the primary Firebase URL  
4. `/readyz` returns 200 and `/metrics` scrapes cleanly  
5. GitHub Actions `CI` green; Deploy smoke curls succeed  
6. Fly Postgres automated / continuous backups confirmed (`fly postgres …` / dashboard)  
7. Migrations through `0008_game_aborted_status` applied (aborted games + retention GC)  
8. This checklist re-checked for any new endpoints  
