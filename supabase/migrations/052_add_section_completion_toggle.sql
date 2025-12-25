-- Add is_complete column to epb_shell_sections
-- This allows users to manually mark an MPA statement as complete
-- rather than relying on whether text exists

ALTER TABLE epb_shell_sections
  ADD COLUMN is_complete BOOLEAN NOT NULL DEFAULT FALSE;

-- Add comment for documentation
COMMENT ON COLUMN epb_shell_sections.is_complete IS 
  'User-controlled toggle to mark this MPA statement as complete/finalized';

