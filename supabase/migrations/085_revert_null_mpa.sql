-- Revert: Add NOT NULL constraint back to mpa column
-- First update any null values to 'miscellaneous' before adding the constraint

UPDATE accomplishments
SET mpa = 'miscellaneous'
WHERE mpa IS NULL;

ALTER TABLE accomplishments
  ALTER COLUMN mpa SET NOT NULL;

-- Remove the comment we added
COMMENT ON COLUMN accomplishments.mpa IS NULL;

