# Deploy runbook — GitHub + Railway + Firebase

Production layout:

- **API / WebSocket** → Railway (`judgement-server` Docker image)
- **Flutter Web** → Firebase Hosting
- **Postgres** → Railway Postgres plugin (`DATABASE_URL`)
- **CI/CD** → GitHub Actions (`.github/workflows/`)

WebSockets go **browser → Railway** directly (Firebase does not proxy WS).
`ALLOWED_ORIGINS` must list the Firebase origins.

---

## One-time bootstrap

### 1. GitHub

```bash
cd judgement   # this directory is the git root
git add -A
git commit -m "Initial commit: Judgement multiplayer card game"
# Create an empty GitHub repo, then:
git remote add origin git@github.com:<org-or-user>/judgement.git
git push -u origin main
```

### 2. Railway

1. New project → **Deploy from GitHub** (select this repo) **or** empty project + Dockerfile service.
2. Root directory: repo root (Dockerfile via [`railway.toml`](../../railway.toml)).
3. **Add Postgres** plugin; link `DATABASE_URL` into the API service
   (`${{Postgres.DATABASE_URL}}` or Railway’s variable reference UI).
4. Set variables from [`deployment/railway.env.example`](../../deployment/railway.env.example).
   Leave `ALLOWED_ORIGINS` / `PUBLIC_WEB_ORIGIN` empty until Firebase URL exists,
   or set temporary values and update after step 3.
5. Deploy → note public URL, e.g. `https://judgement-production.up.railway.app`
   (no trailing slash).
6. Verify: `curl -fsS https://<railway>/healthz` and `/readyz`.

### 3. Firebase Hosting

```bash
npm install -g firebase-tools
firebase login
# Create a Firebase project in console, enable Hosting, then:
cd frontend/judgement_flutter
firebase use --add   # updates .firebaserc (repo root + this dir have copies)
flutter build web --release --dart-define=API_BASE=https://<railway-host>
firebase deploy --only hosting --project <FIREBASE_PROJECT_ID>
```

Note the Hosting URL (`https://<project>.web.app`).

### 4. Wire origins

On Railway API service set:

| Variable | Example |
|----------|---------|
| `ALLOWED_ORIGINS` | `https://<project>.web.app,https://<project>.firebaseapp.com` |
| `PUBLIC_WEB_ORIGIN` | `https://<project>.web.app` |
| `RAG_ENABLED` | `0` |

Redeploy API if variables are not hot-reloaded.

### 5. GitHub Actions config

**Variables** (Settings → Secrets and variables → Actions → Variables):

| Name | Value |
|------|--------|
| `API_BASE` | `https://<railway-host>` |
| `FIREBASE_PROJECT_ID` | Firebase project id |
| `PUBLIC_WEB_ORIGIN` | `https://<project>.web.app` (smoke checks) |
| `RAILWAY_SERVICE_ID` | Optional; Railway service id for CLI deploy |

**Secrets:**

| Name | How to get |
|------|------------|
| `FIREBASE_TOKEN` | `firebase login:ci` |
| `RAILWAY_TOKEN` | Railway → Account → Tokens (skip if using Railway’s GitHub deploy only) |

Push to `main` runs CI then Deploy. Prefer **Railway GitHub integration** for the API
so every push rebuilds the Docker image; keep `RAILWAY_TOKEN` only if you use
`railway up` from Actions.

---

## Ongoing deploys

- Merge / push to `main` → `CI` + `Deploy` workflows.
- Manual: Actions → **Deploy** → Run workflow.

### Change `API_BASE`

1. Update Railway public domain (or custom domain).
2. Update GitHub variable `API_BASE`.
3. Redeploy web (`Deploy` workflow or local `flutter build web` + `firebase deploy`).
4. Update Railway `PUBLIC_WEB_ORIGIN` / `ALLOWED_ORIGINS` if the web origin changed.

---

## Rollback

**API (Railway):** Deployments → select previous successful deploy → **Redeploy**.

**Web (Firebase):** Hosting → Release history → roll back to prior release.

**Bad env var:** revert the variable in Railway / GitHub and redeploy the affected side.

---

## Smoke checklist (after first go-live)

1. Open Firebase URL → create room → second browser joins → play a few tricks (WSS).
2. Schedule event → open `/e/{slug}` in a fresh tab (SPA rewrite).
3. Manage → Copy WhatsApp text → URL uses `PUBLIC_WEB_ORIGIN` / browser origin; time looks correct.
4. `curl -fsS "$API_BASE/readyz"` → 200.
5. Railway dashboard: Postgres backups enabled; logs show no CORS failures.

---

## Local production-shaped verify

```bash
# From judgement/
docker compose -f deployment/docker-compose.prod.yml up --build
```
