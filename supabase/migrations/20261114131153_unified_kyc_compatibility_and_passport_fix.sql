-- Applied to Supabase playpro2 as migration version 20261114131153.
-- Follow-up hardening for DEC-043: safe legacy adapters, pending reuse and central Player Passport issuance.

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
   perform public.attach_identity_kyc_documents(v_id,p_document_storage_paths);
 end if;
 return v_id;
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
   perform public.attach_identity_kyc_documents(v_id,p_document_storage_paths);
 end if;
 return v;
end;
$$;

create or replace function public.request_identity_kyc(
 p_id_type text,p_legal_name text,p_birth_state_code text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_k public.identity_verifications%rowtype; v_id uuid;
begin
 perform public.playpro_require_active_account();
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if lower(trim(coalesce(p_id_type,''))) not in ('mykad','mykid','passport') then raise exception 'Jenis dokumen tidak disokong' using errcode='22023'; end if;
 if nullif(btrim(coalesce(p_legal_name,'')),'') is null then raise exception 'Nama sah diperlukan' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtext(v_uid::text||':identity_kyc'));
 select * into v_k from public.identity_verifications where profile_id=v_uid and subject_type='individual' for update;
 if found then
   if v_k.status in ('verified','approved') and v_k.expires_at>now() then
     return jsonb_build_object('ok',true,'kyc_id',v_k.id,'status','verified','expires_at',v_k.expires_at);
   end if;
   if v_k.status='processing' then
     return jsonb_build_object('ok',true,'kyc_id',v_k.id,'status','processing','provider_status',v_k.provider_status);
   end if;
   if v_k.status='pending' then
     update public.identity_verifications set id_type=lower(trim(p_id_type)),
       legal_name_claimed=btrim(p_legal_name),
       birth_state_code=nullif(btrim(coalesce(p_birth_state_code,'')),''),
       updated_at=now() where id=v_k.id;
     return jsonb_build_object('ok',true,'kyc_id',v_k.id,'status','pending','provider_status',v_k.provider_status);
   end if;
   update public.identity_verifications set id_type=lower(trim(p_id_type)),
     legal_name_claimed=btrim(p_legal_name),
     birth_state_code=nullif(btrim(coalesce(p_birth_state_code,'')),''),
     status='pending',reviewer_profile_id=null,reviewer_note=null,reviewed_at=null,expires_at=null,
     document_storage_paths='[]'::jsonb,provider='google_document_ai',provider_status='queued',
     match_status='not_processed',match_score=null,extracted_legal_name=null,
     extracted_birth_date=null,extracted_id_type=null,extracted_identifier_masked=null,
     processed_at=null,submitted_at=now(),updated_at=now()
     where id=v_k.id returning id into v_id;
 else
   insert into public.identity_verifications(profile_id,subject_type,id_type,legal_name_claimed,
     birth_state_code,document_storage_paths,provider,provider_status,status,match_status)
   values(v_uid,'individual',lower(trim(p_id_type)),btrim(p_legal_name),
     nullif(btrim(coalesce(p_birth_state_code,'')),''),
     '[]'::jsonb,'google_document_ai','queued','pending','not_processed')
   returning id into v_id;
 end if;
 return jsonb_build_object('ok',true,'kyc_id',v_id,'status','pending');
end;
$$;

create or replace function public.approve_identity_kyc(
 p_kyc_id uuid,p_reviewer_note text default null,p_verified_legal_name text default null,
 p_verified_birth_date date default null,p_verified_birth_state_code text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 v_uid uuid:=(select auth.uid()); v_k public.identity_verifications%rowtype;
 v_name text; v_dob date; v_state text; v_player public.players%rowtype;
 v_coach public.coaches%rowtype; v_passport text; v_no bigint; v_result jsonb;
begin
 perform public.playpro_require_active_account();
 if v_uid is null or not public.is_league_founder_or_developer() then
   raise exception 'Developer access required' using errcode='42501';
 end if;
 select * into v_k from public.identity_verifications
   where id=p_kyc_id and subject_type='individual' for update;
 if not found then raise exception 'KYC record not found' using errcode='P0002'; end if;
 if v_k.status='verified' and v_k.expires_at>now() then
   return jsonb_build_object('ok',true,'status','verified','expires_at',v_k.expires_at,'profile_id',v_k.profile_id);
 end if;
 if v_k.status<>'pending' then raise exception 'KYC is not awaiting review' using errcode='40901'; end if;
 if jsonb_array_length(v_k.document_storage_paths) not between 1 and 2 then
   raise exception 'Dokumen asal belum dilampirkan' using errcode='22023';
 end if;
 v_name:=nullif(btrim(coalesce(p_verified_legal_name,v_k.extracted_legal_name,v_k.legal_name_claimed)),'');
 if v_name is null then raise exception 'Nama sah perlu disahkan' using errcode='22023'; end if;
 v_dob:=coalesce(p_verified_birth_date,v_k.extracted_birth_date);
 v_state:=coalesce(nullif(btrim(p_verified_birth_state_code),''),nullif(btrim(v_k.birth_state_code),''),'00');
 perform set_config('playpro.kyc_approval','true',true);
 update public.profiles set full_name=v_name,date_of_birth=coalesce(v_dob,date_of_birth),updated_at=now()
   where id=v_k.profile_id and is_active=true;
 update public.players set full_name=v_name,date_of_birth=coalesce(v_dob,date_of_birth),
   verification_status='verified',verified_at=now(),verified_by=v_uid,
   legal_name_locked_at=coalesce(legal_name_locked_at,now()),updated_at=now()
   where profile_id=v_k.profile_id and is_active=true;
 select * into v_player from public.players where profile_id=v_k.profile_id and is_active=true limit 1;
 if found and v_player.football_passport_no is null then
   v_no:=nextval('public.playpro_passport_user_no_seq');
   v_passport:=upper(rpad(left(regexp_replace(split_part(trim(v_name),' ',1),'[^A-Za-z]','','g'),4),4,'X'))
     ||'-'||v_state||'-'||lpad(v_no::text,4,'0');
   update public.players set football_passport_no=v_passport where id=v_player.id returning * into v_player;
 end if;
 update public.coaches set full_name=v_name,date_of_birth=coalesce(v_dob,date_of_birth),
   verification_status='verified',kyc_verified_at=now(),verified_at=now(),verified_by=v_uid,
   legal_name_locked_at=coalesce(legal_name_locked_at,now()),updated_at=now()
   where profile_id=v_k.profile_id and is_active=true;
 select * into v_coach from public.coaches where profile_id=v_k.profile_id and is_active=true limit 1;
 update public.identity_verifications set status='verified',reviewer_profile_id=v_uid,
   reviewer_note=p_reviewer_note,reviewed_at=now(),expires_at=now()+interval '5 years',
   extracted_legal_name=v_name,extracted_birth_date=coalesce(v_dob,extracted_birth_date),
   provider_status=coalesce(provider_status,'reviewed'),updated_at=now()
   where id=v_k.id;
 v_result:=jsonb_build_object('ok',true,'status','verified','profile_id',v_k.profile_id,
   'expires_at',now()+interval '5 years');
 if v_player.id is not null then
   v_result:=v_result||jsonb_build_object('player_id',v_player.id,'football_passport_no',v_player.football_passport_no);
 end if;
 if v_coach.id is not null then
   v_result:=v_result||jsonb_build_object('coach_id',v_coach.id,'coach_code',v_coach.coach_code);
 end if;
 return v_result;
end;
$$;
