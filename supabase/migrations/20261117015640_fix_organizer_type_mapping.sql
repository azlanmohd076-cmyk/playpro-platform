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
