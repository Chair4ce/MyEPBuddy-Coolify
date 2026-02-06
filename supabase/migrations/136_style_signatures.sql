-- Style Signatures System
-- Stores LLM-readable writing style fingerprints per user, scoped by:
--   target_rank  - the rank of the ratee being written about
--   target_afsc  - the AFSC of the ratee being written about
--   mpa          - the Major Performance Area
--
-- Signatures capture HOW a user writes (patterns, structure, voice)
-- without storing actual statement text. They are derivative artifacts
-- safe to share down the chain of command.
--
-- Extensible via signature_factors JSONB for future dimensions
-- (e.g., unit culture) without schema changes.

-- ============================================
-- STYLE SIGNATURES TABLE
-- ============================================
CREATE TABLE style_signatures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  -- Scoping dimensions: who is the EPB being written FOR?
  target_rank TEXT NOT NULL,           -- rank of the ratee (e.g., "SSgt", "A1C")
  target_afsc TEXT NOT NULL,           -- AFSC of the ratee (e.g., "1B4X1")
  mpa TEXT NOT NULL CHECK (mpa IN (    -- Major Performance Area or "general"
    'executing_mission',
    'leading_people',
    'managing_resources',
    'improving_unit',
    'whole_airman',
    'general'
  )),

  -- The fingerprint itself
  signature_text TEXT NOT NULL,        -- LLM-readable natural language style description
  signature_factors JSONB DEFAULT '{}' NOT NULL,
  -- Extensible structured data. Current keys:
  --   "statement_patterns": { avg_clause_count, verb_intensity, abbreviation_density, ... }
  -- Future keys added without schema changes:
  --   "unit_culture": { ... }

  -- Source tracking for staleness detection
  source_statement_count INTEGER DEFAULT 0 NOT NULL,
  source_hash TEXT,                    -- hash of source statement IDs

  -- Version tracking for evolution
  version INTEGER DEFAULT 1 NOT NULL,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,

  -- One signature per user per rank+AFSC+MPA combination
  UNIQUE (user_id, target_rank, target_afsc, mpa)
);

-- Indexes for common access patterns
CREATE INDEX idx_style_signatures_user ON style_signatures(user_id);
CREATE INDEX idx_style_signatures_lookup ON style_signatures(user_id, target_rank, target_afsc, mpa);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE style_signatures ENABLE ROW LEVEL SECURITY;

-- Users can fully manage their own signatures
CREATE POLICY "Users can view own signatures" ON style_signatures
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own signatures" ON style_signatures
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own signatures" ON style_signatures
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own signatures" ON style_signatures
  FOR DELETE USING (auth.uid() = user_id);

-- Chain of command read access: subordinates can read their supervisors' signatures
-- This is the key security boundary - subordinates get style data (patterns/fingerprints)
-- but NEVER access to the actual statement text that generated the signature.
CREATE POLICY "Chain subordinates can read supervisor signatures" ON style_signatures
  FOR SELECT USING (
    user_id IN (
      SELECT supervisor_id FROM get_supervisor_chain(auth.uid())
    )
  );

-- ============================================
-- AUTO-UPDATE updated_at TRIGGER
-- ============================================
CREATE OR REPLACE FUNCTION update_style_signature_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_style_signature_updated
  BEFORE UPDATE ON style_signatures
  FOR EACH ROW
  EXECUTE FUNCTION update_style_signature_timestamp();

-- ============================================
-- GRANTS
-- ============================================
GRANT SELECT, INSERT, UPDATE, DELETE ON style_signatures TO authenticated;
