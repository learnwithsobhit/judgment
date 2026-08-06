# Table Games Firebase Hosting

**Table Games** ([https://table-games.web.app](https://table-games.web.app)) is the product home. Judgement UI is **embedded** in this SPA; the Judgement **API** stays on Railway/Fly.

## Sites (project `judgment-lws-260731`)

| Hosting target | Site ID | URL | Role |
|---|---|---|---|
| `table-games` | `table-games` | https://table-games.web.app | Shell + embedded Judgement |
| `railway-test` | `judgment-railway-test` | https://judgment-railway-test.web.app | Legacy Judgement-only (optional) |
| `prod` | `judgment-lws-260731` | https://judgment-lws-260731.web.app | Legacy Judgement-only (optional) |

## CORS (required before embed Play works)

Add to Judgement server `ALLOWED_ORIGINS`:

```text
https://table-games.web.app,https://table-games.firebaseapp.com
```

(keep existing Judgement Hosting origins if those sites stay live)

## Build & deploy

```bash
cd frontend/shell_flutter

API_BASE=https://judgement-server-production-311f.up.railway.app \
PUBLIC_WEB_ORIGIN=https://table-games.web.app \
  ./tool/build_web_release.sh

firebase deploy --only hosting:table-games --project judgment-lws-260731
```

Never run bare `firebase deploy --only hosting`.

## Deep links

| Path | Meaning |
|---|---|
| `/` | Table Games home |
| `/j` | Judgement desk (create/join) |
| `/j/r/{CODE}` | **Join desk with code filled** (invite URL) |
| `/r/{CODE}` | 302 → `/j/r/{CODE}` (legacy alias) |

Share links must be `https://table-games.web.app/j/r/{CODE}`. SPA rewrite keeps the path so GoRouter opens the join desk (do not 302 `/j/r/...` to bare `index.html`).

## Smoke checklist

1. Home → Play Judgement (no navigation to judgment-railway-test)
2. Who’s playing → nick saved → desk
3. Create room → share URL contains `table-games.web.app/j/r/`
4. Open invite link → join desk with code (not bare home)
5. Results → **Back to Table Games** → home
6. Leave lobby / leave table → home
7. Second visit: nick remembered; join focuses on room code
8. Continue rail only if reclaim valid
