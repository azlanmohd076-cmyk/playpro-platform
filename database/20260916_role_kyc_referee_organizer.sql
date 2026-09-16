-- PlayPro role KYC bridge for organizer/referee/club-owner plus referee profile creation.
-- Applied to production playpro2 as role_kyc_referee_organizer.

create or replace function public.request_role_kyc(
  p_subject_type text,
  p_id_type text,
  p_legal_name text,
  p_birth_state_code text default null,
  p_masked_identifier text default null,
  p_document_storage_paths jsonb default '[]'::jsonb,
  p_provider_reference text default null
) returns uuid
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_uid uuid:=auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_subject_type not in ('organizer','referee','club_owner') then raise exception 'Unsupported role KYC subject'; end if;
  if p_id_type not in ('mykad','mykid','passport') then raise exception 'Unsupported identity document type'; end if;
  if p_legal_name is null or btrim(p_legal_name)='' then raise exception 'Legal name is required'; end if;
  if jsonb_typeof(coalesce(p_document_storage_paths,'[]'::jsonb)) <> 'array' then raise exception 'Document paths must be an array'; end if;
  if jsonb_array_length(coalesce(p_document_storage_paths,'[]'::jsonb)) > 2 then raise exception 'Maximum 2 KYC documents'; end if;
  select id into v_id from public.identity_verifications where profile_id=v_uid and subject_type=p_subject_type and status='pending' order by created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  insert into public.identity_verifications(profile_id,subject_type,id_type,legal_name_claimed,birth_state_code,masked_identifier,provider_reference,document_storage_paths,provider)
  values(v_uid,p_subject_type,p_id_type,btrim(p_legal_name),nullif(p_birth_state_code,''),nullif(p_masked_identifier,''),p_provider_reference,coalesce(p_document_storage_paths,'[]'::jsonb),'google_document_ai') returning id into v_id;
  return v_id;
end; $$;
revoke execute on function public.request_role_kyc(text,text,text,text,text,jsonb,text) from public,anon;
grant execute on function public.request_role_kyc(text,text,text,text,text,jsonb,text) to authenticated;

create or replace function public.create_referee_profile(
  p_pitch_nickname text default null,
  p_license_type text default null,
  p_coverage_area text default null,
  p_phone text default null
) returns uuid
language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_uid uuid:=auth.uid(); v_id uuid; v_name text; v_dob date; v_nationality text;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if not exists(select 1 from public.identity_verifications where profile_id=v_uid and subject_type='referee' and status='verified') then raise exception 'Referee KYC verification is required'; end if;
  if exists(select 1 from public.referees where user_id=v_uid) then select id into v_id from public.referees where user_id=v_uid limit 1; return v_id; end if;
  select coalesce(p.full_name,'PlayPro Referee'),p.date_of_birth,coalesce(p.nationality,'Malaysian') into v_name,v_dob,v_nationality from public.profiles p where p.id=v_uid;
  insert into public.referees(user_id,full_name,pitch_nickname,license_type,coverage_area,nationality,date_of_birth,phone,verification_status,profile_completed_at)
  values(v_uid,v_name,p_pitch_nickname,p_license_type,p_coverage_area,v_nationality,v_dob,p_phone,'pending',now()) returning id into v_id;
  insert into public.profile_role_profiles(profile_id,role_code,subject_id) values(v_uid,'referee',v_id)
  on conflict(profile_id,role_code) do update set subject_id=excluded.subject_id,is_active=true,updated_at=now();
  return v_id;
end; $$;
revoke execute on function public.create_referee_profile(text,text,text,text) from public,anon;
grant execute on function public.create_referee_profile(text,text,text,text) to authenticated;
