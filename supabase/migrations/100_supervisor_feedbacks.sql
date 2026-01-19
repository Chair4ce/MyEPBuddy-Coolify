-- Migration: Supervisor Feedbacks System
-- Allows supervisors to conduct feedback sessions (initial, midterm, final) for their subordinates
-- Feedbacks are private until shared with the subordinate

-- ============================================
-- CREATE TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS supervisor_feedbacks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supervisor_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  -- Either subordinate_id (real user) or team_member_id (managed member) must be set
  subordinate_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  team_member_id UUID REFERENCES team_members(id) ON DELETE CASCADE,
  -- Feedback type: initial (ACA + expectations), midterm (mid-cycle review), final (after EPB)
  feedback_type TEXT NOT NULL CHECK (feedback_type IN ('initial', 'midterm', 'final')),
  cycle_year INTEGER NOT NULL,
  -- Content
  content TEXT NOT NULL DEFAULT '',
  -- Accomplishments that were reviewed during this feedback (array of UUIDs)
  reviewed_accomplishment_ids UUID[] DEFAULT '{}',
  -- Status: draft (only supervisor can see) or shared (subordinate can see)
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'shared')),
  shared_at TIMESTAMPTZ,
  -- Supervision dates captured at creation for atomic permissions
  supervision_start_date DATE NOT NULL,
  supervision_end_date DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  -- Ensure exactly one of subordinate_id or team_member_id is set
  CONSTRAINT feedback_subordinate_or_team_member CHECK (
    (subordinate_id IS NOT NULL AND team_member_id IS NULL) OR
    (subordinate_id IS NULL AND team_member_id IS NOT NULL)
  )
);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_supervisor_feedbacks_supervisor 
  ON supervisor_feedbacks(supervisor_id);

CREATE INDEX IF NOT EXISTS idx_supervisor_feedbacks_subordinate 
  ON supervisor_feedbacks(subordinate_id) 
  WHERE subordinate_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_supervisor_feedbacks_team_member 
  ON supervisor_feedbacks(team_member_id) 
  WHERE team_member_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_supervisor_feedbacks_cycle_year 
  ON supervisor_feedbacks(cycle_year);

CREATE INDEX IF NOT EXISTS idx_supervisor_feedbacks_type_status 
  ON supervisor_feedbacks(feedback_type, status);

-- Unique constraint: one feedback per type per supervisor-subordinate pair per cycle year
CREATE UNIQUE INDEX IF NOT EXISTS idx_supervisor_feedbacks_unique_profile
  ON supervisor_feedbacks(supervisor_id, subordinate_id, feedback_type, cycle_year)
  WHERE subordinate_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_supervisor_feedbacks_unique_team_member
  ON supervisor_feedbacks(supervisor_id, team_member_id, feedback_type, cycle_year)
  WHERE team_member_id IS NOT NULL;

-- ============================================
-- TRIGGER FOR updated_at
-- ============================================

CREATE OR REPLACE FUNCTION update_supervisor_feedbacks_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_supervisor_feedbacks_updated_at ON supervisor_feedbacks;
CREATE TRIGGER trigger_update_supervisor_feedbacks_updated_at
  BEFORE UPDATE ON supervisor_feedbacks
  FOR EACH ROW
  EXECUTE FUNCTION update_supervisor_feedbacks_updated_at();

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE supervisor_feedbacks ENABLE ROW LEVEL SECURITY;

-- Supervisors can always read feedbacks they created
CREATE POLICY "Supervisors can read their own feedbacks"
  ON supervisor_feedbacks FOR SELECT
  USING (supervisor_id = auth.uid());

-- Subordinates can only read SHARED feedbacks set for them
CREATE POLICY "Subordinates can read shared feedbacks"
  ON supervisor_feedbacks FOR SELECT
  USING (
    subordinate_id = auth.uid() AND 
    status = 'shared'
  );

-- For managed members linked to a real user - only shared feedbacks
CREATE POLICY "Linked users can read shared feedbacks for their managed account"
  ON supervisor_feedbacks FOR SELECT
  USING (
    team_member_id IS NOT NULL AND
    status = 'shared' AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = supervisor_feedbacks.team_member_id
        AND tm.linked_user_id = auth.uid()
    )
  );

-- Supervisors can insert feedbacks for their current subordinates
CREATE POLICY "Supervisors can create feedbacks for subordinates"
  ON supervisor_feedbacks FOR INSERT
  WITH CHECK (
    supervisor_id = auth.uid() AND
    (
      -- For real subordinates: must be in active teams relationship
      (subordinate_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM teams t
        WHERE t.supervisor_id = auth.uid()
          AND t.subordinate_id = supervisor_feedbacks.subordinate_id
      ))
      OR
      -- For managed members: must be the supervisor
      (team_member_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM team_members tm
        WHERE tm.id = supervisor_feedbacks.team_member_id
          AND tm.supervisor_id = auth.uid()
      ))
    )
  );

