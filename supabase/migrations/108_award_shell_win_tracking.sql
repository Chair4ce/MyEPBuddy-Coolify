-- Migration: Award Shell Win Tracking
-- Adds fields to track whether an award package won and at what level
-- When marked as won, awards are applied to the team members tagged in the package

-- ============================================================================
-- CREATE win_level TYPE with new values
-- ============================================================================

-- Create a more comprehensive win level type that includes the requested levels
CREATE TYPE award_win_level AS ENUM (
  'flight',
  'squadron',
  'tenant_unit',
  'group',
  'wing',
  'haf',
  '12_oay'
);

-- ============================================================================
-- ALTER award_shells: Add win tracking fields
-- ============================================================================

-- Whether the award package won
ALTER TABLE public.award_shells
ADD COLUMN IF NOT EXISTS is_winner BOOLEAN NOT NULL DEFAULT FALSE;

-- The level at which the award won
ALTER TABLE public.award_shells
ADD COLUMN IF NOT EXISTS win_level award_win_level;

-- When the win was recorded
ALTER TABLE public.award_shells
ADD COLUMN IF NOT EXISTS won_at TIMESTAMPTZ;

-- Reference to the generated award record (if applicable)
ALTER TABLE public.award_shells
ADD COLUMN IF NOT EXISTS generated_award_id UUID REFERENCES public.awards(id) ON DELETE SET NULL;

-- Index for finding winning packages
CREATE INDEX IF NOT EXISTS idx_award_shells_is_winner 
  ON public.award_shells(is_winner) WHERE is_winner = TRUE;

-- Index for filtering by win level
CREATE INDEX IF NOT EXISTS idx_award_shells_win_level 
  ON public.award_shells(win_level) WHERE win_level IS NOT NULL;

-- ============================================================================
-- FUNCTION: apply_award_shell_win
-- Creates Award records for all team members when a package is marked as won
-- ============================================================================

CREATE OR REPLACE FUNCTION public.apply_award_shell_win(
  p_shell_id UUID,
  p_win_level award_win_level
)
RETURNS UUID AS $$
DECLARE
  v_shell public.award_shells;
  v_award_id UUID;
  v_award_type award_type;
  v_award_level award_level;
  v_quarter award_quarter;
  v_team_member RECORD;
