-- Enforce that only SSgt and above can be supervisors
-- AB, Amn, A1C, SrA cannot have subordinates

-- Create a function to check if a rank can supervise
CREATE OR REPLACE FUNCTION can_supervise(rank_value user_rank)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN rank_value IN ('SSgt', 'TSgt', 'MSgt', 'SMSgt', 'CMSgt');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Create a trigger function to validate supervisor rank
CREATE OR REPLACE FUNCTION validate_supervisor_rank()
RETURNS TRIGGER AS $$
DECLARE
  supervisor_rank user_rank;
BEGIN
  -- Get the supervisor's rank
  SELECT rank INTO supervisor_rank
  FROM profiles
  WHERE id = NEW.supervisor_id;
  
  -- Check if rank allows supervision
  IF supervisor_rank IS NULL OR supervisor_rank NOT IN ('SSgt', 'TSgt', 'MSgt', 'SMSgt', 'CMSgt') THEN
    RAISE EXCEPTION 'Only SSgt and above can supervise others. Current rank: %', supervisor_rank;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger on teams table
DROP TRIGGER IF EXISTS enforce_supervisor_rank ON teams;
CREATE TRIGGER enforce_supervisor_rank
  BEFORE INSERT OR UPDATE ON teams
  FOR EACH ROW
  EXECUTE FUNCTION validate_supervisor_rank();

-- Also validate team_requests - only allow supervision requests from NCOs
CREATE OR REPLACE FUNCTION validate_supervision_request()
RETURNS TRIGGER AS $$
DECLARE
  requester_rank user_rank;
  target_rank user_rank;
BEGIN
  -- Get ranks
  SELECT rank INTO requester_rank FROM profiles WHERE id = NEW.requester_id;
  SELECT rank INTO target_rank FROM profiles WHERE id = NEW.target_id;
  
  -- If requester wants to supervise, they must be SSgt+
  IF NEW.request_type = 'supervise' THEN
    IF requester_rank NOT IN ('SSgt', 'TSgt', 'MSgt', 'SMSgt', 'CMSgt') THEN
      RAISE EXCEPTION 'Only SSgt and above can supervise others';
    END IF;
  END IF;
  
  -- If requester wants to be supervised, the target must be SSgt+
  IF NEW.request_type = 'be_supervised' THEN
    IF target_rank NOT IN ('SSgt', 'TSgt', 'MSgt', 'SMSgt', 'CMSgt') THEN
      RAISE EXCEPTION 'Only SSgt and above can be requested as supervisors';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_supervision_request ON team_requests;
CREATE TRIGGER enforce_supervision_request
  BEFORE INSERT ON team_requests
  FOR EACH ROW
  EXECUTE FUNCTION validate_supervision_request();
