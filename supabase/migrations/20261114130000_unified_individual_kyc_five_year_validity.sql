-- DEC-043: One person, one KYC shared by every role.
-- This migration is prepared for PR review; it is NOT applied to live playpro2.
alter table public.identity_verifications
  add column if not exists expires_at timestamptz;

alter table public.identity_verifications
  drop constraint if exists identity_verifications_subject_type_check;

update public.identity_verifications
set subject_type='individual',
    expires_at=case
      when status in ('verified','approved')
        then coalesce(expires_at, reviewed_at, submitted_at, created_at, now()) + interval '5 years'
      else expires_at
    end
where subject_type <> 'individual';

alter table public.identity_verifications
  add constraint identity_verifications_subject_type_check
  check (subject_type='individual');

drop index if exists public.ux_identity_verifications_pending;
create unique index if not exists ux_identity_verifications_active_request
  on public.identity_verifications(profile_id)
  where status in ('pending','processing');

create index if not exists idx_identity_verifications_profile_status
  on public.identity_verifications(profile_id,status,submitted_at desc);

create or replace function public.playpro_profile_kyc_verified_for(
  p_profile_id uuid,
  p_subject_type text default null
) returns boolean
language sql stable security definer set search_path=''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id=p_profile_id and p.is_active=true
  ) and exists (
    select 1 from public.identity_verifications iv
    where iv.profile_id=p_profile_id
      and iv.subject_type='individual'
      and iv.status in ('verified','approved')
      and iv.expires_at > now()
  );
$$;

create or replace function public.playpro_profile_kyc_verified(p_profile_id uuid)
returns boolean
language sql stable security definer set search_path=''
as $$
  select public.playpro_profile_kyc_verified_for(p_profile_id,null);
$$;

create or replace function public.get_my_identity_kyc_status()
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_k public.identity_verifications%rowtype;
begin
  perform public.playpro_require_active_account();
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into v_k from public.identity_verifications
  where profile_id=v_uid and subject_type='individual'
  order by submitted_at desc,created_at desc limit 1;
  if not found then return jsonb_build_object('ok',true,'status','not_submitted','is_verified',false); end if;
  return jsonb_build_object(
    'ok',true,'kyc_id',v_k.id,'status',v_k.status,
    'is_verified',v_k.status in ('verified','approved') and v_k.expires_at>now(),
    'id_type',v_k.id_type,'submitted_at',v_k.submitted_at,
    'reviewed_at',v_k.reviewed_at,'expires_at',v_k.expires_at,
    'provider_status',v_k.provider_status,'match_status',v_k.match_status,
    'reviewer_note',v_k.reviewer_note
  );
end;
$$;

create or replace function public.request_identity_kyc(
  p_id_type text,
  p_legal_name text,
  p_birth_state_code text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid:=(select auth.uid());
  v_k public.identity_verifications%rowtype;
  v_id uuid;
begin
  perform public.playpro_require_active_account();
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if lower(trim(coalesce(p_id_type,''))) not in ('mykad','mykid','passport') then
    raise exception 'Jenis dokumen tidak disokong' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_legal_name,'')),'') is null then
    raise exception 'Nama sah diperlukan' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtext(v_uid::text||':identity_kyc'));
  select * into v_k from public.identity_verifications
    where profile_id=v_uid and subject_type='individual'
      and status in ('verified','approved') and expires_at>now()
    order by reviewed_at desc nulls last limit 1 for update;
  if found then
    return jsonb_build_object('ok',true,'kyc_id',v_k.id,'status','verified','expires_at',v_k.expires_at);
  end if;
  select * into v_k from public.identity_verifications
    where profile_id=v_uid and subject_type='individual'
      and status in ('pending','processing')
    order by submitted_at desc limit 1 for update;
  if found then
    if v_k.status='processing' then
      return jsonb_build_object('ok',true,'kyc_id',v_k.id,'status','processing');
    end if;
    update public.identity_verifications
      set id_type=lower(trim(p_id_type)),
          legal_name_claimed=btrim(p_legal_name),
          birth_state_code=nullif(btrim(coalesce(p_birth_state_code,'')),''),
          document_storage_paths='[]'::jsonb,
          provider='google_document_ai',provider_status='queued',
          match_status='not_processed',match_score=null,
          extracted_legal_name=null,extracted_birth_date=null,
          extracted_id_type=null,extracted_identifier_masked=null,
          processed_at=null,submitted_at=now(),updated_at=now()
      where id=v_k.id returning id into v_id;
  else
    insert into public.identity_verifications(
      profile_id,subject_type,id_type,legal_name_claimed,birth_state_code,
      document_storage_paths,provider,provider_status,status,match_status
    ) values (
      v_uid,'individual',lower(trim(p_id_type)),btrim(p_legal_name),
      nullif(btrim(coalesce(p_birth_state_code,'')),''),
      '[]'::jsonb,'google_document_ai','queued','pending','not_processed'
    ) returning id into v_id;
  end if;
  return jsonb_build_object('ok',true,'kyc_id',v_id,'status','pending');
