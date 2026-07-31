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

# Managed Postgres (pick a region close to the app; sin = Singapore)
fly postgres create --name judgment-db --region sin --vm-size shared-cpu-1x --volume-size 1
fly postgres attach judgment-db -a judgment-api   # sets DATABASE_URL secret

# App secrets / env (see deployment/fly.env.example)
fly secrets set \
  ALLOWED_ORIGINS=https://judgment-lws-260731.web.app,https://judgment-lws-260731.firebaseapp.com \
  PUBLIC_WEB_ORIGIN=https://judgment-lws-260731.web.app \
  RAG_ENABLED=0 \
  -a judgment-api

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
flutter build web --release --dart-define=API_BASE=https://judgment-api.fly.dev
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

## Smoke checklist (after first go-live)

1. Open Firebase URL → create room → second browser joins → play a few tricks (WSS).
2. Schedule event → open `/e/{slug}` in a fresh tab (SPA rewrite).
3. Manage → Copy WhatsApp text → Firebase origin + sensible local time.
4. `curl -fsS https://judgment-api.fly.dev/readyz` → 200.
5. `fly logs -a judgment-api` — no CORS failures.

---

## Local production-shaped verify

```bash
# From judgement/
docker compose -f deployment/docker-compose.prod.yml up --build
```
