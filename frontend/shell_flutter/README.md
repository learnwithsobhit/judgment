# Table Games

Flutter Web shell — brand home, shared nickname, and **in-app** Judgement (not a link-out).

- Home: [https://table-games.web.app](https://table-games.web.app)
- Judgement Play → `/j` (embedded module)
- Invites: `/j/r/{CODE}`
- Backend: Judgement API via `API_BASE` (independent)

See [docs/runbooks/table_games_firebase.md](../../docs/runbooks/table_games_firebase.md).

```bash
./tool/build_web_release.sh
firebase deploy --only hosting:table-games --project judgment-lws-260731
```

**CORS:** Judgement `ALLOWED_ORIGINS` must include `https://table-games.web.app` and `https://table-games.firebaseapp.com`.
