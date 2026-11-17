CREATE TABLE IF NOT EXISTS private.club_onboarding_details (
  club_id uuid PRIMARY KEY REFERENCES public.clubs(id) ON DELETE CASCADE,
  owner_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  mailing_address text,
  postcode text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.club_onboarding_details ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.club_onboarding_details FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS private.organizer_onboarding_details (
  organizer_id uuid PRIMARY KEY REFERENCES public.organizers(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  base_address text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.organizer_onboarding_details ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.organizer_onboarding_details FROM PUBLIC, anon, authenticated;

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
    v_categories,NULL,
    nullif(trim(p_payload->>'district'),''),NULL
  );

  INSERT INTO public.club_memberships(club_id,profile_id,role_code,status,created_by)
  VALUES(v_club_id,v_uid,'owner','active',v_uid);
  INSERT INTO public.profile_role_profiles(profile_id,role_code,subject_id,is_active,created_at,updated_at)
  VALUES(v_uid,'club_owner',v_club_id,true,now(),now())
  ON CONFLICT(profile_id,role_code) DO UPDATE SET subject_id=excluded.subject_id,is_active=true,updated_at=now();

  RETURN jsonb_build_object('success',true,'club_id',v_club_id,'club_code',v_code,'slug',v_slug,'verification_status','pending');
END;
$function$;

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
  v_type := v_types[1];
  IF EXISTS (
    SELECT 1 FROM unnest(v_types) t(value)
    WHERE value NOT IN ('individual','club','academy','school','university','company','ngo','association','government','community','other')
  ) THEN
    RAISE EXCEPTION 'Jenis Organizer tidak sah' USING ERRCODE='22023';
  END IF;

  SELECT id INTO v_id FROM public.organizers WHERE profile_id=v_uid FOR UPDATE;
  IF v_id IS NULL THEN
    INSERT INTO public.organizers(profile_id,organizer_code,organizer_type,display_name,description,phone,whatsapp,email,city,state,country,profile_visibility,verification_status,profile_completed_at,organizer_types,commercial_name_en,name_mode,district,base_address)
    VALUES(v_uid,'ORG-'||upper(substr(replace(pg_catalog.gen_random_uuid()::text,'-',''),1,10)),v_type,v_name,
      nullif(trim(p_payload->>'description'),''),nullif(trim(concat_ws(' ',p_payload->>'phone_code',p_payload->>'phone')),''),
      nullif(trim(concat_ws(' ',p_payload->>'whatsapp_code',p_payload->>'whatsapp')),''),
      coalesce(nullif(trim(p_payload->>'email'),''),v_profile.email),nullif(trim(p_payload->>'district'),''),
      nullif(trim(p_payload->>'state'),''),'Malaysia','public','pending',now(),v_types,
      nullif(trim(p_payload->>'commercial_name_en'),''),v_mode,
      nullif(trim(p_payload->>'district'),''),NULL)
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.organizers SET
      organizer_type=v_type,organizer_types=v_types,display_name=v_name,
      commercial_name_en=nullif(trim(p_payload->>'commercial_name_en'),''),
      name_mode=v_mode,phone=coalesce(nullif(trim(concat_ws(' ',p_payload->>'phone_code',p_payload->>'phone')),''),phone),
      whatsapp=nullif(trim(concat_ws(' ',p_payload->>'whatsapp_code',p_payload->>'whatsapp')),''),
      email=coalesce(nullif(trim(p_payload->>'email'),''),v_profile.email),
      city=nullif(trim(p_payload->>'district'),''),district=nullif(trim(p_payload->>'district'),''),
      state=nullif(trim(p_payload->>'state'),''),base_address=NULL,
      profile_completed_at=now(),updated_at=now()
    WHERE id=v_id AND profile_id=v_uid;
  END IF;

  INSERT INTO private.organizer_onboarding_details(organizer_id,profile_id,base_address)
  VALUES(v_id,v_uid,nullif(trim(p_payload->>'base_address'),''))
  ON CONFLICT(organizer_id) DO UPDATE SET base_address=excluded.base_address,updated_at=now();

  INSERT INTO public.profile_role_profiles(profile_id,role_code,subject_id,is_active)
  VALUES(v_uid,'organizer',v_id,true)
  ON CONFLICT(profile_id,role_code) DO UPDATE SET subject_id=excluded.subject_id,is_active=true,updated_at=now();

  RETURN jsonb_build_object('success',true,'organizer_id',v_id,'role_code','organizer',
    'verification_status',(SELECT o.verification_status FROM public.organizers o WHERE o.id=v_id),
    'capability_ready',false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_my_club_onboarding(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_club jsonb;
  v_venue jsonb;
  v_club_id uuid;
BEGIN
  PERFORM public.playpro_require_active_account();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;

  v_club := public.create_playpro_club(p_payload);
  v_club_id := (v_club->>'club_id')::uuid;

  INSERT INTO private.club_onboarding_details(club_id,owner_profile_id,mailing_address,postcode)
  VALUES(v_club_id,v_uid,nullif(trim(p_payload->>'mailing_address'),''),nullif(trim(p_payload->>'postcode'),''))
  ON CONFLICT(club_id) DO UPDATE SET mailing_address=excluded.mailing_address,postcode=excluded.postcode,updated_at=now();

  IF nullif(trim(p_payload->>'ground_name'),'') IS NOT NULL THEN
    v_venue := public.save_club_training_venue(
      v_club_id,
      jsonb_build_object(
        'name',p_payload->>'ground_name',
        'address',p_payload->>'ground_address',
        'city',p_payload->>'district',
        'state',p_payload->>'state',
        'country',coalesce(nullif(trim(p_payload->>'country'),''),'Malaysia'),
        'google_maps_url',p_payload->>'map_url',
        'is_primary',true,
        'notes','Padang latihan utama yang dihantar melalui onboarding kelab'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success',true,
    'club_id',v_club_id,
    'club_code',v_club->>'club_code',
    'slug',v_club->>'slug',
    'verification_status',v_club->>'verification_status',
    'venue',v_venue
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_player_profile(p_player_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_player record;
  v_is_owner boolean := false;
  v_is_follower boolean := false;
  v_follow_status text;
  v_attrs jsonb;
  v_followers bigint;
  v_display_name text;
  v_public_player jsonb;
  v_owner_player jsonb;
begin
  if (select auth.uid()) is not null and not public.playpro_account_is_active() then
    raise exception 'ACCOUNT_DISABLED_OR_INACTIVE' using errcode='42501';
  end if;
  select p.id,p.profile_id,p.full_name,p.preferred_name,p.display_name_mode,p.bio,
    p.date_of_birth,p.position,p.preferred_foot,p.photo_url,p.club_id,p.jersey_number,
    p.nationality,p.height_cm,p.weight_kg,p.football_passport_no,p.profile_visibility,
    p.secondary_position,p.gender,p.state,p.experience_level,p.player_status,p.current_club_name,
    p.guardian_name,p.guardian_email,p.guardian_phone,
    p.verification_status,p.verified_at,p.dna_technical,p.dna_physical,p.dna_mental,
    p.dna_tactical,p.dna_overall,p.dna_band,p.is_demo,p.demo_level,
    c.name as club_name,c.logo_url as club_logo
  into v_player from public.players p left join public.clubs c on c.id=p.club_id
  where p.id=p_player_id and p.is_active=true;
  if not found then return jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND'); end if;

  v_is_owner := coalesce(v_player.profile_id=(select auth.uid()),false);
  select pf.status into v_follow_status from public.player_follows pf
  where pf.player_id=p_player_id and pf.follower_profile_id=(select auth.uid());
  v_is_follower := coalesce(v_follow_status='approved',false);
  select count(*) into v_followers from public.player_follows
  where player_id=p_player_id and status='approved';
  v_display_name := case when v_player.display_name_mode='legal' then v_player.full_name
    else coalesce(nullif(btrim(v_player.preferred_name),''),v_player.full_name) end;

  if not (v_is_owner or v_player.profile_visibility='public' or v_is_follower) then
    return jsonb_build_object('ok',true,'restricted',true,
      'player',jsonb_build_object('id',v_player.id,'preferred_name',v_display_name,
        'photo_url',v_player.photo_url,'position',v_player.position,
        'profile_visibility','private','follower_count',v_followers),
      'follow_status',coalesce(v_follow_status,'none'));
  end if;

  select to_jsonb(a)-'player_id'-'updated_at' into v_attrs
  from public.player_attribute_state a where a.player_id=p_player_id;
  v_public_player := jsonb_build_object(
    'id',v_player.id,'full_name',v_display_name,'preferred_name',v_display_name,
    'bio',v_player.bio,
    'age',case when v_player.date_of_birth is not null
      then extract(year from age(current_date,v_player.date_of_birth))::integer else null end,
    'position',v_player.position,'preferred_foot',v_player.preferred_foot,
    'photo_url',v_player.photo_url,'club_name',v_player.club_name,'club_logo',v_player.club_logo,
    'jersey_number',v_player.jersey_number,'nationality',v_player.nationality,
    'height_cm',v_player.height_cm,'weight_kg',v_player.weight_kg,
    'verification_status',v_player.verification_status,'verified_at',v_player.verified_at,
    'profile_visibility',v_player.profile_visibility,'follower_count',v_followers,
    'dna_technical',v_player.dna_technical,'dna_physical',v_player.dna_physical,
    'dna_mental',v_player.dna_mental,'dna_tactical',v_player.dna_tactical,
    'dna_overall',v_player.dna_overall,'dna_band',v_player.dna_band
  );
  if v_is_owner then
    v_owner_player := v_public_player || jsonb_build_object(
      'profile_id',v_player.profile_id,'raw_preferred_name',v_player.preferred_name,
      'display_name_mode',v_player.display_name_mode,'date_of_birth',v_player.date_of_birth,
      'football_passport_no',v_player.football_passport_no,'is_demo',v_player.is_demo,
      'demo_level',v_player.demo_level,'club_id',v_player.club_id,
      'secondary_position',v_player.secondary_position,'gender',v_player.gender,'state',v_player.state,
      'experience_level',v_player.experience_level,'player_status',v_player.player_status,
      'current_club_name',v_player.current_club_name,'guardian_name',v_player.guardian_name,
      'guardian_email',v_player.guardian_email,'guardian_phone',v_player.guardian_phone
    );
    return jsonb_build_object('ok',true,'restricted',false,'player',v_owner_player,
      'attributes',coalesce(v_attrs,'{}'::jsonb),'follow_status',coalesce(v_follow_status,'none'));
  end if;
  return jsonb_build_object('ok',true,'restricted',false,'player',v_public_player,
    'attributes',coalesce(v_attrs,'{}'::jsonb),'follow_status',coalesce(v_follow_status,'none'));
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_club_onboarding_private_details(p_club_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_result jsonb;
BEGIN
  PERFORM public.playpro_require_active_account();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('mailing_address',d.mailing_address,'postcode',d.postcode)
  INTO v_result
  FROM private.club_onboarding_details d
  WHERE d.club_id=p_club_id AND d.owner_profile_id=v_uid;
  IF v_result IS NULL THEN RAISE EXCEPTION 'CLUB_NOT_FOUND_OR_FORBIDDEN' USING ERRCODE='42501'; END IF;
  RETURN v_result;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_my_club_onboarding_private_details(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_club_onboarding_private_details(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_organizer_onboarding_private_details()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_result jsonb;
BEGIN
  PERFORM public.playpro_require_active_account();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('base_address',d.base_address)
  INTO v_result
  FROM private.organizer_onboarding_details d
  WHERE d.profile_id=v_uid;
  RETURN coalesce(v_result,'{}'::jsonb);
END;
$function$;
REVOKE ALL ON FUNCTION public.get_my_organizer_onboarding_private_details() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_organizer_onboarding_private_details() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_referee_profile()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_result jsonb;
BEGIN
  PERFORM public.playpro_require_active_account();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  SELECT to_jsonb(r) INTO v_result FROM public.referees r WHERE r.user_id=v_uid LIMIT 1;
  RETURN coalesce(v_result,'{}'::jsonb);
END;
$function$;
REVOKE ALL ON FUNCTION public.get_my_referee_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_referee_profile() TO authenticated;
