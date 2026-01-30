-- Migration 117: Fix remaining functions with mutable search_path
-- These functions were created after migration 066 and need search_path fixed

-- ============================================================================
-- FIX archive_epb_shell
-- ============================================================================

CREATE OR REPLACE FUNCTION public.archive_epb_shell(
  p_shell_id UUID,
  p_archive_name TEXT DEFAULT NULL,
  p_clear_after_archive BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
  success BOOLEAN,
  statements_saved INTEGER,
  shell_id UUID,
  error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_shell RECORD;
  v_section RECORD;
  v_statements_saved INTEGER := 0;
  v_user_id UUID;
  v_team_member_id UUID;
  v_afsc TEXT;
  v_rank TEXT;
BEGIN
  -- Get the shell and validate ownership/access
  SELECT * INTO v_shell
  FROM public.epb_shells
  WHERE id = p_shell_id
  AND (
    -- Own shell
    (user_id = auth.uid() AND team_member_id IS NULL)
    OR
    -- Supervisor via team history
    (team_member_id IS NULL AND EXISTS (
      SELECT 1 FROM public.team_history th
      WHERE th.subordinate_id = public.epb_shells.user_id
      AND th.supervisor_id = auth.uid()
    ))
    OR
    -- Managed member
    (team_member_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.team_members tm
      WHERE tm.id = public.epb_shells.team_member_id
      AND tm.supervisor_id = auth.uid()
    ))
  );

  IF v_shell IS NULL THEN
    RETURN QUERY SELECT FALSE, 0, NULL::UUID, 'Shell not found or access denied';
    RETURN;
  END IF;

  IF v_shell.status = 'archived' THEN
    RETURN QUERY SELECT FALSE, 0, v_shell.id, 'Shell is already archived';
    RETURN;
  END IF;

  -- Get user info for the ratee
  IF v_shell.team_member_id IS NOT NULL THEN
    -- Managed member - get info from team_members table
    SELECT tm.afsc, tm.rank INTO v_afsc, v_rank
    FROM public.team_members tm
    WHERE tm.id = v_shell.team_member_id;
    
    v_user_id := v_shell.user_id;
    v_team_member_id := v_shell.team_member_id;
  ELSE
    -- Real user - get info from profiles table
    SELECT p.afsc, p.rank INTO v_afsc, v_rank
    FROM public.profiles p
    WHERE p.id = v_shell.user_id;
    
    v_user_id := v_shell.user_id;
    v_team_member_id := NULL;
  END IF;

  -- Copy each non-empty section statement to refined_statements
  FOR v_section IN 
    SELECT ess.* FROM public.epb_shell_sections ess
    WHERE ess.shell_id = p_shell_id
    AND ess.statement_text IS NOT NULL 
    AND trim(ess.statement_text) != ''
    AND length(trim(ess.statement_text)) > 10
  LOOP
    INSERT INTO public.refined_statements (
      user_id,
      created_by,
      team_member_id,
      mpa,
      afsc,
      rank,
      statement,
      cycle_year,
      statement_type,
      source_epb_shell_id,
      is_favorite,
      applicable_mpas
    ) VALUES (
      v_user_id,
      auth.uid(),
      v_team_member_id,
      v_section.mpa,
      COALESCE(v_afsc, 'UNKNOWN'),
      COALESCE(v_rank, 'Amn')::public.user_rank,
      v_section.statement_text,
      v_shell.cycle_year,
      'epb',
      p_shell_id,
      FALSE,
      ARRAY[v_section.mpa]
    );
    
    v_statements_saved := v_statements_saved + 1;
  END LOOP;

  -- Update the shell status to archived
  UPDATE public.epb_shells
  SET 
    status = 'archived',
    archived_at = now(),
    archive_name = COALESCE(p_archive_name, 'EPB ' || v_shell.cycle_year)
  WHERE id = p_shell_id;

  -- Optionally clear the sections after archiving
  IF p_clear_after_archive THEN
    UPDATE public.epb_shell_sections ess_update
    SET 
      statement_text = '',
      is_complete = FALSE,
      updated_at = now()
    WHERE ess_update.shell_id = p_shell_id;
  END IF;

  RETURN QUERY SELECT TRUE, v_statements_saved, p_shell_id, NULL::TEXT;
