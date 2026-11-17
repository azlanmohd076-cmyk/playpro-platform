-- PlayPro: connect all five role onboarding forms to canonical backend records.
-- Scope: additive profile details + authenticated self-service RPCs only.
-- KYC, competition authority, organizer verification and professional accreditation gates remain unchanged.

ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS gender text,
  ADD COLUMN IF NOT EXISTS state text,
  ADD COLUMN IF NOT EXISTS experience_level text,
  ADD COLUMN IF NOT EXISTS player_status text NOT NULL DEFAULT 'Free Agent',
  ADD COLUMN IF NOT EXISTS current_club_name text,
  ADD COLUMN IF NOT EXISTS guardian_name text,
  ADD COLUMN IF NOT EXISTS guardian_email text,
  ADD COLUMN IF NOT EXISTS guardian_phone text;

ALTER TABLE public.coaches
  ADD COLUMN IF NOT EXISTS gender text,
  ADD COLUMN IF NOT EXISTS height_cm integer,
  ADD COLUMN IF NOT EXISTS weight_kg numeric(5,1),
  ADD COLUMN IF NOT EXISTS state text,
  ADD COLUMN IF NOT EXISTS experience_level text,
  ADD COLUMN IF NOT EXISTS years_experience smallint,
  ADD COLUMN IF NOT EXISTS coaching_roles text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS age_groups text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS club_categories text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS qualification_types text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS other_certificate text;

ALTER TABLE public.referees
  ADD COLUMN IF NOT EXISTS gender text,
  ADD COLUMN IF NOT EXISTS state text,
  ADD COLUMN IF NOT EXISTS years_experience smallint,
  ADD COLUMN IF NOT EXISTS license_status text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS license_grade text,
  ADD COLUMN IF NOT EXISTS license_issuers text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS qualification_types text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS experience_types text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS match_types text[] NOT NULL DEFAULT '{}';

ALTER TABLE public.clubs
  ADD COLUMN IF NOT EXISTS club_categories text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS mailing_address text,
  ADD COLUMN IF NOT EXISTS district text,
  ADD COLUMN IF NOT EXISTS postcode text;

ALTER TABLE public.organizers
  ADD COLUMN IF NOT EXISTS organizer_types text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS commercial_name_en text,
  ADD COLUMN IF NOT EXISTS name_mode text NOT NULL DEFAULT 'account',
  ADD COLUMN IF NOT EXISTS district text,
  ADD COLUMN IF NOT EXISTS base_address text;

