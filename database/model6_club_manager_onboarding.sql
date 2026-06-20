-- ============================================================
-- PlayPro Model 6: Club Manager Onboarding RPC
-- Purpose: Club manager can register club profile and become club_admin.
-- ============================================================

CREATE OR REPLACE FUNCTION save_club_manager_onboarding_profile(
  p_profile_id UUID,
  p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_club_id UUID;
  v_org_id UUID;
  v_club_name TEXT;
  v_slug TEXT;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_profile_id THEN
    RETURN jsonb_build_object('success', false, 'reason', 'UNAUTHORIZED', 'message', 'Akses tidak dibenarkan.');
  END IF;

  v_club_name := NULLIF(TRIM(p_payload->>'club_name'), '');

  IF v_club_name IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'CLUB_NAME_REQUIRED', 'message', 'Nama kelab wajib diisi.');
  END IF;

  UPDATE profiles
  SET phone = COALESCE(NULLIF(p_payload->>'phone', ''), phone),
      role = 'club_admin',
      updated_at = NOW()
  WHERE id = p_profile_id;

  SELECT id INTO v_club_id
  FROM clubs
  WHERE admin_id = p_profile_id
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_club_id IS NULL THEN
    INSERT INTO clubs (
      name,
      year_founded,
      home_venue,
      colours,
      admin_id,
      created_at,
      updated_at
    ) VALUES (
      v_club_name,
      NULLIF(p_payload->>'year_founded', '')::INT,
      NULLIF(p_payload->>'training_ground', ''),
      NULLIF(p_payload->>'club_colours', ''),
      p_profile_id,
      NOW(),
      NOW()
    )
    RETURNING id INTO v_club_id;
  ELSE
    UPDATE clubs
    SET name = v_club_name,
        year_founded = COALESCE(NULLIF(p_payload->>'year_founded', '')::INT, year_founded),
        home_venue = COALESCE(NULLIF(p_payload->>'training_ground', ''), home_venue),
        colours = COALESCE(NULLIF(p_payload->>'club_colours', ''), colours),
        updated_at = NOW()
    WHERE id = v_club_id;
  END IF;

  v_slug := lower(regexp_replace(v_club_name, '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substring(v_club_id::text, 1, 8);

  SELECT id INTO v_org_id
  FROM organizations
  WHERE linked_club_id = v_club_id
  LIMIT 1;

  IF v_org_id IS NULL THEN
    INSERT INTO organizations (
      name,
      slug,
      type,
      status,
      linked_club_id,
      owner_profile_id,
      admin_profile_id,
      phone,
      metadata,
      created_by,
      created_at,
      updated_at
    ) VALUES (
      v_club_name,
      v_slug,
      'club',
      'active',
      v_club_id,
      p_profile_id,
      p_profile_id,
      NULLIF(p_payload->>'phone', ''),
      jsonb_build_object(
        'category', COALESCE(NULLIF(p_payload->>'category', ''), 'Akar Umbi'),
        'registered_players_count', COALESCE(NULLIF(p_payload->>'registered_players_count', '')::INT, 0),
        'training_ground', NULLIF(p_payload->>'training_ground', ''),
        'manager_onboarding_completed', true
      ),
      p_profile_id,
      NOW(),
      NOW()
    )
    RETURNING id INTO v_org_id;
  ELSE
    UPDATE organizations
    SET name = v_club_name,
        status = 'active',
        owner_profile_id = COALESCE(owner_profile_id, p_profile_id),
        admin_profile_id = p_profile_id,
        phone = COALESCE(NULLIF(p_payload->>'phone', ''), phone),
        metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
          'category', COALESCE(NULLIF(p_payload->>'category', ''), 'Akar Umbi'),
          'registered_players_count', COALESCE(NULLIF(p_payload->>'registered_players_count', '')::INT, 0),
          'training_ground', NULLIF(p_payload->>'training_ground', ''),
          'manager_onboarding_completed', true
        ),
        updated_at = NOW()
    WHERE id = v_org_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'reason', 'CLUB_MANAGER_ONBOARDING_SAVED',
    'message', 'Profil manager kelab berjaya disimpan.',
    'club_id', v_club_id,
    'organization_id', v_org_id
  );
END;
$$;

REVOKE ALL ON FUNCTION save_club_manager_onboarding_profile(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_club_manager_onboarding_profile(UUID, JSONB) TO authenticated;
