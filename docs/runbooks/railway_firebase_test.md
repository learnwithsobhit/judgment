# Railway + Firebase (test stack)

Default development / Android test environment:

| Piece | Value |
|-------|--------|
| API | https://judgement-server-production-311f.up.railway.app |
| Web | https://judgment-railway-test.web.app |
| Firebase Auth project | **`judgment-railway-test`** (`FIREBASE_PROJECT_ID`) |
| Hosting deploy | Site `judgment-railway-test` (Firebase target `railway-test`; parent project may still be `judgment-lws-260731` for Hosting only) |

Prod (Fly + `judgment-lws-260731` Hosting) is separate — set `API_BASE` / `PUBLIC_WEB_ORIGIN` explicitly when deploying prod.

## Auth setup

1. In Firebase Console → project **`judgment-railway-test`**: enable **Google** and **Apple** sign-in.
2. Register Web + Android apps; run:
   ```bash
   cd frontend/judgement_flutter
   flutterfire configure --project=judgment-railway-test --platforms=web,android
   ```
3. On Railway API service, set:
   ```text
   FIREBASE_PROJECT_ID=judgment-railway-test
   ALLOWED_ORIGINS=https://judgment-railway-test.web.app,https://judgment-railway-test.firebaseapp.com
   PUBLIC_WEB_ORIGIN=https://judgment-railway-test.web.app
   ```
   (See `deployment/railway.env.example`.)

Auth tokens are verified against `FIREBASE_PROJECT_ID`; it must match the project that issues the client ID tokens.

## Deploy commands

```bash
# TEST — Railway API + railway-test Hosting
cd frontend/judgement_flutter
API_BASE=https://judgement-server-production-311f.up.railway.app \
PUBLIC_WEB_ORIGIN=https://judgment-railway-test.web.app \
  ./tool/build_web_release.sh
# Hosting target still lives under judgment-lws-260731 in .firebaserc today:
firebase deploy --only hosting:railway-test --project judgment-lws-260731

# PROD — Fly API (override defaults)
API_BASE=https://judgment-api.fly.dev \
PUBLIC_WEB_ORIGIN=https://judgment-lws-260731.web.app \
  ./tool/build_web_release.sh
firebase deploy --only hosting:prod --project judgment-lws-260731
```

`PUBLIC_WEB_ORIGIN` stamps Open Graph / Twitter absolute URLs and the `og-image.png` footer host so WhatsApp previews match the site you deployed.

Never run bare `firebase deploy --only hosting` after multi-site is enabled (deploys all sites).

## Flutter / Android against Railway

```bash
# Web
flutter run -d chrome \
  --dart-define=API_BASE=https://judgement-server-production-311f.up.railway.app \
  --dart-define=PUBLIC_WEB_ORIGIN=https://judgment-railway-test.web.app

# Android AAB (script defaults already Railway + railway-test)
./tool/build_android_release.sh
```

## Railway variables checklist

```bash
railway login
# select judgment-api-railway-test
# Variables (see deployment/railway.env.example):
#   DATABASE_URL=${{Postgres….DATABASE_URL}}
#   ALLOWED_ORIGINS=https://judgment-railway-test.web.app,https://judgment-railway-test.firebaseapp.com
#   PUBLIC_WEB_ORIGIN=https://judgment-railway-test.web.app
#   FIREBASE_PROJECT_ID=judgment-railway-test
#   RAG_ENABLED=0
#   JUDGEMENT_MIGRATIONS_DIR=/srv/migrations/persistence
```

Keep **replicas = 1**, disable app sleep. Set a monthly spend limit.

## Isolation checklist

1. Prod URL network tab → `judgment-api.fly.dev`
2. Test URL network tab → `*.up.railway.app`
3. Auth ID tokens `aud` / `iss` → `judgment-railway-test`
4. Fly secrets unchanged for prod
