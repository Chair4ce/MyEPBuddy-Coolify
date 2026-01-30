-- Weekly Activity Report (WAR) Storage
-- Stores generated and edited WAR reports for history/archive

CREATE TABLE war_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  
  -- Week identification
  week_start DATE NOT NULL,
  week_end DATE NOT NULL,
  
  -- Report header info
  title TEXT, -- Optional custom title
  unit_office_symbol TEXT,
  prepared_by TEXT NOT NULL,
  
  -- Report content (editable after generation)
  -- Structure: { categories: [{ key, label, items: string[] }] }
  content JSONB NOT NULL DEFAULT '{}'::jsonb,
  
  -- Metadata
  entry_count INT NOT NULL DEFAULT 0, -- Number of entries used to generate
  model_used TEXT, -- Which LLM model was used
  
  -- Status for future sharing feature
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
  
  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE war_reports ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own WAR reports"
  ON war_reports FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own WAR reports"
  ON war_reports FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own WAR reports"
  ON war_reports FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own WAR reports"
  ON war_reports FOR DELETE
  USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_war_reports_user ON war_reports(user_id);
CREATE INDEX idx_war_reports_week ON war_reports(user_id, week_start DESC);
CREATE INDEX idx_war_reports_created ON war_reports(user_id, created_at DESC);

-- Full text search index for searching WAR content
CREATE INDEX idx_war_reports_search ON war_reports USING gin(
  to_tsvector('english', 
    COALESCE(title, '') || ' ' || 
    COALESCE(unit_office_symbol, '') || ' ' || 
    COALESCE(prepared_by, '') || ' ' ||
    COALESCE(content::text, '')
  )
);

-- Update trigger
CREATE TRIGGER update_war_reports_updated_at
  BEFORE UPDATE ON war_reports
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Comments
COMMENT ON TABLE war_reports IS 'Stored Weekly Activity Reports (WARs) with editable content';
COMMENT ON COLUMN war_reports.content IS 'JSONB with categories array, each containing key, label, and items (bullet points)';
COMMENT ON COLUMN war_reports.status IS 'draft = in progress, published = shared, archived = historical';