end;
$$;

create or replace function public.attach_identity_kyc_documents(
  p_kyc_id uuid,
  p_document_paths jsonb
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_path text; v_count integer;
begin
  perform public.playpro_require_active_account();
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_document_paths is null or jsonb_typeof(p_document_paths)<>'array' then
    raise exception 'Dokumen tidak sah' using errcode='22023';
  end if;
  v_count:=jsonb_array_length(p_document_paths);
  if v_count<1 or v_count>2 then raise exception 'Muat naik satu atau dua dokumen sahaja' using errcode='22023'; end if;
  if not exists(select 1 from public.identity_verifications
    where id=p_kyc_id and profile_id=v_uid and subject_type='individual' and status='pending') then
    raise exception 'Permohonan KYC tidak ditemui atau tidak boleh dikemas kini' using errcode='42501';
  end if;
  for v_path in select jsonb_array_elements_text(p_document_paths) loop
    if v_path is null or v_path not like v_uid::text||'/%' then
      raise exception 'Lokasi dokumen tidak sah' using errcode='42501';
    end if;
    if not exists(select 1 from storage.objects
      where bucket_id='kyc-documents' and name=v_path and owner_id=v_uid::text) then
      raise exception 'Dokumen tidak ditemui atau bukan milik akaun ini' using errcode='42501';
    end if;
  end loop;
  update public.identity_verifications
    set document_storage_paths=p_document_paths,updated_at=now()
    where id=p_kyc_id and profile_id=v_uid;
  return jsonb_build_object('ok',true,'kyc_id',p_kyc_id,'document_count',v_count);
end;
$$;

create or replace function public.get_identity_kyc_admin_list()
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_rows jsonb;
begin
  perform public.playpro_require_active_account();
  if auth.uid() is null or (select public.get_my_role()) is distinct from 'developer'::public.user_role then
    raise exception 'Developer access required' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'kyc_id',iv.id,'profile_id',iv.profile_id,'profile_name',p.full_name,
    'profile_dob',p.date_of_birth,'id_type',iv.id_type,
    'legal_name_claimed',iv.legal_name_claimed,'birth_state_code',iv.birth_state_code,
    'submitted_at',iv.submitted_at,'provider_status',iv.provider_status,
    'match_status',iv.match_status,'extracted_legal_name',iv.extracted_legal_name,
    'extracted_birth_date',iv.extracted_birth_date,
    'document_storage_paths',iv.document_storage_paths
  ) order by iv.submitted_at),'[]'::jsonb) into v_rows
  from public.identity_verifications iv
  join public.profiles p on p.id=iv.profile_id
  where iv.subject_type='individual' and iv.status='pending';
  return jsonb_build_object('ok',true,'requests',v_rows);
end;
$$;

