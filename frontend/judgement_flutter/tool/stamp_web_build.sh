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
  # Prefer stamping WINDOW_APP_BUILD_ID; bootstrap JS uses that variable.
  if grep -q "WINDOW_APP_BUILD_ID = 'BUILD_ID'" "$INDEX"; then
    sed -i.bak "s/WINDOW_APP_BUILD_ID = 'BUILD_ID'/WINDOW_APP_BUILD_ID = '${BUILD_ID}'/g" "$INDEX"
  elif grep -q "WINDOW_APP_BUILD_ID = '" "$INDEX"; then
    sed -i.bak "s/WINDOW_APP_BUILD_ID = '[^']*'/WINDOW_APP_BUILD_ID = '${BUILD_ID}'/g" "$INDEX"
  fi

  # Legacy / alternate templates that hardcode bootstrap ?v=BUILD_ID.
  if grep -q 'flutter_bootstrap\.js?v=BUILD_ID' "$INDEX"; then
    sed -i.bak "s/flutter_bootstrap\.js?v=BUILD_ID/flutter_bootstrap.js?v=${BUILD_ID}/g" "$INDEX"
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

echo "stamped WINDOW_APP_BUILD_ID + version.json build_id=$BUILD_ID"

# Per-deploy 302 destinations so Safari cannot reuse a disk-cached `/` document.
FIREBASE_JSON="$ROOT/firebase.json"
export STAMP_FIREBASE_JSON="$FIREBASE_JSON"
if [[ -f "$FIREBASE_JSON" ]]; then
  python3 - <<'PY'
from pathlib import Path
import os, re
path = Path(os.environ["STAMP_FIREBASE_JSON"])
build_id = os.environ["STAMP_BUILD_ID"]
text = path.read_text()
new = re.sub(
    r'("/index\.html\?_b=)[^"&]+',
    lambda m: m.group(1) + build_id,
    text,
)
new = new.replace("/index.html?_b=BUILD_ID", f"/index.html?_b={build_id}")
if new != text:
    path.write_text(new)
    print(f"stamped firebase.json redirects _b={build_id}")
else:
    print("firebase.json redirects unchanged")
PY
fi
