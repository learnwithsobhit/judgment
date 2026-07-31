#!/usr/bin/env bash
# Restore a backup into a scratch database and smoke-check (Phase 9 exit criterion).
set -euo pipefail

SOURCE_URL="${DATABASE_URL:?DATABASE_URL (admin URL that can CREATE DATABASE) is required}"
BACKUP_FILE="${1:?usage: restore_verify.sh <backup.sql.gz>}"
SCRATCH_DB="${SCRATCH_DB:-judgement_restore_verify}"

echo "Creating scratch database ${SCRATCH_DB}"
psql "$SOURCE_URL" -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS ${SCRATCH_DB};"
psql "$SOURCE_URL" -v ON_ERROR_STOP=1 -c "CREATE DATABASE ${SCRATCH_DB};"

# Swap the path component of DATABASE_URL for the scratch DB name.
SCRATCH_URL="$(python3 -c "
from urllib.parse import urlparse, urlunparse
import os
u = urlparse(os.environ['DATABASE_URL'])
print(urlunparse(u._replace(path='/${os.environ['SCRATCH_DB']}')) )
")"

echo "Restoring ${BACKUP_FILE} -> ${SCRATCH_DB}"
gunzip -c "$BACKUP_FILE" | psql "$SCRATCH_URL" -v ON_ERROR_STOP=1 >/dev/null

echo "Verifying core tables exist"
psql "$SCRATCH_URL" -v ON_ERROR_STOP=1 -c "SELECT COUNT(*) FROM guest_sessions;" >/dev/null
psql "$SCRATCH_URL" -v ON_ERROR_STOP=1 -c "SELECT COUNT(*) FROM games;" >/dev/null

echo "RESTORE_VERIFY_OK"
