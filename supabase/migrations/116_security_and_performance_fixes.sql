-- Migration 116: Comprehensive Security and Performance Fixes
-- Addresses issues identified by Supabase Database Linter
-- 
-- SECURITY FIXES:
-- 1. Convert SECURITY DEFINER view to SECURITY INVOKER
-- 2. Fix functions with mutable search_path
-- 3. Fix analytics_events RLS policy (WITH CHECK true)
--
-- PERFORMANCE FIXES:
-- 1. Fix RLS policies to use (select auth.uid()) instead of auth.uid()
-- 2. Add missing indexes for foreign keys
--
-- References:
-- - https://supabase.com/docs/guides/database/database-linter?lint=0010_security_definer_view
-- - https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable
-- - https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select

-- ============================================================================
-- PART 1: FIX SECURITY DEFINER VIEW
-- ============================================================================

-- Drop and recreate duty_description_template_labels view with security_invoker
DROP VIEW IF EXISTS duty_description_template_labels;

CREATE VIEW duty_description_template_labels 
WITH (security_invoker = true) AS
SELECT DISTINCT
  office_label,
  role_label,
  rank_label
FROM duty_description_templates
WHERE 
  office_label IS NOT NULL OR 
  role_label IS NOT NULL OR 
  rank_label IS NOT NULL;

-- Grant access to the view
GRANT SELECT ON duty_description_template_labels TO authenticated;

-- ============================================================================
-- PART 2: FIX FUNCTIONS WITH MUTABLE SEARCH_PATH
-- ============================================================================

-- Fix update_decoration_shell_updated_at
CREATE OR REPLACE FUNCTION public.update_decoration_shell_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Fix update_user_award_categories_updated_at
CREATE OR REPLACE FUNCTION public.update_user_award_categories_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- NOTE: add_award_shell_win_level and remove_award_shell_win_level are complex functions
-- defined in migration 111 with award_win_level type. They already have SECURITY DEFINER
-- but use SET search_path = public which is acceptable. Skipping to avoid signature conflicts.

-- Fix update_award_shell_updated_at
CREATE OR REPLACE FUNCTION public.update_award_shell_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Fix enforce_max_style_examples
CREATE OR REPLACE FUNCTION public.enforce_max_style_examples()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_count INTEGER;
  v_max INTEGER := 10;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM public.user_style_examples
  WHERE user_id = NEW.user_id;
  
  IF v_count >= v_max THEN
    RAISE EXCEPTION 'Maximum of % style examples allowed per user', v_max;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Fix create_award_shell_sections
CREATE OR REPLACE FUNCTION public.create_award_shell_sections()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  -- Insert one section per 1206 category for the new shell (slot_index 0)
  INSERT INTO public.award_shell_sections (shell_id, category, slot_index, last_edited_by)
  VALUES 
    (NEW.id, 'leadership_job_performance', 0, NEW.created_by),
    (NEW.id, 'significant_self_improvement', 0, NEW.created_by),
    (NEW.id, 'base_community_involvement', 0, NEW.created_by);
  RETURN NEW;
END;
$$;

-- Fix calculate_award_period_dates
-- Note: This function has a different signature in migration 072 (4 params)
-- Adding search_path fix with correct signature
CREATE OR REPLACE FUNCTION public.calculate_award_period_dates(
  p_period_type TEXT,
  p_year INTEGER,
  p_quarter INTEGER,
  p_is_fiscal BOOLEAN
)
RETURNS TABLE (start_date DATE, end_date DATE)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
  IF p_period_type = 'annual' THEN
    IF p_is_fiscal THEN
      -- Fiscal year: Oct 1 of previous year to Sep 30 of given year
      RETURN QUERY SELECT 
        make_date(p_year - 1, 10, 1)::DATE,
        make_date(p_year, 9, 30)::DATE;
    ELSE
      -- Calendar year: Jan 1 to Dec 31
      RETURN QUERY SELECT 
        make_date(p_year, 1, 1)::DATE,
        make_date(p_year, 12, 31)::DATE;
    END IF;
  ELSIF p_period_type = 'quarterly' THEN
    IF p_is_fiscal THEN
      -- Fiscal quarters: Q1=Oct-Dec, Q2=Jan-Mar, Q3=Apr-Jun, Q4=Jul-Sep
      CASE p_quarter
        WHEN 1 THEN
          RETURN QUERY SELECT 
            make_date(p_year - 1, 10, 1)::DATE,
            make_date(p_year - 1, 12, 31)::DATE;
        WHEN 2 THEN
          RETURN QUERY SELECT 
            make_date(p_year, 1, 1)::DATE,
            make_date(p_year, 3, 31)::DATE;
        WHEN 3 THEN
          RETURN QUERY SELECT 
            make_date(p_year, 4, 1)::DATE,
            make_date(p_year, 6, 30)::DATE;
        WHEN 4 THEN
          RETURN QUERY SELECT 
            make_date(p_year, 7, 1)::DATE,
            make_date(p_year, 9, 30)::DATE;
      END CASE;
    ELSE
      -- Calendar quarters: Q1=Jan-Mar, Q2=Apr-Jun, Q3=Jul-Sep, Q4=Oct-Dec
      CASE p_quarter
        WHEN 1 THEN
          RETURN QUERY SELECT 
            make_date(p_year, 1, 1)::DATE,
            make_date(p_year, 3, 31)::DATE;
        WHEN 2 THEN
          RETURN QUERY SELECT 
            make_date(p_year, 4, 1)::DATE,
            make_date(p_year, 6, 30)::DATE;
        WHEN 3 THEN
          RETURN QUERY SELECT 
            make_date(p_year, 7, 1)::DATE,
            make_date(p_year, 9, 30)::DATE;
        WHEN 4 THEN
          RETURN QUERY SELECT 
            make_date(p_year, 10, 1)::DATE,
            make_date(p_year, 12, 31)::DATE;
      END CASE;
    END IF;
  END IF;
  -- For 'special', dates are provided directly, no calculation needed
  RETURN;
