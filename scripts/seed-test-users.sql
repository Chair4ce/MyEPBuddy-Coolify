-- Seed file for testing team hierarchies and RLS permissions
-- Run with: psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -f scripts/seed-test-users.sql

-- ============================================
-- STEP 1: Create test users in auth.users
-- ============================================
-- Using confirmed password hash for 'password123' created by Supabase

DO $$
DECLARE
  password_hash text := crypt('password123', gen_salt('bf'));
BEGIN
  -- Flight Chief (MSgt level - top supervisor)
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token)
  VALUES ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'msgt.smith@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"John Smith"}', now(), now(), '', '')
  ON CONFLICT (id) DO NOTHING;

  -- Section NCOICs (TSgt level)
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token)
  VALUES ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tsgt.jones@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Sarah Jones"}', now(), now(), '', '')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token)
  VALUES ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tsgt.williams@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Mike Williams"}', now(), now(), '', '')
  ON CONFLICT (id) DO NOTHING;

  -- Team Leaders (SSgt level)
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token)
  VALUES ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ssgt.brown@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Emily Brown"}', now(), now(), '', '')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token)
  VALUES ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ssgt.davis@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Chris Davis"}', now(), now(), '', '')
  ON CONFLICT (id) DO NOTHING;

  -- Airmen (SrA/A1C level)
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token)
  VALUES ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sra.miller@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Alex Miller"}', now(), now(), '', '')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token)
  VALUES ('77777777-7777-7777-7777-777777777777', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a1c.wilson@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Jordan Wilson"}', now(), now(), '', '')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token)
  VALUES ('88888888-8888-8888-8888-888888888888', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sra.taylor@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Sam Taylor"}', now(), now(), '', '')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token)
  VALUES ('99999999-9999-9999-9999-999999999999', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a1c.anderson@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Casey Anderson"}', now(), now(), '', '')
  ON CONFLICT (id) DO NOTHING;
END $$;

-- Add identities for each user (required for email login)
INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
SELECT 
  id,
  id,
  json_build_object('sub', id::text, 'email', email),
  'email',
  id::text,
  now(),
  now(),
  now()
FROM auth.users
WHERE email LIKE '%@test.af.mil'
ON CONFLICT DO NOTHING;

-- Fix NULL columns that GoTrue expects to be empty strings
UPDATE auth.users 
SET email_change = '', 
    email_change_token_new = '', 
    email_change_token_current = '', 
    phone_change = '', 
    phone_change_token = '', 
    reauthentication_token = '' 
WHERE email LIKE '%@test.af.mil';

-- ============================================
-- Create auth users for managed members (for testing link flow)
-- ============================================
DO $$
DECLARE
  password_hash text := crypt('password123', gen_salt('bf'));
BEGIN
  -- Pat Thompson (managed by SSgt Davis)
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
  VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'amn.thompson@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Pat Thompson"}', now(), now(), '', '', '', '', '', '', '', '')
  ON CONFLICT (id) DO NOTHING;

  -- Riley Johnson (created by TSgt Jones, reports to SSgt Brown)
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
  VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a1c.johnson@test.af.mil', password_hash, now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Riley Johnson"}', now(), now(), '', '', '', '', '', '', '', '')
  ON CONFLICT (id) DO NOTHING;
END $$;

-- Add identities for managed member email login
INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
VALUES 
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'cccccccc-cccc-cccc-cccc-cccccccccccc', '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc","email":"amn.thompson@test.af.mil"}', 'email', 'cccccccc-cccc-cccc-cccc-cccccccccccc', now(), now(), now()),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'dddddddd-dddd-dddd-dddd-dddddddddddd', '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddddd","email":"a1c.johnson@test.af.mil"}', 'email', 'dddddddd-dddd-dddd-dddd-dddddddddddd', now(), now(), now())
ON CONFLICT DO NOTHING;

-- Update profiles with proper info for managed member auth users
UPDATE profiles SET full_name = 'Pat Thompson', rank = 'Amn', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
UPDATE profiles SET full_name = 'Riley Johnson', rank = 'A1C', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';

-- ============================================
-- STEP 2: Update profiles with proper info
-- ============================================

