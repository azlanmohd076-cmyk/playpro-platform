-- ============================================================
-- PlayPro Model 6: Coach Mock Exam Security Hardening
-- Sprint 7: Backend Security for PCSAP Video Mock Exam
-- Purpose:
-- - Limit brute-force attempts to 3.
-- - Enforce 12-hour cooldown.
-- - Hide master benchmarks behind RLS.
-- - Move grading logic into SECURITY DEFINER RPC.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Ensure base assessor table exists if the previous coach permission migration
-- has not been applied yet. Existing table/data remains untouched.
CREATE TABLE IF NOT EXISTS certified_assessors (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id            UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
  license_type          VARCHAR(50) NOT NULL,
  certificate_url       TEXT,
  status                VARCHAR(20) NOT NULL DEFAULT 'pending',
  trust_score           NUMERIC(3,2) NOT NULL DEFAULT 1.00,
  max_attribute_score   INT NOT NULL DEFAULT 20,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc'::text, NOW()),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc'::text, NOW())
);

CREATE INDEX IF NOT EXISTS idx_assessors_profile_status
  ON certified_assessors(profile_id, status);

ALTER TABLE certified_assessors ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- 1) certified_assessors hardening columns
-- ------------------------------------------------------------

ALTER TABLE certified_assessors
  ADD COLUMN IF NOT EXISTS exam_attempts_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_exam_at TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_assessors_exam_cooldown
  ON certified_assessors(profile_id, exam_attempts_count, last_exam_at);

