-- Add decoration-specific and duty description prompt columns to user_llm_settings
-- Decoration prompts: user-editable citation generation prompt (no abbreviations/acronyms - everything spelled out)
-- Duty description prompts: separate from performance statement prompts (present tense, scope/responsibility)

ALTER TABLE user_llm_settings
  ADD COLUMN IF NOT EXISTS decoration_system_prompt TEXT,
  ADD COLUMN IF NOT EXISTS decoration_style_guidelines TEXT,
  ADD COLUMN IF NOT EXISTS duty_description_prompt TEXT;

-- Add comment for documentation
COMMENT ON COLUMN user_llm_settings.decoration_system_prompt IS 'Custom system prompt for decoration citation generation. No abbreviations/acronyms - decorations require everything spelled out.';
COMMENT ON COLUMN user_llm_settings.decoration_style_guidelines IS 'Style guidelines for decoration citation generation.';
COMMENT ON COLUMN user_llm_settings.duty_description_prompt IS 'Custom prompt for duty description revisions. Uses present tense, describes scope/responsibility, not performance.';
