-- Migration: Add snooze functionality to pending managed links
-- Allows users to temporarily hide link requests for 7 days

-- ============================================
-- 1. ADD SNOOZED_UNTIL COLUMN
-- ============================================

ALTER TABLE pending_managed_links
ADD COLUMN IF NOT EXISTS snoozed_until timestamp with time zone DEFAULT NULL;

-- ============================================
-- 2. CREATE SNOOZE FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION public.snooze_pending_link(link_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.pending_managed_links
  SET snoozed_until = now() + interval '7 days'
  WHERE id = link_id AND user_id = auth.uid();
  RETURN FOUND;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.snooze_pending_link(uuid) TO authenticated;

-- ============================================
-- 3. CREATE INDEX FOR EFFICIENT FILTERING
-- ============================================

CREATE INDEX IF NOT EXISTS idx_pending_managed_links_snoozed_until
  ON public.pending_managed_links(snoozed_until)
  WHERE snoozed_until IS NOT NULL;
