-- ============================================================
-- PlayPro Model 6: Coach Onboarding Profile RPC
-- Purpose: Same flow as player onboarding, but for coach identity + license.
-- ============================================================

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS ic_number TEXT,
  ADD COLUMN IF NOT EXISTS passport_number TEXT,
  ADD COLUMN IF NOT EXISTS nationality TEXT DEFAULT 'Malaysian',
  ADD COLUMN IF NOT EXISTS height_cm INT,
  ADD COLUMN IF NOT EXISTS weight_kg INT;

CREATE OR REPLACE FUNCTION save_coach_onboarding_profile(
  p_profile_id UUID,
  p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_license TEXT;
  v_phone TEXT;
  v_ic TEXT;
  v_passport TEXT;
  v_dob DATE;
  v_height INT;
  v_weight INT;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_profile_id THEN
    RETURN jsonb_build_object('success', false, 'reason', 'UNAUTHORIZED', 'message', 'Akses tidak dibenarkan.');
  END IF;

  v_license := COALESCE(NULLIF(p_payload->>'license_type', ''), 'Grassroots / Lesen D');
  v_phone := NULLIF(p_payload->>'phone', '');
  v_ic := NULLIF(p_payload->>'ic_number', '');
  v_passport := NULLIF(p_payload->>'passport_number', '');
  v_height := NULLIF(p_payload->>'height_cm', '')::INT;
  v_weight := NULLIF(p_payload->>'weight_kg', '')::INT;

  IF p_payload ? 'date_of_birth' AND NULLIF(p_payload->>'date_of_birth', '') IS NOT NULL THEN
    v_dob := (p_payload->>'date_of_birth')::DATE;
  END IF;

  IF v_phone IS NULL OR (v_ic IS NULL AND v_passport IS NULL) OR v_license IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'REQUIRED_FIELDS_MISSING', 'message', 'Sila lengkapkan nombor telefon, dokumen identiti, dan tahap lesen.');
  END IF;

  UPDATE profiles
  SET phone = COALESCE(v_phone, phone),
      ic_number = COALESCE(v_ic, ic_number),
      passport_number = COALESCE(v_passport, passport_number),
      date_of_birth = COALESCE(v_dob, date_of_birth),
      nationality = COALESCE(NULLIF(p_payload->>'nationality', ''), nationality, 'Malaysian'),
      height_cm = COALESCE(v_height, height_cm),
      weight_kg = COALESCE(v_weight, weight_kg),
      role = 'coach',
      updated_at = NOW()
  WHERE id = p_profile_id;

  INSERT INTO certified_assessors (
    profile_id,
    license_type,
    status,
    max_attribute_score,
    metadata,
    updated_at
  ) VALUES (
    p_profile_id,
    v_license,
    'pending',
    5,
    jsonb_build_object(
      'license_type', v_license,
      'height_cm', v_height,
      'weight_kg', v_weight,
      'onboarding_completed', true,
      'preferred_formation', COALESCE(NULLIF(p_payload->>'preferred_formation', ''), '4-4-2'),
      'preferred_style', COALESCE(NULLIF(p_payload->>'preferred_style', ''), 'Balanced')
    ),
    NOW()
  )
  ON CONFLICT (profile_id) DO UPDATE
  SET license_type = EXCLUDED.license_type,
      metadata = COALESCE(certified_assessors.metadata, '{}'::jsonb) || EXCLUDED.metadata,
      updated_at = NOW();

  RETURN jsonb_build_object('success', true, 'reason', 'COACH_ONBOARDING_SAVED', 'message', 'Profil pentauliahan coach berjaya disimpan.');
END;
$$;

REVOKE ALL ON FUNCTION save_coach_onboarding_profile(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_coach_onboarding_profile(UUID, JSONB) TO authenticated;