-- Supervisors can update their own feedbacks
CREATE POLICY "Supervisors can update their own feedbacks"
  ON supervisor_feedbacks FOR UPDATE
  USING (supervisor_id = auth.uid())
  WITH CHECK (supervisor_id = auth.uid());

-- Supervisors can delete their own feedbacks (only drafts)
CREATE POLICY "Supervisors can delete their own draft feedbacks"
  ON supervisor_feedbacks FOR DELETE
  USING (supervisor_id = auth.uid() AND status = 'draft');

-- ============================================
-- FUNCTION TO UPSERT FEEDBACK
-- ============================================

CREATE OR REPLACE FUNCTION upsert_supervisor_feedback(
  p_subordinate_id UUID,
  p_team_member_id UUID,
  p_feedback_type TEXT,
  p_cycle_year INTEGER,
  p_content TEXT,
  p_reviewed_accomplishment_ids UUID[] DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_supervisor_id UUID := auth.uid();
  v_supervision_start DATE;
  v_supervision_end DATE;
  v_feedback_id UUID;
BEGIN
  -- Validate that at least one target is provided
  IF p_subordinate_id IS NULL AND p_team_member_id IS NULL THEN
    RAISE EXCEPTION 'Either subordinate_id or team_member_id must be provided';
  END IF;
  
  IF p_subordinate_id IS NOT NULL AND p_team_member_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only one of subordinate_id or team_member_id should be provided';
  END IF;

  -- Validate feedback type
  IF p_feedback_type NOT IN ('initial', 'midterm', 'final') THEN
    RAISE EXCEPTION 'Invalid feedback type. Must be initial, midterm, or final';
  END IF;

  -- Get supervision dates for real subordinate
  IF p_subordinate_id IS NOT NULL THEN
    SELECT supervision_start_date, supervision_end_date
    INTO v_supervision_start, v_supervision_end
    FROM teams
    WHERE supervisor_id = v_supervisor_id
      AND subordinate_id = p_subordinate_id;
    
    IF v_supervision_start IS NULL THEN
      RAISE EXCEPTION 'No active supervision relationship found';
    END IF;
  END IF;

  -- Get supervision dates for managed member
  IF p_team_member_id IS NOT NULL THEN
    SELECT supervision_start_date, supervision_end_date
    INTO v_supervision_start, v_supervision_end
    FROM team_members
    WHERE id = p_team_member_id
      AND supervisor_id = v_supervisor_id;
    
    IF v_supervision_start IS NULL THEN
      RAISE EXCEPTION 'No managed member relationship found';
    END IF;
  END IF;

  -- Try to update existing draft feedback first
  UPDATE supervisor_feedbacks
  SET 
    content = p_content,
    reviewed_accomplishment_ids = p_reviewed_accomplishment_ids,
    updated_at = now()
  WHERE supervisor_id = v_supervisor_id
    AND feedback_type = p_feedback_type
    AND cycle_year = p_cycle_year
    AND status = 'draft'  -- Only update drafts
    AND (
      (p_subordinate_id IS NOT NULL AND subordinate_id = p_subordinate_id) OR
      (p_team_member_id IS NOT NULL AND team_member_id = p_team_member_id)
    )
  RETURNING id INTO v_feedback_id;

  -- If no draft exists, insert new
  IF v_feedback_id IS NULL THEN
    INSERT INTO supervisor_feedbacks (
      supervisor_id,
      subordinate_id,
      team_member_id,
      feedback_type,
      cycle_year,
      content,
      reviewed_accomplishment_ids,
      supervision_start_date,
      supervision_end_date
    )
    VALUES (
      v_supervisor_id,
      p_subordinate_id,
      p_team_member_id,
      p_feedback_type,
      p_cycle_year,
      p_content,
      p_reviewed_accomplishment_ids,
      v_supervision_start,
      v_supervision_end
    )
    RETURNING id INTO v_feedback_id;
  END IF;

  RETURN v_feedback_id;
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_supervisor_feedback(UUID, UUID, TEXT, INTEGER, TEXT, UUID[]) TO authenticated;

-- ============================================
-- FUNCTION TO SHARE FEEDBACK
-- ============================================

CREATE OR REPLACE FUNCTION share_supervisor_feedback(
  p_feedback_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE supervisor_feedbacks
  SET 
    status = 'shared',
    shared_at = now(),
    updated_at = now()
  WHERE id = p_feedback_id
    AND supervisor_id = auth.uid()
    AND status = 'draft';
  
  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION share_supervisor_feedback(UUID) TO authenticated;

-- ============================================
-- FUNCTION TO UNSHARE FEEDBACK (revert to draft)
-- ============================================

CREATE OR REPLACE FUNCTION unshare_supervisor_feedback(
  p_feedback_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE supervisor_feedbacks
  SET 
    status = 'draft',
    shared_at = NULL,
    updated_at = now()
  WHERE id = p_feedback_id
    AND supervisor_id = auth.uid()
    AND status = 'shared';
  
  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION unshare_supervisor_feedback(UUID) TO authenticated;
