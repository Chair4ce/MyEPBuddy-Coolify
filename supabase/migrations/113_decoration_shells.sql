-- Decoration Shell System
-- A shell is a container for a single decoration citation draft
-- Supports AFAM, AFCM, MSM, LOM, BSM decorations per MyDecs Reimagined guidelines
-- Mirrors the Award Shell architecture for consistency

-- ============================================
-- DECORATION SHELLS TABLE
-- ============================================
CREATE TABLE decoration_shells (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- For real users: user_id is their profile id, team_member_id is null
  -- For managed members: user_id is the supervisor's id, team_member_id is set
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  team_member_id UUID REFERENCES team_members(id) ON DELETE CASCADE,
  -- Who created this shell (supervisor creating for subordinate, or self)
  created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  
  -- Decoration configuration
  award_type TEXT NOT NULL CHECK (award_type IN ('afam', 'afcm', 'msm', 'lom', 'bsm')),
  reason TEXT NOT NULL DEFAULT 'meritorious_service' CHECK (reason IN (
    'meritorious_service', 'outstanding_achievement', 'act_of_courage',
    'retirement', 'separation', 'posthumous', 'combat_meritorious', 'combat_valor'
  )),
  
  -- Ratee information for the citation
  duty_title TEXT NOT NULL DEFAULT '',
  unit TEXT NOT NULL DEFAULT '',
  start_date DATE,
  end_date DATE,
  
  -- The generated/edited citation text
  citation_text TEXT NOT NULL DEFAULT '',
  
  -- Selected statement IDs used for generation (stored as JSON array)
  selected_statement_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  
  -- Status
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'finalized')),
  
  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- DECORATION SHELL SHARES
-- ============================================
-- Sharing shells with specific users (beyond supervisor chain)
CREATE TABLE decoration_shell_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_id UUID NOT NULL REFERENCES decoration_shells(id) ON DELETE CASCADE,
  -- Owner of the share (the person sharing)
  owner_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  -- Share type: 'user' for specific user
  share_type TEXT NOT NULL CHECK (share_type IN ('user')),
  -- The user this shell is shared with
  shared_with_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  -- Timestamp
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Unique shares per shell/user combination
  UNIQUE(shell_id, shared_with_id)
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_decoration_shells_user ON decoration_shells(user_id);
CREATE INDEX idx_decoration_shells_team_member ON decoration_shells(team_member_id);
CREATE INDEX idx_decoration_shells_created_by ON decoration_shells(created_by);
CREATE INDEX idx_decoration_shells_award_type ON decoration_shells(award_type);
CREATE INDEX idx_decoration_shells_status ON decoration_shells(status);
CREATE INDEX idx_decoration_shell_shares_shell ON decoration_shell_shares(shell_id);
CREATE INDEX idx_decoration_shell_shares_shared_with ON decoration_shell_shares(shared_with_id);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE decoration_shells ENABLE ROW LEVEL SECURITY;
ALTER TABLE decoration_shell_shares ENABLE ROW LEVEL SECURITY;

-- ============================================
-- DECORATION SHELLS POLICIES
-- ============================================

-- Users can view their own shells (where user_id is them and team_member_id is null)
CREATE POLICY "Users can view own decoration shells"
  ON decoration_shells FOR SELECT
  USING (user_id = auth.uid() AND team_member_id IS NULL);

-- Users can view shells they created (for managed members)
CREATE POLICY "Users can view decoration shells they created"
  ON decoration_shells FOR SELECT
  USING (created_by = auth.uid());

-- Supervisors can view shells of their subordinates (real users via team_history)
CREATE POLICY "Supervisors can view subordinate decoration shells via history"
  ON decoration_shells FOR SELECT
  USING (
    team_member_id IS NULL AND
    EXISTS (
      SELECT 1 FROM team_history th
      WHERE th.subordinate_id = decoration_shells.user_id
      AND th.supervisor_id = auth.uid()
    )
  );

-- Supervisors can view shells for managed members they supervise
CREATE POLICY "Supervisors can view managed member decoration shells"
  ON decoration_shells FOR SELECT
  USING (
    team_member_id IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = decoration_shells.team_member_id
      AND tm.supervisor_id = auth.uid()
    )
  );

-- Users can view shells shared with them
CREATE POLICY "Users can view shared decoration shells"
  ON decoration_shells FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM decoration_shell_shares dss
      WHERE dss.shell_id = decoration_shells.id
      AND dss.shared_with_id = auth.uid()
    )
  );

