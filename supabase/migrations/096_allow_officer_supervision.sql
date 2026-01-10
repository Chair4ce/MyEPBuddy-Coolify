-- Migration: Allow Officers to Supervise
-- Updates the supervisor validation functions to include officer ranks
-- Officers can supervise any rank (enlisted or other officers)
-- Enlisted NCOs can only supervise enlisted members

-- Update the can_supervise function to include officer ranks
CREATE OR REPLACE FUNCTION public.can_supervise(rank_value public.user_rank)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $function$
BEGIN
  -- NCOs (SSgt+) and all Officers can supervise
  RETURN rank_value IN (
    -- Enlisted NCOs
    'SSgt', 'TSgt', 'MSgt', 'SMSgt', 'CMSgt',
    -- Company Grade Officers
    '2d Lt', '1st Lt', 'Capt',
    -- Field Grade Officers
    'Maj', 'Lt Col', 'Col',
    -- General Officers
    'Brig Gen', 'Maj Gen', 'Lt Gen', 'Gen',
    -- Civilians (can also supervise)
    'Civilian'
  );
END;
$function$;

-- Helper function to check if a rank is an officer rank
CREATE OR REPLACE FUNCTION public.is_officer_rank(rank_value public.user_rank)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $function$
BEGIN
  RETURN rank_value IN (
    '2d Lt', '1st Lt', 'Capt', 'Maj', 'Lt Col', 'Col',
    'Brig Gen', 'Maj Gen', 'Lt Gen', 'Gen'
  );
END;
$function$;

-- Helper function to check if a rank is an enlisted rank
CREATE OR REPLACE FUNCTION public.is_enlisted_rank(rank_value public.user_rank)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $function$
BEGIN
  RETURN rank_value IN (
    'AB', 'Amn', 'A1C', 'SrA', 'SSgt', 'TSgt', 'MSgt', 'SMSgt', 'CMSgt'
  );
END;
$function$;

-- Update the validate_supervisor_rank trigger function
-- Now includes officers as valid supervisors
CREATE OR REPLACE FUNCTION public.validate_supervisor_rank()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  supervisor_rank public.user_rank;
  subordinate_rank public.user_rank;
BEGIN
  -- Get the supervisor's rank
  SELECT rank INTO supervisor_rank
  FROM public.profiles
  WHERE id = NEW.supervisor_id;
  
  -- Check if supervisor rank allows supervision
  IF NOT public.can_supervise(supervisor_rank) THEN
    RAISE EXCEPTION 'Only NCOs (SSgt+) and Officers can supervise others. Current rank: %', supervisor_rank;
  END IF;
  
  -- Get the subordinate's rank (if available)
  SELECT rank INTO subordinate_rank
  FROM public.profiles
  WHERE id = NEW.subordinate_id;
  
  -- If supervisor is enlisted, they cannot supervise officers
  IF public.is_enlisted_rank(supervisor_rank) AND public.is_officer_rank(subordinate_rank) THEN
    RAISE EXCEPTION 'Enlisted members cannot supervise officers. Supervisor rank: %, Subordinate rank: %', 
      supervisor_rank, subordinate_rank;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Update the validate_supervision_request trigger function
-- Now allows officers to send/receive supervision requests
CREATE OR REPLACE FUNCTION public.validate_supervision_request()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  requester_rank public.user_rank;
  target_rank public.user_rank;
BEGIN
  -- Get ranks
  SELECT rank INTO requester_rank FROM public.profiles WHERE id = NEW.requester_id;
  SELECT rank INTO target_rank FROM public.profiles WHERE id = NEW.target_id;
  
  -- If requester wants to supervise, they must be able to supervise
  IF NEW.request_type = 'supervise' THEN
    IF NOT public.can_supervise(requester_rank) THEN
      RAISE EXCEPTION 'Only NCOs (SSgt+) and Officers can supervise others';
    END IF;
    
    -- If requester is enlisted, they cannot supervise officers
    IF public.is_enlisted_rank(requester_rank) AND public.is_officer_rank(target_rank) THEN
      RAISE EXCEPTION 'Enlisted members cannot supervise officers';
    END IF;
  END IF;
  
  -- If requester wants to be supervised, the target must be able to supervise
  IF NEW.request_type = 'be_supervised' THEN
    IF NOT public.can_supervise(target_rank) THEN
      RAISE EXCEPTION 'Only NCOs (SSgt+) and Officers can be requested as supervisors';
    END IF;
    
    -- If target is enlisted, they cannot supervise the requester if requester is an officer
    IF public.is_enlisted_rank(target_rank) AND public.is_officer_rank(requester_rank) THEN
      RAISE EXCEPTION 'Enlisted members cannot supervise officers';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$;

-- Note: The triggers themselves (enforce_supervisor_rank, enforce_supervision_request)
-- don't need to be recreated as they just call the functions we've updated above