UPDATE profiles SET full_name = 'John Smith', rank = 'MSgt', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = '11111111-1111-1111-1111-111111111111';
UPDATE profiles SET full_name = 'Sarah Jones', rank = 'TSgt', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = '22222222-2222-2222-2222-222222222222';
UPDATE profiles SET full_name = 'Mike Williams', rank = 'TSgt', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = '33333333-3333-3333-3333-333333333333';
UPDATE profiles SET full_name = 'Emily Brown', rank = 'SSgt', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = '44444444-4444-4444-4444-444444444444';
UPDATE profiles SET full_name = 'Chris Davis', rank = 'SSgt', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = '55555555-5555-5555-5555-555555555555';
UPDATE profiles SET full_name = 'Alex Miller', rank = 'SrA', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = '66666666-6666-6666-6666-666666666666';
UPDATE profiles SET full_name = 'Jordan Wilson', rank = 'A1C', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = '77777777-7777-7777-7777-777777777777';
UPDATE profiles SET full_name = 'Sam Taylor', rank = 'SrA', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = '88888888-8888-8888-8888-888888888888';
UPDATE profiles SET full_name = 'Casey Anderson', rank = 'A1C', afsc = '3D0X2', unit = '42 CS/SCOO' WHERE id = '99999999-9999-9999-9999-999999999999';

-- ============================================
-- STEP 3: Create team relationships
-- ============================================

-- MSgt Smith supervises TSgts
INSERT INTO teams (supervisor_id, subordinate_id) VALUES
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333')
ON CONFLICT DO NOTHING;

-- TSgts supervise SSgts
INSERT INTO teams (supervisor_id, subordinate_id) VALUES
  ('22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444444'),
  ('33333333-3333-3333-3333-333333333333', '55555555-5555-5555-5555-555555555555')
ON CONFLICT DO NOTHING;

-- SSgts supervise Airmen
INSERT INTO teams (supervisor_id, subordinate_id) VALUES
  ('44444444-4444-4444-4444-444444444444', '66666666-6666-6666-6666-666666666666'),
  ('44444444-4444-4444-4444-444444444444', '77777777-7777-7777-7777-777777777777'),
  ('55555555-5555-5555-5555-555555555555', '88888888-8888-8888-8888-888888888888'),
  ('55555555-5555-5555-5555-555555555555', '99999999-9999-9999-9999-999999999999')
ON CONFLICT DO NOTHING;

-- ============================================
-- STEP 4: Create managed members
-- ============================================

INSERT INTO team_members (id, supervisor_id, parent_profile_id, full_name, email, rank, afsc, unit, is_placeholder)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '55555555-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', 'Pat Thompson', 'amn.thompson@test.af.mil', 'Amn', '3D0X2', '42 CS/SCOO', true)
ON CONFLICT DO NOTHING;

INSERT INTO team_members (id, supervisor_id, parent_profile_id, full_name, email, rank, afsc, unit, is_placeholder)
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444444', 'Riley Johnson', 'a1c.johnson@test.af.mil', 'A1C', '3D0X2', '42 CS/SCOO', true)
ON CONFLICT DO NOTHING;

-- ============================================
-- STEP 5: Create accomplishments
-- ============================================

-- MSgt Smith's entries
INSERT INTO accomplishments (user_id, created_by, date, action_verb, details, impact, mpa, cycle_year) VALUES
  ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', '2025-01-15', 'Led', 'Flight-wide training initiative on cybersecurity awareness', 'Improved unit security posture', 'executing_mission', 2025),
  ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', '2025-02-10', 'Mentored', '5 NCOs on leadership development', 'Prepared next generation of leaders', 'leading_people', 2025);

-- TSgt Jones's entries
INSERT INTO accomplishments (user_id, created_by, date, action_verb, details, impact, mpa, cycle_year) VALUES
  ('22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', '2025-01-20', 'Managed', 'Section A operations supporting 24/7 network coverage', 'Zero network outages', 'executing_mission', 2025),
  ('22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', '2025-03-01', 'Coordinated', 'Cross-functional training with Section B', 'Increased interoperability', 'improving_unit', 2025);

-- TSgt Williams's entries (co-worker with TSgt Jones)
INSERT INTO accomplishments (user_id, created_by, date, action_verb, details, impact, mpa, cycle_year) VALUES
  ('33333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', '2025-01-25', 'Directed', 'Section B server migration project', 'Migrated 50 servers with zero downtime', 'executing_mission', 2025),
  ('33333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', '2025-02-15', 'Optimized', 'Resource allocation across team', 'Reduced operating costs by 15%', 'managing_resources', 2025);

-- SSgt Brown's entries
INSERT INTO accomplishments (user_id, created_by, date, action_verb, details, impact, mpa, cycle_year) VALUES
  ('44444444-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444', '2025-02-01', 'Supervised', 'Help desk operations for 500+ users', 'Maintained 95% satisfaction rating', 'executing_mission', 2025);

