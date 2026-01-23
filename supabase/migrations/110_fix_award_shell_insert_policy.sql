-- Migration: Fix Award Shell Insert Policy
-- Updates the insert policy to check team_history instead of just teams table
-- This ensures supervisors can create shells for subordinates they supervise/supervised

-- Drop the existing restrictive policy
DROP POLICY IF EXISTS "Supervisors can create subordinate award shells" ON public.award_shells;

-- Create updated policy that checks team_history (includes current and historical relationships)
CREATE POLICY "Supervisors can create subordinate award shells"
  ON public.award_shells FOR INSERT
  WITH CHECK (
    created_by = (SELECT auth.uid()) AND
    team_member_id IS NULL AND
    (
      -- User creating their own shell (covered by other policy, but include for safety)
      user_id = (SELECT auth.uid())
      OR
      -- Current supervisor via teams table
      EXISTS (
        SELECT 1 FROM public.teams t
        WHERE t.subordinate_id = award_shells.user_id
        AND t.supervisor_id = (SELECT auth.uid())
      )
      OR
      -- Historical supervisor via team_history
      EXISTS (
        SELECT 1 FROM public.team_history th
        WHERE th.subordinate_id = award_shells.user_id
        AND th.supervisor_id = (SELECT auth.uid())
      )
    )
  );

-- Add comment
COMMENT ON POLICY "Supervisors can create subordinate award shells" ON public.award_shells 
  IS 'Allows supervisors to create award shells for current or former subordinates';
