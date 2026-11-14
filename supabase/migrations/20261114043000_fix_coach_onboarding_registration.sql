-- Fix Coach onboarding: coaches.coach_code is NOT NULL and has no default.
-- Generate a unique public Coach code server-side so the onboarding RPC can insert a profile.

create or replace function public.save_coach_onboarding_profile(
  p_profile_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_coach public.coaches%rowtype;
  v_coach_id uuid;
  v_coach_code text;
  v_name text;
  v_preferred text;
  v_phone text;
  v_dob date;
  v_license text;
  v_license_no text;
  v_role text;
begin
  if auth.uid() is null or auth.uid() <> p_profile_id then
    raise exception 'UNAUTHORIZED' using errcode='42501';
  end if;

  select *
    into v_coach
    from public.coaches
   where profile_id=p_profile_id and is_active=true
   for update;

  v_name := nullif(btrim(p_payload->>'full_name'),'');
  v_preferred := nullif(btrim(p_payload->>'preferred_name'),'');
  v_phone := nullif(btrim(p_payload->>'phone'),'');
  v_license := nullif(btrim(p_payload->>'license_type'),'');
  v_license_no := nullif(btrim(p_payload->>'license_number'),'');
  v_role := coalesce(nullif(btrim(p_payload->>'coaching_role'),''),'head_coach');

  if v_name is null or v_phone is null then
    return jsonb_build_object(
      'success',false,
      'reason','REQUIRED_FIELDS_MISSING',
      'message','Nama dan nombor telefon diperlukan.'
    );
  end if;

  if v_coach.id is not null then
    if v_coach.verification_status='verified' or v_coach.legal_name_locked_at is not null then
      v_name := v_coach.full_name;
      v_dob := v_coach.date_of_birth;
    else
      v_dob := v_coach.date_of_birth;
      if nullif(p_payload->>'date_of_birth','') is not null then
        v_dob := (p_payload->>'date_of_birth')::date;
      end if;
    end if;
    v_coach_code := v_coach.coach_code;
  else
    if nullif(p_payload->>'date_of_birth','') is not null then
      v_dob := (p_payload->>'date_of_birth')::date;
    end if;

    -- coaches.coach_code is unique, required, and has no column default.
    loop
      v_coach_code := 'COA-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
      exit when not exists (
        select 1 from public.coaches c where c.coach_code=v_coach_code
      );
    end loop;
  end if;

  update public.profiles
     set phone=v_phone, updated_at=now()
   where id=p_profile_id;

  insert into public.coaches (
    profile_id,coach_code,full_name,preferred_name,phone,date_of_birth,
    license,license_type,license_number,license_issuing_body,coaching_role,
    preferred_formation,preferred_style,coaching_specialties,photo_url,
    verification_status,profile_completed_at,updated_at
  ) values (
    p_profile_id,v_coach_code,v_name,v_preferred,v_phone,v_dob,
    v_license,v_license,v_license_no,
    nullif(btrim(p_payload->>'license_issuing_body'),''),
    v_role,
    nullif(btrim(p_payload->>'preferred_formation'),''),
    nullif(btrim(p_payload->>'preferred_style'),''),
    coalesce(p_payload->'coaching_specialties','[]'::jsonb),
    nullif(btrim(p_payload->>'photo_url'),''),
    case when v_coach.verification_status='verified' then 'verified' else 'pending' end,
    case when v_coach.verification_status='verified' then coalesce(v_coach.profile_completed_at,now()) else null end,
    now()
  )
  on conflict (profile_id) do update set
    full_name=case
      when public.coaches.legal_name_locked_at is not null or public.coaches.verification_status='verified'
      then public.coaches.full_name else excluded.full_name end,
    preferred_name=excluded.preferred_name,
    phone=excluded.phone,
    date_of_birth=case
      when public.coaches.legal_name_locked_at is not null or public.coaches.verification_status='verified'
      then public.coaches.date_of_birth else coalesce(excluded.date_of_birth,public.coaches.date_of_birth) end,
    license=excluded.license,
    license_type=excluded.license_type,
    license_number=excluded.license_number,
    license_issuing_body=excluded.license_issuing_body,
    coaching_role=excluded.coaching_role,
    preferred_formation=excluded.preferred_formation,
    preferred_style=excluded.preferred_style,
    coaching_specialties=excluded.coaching_specialties,
    photo_url=excluded.photo_url,
    verification_status=public.coaches.verification_status,
    profile_completed_at=case
      when public.coaches.verification_status='verified'
      then coalesce(public.coaches.profile_completed_at,now()) else null end,
    updated_at=now()
  returning id into v_coach_id;

  insert into public.profile_role_profiles(profile_id,role_code,subject_id,is_active)
  values(p_profile_id,'coach',v_coach_id,true)
  on conflict(profile_id,role_code) do update
    set subject_id=excluded.subject_id,is_active=true,updated_at=now();

  insert into public.coach_attribute_state(coach_id)
  values(v_coach_id)
  on conflict do nothing;

  return jsonb_build_object(
    'success',true,
    'reason','COACH_PROFILE_SAVED',
    'coach_id',v_coach_id,
    'coach_code',(select c.coach_code from public.coaches c where c.id=v_coach_id),
    'kyc_required',true,
    'verification_status',(select c.verification_status from public.coaches c where c.id=v_coach_id),
    'legal_name_locked',(select c.legal_name_locked_at is not null from public.coaches c where c.id=v_coach_id)
  );
end;
$function$;