BEGIN
  -- Get the shell
  SELECT * INTO v_shell FROM public.award_shells WHERE id = p_shell_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Award shell not found';
  END IF;
  
  -- Only the creator can mark as won
  IF v_shell.created_by != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized to mark this award as won';
  END IF;
  
  -- Map period type to award type
  v_award_type := CASE v_shell.award_period_type
    WHEN 'annual' THEN 'annual'::award_type
    WHEN 'quarterly' THEN 'quarterly'::award_type
    WHEN 'special' THEN 'special'::award_type
    ELSE 'annual'::award_type
  END;
  
  -- Map win level to award level (closest match)
  v_award_level := CASE p_win_level
    WHEN 'flight' THEN 'squadron'::award_level
    WHEN 'squadron' THEN 'squadron'::award_level
    WHEN 'tenant_unit' THEN 'squadron'::award_level
    WHEN 'group' THEN 'group'::award_level
    WHEN 'wing' THEN 'wing'::award_level
    WHEN 'haf' THEN 'haf'::award_level
    WHEN '12_oay' THEN 'haf'::award_level
    ELSE 'squadron'::award_level
  END;
  
  -- Map quarter if quarterly
  v_quarter := CASE v_shell.quarter
    WHEN 1 THEN 'Q1'::award_quarter
    WHEN 2 THEN 'Q2'::award_quarter
    WHEN 3 THEN 'Q3'::award_quarter
    WHEN 4 THEN 'Q4'::award_quarter
    ELSE NULL
  END;
  
  -- For team awards, create awards for each team member
  IF v_shell.is_team_award THEN
    -- Create awards for each team member in the shell
    FOR v_team_member IN 
      SELECT profile_id, team_member_id 
      FROM public.award_shell_team_members 
      WHERE shell_id = p_shell_id
    LOOP
      INSERT INTO public.awards (
        recipient_profile_id,
        recipient_team_member_id,
        created_by,
        supervisor_id,
        award_type,
        award_name,
        quarter,
        award_year,
        period_start,
        period_end,
        award_level,
        award_category,
        is_team_award,
        cycle_year
      ) VALUES (
        v_team_member.profile_id,
        v_team_member.team_member_id,
        v_shell.created_by,
        v_shell.created_by,
        v_award_type,
        CASE p_win_level 
          WHEN '12_oay' THEN '12 Outstanding Airmen of the Year'
          ELSE NULL
        END,
        v_quarter,
        v_shell.cycle_year,
        v_shell.period_start_date::DATE,
        v_shell.period_end_date::DATE,
        v_award_level,
        v_shell.award_category::award_category,
        TRUE,
        v_shell.cycle_year
      ) RETURNING id INTO v_award_id;
    END LOOP;
  ELSE
    -- Single recipient award
    INSERT INTO public.awards (
      recipient_profile_id,
      recipient_team_member_id,
      created_by,
      supervisor_id,
      award_type,
      award_name,
      quarter,
      award_year,
      period_start,
      period_end,
      award_level,
      award_category,
      is_team_award,
      cycle_year
    ) VALUES (
      CASE WHEN v_shell.team_member_id IS NULL THEN v_shell.user_id ELSE NULL END,
      v_shell.team_member_id,
      v_shell.created_by,
      v_shell.created_by,
      v_award_type,
      CASE p_win_level 
        WHEN '12_oay' THEN '12 Outstanding Airmen of the Year'
        ELSE NULL
      END,
      v_quarter,
      v_shell.cycle_year,
      v_shell.period_start_date::DATE,
      v_shell.period_end_date::DATE,
      v_award_level,
      v_shell.award_category::award_category,
      FALSE,
      v_shell.cycle_year
    ) RETURNING id INTO v_award_id;
  END IF;
  
  -- Update the shell with win info
  UPDATE public.award_shells
  SET 
    is_winner = TRUE,
    win_level = p_win_level,
    won_at = now(),
    generated_award_id = v_award_id,
    updated_at = now()
  WHERE id = p_shell_id;
  
  RETURN v_award_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: revoke_award_shell_win
-- Removes the win status and deletes generated awards
-- ============================================================================

CREATE OR REPLACE FUNCTION public.revoke_award_shell_win(p_shell_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_shell public.award_shells;
BEGIN
  -- Get the shell
  SELECT * INTO v_shell FROM public.award_shells WHERE id = p_shell_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Award shell not found';
  END IF;
  
  -- Only the creator can revoke
  IF v_shell.created_by != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized to revoke this award';
  END IF;
  
  -- Delete generated awards (both for team and individual)
  -- For team awards, delete all awards that match the shell criteria
  DELETE FROM public.awards
  WHERE (
    -- Direct reference
    id = v_shell.generated_award_id
    OR
    -- Team member awards (match by created_by, cycle_year, and period)
    (
      created_by = v_shell.created_by
      AND cycle_year = v_shell.cycle_year
      AND period_start = v_shell.period_start_date::DATE
      AND period_end = v_shell.period_end_date::DATE
      AND (
        recipient_profile_id IN (
          SELECT profile_id FROM public.award_shell_team_members WHERE shell_id = p_shell_id
        )
        OR recipient_team_member_id IN (
          SELECT team_member_id FROM public.award_shell_team_members WHERE shell_id = p_shell_id
        )
      )
    )
  );
  
  -- Update the shell
  UPDATE public.award_shells
  SET 
    is_winner = FALSE,
    win_level = NULL,
    won_at = NULL,
    generated_award_id = NULL,
    updated_at = now()
  WHERE id = p_shell_id;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.apply_award_shell_win(UUID, award_win_level) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_award_shell_win(UUID) TO authenticated;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON COLUMN public.award_shells.is_winner IS 'Whether this award package won at any level';
COMMENT ON COLUMN public.award_shells.win_level IS 'The level at which the award package won';
COMMENT ON COLUMN public.award_shells.won_at IS 'Timestamp when the win was recorded';
COMMENT ON COLUMN public.award_shells.generated_award_id IS 'Reference to the Award record generated when marked as won';
COMMENT ON FUNCTION public.apply_award_shell_win IS 'Marks an award shell as won and creates Award records for all tagged team members';
COMMENT ON FUNCTION public.revoke_award_shell_win IS 'Revokes the win status and removes generated awards';