END;
$$;

-- Fix ensure_style_profile_exists
CREATE OR REPLACE FUNCTION public.ensure_style_profile_exists()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.user_style_profiles (user_id)
  VALUES (NEW.user_id)
  ON CONFLICT (user_id) DO NOTHING;
  
  RETURN NEW;
END;
$$;

-- Fix update_supervisor_feedbacks_updated_at
CREATE OR REPLACE FUNCTION public.update_supervisor_feedbacks_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Fix update_supervisor_expectations_updated_at
CREATE OR REPLACE FUNCTION public.update_supervisor_expectations_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Fix update_projects_updated_at (if it exists)
CREATE OR REPLACE FUNCTION public.update_projects_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Fix archive_epb_shell
CREATE OR REPLACE FUNCTION public.archive_epb_shell(
  p_shell_id UUID,
  p_archive_name TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.epb_shells
  SET 
    status = 'archived',
    archived_at = now(),
    archive_name = COALESCE(p_archive_name, 'Archive ' || to_char(now(), 'YYYY-MM-DD'))
  WHERE id = p_shell_id
    AND (user_id = auth.uid() OR created_by = auth.uid());
  
  RETURN FOUND;
END;
$$;

-- Fix get_award_shell_with_sections
-- Note: Must drop first because return type changed in migration 072
DROP FUNCTION IF EXISTS public.get_award_shell_with_sections(UUID);

CREATE OR REPLACE FUNCTION public.get_award_shell_with_sections(p_shell_id UUID)
RETURNS TABLE (
  shell_id UUID,
  user_id UUID,
  team_member_id UUID,
  cycle_year INTEGER,
  award_level TEXT,
  award_category TEXT,
  sentences_per_statement INTEGER,
  created_by UUID,
  shell_created_at TIMESTAMPTZ,
  shell_updated_at TIMESTAMPTZ,
  section_id UUID,
  category TEXT,
  slot_index INTEGER,
  statement_text TEXT,
  source_type TEXT,
  custom_context TEXT,
  selected_action_ids JSONB,
  section_updated_at TIMESTAMPTZ,
  award_period_type TEXT,
  quarter INTEGER,
  is_fiscal_year BOOLEAN,
  period_start_date DATE,
  period_end_date DATE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    aws.id AS shell_id,
    aws.user_id,
    aws.team_member_id,
    aws.cycle_year,
    aws.award_level,
    aws.award_category,
    aws.sentences_per_statement,
    aws.created_by,
    aws.created_at AS shell_created_at,
    aws.updated_at AS shell_updated_at,
    ass.id AS section_id,
    ass.category,
    ass.slot_index,
    ass.statement_text,
    ass.source_type,
    ass.custom_context,
    ass.selected_action_ids,
    ass.updated_at AS section_updated_at,
    aws.award_period_type,
    aws.quarter,
    aws.is_fiscal_year,
    aws.period_start_date,
    aws.period_end_date
  FROM public.award_shells aws
  LEFT JOIN public.award_shell_sections ass ON ass.shell_id = aws.id
  WHERE aws.id = p_shell_id
  ORDER BY 
    CASE ass.category
      WHEN 'leadership_job_performance' THEN 1
      WHEN 'significant_self_improvement' THEN 2
      WHEN 'base_community_involvement' THEN 3
      ELSE 4
    END,
    ass.slot_index;
END;
$$;

-- Fix unarchive_epb_shell
CREATE OR REPLACE FUNCTION public.unarchive_epb_shell(
  p_shell_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.epb_shells
  SET 
    status = 'active',
    archived_at = NULL,
    archive_name = NULL
  WHERE id = p_shell_id
    AND (user_id = auth.uid() OR created_by = auth.uid());
  
  RETURN FOUND;
END;
$$;

-- Fix process_style_feedback - uses different signature (UUID, INTEGER)
CREATE OR REPLACE FUNCTION public.process_style_feedback(p_user_id UUID, p_batch_size INTEGER DEFAULT 50)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  events_processed INTEGER := 0;
  event_record RECORD;
  v_version INTEGER;
  v_aggressiveness INTEGER;
  v_fill_to_max BOOLEAN;
BEGIN
  -- Process unprocessed events for this user
  FOR event_record IN
    SELECT id, event_type, payload
    FROM public.style_feedback_events
    WHERE user_id = p_user_id AND processed = false
    ORDER BY created_at ASC
    LIMIT p_batch_size
  LOOP
    -- Handle each event type
    CASE event_record.event_type
      WHEN 'revision_selected', 'revision_copied' THEN
        v_version := (event_record.payload->>'version')::INTEGER;
        -- Update user preferences based on selected version
        UPDATE public.user_style_profiles
        SET 
          preferred_version = v_version,
          updated_at = now()
        WHERE user_id = p_user_id;
      
      WHEN 'aggressiveness_changed' THEN
        v_aggressiveness := (event_record.payload->>'aggressiveness')::INTEGER;
        UPDATE public.user_style_profiles
        SET 
          aggressiveness = v_aggressiveness,
          updated_at = now()
        WHERE user_id = p_user_id;
      
      WHEN 'fill_to_max_changed' THEN
        v_fill_to_max := (event_record.payload->>'fill_to_max')::BOOLEAN;
        UPDATE public.user_style_profiles
        SET 
          fill_to_max = v_fill_to_max,
          updated_at = now()
        WHERE user_id = p_user_id;
      
      ELSE
        -- Unknown event type, skip
        NULL;
    END CASE;
    
    -- Mark event as processed
    UPDATE public.style_feedback_events
    SET processed = true
    WHERE id = event_record.id;
    
    events_processed := events_processed + 1;
  END LOOP;
  
  RETURN events_processed;
END;
$$;

-- Fix cleanup_old_feedback_events - signature is (INTEGER)
CREATE OR REPLACE FUNCTION public.cleanup_old_feedback_events(p_days_old INTEGER DEFAULT 7)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM public.style_feedback_events
  WHERE processed = true 
    AND created_at < now() - (p_days_old || ' days')::INTERVAL;
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

-- Fix is_in_accomplishment_chain (correct signature: acc_id UUID, viewer_id UUID)
CREATE OR REPLACE FUNCTION public.is_in_accomplishment_chain(acc_id UUID, viewer_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  acc_user_id UUID;
  acc_team_member_id UUID;
  acc_supervisor_id UUID;
BEGIN
  -- Get the accomplishment details
  SELECT user_id, team_member_id INTO acc_user_id, acc_team_member_id
  FROM public.accomplishments WHERE id = acc_id;
  
  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;
  
  -- Case 1: For managed member accomplishments
  IF acc_team_member_id IS NOT NULL THEN
    -- Get the supervisor_id from team_members
    SELECT supervisor_id INTO acc_supervisor_id
    FROM public.team_members WHERE id = acc_team_member_id;
    
    -- Check if viewer is the direct supervisor
    IF acc_supervisor_id = viewer_id THEN
      RETURN TRUE;
    END IF;
    
    -- Check if viewer is in the supervisor chain of the managed member's supervisor
    IF EXISTS (
      SELECT 1 FROM public.get_supervisor_chain(acc_supervisor_id) 
      WHERE supervisor_id = viewer_id
    ) THEN
      RETURN TRUE;
    END IF;
    
    RETURN FALSE;
  END IF;
  
  -- Case 2: For regular profile accomplishments
  -- Check if viewer is in the supervisor chain of the accomplishment owner
  IF EXISTS (
    SELECT 1 FROM public.get_supervisor_chain(acc_user_id) 
    WHERE supervisor_id = viewer_id
  ) THEN
    RETURN TRUE;
  END IF;
  
  RETURN FALSE;
END;
$$;

-- Fix get_accomplishment_comment_counts (correct signature and return type)
CREATE OR REPLACE FUNCTION public.get_accomplishment_comment_counts(acc_ids UUID[])
RETURNS TABLE (
  accomplishment_id UUID,
  total_count BIGINT,
  unresolved_count BIGINT
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.accomplishment_id,
    COUNT(*) AS total_count,
    COUNT(*) FILTER (WHERE NOT c.is_resolved) AS unresolved_count
  FROM public.accomplishment_comments c
  WHERE c.accomplishment_id = ANY(acc_ids)
    -- Only count comments visible to the current user
    AND (
      -- Public comments: no visible_to set
      c.visible_to IS NULL OR array_length(c.visible_to, 1) IS NULL
      OR
      -- Private comments: user is author or in visible_to array
      c.author_id = auth.uid()
      OR
      auth.uid() = ANY(c.visible_to)
    )
  GROUP BY c.accomplishment_id;
END;
$$;

-- Fix add_project_creator_as_owner (correct column names)
CREATE OR REPLACE FUNCTION public.add_project_creator_as_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.project_members (project_id, profile_id, is_owner, added_by)
  VALUES (NEW.id, NEW.created_by, true, NEW.created_by);
  RETURN NEW;
END;
$$;

-- Fix update_opb_shell_updated_at
CREATE OR REPLACE FUNCTION public.update_opb_shell_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Fix create_opb_shell_sections
CREATE OR REPLACE FUNCTION public.create_opb_shell_sections()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  -- Insert all standard MPA sections for the new OPB shell
  INSERT INTO public.opb_shell_sections (shell_id, mpa, last_edited_by)
  VALUES 
    (NEW.id, 'executing_mission', NEW.created_by),
    (NEW.id, 'leading_people', NEW.created_by),
    (NEW.id, 'managing_resources', NEW.created_by),
    (NEW.id, 'improving_unit', NEW.created_by),
    (NEW.id, 'hlr_assessment', NEW.created_by);
  RETURN NEW;
END;
$$;

-- Fix bulk_share_epb_statements (correct signature: p_shell_id UUID)
CREATE OR REPLACE FUNCTION public.bulk_share_epb_statements(
  p_shell_id UUID,
  p_share_type TEXT,
  p_shared_with_id UUID DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count INTEGER := 0;
  v_statement RECORD;
BEGIN
  -- Validate share_type
  IF p_share_type NOT IN ('user', 'team', 'community') THEN
    RAISE EXCEPTION 'Invalid share_type: %', p_share_type;
  END IF;

  -- For 'user' shares, shared_with_id is required
  IF p_share_type = 'user' AND p_shared_with_id IS NULL THEN
    RAISE EXCEPTION 'shared_with_id is required for user shares';
  END IF;

  -- Share each statement from this EPB
  FOR v_statement IN 
    SELECT rs.id, rs.user_id
    FROM public.refined_statements rs
    WHERE rs.source_epb_shell_id = p_shell_id
    AND rs.user_id = auth.uid()
  LOOP
    -- Insert share if it doesn't already exist
    INSERT INTO public.statement_shares (statement_id, owner_id, share_type, shared_with_id)
    VALUES (v_statement.id, v_statement.user_id, p_share_type, p_shared_with_id)
    ON CONFLICT (statement_id, share_type, shared_with_id) DO NOTHING;
    
    IF FOUND THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

-- Fix get_accomplishment_chain_members (correct signature: acc_id UUID)
CREATE OR REPLACE FUNCTION public.get_accomplishment_chain_members(acc_id UUID)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  rank TEXT,
  is_owner BOOLEAN
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  acc_user_id UUID;
  acc_team_member_id UUID;
  owner_supervisor_id UUID;
BEGIN
  -- Get the accomplishment details
  SELECT a.user_id, a.team_member_id INTO acc_user_id, acc_team_member_id
  FROM public.accomplishments a WHERE a.id = acc_id;
  
  IF NOT FOUND THEN
    RETURN;
  END IF;
  
  -- Case 1: Managed member accomplishment
  IF acc_team_member_id IS NOT NULL THEN
    -- Get managed member's supervisor
    SELECT tm.supervisor_id INTO owner_supervisor_id
    FROM public.team_members tm WHERE tm.id = acc_team_member_id;
    
    -- Return all supervisors in the chain
    RETURN QUERY
    SELECT 
      sc.supervisor_id AS user_id,
      p.full_name,
      p.rank::TEXT,
      FALSE AS is_owner
    FROM public.get_supervisor_chain(owner_supervisor_id) sc
    JOIN public.profiles p ON p.id = sc.supervisor_id
    WHERE sc.supervisor_id != auth.uid(); -- Exclude current user
    
    RETURN;
  END IF;
  
  -- Case 2: Regular profile accomplishment
  -- Return the accomplishment owner first
  RETURN QUERY
  SELECT 
    p.id AS user_id,
    p.full_name,
    p.rank::TEXT,
    TRUE AS is_owner
  FROM public.profiles p
  WHERE p.id = acc_user_id
    AND p.id != auth.uid(); -- Exclude current user
  
  -- Then return all supervisors in the chain
  RETURN QUERY
  SELECT 
    sc.supervisor_id AS user_id,
    p.full_name,
    p.rank::TEXT,
    FALSE AS is_owner
  FROM public.get_supervisor_chain(acc_user_id) sc
  JOIN public.profiles p ON p.id = sc.supervisor_id
  WHERE sc.supervisor_id != auth.uid(); -- Exclude current user
  
END;
$$;

-- ============================================================================
-- PART 3: FIX ANALYTICS_EVENTS RLS POLICY
-- ============================================================================

-- Replace the overly permissive INSERT policy
DROP POLICY IF EXISTS "Users can insert own events" ON analytics_events;

CREATE POLICY "Users can insert own events"
  ON analytics_events FOR INSERT
  WITH CHECK (
    -- Allow authenticated users to insert events for themselves
    user_id IS NULL OR user_id = (select auth.uid())
  );

-- Fix the admin read policy to use (select auth.uid())
DROP POLICY IF EXISTS "Admins can read analytics" ON analytics_events;

CREATE POLICY "Admins can read analytics"
  ON analytics_events FOR SELECT
  USING (
    (select auth.uid()) IN (
      SELECT id FROM profiles WHERE role = 'admin'
    )
  );

-- ============================================================================
-- PART 4: FIX RLS POLICIES TO USE (select auth.uid())
-- Performance optimization: prevents re-evaluation for every row
-- ============================================================================

-- OPB SHELLS POLICIES
DROP POLICY IF EXISTS "Officers can view own opb shells" ON opb_shells;
CREATE POLICY "Officers can view own opb shells"
  ON opb_shells FOR SELECT
  USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can view shared opb shells" ON opb_shells;
CREATE POLICY "Users can view shared opb shells"
  ON opb_shells FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM opb_shell_shares oss
      WHERE oss.shell_id = opb_shells.id
      AND oss.shared_with_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Officers can create own opb shells" ON opb_shells;
CREATE POLICY "Officers can create own opb shells"
  ON opb_shells FOR INSERT
  WITH CHECK (
    user_id = (select auth.uid()) AND 
    created_by = (select auth.uid())
  );

DROP POLICY IF EXISTS "Officers can update own opb shells" ON opb_shells;
CREATE POLICY "Officers can update own opb shells"
  ON opb_shells FOR UPDATE
  USING (user_id = (select auth.uid()))
  WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Officers can delete own opb shells" ON opb_shells;
CREATE POLICY "Officers can delete own opb shells"
  ON opb_shells FOR DELETE
  USING (user_id = (select auth.uid()));

-- OPB SHELL SECTIONS POLICIES
DROP POLICY IF EXISTS "Officers can insert opb sections for own shells" ON opb_shell_sections;
CREATE POLICY "Officers can insert opb sections for own shells"
  ON opb_shell_sections FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_shell_sections.shell_id
      AND os.user_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Officers can update opb sections of accessible shells" ON opb_shell_sections;
CREATE POLICY "Officers can update opb sections of accessible shells"
  ON opb_shell_sections FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_shell_sections.shell_id
      AND (
        os.user_id = (select auth.uid())
        OR EXISTS (
          SELECT 1 FROM opb_shell_shares oss
          WHERE oss.shell_id = os.id
          AND oss.shared_with_id = (select auth.uid())
        )
      )
    )
  );

DROP POLICY IF EXISTS "Officers can delete opb sections of own shells" ON opb_shell_sections;
CREATE POLICY "Officers can delete opb sections of own shells"
  ON opb_shell_sections FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_shell_sections.shell_id
      AND os.user_id = (select auth.uid())
    )
  );

-- OPB SHELL SNAPSHOTS POLICIES
DROP POLICY IF EXISTS "Users can insert opb snapshots for accessible sections" ON opb_shell_snapshots;
CREATE POLICY "Users can insert opb snapshots for accessible sections"
  ON opb_shell_snapshots FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM opb_shell_sections oss
      JOIN opb_shells os ON os.id = oss.shell_id
      WHERE oss.id = opb_shell_snapshots.section_id
      AND (
        os.user_id = (select auth.uid())
        OR EXISTS (
          SELECT 1 FROM opb_shell_shares oshr
          WHERE oshr.shell_id = os.id
          AND oshr.shared_with_id = (select auth.uid())
        )
      )
    )
  );

