# Railway + second Firebase Hosting site (test stack)

Parallel environment for experimenting with Railway as the API host.  
**Production** stays on Fly + default Hosting site — do not point prod traffic here.

## Accounts

| Piece | Where |
|-------|--------|
| API + Postgres | **Separate Railway account** (not the personal/dev account used for other projects) |
| Web | Same Firebase project `judgment-lws-260731`, Hosting site **`judgment-railway-test`** |
| Prod web | Hosting site **`judgment-lws-260731`** → Fly `judgment-api.fly.dev` |

Test site URL: https://judgment-railway-test.web.app  
Railway API: https://judgement-server-production-311f.up.railway.app  
Railway account: `chaturvedipriya23@gmail.com` · project `judgment-api-railway-test` · region asia-southeast (as configured in dashboard)

## Deploy commands (safe)

Always name the Hosting **target**:

```bash
# TEST — Railway API baked in
cd frontend/judgement_flutter
API_BASE=https://judgement-server-production-311f.up.railway.app \
PUBLIC_WEB_ORIGIN=https://judgment-railway-test.web.app \
  ./tool/build_web_release.sh
firebase deploy --only hosting:railway-test --project judgment-lws-260731

# PROD — Fly API (CI uses hosting:prod)
API_BASE=https://judgment-api.fly.dev \
PUBLIC_WEB_ORIGIN=https://judgment-lws-260731.web.app \
  ./tool/build_web_release.sh
firebase deploy --only hosting:prod --project judgment-lws-260731
```

`PUBLIC_WEB_ORIGIN` stamps Open Graph / Twitter absolute URLs and the `og-image.png` footer host so WhatsApp previews match the site you deployed.

Never run bare `firebase deploy --only hosting` after multi-site is enabled (deploys all sites).

## Railway setup (on the test account)

```bash
railway login          # must show the test account email
railway init -n judgment-api-railway-test
railway add -d postgres
railway add -s judgement-server
# link service, set variables (see deployment/railway.env.example):
#   DATABASE_URL=${{Postgres….DATABASE_URL}}
#   ALLOWED_ORIGINS=https://judgment-railway-test.web.app,https://judgment-railway-test.firebaseapp.com
#   PUBLIC_WEB_ORIGIN=https://judgment-railway-test.web.app
#   RAG_ENABLED=0
#   JUDGEMENT_MIGRATIONS_DIR=/srv/migrations/persistence
railway up -s judgement-server
railway domain -s judgement-server
```

Keep **replicas = 1**, disable app sleep. Set a monthly spend limit.

## Tear-down / pause

Pause or delete the Railway project when not testing to avoid always-on charges.  
Firebase site `judgment-railway-test` can remain empty or be deleted from the console.

## Isolation checklist

1. Prod URL network tab → `judgment-api.fly.dev`
2. Test URL network tab → `*.up.railway.app` (or custom Railway domain)
3. Fly secrets unchanged
4. GH variable `API_BASE` still Fly for prod CI
