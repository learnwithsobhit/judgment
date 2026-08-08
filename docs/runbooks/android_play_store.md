# Android Play Store runbook — Judgement

Native Flutter Android app: `frontend/judgement_flutter`  
Package / applicationId: `com.judgement.game`  
Play Console account: `chaturvedi99@gmail.com`

Privacy (public URL for Play listing):
`https://judgment-lws-260731.web.app/privacy/`

Terms:
`https://judgment-lws-260731.web.app/terms/`

---

## One-time: upload keystore

Run from `frontend/judgement_flutter`:

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
mkdir -p android/keystore
keytool -genkeypair -v \
  -keystore android/keystore/upload-keystore.p12 \
  -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload \
  -storepass YOUR_STORE_PASSWORD \
  -keypass YOUR_KEY_PASSWORD \
  -dname "CN=Judgement, OU=Mobile, O=Judgement, L=City, ST=State, C=IN"
```

Create `android/key.properties` (gitignored):

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=keystore/upload-keystore.p12
```

**Back up** `upload-keystore.p12` and the passwords offline. Losing the upload key blocks updates unless you use Play App Signing recovery. A local upload keystore was generated on this machine under `android/keystore/` (not committed).

---

## Build release AAB

```bash
cd frontend/judgement_flutter
chmod +x tool/build_android_release.sh
./tool/build_android_release.sh
```

Output:

`build/app/outputs/bundle/release/app-release.aab`

Version comes from `pubspec.yaml` (`version: 1.0.0+2` → versionName `1.0.0`, versionCode `2`). Bump the `+N` integer for every Play upload.

Android release defaults to the **Railway** stack:

- `API_BASE=https://judgement-server-production-311f.up.railway.app`
- `PUBLIC_WEB_ORIGIN=https://judgment-railway-test.web.app` (share `/r/CODE` links)

Override for Fly prod if needed:

```bash
API_BASE=https://judgment-api.fly.dev \
PUBLIC_WEB_ORIGIN=https://judgment-lws-260731.web.app \
  ./tool/build_android_release.sh
```

Keep join links on the same stack: deploy Railway web with
`docs/runbooks/railway_firebase_test.md` so `judgment-railway-test.web.app` also uses Railway.

---

## Play Console checklist

1. Create app **Judgement**, package `com.judgement.game`, free, Games category.
2. Store listing: short/full description, icon (512), feature graphic (`web/og-image.png` is a starting point), phone screenshots.
3. Privacy policy URL: `https://judgment-lws-260731.web.app/privacy/`
4. Content rating questionnaire (card game / social — declare mic + optional phone for RSVP).
5. Data safety: nickname, session token, optional RSVP phone, ephemeral voice notes, microphone.
6. Upload AAB to **Internal testing** first; add tester Gmail; install via Play link.
7. Smoke: create/join room, play a hand, voice note, kill app + reclaim.
8. Promote to Production when Internal testing passes (first review can take days).

---

## Deploy privacy/terms pages

Static pages live under `frontend/judgement_flutter/web/privacy/` and `web/terms/`.  
They ship with the normal Firebase web deploy (`./tool/build_web_release.sh` then `firebase deploy --only hosting:prod`).

---

## Local Android debug (Railway)

```bash
cd frontend/judgement_flutter
flutter run -d <deviceId> \
  --dart-define=API_BASE=https://judgement-server-production-311f.up.railway.app \
  --dart-define=PUBLIC_WEB_ORIGIN=https://judgment-railway-test.web.app
```
