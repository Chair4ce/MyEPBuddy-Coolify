-- Allow NULL values for mpa and impact columns in accomplishments table
-- This supports entries that don't fit into a specific MPA or don't have a defined impact yet

ALTER TABLE accomplishments
  ALTER COLUMN mpa DROP NOT NULL;

ALTER TABLE accomplishments
  ALTER COLUMN impact DROP NOT NULL;

-- Add a comment explaining the nullable fields
COMMENT ON COLUMN accomplishments.mpa IS 'Major Performance Area - nullable for entries that do not fit a specific MPA';
COMMENT ON COLUMN accomplishments.impact IS 'Impact/Result - optional field describing the outcome of the accomplishment';