create or replace function public.approve_identity_kyc(
  p_kyc_id uuid,
  p_reviewer_note text default null,
  p_verified_legal_name text default null,
  p_verified_birth_date date default null,
  p_verified_birth_state_code text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid:=(select auth.uid());
  v_k public.identity_verifications%rowtype;
  v_name text; v_dob date; v_state text;
  v_player public.players%rowtype;
  v_coach public.coaches%rowtype;
  v_passport text;
begin
  perform public.playpro_require_active_account();
  if v_uid is null or not public.is_league_founder_or_developer() then
    raise exception 'Developer access required' using errcode='42501';
  end if;
  select * into v_k from public.identity_verifications
    where id=p_kyc_id and subject_type='individual' for update;
  if not found then raise exception 'KYC record not found' using errcode='P0002'; end if;
  if v_k.status='verified' and v_k.expires_at>now() then
    return jsonb_build_object('ok',true,'status','verified','expires_at',v_k.expires_at);
  end if;
  if v_k.status<>'pending' then raise exception 'KYC is not awaiting review' using errcode='40901'; end if;
  if jsonb_array_length(v_k.document_storage_paths) not between 1 and 2 then
    raise exception 'Dokumen asal belum dilampirkan' using errcode='22023';
  end if;
  v_name:=nullif(btrim(coalesce(p_verified_legal_name,v_k.extracted_legal_name,v_k.legal_name_claimed)),'');
  if v_name is null then raise exception 'Nama sah perlu disahkan' using errcode='22023'; end if;
  v_dob:=coalesce(p_verified_birth_date,v_k.extracted_birth_date);
  v_state:=coalesce(nullif(btrim(p_verified_birth_state_code),''),nullif(btrim(v_k.birth_state_code),''));
  if v_state is null or v_state !~ '^[0-9]{2}$' then raise exception 'Kod negeri kelahiran mesti dua digit' using errcode='22023'; end if;

  perform set_config('playpro.kyc_approval','true',true);
  update public.profiles set full_name=v_name,date_of_birth=coalesce(v_dob,date_of_birth),updated_at=now()
    where id=v_k.profile_id and is_active=true;
  update public.players set full_name=v_name,date_of_birth=coalesce(v_dob,date_of_birth),
    verification_status='verified',verified_at=now(),verified_by=v_uid,
    legal_name_locked_at=coalesce(legal_name_locked_at,now()),updated_at=now()
    where profile_id=v_k.profile_id and is_active=true;
  update public.coaches set full_name=v_name,date_of_birth=coalesce(v_dob,date_of_birth),
    verification_status='verified',kyc_verified_at=now(),verified_at=now(),verified_by=v_uid,
    legal_name_locked_at=coalesce(legal_name_locked_at,now()),updated_at=now()
    where profile_id=v_k.profile_id and is_active=true;
  update public.identity_verifications set status='verified',reviewer_profile_id=v_uid,
    reviewer_note=p_reviewer_note,reviewed_at=now(),expires_at=now()+interval '5 years',
    extracted_legal_name=v_name,extracted_birth_date=coalesce(v_dob,extracted_birth_date),
    provider_status=coalesce(provider_status,'reviewed'),updated_at=now()
    where id=v_k.id;
  return jsonb_build_object('ok',true,'status','verified','profile_id',v_k.profile_id,
    'expires_at',now()+interval '5 years','roles_updated',jsonb_build_array('player','coach'));
end;
$$;

create or replace function public.reject_identity_kyc(p_kyc_id uuid,p_reviewer_note text)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid());
begin
  perform public.playpro_require_active_account();
  if v_uid is null or not public.is_league_founder_or_developer() then
    raise exception 'Developer access required' using errcode='42501';
  end if;
  if nullif(btrim(coalesce(p_reviewer_note,'')),'') is null then
    raise exception 'Sebab penolakan wajib diisi' using errcode='22023';
  end if;
  update public.identity_verifications set status='rejected',reviewer_profile_id=v_uid,
    reviewer_note=btrim(p_reviewer_note),reviewed_at=now(),updated_at=now()
    where id=p_kyc_id and subject_type='individual' and status='pending';
  if not found then raise exception 'KYC tidak ditemui atau sudah diputuskan' using errcode='P0002'; end if;
  return jsonb_build_object('ok',true,'status','rejected','kyc_id',p_kyc_id);
end;
$$;

-- One private storage policy set for the canonical individual KYC record.
drop policy if exists "coach_kyc_owner_read_attached_active" on storage.objects;
drop policy if exists "coach_kyc_owner_upload_pending_active" on storage.objects;
drop policy if exists "coach_kyc_developer_read_attached_active" on storage.objects;
drop policy if exists "player_kyc_owner_read_attached_active" on storage.objects;
drop policy if exists "player_kyc_owner_upload_pending_active" on storage.objects;
drop policy if exists "role_kyc_owner_read_attached_active" on storage.objects;
drop policy if exists "role_kyc_owner_upload_pending_active" on storage.objects;
drop policy if exists "role_kyc_developer_read_attached_active" on storage.objects;

create policy "identity_kyc_owner_read_attached_active"
on storage.objects for select to authenticated
using (
  bucket_id='kyc-documents'
  and owner_id=(select auth.uid())::text
  and public.playpro_account_is_active()
  and exists(select 1 from public.identity_verifications iv
    where iv.profile_id=(select auth.uid()) and iv.subject_type='individual'
      and iv.document_storage_paths @> jsonb_build_array(objects.name))
);