-- ------------------------------------------------------------
-- 2) master_benchmarks vault table
-- No SELECT policy is created for anon/authenticated.
-- Only service_role / SECURITY DEFINER RPC can read it.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS master_benchmarks (
  attribute_code   TEXT PRIMARY KEY,
  benchmark_score  INT NOT NULL CHECK (benchmark_score BETWEEN 1 AND 20),
  category         TEXT,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE master_benchmarks ENABLE ROW LEVEL SECURITY;

-- Ensure no accidental public/authenticated read policies exist under our known names.
DROP POLICY IF EXISTS "master_benchmarks_public_read" ON master_benchmarks;
DROP POLICY IF EXISTS "master_benchmarks_authenticated_read" ON master_benchmarks;

-- Seed or refresh the protected master benchmark set.
INSERT INTO master_benchmarks (attribute_code, benchmark_score, category) VALUES
  ('judging_ability', 16, 'objective'),
  ('judging_potential', 15, 'objective'),
  ('tactical_knowledge', 14, 'objective'),
  ('coaching_outfield', 15, 'certificate'),
  ('coaching_goalkeepers', 10, 'certificate'),
  ('technical_coaching', 15, 'field'),
  ('attacking_coaching', 14, 'field'),
  ('defending_coaching', 13, 'field'),
  ('fitness_coaching', 12, 'field'),
  ('set_piece_coaching', 13, 'field'),
  ('man_management', 15, 'dynamic'),
  ('motivating', 16, 'dynamic'),
  ('discipline_management', 14, 'dynamic'),
  ('physiotherapy', 9, 'certificate'),
  ('sports_science', 11, 'certificate'),
  ('working_with_youngsters', 17, 'dynamic'),
  ('adaptability', 13, 'dynamic'),
  ('determination', 16, 'dynamic'),
  ('data_analysis', 12, 'objective'),
  ('communication', 15, 'dynamic'),
  ('coaching_style', 14, 'dynamic')
ON CONFLICT (attribute_code) DO UPDATE
SET benchmark_score = EXCLUDED.benchmark_score,
    category = EXCLUDED.category,
    updated_at = NOW();

-- ------------------------------------------------------------
-- 3) Secure RPC: process_coach_mock_exam_result
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION process_coach_mock_exam_result(
  p_profile_id UUID,
  p_submitted_scores JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_now                 TIMESTAMPTZ := NOW();
  v_attempts            INT;
  v_last_exam_at         TIMESTAMPTZ;
  v_cooldown_until       TIMESTAMPTZ;
  v_benchmark_count      INT;
  v_valid_submitted_count INT;
  v_average_error        NUMERIC(10,4);
  v_pass_threshold       NUMERIC(10,4) := 1.5;
BEGIN
  -- Auth guard: caller can only process own exam result.
  IF auth.uid() IS NULL OR auth.uid() <> p_profile_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'UNAUTHORIZED',
      'message', 'Akses tidak dibenarkan.'
    );
  END IF;

  IF p_submitted_scores IS NULL OR jsonb_typeof(p_submitted_scores) <> 'object' THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'INVALID_SUBMISSION',
      'message', 'Format jawapan ujian tidak sah.'
    );
  END IF;

  -- Ensure assessor row exists, then lock it to prevent race conditions.
  INSERT INTO certified_assessors (
    profile_id,
    license_type,
    status,
    max_attribute_score,
    exam_attempts_count,
    metadata
  ) VALUES (
    p_profile_id,
    'PCSAP_VIDEO_MOCK_EXAM',
    'pending',
    5,
    0,
    '{}'::jsonb
  )
  ON CONFLICT (profile_id) DO NOTHING;

  SELECT exam_attempts_count, last_exam_at
    INTO v_attempts, v_last_exam_at
  FROM certified_assessors
  WHERE profile_id = p_profile_id
  FOR UPDATE;

  v_attempts := COALESCE(v_attempts, 0);

  -- Cooldown rule: 3 attempts, then 12 hours lockout.
  IF v_attempts >= 3 AND v_last_exam_at IS NOT NULL THEN
    v_cooldown_until := v_last_exam_at + INTERVAL '12 hours';

    IF v_now < v_cooldown_until THEN
      RETURN jsonb_build_object(
        'success', false,
        'reason', 'COOLDOWN_ACTIVE',
        'message', 'Anda telah mencapai had 3 kali cubaan. Sila tunggu 12 jam tempoh bertenang.',
        'cooldownUntil', v_cooldown_until
      );
    ELSE
      v_attempts := 0;
      UPDATE certified_assessors
      SET exam_attempts_count = 0,
          updated_at = v_now
      WHERE profile_id = p_profile_id;
    END IF;
  END IF;

  -- Count this permitted attempt before grading.
  UPDATE certified_assessors
  SET exam_attempts_count = v_attempts + 1,
      last_exam_at = v_now,
      updated_at = v_now
  WHERE profile_id = p_profile_id;

  SELECT COUNT(*) INTO v_benchmark_count
  FROM master_benchmarks;

  -- Validate submitted values without exposing benchmark keys/scores.
  SELECT COUNT(*) INTO v_valid_submitted_count
  FROM master_benchmarks mb
  JOIN jsonb_each_text(p_submitted_scores) submitted(attribute_code, submitted_score_text)
    ON submitted.attribute_code = mb.attribute_code
  WHERE submitted.submitted_score_text ~ '^[0-9]+(\.[0-9]+)?$'
    AND submitted.submitted_score_text::NUMERIC BETWEEN 1 AND 20;

  IF v_benchmark_count = 0 OR v_valid_submitted_count <> v_benchmark_count THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'INVALID_SUBMISSION',
      'message', 'Jawapan ujian tidak lengkap atau tidak sah.'
    );
  END IF;

  SELECT AVG(ABS(submitted.submitted_score_text::NUMERIC - mb.benchmark_score))
    INTO v_average_error
  FROM master_benchmarks mb
  JOIN jsonb_each_text(p_submitted_scores) submitted(attribute_code, submitted_score_text)
    ON submitted.attribute_code = mb.attribute_code;

  -- Passed: activate assessor and reset attempt counter.
  IF v_average_error <= v_pass_threshold THEN
    UPDATE certified_assessors
    SET status = 'active',
        license_type = COALESCE(NULLIF(license_type, ''), 'PCSAP_VIDEO_MOCK_EXAM'),
        max_attribute_score = 20,
        exam_attempts_count = 0,
        last_exam_at = v_now,
        trust_score = LEAST(5.00, GREATEST(1.00, 5.00 - v_average_error)),
        metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
          'last_mock_exam_status', 'PASSED',
          'last_mock_exam_at', v_now,
          'last_mock_exam_error_margin', ROUND(v_average_error, 2)
        ),
        updated_at = v_now
    WHERE profile_id = p_profile_id;

    RETURN jsonb_build_object(
      'success', true,
      'status', 'PASSED',
      'newGrade', 'GRED_2_CERTIFIED_ASSESSOR',
      'message', 'Tahniah. Anda telah lulus Ujian Video PCSAP dan dinaikkan ke Gred 2.',
      'errorMargin', ROUND(v_average_error, 2)
    );
  END IF;

  -- Failed: generic message only. Do not leak benchmark details.
  UPDATE certified_assessors
  SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
        'last_mock_exam_status', 'FAILED',
        'last_mock_exam_at', v_now
      ),
      updated_at = v_now
  WHERE profile_id = p_profile_id;

  RETURN jsonb_build_object(
    'success', false,
    'status', 'FAILED',
    'reason', 'EXAM_FAILED',
    'message', 'Keputusan ujian tidak mencapai standard penarafan. Sila cuba lagi.'
  );
END;
$$;

REVOKE ALL ON FUNCTION process_coach_mock_exam_result(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION process_coach_mock_exam_result(UUID, JSONB) TO authenticated;

-- ============================================================
-- END OF SPRINT 7 SECURITY HARDENING
-- ============================================================