CREATE OR REPLACE FUNCTION public.register_my_player(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_profile public.profiles%ROWTYPE;
  v_player public.players%ROWTYPE;
  v_dob date;
  v_position_code text := upper(trim(coalesce(p_payload->>'position','')));
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
  v_status text;
  v_guardian_name text;
  v_guardian_email text;
  v_guardian_phone text;
  v_age integer;
BEGIN
  PERFORM public.playpro_require_active_account();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_profile FROM public.profiles WHERE id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;

  BEGIN
    v_dob := NULLIF(p_payload->>'date_of_birth','')::date;
    v_jersey := NULLIF(p_payload->>'jersey_number','')::integer;
    v_height := NULLIF(p_payload->>'height_cm','')::integer;
    v_weight := NULLIF(p_payload->>'weight_kg','')::numeric;
    v_foot := NULLIF(lower(trim(p_payload->>'preferred_foot')),'')::public.preferred_foot;
  EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow THEN
    RAISE EXCEPTION 'Invalid player onboarding value' USING ERRCODE='22023';
  END;

  IF v_dob IS NULL OR v_dob>CURRENT_DATE THEN
    RAISE EXCEPTION 'Tarikh lahir yang sah diperlukan' USING ERRCODE='22023';
  END IF;

  v_age := extract(year FROM age(CURRENT_DATE,v_dob))::integer;
  v_position := CASE
    WHEN v_position_code IN ('GK','GOALKEEPER') THEN 'goalkeeper'::public.player_position
    WHEN v_position_code IN ('CB','LB','RB','LWB','RWB','DEFENDER') THEN 'defender'::public.player_position
    WHEN v_position_code IN ('CDM','DM','CM','CAM','AM','LM','RM','MIDFIELDER','FLEX') THEN 'midfielder'::public.player_position
    WHEN v_position_code IN ('RW','LW','CF','ST','SS','FORWARD') THEN 'forward'::public.player_position
    ELSE NULL
  END;
  IF v_position IS NULL THEN RAISE EXCEPTION 'Posisi pemain diperlukan' USING ERRCODE='22023'; END IF;

  IF v_jersey IS NOT NULL AND v_jersey NOT BETWEEN 1 AND 99 THEN
    RAISE EXCEPTION 'Nombor jersi mesti antara 1 hingga 99' USING ERRCODE='22023';
  END IF;
  IF v_height IS NOT NULL AND v_height NOT BETWEEN 50 AND 250 THEN
    RAISE EXCEPTION 'Tinggi pemain tidak sah' USING ERRCODE='22023';
  END IF;
  IF v_weight IS NOT NULL AND v_weight NOT BETWEEN 10 AND 250 THEN
    RAISE EXCEPTION 'Berat pemain tidak sah' USING ERRCODE='22023';
  END IF;

  v_name := coalesce(nullif(trim(v_profile.full_name),''),'Pemain Baru');
  v_preferred := nullif(trim(p_payload->>'preferred_name'),'');
  v_display := lower(trim(coalesce(p_payload->>'display_name_mode','preferred')));
  v_visibility := CASE WHEN p_payload->>'profile_visibility'='private' THEN 'private' ELSE 'public' END;
  IF v_display NOT IN ('legal','preferred') THEN v_display := 'preferred'; END IF;
  v_phone := nullif(trim(concat_ws(' ',p_payload->>'phone_code',p_payload->>'phone')),'');
  v_bio := nullif(trim(coalesce(p_payload->>'bio',p_payload->>'biography','')),'');
  v_status := coalesce(nullif(trim(p_payload->>'player_status'),''),'Free Agent');

  IF v_status NOT IN ('Free Agent','Bernaung di kelab','Akademi') THEN
    RAISE EXCEPTION 'Status pemain tidak sah' USING ERRCODE='22023';
  END IF;

  IF v_age < 18 THEN
    v_guardian_name := nullif(trim(p_payload->>'guardian_name'),'');
    v_guardian_email := nullif(lower(trim(p_payload->>'guardian_email')),'');
    v_guardian_phone := nullif(trim(concat_ws(' ',p_payload->>'guardian_phone_code',p_payload->>'guardian_phone')),'');
    IF v_guardian_name IS NULL OR v_guardian_email IS NULL OR v_guardian_phone IS NULL THEN
      RAISE EXCEPTION 'Maklumat penjaga wajib untuk pemain bawah 18 tahun' USING ERRCODE='22023';
    END IF;
  END IF;

  UPDATE public.profiles
     SET phone=coalesce(v_phone,phone), updated_at=now()
   WHERE id=v_uid;

  INSERT INTO public.players(
    profile_id,full_name,preferred_name,nickname,date_of_birth,position,preferred_foot,dominant_foot,
    jersey_number,preferred_jersey_no,height_cm,weight_kg,nationality,is_active,profile_visibility,
    verification_status,kyc_status,profile_completed_at,football_passport_no,passport_number,
    display_name_mode,biography,bio,phone,is_free_agent,best_position,secondary_position,
    gender,state,experience_level,player_status,current_club_name,guardian_name,guardian_email,guardian_phone
  )
  VALUES(
    v_uid,v_name,v_preferred,v_preferred,v_dob,v_position,v_foot,
    CASE WHEN v_foot IS NULL THEN NULL ELSE v_foot::text END,
    v_jersey,v_jersey,v_height,v_weight,
    coalesce(nullif(trim(p_payload->>'nationality'),''),'Malaysian'),
    true,v_visibility,'unverified','unverified',now(),NULL,NULL,v_display,v_bio,v_bio,v_phone,
    (v_status='Free Agent'),v_position_code,
    nullif(upper(trim(p_payload->>'secondary_position')),''),
    nullif(trim(p_payload->>'gender'),''),nullif(trim(p_payload->>'state'),''),
    nullif(trim(p_payload->>'experience_level'),''),v_status,
    CASE WHEN v_status='Free Agent' THEN NULL ELSE nullif(trim(p_payload->>'club_name'),'') END,
    v_guardian_name,v_guardian_email,v_guardian_phone
  )
  ON CONFLICT(profile_id) DO UPDATE SET
    full_name=CASE WHEN public.players.verification_status='verified' THEN public.players.full_name ELSE excluded.full_name END,
    preferred_name=excluded.preferred_name,
    nickname=excluded.nickname,
    date_of_birth=excluded.date_of_birth,
    position=excluded.position,
    preferred_foot=coalesce(excluded.preferred_foot,public.players.preferred_foot),
    dominant_foot=coalesce(excluded.dominant_foot,public.players.dominant_foot),
    jersey_number=coalesce(excluded.jersey_number,public.players.jersey_number),
    preferred_jersey_no=coalesce(excluded.preferred_jersey_no,public.players.preferred_jersey_no),
    height_cm=coalesce(excluded.height_cm,public.players.height_cm),
    weight_kg=coalesce(excluded.weight_kg,public.players.weight_kg),
    nationality=coalesce(excluded.nationality,public.players.nationality),
    profile_visibility=excluded.profile_visibility,
    display_name_mode=excluded.display_name_mode,
    biography=coalesce(excluded.biography,public.players.biography),
    bio=coalesce(excluded.bio,public.players.bio),
    phone=coalesce(excluded.phone,public.players.phone),
    best_position=excluded.best_position,
    secondary_position=excluded.secondary_position,
    gender=excluded.gender,state=excluded.state,experience_level=excluded.experience_level,
    player_status=excluded.player_status,current_club_name=excluded.current_club_name,
    guardian_name=excluded.guardian_name,guardian_email=excluded.guardian_email,guardian_phone=excluded.guardian_phone,
    kyc_status=CASE WHEN public.players.verification_status='verified' THEN public.players.kyc_status ELSE excluded.kyc_status END,
    passport_number=coalesce(public.players.passport_number,public.players.football_passport_no),
    is_free_agent=excluded.is_free_agent,
    profile_completed_at=now(),updated_at=now()
  RETURNING * INTO v_player;

  INSERT INTO public.profile_role_profiles(profile_id,role_code,subject_id,is_active)
  VALUES(v_uid,'player',v_player.id,true)
  ON CONFLICT(profile_id,role_code) DO UPDATE SET subject_id=EXCLUDED.subject_id,is_active=true,updated_at=now();

  INSERT INTO public.player_attribute_state(player_id)
  VALUES(v_player.id) ON CONFLICT(player_id) DO NOTHING;

  RETURN jsonb_build_object('ok',true,'player_id',v_player.id,'role_code','player',
    'football_passport_no',v_player.football_passport_no,'verification_status',v_player.verification_status);
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_coach_onboarding_profile(p_profile_id uuid,p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_coach public.coaches%ROWTYPE;
  v_coach_id uuid;
  v_coach_code text;
  v_profile public.profiles%ROWTYPE;
  v_name text;
  v_preferred text;
  v_phone text;
  v_dob date;
  v_license text;
  v_license_no text;
  v_role text;
  v_height integer;
  v_weight numeric(5,1);
  v_years smallint;
  v_roles text[];
  v_ages text[];
  v_levels text[];
  v_quals text[];
BEGIN
  PERFORM public.playpro_require_active_account();
  IF auth.uid() IS NULL OR auth.uid()<>p_profile_id THEN
    RAISE EXCEPTION 'UNAUTHORIZED' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_profile FROM public.profiles WHERE id=p_profile_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE='P0002'; END IF;

  SELECT * INTO v_coach FROM public.coaches
   WHERE profile_id=p_profile_id AND is_active=true FOR UPDATE;

  v_name := coalesce(nullif(btrim(p_payload->>'full_name'),''),v_profile.full_name);
  v_preferred := nullif(btrim(p_payload->>'preferred_name'),'');
  v_phone := nullif(btrim(p_payload->>'phone'),'');
  v_license := nullif(btrim(p_payload->>'license_type'),'');
  v_license_no := nullif(btrim(p_payload->>'license_number'),'');
  v_role := coalesce(nullif(btrim(p_payload->>'coaching_role'),''),'head_coach');

  v_height := nullif(p_payload->>'height_cm','')::integer;
  v_weight := nullif(p_payload->>'weight_kg','')::numeric;
  v_years := nullif(p_payload->>'years_experience','')::smallint;
  SELECT coalesce(array_agg(value),'{}'::text[]) INTO v_roles FROM jsonb_array_elements_text(coalesce(p_payload->'coaching_roles','[]'::jsonb)) AS t(value);
  SELECT coalesce(array_agg(value),'{}'::text[]) INTO v_ages FROM jsonb_array_elements_text(coalesce(p_payload->'age_groups','[]'::jsonb)) AS t(value);
  SELECT coalesce(array_agg(value),'{}'::text[]) INTO v_levels FROM jsonb_array_elements_text(coalesce(p_payload->'club_categories','[]'::jsonb)) AS t(value);
  SELECT coalesce(array_agg(value),'{}'::text[]) INTO v_quals FROM jsonb_array_elements_text(coalesce(p_payload->'qualification_types','[]'::jsonb)) AS t(value);

  IF v_name IS NULL OR btrim(v_name)='' THEN RAISE EXCEPTION 'Nama akaun diperlukan' USING ERRCODE='22023'; END IF;
  IF cardinality(v_roles)=0 OR cardinality(v_ages)=0 OR cardinality(v_levels)=0 OR cardinality(v_quals)=0 THEN
    RAISE EXCEPTION 'Lengkapkan fokus dan kelayakan kejurulatihan' USING ERRCODE='22023';
  END IF;
  IF v_height IS NOT NULL AND v_height NOT BETWEEN 100 AND 250 THEN RAISE EXCEPTION 'Tinggi tidak sah' USING ERRCODE='22023'; END IF;
  IF v_weight IS NOT NULL AND v_weight NOT BETWEEN 25 AND 300 THEN RAISE EXCEPTION 'Berat tidak sah' USING ERRCODE='22023'; END IF;
  IF v_years IS NOT NULL AND v_years NOT BETWEEN 0 AND 70 THEN RAISE EXCEPTION 'Tempoh pengalaman tidak sah' USING ERRCODE='22023'; END IF;

  IF v_coach.id IS NOT NULL THEN
    IF v_coach.verification_status='verified' OR v_coach.legal_name_locked_at IS NOT NULL THEN
      v_name := v_coach.full_name;
      v_dob := v_coach.date_of_birth;
    ELSE
      v_dob := coalesce(nullif(p_payload->>'date_of_birth','')::date,v_coach.date_of_birth);
    END IF;
    v_coach_code := v_coach.coach_code;
  ELSE
    v_dob := nullif(p_payload->>'date_of_birth','')::date;
    LOOP
      v_coach_code := 'COA-' || upper(substr(replace(pg_catalog.gen_random_uuid()::text,'-',''),1,10));
      EXIT WHEN NOT EXISTS(SELECT 1 FROM public.coaches c WHERE c.coach_code=v_coach_code);
    END LOOP;
  END IF;

  UPDATE public.profiles SET phone=coalesce(v_phone,phone),updated_at=now() WHERE id=p_profile_id;

  INSERT INTO public.coaches(
    profile_id,coach_code,full_name,preferred_name,phone,date_of_birth,
    license,license_type,license_number,license_issuing_body,coaching_role,
    preferred_formation,preferred_style,coaching_specialties,photo_url,
    verification_status,profile_completed_at,updated_at,
    gender,height_cm,weight_kg,state,experience_level,years_experience,
    coaching_roles,age_groups,club_categories,qualification_types,other_certificate
  ) VALUES (
    p_profile_id,v_coach_code,v_name,v_preferred,v_phone,v_dob,
    v_license,v_license,v_license_no,nullif(btrim(p_payload->>'license_issuing_body'),''),v_role,
    nullif(btrim(p_payload->>'preferred_formation'),''),nullif(btrim(p_payload->>'preferred_style'),''),
    jsonb_build_object('roles',to_jsonb(v_roles),'age_groups',to_jsonb(v_ages),'club_categories',to_jsonb(v_levels),'qualifications',to_jsonb(v_quals)),
    nullif(btrim(p_payload->>'photo_url'),''),
    CASE WHEN v_coach.verification_status='verified' THEN 'verified' ELSE 'unverified' END,
    CASE WHEN v_coach.verification_status='verified' THEN coalesce(v_coach.profile_completed_at,now()) ELSE NULL END,
    now(),
    nullif(btrim(p_payload->>'gender'),''),v_height,v_weight,nullif(btrim(p_payload->>'state'),''),
    nullif(btrim(p_payload->>'experience_level'),''),v_years,
    v_roles,v_ages,v_levels,v_quals,nullif(btrim(p_payload->>'other_certificate'),'')
  )
  ON CONFLICT(profile_id) DO UPDATE SET
    full_name=CASE WHEN public.coaches.legal_name_locked_at IS NOT NULL OR public.coaches.verification_status='verified' THEN public.coaches.full_name ELSE excluded.full_name END,
    preferred_name=excluded.preferred_name,phone=coalesce(excluded.phone,public.coaches.phone),
    date_of_birth=CASE WHEN public.coaches.legal_name_locked_at IS NOT NULL OR public.coaches.verification_status='verified' THEN public.coaches.date_of_birth ELSE coalesce(excluded.date_of_birth,public.coaches.date_of_birth) END,
    license=excluded.license,license_type=excluded.license_type,license_number=excluded.license_number,
    license_issuing_body=excluded.license_issuing_body,coaching_role=excluded.coaching_role,
    preferred_formation=excluded.preferred_formation,preferred_style=excluded.preferred_style,
    coaching_specialties=excluded.coaching_specialties,photo_url=excluded.photo_url,
    verification_status=public.coaches.verification_status,
    profile_completed_at=CASE WHEN public.coaches.verification_status='verified' THEN coalesce(public.coaches.profile_completed_at,now()) ELSE NULL END,
    gender=excluded.gender,height_cm=excluded.height_cm,weight_kg=excluded.weight_kg,state=excluded.state,
    experience_level=excluded.experience_level,years_experience=excluded.years_experience,
    coaching_roles=excluded.coaching_roles,age_groups=excluded.age_groups,club_categories=excluded.club_categories,
    qualification_types=excluded.qualification_types,other_certificate=excluded.other_certificate,updated_at=now()
  RETURNING id INTO v_coach_id;

  INSERT INTO public.profile_role_profiles(profile_id,role_code,subject_id,is_active)
  VALUES(p_profile_id,'coach',v_coach_id,true)
  ON CONFLICT(profile_id,role_code) DO UPDATE SET subject_id=excluded.subject_id,is_active=true,updated_at=now();
  INSERT INTO public.coach_attribute_state(coach_id) VALUES(v_coach_id) ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('success',true,'reason','COACH_PROFILE_SAVED','coach_id',v_coach_id,
    'verification_status',(SELECT c.verification_status FROM public.coaches c WHERE c.id=v_coach_id),
    'kyc_required',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_my_referee_onboarding(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_referee_id uuid;
  v_phone text;
  v_issuers text[];
  v_quals text[];
  v_experience text[];
  v_matches text[];
  v_dob date;
  v_years smallint;
  v_license_type text;
BEGIN
  PERFORM public.playpro_require_active_account();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;

  v_phone := nullif(trim(concat_ws(' ',p_payload->>'phone_code',p_payload->>'phone')),'');
  v_dob := nullif(p_payload->>'date_of_birth','')::date;
  v_years := nullif(p_payload->>'years_experience','')::smallint;
  SELECT coalesce(array_agg(value),'{}'::text[]) INTO v_issuers FROM jsonb_array_elements_text(coalesce(p_payload->'license_issuers','[]'::jsonb)) AS t(value);
  SELECT coalesce(array_agg(value),'{}'::text[]) INTO v_quals FROM jsonb_array_elements_text(coalesce(p_payload->'qualification_types','[]'::jsonb)) AS t(value);
  SELECT coalesce(array_agg(value),'{}'::text[]) INTO v_experience FROM jsonb_array_elements_text(coalesce(p_payload->'experience_types','[]'::jsonb)) AS t(value);
  SELECT coalesce(array_agg(value),'{}'::text[]) INTO v_matches FROM jsonb_array_elements_text(coalesce(p_payload->'match_types','[]'::jsonb)) AS t(value);
  IF v_dob IS NULL OR v_dob>CURRENT_DATE THEN RAISE EXCEPTION 'Tarikh lahir tidak sah' USING ERRCODE='22023'; END IF;
  IF cardinality(v_experience)=0 OR cardinality(v_matches)=0 THEN RAISE EXCEPTION 'Pilih pengalaman dan jenis perlawanan' USING ERRCODE='22023'; END IF;
  IF coalesce(p_payload->>'license_status','none')='licensed' AND (cardinality(v_issuers)=0 OR cardinality(v_quals)=0 OR nullif(trim(p_payload->>'license_number'),'') IS NULL) THEN
    RAISE EXCEPTION 'Maklumat lesen tidak lengkap' USING ERRCODE='22023';
  END IF;

  PERFORM public.create_referee_profile(
    nullif(trim(p_payload->>'pitch_nickname'),''),
    CASE WHEN cardinality(v_quals)>0 THEN array_to_string(v_quals,', ') ELSE 'none' END,
    nullif(trim(p_payload->>'state'),''),
    v_phone
  );
  SELECT id INTO v_referee_id FROM public.referees WHERE user_id=v_uid LIMIT 1;
  IF v_referee_id IS NULL THEN RAISE EXCEPTION 'REFEREE_PROFILE_NOT_CREATED' USING ERRCODE='P0002'; END IF;

  UPDATE public.referees SET
    date_of_birth=v_dob,phone=v_phone,gender=nullif(trim(p_payload->>'gender'),''),
    state=nullif(trim(p_payload->>'state'),''),years_experience=v_years,
    license_status=CASE WHEN p_payload->>'license_status'='licensed' THEN 'licensed' ELSE 'none' END,
    license_grade=nullif(trim(p_payload->>'license_grade'),''),
    license_issuers=v_issuers,qualification_types=v_quals,experience_types=v_experience,
    match_types=v_matches,license_type=CASE WHEN cardinality(v_quals)>0 THEN array_to_string(v_quals,', ') ELSE NULL END,
    updated_at=now()
  WHERE id=v_referee_id AND user_id=v_uid;

  RETURN jsonb_build_object('success',true,'referee_id',v_referee_id,'role_code','referee',
    'verification_status',(SELECT r.verification_status FROM public.referees r WHERE r.id=v_referee_id),
    'license_status',(SELECT r.license_status FROM public.referees r WHERE r.id=v_referee_id));
END;
$function$;

REVOKE ALL ON FUNCTION public.save_my_referee_onboarding(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_my_referee_onboarding(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_my_organizer_onboarding(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_profile public.profiles%ROWTYPE;
  v_id uuid;
  v_types text[];
  v_type text;
  v_name text;
  v_mode text;
BEGIN
  PERFORM public.playpro_require_active_account();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_profile FROM public.profiles WHERE id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE='P0002'; END IF;

  SELECT coalesce(array_agg(value),'{}'::text[]) INTO v_types
  FROM jsonb_array_elements_text(coalesce(p_payload->'organizer_types','[]'::jsonb)) AS t(value);
  IF cardinality(v_types)=0 THEN RAISE EXCEPTION 'Pilih sekurang-kurangnya satu jenis Organizer' USING ERRCODE='22023'; END IF;
  v_mode := CASE WHEN p_payload->>'name_mode'='commercial' THEN 'commercial' ELSE 'account' END;
  v_name := CASE WHEN v_mode='commercial' THEN nullif(trim(p_payload->>'commercial_name_ms'),'') ELSE v_profile.full_name END;
  IF v_name IS NULL OR btrim(v_name)='' THEN RAISE EXCEPTION 'Nama paparan Organizer diperlukan' USING ERRCODE='22023'; END IF;
  v_type := array_to_string(v_types,', ');

  SELECT id INTO v_id FROM public.organizers WHERE profile_id=v_uid FOR UPDATE;
  IF v_id IS NULL THEN
    INSERT INTO public.organizers(profile_id,organizer_code,organizer_type,display_name,description,phone,whatsapp,email,city,state,country,profile_visibility,verification_status,profile_completed_at,organizer_types,commercial_name_en,name_mode,district,base_address)
    VALUES(v_uid,'ORG-'||upper(substr(replace(pg_catalog.gen_random_uuid()::text,'-',''),1,10)),v_type,v_name,
      nullif(trim(p_payload->>'description'),''),nullif(trim(concat_ws(' ',p_payload->>'phone_code',p_payload->>'phone')),''),
      nullif(trim(concat_ws(' ',p_payload->>'whatsapp_code',p_payload->>'whatsapp')),''),
      coalesce(nullif(trim(p_payload->>'email'),''),v_profile.email),nullif(trim(p_payload->>'district'),''),
      nullif(trim(p_payload->>'state'),''),'Malaysia','public','pending',now(),v_types,
      nullif(trim(p_payload->>'commercial_name_en'),''),v_mode,
      nullif(trim(p_payload->>'district'),''),nullif(trim(p_payload->>'base_address'),''))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.organizers SET
      organizer_type=v_type,organizer_types=v_types,display_name=v_name,
      commercial_name_en=nullif(trim(p_payload->>'commercial_name_en'),''),
      name_mode=v_mode,phone=coalesce(nullif(trim(concat_ws(' ',p_payload->>'phone_code',p_payload->>'phone')),''),phone),
      whatsapp=nullif(trim(concat_ws(' ',p_payload->>'whatsapp_code',p_payload->>'whatsapp')),''),
      email=coalesce(nullif(trim(p_payload->>'email'),''),v_profile.email),
      city=nullif(trim(p_payload->>'district'),''),district=nullif(trim(p_payload->>'district'),''),
      state=nullif(trim(p_payload->>'state'),''),base_address=nullif(trim(p_payload->>'base_address'),''),
      profile_completed_at=now(),updated_at=now()
    WHERE id=v_id AND profile_id=v_uid;
  END IF;

  INSERT INTO public.profile_role_profiles(profile_id,role_code,subject_id,is_active)
  VALUES(v_uid,'organizer',v_id,true)
  ON CONFLICT(profile_id,role_code) DO UPDATE SET subject_id=excluded.subject_id,is_active=true,updated_at=now();

  RETURN jsonb_build_object('success',true,'organizer_id',v_id,'role_code','organizer',
    'verification_status',(SELECT o.verification_status FROM public.organizers o WHERE o.id=v_id),
    'capability_ready',false);
END;
$function$;

REVOKE ALL ON FUNCTION public.save_my_organizer_onboarding(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_my_organizer_onboarding(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_playpro_club(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_club_id uuid;
  v_name text := nullif(trim(p_payload->>'name'),'');
  v_type text := nullif(trim(p_payload->>'club_type'),'');
  v_categories text[];
  v_slug text;
  v_code text;
  v_year integer;
BEGIN
  PERFORM public.playpro_require_active_account();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan.' USING ERRCODE='42501'; END IF;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Nama kelab wajib diisi.' USING ERRCODE='22023'; END IF;

  SELECT coalesce(array_agg(value),'{}'::text[]) INTO v_categories
  FROM jsonb_array_elements_text(coalesce(p_payload->'club_categories','[]'::jsonb)) AS t(value);
  IF cardinality(v_categories)>0 THEN v_type := v_categories[1]; END IF;
  IF v_type IS NULL OR NOT EXISTS(SELECT 1 FROM public.club_type_catalog WHERE code=v_type AND active) THEN
    RAISE EXCEPTION 'Jenis kelab tidak sah.' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(v_categories) c LEFT JOIN public.club_type_catalog t ON t.code=c AND t.active WHERE t.code IS NULL) THEN
    RAISE EXCEPTION 'Kategori kelab tidak sah.' USING ERRCODE='22023';
  END IF;

  v_year := nullif(p_payload->>'year_founded','')::integer;
  IF v_year IS NOT NULL AND v_year NOT BETWEEN 1800 AND extract(year FROM CURRENT_DATE)::integer THEN
    RAISE EXCEPTION 'Tahun penubuhan tidak sah' USING ERRCODE='22023';
  END IF;

  v_club_id := pg_catalog.gen_random_uuid();
  v_code := 'PP-CLB-' || lpad(nextval('public.club_code_seq')::text,6,'0');
  v_slug := lower(regexp_replace(v_name,'[^a-zA-Z0-9]+','-','g')) || '-' || substring(v_club_id::text,1,8);

  INSERT INTO public.clubs(
    id,name,logo_url,year_founded,home_venue,colours,admin_id,owner_profile_id,club_code,slug,
    club_type,description,ros_registration_no,contact_phone,whatsapp_phone,city,state,country,
    verification_status,visibility,created_at,updated_at,club_categories,mailing_address,district,postcode
  ) VALUES (
    v_club_id,v_name,nullif(trim(p_payload->>'logo_url'),''),v_year,null,null,v_uid,v_uid,v_code,v_slug,
    v_type,nullif(trim(p_payload->>'description'),''),nullif(trim(p_payload->>'ros_registration_no'),''),
    nullif(trim(p_payload->>'contact_phone'),''),null,
    nullif(trim(p_payload->>'district'),''),nullif(trim(p_payload->>'state'),''),
    coalesce(nullif(trim(p_payload->>'country'),''),'Malaysia'),'pending',
    CASE WHEN p_payload->>'visibility'='private' THEN 'private' ELSE 'public' END,now(),now(),
    v_categories,nullif(trim(p_payload->>'mailing_address'),''),
    nullif(trim(p_payload->>'district'),''),nullif(trim(p_payload->>'postcode'),'')
  );

  INSERT INTO public.club_memberships(club_id,profile_id,role_code,status,created_by)
  VALUES(v_club_id,v_uid,'owner','active',v_uid);
  INSERT INTO public.profile_role_profiles(profile_id,role_code,subject_id,is_active,created_at,updated_at)
  VALUES(v_uid,'club_owner',v_club_id,true,now(),now())
  ON CONFLICT(profile_id,role_code) DO UPDATE SET subject_id=excluded.subject_id,is_active=true,updated_at=now();

  RETURN jsonb_build_object('success',true,'club_id',v_club_id,'club_code',v_code,'slug',v_slug,'verification_status','pending');
END;
$function$;

REVOKE ALL ON FUNCTION public.register_my_player(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_my_player(jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.save_coach_onboarding_profile(uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_coach_onboarding_profile(uuid,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.create_playpro_club(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_playpro_club(jsonb) TO authenticated;

COMMENT ON FUNCTION public.save_my_referee_onboarding(jsonb) IS
  'Authenticated owner-only referee onboarding. License review and official referee authority remain separately gated.';
COMMENT ON FUNCTION public.save_my_organizer_onboarding(jsonb) IS
  'Authenticated owner-only organizer onboarding. Verification is pending until the approved verification workflow completes.';
