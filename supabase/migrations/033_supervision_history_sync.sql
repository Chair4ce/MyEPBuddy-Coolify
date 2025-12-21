-- Migration: Enhanced supervision history with date syncing
-- 1. Add supervision dates to team_history (actual supervised period vs DB timestamps)
-- 2. Sync dates from teams/team_members to team_history
-- 3. Create history for managed members

-- Add supervision date columns to team_history
ALTER TABLE team_history
ADD COLUMN IF NOT EXISTS supervision_start_date date,
ADD COLUMN IF NOT EXISTS supervision_end_date date;

-- Also track if this came from a managed member (for context)
ALTER TABLE team_history
ADD COLUMN IF NOT EXISTS source_team_member_id uuid REFERENCES team_members(id) ON DELETE SET NULL;

-- Backfill: set supervision dates from existing history timestamps
UPDATE team_history
SET 
  supervision_start_date = COALESCE(supervision_start_date, started_at::date),
  supervision_end_date = COALESCE(supervision_end_date, ended_at::date)
WHERE supervision_start_date IS NULL;

-- Update the create_team_history function to include supervision dates
CREATE OR REPLACE FUNCTION create_team_history()
RETURNS TRIGGER AS $$
BEGIN
  -- End any existing active relationship for this subordinate with this supervisor
  UPDATE team_history 
  SET ended_at = now(),
      supervision_end_date = COALESCE(NEW.supervision_start_date, CURRENT_DATE) - INTERVAL '1 day'
  WHERE subordinate_id = NEW.subordinate_id 
    AND supervisor_id = NEW.supervisor_id
    AND ended_at IS NULL;
  
  -- Create new history entry with supervision dates
  INSERT INTO team_history (
    subordinate_id, 
    supervisor_id, 
    started_at,
    supervision_start_date
  )
  VALUES (
    NEW.subordinate_id, 
    NEW.supervisor_id, 
    now(),
    COALESCE(NEW.supervision_start_date, CURRENT_DATE)
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to sync supervision dates when they're updated on teams table
CREATE OR REPLACE FUNCTION sync_supervision_dates_to_history()
RETURNS TRIGGER AS $$
BEGIN
  -- Update the active history entry with the new dates
  UPDATE team_history
  SET 
    supervision_start_date = NEW.supervision_start_date,
    supervision_end_date = NEW.supervision_end_date
  WHERE subordinate_id = NEW.subordinate_id
    AND supervisor_id = NEW.supervisor_id
    AND ended_at IS NULL;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_sync_supervision_dates ON teams;
CREATE TRIGGER trigger_sync_supervision_dates
  AFTER UPDATE OF supervision_start_date, supervision_end_date ON teams
  FOR EACH ROW
  EXECUTE FUNCTION sync_supervision_dates_to_history();

-- Function to end team history when relationship is deleted
CREATE OR REPLACE FUNCTION end_team_history()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE team_history 
  SET ended_at = now(),
      supervision_end_date = COALESCE(OLD.supervision_end_date, CURRENT_DATE)
  WHERE subordinate_id = OLD.subordinate_id 
    AND supervisor_id = OLD.supervisor_id
    AND ended_at IS NULL;
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_end_team_history ON teams;
CREATE TRIGGER trigger_end_team_history
  BEFORE DELETE ON teams
  FOR EACH ROW
  EXECUTE FUNCTION end_team_history();

-- ============================================
-- MANAGED MEMBER HISTORY
-- ============================================

-- Create table for managed member history (similar to team_history but for managed accounts)
CREATE TABLE IF NOT EXISTS managed_member_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supervisor_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  team_member_id UUID NOT NULL REFERENCES team_members(id) ON DELETE CASCADE,
  member_name TEXT NOT NULL, -- Store name for historical reference
  member_rank TEXT, -- Store rank for historical reference
  member_email TEXT, -- Store email for historical reference
  supervision_start_date date,
  supervision_end_date date,
  status TEXT DEFAULT 'active', -- active, prior_subordinate, archived, deleted
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for efficient lookups
CREATE INDEX IF NOT EXISTS idx_managed_member_history_supervisor ON managed_member_history(supervisor_id);
CREATE INDEX IF NOT EXISTS idx_managed_member_history_member ON managed_member_history(team_member_id);

-- RLS for managed_member_history
ALTER TABLE managed_member_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Supervisors can view their managed member history"
  ON managed_member_history FOR SELECT
  USING (supervisor_id = auth.uid());

-- Trigger to create history when managed member is created
CREATE OR REPLACE FUNCTION create_managed_member_history()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO managed_member_history (
    supervisor_id,
    team_member_id,
    member_name,
    member_rank,
    member_email,
    supervision_start_date,
    status
  ) VALUES (
    NEW.supervisor_id,
    NEW.id,
    NEW.full_name,
    NEW.rank,
    NEW.email,
    COALESCE(NEW.supervision_start_date, CURRENT_DATE),
    NEW.member_status
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_create_managed_member_history ON team_members;
CREATE TRIGGER trigger_create_managed_member_history
  AFTER INSERT ON team_members
  FOR EACH ROW
  EXECUTE FUNCTION create_managed_member_history();

-- Trigger to sync managed member updates to history
CREATE OR REPLACE FUNCTION sync_managed_member_history()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE managed_member_history
  SET 
    member_name = NEW.full_name,
    member_rank = NEW.rank,
    member_email = NEW.email,
    supervision_start_date = NEW.supervision_start_date,
    supervision_end_date = NEW.supervision_end_date,
    status = NEW.member_status,
    updated_at = now()
  WHERE team_member_id = NEW.id
    AND supervisor_id = NEW.supervisor_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_sync_managed_member_history ON team_members;
CREATE TRIGGER trigger_sync_managed_member_history
  AFTER UPDATE ON team_members
  FOR EACH ROW
  EXECUTE FUNCTION sync_managed_member_history();

-- ============================================
-- SUBORDINATE VIEW OF HISTORY
-- ============================================

-- Create a view for subordinates to see their supervision history
-- This combines team_history (real relationships) with linked managed member history
CREATE OR REPLACE VIEW my_supervision_history AS
SELECT 
  th.id,
  'real'::text as relationship_type,
  th.subordinate_id,
  th.supervisor_id,
  p.full_name as supervisor_name,
  p.rank::text as supervisor_rank,
  th.supervision_start_date,
  th.supervision_end_date,
  th.started_at as created_at,
  CASE WHEN th.ended_at IS NULL THEN 'current' ELSE 'ended' END as status
FROM team_history th
JOIN profiles p ON p.id = th.supervisor_id
WHERE th.subordinate_id = auth.uid()

UNION ALL

-- Include managed member history where user was linked
SELECT 
  mmh.id,
  'managed'::text as relationship_type,
  tm.linked_user_id as subordinate_id,
  mmh.supervisor_id,
  p.full_name as supervisor_name,
  p.rank::text as supervisor_rank,
  mmh.supervision_start_date,
  mmh.supervision_end_date,
  mmh.created_at,
  mmh.status
FROM managed_member_history mmh
JOIN team_members tm ON tm.id = mmh.team_member_id
JOIN profiles p ON p.id = mmh.supervisor_id
WHERE tm.linked_user_id = auth.uid();

-- ============================================
-- SUPERVISOR VIEW OF HISTORY
-- ============================================

-- Create a view for supervisors to see all their subordinate history
CREATE OR REPLACE VIEW my_subordinate_history AS
SELECT 
  th.id,
  'real'::text as relationship_type,
  th.subordinate_id as member_id,
  NULL::uuid as team_member_id,
  p.full_name as member_name,
  p.rank::text as member_rank,
  p.email as member_email,
  th.supervision_start_date,
  th.supervision_end_date,
  th.started_at as created_at,
  CASE WHEN th.ended_at IS NULL THEN 'current' ELSE 'ended' END as status
FROM team_history th
JOIN profiles p ON p.id = th.subordinate_id
WHERE th.supervisor_id = auth.uid()

UNION ALL

-- Include managed member history
SELECT 
  mmh.id,
  'managed'::text as relationship_type,
  tm.linked_user_id as member_id,
  mmh.team_member_id,
  mmh.member_name,
  mmh.member_rank::text,
  mmh.member_email,
  mmh.supervision_start_date,
  mmh.supervision_end_date,
  mmh.created_at,
  mmh.status
FROM managed_member_history mmh
JOIN team_members tm ON tm.id = mmh.team_member_id
WHERE mmh.supervisor_id = auth.uid();

