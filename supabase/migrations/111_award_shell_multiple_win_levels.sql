-- Migration: Award Shell Multiple Win Levels
-- Supports multiple win levels per award package as awards progress through levels over time
-- e.g., an award can win at Squadron, then Group, then Wing, etc.

-- ============================================================================
-- TABLE: award_shell_wins
-- Tracks each level an award shell has won at
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.award_shell_wins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_id UUID NOT NULL REFERENCES public.award_shells(id) ON DELETE CASCADE,
  win_level award_win_level NOT NULL,
  won_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  added_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- Generated award reference (if applicable - for the first win or highest level)
  generated_award_id UUID REFERENCES public.awards(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  
  -- Each shell can only win once at each level
  CONSTRAINT award_shell_wins_unique_level 
    UNIQUE (shell_id, win_level)
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_award_shell_wins_shell_id 
  ON public.award_shell_wins(shell_id);
CREATE INDEX IF NOT EXISTS idx_award_shell_wins_level 
  ON public.award_shell_wins(win_level);

-- ============================================================================
-- MIGRATE EXISTING DATA
-- Move existing win data from award_shells to the new table
-- ============================================================================

INSERT INTO public.award_shell_wins (shell_id, win_level, won_at, added_by, generated_award_id, created_at)
SELECT 
  id,
  win_level,
  COALESCE(won_at, now()),
  created_by,
  generated_award_id,
  COALESCE(won_at, now())
FROM public.award_shells
WHERE is_winner = TRUE AND win_level IS NOT NULL;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.award_shell_wins ENABLE ROW LEVEL SECURITY;

-- Users can view wins for shells they can access
CREATE POLICY "Users can view wins for accessible award shells"
  ON public.award_shell_wins
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.award_shells aws
      WHERE aws.id = award_shell_wins.shell_id
      -- RLS on award_shells will filter access
    )
  );

-- Users can add wins to shells they created
CREATE POLICY "Users can add wins to their award shells"
  ON public.award_shell_wins
  FOR INSERT
  TO authenticated
  WITH CHECK (
    added_by = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.award_shells aws
      WHERE aws.id = award_shell_wins.shell_id
      AND aws.created_by = auth.uid()
    )
  );

-- Users can delete wins from shells they created
CREATE POLICY "Users can delete wins from their award shells"
  ON public.award_shell_wins
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.award_shells aws
      WHERE aws.id = award_shell_wins.shell_id
      AND aws.created_by = auth.uid()
    )
  );

-- ============================================================================
-- FUNCTION: add_award_shell_win_level
-- Adds a win level to an award shell and creates/updates awards for team members
-- ============================================================================

CREATE OR REPLACE FUNCTION public.add_award_shell_win_level(
  p_shell_id UUID,
  p_win_level award_win_level
)
RETURNS UUID AS $$
DECLARE
  v_shell public.award_shells;
  v_existing_win public.award_shell_wins;
  v_win_id UUID;
  v_award_id UUID;
  v_award_type award_type;
  v_award_level award_level;
  v_quarter award_quarter;
  v_team_member RECORD;
  v_highest_level award_win_level;
BEGIN
  -- Get the shell
  SELECT * INTO v_shell FROM public.award_shells WHERE id = p_shell_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Award shell not found';
  END IF;
  
  -- Only the creator can add wins
  IF v_shell.created_by != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized to add wins to this award';
  END IF;
  
  -- Check if already won at this level
  SELECT * INTO v_existing_win 
  FROM public.award_shell_wins 
  WHERE shell_id = p_shell_id AND win_level = p_win_level;
  
  IF FOUND THEN
    -- Already won at this level, just return existing
    RETURN v_existing_win.id;
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
  
  -- Delete existing awards for this shell (we'll recreate at highest level)
  DELETE FROM public.awards
  WHERE id IN (
    SELECT generated_award_id FROM public.award_shell_wins WHERE shell_id = p_shell_id
  );
  
  -- Also delete any awards that match the shell criteria for team members
  IF v_shell.is_team_award THEN
    DELETE FROM public.awards
    WHERE created_by = v_shell.created_by
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
      );
  END IF;
  
  -- Insert the new win record
  INSERT INTO public.award_shell_wins (shell_id, win_level, added_by)
  VALUES (p_shell_id, p_win_level, auth.uid())
  RETURNING id INTO v_win_id;
  
  -- Determine the highest win level for this shell
  SELECT win_level INTO v_highest_level
  FROM public.award_shell_wins
  WHERE shell_id = p_shell_id
  ORDER BY 
    CASE win_level
      WHEN '12_oay' THEN 7
      WHEN 'haf' THEN 6
      WHEN 'wing' THEN 5
      WHEN 'group' THEN 4
      WHEN 'tenant_unit' THEN 3
      WHEN 'squadron' THEN 2
      WHEN 'flight' THEN 1
      ELSE 0
    END DESC
  LIMIT 1;
  
  -- Update award_level based on highest win level
  v_award_level := CASE v_highest_level
    WHEN 'flight' THEN 'squadron'::award_level
    WHEN 'squadron' THEN 'squadron'::award_level
    WHEN 'tenant_unit' THEN 'squadron'::award_level
    WHEN 'group' THEN 'group'::award_level
    WHEN 'wing' THEN 'wing'::award_level
    WHEN 'haf' THEN 'haf'::award_level
    WHEN '12_oay' THEN 'haf'::award_level
    ELSE 'squadron'::award_level
  END;
  
  -- Create awards at the highest level for team members
  IF v_shell.is_team_award THEN
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
        CASE v_highest_level 
          WHEN '12_oay' THEN '12 Outstanding Airmen of the Year'
          ELSE v_shell.title
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
      CASE v_highest_level 
        WHEN '12_oay' THEN '12 Outstanding Airmen of the Year'
        ELSE v_shell.title
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
  
  -- Update the win record with the generated award ID
  UPDATE public.award_shell_wins
  SET generated_award_id = v_award_id
  WHERE id = v_win_id;
  
  -- Update the shell to mark as winner
  UPDATE public.award_shells
  SET 
    is_winner = TRUE,
    win_level = v_highest_level,
    won_at = COALESCE(won_at, now()),
    generated_award_id = v_award_id,
    updated_at = now()
  WHERE id = p_shell_id;
  
  RETURN v_win_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: remove_award_shell_win_level
