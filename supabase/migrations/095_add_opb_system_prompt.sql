-- Add OPB (Officer Performance Brief) system prompt columns to user_llm_settings
-- Officers can customize their OPB generation prompt similar to enlisted EPB prompts

ALTER TABLE public.user_llm_settings 
  ADD COLUMN IF NOT EXISTS opb_system_prompt TEXT,
  ADD COLUMN IF NOT EXISTS opb_style_guidelines TEXT;

-- Add comment describing the columns
COMMENT ON COLUMN public.user_llm_settings.opb_system_prompt IS 'Custom system prompt for OPB (Officer Performance Brief) statement generation';
COMMENT ON COLUMN public.user_llm_settings.opb_style_guidelines IS 'Custom style guidelines for OPB statement generation';
