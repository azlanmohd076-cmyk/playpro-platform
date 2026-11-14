-- Developer review workflow for Club Owner, Organizer and Referee identity verification.
drop policy if exists identity_verification_developer_read_role on public.identity_verifications;
create policy identity_verification_developer_read_role
on public.identity_verifications for select to authenticated
using (
  subject_type in ('club_owner','organizer','referee')
  and (select public.get_my_role())='developer'::public.user_role
);

drop policy if exists role_kyc_read_developer_documents on storage.objects;
create policy role_kyc_read_developer_documents
on storage.objects for select to authenticated
using (
  bucket_id='kyc-documents'
  and (select public.get_my_role())='developer'::public.user_role
  and exists (
    select 1
    from public.identity_verifications iv
    where iv.subject_type in ('club_owner','organizer','referee')
      and (storage.foldername(name))[1]=iv.profile_id::text
      and iv.document_storage_paths @> jsonb_build_array(name)
  )
);

create or replace function public.get_role_kyc_admin_list()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rows jsonb;
begin
  if auth.uid() is null or (select public.get_my_role()) is distinct from 'developer'::public.user_role then
    raise exception 'FORBIDDEN: Developer PlayPro only' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'kyc_id',iv.id,
    'profile_id',iv.profile_id,
    'subject_type',iv.subject_type,
    'profile_name',p.full_name,
    'profile_dob',p.date_of_birth,
    'id_type',iv.id_type,
    'legal_name_claimed',iv.legal_name_claimed,
    'birth_state_code',iv.birth_state_code,
    'submitted_at',iv.submitted_at,
    'provider_status',iv.provider_status,
    'match_status',iv.match_status,
    'extracted_legal_name',iv.extracted_legal_name,
    'extracted_birth_date',iv.extracted_birth_date,
    'document_storage_paths',iv.document_storage_paths
  ) order by iv.submitted_at),'[]'::jsonb)
  into v_rows
  from public.identity_verifications iv
  left join public.profiles p on p.id=iv.profile_id
  where iv.subject_type in ('club_owner','organizer','referee')
    and iv.status='pending';

  return jsonb_build_object('ok',true,'requests',v_rows);
end;
$function$;

create or replace function public.approve_role_kyc(
  p_kyc_id uuid,
  p_reviewer_note text default null,
  p_verified_legal_name text default null,
  p_verified_birth_date date default null,
  p_verified_birth_state_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_k public.identity_verifications%rowtype;
  v_name text;
  v_dob date;
  v_state text;
begin
  if v_uid is null or not public.is_league_founder_or_developer() then
    raise exception 'KYC approval requires PlayPro privileged access' using errcode='42501';
  end if;

  select * into v_k
  from public.identity_verifications
  where id=p_kyc_id and subject_type in ('club_owner','organizer','referee')
  for update;
  if not found then raise exception 'Role KYC request not found' using errcode='P0002'; end if;
  if v_k.status='verified' then
    return jsonb_build_object('ok',true,'status','verified','subject_type',v_k.subject_type,'profile_id',v_k.profile_id);
  end if;
  if v_k.status<>'pending' then
    raise exception 'Role KYC request is not awaiting approval' using errcode='40901';
  end if;

  v_name := nullif(btrim(coalesce(p_verified_legal_name,v_k.extracted_legal_name)), '');
  if v_name is null then
    raise exception 'Reviewer mesti mengesahkan nama sah berdasarkan dokumen asal.' using errcode='22023';
  end if;
  v_dob := coalesce(p_verified_birth_date,v_k.extracted_birth_date);
  if v_k.extracted_birth_date is not null and p_verified_birth_date is not null
     and v_k.extracted_birth_date<>p_verified_birth_date then
    raise exception 'Tarikh lahir yang disahkan tidak sepadan dengan bacaan dokumen. Semak semula dokumen asal.' using errcode='22023';
  end if;
  v_state := coalesce(nullif(btrim(p_verified_birth_state_code),''),nullif(btrim(v_k.birth_state_code),''));
  if v_state is null or v_state !~ '^[0-9]{2}$' then
    raise exception 'Kod negeri kelahiran mesti 2 digit.' using errcode='22023';
  end if;

  update public.identity_verifications
     set status='verified',
         reviewer_profile_id=v_uid,
         reviewer_note=p_reviewer_note,
         reviewed_at=now(),
         extracted_legal_name=v_name,
         extracted_birth_date=coalesce(v_dob,extracted_birth_date),
         provider_status=coalesce(provider_status,'reviewed'),
         updated_at=now()
   where id=v_k.id;

  return jsonb_build_object('ok',true,'status','verified','subject_type',v_k.subject_type,'profile_id',v_k.profile_id);
end;
$function$;

create or replace function public.reject_role_kyc(
  p_kyc_id uuid,
  p_reviewer_note text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_k public.identity_verifications%rowtype;
begin
  if v_uid is null or not public.is_league_founder_or_developer() then
    raise exception 'KYC rejection requires PlayPro privileged access' using errcode='42501';
  end if;
  if p_reviewer_note is null or btrim(p_reviewer_note)='' then
    raise exception 'Sebab penolakan wajib diisi' using errcode='22023';
  end if;
  select * into v_k
  from public.identity_verifications
  where id=p_kyc_id and subject_type in ('club_owner','organizer','referee')
  for update;
  if not found then raise exception 'Role KYC request not found' using errcode='P0002'; end if;
  if v_k.status<>'pending' then
    raise exception 'Role KYC request is not awaiting review' using errcode='40901';
  end if;

  update public.identity_verifications
     set status='rejected',
         reviewer_profile_id=v_uid,
         reviewer_note=btrim(p_reviewer_note),
         reviewed_at=now(),
         updated_at=now()
   where id=v_k.id;

  return jsonb_build_object('ok',true,'status','rejected','subject_type',v_k.subject_type,'profile_id',v_k.profile_id);
end;
$function$;

revoke all on function public.get_role_kyc_admin_list() from public,anon;
revoke all on function public.approve_role_kyc(uuid,text,date,text) from public,anon;
revoke all on function public.reject_role_kyc(uuid,text) from public,anon;
grant execute on function public.get_role_kyc_admin_list() to authenticated;
grant execute on function public.approve_role_kyc(uuid,text,date,text) to authenticated;
grant execute on function public.reject_role_kyc(uuid,text) to authenticated;