-- SSgt Davis's entries
INSERT INTO accomplishments (user_id, created_by, date, action_verb, details, impact, mpa, cycle_year) VALUES
  ('55555555-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', '2025-02-05', 'Executed', 'Network infrastructure upgrade', 'Doubled network capacity', 'executing_mission', 2025);

-- SrA Miller's entries
INSERT INTO accomplishments (user_id, created_by, date, action_verb, details, impact, mpa, cycle_year) VALUES
  ('66666666-6666-6666-6666-666666666666', '66666666-6666-6666-6666-666666666666', '2025-01-10', 'Resolved', '150 help desk tickets in first quarter', 'Reduced backlog by 40%', 'executing_mission', 2025),
  ('66666666-6666-6666-6666-666666666666', '66666666-6666-6666-6666-666666666666', '2025-02-20', 'Trained', '3 new airmen on ticketing system', 'Accelerated onboarding by 2 weeks', 'leading_people', 2025);

-- A1C Wilson's entries (some by supervisor)
INSERT INTO accomplishments (user_id, created_by, date, action_verb, details, impact, mpa, cycle_year) VALUES
  ('77777777-7777-7777-7777-777777777777', '77777777-7777-7777-7777-777777777777', '2025-01-05', 'Assisted', 'Senior technicians with server maintenance', 'Gained hands-on experience', 'executing_mission', 2025),
  ('77777777-7777-7777-7777-777777777777', '44444444-4444-4444-4444-444444444444', '2025-03-10', 'Volunteered', 'Base cleanup event', 'Demonstrated community involvement', 'improving_unit', 2025);

-- SrA Taylor's entries
INSERT INTO accomplishments (user_id, created_by, date, action_verb, details, impact, mpa, cycle_year) VALUES
  ('88888888-8888-8888-8888-888888888888', '88888888-8888-8888-8888-888888888888', '2025-01-15', 'Configured', '25 new workstations for incoming personnel', 'Ensured day-one productivity', 'executing_mission', 2025);

-- A1C Anderson's entries
INSERT INTO accomplishments (user_id, created_by, date, action_verb, details, impact, mpa, cycle_year) VALUES
  ('99999999-9999-9999-9999-999999999999', '99999999-9999-9999-9999-999999999999', '2025-02-01', 'Supported', 'Base-wide IT upgrade project', 'Contributed to successful rollout', 'executing_mission', 2025);

-- Managed member entries
INSERT INTO accomplishments (user_id, created_by, team_member_id, date, action_verb, details, impact, mpa, cycle_year) VALUES
  ('55555555-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2025-01-20', 'Performed', 'Cable management in server room', 'Improved airflow and organization', 'executing_mission', 2025),
  ('55555555-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '2025-02-15', 'Assisted', 'Network equipment installation', 'Supported infrastructure upgrade', 'executing_mission', 2025),
  ('22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '2025-03-01', 'Completed', 'Initial technical training certification', 'Ready for independent work assignments', 'executing_mission', 2025);

-- ============================================
-- STEP 6: Create refined statements
-- ============================================

INSERT INTO refined_statements (user_id, created_by, mpa, afsc, rank, statement, cycle_year) VALUES
  ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'executing_mission', '3D0X2', 'MSgt', 'Spearheaded flight-wide cybersecurity awareness initiative; trained 45 personnel--reduced security incidents 30%', 2025),
  ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'leading_people', '3D0X2', 'MSgt', 'Championed professional development for 5 NCOs; guided career progression--3 selected for advanced training', 2025),
  ('66666666-6666-6666-6666-666666666666', '66666666-6666-6666-6666-666666666666', 'executing_mission', '3D0X2', 'SrA', 'Resolved 150 help desk tickets; maintained 98% first-contact resolution--reduced response time 25%', 2025);

-- Managed member statement
INSERT INTO refined_statements (user_id, created_by, team_member_id, mpa, afsc, rank, statement, cycle_year) VALUES
  ('55555555-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'executing_mission', '3D0X2', 'Amn', 'Performed cable management in server room; reorganized 200+ connections--improved airflow efficiency 40%', 2025);

-- ============================================
-- Verification Queries
-- ============================================
SELECT 'Users created: ' || count(*) FROM auth.users WHERE email LIKE '%@test.af.mil';
SELECT 'Profiles created: ' || count(*) FROM profiles;
SELECT 'Teams created: ' || count(*) FROM teams;
SELECT 'Managed members: ' || count(*) FROM team_members;
SELECT 'Accomplishments: ' || count(*) FROM accomplishments;
SELECT 'Statements: ' || count(*) FROM refined_statements;
SELECT 'Pending managed links: ' || count(*) FROM pending_managed_links WHERE status = 'pending';

