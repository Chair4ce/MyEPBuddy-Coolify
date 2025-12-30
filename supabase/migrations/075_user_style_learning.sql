-- User Style Learning System
-- Enables the app to learn user writing preferences for better AI generations

-- ============================================
-- STYLE PROFILES (Single row per user, ~500 bytes max)
-- ============================================
CREATE TABLE user_style_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
  
  -- === Aggregated Style Metrics (0-100 scale) ===
  -- Higher = more of that characteristic
  sentence_length_pref SMALLINT DEFAULT 50 CHECK (sentence_length_pref BETWEEN 0 AND 100),
  -- 0 = prefers short punchy sentences, 100 = prefers longer detailed sentences
  
  verb_intensity_pref SMALLINT DEFAULT 50 CHECK (verb_intensity_pref BETWEEN 0 AND 100),
  -- 0 = mild verbs (led, managed), 100 = strong verbs (spearheaded, revolutionized)
  
  abbreviation_pref SMALLINT DEFAULT 50 CHECK (abbreviation_pref BETWEEN 0 AND 100),
  -- 0 = prefers full words, 100 = prefers abbreviations (&, Amn, hrs)
  
  metrics_density_pref SMALLINT DEFAULT 50 CHECK (metrics_density_pref BETWEEN 0 AND 100),
  -- 0 = fewer metrics, 100 = metric-heavy statements
  
  formality_pref SMALLINT DEFAULT 50 CHECK (formality_pref BETWEEN 0 AND 100),
  -- 0 = casual/simple, 100 = formal/technical language
  
  -- === Revision Selection Tracking ===
  -- Which revision version user typically picks (helps weight future generations)
  version_1_count INTEGER DEFAULT 0,
  version_2_count INTEGER DEFAULT 0,
  version_3_count INTEGER DEFAULT 0,
  version_other_count INTEGER DEFAULT 0, -- for 4+ versions
  
  -- === Learned Slider/Toggle Preferences ===
  -- Running averages of user's explicit choices
  avg_aggressiveness SMALLINT DEFAULT 50 CHECK (avg_aggressiveness BETWEEN 0 AND 100),
  aggressiveness_samples INTEGER DEFAULT 0,
  
  fill_to_max_ratio SMALLINT DEFAULT 75 CHECK (fill_to_max_ratio BETWEEN 0 AND 100),
  -- What % of time user enables fill-to-max (0 = never, 100 = always)
  fill_to_max_samples INTEGER DEFAULT 0,
  
  -- === Quality Indicators ===
  total_statements_analyzed INTEGER DEFAULT 0,
  total_revisions_selected INTEGER DEFAULT 0,
  total_manual_edits INTEGER DEFAULT 0,
  
  -- === Metadata ===
  last_updated TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for fast lookup during generation
CREATE INDEX idx_style_profiles_user ON user_style_profiles(user_id);

-- RLS for style profiles
ALTER TABLE user_style_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own style profile" ON user_style_profiles
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update own style profile" ON user_style_profiles
FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "System can insert style profiles" ON user_style_profiles
FOR INSERT WITH CHECK (auth.uid() = user_id);


