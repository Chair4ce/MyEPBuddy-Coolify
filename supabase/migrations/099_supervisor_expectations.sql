-- Migration: Supervisor Expectations System
-- Allows supervisors to set private expectations for their subordinates
-- Expectations are atomic to the supervision relationship and persist after supervision ends

-- ============================================
-- CREATE TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS supervisor_expectations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supervisor_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  -- Either subordinate_id (real user) or team_member_id (managed member) must be set
  subordinate_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  team_member_id UUID REFERENCES team_members(id) ON DELETE CASCADE,
  expectation_text TEXT NOT NULL,
  -- Supervision dates captured at creation for atomic permissions
  supervision_start_date DATE NOT NULL,
  supervision_end_date DATE,
  cycle_year INTEGER NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  -- Ensure exactly one of subordinate_id or team_member_id is set
  CONSTRAINT subordinate_or_team_member CHECK (
    (subordinate_id IS NOT NULL AND team_member_id IS NULL) OR
    (subordinate_id IS NULL AND team_member_id IS NOT NULL)
  )
);

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_supervisor_expectations_supervisor 
  ON supervisor_expectations(supervisor_id);

CREATE INDEX IF NOT EXISTS idx_supervisor_expectations_subordinate 
  ON supervisor_expectations(subordinate_id) 
  WHERE subordinate_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_supervisor_expectations_team_member 
  ON supervisor_expectations(team_member_id) 
  WHERE team_member_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_supervisor_expectations_cycle_year 
  ON supervisor_expectations(cycle_year);

-- Unique constraint: one expectation per supervisor-subordinate pair per cycle year
CREATE UNIQUE INDEX IF NOT EXISTS idx_supervisor_expectations_unique_profile
  ON supervisor_expectations(supervisor_id, subordinate_id, cycle_year)
  WHERE subordinate_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_supervisor_expectations_unique_team_member
  ON supervisor_expectations(supervisor_id, team_member_id, cycle_year)
  WHERE team_member_id IS NOT NULL;

-- ============================================
-- TRIGGER FOR updated_at
-- ============================================

CREATE OR REPLACE FUNCTION update_supervisor_expectations_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_supervisor_expectations_updated_at ON supervisor_expectations;
CREATE TRIGGER trigger_update_supervisor_expectations_updated_at
  BEFORE UPDATE ON supervisor_expectations
  FOR EACH ROW
  EXECUTE FUNCTION update_supervisor_expectations_updated_at();

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE supervisor_expectations ENABLE ROW LEVEL SECURITY;

-- Supervisors can read expectations they created
CREATE POLICY "Supervisors can read their own expectations"
  ON supervisor_expectations FOR SELECT
  USING (supervisor_id = auth.uid());

-- Subordinates can read expectations set for them
-- For real users: check subordinate_id matches
CREATE POLICY "Subordinates can read expectations set for them"
  ON supervisor_expectations FOR SELECT
  USING (subordinate_id = auth.uid());

-- For managed members linked to a real user
CREATE POLICY "Linked users can read expectations for their managed account"
  ON supervisor_expectations FOR SELECT
  USING (
    team_member_id IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = supervisor_expectations.team_member_id
        AND tm.linked_user_id = auth.uid()
    )
  );

-- Supervisors can insert expectations for their current subordinates
CREATE POLICY "Supervisors can create expectations for subordinates"
  ON supervisor_expectations FOR INSERT
  WITH CHECK (
    supervisor_id = auth.uid() AND
    (
      -- For real subordinates: must be in active teams relationship
      (subordinate_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM teams t
        WHERE t.supervisor_id = auth.uid()
          AND t.subordinate_id = supervisor_expectations.subordinate_id
      ))
      OR
      -- For managed members: must be the supervisor
      (team_member_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM team_members tm
        WHERE tm.id = supervisor_expectations.team_member_id
          AND tm.supervisor_id = auth.uid()
      ))
    )
  );

-- Supervisors can update their own expectations
CREATE POLICY "Supervisors can update their own expectations"
  ON supervisor_expectations FOR UPDATE
  USING (supervisor_id = auth.uid())
  WITH CHECK (supervisor_id = auth.uid());

-- Supervisors can delete their own expectations
CREATE POLICY "Supervisors can delete their own expectations"
  ON supervisor_expectations FOR DELETE
  USING (supervisor_id = auth.uid());

