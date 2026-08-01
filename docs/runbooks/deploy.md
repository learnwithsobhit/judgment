# Deploy runbook — GitHub + Fly.io + Firebase

Production layout:

- **API / WebSocket** → Fly.io (`judgment-api`, Docker via [`fly.toml`](../../fly.toml))
- **Flutter Web** → Firebase Hosting (`judgment-lws-260731`)
- **Postgres** → Fly Postgres (attached `DATABASE_URL`) or Neon/Supabase
- **CI/CD** → GitHub Actions (`.github/workflows/`)

WebSockets go **browser → Fly.io** directly (Firebase does not proxy WS).
`ALLOWED_ORIGINS` must list the Firebase origins.

---

## One-time bootstrap

### 1. GitHub

```bash
cd judgement   # this directory is the git root
git remote -v  # e.g. https://github.com/learnwithsobhit/judgment.git
git push -u origin main
```

### 2. Fly.io (API + Postgres)

```bash
# Install CLI: https://fly.io/docs/hands-on/install-flyctl/
export PATH="$HOME/.fly/bin:$PATH"
fly auth login

cd judgement   # repo root with fly.toml
fly apps create judgment-api --org personal   # skip if app exists

# Managed Postgres (pick a region close to the app; sin = Singapore).
# Minimum memory: 1GB — 256MB thrashing causes mid-game persist hangs.
fly postgres create --name judgment-db --region sin --vm-size shared-cpu-1x --volume-size 1
fly postgres attach judgment-db -a judgment-api   # sets DATABASE_URL secret
# If the cluster was created at 256MB, scale immediately:
#   fly machine update <pg-machine-id> -a judgment-db --vm-memory 1024
# Enable backups (interactive ToS agree):
#   fly pg backup enable -a judgment-db
# Optional one-time data GC after launch / retention change:
#   fly postgres connect -a judgment-db < deployment/scripts/purge_finished_games.sql

# App secrets / env (see deployment/fly.env.example)
fly secrets set \
  ALLOWED_ORIGINS=https://judgment-lws-260731.web.app,https://judgment-lws-260731.firebaseapp.com \
  PUBLIC_WEB_ORIGIN=https://judgment-lws-260731.web.app \
  RAG_ENABLED=0 \
  HTTP_RATE_LIMIT=120 \
  HTTP_GUEST_RATE_LIMIT=20 \
  HTTP_RATE_WINDOW_SECS=60 \
  -a judgment-api

# Enable / confirm Fly Postgres backups (dashboard or provider docs) before public launch.

# First deploy (remote Docker build)
fly deploy -a judgment-api

# Verify
curl -fsS https://judgment-api.fly.dev/healthz
curl -fsS https://judgment-api.fly.dev/readyz
```

Public API base (no trailing slash): `https://judgment-api.fly.dev`

### 3. Firebase Hosting

```bash
npm install -g firebase-tools
firebase login
cd frontend/judgement_flutter
flutter build web --release --pwa-strategy=none --dart-define=API_BASE=https://judgment-api.fly.dev
firebase deploy --only hosting --project judgment-lws-260731
```

Hosting URL: `https://judgment-lws-260731.web.app`

### 4. GitHub Actions config

**Variables:**

| Name | Value |
|------|--------|
| `API_BASE` | `https://judgment-api.fly.dev` |
| `FIREBASE_PROJECT_ID` | `judgment-lws-260731` |
| `PUBLIC_WEB_ORIGIN` | `https://judgment-lws-260731.web.app` |

**Secrets:**

| Name | How to get |
|------|------------|
| `FIREBASE_TOKEN` | `firebase login:ci` |
| `FLY_API_TOKEN` | `fly tokens create deploy -a judgment-api` |

**Required:** Deploy fails if `FLY_API_TOKEN` or `FIREBASE_TOKEN` is missing (no silent skip).

Push to `main` runs CI; Deploy workflow runs after CI succeeds (`fly deploy` + Firebase Hosting).

---

## Ongoing deploys

```bash
fly deploy -a judgment-api
# or push to main (with FLY_API_TOKEN set)
```

### Change `API_BASE`

1. Note new Fly hostname / custom domain.
2. Update GitHub variable `API_BASE`.
3. Redeploy web (`flutter build web` + `firebase deploy` or Actions).
4. Update Fly secrets `PUBLIC_WEB_ORIGIN` / `ALLOWED_ORIGINS` if the web origin changed.

---

## Rollback

**API (Fly):** `fly releases -a judgment-api` then `fly deploy --image <previous>` or redeploy a known-good git SHA.

**Web (Firebase):** Hosting → Release history → roll back.

---

## Post-deploy migration check

After a deploy that includes new migrations, confirm columns exist (via `fly postgres connect -a judgment-db` or your SQL client):

```sql
-- 0006 avatars
SELECT column_name FROM information_schema.columns
  WHERE table_name = 'guest_sessions' AND column_name = 'avatar_id';
SELECT column_name FROM information_schema.columns
  WHERE table_name = 'room_players' AND column_name = 'avatar_id';

-- 0007 dealer bid restriction
SELECT column_name FROM information_schema.columns
  WHERE table_name = 'rooms' AND column_name = 'dealer_total_restriction';
```

Migrations run automatically on API boot (`JUDGEMENT_MIGRATIONS_DIR`).

---

## Smoke checklist (after first go-live)

1. Open Firebase URL → create room → second browser joins → play a few tricks (WSS).
2. Create room with dealer restriction OFF and ON; verify bidding when ON.
3. Mid-game: change avatar → hard refresh → avatar still set; reaction + typed emote appear for peers.
4. Scoreboard: round rows / player columns / full names; no Tot until finished.
5. Finish game → victory celebration → results tally + round matrix.
6. Kill network briefly → confirm Reconnect / actions work after reconnect.
7. Schedule event → open `/e/{slug}` in a fresh tab (SPA rewrite).
8. Manage → Copy WhatsApp text → Firebase origin + sensible local time.
9. `curl -fsS https://judgment-api.fly.dev/readyz` → 200.
10. `fly logs -a judgment-api` — no CORS failures; **no** raw `DATABASE_URL` in logs.

---

## Local production-shaped verify

```bash
# From judgement/
docker compose -f deployment/docker-compose.prod.yml up --build
```
