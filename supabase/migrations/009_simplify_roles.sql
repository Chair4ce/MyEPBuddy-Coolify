-- Add 'member' to the enum first (needs separate transaction)
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'member';
