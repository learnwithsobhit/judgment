#!/usr/bin/env bash
# Flutter Android App Bundle for Play Store — Railway API stack.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Railway test API + matching Firebase Hosting site (join links /r/CODE).
API_BASE="${API_BASE:-https://judgement-server-production-311f.up.railway.app}"
PUBLIC_WEB_ORIGIN="${PUBLIC_WEB_ORIGIN:-https://judgment-railway-test.web.app}"
PUBLIC_WEB_ORIGIN="${PUBLIC_WEB_ORIGIN%/}"

APP_VERSION="$(sed -n 's/^version:[[:space:]]*\([^+]*\).*/\1/p' pubspec.yaml | head -1)"
APP_VERSION="${APP_VERSION:-1.0.0}"
BUILD_ID="${BUILD_ID:-$(date -u +%Y%m%d%H%M%S)}"
if command -v git >/dev/null 2>&1 && git rev-parse --short HEAD >/dev/null 2>&1; then
  BUILD_ID="${BUILD_ID}-$(git rev-parse --short HEAD)"
fi

# Prefer Android Studio JBR when JAVA_HOME is unset.
if [[ -z "${JAVA_HOME:-}" && -x "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"

if [[ ! -f "$ROOT/android/key.properties" ]]; then
  echo "WARNING: android/key.properties missing — release will fall back to debug signing." >&2
  echo "See docs/runbooks/android_play_store.md to create an upload keystore." >&2
fi

echo "Building Android App Bundle APP_VERSION=$APP_VERSION APP_BUILD_ID=$BUILD_ID"
echo "  API_BASE=$API_BASE"
echo "  PUBLIC_WEB_ORIGIN=$PUBLIC_WEB_ORIGIN"
flutter build appbundle --release \
  --dart-define=API_BASE="$API_BASE" \
  --dart-define=PUBLIC_WEB_ORIGIN="$PUBLIC_WEB_ORIGIN" \
  --dart-define=APP_VERSION="$APP_VERSION" \
  --dart-define=APP_BUILD_ID="$BUILD_ID"

echo "AAB: $ROOT/build/app/outputs/bundle/release/app-release.aab"