DROP POLICY IF EXISTS "Users can delete opb snapshots they created" ON opb_shell_snapshots;
CREATE POLICY "Users can delete opb snapshots they created"
  ON opb_shell_snapshots FOR DELETE
  USING (created_by = (select auth.uid()));

-- OPB SHELL SHARES POLICIES
DROP POLICY IF EXISTS "Users can view own opb shell shares" ON opb_shell_shares;
CREATE POLICY "Users can view own opb shell shares"
  ON opb_shell_shares FOR SELECT
  USING (owner_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can view opb shells shared with them" ON opb_shell_shares;
CREATE POLICY "Users can view opb shells shared with them"
  ON opb_shell_shares FOR SELECT
  USING (shared_with_id = (select auth.uid()));

DROP POLICY IF EXISTS "Officers can create opb shell shares" ON opb_shell_shares;
CREATE POLICY "Officers can create opb shell shares"
  ON opb_shell_shares FOR INSERT
  WITH CHECK (
    owner_id = (select auth.uid()) AND
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_shell_shares.shell_id
      AND os.user_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Officers can delete own opb shell shares" ON opb_shell_shares;
CREATE POLICY "Officers can delete own opb shell shares"
  ON opb_shell_shares FOR DELETE
  USING (owner_id = (select auth.uid()));

-- OPB DUTY DESCRIPTION SNAPSHOTS POLICIES
DROP POLICY IF EXISTS "Users can insert opb duty description snapshots" ON opb_duty_description_snapshots;
CREATE POLICY "Users can insert opb duty description snapshots"
  ON opb_duty_description_snapshots FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM opb_shells os
      WHERE os.id = opb_duty_description_snapshots.shell_id
      AND (
        os.user_id = (select auth.uid())
        OR EXISTS (
          SELECT 1 FROM opb_shell_shares oss
          WHERE oss.shell_id = os.id
          AND oss.shared_with_id = (select auth.uid())
        )
      )
    )
  );

