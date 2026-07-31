#!/usr/bin/env bash
# Daily Postgres backup helper (PLAN.md §25.1).
set -euo pipefail

DATABASE_URL="${DATABASE_URL:?DATABASE_URL is required}"
OUT_DIR="${BACKUP_DIR:-./backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT_DIR"
OUT_FILE="${OUT_DIR}/judgement-${STAMP}.sql.gz"

echo "Writing ${OUT_FILE}"
pg_dump "$DATABASE_URL" | gzip > "$OUT_FILE"
echo "OK $(du -h "$OUT_FILE" | awk '{print $1}')"

# Retain last 14 backups by default.
ls -1t "$OUT_DIR"/judgement-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm -f