-- Removes a win level from an award shell and updates awards
-- ============================================================================

CREATE OR REPLACE FUNCTION public.remove_award_shell_win_level(
  p_shell_id UUID,
  p_win_level award_win_level
)
RETURNS BOOLEAN AS $$
DECLARE
  v_shell public.award_shells;
  v_remaining_wins INTEGER;
  v_highest_level award_win_level;
BEGIN
  -- Get the shell
  SELECT * INTO v_shell FROM public.award_shells WHERE id = p_shell_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Award shell not found';
  END IF;
  
  -- Only the creator can remove wins
  IF v_shell.created_by != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized to remove wins from this award';
  END IF;
  
  -- Delete the win record
  DELETE FROM public.award_shell_wins
  WHERE shell_id = p_shell_id AND win_level = p_win_level;
  
  -- Count remaining wins
  SELECT COUNT(*) INTO v_remaining_wins
  FROM public.award_shell_wins
  WHERE shell_id = p_shell_id;
  
  IF v_remaining_wins = 0 THEN
    -- No more wins - delete all awards and reset shell
    DELETE FROM public.awards
    WHERE id = v_shell.generated_award_id;
    
    -- Delete team member awards
    IF v_shell.is_team_award THEN
      DELETE FROM public.awards
      WHERE created_by = v_shell.created_by
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
        );
    END IF;
    
    UPDATE public.award_shells
    SET 
      is_winner = FALSE,
      win_level = NULL,
      won_at = NULL,
      generated_award_id = NULL,
      updated_at = now()
    WHERE id = p_shell_id;
  ELSE
    -- Recalculate highest level and update awards
    SELECT win_level INTO v_highest_level
    FROM public.award_shell_wins
    WHERE shell_id = p_shell_id
    ORDER BY 
      CASE win_level
        WHEN '12_oay' THEN 7
        WHEN 'haf' THEN 6
        WHEN 'wing' THEN 5
        WHEN 'group' THEN 4
        WHEN 'tenant_unit' THEN 3
        WHEN 'squadron' THEN 2
        WHEN 'flight' THEN 1
        ELSE 0
      END DESC
    LIMIT 1;
    
    -- Re-add at highest remaining level to update awards
    PERFORM public.add_award_shell_win_level(p_shell_id, v_highest_level);
  END IF;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- DROP OLD FUNCTIONS (replaced by new ones)
-- ============================================================================

DROP FUNCTION IF EXISTS public.apply_award_shell_win(UUID, award_win_level);
DROP FUNCTION IF EXISTS public.revoke_award_shell_win(UUID);

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT SELECT, INSERT, DELETE ON public.award_shell_wins TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_award_shell_win_level(UUID, award_win_level) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_award_shell_win_level(UUID, award_win_level) TO authenticated;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE public.award_shell_wins IS 'Tracks each level an award shell has won at - awards can progress through multiple levels over time';
COMMENT ON COLUMN public.award_shell_wins.win_level IS 'The level at which the award won';
COMMENT ON COLUMN public.award_shell_wins.won_at IS 'When this win level was recorded';
COMMENT ON FUNCTION public.add_award_shell_win_level IS 'Adds a win level to an award shell and creates/updates Award records for team members at the highest level';
COMMENT ON FUNCTION public.remove_award_shell_win_level IS 'Removes a win level from an award shell and updates Award records accordingly';
