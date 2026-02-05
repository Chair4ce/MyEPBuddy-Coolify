-- Fix handle_new_user to cast rank from text to user_rank enum type
-- The rank column is of type user_rank, not text

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rank text;
BEGIN
  -- Get rank from metadata (may be null)
  v_rank := NEW.raw_user_meta_data->>'rank';
  
  INSERT INTO public.profiles (id, email, full_name, avatar_url, role, rank, afsc, unit, terms_accepted_at)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name'),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', NEW.raw_user_meta_data->>'picture'),
    'member',
    -- Only cast to user_rank if the value is not null and is a valid enum value
    CASE 
      WHEN v_rank IS NOT NULL AND v_rank != '' THEN v_rank::user_rank 
      ELSE NULL 
    END,
    NEW.raw_user_meta_data->>'afsc',
    NEW.raw_user_meta_data->>'unit',
    NULL
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
