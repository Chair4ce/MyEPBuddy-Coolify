-- Migration: Add title field to award_shells
-- Allows users to give a custom label/title to award packages
-- Especially useful for team awards to identify the office/section

ALTER TABLE public.award_shells
ADD COLUMN IF NOT EXISTS title TEXT;

-- Add comment
COMMENT ON COLUMN public.award_shells.title IS 'Optional custom title/label for the award package (e.g., "Flight Operations Team" for team awards)';
