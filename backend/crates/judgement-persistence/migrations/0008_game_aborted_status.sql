-- Allow host/vacancy abort of in-progress games (replace-or-end presence).
ALTER TABLE games DROP CONSTRAINT IF EXISTS games_status_check;
ALTER TABLE games ADD CONSTRAINT games_status_check
    CHECK (status IN ('active', 'finished', 'aborted'));