-- Users can create shells for themselves
CREATE POLICY "Users can create own decoration shells"
  ON decoration_shells FOR INSERT
  WITH CHECK (
    user_id = auth.uid() AND 
    created_by = auth.uid() AND
    team_member_id IS NULL
  );

-- Supervisors can create shells for subordinates (real users)
CREATE POLICY "Supervisors can create subordinate decoration shells"
  ON decoration_shells FOR INSERT
  WITH CHECK (
    created_by = auth.uid() AND
    team_member_id IS NULL AND
    EXISTS (
      SELECT 1 FROM teams t
      WHERE t.subordinate_id = decoration_shells.user_id
      AND t.supervisor_id = auth.uid()
    )
  );

-- Supervisors can create shells for managed members
CREATE POLICY "Supervisors can create managed member decoration shells"
  ON decoration_shells FOR INSERT
  WITH CHECK (
    created_by = auth.uid() AND
    team_member_id IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = decoration_shells.team_member_id
      AND tm.supervisor_id = auth.uid()
    )
  );

-- Users can update their own shells
CREATE POLICY "Users can update own decoration shells"
  ON decoration_shells FOR UPDATE
  USING (user_id = auth.uid() AND team_member_id IS NULL)
  WITH CHECK (user_id = auth.uid() AND team_member_id IS NULL);

-- Supervisors can update shells via team history
CREATE POLICY "Supervisors can update subordinate decoration shells via history"
  ON decoration_shells FOR UPDATE
  USING (
    team_member_id IS NULL AND
    EXISTS (
      SELECT 1 FROM team_history th
      WHERE th.subordinate_id = decoration_shells.user_id
      AND th.supervisor_id = auth.uid()
    )
  );

-- Supervisors can update managed member shells
CREATE POLICY "Supervisors can update managed member decoration shells"
  ON decoration_shells FOR UPDATE
  USING (
    team_member_id IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = decoration_shells.team_member_id
      AND tm.supervisor_id = auth.uid()
    )
  );

-- Users can delete their own shells
CREATE POLICY "Users can delete own decoration shells"
  ON decoration_shells FOR DELETE
  USING (user_id = auth.uid() AND team_member_id IS NULL);

-- Supervisors can delete subordinate shells
CREATE POLICY "Supervisors can delete subordinate decoration shells"
  ON decoration_shells FOR DELETE
  USING (
    team_member_id IS NULL AND
    EXISTS (
      SELECT 1 FROM team_history th
      WHERE th.subordinate_id = decoration_shells.user_id
      AND th.supervisor_id = auth.uid()
    )
  );

-- Supervisors can delete managed member shells
CREATE POLICY "Supervisors can delete managed member decoration shells"
  ON decoration_shells FOR DELETE
  USING (
    team_member_id IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = decoration_shells.team_member_id
      AND tm.supervisor_id = auth.uid()
    )
  );

-- ============================================
-- DECORATION SHELL SHARES POLICIES
-- ============================================

-- Users can view shares they own
CREATE POLICY "Users can view own decoration shell shares"
  ON decoration_shell_shares FOR SELECT
  USING (owner_id = auth.uid());

-- Users can view shares where they are the recipient
CREATE POLICY "Users can view decoration shells shared with them"
  ON decoration_shell_shares FOR SELECT
  USING (shared_with_id = auth.uid());

-- Users can create shares for shells they can access
CREATE POLICY "Users can create decoration shell shares"
  ON decoration_shell_shares FOR INSERT
  WITH CHECK (
    owner_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM decoration_shells ds
      WHERE ds.id = decoration_shell_shares.shell_id
      AND (
        (ds.user_id = auth.uid() AND ds.team_member_id IS NULL)
        OR
        (ds.team_member_id IS NULL AND EXISTS (
          SELECT 1 FROM team_history th
          WHERE th.subordinate_id = ds.user_id
          AND th.supervisor_id = auth.uid()
        ))
        OR
        (ds.team_member_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM team_members tm
          WHERE tm.id = ds.team_member_id
          AND tm.supervisor_id = auth.uid()
        ))
      )
    )
  );

-- Users can delete shares they own
CREATE POLICY "Users can delete own decoration shell shares"
  ON decoration_shell_shares FOR DELETE
  USING (owner_id = auth.uid());

-- ============================================
-- TRIGGER: Auto-update updated_at
-- ============================================
CREATE OR REPLACE FUNCTION update_decoration_shell_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER decoration_shells_updated_at
  BEFORE UPDATE ON decoration_shells
  FOR EACH ROW EXECUTE FUNCTION update_decoration_shell_updated_at();
