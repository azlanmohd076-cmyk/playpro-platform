-- ============================================================
-- PlayPro Model 6: Public Coach Profile RPC
-- Purpose: Read-only public Coach Passport view without exposing raw tables.
-- This avoids RLS blocking certified_assessors when viewing other coaches.
-- ============================================================

CREATE OR REPLACE FUNCTION get_public_coach_profile(p_profile_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_profile JSONB;
  v_assessor JSONB;
BEGIN
  SELECT jsonb_build_object(
    'id', p.id,
    'full_name', p.full_name,
    'email', p.email,
    'role', p.role,
    'avatar_url', p.avatar_url,
    'date_of_birth', p.date_of_birth,
    'ic_number', p.ic_number,
    'passport_number', p.passport_number,
    'nationality', COALESCE(p.nationality, 'Malaysian')
  )
  INTO v_profile
  FROM profiles p
  WHERE p.id = p_profile_id
    AND p.role = 'coach';

  IF v_profile IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'COACH_PROFILE_NOT_FOUND'
    );
  END IF;

  SELECT jsonb_build_object(
    'profile_id', ca.profile_id,
    'license_type', ca.license_type,
    'status', ca.status,
    'trust_score', ca.trust_score,
    'max_attribute_score', ca.max_attribute_score,
    'metadata', COALESCE(ca.metadata, '{}'::jsonb)
  )
  INTO v_assessor
  FROM certified_assessors ca
  WHERE ca.profile_id = p_profile_id;

  RETURN jsonb_build_object(
    'success', true,
    'profile', v_profile,
    'assessor', COALESCE(v_assessor, '{}'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION get_public_coach_profile(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_public_coach_profile(UUID) TO anon, authenticated;
