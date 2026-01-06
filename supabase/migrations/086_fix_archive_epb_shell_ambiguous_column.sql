-- Fix ambiguous column reference in archive_epb_shell function
-- The return table has shell_id column which conflicts with epb_shell_sections.shell_id

CREATE OR REPLACE FUNCTION archive_epb_shell(
  p_shell_id UUID,
  p_archive_name TEXT DEFAULT NULL,
  p_clear_after_archive BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
  success BOOLEAN,
  statements_saved INTEGER,
  shell_id UUID,
  error_message TEXT
) AS $$
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
  FROM epb_shells
  WHERE id = p_shell_id
  AND (
    -- Own shell
    (user_id = auth.uid() AND team_member_id IS NULL)
    OR
    -- Supervisor via team history
    (team_member_id IS NULL AND EXISTS (
      SELECT 1 FROM team_history th
      WHERE th.subordinate_id = epb_shells.user_id
      AND th.supervisor_id = auth.uid()
    ))
    OR
    -- Managed member
    (team_member_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM team_members tm
      WHERE tm.id = epb_shells.team_member_id
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
    FROM team_members tm
    WHERE tm.id = v_shell.team_member_id;
    
    v_user_id := v_shell.user_id; -- Supervisor's ID (owner of the statements)
    v_team_member_id := v_shell.team_member_id;
  ELSE
    -- Real user - get info from profiles table
    SELECT p.afsc, p.rank INTO v_afsc, v_rank
    FROM profiles p
    WHERE p.id = v_shell.user_id;
    
    v_user_id := v_shell.user_id;
    v_team_member_id := NULL;
  END IF;

  -- Copy each non-empty section statement to refined_statements
  -- Use table alias to avoid ambiguity with return column shell_id
  FOR v_section IN 
    SELECT ess.* FROM epb_shell_sections ess
    WHERE ess.shell_id = p_shell_id
    AND ess.statement_text IS NOT NULL 
    AND trim(ess.statement_text) != ''
    AND length(trim(ess.statement_text)) > 10 -- Only save meaningful statements
  LOOP
    INSERT INTO refined_statements (
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
      COALESCE(v_rank, 'Amn')::user_rank,
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
  UPDATE epb_shells
  SET 
    status = 'archived',
    archived_at = now(),
    archive_name = COALESCE(p_archive_name, 'EPB ' || v_shell.cycle_year)
  WHERE id = p_shell_id;

  -- Optionally clear the sections after archiving (for fresh start)
  IF p_clear_after_archive THEN
    UPDATE epb_shell_sections ess_update
    SET 
      statement_text = '',
      is_complete = FALSE,
      updated_at = now()
    WHERE ess_update.shell_id = p_shell_id;
  END IF;

  RETURN QUERY SELECT TRUE, v_statements_saved, p_shell_id, NULL::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

