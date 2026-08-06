#!/usr/bin/env bash
# Build Table Games shell (embeds Judgement UI; API stays on Judgement backend).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

API_BASE="${API_BASE:-https://judgement-server-production-311f.up.railway.app}"
PUBLIC_WEB_ORIGIN="${PUBLIC_WEB_ORIGIN:-https://table-games.web.app}"

echo "API_BASE=$API_BASE"
echo "PUBLIC_WEB_ORIGIN=$PUBLIC_WEB_ORIGIN"

flutter pub get
flutter build web --release \
  --dart-define=API_BASE="$API_BASE" \
  --dart-define=PUBLIC_WEB_ORIGIN="$PUBLIC_WEB_ORIGIN"

echo "Built build/web — deploy with:"
echo "  firebase deploy --only hosting:table-games --project judgment-lws-260731"
echo "Ensure Judgement ALLOWED_ORIGINS includes:"
echo "  https://table-games.web.app,https://table-games.firebaseapp.com"
