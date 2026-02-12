-- AI Model Survey: One-time product validation survey
-- Collects user interest in premium AI models and willingness to pay
-- Used for product validation only - no actual payment integration

CREATE TABLE ai_model_survey_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Survey answers
  payment_preference TEXT NOT NULL CHECK (
    payment_preference IN ('subscription', 'on_demand', 'bring_own_key', 'not_interested', 'dismissed')
  ),
  price_point INTEGER, -- Dollar amount selected (null if not interested/dismissed/skipped)
  
  -- Context
  source_page TEXT NOT NULL CHECK (
    source_page IN ('generate', 'award', 'decoration')
  ),
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- One response per user
  CONSTRAINT unique_user_survey UNIQUE (user_id)
);

-- Indexes
CREATE INDEX idx_ai_model_survey_user ON ai_model_survey_responses(user_id);
CREATE INDEX idx_ai_model_survey_preference ON ai_model_survey_responses(payment_preference);

-- Enable RLS
ALTER TABLE ai_model_survey_responses ENABLE ROW LEVEL SECURITY;

-- Users can insert their own response
CREATE POLICY "Users can insert own survey response"
  ON ai_model_survey_responses FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can read their own response (to check if already completed)
CREATE POLICY "Users can read own survey response"
  ON ai_model_survey_responses FOR SELECT
  USING (auth.uid() = user_id);

-- Admins can read all responses for analysis
CREATE POLICY "Admins can read all survey responses"
  ON ai_model_survey_responses FOR SELECT
  USING (
    auth.uid() IN (
      SELECT id FROM profiles WHERE role = 'admin'
    )
  );

COMMENT ON TABLE ai_model_survey_responses IS 'Product validation survey: gauges user interest in premium AI model access and pricing preferences.';
