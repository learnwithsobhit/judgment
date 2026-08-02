#!/usr/bin/env bash
# One-command local load test: Postgres + API + HTTP smoke + k6 scenario.
#
# Usage:
#   ./deployment/load/local.sh                 # smoke_ws (default)
#   ./deployment/load/local.sh comfort
#   ./deployment/load/local.sh target
#   THRESHOLDS_PROFILE=strict ./deployment/load/local.sh target
#   ./deployment/load/local.sh --memory smoke_ws   # no Postgres (in-memory store)
#   ./deployment/load/local.sh --reset-db smoke_ws # wipe local compose Postgres volume
#   ./deployment/load/local.sh --kill-port         # free PORT if something else holds it
#   PORT=8081 ./deployment/load/local.sh comfort   # use another port
#   ./deployment/load/local.sh --keep-api smoke_ws # leave API running after
#   ./deployment/load/local.sh --http-only         # smoke.sh only, no k6
#
set -euo pipefail

LOAD_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$LOAD_DIR/../.." && pwd)"
BACKEND="$REPO_ROOT/backend"

SCENARIO="smoke_ws"
USE_POSTGRES=1
RESET_DB=0
KILL_PORT=0
KEEP_API=0
HTTP_ONLY=0
SKIP_HTTP_SMOKE=0
PORT="${PORT:-8080}"
THRESHOLDS_PROFILE="${THRESHOLDS_PROFILE:-ci}"
DATABASE_URL="${DATABASE_URL:-postgres://judgement:judgement@127.0.0.1:5434/judgement}"

STARTED_API=0
API_PID=""
LOG_FILE="${TMPDIR:-/tmp}/judgement-load-api.log"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --memory) USE_POSTGRES=0; shift ;;
    --reset-db) RESET_DB=1; shift ;;
    --kill-port) KILL_PORT=1; shift ;;
    --keep-api) KEEP_API=1; shift ;;
    --http-only) HTTP_ONLY=1; shift ;;
    --skip-http-smoke) SKIP_HTTP_SMOKE=1; shift ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      SCENARIO="$1"
      shift
      ;;
  esac
done

# Resolve API_BASE after flags (PORT may be set in the environment).
API_BASE="${API_BASE:-http://127.0.0.1:${PORT}}"
API_BASE="${API_BASE%/}"
export API_BASE
export THRESHOLDS_PROFILE
export PORT

cleanup() {
  local code=$?
  if [[ "$STARTED_API" -eq 1 && "$KEEP_API" -eq 0 && -n "$API_PID" ]]; then
    echo "Stopping API (pid ${API_PID})..."
    kill "$API_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
  elif [[ "$STARTED_API" -eq 1 && "$KEEP_API" -eq 1 ]]; then
    echo "Leaving API running (pid ${API_PID}) log=${LOG_FILE}"
  fi
  exit "$code"
}
trap cleanup EXIT

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

api_ready() {
  curl -fsS --max-time 2 "${API_BASE}/readyz" 2>/dev/null | grep -qi ready
}

port_pids() {
  lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN -t 2>/dev/null || true
}

describe_port() {
  lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null || echo "(nothing listening)"
}

kill_port_listeners() {
  local pids
  pids="$(port_pids)"
  if [[ -z "$pids" ]]; then
    return 0
  fi
  echo "==> Freeing port ${PORT} (pids: $(echo "$pids" | tr '\n' ' '))"
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 1
  pids="$(port_pids)"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
    sleep 0.5
  fi
  if [[ -n "$(port_pids)" ]]; then
    echo "Could not free port ${PORT}:" >&2
    describe_port >&2
    exit 1
  fi
}

echo "==> Local load: scenario=${SCENARIO} API_BASE=${API_BASE} profile=${THRESHOLDS_PROFILE}"

if [[ "$HTTP_ONLY" -eq 0 ]]; then
  need_cmd k6
fi
need_cmd curl
need_cmd cargo

# Reuse an already-running Judgement API.
if api_ready; then
  echo "==> API already ready at ${API_BASE}"
