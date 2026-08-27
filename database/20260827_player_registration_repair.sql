-- PlayPro — atomic player onboarding repair
-- Date: 2026-08-27
-- Apply after model6_p0_auth_identity_repair.sql and playpro_phase6_5_dna_migration.sql.
--
-- The former browser flow attempted an INSERT missing the NOT NULL `position`
-- column, sent detailed position codes to the broader player_position enum,
-- referenced columns that do not exist on `players`, swallowed PostgREST errors,
-- and was denied by the club-admin-only players INSERT policy.
--
-- This authenticated SECURITY DEFINER RPC is the sole player self-onboarding
-- write path. It derives identity from auth.uid(), validates input, maps UI
-- position codes, and upserts atomically against players.profile_id.

BEGIN;

-- Identity details are private profile data, not public player fields.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS ic_number TEXT,
  ADD COLUMN IF NOT EXISTS passport_number TEXT,
  ADD COLUMN IF NOT EXISTS date_of_birth DATE;

CREATE OR REPLACE FUNCTION register_my_player(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_profile profiles%ROWTYPE;
  v_player players%ROWTYPE;
  v_dob DATE;
  v_position_code TEXT := lower(trim(COALESCE(p_payload->>'position', '')));
  v_position player_position;
  v_foot preferred_foot;
  v_jersey INTEGER;
  v_height INTEGER;
  v_weight INTEGER;
  v_name TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_profile FROM profiles WHERE id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found; call ensure_profile_after_signup first'
      USING ERRCODE = 'P0002';
  END IF;
  IF v_profile.role <> 'player'::user_role THEN
    RAISE EXCEPTION 'Only player accounts can create their own player record'
      USING ERRCODE = '42501';
  END IF;

  BEGIN
    v_dob := NULLIF(p_payload->>'date_of_birth', '')::DATE;
    v_jersey := NULLIF(p_payload->>'jersey_number', '')::INTEGER;
    v_height := NULLIF(p_payload->>'height_cm', '')::INTEGER;
    v_weight := NULLIF(p_payload->>'weight_kg', '')::INTEGER;
    v_foot := NULLIF(lower(trim(p_payload->>'preferred_foot')), '')::preferred_foot;
  EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
    RAISE EXCEPTION 'Invalid player onboarding value' USING ERRCODE = '22023';
  END;

  IF v_dob IS NULL OR v_dob > CURRENT_DATE THEN
    RAISE EXCEPTION 'A valid date_of_birth is required' USING ERRCODE = '22023';
  END IF;

  v_position := CASE
    WHEN v_position_code IN ('gk', 'goalkeeper') THEN 'goalkeeper'::player_position
    WHEN v_position_code IN ('cb','lb','rb','lwb','rwb','defender') THEN 'defender'::player_position
    WHEN v_position_code IN ('dm','cm','am','lm','rm','midfielder') THEN 'midfielder'::player_position
    WHEN v_position_code IN ('cf','st','ss','forward') THEN 'forward'::player_position
    ELSE NULL
  END;
  IF v_position IS NULL THEN
    RAISE EXCEPTION 'A valid position is required' USING ERRCODE = '22023';
  END IF;

  IF v_jersey IS NOT NULL AND v_jersey NOT BETWEEN 1 AND 99 THEN
    RAISE EXCEPTION 'jersey_number must be between 1 and 99' USING ERRCODE = '22023';
  END IF;
  IF v_height IS NOT NULL AND v_height NOT BETWEEN 100 AND 230 THEN
    RAISE EXCEPTION 'height_cm must be between 100 and 230' USING ERRCODE = '22023';
  END IF;
  IF v_weight IS NOT NULL AND v_weight NOT BETWEEN 30 AND 150 THEN
    RAISE EXCEPTION 'weight_kg must be between 30 and 150' USING ERRCODE = '22023';
  END IF;

  v_name := COALESCE(NULLIF(trim(v_profile.full_name), ''), 'Pemain Baru');

  UPDATE profiles
     SET phone = COALESCE(NULLIF(trim(p_payload->>'phone'), ''), phone),
         ic_number = CASE WHEN p_payload->>'document_type' <> 'passport'
                          THEN COALESCE(NULLIF(trim(p_payload->>'document_number'), ''), ic_number)
                          ELSE ic_number END,
         passport_number = CASE WHEN p_payload->>'document_type' = 'passport'
                                THEN COALESCE(NULLIF(trim(p_payload->>'document_number'), ''), passport_number)
                                ELSE passport_number END,
         date_of_birth = v_dob,
         updated_at = NOW()
   WHERE id = v_uid;

  INSERT INTO players (
    profile_id, full_name, preferred_name, date_of_birth, position,
    preferred_foot, jersey_number, height_cm, weight_kg,
    best_position, is_active, is_passport_public
  ) VALUES (
    v_uid, v_name,
    COALESCE(NULLIF(trim(p_payload->>'preferred_name'), ''), v_name),
    v_dob, v_position, v_foot, v_jersey, v_height, v_weight,
    upper(v_position_code), true, true
  )
  ON CONFLICT (profile_id) WHERE profile_id IS NOT NULL DO UPDATE SET
    full_name = EXCLUDED.full_name,
    preferred_name = EXCLUDED.preferred_name,
    date_of_birth = EXCLUDED.date_of_birth,
    position = EXCLUDED.position,
    preferred_foot = COALESCE(EXCLUDED.preferred_foot, players.preferred_foot),
    jersey_number = COALESCE(EXCLUDED.jersey_number, players.jersey_number),
    height_cm = COALESCE(EXCLUDED.height_cm, players.height_cm),
    weight_kg = COALESCE(EXCLUDED.weight_kg, players.weight_kg),
    best_position = EXCLUDED.best_position,
    updated_at = NOW()
  RETURNING * INTO v_player;

  RETURN jsonb_build_object(
    'ok', true,
    'player_id', v_player.id,
    'profile_id', v_player.profile_id,
    'position', v_player.position
  );
END;
$$;

REVOKE ALL ON FUNCTION register_my_player(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION register_my_player(JSONB) TO authenticated;

COMMENT ON FUNCTION register_my_player(JSONB) IS
  'Atomic, idempotent self-onboarding for authenticated player accounts. '
  'Never accepts profile_id or role from the browser.';

COMMIT;

-- Verification (run after apply):
-- SELECT routine_name, security_type
-- FROM information_schema.routines
-- WHERE routine_schema='public' AND routine_name='register_my_player';
-- Expected anonymous call: permission denied / unauthenticated.
-- Expected authenticated player call: one players row linked to auth.uid().
