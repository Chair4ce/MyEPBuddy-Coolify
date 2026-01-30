-- Migration 118: Fix duplicate indexes and add missing foreign key indexes
-- Addresses performance advisor warnings

-- ============================================================================
-- PART 1: DROP DUPLICATE INDEXES
-- ============================================================================

-- supervisor_expectations has duplicate indexes on subordinate_id
-- idx_supervisor_expectations_subordinate was created in migration 099
-- idx_supervisor_expectations_subordinate_idx was created in migration 116 (duplicate)
DROP INDEX IF EXISTS public.idx_supervisor_expectations_subordinate_idx;

-- supervisor_feedbacks has duplicate indexes on subordinate_id
-- idx_supervisor_feedbacks_subordinate was created in migration 100
-- idx_supervisor_feedbacks_subordinate_team was created in migration 116 (named differently but same column)
DROP INDEX IF EXISTS public.idx_supervisor_feedbacks_subordinate_team;

-- ============================================================================
-- PART 2: ADD MISSING FOREIGN KEY INDEXES
-- ============================================================================

-- award_shell_wins.added_by
CREATE INDEX IF NOT EXISTS idx_award_shell_wins_added_by 
  ON public.award_shell_wins(added_by);

-- award_shell_wins.generated_award_id
CREATE INDEX IF NOT EXISTS idx_award_shell_wins_generated_award_id 
  ON public.award_shell_wins(generated_award_id) 
  WHERE generated_award_id IS NOT NULL;

-- award_shells.generated_award_id
CREATE INDEX IF NOT EXISTS idx_award_shells_generated_award_id 
  ON public.award_shells(generated_award_id) 
  WHERE generated_award_id IS NOT NULL;

-- project_members.added_by
CREATE INDEX IF NOT EXISTS idx_project_members_added_by 
  ON public.project_members(added_by);

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON INDEX public.idx_award_shell_wins_added_by IS 'Index for FK award_shell_wins_added_by_fkey';
COMMENT ON INDEX public.idx_award_shell_wins_generated_award_id IS 'Index for FK award_shell_wins_generated_award_id_fkey';
COMMENT ON INDEX public.idx_award_shells_generated_award_id IS 'Index for FK award_shells_generated_award_id_fkey';
COMMENT ON INDEX public.idx_project_members_added_by IS 'Index for FK project_members_added_by_fkey';