DROP POLICY IF EXISTS "Users can delete opb duty description snapshots they created" ON opb_duty_description_snapshots;
CREATE POLICY "Users can delete opb duty description snapshots they created"
  ON opb_duty_description_snapshots FOR DELETE
  USING (created_by = (select auth.uid()));

-- SUPERVISOR FEEDBACKS POLICIES
DROP POLICY IF EXISTS "Supervisors can read their own feedbacks" ON supervisor_feedbacks;
CREATE POLICY "Supervisors can read their own feedbacks"
  ON supervisor_feedbacks FOR SELECT
  USING (supervisor_id = (select auth.uid()));

DROP POLICY IF EXISTS "Subordinates can read shared feedbacks" ON supervisor_feedbacks;
CREATE POLICY "Subordinates can read shared feedbacks"
  ON supervisor_feedbacks FOR SELECT
  USING (
    subordinate_id = (select auth.uid()) AND 
    status = 'shared'
  );

DROP POLICY IF EXISTS "Linked users can read shared feedbacks for their managed account" ON supervisor_feedbacks;
CREATE POLICY "Linked users can read shared feedbacks for their managed account"
  ON supervisor_feedbacks FOR SELECT
  USING (
    team_member_id IS NOT NULL AND
    status = 'shared' AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = supervisor_feedbacks.team_member_id
        AND tm.linked_user_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Supervisors can create feedbacks for subordinates" ON supervisor_feedbacks;
CREATE POLICY "Supervisors can create feedbacks for subordinates"
  ON supervisor_feedbacks FOR INSERT
  WITH CHECK (
    supervisor_id = (select auth.uid()) AND
    (
      (subordinate_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM teams t
        WHERE t.supervisor_id = (select auth.uid())
          AND t.subordinate_id = supervisor_feedbacks.subordinate_id
      ))
      OR
      (team_member_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM team_members tm
        WHERE tm.id = supervisor_feedbacks.team_member_id
          AND tm.supervisor_id = (select auth.uid())
      ))
    )
  );