else
  if [[ "$KILL_PORT" -eq 1 ]]; then
    kill_port_listeners
  elif [[ -n "$(port_pids)" ]]; then
    echo "Port ${PORT} is already in use by a non-ready service:" >&2
    describe_port >&2
    echo >&2
    echo "Fix options:" >&2
    echo "  ./deployment/load/local.sh --kill-port ${SCENARIO}" >&2
    echo "  PORT=8081 ./deployment/load/local.sh ${SCENARIO}" >&2
    exit 1
  fi

  if [[ "$USE_POSTGRES" -eq 1 ]]; then
    need_cmd docker
    if [[ "$RESET_DB" -eq 1 ]]; then
      echo "==> Resetting local Postgres volume (docker compose down -v)..."
      (cd "$REPO_ROOT" && docker compose down -v)
    fi
    echo "==> Starting Postgres (docker compose)..."
    (cd "$REPO_ROOT" && docker compose up -d postgres)
    for i in $(seq 1 45); do
      if docker compose -f "$REPO_ROOT/docker-compose.yml" exec -T postgres \
        pg_isready -U judgement -d judgement >/dev/null 2>&1; then
        break
      fi
      sleep 1
      if [[ "$i" -eq 45 ]]; then
        echo "Postgres did not become ready" >&2
        exit 1
      fi
    done
  fi

  echo "==> Building judgement-server (release)..."
  (cd "$BACKEND" && cargo build --release -p judgement-server)

  echo "==> Starting API (log: ${LOG_FILE})..."
  (
    cd "$BACKEND"
    export PORT
    export JUDGEMENT_ALLOW_SEED=1
    export HTTP_GUEST_RATE_LIMIT=10000
    export HTTP_RATE_LIMIT=100000
    export RAG_ENABLED=0
    export RUST_LOG="${RUST_LOG:-info}"
    if [[ "$USE_POSTGRES" -eq 1 ]]; then
      export DATABASE_URL
    else
      unset DATABASE_URL || true
    fi
    exec ./target/release/judgement-server
  ) >"$LOG_FILE" 2>&1 &
  API_PID=$!
  STARTED_API=1

  for i in $(seq 1 60); do
    if api_ready; then
      echo "==> API ready"
      break
    fi
    if ! kill -0 "$API_PID" 2>/dev/null; then
      echo "API exited early. Last log lines:" >&2
      tail -40 "$LOG_FILE" >&2 || true
      if grep -q 'previously applied but has been modified' "$LOG_FILE" 2>/dev/null; then
        echo >&2
        echo "Local Postgres migration checksum mismatch (stale docker volume)." >&2
        echo "Fix:  ./deployment/load/local.sh --reset-db ${SCENARIO}" >&2
        echo "Or:   ./deployment/load/local.sh --memory ${SCENARIO}" >&2
      fi
      if grep -q 'Address already in use' "$LOG_FILE" 2>/dev/null; then
        echo >&2
        echo "Port ${PORT} busy:" >&2
        describe_port >&2
        echo "Fix:  ./deployment/load/local.sh --kill-port ${SCENARIO}" >&2
        echo "Or:   PORT=8081 ./deployment/load/local.sh ${SCENARIO}" >&2
      fi
      exit 1
    fi
    sleep 1
    if [[ "$i" -eq 60 ]]; then
      echo "API did not become ready. Log: ${LOG_FILE}" >&2
      tail -40 "$LOG_FILE" >&2 || true
      exit 1
    fi
  done
fi

if [[ "$SKIP_HTTP_SMOKE" -eq 0 ]]; then
  echo "==> HTTP smoke"
  "$LOAD_DIR/smoke.sh"
fi

if [[ "$HTTP_ONLY" -eq 1 ]]; then
  echo "==> --http-only: skipping k6"
else
  echo "==> k6 ${SCENARIO}"
  "$LOAD_DIR/run.sh" "$SCENARIO"
fi

echo "==> Metrics"
"$LOAD_DIR/scrape_metrics.sh" snapshot || true

echo "LOCAL_LOAD_OK scenario=${SCENARIO}"
