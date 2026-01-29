-- Decoration Shell Snapshots
-- Snapshot history for citation versions - allows "time capsule" viewing and restoration
-- Mirrors the EPB shell snapshots pattern

-- ============================================
-- DECORATION SHELL SNAPSHOTS TABLE
-- ============================================
CREATE TABLE decoration_shell_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_id UUID NOT NULL REFERENCES decoration_shells(id) ON DELETE CASCADE,
  -- Snapshot of the citation text
  citation_text TEXT NOT NULL,
  -- Who created this snapshot
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  -- Optional note/label for the snapshot
  note TEXT,
  -- Timestamp
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX idx_decoration_shell_snapshots_shell ON decoration_shell_snapshots(shell_id);
CREATE INDEX idx_decoration_shell_snapshots_created_at ON decoration_shell_snapshots(created_at DESC);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE decoration_shell_snapshots ENABLE ROW LEVEL SECURITY;

-- ============================================
-- DECORATION SHELL SNAPSHOTS POLICIES
-- ============================================

-- View snapshots if user can view the parent shell
CREATE POLICY "Users can view snapshots of accessible decoration shells"
  ON decoration_shell_snapshots FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM decoration_shells ds
      WHERE ds.id = decoration_shell_snapshots.shell_id
    )
  );

-- Insert snapshots if user can update the parent shell
CREATE POLICY "Users can insert snapshots for accessible decoration shells"
  ON decoration_shell_snapshots FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM decoration_shells ds
      WHERE ds.id = decoration_shell_snapshots.shell_id
      AND (
        -- Own shell
        (ds.user_id = auth.uid() AND ds.team_member_id IS NULL)
        OR
        -- Supervisor via history
        (ds.team_member_id IS NULL AND EXISTS (
          SELECT 1 FROM team_history th
          WHERE th.subordinate_id = ds.user_id
          AND th.supervisor_id = auth.uid()
        ))
        OR
        -- Managed member
        (ds.team_member_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM team_members tm
          WHERE tm.id = ds.team_member_id
          AND tm.supervisor_id = auth.uid()
        ))
      )
    )
  );

-- Delete own snapshots
CREATE POLICY "Users can delete decoration snapshots they created"
  ON decoration_shell_snapshots FOR DELETE
  USING (created_by = auth.uid());