DROP POLICY IF EXISTS "Supervisors can update their own feedbacks" ON supervisor_feedbacks;
CREATE POLICY "Supervisors can update their own feedbacks"
  ON supervisor_feedbacks FOR UPDATE
  USING (supervisor_id = (select auth.uid()))
  WITH CHECK (supervisor_id = (select auth.uid()));

DROP POLICY IF EXISTS "Supervisors can delete their own draft feedbacks" ON supervisor_feedbacks;
CREATE POLICY "Supervisors can delete their own draft feedbacks"
  ON supervisor_feedbacks FOR DELETE
  USING (supervisor_id = (select auth.uid()) AND status = 'draft');

-- SUPERVISOR EXPECTATIONS POLICIES
DROP POLICY IF EXISTS "Supervisors can read their own expectations" ON supervisor_expectations;
CREATE POLICY "Supervisors can read their own expectations"
  ON supervisor_expectations FOR SELECT
  USING (supervisor_id = (select auth.uid()));

DROP POLICY IF EXISTS "Subordinates can read expectations set for them" ON supervisor_expectations;
CREATE POLICY "Subordinates can read expectations set for them"
  ON supervisor_expectations FOR SELECT
  USING (subordinate_id = (select auth.uid()));

DROP POLICY IF EXISTS "Linked users can read expectations for their managed account" ON supervisor_expectations;
CREATE POLICY "Linked users can read expectations for their managed account"
  ON supervisor_expectations FOR SELECT
  USING (
    team_member_id IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = supervisor_expectations.team_member_id
        AND tm.linked_user_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Supervisors can create expectations for subordinates" ON supervisor_expectations;
CREATE POLICY "Supervisors can create expectations for subordinates"
  ON supervisor_expectations FOR INSERT
  WITH CHECK (
    supervisor_id = (select auth.uid()) AND
    (
      (subordinate_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM teams t
        WHERE t.supervisor_id = (select auth.uid())
          AND t.subordinate_id = supervisor_expectations.subordinate_id
      ))
      OR
      (team_member_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM team_members tm
        WHERE tm.id = supervisor_expectations.team_member_id
          AND tm.supervisor_id = (select auth.uid())
      ))
    )
  );

