-- Supervisor visibility and data provenance
-- This migration adds tracking for who created entries/statements and enables proper chain visibility

-- ============================================
-- 0. CLEANUP - Drop duplicate triggers from earlier migrations
-- ============================================

-- Migration 022 created this trigger which conflicts with 026's trigger
DROP TRIGGER IF EXISTS on_profile_created_link_team_member ON profiles;
DROP FUNCTION IF EXISTS link_user_to_team_member();

-- ============================================
-- 1. DATA PROVENANCE - Track who created entries/statements
-- ============================================

-- accomplishments already has created_by column from initial schema
-- Add created_by to refined_statements (to track who created statements)
ALTER TABLE refined_statements 
ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES profiles(id) ON DELETE SET NULL;

-- Backfill: set created_by to user_id for existing statements (self-created)
UPDATE refined_statements SET created_by = user_id WHERE created_by IS NULL;

-- Index for efficient lookups  
CREATE INDEX IF NOT EXISTS idx_refined_statements_created_by ON refined_statements(created_by);

-- ============================================
-- 2. TEAM HISTORY - Track supervisor changes over time
-- ============================================

-- Create team_history to track when supervisor relationships existed
CREATE TABLE IF NOT EXISTS team_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subordinate_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  supervisor_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at TIMESTAMPTZ, -- NULL means current/active relationship
  created_at TIMESTAMPTZ DEFAULT now(),
  
  -- Ensure no overlapping active relationships for same subordinate
  CONSTRAINT unique_active_supervisor UNIQUE (subordinate_id, ended_at)
);

-- Index for efficient history lookups
CREATE INDEX idx_team_history_subordinate ON team_history(subordinate_id);
CREATE INDEX idx_team_history_supervisor ON team_history(supervisor_id);
CREATE INDEX idx_team_history_active ON team_history(subordinate_id) WHERE ended_at IS NULL;

-- RLS for team_history
ALTER TABLE team_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own team history"
  ON team_history FOR SELECT
  USING (subordinate_id = auth.uid() OR supervisor_id = auth.uid());

-- Trigger to auto-create history when team relationship is created
CREATE OR REPLACE FUNCTION create_team_history()
RETURNS TRIGGER AS $$
BEGIN
  -- End any existing active relationship for this subordinate
  UPDATE team_history 
  SET ended_at = now() 
  WHERE subordinate_id = NEW.subordinate_id 
    AND ended_at IS NULL;
  
  -- Create new history entry
  INSERT INTO team_history (subordinate_id, supervisor_id, started_at)
  VALUES (NEW.subordinate_id, NEW.supervisor_id, now());
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_create_team_history ON teams;
CREATE TRIGGER trigger_create_team_history
  AFTER INSERT ON teams
  FOR EACH ROW
  EXECUTE FUNCTION create_team_history();

-- Trigger to end history when team relationship is removed
CREATE OR REPLACE FUNCTION end_team_history()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE team_history 
  SET ended_at = now() 
  WHERE subordinate_id = OLD.subordinate_id 
    AND supervisor_id = OLD.supervisor_id
    AND ended_at IS NULL;
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_end_team_history ON teams;
CREATE TRIGGER trigger_end_team_history
  AFTER DELETE ON teams
  FOR EACH ROW
  EXECUTE FUNCTION end_team_history();

-- ============================================
-- 3. PENDING MANAGED ACCOUNT LINKS
-- ============================================

-- Track pending links for users who sign up with matching managed account emails
CREATE TABLE IF NOT EXISTS pending_managed_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  team_member_id UUID NOT NULL REFERENCES team_members(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at TIMESTAMPTZ DEFAULT now(),
  responded_at TIMESTAMPTZ,
  
  UNIQUE(user_id, team_member_id)
);

CREATE INDEX idx_pending_links_user ON pending_managed_links(user_id);
CREATE INDEX idx_pending_links_status ON pending_managed_links(status);

-- RLS for pending links
ALTER TABLE pending_managed_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their pending links"
  ON pending_managed_links FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "Users can update their pending links"
  ON pending_managed_links FOR UPDATE
  USING (user_id = auth.uid());

