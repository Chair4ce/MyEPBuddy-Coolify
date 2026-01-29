-- Self-hosted analytics events table
-- Keeps all user behavior data in-house, no third-party dependencies

CREATE TABLE analytics_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Who (nullable for anonymous/pre-login events)
  user_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  session_id TEXT NOT NULL, -- Client-generated session identifier
  
  -- What
  event_name TEXT NOT NULL,
  properties JSONB DEFAULT '{}'::jsonb,
  
  -- Where
  page_path TEXT,
  referrer TEXT,
  
  -- When
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Context
  user_agent TEXT,
  screen_width INTEGER,
  screen_height INTEGER
);

-- Indexes for common queries
CREATE INDEX idx_analytics_events_user ON analytics_events(user_id);
CREATE INDEX idx_analytics_events_name ON analytics_events(event_name);
CREATE INDEX idx_analytics_events_created ON analytics_events(created_at DESC);
CREATE INDEX idx_analytics_events_session ON analytics_events(session_id);

-- Composite index for funnel analysis
CREATE INDEX idx_analytics_events_user_time ON analytics_events(user_id, created_at DESC);

-- Enable RLS
ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;

-- Only admins can read analytics (you'll query via service role or admin check)
CREATE POLICY "Admins can read analytics"
  ON analytics_events FOR SELECT
  USING (
    auth.uid() IN (
      SELECT id FROM profiles WHERE role = 'admin'
    )
  );

-- Anyone can insert their own events (we validate server-side)
CREATE POLICY "Users can insert own events"
  ON analytics_events FOR INSERT
  WITH CHECK (true); -- We validate via API route, not RLS

-- Comment for documentation
COMMENT ON TABLE analytics_events IS 'Self-hosted user behavior analytics. No third-party data sharing.';
