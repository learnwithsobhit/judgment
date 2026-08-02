#!/usr/bin/env bash
# Scrape /metrics and print persist histogram + key counters.
# Usage:
#   ./scrape_metrics.sh [label]           # print snapshot
#   ./scrape_metrics.sh before out.txt    # save snapshot
#   ./scrape_metrics.sh diff before after # compare two snapshots
set -euo pipefail

API_BASE="${API_BASE:-http://127.0.0.1:8080}"
API_BASE="${API_BASE%/}"

fetch() {
  curl -fsS --max-time 15 "${API_BASE}/metrics"
}

approx_persist_p95() {
  # Bucket edges: 10, 50, 100, 500, +Inf. Report lowest le covering ≥95% of samples.
  local text="$1"
  local count sum
  count="$(echo "$text" | awk '/judgement_persist_commit_duration_milliseconds_count/{print $2; exit}')"
  sum="$(echo "$text" | awk '/judgement_persist_commit_duration_milliseconds_sum/{print $2; exit}')"
  if [[ -z "${count:-}" || "$count" == "0" ]]; then
    echo "persist: no samples"
    return
  fi
  local mean
  mean="$(awk -v s="$sum" -v c="$count" 'BEGIN{printf "%.2f", s/c}')"
  local target
  target="$(awk -v c="$count" 'BEGIN{printf "%.0f", c*0.95}')"
  local p95_bucket=">500"
  while IFS= read -r line; do
    local le val
    le="$(echo "$line" | sed -n 's/.*le="\([^"]*\)".*/\1/p')"
    val="$(echo "$line" | awk '{print $2}')"
    if [[ "$le" != "+Inf" ]] && awk -v v="$val" -v t="$target" 'BEGIN{exit !(v+0 >= t+0)}'; then
      p95_bucket="<=${le}ms"
      break
    fi
  done < <(echo "$text" | grep 'judgement_persist_commit_duration_milliseconds_bucket')
  echo "persist: count=${count} mean_ms=${mean} p95_approx=${p95_bucket}"
}

print_key() {
  local text="$1"
  local label="${2:-snapshot}"
  echo "=== metrics ${label} @ ${API_BASE} ==="
  echo "$text" | awk '
    /^judgement_(active_|db_write_failures_total|games_admission_rejected_total|http_rate_limited_total|ws_connected_total|ws_disconnected_total|reconnects_total|outbound_snapshot_drops_total|actors_respawned_total|games_started_total|games_completed_total|invalid_actions_total)/ {
      print
    }
  '
  approx_persist_p95 "$text"
}

extract_counter() {
  local file="$1" name="$2"
  awk -v n="$name" '$1==n {print $2; exit}' "$file"
}

cmd="${1:-snapshot}"

case "$cmd" in
  snapshot|"")
    text="$(fetch)"
    print_key "$text" "live"
    ;;
  before|after)
    out="${2:?usage: $0 before|after outfile}"
    fetch >"$out"
    print_key "$(cat "$out")" "$cmd"
    ;;
  diff)
    before="${2:?usage: $0 diff before.txt after.txt}"
    after="${3:?usage: $0 diff before.txt after.txt}"
    echo "=== metrics diff ==="
    for metric in \
      judgement_db_write_failures_total \
      judgement_games_admission_rejected_total \
      judgement_http_rate_limited_total \
      judgement_ws_connected_total \
      judgement_outbound_snapshot_drops_total \
      judgement_actors_respawned_total \
      judgement_games_started_total \
      judgement_invalid_actions_total
    do
      a="$(extract_counter "$before" "$metric" || echo 0)"
      b="$(extract_counter "$after" "$metric" || echo 0)"
      a="${a:-0}"; b="${b:-0}"
      delta="$(awk -v a="$a" -v b="$b" 'BEGIN{print b-a}')"
      echo "${metric}: ${a} -> ${b} (delta=${delta})"
    done
    echo "--- after ---"
    print_key "$(cat "$after")" "after"
    # Fail if db write failures increased.
    fa="$(extract_counter "$before" "judgement_db_write_failures_total" || echo 0)"
    fb="$(extract_counter "$after" "judgement_db_write_failures_total" || echo 0)"
    fa="${fa:-0}"; fb="${fb:-0}"
    if awk -v a="$fa" -v b="$fb" 'BEGIN{exit !(b>a)}'; then
      echo "FAIL: db_write_failures increased (${fa} -> ${fb})" >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 [snapshot|before outfile|after outfile|diff before after]" >&2
    exit 1
    ;;
esac
