-- ============================================================
-- PlayPro Model 6: Certified Assessors / Coach Permission Layer
-- Purpose: Data Integrity & Anti-Inflation Rule for player assessments
-- Scope: Adds certified_assessors table, RLS, indexes only.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS certified_assessors (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id            UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,

  license_type          VARCHAR(50) NOT NULL,
  certificate_url       TEXT,
  status                VARCHAR(20) NOT NULL DEFAULT 'pending',
  trust_score           NUMERIC(3,2) NOT NULL DEFAULT 1.00,
  max_attribute_score   INT NOT NULL DEFAULT 20,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc'::text, NOW()),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc'::text, NOW()),

  CONSTRAINT certified_assessors_status_chk
    CHECK (status IN ('pending', 'active', 'suspended', 'rejected', 'expired')),
  CONSTRAINT certified_assessors_trust_score_chk
    CHECK (trust_score >= 0.00 AND trust_score <= 5.00),
  CONSTRAINT certified_assessors_max_score_chk
    CHECK (max_attribute_score >= 1 AND max_attribute_score <= 20)
);

-- Indeks laju untuk semakan log masuk/pemberian kuasa jurulatih.
CREATE INDEX IF NOT EXISTS idx_assessors_profile_status
  ON certified_assessors(profile_id, status);

CREATE INDEX IF NOT EXISTS idx_assessors_status
  ON certified_assessors(status);

-- ============================================================
-- RLS: Fail-closed permission model
-- - Coach/assessor can read own certification row only.
-- - No direct frontend insert/update/delete.
-- - Admin/service role or controlled RPC handles approval workflow.
-- ============================================================

ALTER TABLE certified_assessors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "certified_assessors_owner_read" ON certified_assessors;
CREATE POLICY "certified_assessors_owner_read"
  ON certified_assessors
  FOR SELECT
  TO authenticated
  USING (profile_id = auth.uid());

DROP POLICY IF EXISTS "certified_assessors_block_frontend_insert" ON certified_assessors;
CREATE POLICY "certified_assessors_block_frontend_insert"
  ON certified_assessors
  FOR INSERT
  TO authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS "certified_assessors_block_frontend_update" ON certified_assessors;
CREATE POLICY "certified_assessors_block_frontend_update"
  ON certified_assessors
  FOR UPDATE
  TO authenticated
  USING (false)
  WITH CHECK (false);

DROP POLICY IF EXISTS "certified_assessors_block_frontend_delete" ON certified_assessors;
CREATE POLICY "certified_assessors_block_frontend_delete"
  ON certified_assessors
  FOR DELETE
  TO authenticated
  USING (false);

-- ============================================================
-- END
-- ============================================================
