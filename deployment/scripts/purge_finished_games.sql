-- One-time / ops backfill: compact then delete terminal games older than 24h.
-- Run via: fly postgres connect -a judgment-db
--   or: psql "$DATABASE_URL" -f deployment/scripts/purge_finished_games.sql

BEGIN;

-- Drop mid-game event history for finished/aborted games (keep latest snapshot).
DELETE FROM game_events ge
USING games g
WHERE ge.game_id = g.game_id
  AND g.status IN ('finished', 'aborted');

DELETE FROM game_snapshots gs
USING games g
WHERE gs.game_id = g.game_id
  AND g.status IN ('finished', 'aborted')
  AND gs.state_version < (
      SELECT COALESCE(MAX(s2.state_version), 0)
      FROM game_snapshots s2
      WHERE s2.game_id = gs.game_id
  );

-- Hard-delete games finished/aborted more than 24 hours ago (cascades children).
WITH doomed AS (
  SELECT game_id, room_id
  FROM games
  WHERE status IN ('finished', 'aborted')
    AND finished_at IS NOT NULL
    AND finished_at < now() - interval '24 hours'
)
DELETE FROM games g
USING doomed d
WHERE g.game_id = d.game_id;

-- Remove orphan in_game rooms that no longer have a game row.
DELETE FROM rooms r
WHERE r.phase = 'in_game'
  AND (
    r.game_id IS NULL
    OR NOT EXISTS (SELECT 1 FROM games g WHERE g.game_id = r.game_id)
  );

COMMIT;
