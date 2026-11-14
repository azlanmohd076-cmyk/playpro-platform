
-- New Coach profiles must not look KYC-pending before a KYC request exists.
do $migration$
declare
  v_def text;
  v_old text := 'case when v_coach.verification_status=''verified'' then ''verified'' else ''pending'' end';
  v_new text := 'case when v_coach.verification_status=''verified'' then ''verified'' else ''unverified'' end';
begin
  select pg_get_functiondef('public.save_coach_onboarding_profile(uuid,jsonb)'::regprocedure) into v_def;
  if position(v_old in v_def)=0 then
    raise exception 'Expected initial Coach verification status expression was not found';
  end if;
  execute replace(v_def,v_old,v_new);
end;
$migration$;

create or replace function public.request_coach_kyc(
  p_id_type text,
  p_legal_name text,
  p_birth_state_code text default null,
  p_masked_identifier text default null,
  p_provider_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public','pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_coach public.coaches%rowtype;
  v_id uuid;
  v_status text;
begin
  perform public.playpro_require_active_account();
  if v_uid is null then raise exception 'UNAUTHORIZED' using errcode='42501'; end if;

  select * into v_coach
  from public.coaches
  where profile_id=v_uid and is_active=true
  for update;
  if not found then raise exception 'Coach profile not found' using errcode='P0002'; end if;

  if v_coach.verification_status='verified' or v_coach.kyc_verified_at is not null then
    raise exception 'COACH_KYC_ALREADY_VERIFIED' using errcode='40901';
  end if;

  if lower(trim(coalesce(p_id_type,''))) not in ('mykad','mykid','passport') then
    raise exception 'Unsupported identity document type' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_legal_name,'')),'') is null then
    raise exception 'Legal name is required' using errcode='22023';
  end if;

  select id,status into v_id,v_status
  from public.identity_verifications
  where profile_id=v_uid and subject_type='coach' and status in ('pending','processing')
  order by submitted_at desc
  limit 1
  for update;

  if v_status='processing' then
    raise exception 'KYC_PROCESSING_IN_PROGRESS' using errcode='40901';
  end if;

  if v_id is null then
    insert into public.identity_verifications(
      profile_id,subject_type,id_type,legal_name_claimed,birth_state_code,masked_identifier,
      status,provider_reference,submitted_at,created_at,updated_at,document_storage_paths,
      provider,provider_status,match_status
    ) values (
      v_uid,'coach',lower(trim(p_id_type)),btrim(p_legal_name),
      nullif(btrim(coalesce(p_birth_state_code,'')),''),
      nullif(btrim(coalesce(p_masked_identifier,'')),''),
      'pending',p_provider_reference,now(),now(),now(),'[]'::jsonb,
      'google_document_ai','queued','not_processed'
    ) returning id into v_id;
  else
    update public.identity_verifications
    set id_type=lower(trim(p_id_type)),
        legal_name_claimed=btrim(p_legal_name),
        birth_state_code=nullif(btrim(coalesce(p_birth_state_code,'')),''),
        masked_identifier=nullif(btrim(coalesce(p_masked_identifier,'')),''),
        provider_reference=p_provider_reference,
        document_storage_paths='[]'::jsonb,
        provider='google_document_ai',
        provider_status='queued',
        match_status='not_processed',
        match_score=null,
        extracted_legal_name=null,
        extracted_birth_date=null,
        extracted_id_type=null,
        extracted_identifier_masked=null,
        processed_at=null,
        submitted_at=now(),
        updated_at=now()
    where id=v_id;
  end if;

  update public.coaches set verification_status='pending',updated_at=now()
  where id=v_coach.id;

  return jsonb_build_object('success',true,'kyc_id',v_id,'status','pending','subject_type','coach');
end;
$function$;