-- Function to accept a pending managed link
-- This links the team_member to the user and triggers data migration
CREATE OR REPLACE FUNCTION accept_pending_managed_link(link_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_user_id UUID;
  v_team_member_id UUID;
  v_link_status TEXT;
BEGIN
  -- Get the pending link
  SELECT user_id, team_member_id, status
  INTO v_user_id, v_team_member_id, v_link_status
  FROM pending_managed_links
  WHERE id = link_id AND user_id = auth.uid();
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pending link not found or not owned by current user';
  END IF;
  
  IF v_link_status != 'pending' THEN
    RAISE EXCEPTION 'Link has already been processed';
  END IF;
  
  -- Update the pending link status
  UPDATE pending_managed_links
  SET status = 'accepted', responded_at = now()
  WHERE id = link_id;
  
  -- Link the team_member to this user (this triggers migrate_managed_member_data from 022)
  UPDATE team_members
  SET linked_user_id = v_user_id,
      is_placeholder = false,
      updated_at = now()
  WHERE id = v_team_member_id;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION accept_pending_managed_link(UUID) TO authenticated;

-- Function to reject a pending managed link
CREATE OR REPLACE FUNCTION reject_pending_managed_link(link_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  UPDATE pending_managed_links
  SET status = 'rejected', responded_at = now()
  WHERE id = link_id AND user_id = auth.uid();
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pending link not found or not owned by current user';
  END IF;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION reject_pending_managed_link(UUID) TO authenticated;

-- Update the profile trigger to create pending links instead of auto-linking
CREATE OR REPLACE FUNCTION link_managed_members_by_email()
RETURNS TRIGGER AS $$
BEGIN
  -- When a new profile is created with an email, create pending links
  IF NEW.email IS NOT NULL THEN
    INSERT INTO pending_managed_links (user_id, team_member_id)
    SELECT NEW.id, tm.id
    FROM team_members tm
    WHERE tm.email = NEW.email
      AND tm.linked_user_id IS NULL
      AND tm.is_placeholder = true
    ON CONFLICT (user_id, team_member_id) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 4. RLS POLICIES FOR CHAIN VISIBILITY
-- ============================================

-- Drop ALL existing accomplishment SELECT policies (using exact production names)
DROP POLICY IF EXISTS "Users can view own accomplishments" ON accomplishments;
DROP POLICY IF EXISTS "Parent users can view managed member accomplishments" ON accomplishments;
DROP POLICY IF EXISTS "Supervisors can view subordinate accomplishments" ON accomplishments;
DROP POLICY IF EXISTS "Supervisors can view subordinates accomplishments" ON accomplishments; -- Production uses plural
DROP POLICY IF EXISTS "Supervisors can view managed member accomplishments" ON accomplishments;
DROP POLICY IF EXISTS "Supervisors can view subordinate chain accomplishments" ON accomplishments;
DROP POLICY IF EXISTS "Chain supervisors can view subordinate chain accomplishments" ON accomplishments; -- Production name
DROP POLICY IF EXISTS "Users can insert own accomplishments" ON accomplishments;
DROP POLICY IF EXISTS "Users can create own accomplishments" ON accomplishments; -- Production name
DROP POLICY IF EXISTS "Supervisors can insert subordinate accomplishments" ON accomplishments;
DROP POLICY IF EXISTS "Supervisors can create subordinates accomplishments" ON accomplishments; -- Production name
DROP POLICY IF EXISTS "Supervisors can insert managed member accomplishments" ON accomplishments;

-- Users can see their own accomplishments
CREATE POLICY "Users can view own accomplishments"
  ON accomplishments FOR SELECT
  USING (user_id = auth.uid());

-- Supervisors can see accomplishments for anyone in their subordinate chain
CREATE POLICY "Supervisors can view subordinate chain accomplishments"
  ON accomplishments FOR SELECT
  USING (
    user_id IN (
      SELECT subordinate_id FROM get_subordinate_chain(auth.uid())
    )
  );

-- Supervisors can see accomplishments for managed members they created
CREATE POLICY "Supervisors can view managed member accomplishments"
  ON accomplishments FOR SELECT
  USING (
    team_member_id IN (
      SELECT id FROM team_members WHERE supervisor_id = auth.uid()
    )
  );

-- Users can insert accomplishments for themselves
CREATE POLICY "Users can insert own accomplishments"
  ON accomplishments FOR INSERT
  WITH CHECK (user_id = auth.uid() AND created_by = auth.uid());

-- Supervisors can insert accomplishments for subordinates
CREATE POLICY "Supervisors can insert subordinate accomplishments"
  ON accomplishments FOR INSERT
  WITH CHECK (
    user_id IN (SELECT subordinate_id FROM get_subordinate_chain(auth.uid()))
    AND created_by = auth.uid()
  );

-- Similar policies for refined_statements (using exact production names)
DROP POLICY IF EXISTS "Users can view own statements" ON refined_statements;
DROP POLICY IF EXISTS "Users can view own refined statements" ON refined_statements; -- Production name
DROP POLICY IF EXISTS "Parent users can view managed member refined statements" ON refined_statements;
-- NOTE: "Users can view shared statements" is preserved from migration 017 - do NOT drop
DROP POLICY IF EXISTS "Supervisors can view managed member statements" ON refined_statements;
DROP POLICY IF EXISTS "Supervisors can view managed member refined statements" ON refined_statements; -- From 022
DROP POLICY IF EXISTS "Supervisors can view subordinate chain statements" ON refined_statements;

-- Users can see their own statements
CREATE POLICY "Users can view own statements"
  ON refined_statements FOR SELECT
  USING (user_id = auth.uid());

-- Supervisors can see statements for anyone in their subordinate chain
CREATE POLICY "Supervisors can view subordinate chain statements"
  ON refined_statements FOR SELECT
  USING (
    user_id IN (
      SELECT subordinate_id FROM get_subordinate_chain(auth.uid())
    )
  );

-- Supervisors can see statements for managed members they created
CREATE POLICY "Supervisors can view managed member statements"
  ON refined_statements FOR SELECT
  USING (
    team_member_id IN (
      SELECT id FROM team_members WHERE supervisor_id = auth.uid()
    )
  );

-- Note: The shared statements policy is already handled by migration 017
-- which uses a more comprehensive check including team and community shares

