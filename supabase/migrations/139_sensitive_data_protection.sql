-- Migration 139: Sensitive Data Protection
-- Adds infrastructure for PII/CUI detection, tracking, and audit logging
-- on accomplishment entries.

-- ──────────────────────────────────────────────────────────────────────────────
-- 1. Add scan tracking columns to accomplishments
-- ──────────────────────────────────────────────────────────────────────────────

ALTER TABLE accomplishments
  ADD COLUMN IF NOT EXISTS sensitive_data_scanned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sensitive_data_flags     JSONB;

COMMENT ON COLUMN accomplishments.sensitive_data_scanned_at
  IS 'Timestamp of the most recent PII/CUI scan for this entry';
COMMENT ON COLUMN accomplishments.sensitive_data_flags
  IS 'JSONB array of detected/redacted sensitive data matches (type, category, severity)';

-- Index to quickly find un-scanned entries for batch processing
CREATE INDEX IF NOT EXISTS idx_accomplishments_unscanned
  ON accomplishments (created_at)
  WHERE sensitive_data_scanned_at IS NULL;

-- ──────────────────────────────────────────────────────────────────────────────
-- 2. Sensitive data audit log table
-- ──────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS sensitive_data_audit_log (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  accomplishment_id UUID        REFERENCES accomplishments(id) ON DELETE SET NULL,
  user_id           UUID,       -- entry owner / actor
  action            TEXT        NOT NULL,  -- 'blocked', 'redacted', 'scan_clean'
  matches           JSONB,      -- array of SensitiveMatch objects detected
  original_snippets JSONB,      -- redacted content snippets for incident response
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE sensitive_data_audit_log
  IS 'Audit trail for PII/CUI detection events — restricted to postgres role only';

-- Indexes for querying audit log
CREATE INDEX IF NOT EXISTS idx_sensitive_audit_accomplishment
  ON sensitive_data_audit_log (accomplishment_id);
CREATE INDEX IF NOT EXISTS idx_sensitive_audit_user
  ON sensitive_data_audit_log (user_id);
CREATE INDEX IF NOT EXISTS idx_sensitive_audit_action
  ON sensitive_data_audit_log (action);
CREATE INDEX IF NOT EXISTS idx_sensitive_audit_created
  ON sensitive_data_audit_log (created_at);

-- ──────────────────────────────────────────────────────────────────────────────
-- 3. RLS — restrict audit log to postgres role only
-- ──────────────────────────────────────────────────────────────────────────────

ALTER TABLE sensitive_data_audit_log ENABLE ROW LEVEL SECURITY;

-- No policies for anon/authenticated — only service_role & postgres can access
-- This ensures users cannot query back redacted content via the Supabase client

-- Grant insert to service_role so server actions can log events
GRANT INSERT ON sensitive_data_audit_log TO service_role;
GRANT SELECT ON sensitive_data_audit_log TO service_role;