END;
$$;

-- ============================================================================
-- FIX add_award_shell_win_level
-- ============================================================================

CREATE OR REPLACE FUNCTION public.add_award_shell_win_level(
  p_shell_id UUID,
  p_win_level public.award_win_level
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_shell public.award_shells;
  v_existing_win public.award_shell_wins;
  v_win_id UUID;
  v_award_id UUID;
  v_award_type public.award_type;
  v_award_level public.award_level;
  v_quarter public.award_quarter;
  v_team_member RECORD;
  v_highest_level public.award_win_level;
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
    RETURN v_existing_win.id;
  END IF;
  
  -- Map period type to award type
  v_award_type := CASE v_shell.award_period_type
    WHEN 'annual' THEN 'annual'::public.award_type
    WHEN 'quarterly' THEN 'quarterly'::public.award_type
    WHEN 'special' THEN 'special'::public.award_type
    ELSE 'annual'::public.award_type
  END;
  
  -- Map win level to award level
  v_award_level := CASE p_win_level
    WHEN 'flight' THEN 'squadron'::public.award_level
    WHEN 'squadron' THEN 'squadron'::public.award_level
    WHEN 'tenant_unit' THEN 'squadron'::public.award_level
    WHEN 'group' THEN 'group'::public.award_level
    WHEN 'wing' THEN 'wing'::public.award_level
    WHEN 'haf' THEN 'haf'::public.award_level
    WHEN '12_oay' THEN 'haf'::public.award_level
    ELSE 'squadron'::public.award_level
  END;
  
  -- Map quarter if quarterly
  v_quarter := CASE v_shell.quarter
    WHEN 1 THEN 'Q1'::public.award_quarter
    WHEN 2 THEN 'Q2'::public.award_quarter
    WHEN 3 THEN 'Q3'::public.award_quarter
    WHEN 4 THEN 'Q4'::public.award_quarter
    ELSE NULL
  END;
  
  -- Delete existing awards for this shell
  DELETE FROM public.awards
  WHERE id IN (
    SELECT generated_award_id FROM public.award_shell_wins WHERE shell_id = p_shell_id
  );
  
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
  
  -- Insert the new win record
  INSERT INTO public.award_shell_wins (shell_id, win_level, added_by)
  VALUES (p_shell_id, p_win_level, auth.uid())
  RETURNING id INTO v_win_id;
  
  -- Determine the highest win level
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
    WHEN 'flight' THEN 'squadron'::public.award_level
    WHEN 'squadron' THEN 'squadron'::public.award_level
    WHEN 'tenant_unit' THEN 'squadron'::public.award_level
    WHEN 'group' THEN 'group'::public.award_level
    WHEN 'wing' THEN 'wing'::public.award_level
    WHEN 'haf' THEN 'haf'::public.award_level
    WHEN '12_oay' THEN 'haf'::public.award_level
    ELSE 'squadron'::public.award_level
  END;
  
  -- Create awards for team members or single recipient
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
        v_shell.award_category::public.award_category,
        TRUE,
        v_shell.cycle_year
      ) RETURNING id INTO v_award_id;
    END LOOP;
  ELSE
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
      v_shell.award_category::public.award_category,
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
$$;

-- ============================================================================
-- FIX remove_award_shell_win_level
-- ============================================================================

CREATE OR REPLACE FUNCTION public.remove_award_shell_win_level(
  p_shell_id UUID,
  p_win_level public.award_win_level
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_shell public.award_shells;
  v_remaining_wins INTEGER;
  v_highest_level public.award_win_level;
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
$$;