-- ============================================
-- STYLE EXAMPLES BANK (Bounded: max 5 per category per user)
-- ============================================
CREATE TABLE user_style_examples (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  
  -- Category of statement (for targeted few-shot learning)
  category TEXT NOT NULL CHECK (category IN (
    'executing_mission',
    'leading_people', 
    'managing_resources',
    'improving_unit',
    'whole_airman',
    'duty_description',
    'award_statement'
  )),
  
  -- The actual statement text (gold example from user)
  statement_text TEXT NOT NULL,
  
  -- Quality indicators
  is_finalized BOOLEAN DEFAULT false, -- came from a finalized EPB
  was_ai_assisted BOOLEAN DEFAULT false, -- started from AI generation
  edit_ratio SMALLINT DEFAULT 0, -- how much user edited (0-100%)
  
  -- For ordering/replacement (FIFO within category)
  sequence_num SMALLINT DEFAULT 1,
  
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Composite index for category lookups
CREATE INDEX idx_style_examples_user_category ON user_style_examples(user_id, category);

-- RLS for style examples
ALTER TABLE user_style_examples ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own style examples" ON user_style_examples
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own style examples" ON user_style_examples
FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================
-- FEEDBACK EVENTS QUEUE (Async processing, auto-purged)
-- ============================================
CREATE TABLE style_feedback_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  
  -- Event classification
  event_type TEXT NOT NULL CHECK (event_type IN (
    'revision_selected',    -- user picked a revision version
    'revision_copied',      -- user copied a revision (stronger signal)
    'statement_edited',     -- user manually edited after AI
    'statement_finalized',  -- user finalized an EPB section
    'slider_used',          -- user adjusted aggressiveness slider
    'toggle_used'           -- user toggled fill-to-max
  )),
  
  -- Event payload (flexible JSON for different event types)
  payload JSONB NOT NULL,
  -- revision_selected: { version: 1, total_versions: 3, char_count: 350, category: "executing_mission" }
  -- revision_copied: { version: 2, text: "...", category: "leading_people" }
  -- statement_edited: { original: "...", edited: "...", edit_distance: 15 }
  -- statement_finalized: { text: "...", category: "...", was_ai_assisted: true }
  -- slider_used: { value: 75 }
  -- toggle_used: { fill_to_max: true }
  
  -- Processing status
  processed BOOLEAN DEFAULT false,
  processed_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for unprocessed events (background worker query)
CREATE INDEX idx_feedback_events_unprocessed ON style_feedback_events(user_id, processed) 
WHERE processed = false;

-- Auto-delete old processed events (keep queue small)
CREATE INDEX idx_feedback_events_cleanup ON style_feedback_events(processed, created_at)
WHERE processed = true;

-- RLS for feedback events
ALTER TABLE style_feedback_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert own feedback events" ON style_feedback_events
FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view own feedback events" ON style_feedback_events
FOR SELECT USING (auth.uid() = user_id);


-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Function to enforce max 5 examples per category per user
CREATE OR REPLACE FUNCTION enforce_max_style_examples()
RETURNS TRIGGER AS $$
DECLARE
  example_count INTEGER;
  oldest_id UUID;
BEGIN
  -- Count existing examples in this category for this user
  SELECT COUNT(*) INTO example_count
  FROM user_style_examples
  WHERE user_id = NEW.user_id AND category = NEW.category;
  
  -- If at limit (5), delete the oldest one
  IF example_count >= 5 THEN
    SELECT id INTO oldest_id
    FROM user_style_examples
    WHERE user_id = NEW.user_id AND category = NEW.category
    ORDER BY created_at ASC
    LIMIT 1;
    
    DELETE FROM user_style_examples WHERE id = oldest_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_enforce_max_style_examples
BEFORE INSERT ON user_style_examples
FOR EACH ROW
EXECUTE FUNCTION enforce_max_style_examples();


-- Function to auto-create style profile on first feedback event
CREATE OR REPLACE FUNCTION ensure_style_profile_exists()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_style_profiles (user_id)
  VALUES (NEW.user_id)
  ON CONFLICT (user_id) DO NOTHING;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_ensure_style_profile
BEFORE INSERT ON style_feedback_events
FOR EACH ROW
EXECUTE FUNCTION ensure_style_profile_exists();


-- Function to process feedback events and update style profile
-- Called periodically or on-demand
CREATE OR REPLACE FUNCTION process_style_feedback(p_user_id UUID, p_batch_size INTEGER DEFAULT 50)
RETURNS INTEGER AS $$
DECLARE
  events_processed INTEGER := 0;
  event_record RECORD;
  v_version INTEGER;
  v_aggressiveness INTEGER;
  v_fill_to_max BOOLEAN;
BEGIN
  -- Process unprocessed events for this user
  FOR event_record IN
    SELECT id, event_type, payload
    FROM style_feedback_events
    WHERE user_id = p_user_id AND processed = false
    ORDER BY created_at ASC
    LIMIT p_batch_size
  LOOP
    -- Handle each event type
    CASE event_record.event_type
      WHEN 'revision_selected', 'revision_copied' THEN
        v_version := (event_record.payload->>'version')::INTEGER;
        
        -- Update version selection counts
        UPDATE user_style_profiles
        SET 
          version_1_count = version_1_count + CASE WHEN v_version = 1 THEN 1 ELSE 0 END,
          version_2_count = version_2_count + CASE WHEN v_version = 2 THEN 1 ELSE 0 END,
          version_3_count = version_3_count + CASE WHEN v_version = 3 THEN 1 ELSE 0 END,
          version_other_count = version_other_count + CASE WHEN v_version > 3 THEN 1 ELSE 0 END,
          total_revisions_selected = total_revisions_selected + 1,
          last_updated = now()
        WHERE user_id = p_user_id;
        
      WHEN 'slider_used' THEN
        v_aggressiveness := (event_record.payload->>'value')::INTEGER;
        
        -- Update running average of aggressiveness preference
        UPDATE user_style_profiles
        SET 
          avg_aggressiveness = (
            (avg_aggressiveness * aggressiveness_samples + v_aggressiveness) / 
            (aggressiveness_samples + 1)
          )::SMALLINT,
          aggressiveness_samples = aggressiveness_samples + 1,
          last_updated = now()
        WHERE user_id = p_user_id;
        
      WHEN 'toggle_used' THEN
        v_fill_to_max := (event_record.payload->>'fill_to_max')::BOOLEAN;
        
        -- Update fill-to-max ratio
        UPDATE user_style_profiles
        SET 
          fill_to_max_ratio = (
            (fill_to_max_ratio * fill_to_max_samples + CASE WHEN v_fill_to_max THEN 100 ELSE 0 END) / 
            (fill_to_max_samples + 1)
          )::SMALLINT,
          fill_to_max_samples = fill_to_max_samples + 1,
          last_updated = now()
        WHERE user_id = p_user_id;
        
      WHEN 'statement_finalized' THEN
        UPDATE user_style_profiles
        SET 
          total_statements_analyzed = total_statements_analyzed + 1,
          last_updated = now()
        WHERE user_id = p_user_id;
        
      WHEN 'statement_edited' THEN
        UPDATE user_style_profiles
        SET 
          total_manual_edits = total_manual_edits + 1,
          last_updated = now()
        WHERE user_id = p_user_id;
        
      ELSE
        -- Unknown event type, skip
        NULL;
    END CASE;
    
    -- Mark event as processed
    UPDATE style_feedback_events
    SET processed = true, processed_at = now()
    WHERE id = event_record.id;
    
    events_processed := events_processed + 1;
  END LOOP;
  
  RETURN events_processed;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to clean up old processed events (run periodically)
CREATE OR REPLACE FUNCTION cleanup_old_feedback_events(p_days_old INTEGER DEFAULT 7)
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM style_feedback_events
  WHERE processed = true 
    AND created_at < now() - (p_days_old || ' days')::INTERVAL;
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================
-- GRANT PERMISSIONS
-- ============================================
GRANT EXECUTE ON FUNCTION process_style_feedback(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_old_feedback_events(INTEGER) TO service_role;

