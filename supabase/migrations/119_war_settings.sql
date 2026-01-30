-- Weekly Activity Report (WAR) Settings
-- Stores user-customizable categories for organizing weekly reports

CREATE TABLE war_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
  
  -- Categories for organizing entries in the WAR
  -- Each category has: key (unique identifier), label (display name), description (help text), order (sort order)
  categories JSONB NOT NULL DEFAULT '[
    {
      "key": "key_accomplishments",
      "label": "Key Accomplishments/Highlights",
      "description": "Impact-driven achievements - the What. Focus on quantifiable results (e.g., $X saved, Y personnel trained).",
      "order": 1
    },
    {
      "key": "issues_roadblocks",
      "label": "Issues/Roadblocks",
      "description": "High-level challenges requiring attention - the So What. Personnel shortages, equipment failures, or logistical bottlenecks.",
      "order": 2
    },
    {
      "key": "upcoming_priorities",
      "label": "Upcoming Priorities/Key Events",
      "description": "Immediate actions or milestones planned for the following 1-2 weeks - the Now What.",
      "order": 3
    }
  ]'::jsonb,
  
  -- Optional header info to include in WARs
  unit_office_symbol TEXT,
  
  -- Custom instructions for LLM synthesis
  synthesis_instructions TEXT DEFAULT 'Synthesize the entries into a concise, actionable format. Use bullet points rather than lengthy narratives. Structure each bullet as: [Action taken] + [Result/Impact]. Keep paragraphs to 3-4 sentences maximum. Use no pronouns. Include specific, measurable, and relevant language.',
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE war_settings ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own WAR settings"
  ON war_settings FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own WAR settings"
  ON war_settings FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own WAR settings"
  ON war_settings FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own WAR settings"
  ON war_settings FOR DELETE
  USING (auth.uid() = user_id);

-- Index
CREATE INDEX idx_war_settings_user ON war_settings(user_id);

-- Update trigger
CREATE TRIGGER update_war_settings_updated_at
  BEFORE UPDATE ON war_settings
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Add comment
COMMENT ON TABLE war_settings IS 'User settings for Weekly Activity Reports (WAR) including customizable categories for organizing team accomplishments';
COMMENT ON COLUMN war_settings.categories IS 'JSONB array of category objects with key, label, description, and order fields';
