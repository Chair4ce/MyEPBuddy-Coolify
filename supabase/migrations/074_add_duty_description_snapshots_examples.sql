-- Add snapshots and examples tables for duty description
-- Similar to epb_shell_snapshots and epb_saved_examples but for duty_description on epb_shells

-- ============================================
-- DUTY DESCRIPTION SNAPSHOTS (History)
-- ============================================
CREATE TABLE epb_duty_description_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_id UUID NOT NULL REFERENCES epb_shells(id) ON DELETE CASCADE,
  -- Snapshot of the duty description text
  description_text TEXT NOT NULL,
  -- Who created this snapshot
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  -- Optional note/label for the snapshot
  note TEXT,
  -- Timestamp
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- DUTY DESCRIPTION SAVED EXAMPLES
-- ============================================
CREATE TABLE epb_duty_description_examples (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_id UUID NOT NULL REFERENCES epb_shells(id) ON DELETE CASCADE,
  -- The saved example text
  example_text TEXT NOT NULL,
  -- Optional note about this example
  note TEXT,
  -- Who saved this example
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  -- Timestamp
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_duty_desc_snapshots_shell ON epb_duty_description_snapshots(shell_id);
CREATE INDEX idx_duty_desc_snapshots_created_at ON epb_duty_description_snapshots(created_at DESC);
CREATE INDEX idx_duty_desc_examples_shell ON epb_duty_description_examples(shell_id);
CREATE INDEX idx_duty_desc_examples_created_at ON epb_duty_description_examples(created_at DESC);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE epb_duty_description_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE epb_duty_description_examples ENABLE ROW LEVEL SECURITY;

-- ============================================
-- DUTY DESCRIPTION SNAPSHOTS POLICIES
-- ============================================

-- View snapshots if user can view the parent shell
CREATE POLICY "Users can view duty description snapshots of accessible shells"
  ON epb_duty_description_snapshots FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM epb_shells es
      WHERE es.id = epb_duty_description_snapshots.shell_id
    )
  );

-- Insert snapshots if user can update the parent shell
CREATE POLICY "Users can insert duty description snapshots for accessible shells"
  ON epb_duty_description_snapshots FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM epb_shells es
      WHERE es.id = epb_duty_description_snapshots.shell_id
      AND (
        (es.user_id = auth.uid() AND es.team_member_id IS NULL)
        OR
        (es.team_member_id IS NULL AND EXISTS (
          SELECT 1 FROM team_history th
          WHERE th.subordinate_id = es.user_id
          AND th.supervisor_id = auth.uid()
        ))
        OR
        (es.team_member_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM team_members tm
          WHERE tm.id = es.team_member_id
          AND tm.supervisor_id = auth.uid()
        ))
      )
    )
  );

-- Delete own snapshots
CREATE POLICY "Users can delete duty description snapshots they created"
  ON epb_duty_description_snapshots FOR DELETE
  USING (created_by = auth.uid());

-- ============================================
-- DUTY DESCRIPTION EXAMPLES POLICIES
-- ============================================

-- View examples if user can view the parent shell
CREATE POLICY "Users can view duty description examples of accessible shells"
  ON epb_duty_description_examples FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM epb_shells es
      WHERE es.id = epb_duty_description_examples.shell_id
    )
  );

-- Insert examples if user can update the parent shell
CREATE POLICY "Users can insert duty description examples for accessible shells"
  ON epb_duty_description_examples FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM epb_shells es
      WHERE es.id = epb_duty_description_examples.shell_id
      AND (
        (es.user_id = auth.uid() AND es.team_member_id IS NULL)
        OR
        (es.team_member_id IS NULL AND EXISTS (
          SELECT 1 FROM team_history th
          WHERE th.subordinate_id = es.user_id
          AND th.supervisor_id = auth.uid()
        ))
        OR
        (es.team_member_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM team_members tm
          WHERE tm.id = es.team_member_id
          AND tm.supervisor_id = auth.uid()
        ))
      )
    )
  );

-- Delete own examples
CREATE POLICY "Users can delete duty description examples they created"
  ON epb_duty_description_examples FOR DELETE
  USING (created_by = auth.uid());

