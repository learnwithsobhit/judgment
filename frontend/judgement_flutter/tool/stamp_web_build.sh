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

PUBLIC_WEB_ORIGIN="${PUBLIC_WEB_ORIGIN:-https://judgment-lws-260731.web.app}"
PUBLIC_WEB_ORIGIN="${PUBLIC_WEB_ORIGIN%/}"

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

  # Open Graph / Twitter absolute URLs for the deploying site.
  if grep -q '__WEB_ORIGIN__' "$INDEX"; then
    sed -i.bak "s|__WEB_ORIGIN__|${PUBLIC_WEB_ORIGIN}|g" "$INDEX"
  elif grep -q 'content="WEB_ORIGIN' "$INDEX"; then
    sed -i.bak "s|WEB_ORIGIN|${PUBLIC_WEB_ORIGIN}|g" "$INDEX"
  else
    # Already-stamped or legacy hardcoded prod — rewrite known absolute OG URLs.
    sed -i.bak -E \
      "s|https://judgment-[a-z0-9.-]+\.web\.app|${PUBLIC_WEB_ORIGIN}|g" \
      "$INDEX"
  fi
  rm -f "${INDEX}.bak"
  echo "stamped OG origin $PUBLIC_WEB_ORIGIN"
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

# Stamp share-preview image footer with this site's host (Pillow optional).
OG_IMAGE="$WEB/og-image.png"
if [[ -f "$OG_IMAGE" ]]; then
  export STAMP_OG_IMAGE="$OG_IMAGE"
  export STAMP_WEB_ORIGIN="$PUBLIC_WEB_ORIGIN"
  python3 - <<'PY' || echo "stamp_web_build: skip og-image footer (Pillow unavailable)"
import os
from pathlib import Path
from urllib.parse import urlparse

path = Path(os.environ["STAMP_OG_IMAGE"])
origin = os.environ["STAMP_WEB_ORIGIN"].rstrip("/")
host = urlparse(origin).netloc or origin.replace("https://", "").replace("http://", "")
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    raise SystemExit(1)

im = Image.open(path).convert("RGB")
w, h = im.size
draw = ImageDraw.Draw(im)
bg = (15, 55, 18)
draw.rectangle([60, 490, w - 60, 610], fill=bg)

font = None
for candidate in (
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
):
    try:
        font = ImageFont.truetype(candidate, 26)
        break
    except Exception:
        pass
if font is None:
    font = ImageFont.load_default()

text = f"{host}  ·  #JudgementTable"
bbox = draw.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
draw.text(((w - tw) // 2, 545), text, fill=(210, 195, 140), font=font)
im.save(path, optimize=True)
print(f"stamped og-image.png footer host={host}")
PY
fi

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