create policy "identity_kyc_owner_upload_pending_active"
on storage.objects for insert to authenticated
with check (
  bucket_id='kyc-documents'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and public.playpro_account_is_active()
  and exists(select 1 from public.identity_verifications iv
    where iv.profile_id=(select auth.uid()) and iv.subject_type='individual'
      and iv.status='pending')
);

create policy "identity_kyc_developer_read_attached_active"
on storage.objects for select to authenticated
using (
  bucket_id='kyc-documents'
  and public.playpro_account_is_active()
  and public.get_my_role()='developer'::public.user_role
  and exists(select 1 from public.identity_verifications iv
    where iv.subject_type='individual'
      and (storage.foldername(objects.name))[1]=iv.profile_id::text
      and iv.document_storage_paths @> jsonb_build_array(objects.name))
);

revoke all on function public.get_my_identity_kyc_status() from public,anon;
revoke all on function public.request_identity_kyc(text,text,text) from public,anon;
revoke all on function public.attach_identity_kyc_documents(uuid,jsonb) from public,anon;
revoke all on function public.get_identity_kyc_admin_list() from public,anon;
revoke all on function public.approve_identity_kyc(uuid,text,text,date,text) from public,anon;
revoke all on function public.reject_identity_kyc(uuid,text) from public,anon;
grant execute on function public.get_my_identity_kyc_status() to authenticated,service_role;
grant execute on function public.request_identity_kyc(text,text,text) to authenticated,service_role;
grant execute on function public.attach_identity_kyc_documents(uuid,jsonb) to authenticated,service_role;
grant execute on function public.get_identity_kyc_admin_list() to authenticated,service_role;
grant execute on function public.approve_identity_kyc(uuid,text,text,date,text) to authenticated,service_role;
grant execute on function public.reject_identity_kyc(uuid,text) to authenticated,service_role;