DROP POLICY IF EXISTS "Supervisors can update their own expectations" ON supervisor_expectations;
CREATE POLICY "Supervisors can update their own expectations"
  ON supervisor_expectations FOR UPDATE
  USING (supervisor_id = (select auth.uid()))
  WITH CHECK (supervisor_id = (select auth.uid()));

DROP POLICY IF EXISTS "Supervisors can delete their own expectations" ON supervisor_expectations;
CREATE POLICY "Supervisors can delete their own expectations"
  ON supervisor_expectations FOR DELETE
  USING (supervisor_id = (select auth.uid()));

-- DUTY DESCRIPTION TEMPLATES POLICIES
DROP POLICY IF EXISTS "Users can view their own duty description templates" ON duty_description_templates;
CREATE POLICY "Users can view their own duty description templates"
  ON duty_description_templates FOR SELECT
  USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert their own duty description templates" ON duty_description_templates;
CREATE POLICY "Users can insert their own duty description templates"
  ON duty_description_templates FOR INSERT
  WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own duty description templates" ON duty_description_templates;
CREATE POLICY "Users can update their own duty description templates"
  ON duty_description_templates FOR UPDATE
  USING (user_id = (select auth.uid()))
  WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own duty description templates" ON duty_description_templates;
CREATE POLICY "Users can delete their own duty description templates"
  ON duty_description_templates FOR DELETE
  USING (user_id = (select auth.uid()));

-- USER AWARD CATEGORIES POLICIES
DROP POLICY IF EXISTS "Users can view own award categories" ON user_award_categories;
CREATE POLICY "Users can view own award categories"
  ON user_award_categories FOR SELECT
  TO authenticated
  USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert own award categories" ON user_award_categories;
CREATE POLICY "Users can insert own award categories"
  ON user_award_categories FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update own award categories" ON user_award_categories;
CREATE POLICY "Users can update own award categories"
  ON user_award_categories FOR UPDATE
  TO authenticated
  USING (user_id = (select auth.uid()))
  WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete own award categories" ON user_award_categories;
CREATE POLICY "Users can delete own award categories"
  ON user_award_categories FOR DELETE
  TO authenticated
  USING (user_id = (select auth.uid()));

-- DECORATION SHELLS POLICIES
DROP POLICY IF EXISTS "Users can view own decoration shells" ON decoration_shells;
CREATE POLICY "Users can view own decoration shells"
  ON decoration_shells FOR SELECT
  USING (user_id = (select auth.uid()) AND team_member_id IS NULL);

DROP POLICY IF EXISTS "Users can view decoration shells they created" ON decoration_shells;
CREATE POLICY "Users can view decoration shells they created"
  ON decoration_shells FOR SELECT
  USING (created_by = (select auth.uid()));

