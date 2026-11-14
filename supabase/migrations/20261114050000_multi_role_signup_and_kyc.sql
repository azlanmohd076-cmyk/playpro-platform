-- Multi-role onboarding: correct signup role aliases and allow verified Club Owner KYC.
create or replace function public.playpro_safe_signup_role(p_role text)
returns public.user_role
language plpgsql
immutable
set search_path to 'public','pg_temp'
as $function$
declare
  v_role text := lower(trim(coalesce(p_role,'')));
begin
  v_role := case v_role
    when 'pemain' then 'player'
    when 'jurulatih' then 'coach'
    when 'pengurus_kelab' then 'club_admin'
    when 'club_manager' then 'club_admin'
    when 'manager' then 'club_admin'
    when 'club_admin' then 'club_admin'
    when 'club_owner' then 'club_admin'
    when 'penganjur_liga' then 'organizer'
    when 'league_admin' then 'organizer'
    when 'organizer' then 'organizer'
    when 'pengadil' then 'referee'
    else v_role
  end;

  if v_role in ('player','coach','club_admin','organizer','referee') then
    return v_role::public.user_role;
  end if;
  return 'player'::public.user_role;
end;
$function$;

create or replace function public.playpro_profile_kyc_verified(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    exists (
      select 1
      from public.identity_verifications iv
      where iv.profile_id = p_profile_id
        and lower(btrim(iv.status::text)) in ('verified','approved')
        and lower(btrim(coalesce(iv.subject_type::text,'player'))) in ('player','club_owner')
    )
    or exists (
      select 1
      from public.players p
      where p.profile_id = p_profile_id
        and p.is_active = true
        and lower(btrim(p.verification_status::text)) = 'verified'
    );
$function$;

create or replace function public.request_role_kyc(
  p_subject_type text,
  p_id_type text,
  p_legal_name text,
  p_birth_state_code text default null,
  p_masked_identifier text default null,
  p_document_storage_paths jsonb default '[]'::jsonb,
  p_provider_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  if p_subject_type not in ('organizer','referee','club_owner') then
    raise exception 'Unsupported role KYC subject';
  end if;
  if p_id_type not in ('mykad','mykid','passport') then
    raise exception 'Unsupported identity document type';
  end if;
  if p_legal_name is null or btrim(p_legal_name)='' then
    raise exception 'Legal name is required';
  end if;
  if p_document_storage_paths is null or jsonb_typeof(p_document_storage_paths)<>'array'
     or jsonb_array_length(p_document_storage_paths) not between 1 and 2 then
    raise exception 'Sila muat naik 1 atau 2 dokumen';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(p_document_storage_paths) as d(path)
    where d.path !~ ('^'||v_uid::text||'/[A-Za-z0-9._-]+$')
  ) then
    raise exception 'Lokasi dokumen KYC tidak sah' using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_uid::text||':'||p_subject_type));

  select id into v_id
  from public.identity_verifications
  where profile_id=v_uid and subject_type=p_subject_type and status='pending'
  order by created_at desc
  limit 1
  for update;

  if v_id is not null then
    update public.identity_verifications
       set id_type=lower(trim(p_id_type)),
           legal_name_claimed=btrim(p_legal_name),
           birth_state_code=nullif(btrim(coalesce(p_birth_state_code,'')),''),
           masked_identifier=nullif(btrim(coalesce(p_masked_identifier,'')),''),
           provider_reference=p_provider_reference,
           document_storage_paths=p_document_storage_paths,
           provider='google_document_ai',
           provider_status='queued',
           match_status='not_processed',
           match_score=null,
           processed_at=null,
           updated_at=now()
     where id=v_id;
    return v_id;
  end if;

  insert into public.identity_verifications(
    profile_id,subject_type,id_type,legal_name_claimed,birth_state_code,
    masked_identifier,provider_reference,document_storage_paths,provider,
    provider_status,status,match_status
  )
  values(
    v_uid,p_subject_type,lower(trim(p_id_type)),btrim(p_legal_name),
    nullif(btrim(coalesce(p_birth_state_code,'')),''),
    nullif(btrim(coalesce(p_masked_identifier,'')),''),
    p_provider_reference,p_document_storage_paths,'google_document_ai',
    'queued','pending','not_processed'
  )
  returning id into v_id;

  return v_id;
end;
$function$;
