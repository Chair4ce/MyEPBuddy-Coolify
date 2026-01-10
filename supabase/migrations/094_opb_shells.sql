-- OPB Shell System (Officer Performance Brief)
-- Similar to EPB shells but for officers (O-1 to O-6)
-- Officers generate OPBs for themselves, unlike EPBs where supervisors often help
-- Same 4 MPAs with 350 char max, HLR with 250 char max

-- ============================================
-- OPB SHELLS TABLE
-- ============================================
CREATE TABLE opb_shells (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Officer user profile
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  -- Who created this shell (typically the officer themselves)
  created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  -- Performance cycle year
  cycle_year INTEGER NOT NULL,
  -- Duty description (concise scope of responsibility)
  duty_description TEXT NOT NULL DEFAULT '',
  -- Whether duty description is marked complete
  duty_description_complete BOOLEAN NOT NULL DEFAULT false,
  -- Shell status
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  archived_at TIMESTAMPTZ,
  archive_name TEXT,
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Only 1 active shell per officer per cycle year
  CONSTRAINT unique_opb_shell_per_user_cycle UNIQUE NULLS NOT DISTINCT (user_id, cycle_year, status)
);

-- ============================================
-- OPB SHELL MPA SECTIONS
-- ============================================
CREATE TABLE opb_shell_sections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_id UUID NOT NULL REFERENCES opb_shells(id) ON DELETE CASCADE,
  -- MPA key: executing_mission, leading_people, managing_resources, improving_unit, hlr_assessment
  mpa TEXT NOT NULL,
  -- Current statement text (max 350 chars, HLR max 250)
  statement_text TEXT NOT NULL DEFAULT '',
  -- Section marked as complete
  is_complete BOOLEAN NOT NULL DEFAULT false,
  -- Last editor
  last_edited_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Only 1 section per MPA per shell
  UNIQUE(shell_id, mpa)
);

-- ============================================
-- OPB SHELL SECTION SNAPSHOTS (History)
-- ============================================
CREATE TABLE opb_shell_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  section_id UUID NOT NULL REFERENCES opb_shell_sections(id) ON DELETE CASCADE,
  statement_text TEXT NOT NULL,
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- OPB SHELL SHARES
-- ============================================
-- Officers may share their OPB with raters, mentors, etc.
CREATE TABLE opb_shell_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_id UUID NOT NULL REFERENCES opb_shells(id) ON DELETE CASCADE,
  owner_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  share_type TEXT NOT NULL CHECK (share_type IN ('user')),
  shared_with_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(shell_id, shared_with_id)
);

-- ============================================
-- DUTY DESCRIPTION SNAPSHOTS
-- ============================================
CREATE TABLE opb_duty_description_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_id UUID NOT NULL REFERENCES opb_shells(id) ON DELETE CASCADE,
  description_text TEXT NOT NULL,
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_opb_shells_user ON opb_shells(user_id);
CREATE INDEX idx_opb_shells_created_by ON opb_shells(created_by);
CREATE INDEX idx_opb_shells_cycle_year ON opb_shells(cycle_year);
CREATE INDEX idx_opb_shells_status ON opb_shells(status);
CREATE INDEX idx_opb_shell_sections_shell ON opb_shell_sections(shell_id);
CREATE INDEX idx_opb_shell_sections_mpa ON opb_shell_sections(mpa);
CREATE INDEX idx_opb_shell_snapshots_section ON opb_shell_snapshots(section_id);
CREATE INDEX idx_opb_shell_snapshots_created_at ON opb_shell_snapshots(created_at DESC);
CREATE INDEX idx_opb_shell_shares_shell ON opb_shell_shares(shell_id);
CREATE INDEX idx_opb_shell_shares_shared_with ON opb_shell_shares(shared_with_id);
CREATE INDEX idx_opb_duty_description_snapshots_shell ON opb_duty_description_snapshots(shell_id);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE opb_shells ENABLE ROW LEVEL SECURITY;
ALTER TABLE opb_shell_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE opb_shell_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE opb_shell_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE opb_duty_description_snapshots ENABLE ROW LEVEL SECURITY;

