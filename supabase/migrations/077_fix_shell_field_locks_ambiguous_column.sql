-- Fix ambiguous column reference in get_shell_field_locks function
-- The RETURNS TABLE column names conflicted with table columns

-- Drop the existing function first (can't change return type with CREATE OR REPLACE)
DROP FUNCTION IF EXISTS get_shell_field_locks(UUID);

CREATE OR REPLACE FUNCTION get_shell_field_locks(p_shell_id UUID)
RETURNS TABLE (
  out_field_key TEXT,
  out_user_id UUID,
  out_user_name TEXT,
  out_user_rank TEXT,
  out_acquired_at TIMESTAMPTZ,
  out_expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Clean up expired locks first
  DELETE FROM epb_shell_field_locks
  WHERE shell_id = p_shell_id AND epb_shell_field_locks.expires_at < now();
  
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

