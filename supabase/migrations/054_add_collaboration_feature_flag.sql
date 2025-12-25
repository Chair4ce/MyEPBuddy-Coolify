-- Add feature flag for multi-user collaboration
-- This allows admins to enable/disable the entire collaboration feature

ALTER TABLE epb_config
  ADD COLUMN enable_collaboration BOOLEAN NOT NULL DEFAULT FALSE;

-- Add comment for documentation
COMMENT ON COLUMN epb_config.enable_collaboration IS 
  'Feature flag to enable/disable multi-user collaboration functionality in EPB workspace';