-- Compatibility adapters: legacy role endpoints now read/write the same person-level KYC.
create or replace function public.request_role_kyc(
 p_subject_type text,p_id_type text,p_legal_name text,p_birth_state_code text default null,
 p_masked_identifier text default null,p_document_storage_paths jsonb default '[]'::jsonb,
 p_provider_reference text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v jsonb; v_id uuid;
begin
 v:=public.request_identity_kyc(p_id_type,p_legal_name,p_birth_state_code);
 v_id:=(v->>'kyc_id')::uuid;
 if jsonb_typeof(coalesce(p_document_storage_paths,'[]'::jsonb))='array'
    and jsonb_array_length(coalesce(p_document_storage_paths,'[]'::jsonb)) between 1 and 2 then
   update public.identity_verifications set document_storage_paths=p_document_storage_paths,
     updated_at=now() where id=v_id and profile_id=auth.uid() and status='pending';
 end if;
 return v_id;
end;
$$;

create or replace function public.request_coach_kyc(
 p_id_type text,p_legal_name text,p_birth_state_code text default null,
 p_masked_identifier text default null,p_provider_reference text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v jsonb;
begin
 v:=public.request_identity_kyc(p_id_type,p_legal_name,p_birth_state_code);
 return v||jsonb_build_object('success',true);
end;
$$;

create or replace function public.request_player_kyc_document(
 p_id_type text,p_legal_name text,p_birth_state_code text,p_document_storage_paths jsonb
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v jsonb; v_id uuid;
begin
 v:=public.request_identity_kyc(p_id_type,p_legal_name,p_birth_state_code);
 v_id:=(v->>'kyc_id')::uuid;
 if v->>'status'='verified' then return v; end if;
 if p_document_storage_paths is not null and jsonb_typeof(p_document_storage_paths)='array'
    and jsonb_array_length(p_document_storage_paths) between 1 and 2 then
   update public.identity_verifications set document_storage_paths=p_document_storage_paths,
     updated_at=now() where id=v_id and profile_id=auth.uid() and status='pending';
 end if;
 return v;
end;
$$;

create or replace function public.approve_player_kyc(
 p_kyc_id uuid,p_reviewer_note text default null,p_verified_legal_name text default null,
 p_verified_birth_date date default null,p_verified_birth_state_code text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v jsonb; v_player public.players%rowtype; v_name text; v_state text; v_no bigint; v_passport text;
begin
 v:=public.approve_identity_kyc(p_kyc_id,p_reviewer_note,p_verified_legal_name,p_verified_birth_date,p_verified_birth_state_code);
 select * into v_player from public.players where profile_id=(v->>'profile_id')::uuid and is_active=true limit 1;
 if found then
   if v_player.football_passport_no is null then
     v_name:=coalesce(p_verified_legal_name,v_player.full_name);
     v_state:=coalesce(nullif(btrim(p_verified_birth_state_code),''),'00');
     v_no:=nextval('public.playpro_passport_user_no_seq');
     v_passport:=upper(rpad(left(regexp_replace(split_part(trim(v_name),' ',1),'[^A-Za-z]','','g'),4),4,'X'))||'-'||v_state||'-'||lpad(v_no::text,4,'0');
     update public.players set football_passport_no=v_passport where id=v_player.id returning * into v_player;
   end if;
   return v||jsonb_build_object('player_id',v_player.id,'football_passport_no',v_player.football_passport_no);
 end if;
 return v;
end;
$$;

create or replace function public.approve_coach_kyc(
 p_kyc_id uuid,p_reviewer_note text default null,p_verified_legal_name text default null,
 p_verified_birth_date date default null,p_verified_birth_state_code text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v jsonb; v_coach public.coaches%rowtype;
begin
 v:=public.approve_identity_kyc(p_kyc_id,p_reviewer_note,p_verified_legal_name,p_verified_birth_date,p_verified_birth_state_code);
 select * into v_coach from public.coaches where profile_id=(v->>'profile_id')::uuid and is_active=true limit 1;
 if found then return v||jsonb_build_object('coach_id',v_coach.id,'coach_code',v_coach.coach_code); end if;
 return v;
end;
$$;

create or replace function public.approve_role_kyc(
 p_kyc_id uuid,p_reviewer_note text default null,p_verified_legal_name text default null,
 p_verified_birth_date date default null,p_verified_birth_state_code text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
begin
 return public.approve_identity_kyc(p_kyc_id,p_reviewer_note,p_verified_legal_name,p_verified_birth_date,p_verified_birth_state_code);
end;
$$;

create or replace function public.reject_player_kyc(p_kyc_id uuid,p_reviewer_note text)
returns jsonb language sql security definer set search_path=''
as $$ select public.reject_identity_kyc(p_kyc_id,p_reviewer_note); $$;

create or replace function public.reject_coach_kyc(p_kyc_id uuid,p_reviewer_note text default null)
returns jsonb language sql security definer set search_path=''
as $$ select public.reject_identity_kyc(p_kyc_id,p_reviewer_note); $$;

create or replace function public.reject_role_kyc(p_kyc_id uuid,p_reviewer_note text)
returns jsonb language sql security definer set search_path=''
as $$ select public.reject_identity_kyc(p_kyc_id,p_reviewer_note); $$;

create or replace function public.get_my_player_kyc_status()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_k jsonb; v_p public.players%rowtype;
begin
 v_k:=public.get_my_identity_kyc_status();
 select * into v_p from public.players where profile_id=v_uid and is_active=true limit 1;
 if not found then return jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND'); end if;
 return v_k||jsonb_build_object('verification_status',v_p.verification_status,
   'football_passport_no',v_p.football_passport_no);
end;
$$;

create or replace function public.get_player_kyc_admin_list()
returns jsonb language sql security definer set search_path=''
as $$ select public.get_identity_kyc_admin_list(); $$;

create or replace function public.get_role_kyc_admin_list()
returns jsonb language sql security definer set search_path=''
as $$ select public.get_identity_kyc_admin_list(); $$;

create or replace function public.get_coach_kyc_admin_list()
returns jsonb language sql security definer set search_path=''
as $$ select public.get_identity_kyc_admin_list(); $$;

revoke all on function public.request_role_kyc(text,text,text,text,text,jsonb,text) from public,anon;
revoke all on function public.request_coach_kyc(text,text,text,text,text) from public,anon;
revoke all on function public.request_player_kyc_document(text,text,text,jsonb) from public,anon;
revoke all on function public.approve_player_kyc(uuid,text,text,date,text) from public,anon;
revoke all on function public.approve_coach_kyc(uuid,text,text,date,text) from public,anon;
revoke all on function public.approve_role_kyc(uuid,text,text,date,text) from public,anon;
revoke all on function public.reject_player_kyc(uuid,text) from public,anon;
revoke all on function public.reject_coach_kyc(uuid,text) from public,anon;
revoke all on function public.reject_role_kyc(uuid,text) from public,anon;
revoke all on function public.get_my_player_kyc_status() from public,anon;
revoke all on function public.get_player_kyc_admin_list() from public,anon;
revoke all on function public.get_role_kyc_admin_list() from public,anon;
revoke all on function public.get_coach_kyc_admin_list() from public,anon;
grant execute on function public.request_role_kyc(text,text,text,text,text,jsonb,text) to authenticated,service_role;
grant execute on function public.request_coach_kyc(text,text,text,text,text) to authenticated,service_role;
grant execute on function public.request_player_kyc_document(text,text,text,jsonb) to authenticated,service_role;
grant execute on function public.approve_player_kyc(uuid,text,text,date,text) to authenticated,service_role;
grant execute on function public.approve_coach_kyc(uuid,text,text,date,text) to authenticated,service_role;
grant execute on function public.approve_role_kyc(uuid,text,text,date,text) to authenticated,service_role;
grant execute on function public.reject_player_kyc(uuid,text) to authenticated,service_role;
grant execute on function public.reject_coach_kyc(uuid,text) to authenticated,service_role;
grant execute on function public.reject_role_kyc(uuid,text) to authenticated,service_role;
grant execute on function public.get_my_player_kyc_status() to authenticated,service_role;
grant execute on function public.get_player_kyc_admin_list() to authenticated,service_role;
grant execute on function public.get_role_kyc_admin_list() to authenticated,service_role;
grant execute on function public.get_coach_kyc_admin_list() to authenticated,service_role;


-- Enforce one canonical row per person. The live audit on 2026-11-14 found
-- zero profiles with multiple identity_verifications rows.
drop index if exists public.ux_identity_verifications_active_request;
create unique index if not exists ux_identity_verifications_one_per_person
  on public.identity_verifications(profile_id);

create or replace function public.request_identity_kyc(
  p_id_type text,
  p_legal_name text,
  p_birth_state_code text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid:=(select auth.uid());
  v_k public.identity_verifications%rowtype;
  v_id uuid;
begin
  perform public.playpro_require_active_account();
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if lower(trim(coalesce(p_id_type,''))) not in ('mykad','mykid','passport') then
    raise exception 'Jenis dokumen tidak disokong' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_legal_name,'')),'') is null then
    raise exception 'Nama sah diperlukan' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtext(v_uid::text||':identity_kyc'));
  select * into v_k from public.identity_verifications
    where profile_id=v_uid and subject_type='individual' for update;
  if found then
    if v_k.status in ('verified','approved') and v_k.expires_at>now() then
      return jsonb_build_object('ok',true,'kyc_id',v_k.id,'status','verified','expires_at',v_k.expires_at);
    end if;
    if v_k.status='processing' then
      return jsonb_build_object('ok',true,'kyc_id',v_k.id,'status','processing');
    end if;
    update public.identity_verifications set
      id_type=lower(trim(p_id_type)),
      legal_name_claimed=btrim(p_legal_name),
      birth_state_code=nullif(btrim(coalesce(p_birth_state_code,'')),''),
      status='pending',reviewer_profile_id=null,reviewer_note=null,reviewed_at=null,expires_at=null,
      document_storage_paths='[]'::jsonb,provider='google_document_ai',
      provider_status='queued',match_status='not_processed',match_score=null,
      extracted_legal_name=null,extracted_birth_date=null,extracted_id_type=null,
      extracted_identifier_masked=null,processed_at=null,submitted_at=now(),updated_at=now()
      where id=v_k.id returning id into v_id;
  else
    insert into public.identity_verifications(
      profile_id,subject_type,id_type,legal_name_claimed,birth_state_code,
      document_storage_paths,provider,provider_status,status,match_status
    ) values (
      v_uid,'individual',lower(trim(p_id_type)),btrim(p_legal_name),
      nullif(btrim(coalesce(p_birth_state_code,'')),''),
      '[]'::jsonb,'google_document_ai','queued','pending','not_processed'
    ) returning id into v_id;
  end if;
  return jsonb_build_object('ok',true,'kyc_id',v_id,'status','pending');
end;
$$;

drop policy if exists identity_verification_developer_read_coach on public.identity_verifications;
create policy identity_verification_developer_read_active
on public.identity_verifications for select to authenticated
using (
  subject_type='individual'
  and public.playpro_account_is_active()
  and (select public.get_my_role())='developer'::public.user_role
);