-- ============================================
-- OPB SHELLS POLICIES
-- ============================================

-- Officers can view their own shells
CREATE POLICY "Officers can view own opb shells"
  ON opb_shells FOR SELECT
  USING (user_id = auth.uid());

-- Officers can view shells shared with them
CREATE POLICY "Users can view shared opb shells"
  ON opb_shells FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM opb_shell_shares oss
      WHERE oss.shell_id = opb_shells.id
      AND oss.shared_with_id = auth.uid()
    )
  );

-- Officers can create shells for themselves
CREATE POLICY "Officers can create own opb shells"
  ON opb_shells FOR INSERT
  WITH CHECK (
    user_id = auth.uid() AND 
    created_by = auth.uid()
  );

-- Officers can update their own shells
CREATE POLICY "Officers can update own opb shells"
  ON opb_shells FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Officers can delete their own shells
CREATE POLICY "Officers can delete own opb shells"
  ON opb_shells FOR DELETE
  USING (user_id = auth.uid());

-- ============================================
-- OPB SHELL SECTIONS POLICIES
-- ============================================

-- View sections if user can view the parent shell
CREATE POLICY "Users can view opb sections of accessible shells"
  ON opb_shell_sections FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_shell_sections.shell_id
    )
  );

-- Insert sections if user owns the parent shell
CREATE POLICY "Officers can insert opb sections for own shells"
  ON opb_shell_sections FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_shell_sections.shell_id
      AND os.user_id = auth.uid()
    )
  );

-- Update sections if user owns the parent shell or has share access
CREATE POLICY "Officers can update opb sections of accessible shells"
  ON opb_shell_sections FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_shell_sections.shell_id
      AND (
        os.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM opb_shell_shares oss
          WHERE oss.shell_id = os.id
          AND oss.shared_with_id = auth.uid()
        )
      )
    )
  );

-- Delete sections if user owns the parent shell
CREATE POLICY "Officers can delete opb sections of own shells"
  ON opb_shell_sections FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_shell_sections.shell_id
      AND os.user_id = auth.uid()
    )
  );

-- ============================================
-- OPB SHELL SNAPSHOTS POLICIES
-- ============================================

-- View snapshots if user can view the parent section
CREATE POLICY "Users can view opb snapshots of accessible sections"
  ON opb_shell_snapshots FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM opb_shell_sections oss
      WHERE oss.id = opb_shell_snapshots.section_id
    )
  );

-- Insert snapshots if user can update the parent section
CREATE POLICY "Users can insert opb snapshots for accessible sections"
  ON opb_shell_snapshots FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM opb_shell_sections oss
      JOIN opb_shells os ON os.id = oss.shell_id
      WHERE oss.id = opb_shell_snapshots.section_id
      AND (
        os.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM opb_shell_shares oshr
          WHERE oshr.shell_id = os.id
          AND oshr.shared_with_id = auth.uid()
        )
      )
    )
  );

-- Delete own snapshots
CREATE POLICY "Users can delete opb snapshots they created"
  ON opb_shell_snapshots FOR DELETE
  USING (created_by = auth.uid());

-- ============================================
-- OPB SHELL SHARES POLICIES
-- ============================================

-- Users can view shares they own
CREATE POLICY "Users can view own opb shell shares"
  ON opb_shell_shares FOR SELECT
  USING (owner_id = auth.uid());

-- Users can view shares where they are the recipient
CREATE POLICY "Users can view opb shells shared with them"
  ON opb_shell_shares FOR SELECT
  USING (shared_with_id = auth.uid());

-- Users can create shares for shells they own
CREATE POLICY "Officers can create opb shell shares"
  ON opb_shell_shares FOR INSERT
  WITH CHECK (
    owner_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_shell_shares.shell_id
      AND os.user_id = auth.uid()
    )
  );

-- Users can delete shares they own
CREATE POLICY "Officers can delete own opb shell shares"
  ON opb_shell_shares FOR DELETE
  USING (owner_id = auth.uid());

