-- ============================================
-- DUTY DESCRIPTION TEMPLATES
-- ============================================
-- Reusable duty description templates that can be shared across team members
-- Templates are organized by Office, Role, and Rank metadata
-- Unlike epb_duty_description_examples (shell-specific), these are user-owned
-- and can be applied to any team member's EPB

CREATE TABLE duty_description_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Owner of this template (supervisor who created it)
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  -- The template content
  template_text TEXT NOT NULL,
  -- Metadata labels for organization
  office_label TEXT,  -- e.g., "Cyber Operations", "Maintenance", "Finance"
  role_label TEXT,    -- e.g., "Flight Chief", "Section Lead", "NCOIC"
  rank_label TEXT,    -- e.g., "TSgt", "MSgt", "SrA" - freeform to allow ranges like "TSgt-MSgt"
  -- Optional note about this template
  note TEXT,
  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_duty_desc_templates_user ON duty_description_templates(user_id);
CREATE INDEX idx_duty_desc_templates_office ON duty_description_templates(office_label) WHERE office_label IS NOT NULL;
CREATE INDEX idx_duty_desc_templates_role ON duty_description_templates(role_label) WHERE role_label IS NOT NULL;
CREATE INDEX idx_duty_desc_templates_rank ON duty_description_templates(rank_label) WHERE rank_label IS NOT NULL;
CREATE INDEX idx_duty_desc_templates_created ON duty_description_templates(created_at DESC);

-- Text search index for searching across all fields
CREATE INDEX idx_duty_desc_templates_search ON duty_description_templates 
  USING GIN (to_tsvector('english', 
    COALESCE(template_text, '') || ' ' || 
    COALESCE(office_label, '') || ' ' || 
    COALESCE(role_label, '') || ' ' || 
    COALESCE(rank_label, '') || ' ' ||
    COALESCE(note, '')
  ));

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE duty_description_templates ENABLE ROW LEVEL SECURITY;

-- ============================================
-- RLS POLICIES
-- ============================================

-- Users can view their own templates
CREATE POLICY "Users can view their own duty description templates"
  ON duty_description_templates FOR SELECT
  USING (user_id = auth.uid());

-- Users can insert their own templates
CREATE POLICY "Users can insert their own duty description templates"
  ON duty_description_templates FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Users can update their own templates
CREATE POLICY "Users can update their own duty description templates"
  ON duty_description_templates FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Users can delete their own templates
CREATE POLICY "Users can delete their own duty description templates"
  ON duty_description_templates FOR DELETE
  USING (user_id = auth.uid());

-- ============================================
-- UPDATED_AT TRIGGER
-- ============================================
CREATE OR REPLACE FUNCTION update_duty_description_templates_updated_at()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER duty_description_templates_updated_at
  BEFORE UPDATE ON duty_description_templates
  FOR EACH ROW
  EXECUTE FUNCTION update_duty_description_templates_updated_at();

-- ============================================
-- HELPER VIEW FOR DISTINCT LABELS
-- ============================================
-- This view helps populate filter dropdowns with existing labels
CREATE OR REPLACE VIEW duty_description_template_labels AS
SELECT DISTINCT
  office_label,
  role_label,
  rank_label
FROM duty_description_templates
WHERE 
  office_label IS NOT NULL OR 
  role_label IS NOT NULL OR 
  rank_label IS NOT NULL;

-- Grant access to the view
GRANT SELECT ON duty_description_template_labels TO authenticated;

