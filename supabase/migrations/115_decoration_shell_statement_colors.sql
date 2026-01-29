-- Add statement_colors column to decoration_shells
-- Stores a JSON object mapping statement IDs to their assigned highlight color IDs
-- Example: {"stmt-123": "blue", "stmt-456": "red"}

ALTER TABLE decoration_shells
ADD COLUMN statement_colors JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Add a comment for documentation
COMMENT ON COLUMN decoration_shells.statement_colors IS 'JSON object mapping statement IDs to highlight color IDs for visual tracking';
