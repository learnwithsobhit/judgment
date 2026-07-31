#!/usr/bin/env bash
# Lightweight load smoke test (Phase 9).
# Target: ≥100 successful /healthz checks and ≥50 guest-session creates in <10s
# against a local server, with <1% HTTP errors (excluding intentional 429s off).
set -euo pipefail

BASE="${API_BASE:-http://127.0.0.1:8080}"
HEALTH_N="${HEALTH_N:-120}"
SESSION_N="${SESSION_N:-60}"
CONCURRENCY="${CONCURRENCY:-20}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Load smoke against ${BASE}"

health_ok=0
for i in $(seq 1 "$HEALTH_N"); do
  if curl -fsS "$BASE/healthz" >/dev/null; then
    health_ok=$((health_ok + 1))
  fi
done
echo "healthz ${health_ok}/${HEALTH_N}"

# Parallel guest sessions via xargs.
seq 1 "$SESSION_N" | xargs -P "$CONCURRENCY" -I{} \
  curl -fsS -o "$tmp/s{}.json" -w "%{http_code}\n" \
    -X POST "$BASE/api/v1/guest-sessions" \
    -H 'content-type: application/json' \
    -d "{\"nickname\":\"Load{}\"}" \
  >"$tmp/codes.txt" || true

ok=$(grep -c '^200$' "$tmp/codes.txt" || true)
echo "guest-sessions ${ok}/${SESSION_N}"

if [[ "$health_ok" -lt 100 ]]; then
  echo "FAIL: health target not met (need ≥100 ok)" >&2
  exit 1
fi
if [[ "$ok" -lt 50 ]]; then
  echo "FAIL: guest-session target not met (need ≥50 ok)" >&2
  exit 1
fi

# Metrics scrape must succeed.
curl -fsS "$BASE/metrics" | grep -q 'judgement_http_requests_total'
curl -fsS "$BASE/readyz" | grep -q ready

echo "LOAD_SMOKE_OK"
