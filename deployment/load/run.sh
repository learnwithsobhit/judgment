#!/usr/bin/env bash
# Run a k6 load scenario against a Judgement API.
# Default: local ephemeral. Production requires ALLOW_PROD_LOAD=1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SCENARIO="${1:-smoke_ws}"
API_BASE="${API_BASE:-http://127.0.0.1:8080}"
THRESHOLDS_PROFILE="${THRESHOLDS_PROFILE:-ci}"

# Strip trailing slash.
API_BASE="${API_BASE%/}"
export API_BASE
export THRESHOLDS_PROFILE

is_prod_host() {
  local host="$1"
  case "$host" in
    *judgment-api.fly.dev*|*judgement-api.fly.dev*|*.fly.dev*)
      return 0
      ;;
  esac
  return 1
}

if is_prod_host "$API_BASE"; then
  if [[ "${ALLOW_PROD_LOAD:-}" != "1" ]]; then
    echo "REFUSED: API_BASE=$API_BASE looks like production." >&2
    echo "Set ALLOW_PROD_LOAD=1 only for the manual prod smoke workflow / intentional soak." >&2
    exit 2
  fi
  if [[ "$SCENARIO" != "smoke_prod" ]]; then
    echo "REFUSED: production host only allows scenario 'smoke_prod' (got '$SCENARIO')." >&2
    exit 2
  fi
  export OMIT_SEED=1
  # GH → sin RTT is noisy; always use the remote profile on Fly.
  export THRESHOLDS_PROFILE=prod_remote
fi

SCRIPT="$ROOT/k6/scenarios/${SCENARIO}.js"
if [[ ! -f "$SCRIPT" ]]; then
  echo "Unknown scenario '$SCENARIO'. Expected one of:" >&2
  ls "$ROOT/k6/scenarios"/*.js | xargs -n1 basename | sed 's/\.js$//' >&2
  exit 1
fi

if ! command -v k6 >/dev/null 2>&1; then
  echo "k6 not found in PATH. Install: https://grafana.com/docs/k6/latest/set-up/install-k6/" >&2
  exit 1
fi

echo "Load scenario=${SCENARIO} API_BASE=${API_BASE} THRESHOLDS_PROFILE=${THRESHOLDS_PROFILE}"

# Preflight
if ! curl -fsS --max-time 10 "${API_BASE}/readyz" | grep -qi ready; then
  echo "FAIL: ${API_BASE}/readyz not ready" >&2
  exit 1
fi

K6_ARGS=(
  run
  --summary-export="${K6_SUMMARY:-$ROOT/k6-summary.json}"
  -e "API_BASE=${API_BASE}"
  -e "THRESHOLDS_PROFILE=${THRESHOLDS_PROFILE}"
  -e "OMIT_SEED=${OMIT_SEED:-0}"
  -e "FULL_SCHEDULE=${FULL_SCHEDULE:-0}"
)
if [[ -n "${TABLES:-}" ]]; then K6_ARGS+=(-e "TABLES=${TABLES}"); fi
if [[ -n "${SEATS:-}" ]]; then K6_ARGS+=(-e "SEATS=${SEATS}"); fi
K6_ARGS+=("$SCRIPT")

k6 "${K6_ARGS[@]}"

echo "LOAD_OK scenario=${SCENARIO}"