-- ============================================
-- DUTY DESCRIPTION SNAPSHOTS POLICIES
-- ============================================

-- View snapshots if user can view the parent shell
CREATE POLICY "Users can view opb duty description snapshots"
  ON opb_duty_description_snapshots FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_duty_description_snapshots.shell_id
    )
  );

-- Insert snapshots if user can update the parent shell
CREATE POLICY "Users can insert opb duty description snapshots"
  ON opb_duty_description_snapshots FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_duty_description_snapshots.shell_id
      AND (
        os.user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM opb_shell_shares oss
          WHERE oss.shell_id = os.id
          AND oss.shared_with_id = auth.uid()
        )
      )
    )
  );

-- Delete own snapshots
CREATE POLICY "Users can delete opb duty description snapshots they created"
  ON opb_duty_description_snapshots FOR DELETE
  USING (created_by = auth.uid());

-- ============================================
-- TRIGGER: Auto-update updated_at
-- ============================================
CREATE OR REPLACE FUNCTION update_opb_shell_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER opb_shells_updated_at
  BEFORE UPDATE ON opb_shells
  FOR EACH ROW EXECUTE FUNCTION update_opb_shell_updated_at();

CREATE TRIGGER opb_shell_sections_updated_at
  BEFORE UPDATE ON opb_shell_sections
  FOR EACH ROW EXECUTE FUNCTION update_opb_shell_updated_at();

-- ============================================
-- TRIGGER: Auto-create MPA sections when OPB shell is created
-- ============================================
CREATE OR REPLACE FUNCTION create_opb_shell_sections()
RETURNS TRIGGER AS $$
BEGIN
  -- Insert all standard MPA sections for the new OPB shell
  -- Same MPAs as EPB: executing_mission, leading_people, managing_resources, improving_unit, hlr_assessment
  INSERT INTO opb_shell_sections (shell_id, mpa, last_edited_by)
  VALUES 
    (NEW.id, 'executing_mission', NEW.created_by),
    (NEW.id, 'leading_people', NEW.created_by),
    (NEW.id, 'managing_resources', NEW.created_by),
    (NEW.id, 'improving_unit', NEW.created_by),
    (NEW.id, 'hlr_assessment', NEW.created_by);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER opb_shells_create_sections
  AFTER INSERT ON opb_shells
  FOR EACH ROW EXECUTE FUNCTION create_opb_shell_sections();

-- ============================================
-- FUNCTION: Get OPB shell with sections
-- ============================================
CREATE OR REPLACE FUNCTION get_opb_shell_with_sections(p_shell_id UUID)
RETURNS TABLE (
  shell_id UUID,
  user_id UUID,
  cycle_year INTEGER,
  created_by UUID,
  duty_description TEXT,
  duty_description_complete BOOLEAN,
  status TEXT,
  archived_at TIMESTAMPTZ,
  archive_name TEXT,
  shell_created_at TIMESTAMPTZ,
  shell_updated_at TIMESTAMPTZ,
  section_id UUID,
  mpa TEXT,
  statement_text TEXT,
  is_complete BOOLEAN,
  section_updated_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    os.id AS shell_id,
    os.user_id,
    os.cycle_year,
    os.created_by,
    os.duty_description,
    os.duty_description_complete,
    os.status,
    os.archived_at,
    os.archive_name,
    os.created_at AS shell_created_at,
    os.updated_at AS shell_updated_at,
    oss.id AS section_id,
    oss.mpa,
    oss.statement_text,
    oss.is_complete,
    oss.updated_at AS section_updated_at
  FROM opb_shells os
  LEFT JOIN opb_shell_sections oss ON oss.shell_id = os.id
  WHERE os.id = p_shell_id
  ORDER BY 
    CASE oss.mpa
      WHEN 'executing_mission' THEN 1
      WHEN 'leading_people' THEN 2
      WHEN 'managing_resources' THEN 3
      WHEN 'improving_unit' THEN 4
      WHEN 'hlr_assessment' THEN 5
      ELSE 6
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;
