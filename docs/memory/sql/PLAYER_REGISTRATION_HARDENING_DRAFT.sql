-- PLAYPRO — PLAYER REGISTRATION HARDENING (DRAFT ONLY)
-- 2026-11-13
-- DO NOT APPLY until Phase 2C production baseline/reconciliation is complete.
-- Purpose:
--   1) Persist photo_url uploaded to the existing public player-photos bucket.
--   2) Enforce registration field validation server-side.
--   3) Preserve legal name/date of birth for verified players.
--   4) Keep existing profile-role and player-attribute initialization behavior.
--
-- Existing production trigger trg_lock_verified_player_identity already blocks
-- changes to players.full_name, players.date_of_birth and players.profile_id
-- once verification_status='verified'. This function avoids attempting those
-- changes for verified records and avoids changing profiles.full_name then.

CREATE OR REPLACE FUNCTION public.register_my_player(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_profile public.profiles%ROWTYPE;
  v_existing public.players%ROWTYPE;
  v_player public.players%ROWTYPE;
  v_dob date;
  v_position_code text := lower(trim(coalesce(p_payload->>'position','')));
  v_position public.player_position;
  v_foot public.preferred_foot;
  v_jersey integer;
  v_height integer;
  v_weight numeric;
  v_name text;
  v_preferred text;
  v_display text;
  v_visibility text;
  v_phone text;
  v_bio text;
  v_photo_url text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id=v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002';
  END IF;

  SELECT * INTO v_existing
  FROM public.players
  WHERE profile_id=v_uid
  FOR UPDATE;

  v_jersey=NULLIF(trim(p_payload->>'jersey_number'),'')::integer;
  v_height=NULLIF(trim(p_payload->>'height_cm'),'')::integer;
  v_weight=NULLIF(trim(p_payload->>'weight_kg'),'')::numeric;
  v_phone=NULLIF(trim(p_payload->>'phone'),'');
  v_bio=NULLIF(trim(coalesce(p_payload->>'bio',p_payload->>'biography','')),'');
  v_photo_url=NULLIF(trim(p_payload->>'photo_url'),'');

  IF v_existing.id IS NOT NULL AND v_existing.verification_status='verified' THEN
    v_dob := v_existing.date_of_birth;
    v_name := v_existing.full_name;
  ELSE
    v_dob := NULLIF(trim(p_payload->>'date_of_birth'),'')::date;
    v_name := NULLIF(trim(p_payload->>'full_name'),'');
  END IF;

  IF v_dob IS NULL OR v_dob>CURRENT_DATE THEN
    RAISE EXCEPTION 'Tarikh lahir yang sah diperlukan' USING ERRCODE='22023';
  END IF;
  IF v_name IS NULL OR length(v_name)<3 OR length(v_name)>120 THEN
    RAISE EXCEPTION 'Nama sebenar mesti antara 3 hingga 120 aksara' USING ERRCODE='22023';
  END IF;

  v_position=CASE
    WHEN v_position_code IN('gk','goalkeeper') THEN 'goalkeeper'::public.player_position
    WHEN v_position_code IN('cb','lb','rb','lwb','rwb','defender') THEN 'defender'::public.player_position
    WHEN v_position_code IN('dm','cm','am','lm','rm','midfielder') THEN 'midfielder'::public.player_position
    WHEN v_position_code IN('cf','st','ss','forward') THEN 'forward'::public.player_position
    ELSE NULL
  END;
  IF v_position IS NULL THEN
    RAISE EXCEPTION 'Posisi pemain diperlukan' USING ERRCODE='22023';
  END IF;

  v_foot=NULLIF(lower(trim(p_payload->>'preferred_foot')),'')::public.preferred_foot;
  IF v_foot IS NULL AND v_existing.id IS NOT NULL THEN
    v_foot := v_existing.preferred_foot;
  END IF;
  IF v_foot IS NULL THEN
    RAISE EXCEPTION 'Kaki dominan diperlukan' USING ERRCODE='22023';
  END IF;

  IF v_jersey IS NOT NULL AND v_jersey NOT BETWEEN 1 AND 99 THEN
    RAISE EXCEPTION 'Nombor jersi mesti antara 1 hingga 99' USING ERRCODE='22023';
  END IF;
  IF v_height IS NOT NULL AND v_height NOT BETWEEN 100 AND 230 THEN
    RAISE EXCEPTION 'Tinggi mesti antara 100 hingga 230 cm' USING ERRCODE='22023';
  END IF;
  IF v_weight IS NOT NULL AND v_weight NOT BETWEEN 30 AND 150 THEN
    RAISE EXCEPTION 'Berat mesti antara 30 hingga 150 kg' USING ERRCODE='22023';
  END IF;

  IF v_photo_url IS NOT NULL AND v_photo_url NOT LIKE
    'https://muirhenvjruvfxenoaxm.supabase.co/storage/v1/object/public/player-photos/'||v_uid::text||'/%' THEN
    RAISE EXCEPTION 'Lokasi foto profil tidak sah' USING ERRCODE='22023';
  END IF;

  v_preferred=NULLIF(trim(p_payload->>'preferred_name'),'');
  v_display=lower(trim(coalesce(p_payload->>'display_name_mode','preferred')));
  v_visibility=CASE WHEN p_payload->>'profile_visibility'='private' THEN 'private' ELSE 'public' END;
  IF v_display NOT IN ('legal','preferred') THEN v_display='preferred'; END IF;

  -- A verified legal name is authoritative. Do not overwrite profiles.full_name.
  IF v_existing.id IS NULL OR v_existing.verification_status IS DISTINCT FROM 'verified' THEN
    UPDATE public.profiles
    SET full_name=v_name, phone=coalesce(v_phone,phone), updated_at=now()
    WHERE id=v_uid;
  END IF;

  INSERT INTO public.players(
    profile_id,full_name,preferred_name,nickname,date_of_birth,position,preferred_foot,dominant_foot,
    jersey_number,preferred_jersey_no,height_cm,weight_kg,nationality,is_active,photo_url,profile_visibility,
    verification_status,kyc_status,profile_completed_at,football_passport_no,passport_number,
    display_name_mode,biography,bio,phone,is_free_agent
  )
  VALUES(
    v_uid,v_name,v_preferred,v_preferred,v_dob,v_position,v_foot,v_foot::text,
    v_jersey,v_jersey,v_height,v_weight,coalesce(nullif(trim(p_payload->>'nationality'),''),'Malaysian'),
    true,v_photo_url,v_visibility,'unverified','unverified',now(),NULL,NULL,
    v_display,v_bio,v_bio,v_phone,true
  )
  ON CONFLICT(profile_id) DO UPDATE SET
    full_name=CASE WHEN public.players.verification_status='verified' THEN public.players.full_name ELSE excluded.full_name END,
    preferred_name=excluded.preferred_name,
    nickname=excluded.nickname,
    date_of_birth=CASE WHEN public.players.verification_status='verified' THEN public.players.date_of_birth ELSE excluded.date_of_birth END,
    position=excluded.position,
    preferred_foot=coalesce(excluded.preferred_foot,public.players.preferred_foot),
    dominant_foot=coalesce(excluded.dominant_foot,public.players.dominant_foot),
    jersey_number=coalesce(excluded.jersey_number,public.players.jersey_number),
    preferred_jersey_no=coalesce(excluded.preferred_jersey_no,public.players.preferred_jersey_no),
    height_cm=coalesce(excluded.height_cm,public.players.height_cm),
    weight_kg=coalesce(excluded.weight_kg,public.players.weight_kg),
    nationality=coalesce(excluded.nationality,public.players.nationality),
    photo_url=coalesce(excluded.photo_url,public.players.photo_url),
    profile_visibility=excluded.profile_visibility,
    display_name_mode=excluded.display_name_mode,
    biography=coalesce(excluded.biography,public.players.biography),
    bio=coalesce(excluded.bio,public.players.bio),
    phone=coalesce(excluded.phone,public.players.phone),
    kyc_status=CASE WHEN public.players.verification_status='verified' THEN public.players.kyc_status ELSE excluded.kyc_status END,
    passport_number=coalesce(public.players.passport_number,public.players.football_passport_no),
    is_free_agent=coalesce(public.players.is_free_agent,public.players.club_id IS NULL),
    profile_completed_at=now(),updated_at=now()
  RETURNING * INTO v_player;

  INSERT INTO public.profile_role_profiles(profile_id,role_code,subject_id,is_active)
  VALUES(v_uid,'player',v_player.id,true)
  ON CONFLICT(profile_id,role_code) DO UPDATE
  SET subject_id=EXCLUDED.subject_id,is_active=true,updated_at=now();

  INSERT INTO public.player_attribute_state(player_id)
  VALUES(v_player.id) ON CONFLICT(player_id) DO NOTHING;

  RETURN jsonb_build_object(
    'ok',true,
    'player_id',v_player.id,
    'photo_url',v_player.photo_url,
    'football_passport_no',v_player.football_passport_no,
    'verification_status',v_player.verification_status
  );
END;
$function$;

-- Post-application verification checklist (run only after the baseline gate):
-- A. New account: missing full_name / DOB / position / foot must be rejected.
-- B. Invalid jersey (<1 or >99), height (<100 or >230), weight (<30 or >150)
--    must be rejected by the RPC, not merely by browser controls.
-- C. Upload a JPEG/PNG/WEBP through player-onboarding; verify a file exists in
--    player-photos/<auth.uid>/ and players.photo_url contains its public URL.
-- D. Re-open registration without selecting a new photo; existing photo remains.
-- E. After approved KYC sets players.verification_status='verified', direct
--    attempts to alter full_name/date_of_birth/profile_id must be rejected by
--    trg_lock_verified_player_identity.
-- F. Confirm profile page and Player Card render the saved photo.
