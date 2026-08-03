#!/usr/bin/env bash
# Stamp build/web after `flutter build web` so browsers fetch a fresh bootstrap
# and version.json exposes a unique build_id for update checks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ROOT/build/web"
BUILD_ID="${1:-}"
APP_VERSION="${2:-}"

if [[ ! -d "$WEB" ]]; then
  echo "stamp_web_build: missing $WEB (run flutter build web first)" >&2
  exit 1
fi

if [[ -z "$BUILD_ID" ]]; then
  BUILD_ID="$(date -u +%Y%m%d%H%M%S)"
fi

if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="$(sed -n 's/^version:[[:space:]]*\([^+]*\).*/\1/p' "$ROOT/pubspec.yaml" | head -1)"
  APP_VERSION="${APP_VERSION:-0.0.0}"
fi

INDEX="$WEB/index.html"
if [[ -f "$INDEX" ]]; then
  if grep -q 'flutter_bootstrap\.js?v=BUILD_ID' "$INDEX"; then
    sed -i.bak "s/flutter_bootstrap\.js?v=BUILD_ID/flutter_bootstrap.js?v=${BUILD_ID}/g" "$INDEX"
  elif grep -q 'flutter_bootstrap\.js?v=' "$INDEX"; then
    sed -i.bak "s/flutter_bootstrap\.js?v=[^\"]*/flutter_bootstrap.js?v=${BUILD_ID}/g" "$INDEX"
  elif grep -q 'flutter_bootstrap\.js"' "$INDEX"; then
    sed -i.bak "s/flutter_bootstrap\.js\"/flutter_bootstrap.js?v=${BUILD_ID}\"/g" "$INDEX"
  fi
  rm -f "${INDEX}.bak"
fi

VERSION_JSON="$WEB/version.json"
export STAMP_BUILD_ID="$BUILD_ID"
export STAMP_APP_VERSION="$APP_VERSION"
export STAMP_VERSION_JSON="$VERSION_JSON"
python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["STAMP_VERSION_JSON"])
build_id = os.environ["STAMP_BUILD_ID"]
app_version = os.environ["STAMP_APP_VERSION"]
if path.exists():
    data = json.loads(path.read_text())
else:
    data = {}
data["version"] = data.get("version") or app_version
data["build_id"] = build_id
path.write_text(json.dumps(data))
print(f"stamped version.json build_id={build_id} version={data.get('version')}")
PY

echo "stamped bootstrap ?v=$BUILD_ID"
