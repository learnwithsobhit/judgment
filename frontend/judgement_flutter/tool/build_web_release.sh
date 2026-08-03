#!/usr/bin/env bash
# Production Flutter web build + cache-bust stamp.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

API_BASE="${API_BASE:-https://judgment-api.fly.dev}"
APP_VERSION="$(sed -n 's/^version:[[:space:]]*\([^+]*\).*/\1/p' pubspec.yaml | head -1)"
APP_VERSION="${APP_VERSION:-1.0.0}"
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%d%H%M%S)}"
if command -v git >/dev/null 2>&1 && git rev-parse --short HEAD >/dev/null 2>&1; then
  BUILD_ID="${BUILD_ID}-$(git rev-parse --short HEAD)"
fi

echo "Building web APP_VERSION=$APP_VERSION APP_BUILD_ID=$BUILD_ID API_BASE=$API_BASE"
flutter build web --release --pwa-strategy=none \
  --dart-define=API_BASE="$API_BASE" \
  --dart-define=APP_VERSION="$APP_VERSION" \
  --dart-define=APP_BUILD_ID="$BUILD_ID"

chmod +x "$ROOT/tool/stamp_web_build.sh"
"$ROOT/tool/stamp_web_build.sh" "$BUILD_ID" "$APP_VERSION"