create or replace function public.approve_coach_kyc(
  p_kyc_id uuid,
  p_reviewer_note text default null,
  p_verified_legal_name text default null,
  p_verified_birth_date date default null,
  p_verified_birth_state_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public','pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_k public.identity_verifications%rowtype;
  v_coach public.coaches%rowtype;
  v_name text;
  v_dob date;
  v_state text;
begin
  perform public.playpro_require_active_account();
  if v_uid is null or not public.is_league_founder_or_developer() then
    raise exception 'KYC approval requires PlayPro privileged access' using errcode='42501';
  end if;

  select * into v_k from public.identity_verifications
  where id=p_kyc_id and subject_type='coach' for update;
  if not found then raise exception 'Coach KYC request not found' using errcode='P0002'; end if;

  if not exists(select 1 from public.profiles p where p.id=v_k.profile_id and p.is_active=true) then
    raise exception 'ACCOUNT_DISABLED_OR_INACTIVE' using errcode='42501';
  end if;

  select * into v_coach from public.coaches
  where profile_id=v_k.profile_id and is_active=true for update;
  if not found then raise exception 'Coach profile not found' using errcode='P0002'; end if;

  if v_k.status='verified' then
    return jsonb_build_object('ok',true,'status','verified','coach_id',v_coach.id,'coach_code',v_coach.coach_code);
  end if;
  if v_k.status <> 'pending' then
    raise exception 'KYC request is not awaiting approval' using errcode='40901';
  end if;

  if jsonb_typeof(v_k.document_storage_paths) is distinct from 'array' then
    raise exception 'KYC_DOCUMENTS_REQUIRED' using errcode='22023';
  end if;
  if jsonb_array_length(v_k.document_storage_paths) not between 1 and 2 then
    raise exception 'KYC_DOCUMENTS_REQUIRED' using errcode='22023';
  end if;
  if coalesce(v_k.match_status,'not_processed') <> 'match'
     and nullif(btrim(coalesce(p_reviewer_note,'')),'') is null then
    raise exception 'KYC_REVIEW_NOTE_REQUIRED_FOR_NON_MATCH' using errcode='22023';
  end if;

  v_name := nullif(btrim(coalesce(p_verified_legal_name,v_k.extracted_legal_name,v_k.legal_name_claimed)), '');
  if v_name is null then raise exception 'Verified legal name is required' using errcode='22023'; end if;

  -- Reviewer-confirmed DOB takes precedence over OCR extraction.
  v_dob := coalesce(p_verified_birth_date,v_k.extracted_birth_date,v_coach.date_of_birth);
  v_state := coalesce(nullif(btrim(p_verified_birth_state_code),''),nullif(btrim(v_k.birth_state_code),''));

  perform set_config('playpro.kyc_approval','true',true);

  update public.coaches
  set full_name=v_name,
      date_of_birth=v_dob,
      verification_status='verified',
      kyc_verified_at=now(),
      legal_name_locked_at=now(),
      verified_at=now(),
      verified_by=v_uid,
      profile_completed_at=coalesce(profile_completed_at,now()),
      updated_at=now()
  where id=v_coach.id;

  update public.profiles set full_name=v_name,updated_at=now()
  where id=v_coach.profile_id;

  update public.identity_verifications
  set status='verified',
      reviewer_profile_id=v_uid,
      reviewer_note=p_reviewer_note,
      reviewed_at=now(),
      provider_status=coalesce(provider_status,'processed'),
      extracted_legal_name=coalesce(extracted_legal_name,v_name),
      extracted_birth_date=coalesce(extracted_birth_date,v_dob),
      updated_at=now()
  where id=v_k.id;

  return jsonb_build_object('ok',true,'status','verified','coach_id',v_coach.id,
    'coach_code',v_coach.coach_code,'legal_name_locked',true,'birth_state_code',v_state);
end;
$function$;

-- Disabled accounts cannot read or upload private Coach/KYC records through old JWTs.
drop policy if exists coaches_owner_or_club_admin_read on public.coaches;
create policy coaches_owner_or_club_admin_read
on public.coaches for select to authenticated
using (
  public.playpro_account_is_active()
  and (
    profile_id=(select auth.uid())
    or (select public.get_my_role())='developer'::public.user_role
    or (club_id is not null and public.is_club_admin(club_id))
  )
);

drop policy if exists coach_accreditations_read_own_or_developer on public.coach_accreditations;
create policy coach_accreditations_read_own_or_developer
on public.coach_accreditations for select to authenticated
using (
  public.playpro_account_is_active()
  and (
    coach_profile_id=(select auth.uid())
    or (select public.get_my_role())='developer'::public.user_role
  )
);

drop policy if exists coach_certification_courses_owner_read on public.coach_certification_courses;
create policy coach_certification_courses_owner_read
on public.coach_certification_courses for select to authenticated
using (
  public.playpro_account_is_active()
  and exists(select 1 from public.coaches c
    where c.id=coach_certification_courses.coach_id and c.profile_id=(select auth.uid()))
);

drop policy if exists coach_cert_requests_owner_read on public.coach_certification_requests;
drop policy if exists coach_certification_requests_owner_read on public.coach_certification_requests;
create policy coach_certification_requests_owner_read
on public.coach_certification_requests for select to authenticated
using (
  public.playpro_account_is_active()
  and exists(select 1 from public.coaches c
    where c.id=coach_certification_requests.coach_id and c.profile_id=(select auth.uid()))
);

drop policy if exists "identity verification owner read" on public.identity_verifications;
create policy "identity verification owner read"
on public.identity_verifications for select to authenticated
using (profile_id=(select auth.uid()) and public.playpro_account_is_active());

drop policy if exists "coach kyc read own document" on storage.objects;
create policy "coach kyc read own document"
on storage.objects for select to authenticated
using (
  bucket_id='kyc-documents'
  and owner_id=(select (auth.uid())::text)
  and public.playpro_account_is_active()
  and exists(select 1 from public.coaches c
    where c.profile_id=(select auth.uid()) and c.is_active=true)
);

drop policy if exists "coach kyc upload own document" on storage.objects;
create policy "coach kyc upload own document"
on storage.objects for insert to authenticated
with check (
  bucket_id='kyc-documents'
  and (storage.foldername(name))[1]=(select (auth.uid())::text)
  and public.playpro_account_is_active()
  and exists(select 1 from public.coaches c
    where c.profile_id=(select auth.uid()) and c.is_active=true)
);
