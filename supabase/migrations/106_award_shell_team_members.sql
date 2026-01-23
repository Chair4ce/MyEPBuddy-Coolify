-- Migration: Award Shell Team Members
-- Adds support for team awards where multiple members are nominated
-- Stores the team members associated with an award shell

-- ============================================================================
-- ALTER award_shells: Add is_team_award flag
-- ============================================================================

ALTER TABLE public.award_shells
ADD COLUMN IF NOT EXISTS is_team_award BOOLEAN NOT NULL DEFAULT FALSE;

-- Index for filtering team awards
CREATE INDEX IF NOT EXISTS idx_award_shells_is_team_award 
  ON public.award_shells(is_team_award) WHERE is_team_award = TRUE;

-- ============================================================================
-- TABLE: award_shell_team_members
-- Junction table for team award nominations
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.award_shell_team_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_id UUID NOT NULL REFERENCES public.award_shells(id) ON DELETE CASCADE,
  -- Either a real profile or a managed team member
  profile_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_member_id UUID REFERENCES public.team_members(id) ON DELETE CASCADE,
  -- Who added this member
  added_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- Timestamp
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  -- Either profile_id or team_member_id must be set, not both
  CONSTRAINT award_shell_team_members_check_member 
    CHECK (
      (profile_id IS NOT NULL AND team_member_id IS NULL) OR
      (profile_id IS NULL AND team_member_id IS NOT NULL)
    ),
  
  -- Unique member per shell (prevent duplicates)
  CONSTRAINT award_shell_team_members_unique_profile 
    UNIQUE NULLS NOT DISTINCT (shell_id, profile_id),
  CONSTRAINT award_shell_team_members_unique_team_member 
    UNIQUE NULLS NOT DISTINCT (shell_id, team_member_id)
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_award_shell_team_members_shell_id 
  ON public.award_shell_team_members(shell_id);
CREATE INDEX IF NOT EXISTS idx_award_shell_team_members_profile_id 
  ON public.award_shell_team_members(profile_id) WHERE profile_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_award_shell_team_members_team_member_id 
  ON public.award_shell_team_members(team_member_id) WHERE team_member_id IS NOT NULL;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.award_shell_team_members ENABLE ROW LEVEL SECURITY;

-- Users can view team members of shells they can access
CREATE POLICY "Users can view team members of accessible award shells"
  ON public.award_shell_team_members
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.award_shells aws
      WHERE aws.id = award_shell_team_members.shell_id
      -- RLS on award_shells will filter access
    )
  );

-- Users can add team members to shells they can update
CREATE POLICY "Users can add team members to accessible award shells"
  ON public.award_shell_team_members
  FOR INSERT
  TO authenticated
  WITH CHECK (
    added_by = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.award_shells aws
      WHERE aws.id = award_shell_team_members.shell_id
      AND (
        -- Own shell
        (aws.user_id = auth.uid() AND aws.team_member_id IS NULL)
        OR
        -- Supervisor via history
        (aws.team_member_id IS NULL AND EXISTS (
          SELECT 1 FROM public.team_history th
          WHERE th.subordinate_id = aws.user_id
          AND th.supervisor_id = auth.uid()
        ))
        OR
        -- Managed member
        (aws.team_member_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.team_members tm
          WHERE tm.id = aws.team_member_id
          AND tm.supervisor_id = auth.uid()
        ))
        OR
        -- Shell creator
        (aws.created_by = auth.uid())
      )
    )
  );

-- Users can remove team members from shells they can update
CREATE POLICY "Users can remove team members from accessible award shells"
  ON public.award_shell_team_members
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.award_shells aws
      WHERE aws.id = award_shell_team_members.shell_id
      AND (
        -- Own shell
        (aws.user_id = auth.uid() AND aws.team_member_id IS NULL)
        OR
        -- Supervisor via history
        (aws.team_member_id IS NULL AND EXISTS (
          SELECT 1 FROM public.team_history th
          WHERE th.subordinate_id = aws.user_id
          AND th.supervisor_id = auth.uid()
        ))
        OR
        -- Managed member
        (aws.team_member_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.team_members tm
          WHERE tm.id = aws.team_member_id
          AND tm.supervisor_id = auth.uid()
        ))
        OR
        -- Shell creator
        (aws.created_by = auth.uid())
      )
    )
  );

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT, INSERT, DELETE ON public.award_shell_team_members TO authenticated;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE public.award_shell_team_members IS 'Junction table for team award nominations - links team members to award shells';
COMMENT ON COLUMN public.award_shell_team_members.profile_id IS 'Real user profile ID (for subordinates with accounts)';
COMMENT ON COLUMN public.award_shell_team_members.team_member_id IS 'Managed team member ID (for placeholder subordinates)';
COMMENT ON COLUMN public.award_shells.is_team_award IS 'Whether this award package is for multiple team members';
