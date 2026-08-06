# Dehla shell Firebase hosting (ADR 0006)

Dehla invite links use `/dp/r/{CODE}` and must be served by **`shell_flutter`**, not the Judgement SPA.

Judgement hosting (`judgment-railway-test` / prod) is **unchanged** by this runbook.

## One-time Firebase setup

Create a Hosting site in the same project:

```bash
firebase hosting:sites:create dehla-railway-test --project judgment-lws-260731
```

Apply the target from [`frontend/shell_flutter/.firebaserc`](../../frontend/shell_flutter/.firebaserc):

```bash
cd frontend/shell_flutter
firebase target:apply hosting dehla-railway-test dehla-railway-test --project judgment-lws-260731
```

## Build + deploy

```bash
export DEHLA_API_BASE=https://<your-dehla-railway-api>
export PUBLIC_WEB_ORIGIN=https://dehla-railway-test.web.app

cd frontend/shell_flutter
chmod +x tool/build_web_release.sh
./tool/build_web_release.sh

firebase deploy --only hosting:dehla-railway-test --project judgment-lws-260731
```

## Smoke checks

1. Open `https://dehla-railway-test.web.app/` → game picker.
2. Open `/dp` → Dehla home.
3. Create a room (Terms checked) → Copy join link → path is `/dp/r/{CODE}` on the **shell** origin.
4. Open the link in a private window → Dehla join with code prefilled + legal gate.
5. Confirm Judgement `https://judgment-railway-test.web.app/r/{CODE}` still opens Judgement (unchanged).

## Local invites

When running shell locally, invite URLs use `Uri.base.origin` (e.g. `http://localhost:xxxxx/dp/r/CODE`) so friends on the same machine/network stay on Dehla — never the Judgement Firebase host.