-- ============================================
-- FUNCTION TO GET OR CREATE EXPECTATION
-- ============================================

CREATE OR REPLACE FUNCTION upsert_supervisor_expectation(
  p_subordinate_id UUID,
  p_team_member_id UUID,
  p_expectation_text TEXT,
  p_cycle_year INTEGER
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
  v_expectation_id UUID;
BEGIN
  -- Validate that at least one target is provided
  IF p_subordinate_id IS NULL AND p_team_member_id IS NULL THEN
    RAISE EXCEPTION 'Either subordinate_id or team_member_id must be provided';
  END IF;
  
  IF p_subordinate_id IS NOT NULL AND p_team_member_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only one of subordinate_id or team_member_id should be provided';
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

  -- Upsert the expectation
  INSERT INTO supervisor_expectations (
    supervisor_id,
    subordinate_id,
    team_member_id,
    expectation_text,
    supervision_start_date,
    supervision_end_date,
    cycle_year
  )
  VALUES (
    v_supervisor_id,
    p_subordinate_id,
    p_team_member_id,
    p_expectation_text,
    v_supervision_start,
    v_supervision_end,
    p_cycle_year
  )
  ON CONFLICT (supervisor_id, subordinate_id, cycle_year) WHERE subordinate_id IS NOT NULL
  DO UPDATE SET
    expectation_text = EXCLUDED.expectation_text,
    updated_at = now()
  RETURNING id INTO v_expectation_id;

  -- Handle team_member conflict separately (can't have multiple ON CONFLICT)
  IF v_expectation_id IS NULL AND p_team_member_id IS NOT NULL THEN
    UPDATE supervisor_expectations
    SET expectation_text = p_expectation_text,
        updated_at = now()
    WHERE supervisor_id = v_supervisor_id
      AND team_member_id = p_team_member_id
      AND cycle_year = p_cycle_year
    RETURNING id INTO v_expectation_id;
    
    -- If no update happened, insert
    IF v_expectation_id IS NULL THEN
      INSERT INTO supervisor_expectations (
        supervisor_id,
        subordinate_id,
        team_member_id,
        expectation_text,
        supervision_start_date,
        supervision_end_date,
        cycle_year
      )
      VALUES (
        v_supervisor_id,
        NULL,
        p_team_member_id,
        p_expectation_text,
        v_supervision_start,
        v_supervision_end,
        p_cycle_year
      )
      RETURNING id INTO v_expectation_id;
    END IF;
  END IF;

  RETURN v_expectation_id;
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_supervisor_expectation(UUID, UUID, TEXT, INTEGER) TO authenticated;

-- ============================================
-- FUNCTION TO GET EXPECTATIONS FOR A MEMBER
-- ============================================

CREATE OR REPLACE FUNCTION get_expectations_for_member(
  p_subordinate_id UUID DEFAULT NULL,
  p_team_member_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  supervisor_id UUID,
  subordinate_id UUID,
  team_member_id UUID,
  expectation_text TEXT,
  supervision_start_date DATE,
  supervision_end_date DATE,
  cycle_year INTEGER,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  supervisor_name TEXT,
  supervisor_rank TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    se.id,
    se.supervisor_id,
    se.subordinate_id,
    se.team_member_id,
    se.expectation_text,
    se.supervision_start_date,
    se.supervision_end_date,
    se.cycle_year,
    se.created_at,
    se.updated_at,
    p.full_name AS supervisor_name,
    p.rank::TEXT AS supervisor_rank
  FROM supervisor_expectations se
  JOIN profiles p ON p.id = se.supervisor_id
  WHERE 
    -- Supervisor can see their own expectations
    (se.supervisor_id = auth.uid())
    OR
    -- Subordinate can see expectations set for them
    (p_subordinate_id IS NOT NULL AND se.subordinate_id = p_subordinate_id AND p_subordinate_id = auth.uid())
    OR
    -- For managed members, linked user can see
    (p_team_member_id IS NOT NULL AND se.team_member_id = p_team_member_id AND EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = p_team_member_id AND tm.linked_user_id = auth.uid()
    ))
  ORDER BY se.cycle_year DESC, se.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_expectations_for_member(UUID, UUID) TO authenticated;
