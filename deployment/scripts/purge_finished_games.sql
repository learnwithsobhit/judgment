-- Ops backstop: hard-delete leftover finished/aborted games older than 4h.
-- Primary path deletes on finish/abort; this catches stragglers.
-- Run via: fly postgres connect -a judgment-db
--   or: psql "$DATABASE_URL" -f deployment/scripts/purge_finished_games.sql

BEGIN;

-- Hard-delete leftover terminal games (cascades events/snapshots/results).
WITH doomed AS (
  SELECT game_id, room_id
  FROM games
  WHERE status IN ('finished', 'aborted')
    AND finished_at IS NOT NULL
    AND finished_at < now() - interval '4 hours'
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
