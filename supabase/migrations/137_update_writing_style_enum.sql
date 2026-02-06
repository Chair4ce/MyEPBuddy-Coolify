-- Update writing_style CHECK constraint on profiles table
-- Replace "hybrid" with "chain_of_command" as a writing style option

-- Step 1: Migrate any existing "hybrid" values to "personal" (safe default)
UPDATE profiles SET writing_style = 'personal' WHERE writing_style = 'hybrid';

-- Step 2: Drop the old constraint and add the updated one
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_writing_style_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_writing_style_check
  CHECK (writing_style IN ('personal', 'community', 'chain_of_command'));
