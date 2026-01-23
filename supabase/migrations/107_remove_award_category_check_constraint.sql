-- Migration: Remove award_category check constraint
-- The original constraint limited award_category to a fixed set of values.
-- Now that users can create custom categories, we need to allow any text value.

-- Drop the existing check constraint
ALTER TABLE public.award_shells
DROP CONSTRAINT IF EXISTS award_shells_award_category_check;

-- Add a comment explaining the change
COMMENT ON COLUMN public.award_shells.award_category IS 'Award category key - can be default or user-defined custom category';
