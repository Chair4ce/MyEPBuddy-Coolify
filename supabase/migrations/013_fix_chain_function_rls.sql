-- Fix the infinite recursion issue
-- The get_subordinate_chain function queries teams table which triggers RLS
-- which calls get_subordinate_chain again causing stack overflow

-- First drop all policies that depend on the function
DROP POLICY IF EXISTS "Chain supervisors can view subordinate chain accomplishments" ON accomplishments;
DROP POLICY IF EXISTS "Chain supervisors can view subordinate chain statement history" ON statement_history;
DROP POLICY IF EXISTS "Chain supervisors can view subordinate chain refined statements" ON refined_statements;
DROP POLICY IF EXISTS "Users can view teams in their chain" ON teams;

-- Now we can drop and recreate the function with SECURITY DEFINER
DROP FUNCTION IF EXISTS get_subordinate_chain(UUID);

CREATE OR REPLACE FUNCTION get_subordinate_chain(supervisor_uuid UUID)
RETURNS TABLE(subordinate_id UUID, depth INT) 
SECURITY DEFINER  -- This bypasses RLS when the function runs
SET search_path = public
AS $$
WITH RECURSIVE chain AS (
  -- Direct subordinates (depth 1)
  SELECT t.subordinate_id, 1 as depth
  FROM teams t
  WHERE t.supervisor_id = supervisor_uuid
  
  UNION ALL
  
  -- Subordinates of subordinates (depth + 1)
  SELECT t.subordinate_id, c.depth + 1
  FROM teams t
  INNER JOIN chain c ON t.supervisor_id = c.subordinate_id
  WHERE c.depth < 10 -- Prevent infinite loops, max 10 levels deep
)
SELECT * FROM chain;
$$ LANGUAGE SQL STABLE;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_subordinate_chain(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_subordinate_chain(UUID) TO anon;

-- Also fix get_supervisor_chain
DROP FUNCTION IF EXISTS get_supervisor_chain(UUID);

CREATE OR REPLACE FUNCTION get_supervisor_chain(subordinate_uuid UUID)
RETURNS TABLE(supervisor_id UUID, depth INT) 
SECURITY DEFINER
SET search_path = public
AS $$
WITH RECURSIVE chain AS (
  -- Direct supervisor (depth 1)
  SELECT t.supervisor_id, 1 as depth
  FROM teams t
  WHERE t.subordinate_id = subordinate_uuid
  
  UNION ALL
  
  -- Supervisor of supervisors (depth + 1)
  SELECT t.supervisor_id, c.depth + 1
  FROM teams t
  INNER JOIN chain c ON t.subordinate_id = c.supervisor_id
  WHERE c.depth < 10 -- Prevent infinite loops
)
SELECT * FROM chain;
$$ LANGUAGE SQL STABLE;

GRANT EXECUTE ON FUNCTION get_supervisor_chain(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_supervisor_chain(UUID) TO anon;

-- Recreate the policies using the updated function
-- Teams: Allow viewing teams in your chain
CREATE POLICY "Users can view teams in their chain"
  ON teams FOR SELECT
  USING (
    supervisor_id = auth.uid() 
    OR subordinate_id = auth.uid()
    OR supervisor_id IN (SELECT subordinate_id FROM get_subordinate_chain(auth.uid()))
  );

-- Accomplishments: Allow viewing subordinate chain's accomplishments
CREATE POLICY "Chain supervisors can view subordinate chain accomplishments"
  ON accomplishments FOR SELECT
  USING (
    user_id IN (SELECT subordinate_id FROM get_subordinate_chain(auth.uid()))
  );

-- Statement history: Allow viewing subordinate chain's history
CREATE POLICY "Chain supervisors can view subordinate chain statement history"
  ON statement_history FOR SELECT
  USING (
    ratee_id IN (SELECT subordinate_id FROM get_subordinate_chain(auth.uid()))
  );

-- Refined statements: Allow viewing subordinate chain's refined statements
CREATE POLICY "Chain supervisors can view subordinate chain refined statements"
  ON refined_statements FOR SELECT
  USING (
    user_id IN (SELECT subordinate_id FROM get_subordinate_chain(auth.uid()))
  );
