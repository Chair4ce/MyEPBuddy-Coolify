-- Migration: Add Officer Ranks to user_rank enum
-- Officers have OPBs (Officer Performance Briefs), not EPBs
-- This allows officers to join the app and manage their enlisted subordinates

-- Add officer ranks to the user_rank enum
ALTER TYPE user_rank ADD VALUE IF NOT EXISTS '2d Lt';
ALTER TYPE user_rank ADD VALUE IF NOT EXISTS '1st Lt';
ALTER TYPE user_rank ADD VALUE IF NOT EXISTS 'Capt';
ALTER TYPE user_rank ADD VALUE IF NOT EXISTS 'Maj';
ALTER TYPE user_rank ADD VALUE IF NOT EXISTS 'Lt Col';
ALTER TYPE user_rank ADD VALUE IF NOT EXISTS 'Col';
ALTER TYPE user_rank ADD VALUE IF NOT EXISTS 'Brig Gen';
ALTER TYPE user_rank ADD VALUE IF NOT EXISTS 'Maj Gen';
ALTER TYPE user_rank ADD VALUE IF NOT EXISTS 'Lt Gen';
ALTER TYPE user_rank ADD VALUE IF NOT EXISTS 'Gen';