DROP POLICY IF EXISTS "Supervisors can view subordinate decoration shells via history" ON decoration_shells;
CREATE POLICY "Supervisors can view subordinate decoration shells via history"
  ON decoration_shells FOR SELECT
  USING (
    team_member_id IS NULL AND
    EXISTS (
      SELECT 1 FROM team_history th
      WHERE th.subordinate_id = decoration_shells.user_id
      AND th.supervisor_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Supervisors can view managed member decoration shells" ON decoration_shells;
CREATE POLICY "Supervisors can view managed member decoration shells"
  ON decoration_shells FOR SELECT
  USING (
    team_member_id IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = decoration_shells.team_member_id
      AND tm.supervisor_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can view shared decoration shells" ON decoration_shells;
CREATE POLICY "Users can view shared decoration shells"
  ON decoration_shells FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM decoration_shell_shares dss
      WHERE dss.shell_id = decoration_shells.id
      AND dss.shared_with_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can create own decoration shells" ON decoration_shells;
CREATE POLICY "Users can create own decoration shells"
  ON decoration_shells FOR INSERT
  WITH CHECK (
    user_id = (select auth.uid()) AND 
    created_by = (select auth.uid()) AND
    team_member_id IS NULL
  );

DROP POLICY IF EXISTS "Supervisors can create subordinate decoration shells" ON decoration_shells;
CREATE POLICY "Supervisors can create subordinate decoration shells"
  ON decoration_shells FOR INSERT
  WITH CHECK (
    created_by = (select auth.uid()) AND
    team_member_id IS NULL AND
    EXISTS (
      SELECT 1 FROM teams t
      WHERE t.subordinate_id = decoration_shells.user_id
      AND t.supervisor_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Supervisors can create managed member decoration shells" ON decoration_shells;
CREATE POLICY "Supervisors can create managed member decoration shells"
  ON decoration_shells FOR INSERT
  WITH CHECK (
    created_by = (select auth.uid()) AND
    team_member_id IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = decoration_shells.team_member_id
      AND tm.supervisor_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can update own decoration shells" ON decoration_shells;
CREATE POLICY "Users can update own decoration shells"
  ON decoration_shells FOR UPDATE
  USING (user_id = (select auth.uid()) AND team_member_id IS NULL)
  WITH CHECK (user_id = (select auth.uid()) AND team_member_id IS NULL);

DROP POLICY IF EXISTS "Supervisors can update subordinate decoration shells via history" ON decoration_shells;
CREATE POLICY "Supervisors can update subordinate decoration shells via history"
  ON decoration_shells FOR UPDATE
  USING (
    team_member_id IS NULL AND
    EXISTS (
      SELECT 1 FROM team_history th
      WHERE th.subordinate_id = decoration_shells.user_id
      AND th.supervisor_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Supervisors can update managed member decoration shells" ON decoration_shells;
CREATE POLICY "Supervisors can update managed member decoration shells"
  ON decoration_shells FOR UPDATE
  USING (
    team_member_id IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = decoration_shells.team_member_id
      AND tm.supervisor_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Users can delete own decoration shells" ON decoration_shells;
CREATE POLICY "Users can delete own decoration shells"
  ON decoration_shells FOR DELETE
  USING (user_id = (select auth.uid()) AND team_member_id IS NULL);

DROP POLICY IF EXISTS "Supervisors can delete subordinate decoration shells" ON decoration_shells;
CREATE POLICY "Supervisors can delete subordinate decoration shells"
  ON decoration_shells FOR DELETE
  USING (
    team_member_id IS NULL AND
    EXISTS (
      SELECT 1 FROM team_history th
      WHERE th.subordinate_id = decoration_shells.user_id
      AND th.supervisor_id = (select auth.uid())
    )
  );

DROP POLICY IF EXISTS "Supervisors can delete managed member decoration shells" ON decoration_shells;
CREATE POLICY "Supervisors can delete managed member decoration shells"
  ON decoration_shells FOR DELETE
  USING (
    team_member_id IS NOT NULL AND
    EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = decoration_shells.team_member_id
      AND tm.supervisor_id = (select auth.uid())
    )
  );

-- DECORATION SHELL SHARES POLICIES
DROP POLICY IF EXISTS "Users can view own decoration shell shares" ON decoration_shell_shares;
CREATE POLICY "Users can view own decoration shell shares"
  ON decoration_shell_shares FOR SELECT
  USING (owner_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can view decoration shells shared with them" ON decoration_shell_shares;
CREATE POLICY "Users can view decoration shells shared with them"
  ON decoration_shell_shares FOR SELECT
  USING (shared_with_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can create decoration shell shares" ON decoration_shell_shares;
CREATE POLICY "Users can create decoration shell shares"
  ON decoration_shell_shares FOR INSERT
  WITH CHECK (
    owner_id = (select auth.uid()) AND
    EXISTS (
      SELECT 1 FROM decoration_shells ds
      WHERE ds.id = decoration_shell_shares.shell_id
      AND (
        (ds.user_id = (select auth.uid()) AND ds.team_member_id IS NULL)
        OR
        (ds.team_member_id IS NULL AND EXISTS (
          SELECT 1 FROM team_history th
          WHERE th.subordinate_id = ds.user_id
          AND th.supervisor_id = (select auth.uid())
        ))
        OR
        (ds.team_member_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM team_members tm
          WHERE tm.id = ds.team_member_id
          AND tm.supervisor_id = (select auth.uid())
        ))
      )
    )
  );

DROP POLICY IF EXISTS "Users can delete own decoration shell shares" ON decoration_shell_shares;
CREATE POLICY "Users can delete own decoration shell shares"
  ON decoration_shell_shares FOR DELETE
  USING (owner_id = (select auth.uid()));

-- DECORATION SHELL SNAPSHOTS POLICIES
DROP POLICY IF EXISTS "Users can insert snapshots for accessible decoration shells" ON decoration_shell_snapshots;
CREATE POLICY "Users can insert snapshots for accessible decoration shells"
  ON decoration_shell_snapshots FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM decoration_shells ds
      WHERE ds.id = decoration_shell_snapshots.shell_id
      AND (
        (ds.user_id = (select auth.uid()) AND ds.team_member_id IS NULL)
        OR
        (ds.team_member_id IS NULL AND EXISTS (
          SELECT 1 FROM team_history th
          WHERE th.subordinate_id = ds.user_id
          AND th.supervisor_id = (select auth.uid())
        ))
        OR
        (ds.team_member_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM team_members tm
          WHERE tm.id = ds.team_member_id
          AND tm.supervisor_id = (select auth.uid())
        ))
      )
    )
  );

DROP POLICY IF EXISTS "Users can delete decoration snapshots they created" ON decoration_shell_snapshots;
CREATE POLICY "Users can delete decoration snapshots they created"
  ON decoration_shell_snapshots FOR DELETE
  USING (created_by = (select auth.uid()));

-- AWARD SHELL TEAM MEMBERS POLICIES
DROP POLICY IF EXISTS "Users can add team members to accessible award shells" ON award_shell_team_members;
CREATE POLICY "Users can add team members to accessible award shells"
  ON award_shell_team_members FOR INSERT
  WITH CHECK (
    added_by = (select auth.uid()) AND
    EXISTS (
      SELECT 1 FROM award_shells aws
      WHERE aws.id = award_shell_team_members.shell_id
      AND (
        (aws.user_id = (select auth.uid()) AND aws.team_member_id IS NULL)
        OR aws.created_by = (select auth.uid())
        OR EXISTS (
          SELECT 1 FROM team_history th
          WHERE th.subordinate_id = aws.user_id
          AND th.supervisor_id = (select auth.uid())
        )
      )
    )
  );

DROP POLICY IF EXISTS "Users can remove team members from accessible award shells" ON award_shell_team_members;
CREATE POLICY "Users can remove team members from accessible award shells"
  ON award_shell_team_members FOR DELETE
  USING (
    added_by = (select auth.uid()) OR
    EXISTS (
      SELECT 1 FROM award_shells aws
      WHERE aws.id = award_shell_team_members.shell_id
      AND (
        (aws.user_id = (select auth.uid()) AND aws.team_member_id IS NULL)
        OR aws.created_by = (select auth.uid())
      )
    )
  );

-- AWARD SHELL WINS POLICIES
DROP POLICY IF EXISTS "Users can add wins to their award shells" ON award_shell_wins;
CREATE POLICY "Users can add wins to their award shells"
  ON award_shell_wins FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM award_shells aws
      WHERE aws.id = award_shell_wins.shell_id
      AND (
        (aws.user_id = (select auth.uid()) AND aws.team_member_id IS NULL)
        OR aws.created_by = (select auth.uid())
        OR EXISTS (
          SELECT 1 FROM team_history th
          WHERE th.subordinate_id = aws.user_id
          AND th.supervisor_id = (select auth.uid())
        )
      )
    )
  );

DROP POLICY IF EXISTS "Users can delete wins from their award shells" ON award_shell_wins;
CREATE POLICY "Users can delete wins from their award shells"
  ON award_shell_wins FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM award_shells aws
      WHERE aws.id = award_shell_wins.shell_id
      AND (
        (aws.user_id = (select auth.uid()) AND aws.team_member_id IS NULL)
        OR aws.created_by = (select auth.uid())
      )
    )
  );

-- ============================================================================
-- PART 5: ADD MISSING INDEXES FOR FOREIGN KEYS
-- ============================================================================

-- award_shell_team_members
CREATE INDEX IF NOT EXISTS idx_award_shell_team_members_added_by 
  ON award_shell_team_members(added_by);

CREATE INDEX IF NOT EXISTS idx_award_shell_team_members_profile_id 
  ON award_shell_team_members(profile_id) 
  WHERE profile_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_award_shell_team_members_team_member_id 
  ON award_shell_team_members(team_member_id) 
  WHERE team_member_id IS NOT NULL;

-- award_shell_sections
CREATE INDEX IF NOT EXISTS idx_award_shell_sections_last_edited_by 
  ON award_shell_sections(last_edited_by) 
  WHERE last_edited_by IS NOT NULL;

-- award_shell_shares
CREATE INDEX IF NOT EXISTS idx_award_shell_shares_owner_id 
  ON award_shell_shares(owner_id);

-- award_shell_snapshots
CREATE INDEX IF NOT EXISTS idx_award_shell_snapshots_created_by 
  ON award_shell_snapshots(created_by) 
  WHERE created_by IS NOT NULL;

-- award_shell_wins
CREATE INDEX IF NOT EXISTS idx_award_shell_wins_shell_id 
  ON award_shell_wins(shell_id);

-- decoration_shells
CREATE INDEX IF NOT EXISTS idx_decoration_shells_user_team 
  ON decoration_shells(user_id, team_member_id);

-- decoration_shell_shares
CREATE INDEX IF NOT EXISTS idx_decoration_shell_shares_owner_id 
  ON decoration_shell_shares(owner_id);

-- decoration_shell_snapshots
CREATE INDEX IF NOT EXISTS idx_decoration_shell_snapshots_created_by 
  ON decoration_shell_snapshots(created_by) 
  WHERE created_by IS NOT NULL;

-- supervisor_feedbacks
CREATE INDEX IF NOT EXISTS idx_supervisor_feedbacks_subordinate_team 
  ON supervisor_feedbacks(subordinate_id) 
  WHERE subordinate_id IS NOT NULL;

-- supervisor_expectations  
CREATE INDEX IF NOT EXISTS idx_supervisor_expectations_subordinate_idx 
  ON supervisor_expectations(subordinate_id) 
  WHERE subordinate_id IS NOT NULL;

-- opb_shell_sections
CREATE INDEX IF NOT EXISTS idx_opb_shell_sections_last_edited_by 
  ON opb_shell_sections(last_edited_by) 
  WHERE last_edited_by IS NOT NULL;

-- opb_shell_snapshots
CREATE INDEX IF NOT EXISTS idx_opb_shell_snapshots_created_by 
  ON opb_shell_snapshots(created_by) 
  WHERE created_by IS NOT NULL;

-- opb_shell_shares
CREATE INDEX IF NOT EXISTS idx_opb_shell_shares_owner_id 
  ON opb_shell_shares(owner_id);

-- opb_duty_description_snapshots
CREATE INDEX IF NOT EXISTS idx_opb_duty_description_snapshots_created_by 
  ON opb_duty_description_snapshots(created_by) 
  WHERE created_by IS NOT NULL;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON FUNCTION public.update_decoration_shell_updated_at IS 'Trigger function with search_path fixed for security';
COMMENT ON FUNCTION public.update_award_shell_updated_at IS 'Trigger function with search_path fixed for security';
COMMENT ON FUNCTION public.update_opb_shell_updated_at IS 'Trigger function with search_path fixed for security';
