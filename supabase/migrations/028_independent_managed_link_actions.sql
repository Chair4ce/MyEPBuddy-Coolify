-- Migration: Independent Managed Link Actions
-- Allows users to separately:
-- 1. Sync data (entries/statements) from managed accounts
-- 2. Accept supervisor relationships
-- These are independent actions that can happen in any combination

-- Drop existing functions that we're replacing
DROP FUNCTION IF EXISTS accept_pending_managed_link(uuid);
DROP FUNCTION IF EXISTS reject_pending_managed_link(uuid);

-- Add columns to track independent actions
ALTER TABLE pending_managed_links
ADD COLUMN IF NOT EXISTS data_synced boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS supervisor_accepted boolean DEFAULT false;

-- Function to sync data from a managed account without accepting supervisor
CREATE OR REPLACE FUNCTION sync_managed_account_data(link_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_team_member_id uuid;
  v_entries_synced int := 0;
  v_statements_synced int := 0;
BEGIN
  -- Get the link details
  SELECT user_id, team_member_id INTO v_user_id, v_team_member_id
  FROM pending_managed_links
  WHERE id = link_id AND user_id = auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Link not found or not authorized';
  END IF;

  -- Check if already synced
  IF (SELECT data_synced FROM pending_managed_links WHERE id = link_id) THEN
    RETURN json_build_object('success', true, 'message', 'Data already synced', 'entries_synced', 0, 'statements_synced', 0);
  END IF;

  -- Sync accomplishments: Update user_id to the real user, keep team_member_id for reference
  UPDATE accomplishments
  SET user_id = v_user_id
  WHERE team_member_id = v_team_member_id;
  
  GET DIAGNOSTICS v_entries_synced = ROW_COUNT;

  -- Sync refined statements
  UPDATE refined_statements
  SET user_id = v_user_id
  WHERE team_member_id = v_team_member_id;
  
  GET DIAGNOSTICS v_statements_synced = ROW_COUNT;

  -- Mark data as synced
  UPDATE pending_managed_links
  SET data_synced = true
  WHERE id = link_id;

  -- Update team_member to link to profile (for data continuity)
  UPDATE team_members
  SET linked_user_id = v_user_id
  WHERE id = v_team_member_id;

  RETURN json_build_object(
    'success', true,
    'entries_synced', v_entries_synced,
    'statements_synced', v_statements_synced
  );
END;
$$;

-- Function to accept supervisor relationship from a managed account
CREATE OR REPLACE FUNCTION accept_supervisor_from_link(link_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_team_member_id uuid;
  v_supervisor_id uuid;
  v_supervisor_name text;
BEGIN
  -- Get the link details
  SELECT pml.user_id, pml.team_member_id, tm.supervisor_id
  INTO v_user_id, v_team_member_id, v_supervisor_id
  FROM pending_managed_links pml
  JOIN team_members tm ON pml.team_member_id = tm.id
  WHERE pml.id = link_id AND pml.user_id = auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Link not found or not authorized';
  END IF;

  -- Check if already accepted a supervisor
  IF (SELECT supervisor_accepted FROM pending_managed_links WHERE id = link_id) THEN
    RETURN json_build_object('success', true, 'message', 'Supervisor already accepted');
  END IF;

  -- Get supervisor name for response
  SELECT full_name INTO v_supervisor_name FROM profiles WHERE id = v_supervisor_id;

  -- Create team relationship (if not exists)
  INSERT INTO teams (supervisor_id, subordinate_id)
  VALUES (v_supervisor_id, v_user_id)
  ON CONFLICT (supervisor_id, subordinate_id) DO NOTHING;

  -- Mark supervisor as accepted
  UPDATE pending_managed_links
  SET supervisor_accepted = true
  WHERE id = link_id;

  RETURN json_build_object(
    'success', true,
    'supervisor_id', v_supervisor_id,
    'supervisor_name', v_supervisor_name
  );
END;
$$;

-- Function to dismiss/reject a pending link without taking any action
CREATE OR REPLACE FUNCTION dismiss_pending_link(link_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE pending_managed_links
  SET status = 'rejected',
      responded_at = now()
  WHERE id = link_id AND user_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Link not found or not authorized';
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

-- Function to complete the linking process (mark as done)
CREATE OR REPLACE FUNCTION complete_pending_link(link_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE pending_managed_links
  SET status = 'accepted',
      responded_at = now()
  WHERE id = link_id AND user_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Link not found or not authorized';
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

-- Update the original accept function to use the new flow (backwards compatibility)
CREATE OR REPLACE FUNCTION accept_pending_managed_link(link_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data_result json;
  v_supervisor_result json;
BEGIN
  -- Sync data
  v_data_result := sync_managed_account_data(link_id);
  
  -- Accept supervisor
  v_supervisor_result := accept_supervisor_from_link(link_id);
  
  -- Complete the link
  PERFORM complete_pending_link(link_id);

  RETURN json_build_object(
    'success', true,
    'data_synced', v_data_result,
    'supervisor_accepted', v_supervisor_result
  );
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION sync_managed_account_data(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION accept_supervisor_from_link(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION dismiss_pending_link(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION complete_pending_link(uuid) TO authenticated;

-- Allow users to see team_members that have pending links to them (for onboarding UI)
CREATE POLICY "Users can view team_members with pending links to them"
ON team_members
FOR SELECT
USING (
  id IN (
    SELECT team_member_id 
    FROM pending_managed_links 
    WHERE user_id = auth.uid()
  )
);

-- Allow users to see accomplishments ONLY after accepting the supervisor link
-- This ensures users must commit to the supervisor relationship before seeing content
CREATE POLICY "Users can view accomplishments for accepted pending links"
ON accomplishments
FOR SELECT
USING (
  team_member_id IN (
    SELECT team_member_id 
    FROM pending_managed_links 
    WHERE user_id = auth.uid() 
      AND status = 'pending'
      AND supervisor_accepted = true
  )
);

-- Same for refined_statements
CREATE POLICY "Users can view statements for accepted pending links"
ON refined_statements
FOR SELECT
USING (
  team_member_id IN (
    SELECT team_member_id 
    FROM pending_managed_links 
    WHERE user_id = auth.uid() 
      AND status = 'pending'
      AND supervisor_accepted = true
  )
);

