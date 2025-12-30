-- ============================================
-- SHELL FIELD LOCKS
-- For locking shell-level fields like duty_description
-- ============================================

CREATE TABLE epb_shell_field_locks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_id UUID NOT NULL REFERENCES epb_shells(id) ON DELETE CASCADE,
  field_key TEXT NOT NULL, -- e.g., 'duty_description'
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '5 minutes'),
  
  -- Only one lock per field per shell
  UNIQUE (shell_id, field_key)
);

-- Index for quick lookups
CREATE INDEX idx_shell_field_locks_shell ON epb_shell_field_locks(shell_id);
CREATE INDEX idx_shell_field_locks_expires ON epb_shell_field_locks(expires_at);

-- RLS
ALTER TABLE epb_shell_field_locks ENABLE ROW LEVEL SECURITY;

-- Anyone can view locks for shells they have access to
CREATE POLICY "View shell field locks" ON epb_shell_field_locks
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM epb_shells es
    WHERE es.id = shell_id
    AND (
      es.user_id = auth.uid()
      OR es.created_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM epb_shell_shares ess
        WHERE ess.shell_id = es.id AND ess.shared_with_id = auth.uid()
      )
    )
  )
);

-- Users can insert/update/delete their own locks
CREATE POLICY "Manage own shell field locks" ON epb_shell_field_locks
FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ============================================
-- RPC: Get all field locks for a shell
-- ============================================
CREATE OR REPLACE FUNCTION get_shell_field_locks(p_shell_id UUID)
RETURNS TABLE (
  field_key TEXT,
  user_id UUID,
  user_name TEXT,
  user_rank TEXT,
  acquired_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Clean up expired locks first
  DELETE FROM epb_shell_field_locks
  WHERE shell_id = p_shell_id AND expires_at < now();
  
  RETURN QUERY
  SELECT 
    sfl.field_key,
    sfl.user_id,
    p.full_name,
    p.rank::TEXT,
    sfl.acquired_at,
    sfl.expires_at
  FROM epb_shell_field_locks sfl
  JOIN profiles p ON p.id = sfl.user_id
  WHERE sfl.shell_id = p_shell_id
  AND sfl.expires_at > now();
END;
$$;

-- ============================================
-- RPC: Acquire a field lock
-- ============================================
CREATE OR REPLACE FUNCTION acquire_shell_field_lock(
  p_shell_id UUID,
  p_field_key TEXT,
  p_user_id UUID
)
RETURNS TABLE (
  success BOOLEAN,
  locked_by_name TEXT,
  locked_by_rank TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing_lock epb_shell_field_locks;
  v_lock_duration INTERVAL := interval '5 minutes';
BEGIN
  -- Clean up expired locks
  DELETE FROM epb_shell_field_locks
  WHERE shell_id = p_shell_id AND expires_at < now();
  
  -- Check for existing lock
  SELECT * INTO v_existing_lock
  FROM epb_shell_field_locks
  WHERE shell_id = p_shell_id AND field_key = p_field_key
  FOR UPDATE;
  
  IF v_existing_lock IS NULL THEN
    -- No lock exists, create one
    INSERT INTO epb_shell_field_locks (shell_id, field_key, user_id, acquired_at, expires_at)
    VALUES (p_shell_id, p_field_key, p_user_id, now(), now() + v_lock_duration);
    
    RETURN QUERY SELECT TRUE, NULL::TEXT, NULL::TEXT;
  ELSIF v_existing_lock.user_id = p_user_id THEN
    -- User already has the lock, refresh it
    UPDATE epb_shell_field_locks
    SET expires_at = now() + v_lock_duration
    WHERE id = v_existing_lock.id;
    
    RETURN QUERY SELECT TRUE, NULL::TEXT, NULL::TEXT;
  ELSE
    -- Someone else has the lock
    RETURN QUERY
    SELECT FALSE, p.full_name, p.rank::TEXT
    FROM profiles p
    WHERE p.id = v_existing_lock.user_id;
  END IF;
END;
$$;

-- ============================================
-- RPC: Release a field lock
-- ============================================
CREATE OR REPLACE FUNCTION release_shell_field_lock(
  p_shell_id UUID,
  p_field_key TEXT,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM epb_shell_field_locks
  WHERE shell_id = p_shell_id
  AND field_key = p_field_key
  AND user_id = p_user_id;
END;
$$;

-- ============================================
-- RPC: Refresh a field lock (heartbeat)
-- ============================================
CREATE OR REPLACE FUNCTION refresh_shell_field_lock(
  p_shell_id UUID,
  p_field_key TEXT,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_duration INTERVAL := interval '5 minutes';
BEGIN
  UPDATE epb_shell_field_locks
  SET expires_at = now() + v_lock_duration
  WHERE shell_id = p_shell_id
  AND field_key = p_field_key
  AND user_id = p_user_id;
  
  RETURN FOUND;
END;
$$;

-- Enable realtime for the locks table
ALTER PUBLICATION supabase_realtime ADD TABLE epb_shell_field_locks;

