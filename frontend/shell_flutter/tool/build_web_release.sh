#!/usr/bin/env bash
# Build shell_flutter web for Dehla hosting (does not touch Judgement deploy).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${PUBLIC_WEB_ORIGIN:=https://dehla-railway-test.web.app}"
: "${DEHLA_API_BASE:?Set DEHLA_API_BASE to the Dehla API origin}"
: "${APP_VERSION:=0.1.0}"

flutter pub get
flutter build web --release \
  --dart-define=PUBLIC_WEB_ORIGIN="$PUBLIC_WEB_ORIGIN" \
  --dart-define=DEHLA_API_BASE="$DEHLA_API_BASE" \
  --dart-define=APP_VERSION="$APP_VERSION"

echo "Built shell web → $ROOT/build/web"
echo "PUBLIC_WEB_ORIGIN=$PUBLIC_WEB_ORIGIN"
echo "DEHLA_API_BASE=$DEHLA_API_BASE"
