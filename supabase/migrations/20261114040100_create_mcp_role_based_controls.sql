
create table if not exists private.mcp_admin_role_assignments (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  previous_role public.user_role not null,
  assigned_by uuid not null references public.profiles(id),
  assigned_at timestamptz not null default now(),
  revoked_by uuid references public.profiles(id),
  revoked_at timestamptz
);
revoke all on private.mcp_admin_role_assignments from public, anon, authenticated;

create or replace function public.mcp_overview()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role text; v jsonb;
begin
 select role::text into v_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or v_role not in ('developer','admin') then raise exception 'MCP access denied' using errcode='42501'; end if;
 select jsonb_build_object(
  'role',v_role,
  'players',(select count(*) from public.players),
  'active_players',(select count(*) from public.players where is_active),
  'demo_players',(select count(*) from public.players where is_demo),
  'coaches',(select count(*) from public.coaches),
  'active_coaches',(select count(*) from public.coaches where is_active),
  'clubs',(select count(*) from public.clubs),
  'pending_player_kyc',(select count(*) from public.identity_verifications where subject_type='player' and status='pending'),
  'pending_coach_kyc',(select count(*) from public.identity_verifications where subject_type='coach' and status='pending'),
  'player_assessments',(select count(*) from public.player_assessment_records),
  'accredited_coaches',(select count(*) from public.coach_accreditations where status='active')
 ) into v;
 return v;
end $$;
revoke all on function public.mcp_overview() from public,anon;
grant execute on function public.mcp_overview() to authenticated;

create or replace function public.mcp_search_records(p_entity text,p_search text default '',p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role text; v_rows jsonb; v_q text := '%'||coalesce(trim(p_search),'')||'%'; v_limit int:=least(greatest(coalesce(p_limit,50),1),100);
begin
 select role::text into v_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or v_role not in ('developer','admin') then raise exception 'MCP access denied' using errcode='42501'; end if;
 if p_entity='players' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
   select id,profile_id,full_name,preferred_name,date_of_birth,position::text position,nationality,
    height_cm,weight_kg,preferred_foot::text preferred_foot,jersey_number,bio,is_active,is_demo,is_free_agent,
    profile_visibility,verification_status,football_passport_no,created_at
   from public.players
   where coalesce(full_name,'') ilike v_q or coalesce(preferred_name,'') ilike v_q or coalesce(football_passport_no,'') ilike v_q
   order by created_at desc limit v_limit
  ) x;
 elsif p_entity='coaches' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
   select c.id,c.profile_id,c.full_name,c.preferred_name,c.bio,c.coaching_role,c.preferred_formation,c.preferred_style,
    c.coaching_specialties,c.license_type,c.license_status,c.verification_status,c.is_active,c.coach_code,c.created_at,
    ca.accreditation_level,ca.status assessor_status
   from public.coaches c left join public.coach_accreditations ca on ca.coach_profile_id=c.profile_id
   where coalesce(c.full_name,'') ilike v_q or coalesce(c.preferred_name,'') ilike v_q or coalesce(c.coach_code,'') ilike v_q
   order by c.created_at desc limit v_limit
  ) x;
 elsif p_entity='assessments' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
   select a.id,a.player_id,p.full_name player_name,a.coach_profile_id,co.full_name coach_name,
    a.accreditation_level,a.assessed_at,a.notes,a.attributes
   from public.player_assessment_records a join public.players p on p.id=a.player_id
   left join public.coaches co on co.profile_id=a.coach_profile_id
   where coalesce(p.full_name,'') ilike v_q or coalesce(co.full_name,'') ilike v_q
   order by a.assessed_at desc limit v_limit
  ) x;
 else raise exception 'Unsupported MCP entity'; end if;
 return v_rows;
end $$;
revoke all on function public.mcp_search_records(text,text,integer) from public,anon;
grant execute on function public.mcp_search_records(text,text,integer) to authenticated;

create or replace function public.mcp_update_record(p_entity text,p_id uuid,p_changes jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role text; v_before jsonb; v_after jsonb; v_allowed text[]; v_key text;
begin
 select role::text into v_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or v_role not in ('developer','admin') then raise exception 'MCP access denied' using errcode='42501'; end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'object' or p_changes='{}'::jsonb then raise exception 'No changes supplied'; end if;
 if v_role='admin' then
  if p_entity='players' then v_allowed:=array['preferred_name','position','nationality','height_cm','weight_kg','preferred_foot','jersey_number','bio','is_free_agent'];
  elsif p_entity='coaches' then v_allowed:=array['preferred_name','bio','coaching_role','preferred_formation','preferred_style','coaching_specialties'];
  else raise exception 'Admin cannot edit this entity'; end if;
 else
  if p_entity='players' then v_allowed:=array['full_name','preferred_name','date_of_birth','position','nationality','height_cm','weight_kg','preferred_foot','jersey_number','bio','is_active','is_free_agent'];
  elsif p_entity='coaches' then v_allowed:=array['full_name','preferred_name','bio','coaching_role','preferred_formation','preferred_style','coaching_specialties','license_type','license_number','license_issuing_body','license_issue_date','license_expiry_date','license_status','is_active'];
  else raise exception 'Updates not enabled for this entity'; end if;
 end if;
 for v_key in select jsonb_object_keys(p_changes) loop
  if not (v_key=any(v_allowed)) then raise exception 'Field not permitted for role: %',v_key using errcode='42501'; end if;
 end loop;
 if p_entity='players' then
  select to_jsonb(p) into v_before from public.players p where p.id=p_id for update;
  if v_before is null then raise exception 'Player not found'; end if;
  update public.players p set
   full_name=case when p_changes?'full_name' then nullif(p_changes->>'full_name','') else p.full_name end,
   preferred_name=case when p_changes?'preferred_name' then nullif(p_changes->>'preferred_name','') else p.preferred_name end,
   date_of_birth=case when p_changes?'date_of_birth' then (p_changes->>'date_of_birth')::date else p.date_of_birth end,
   position=case when p_changes?'position' then (p_changes->>'position')::public.player_position else p.position end,
   nationality=case when p_changes?'nationality' then nullif(p_changes->>'nationality','') else p.nationality end,
   height_cm=case when p_changes?'height_cm' then nullif(p_changes->>'height_cm','')::numeric else p.height_cm end,
   weight_kg=case when p_changes?'weight_kg' then nullif(p_changes->>'weight_kg','')::numeric else p.weight_kg end,
   preferred_foot=case when p_changes?'preferred_foot' then nullif(p_changes->>'preferred_foot','')::public.preferred_foot else p.preferred_foot end,
   jersey_number=case when p_changes?'jersey_number' then nullif(p_changes->>'jersey_number','')::integer else p.jersey_number end,
   bio=case when p_changes?'bio' then nullif(p_changes->>'bio','') else p.bio end,
   is_active=case when p_changes?'is_active' then (p_changes->>'is_active')::boolean else p.is_active end,
   is_free_agent=case when p_changes?'is_free_agent' then (p_changes->>'is_free_agent')::boolean else p.is_free_agent end,
   updated_at=now() where p.id=p_id returning to_jsonb(p) into v_after;
 elsif p_entity='coaches' then
  select to_jsonb(c) into v_before from public.coaches c where c.id=p_id for update;
  if v_before is null then raise exception 'Coach not found'; end if;
  update public.coaches c set
   full_name=case when p_changes?'full_name' then nullif(p_changes->>'full_name','') else c.full_name end,
   preferred_name=case when p_changes?'preferred_name' then nullif(p_changes->>'preferred_name','') else c.preferred_name end,
   bio=case when p_changes?'bio' then nullif(p_changes->>'bio','') else c.bio end,
   coaching_role=case when p_changes?'coaching_role' then nullif(p_changes->>'coaching_role','') else c.coaching_role end,
   preferred_formation=case when p_changes?'preferred_formation' then nullif(p_changes->>'preferred_formation','') else c.preferred_formation end,
   preferred_style=case when p_changes?'preferred_style' then nullif(p_changes->>'preferred_style','') else c.preferred_style end,
   coaching_specialties=case when p_changes?'coaching_specialties' then p_changes->'coaching_specialties' else c.coaching_specialties end,
   license_type=case when p_changes?'license_type' then nullif(p_changes->>'license_type','') else c.license_type end,
   license_number=case when p_changes?'license_number' then nullif(p_changes->>'license_number','') else c.license_number end,
   license_issuing_body=case when p_changes?'license_issuing_body' then nullif(p_changes->>'license_issuing_body','') else c.license_issuing_body end,
   license_issue_date=case when p_changes?'license_issue_date' then nullif(p_changes->>'license_issue_date','')::date else c.license_issue_date end,
   license_expiry_date=case when p_changes?'license_expiry_date' then nullif(p_changes->>'license_expiry_date','')::date else c.license_expiry_date end,
   license_status=case when p_changes?'license_status' then nullif(p_changes->>'license_status','') else c.license_status end,
   is_active=case when p_changes?'is_active' then (p_changes->>'is_active')::boolean else c.is_active end,
   updated_at=now() where c.id=p_id returning to_jsonb(c) into v_after;
 end if;
 insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data)
 values(auth.uid(),p_entity,p_id,'update',v_before,v_after);
 return jsonb_build_object('saved',true,'entity',p_entity,'id',p_id,'role',v_role);
end $$;
revoke all on function public.mcp_update_record(text,uuid,jsonb) from public,anon;
grant execute on function public.mcp_update_record(text,uuid,jsonb) to authenticated;

create or replace function public.mcp_create_player(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role text; v_id uuid; v_row jsonb;
begin
 select role::text into v_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or v_role not in ('developer','admin') then raise exception 'MCP access denied' using errcode='42501'; end if;
 if p_payload is null or jsonb_typeof(p_payload)<>'object' or nullif(trim(p_payload->>'full_name'),'') is null
  or nullif(p_payload->>'date_of_birth','') is null or nullif(p_payload->>'position','') is null then
  raise exception 'Nama, tarikh lahir dan posisi wajib diisi';
 end if;
 insert into public.players(full_name,date_of_birth,position,nationality,is_active,is_demo,is_free_agent,profile_visibility,verification_status)
 values(trim(p_payload->>'full_name'),(p_payload->>'date_of_birth')::date,(p_payload->>'position')::public.player_position,
  coalesce(nullif(p_payload->>'nationality',''),'Malaysia'),false,false,true,'private','pending')
 returning id into v_id;
 select to_jsonb(p) into v_row from public.players p where p.id=v_id;
 insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data)
 values(auth.uid(),'players',v_id,'insert','{}'::jsonb,v_row);
 return jsonb_build_object('created',true,'id',v_id,'status','pending');
end $$;
revoke all on function public.mcp_create_player(jsonb) from public,anon;
grant execute on function public.mcp_create_player(jsonb) to authenticated;

create or replace function public.mcp_list_users(p_search text default '',p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role text; v_rows jsonb; v_q text:='%'||coalesce(trim(p_search),'')||'%';
begin
 select role::text into v_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or v_role<>'developer' then raise exception 'Developer access required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
  select id,email,full_name,role::text role,is_active,created_at from public.profiles
  where coalesce(email,'') ilike v_q or coalesce(full_name,'') ilike v_q
  order by created_at desc limit least(greatest(coalesce(p_limit,100),1),100)
 ) x;
 return v_rows;
end $$;
revoke all on function public.mcp_list_users(text,integer) from public,anon;
grant execute on function public.mcp_list_users(text,integer) to authenticated;

create or replace function public.mcp_set_admin_access(p_profile_id uuid,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role text; v_old public.user_role; v_new public.user_role;
begin
 select role::text into v_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or v_role<>'developer' then raise exception 'Developer access required' using errcode='42501'; end if;
 if p_profile_id is null or p_profile_id=auth.uid() then raise exception 'Cannot change own access'; end if;
 select role into v_old from public.profiles where id=p_profile_id for update;
 if not found then raise exception 'User not found'; end if;
 if v_old='developer' then raise exception 'Developer role cannot be changed through Admin Access'; end if;
 if p_enabled then
  if v_old='admin' then return jsonb_build_object('ok',true,'role','admin','unchanged',true); end if;
  insert into private.mcp_admin_role_assignments(profile_id,previous_role,assigned_by,assigned_at,revoked_by,revoked_at)
  values(p_profile_id,v_old,auth.uid(),now(),null,null)
  on conflict(profile_id) do update set previous_role=excluded.previous_role,assigned_by=excluded.assigned_by,assigned_at=now(),revoked_by=null,revoked_at=null;
  update public.profiles set role='admin'::public.user_role,updated_at=now() where id=p_profile_id;
  v_new:='admin'::public.user_role;
 else
  if v_old<>'admin' then return jsonb_build_object('ok',true,'role',v_old::text,'unchanged',true); end if;
  select previous_role into v_new from private.mcp_admin_role_assignments where profile_id=p_profile_id and revoked_at is null;
  if v_new is null or v_new='admin' then v_new:='player'::public.user_role; end if;
  update public.profiles set role=v_new,updated_at=now() where id=p_profile_id;
  update private.mcp_admin_role_assignments set revoked_by=auth.uid(),revoked_at=now() where profile_id=p_profile_id;
 end if;
 insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data)
 values(auth.uid(),'profiles',p_profile_id,case when p_enabled then 'grant_admin' else 'revoke_admin' end,
  jsonb_build_object('role',v_old::text),jsonb_build_object('role',v_new::text));
 return jsonb_build_object('ok',true,'role',v_new::text);
end $$;
revoke all on function public.mcp_set_admin_access(uuid,boolean) from public,anon;
grant execute on function public.mcp_set_admin_access(uuid,boolean) to authenticated;

create or replace function public.get_player_kyc_admin_list()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role text; v_rows jsonb;
begin
 select role::text into v_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or v_role<>'developer' then raise exception 'Developer access required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'kyc_id',iv.id,'profile_id',iv.profile_id,'player_id',p.id,
  'player_name',coalesce(nullif(p.preferred_name,''),p.full_name),
  'player_passport',p.football_passport_no,'profile_dob',p.date_of_birth,
  'id_type',iv.id_type,'legal_name_claimed',iv.legal_name_claimed,
  'birth_state_code',iv.birth_state_code,'submitted_at',iv.submitted_at,
  'provider_status',iv.provider_status,'match_status',iv.match_status,
  'extracted_legal_name',iv.extracted_legal_name,
  'extracted_birth_date',iv.extracted_birth_date,
  'document_storage_paths',iv.document_storage_paths
 ) order by iv.submitted_at),'[]'::jsonb) into v_rows
 from public.identity_verifications iv join public.players p on p.profile_id=iv.profile_id
 where iv.subject_type='player' and iv.status='pending' and p.is_active=true;
 return jsonb_build_object('ok',true,'requests',v_rows);
end $$;
revoke all on function public.get_player_kyc_admin_list() from public,anon;
grant execute on function public.get_player_kyc_admin_list() to authenticated;

create or replace function private.audit_identity_verification_status()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if old.status is distinct from new.status then
  insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data)
  values(
   coalesce(auth.uid(),new.reviewer_profile_id),
   'identity_verifications:'||new.subject_type,
   new.id,
   'update',
   jsonb_build_object('status',old.status,'reviewer_note',old.reviewer_note),
   jsonb_build_object('status',new.status,'reviewer_note',new.reviewer_note,'reviewer_profile_id',new.reviewer_profile_id)
  );
 end if;
 return new;
end $$;
revoke all on function private.audit_identity_verification_status() from public,anon,authenticated;
drop trigger if exists trg_audit_identity_verification_status on public.identity_verifications;
create trigger trg_audit_identity_verification_status
after update of status on public.identity_verifications
for each row execute function private.audit_identity_verification_status();

-- Admin is an additive MCP grant. Never overwrite profiles.role: a coach, player or referee must retain their PlayPro operational role.
create or replace function public.mcp_overview()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_base_role text; v_role text; v jsonb;
begin
 select role::text into v_base_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or not (v_base_role='developer' or exists(select 1 from private.mcp_admin_role_assignments a where a.profile_id=auth.uid() and a.revoked_at is null)) then
  raise exception 'MCP access denied' using errcode='42501';
 end if;
 v_role:=case when v_base_role='developer' then 'developer' else 'admin' end;
 select jsonb_build_object(
  'role',v_role,'players',(select count(*) from public.players),
  'active_players',(select count(*) from public.players where is_active),
  'demo_players',(select count(*) from public.players where is_demo),
  'coaches',(select count(*) from public.coaches),
  'active_coaches',(select count(*) from public.coaches where is_active),
  'clubs',(select count(*) from public.clubs),
  'pending_player_kyc',(select count(*) from public.identity_verifications where subject_type='player' and status='pending'),
  'pending_coach_kyc',(select count(*) from public.identity_verifications where subject_type='coach' and status='pending'),
  'player_assessments',(select count(*) from public.player_assessment_records),
  'accredited_coaches',(select count(*) from public.coach_accreditations where status='active')
 ) into v;
 return v;
end $$;

create or replace function public.mcp_search_records(p_entity text,p_search text default '',p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_base_role text; v_rows jsonb; v_q text := '%'||coalesce(trim(p_search),'')||'%'; v_limit int:=least(greatest(coalesce(p_limit,50),1),100);
begin
 select role::text into v_base_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or not (v_base_role='developer' or exists(select 1 from private.mcp_admin_role_assignments a where a.profile_id=auth.uid() and a.revoked_at is null)) then raise exception 'MCP access denied' using errcode='42501'; end if;
 if p_entity='players' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
   select id,profile_id,full_name,preferred_name,date_of_birth,position::text position,nationality,height_cm,weight_kg,
    preferred_foot::text preferred_foot,jersey_number,bio,is_active,is_demo,is_free_agent,profile_visibility,verification_status,football_passport_no,created_at
   from public.players where coalesce(full_name,'') ilike v_q or coalesce(preferred_name,'') ilike v_q or coalesce(football_passport_no,'') ilike v_q
   order by created_at desc limit v_limit) x;
 elsif p_entity='coaches' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
   select c.id,c.profile_id,c.full_name,c.preferred_name,c.bio,c.coaching_role,c.preferred_formation,c.preferred_style,c.coaching_specialties,
    c.license_type,c.license_status,c.verification_status,c.is_active,c.coach_code,c.created_at,ca.accreditation_level,ca.status assessor_status
   from public.coaches c left join public.coach_accreditations ca on ca.coach_profile_id=c.profile_id
   where coalesce(c.full_name,'') ilike v_q or coalesce(c.preferred_name,'') ilike v_q or coalesce(c.coach_code,'') ilike v_q
   order by c.created_at desc limit v_limit) x;
 elsif p_entity='assessments' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
   select a.id,a.player_id,p.full_name player_name,a.coach_profile_id,co.full_name coach_name,a.accreditation_level,a.assessed_at,a.notes,a.attributes
   from public.player_assessment_records a join public.players p on p.id=a.player_id left join public.coaches co on co.profile_id=a.coach_profile_id
   where coalesce(p.full_name,'') ilike v_q or coalesce(co.full_name,'') ilike v_q
   order by a.assessed_at desc limit v_limit) x;
 else raise exception 'Unsupported MCP entity'; end if;
 return v_rows;
end $$;

create or replace function public.mcp_update_record(p_entity text,p_id uuid,p_changes jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_base_role text; v_role text; v_before jsonb; v_after jsonb; v_allowed text[]; v_key text;
begin
 select role::text into v_base_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or not (v_base_role='developer' or exists(select 1 from private.mcp_admin_role_assignments a where a.profile_id=auth.uid() and a.revoked_at is null)) then raise exception 'MCP access denied' using errcode='42501'; end if;
 v_role:=case when v_base_role='developer' then 'developer' else 'admin' end;
 if p_changes is null or jsonb_typeof(p_changes)<>'object' or p_changes='{}'::jsonb then raise exception 'No changes supplied'; end if;
 if v_role='admin' then
  if p_entity='players' then v_allowed:=array['preferred_name','position','nationality','height_cm','weight_kg','preferred_foot','jersey_number','bio','is_free_agent'];
  elsif p_entity='coaches' then v_allowed:=array['preferred_name','bio','coaching_role','preferred_formation','preferred_style','coaching_specialties'];
  else raise exception 'Admin cannot edit this entity'; end if;
 else
  if p_entity='players' then v_allowed:=array['full_name','preferred_name','date_of_birth','position','nationality','height_cm','weight_kg','preferred_foot','jersey_number','bio','is_active','is_free_agent'];
  elsif p_entity='coaches' then v_allowed:=array['full_name','preferred_name','bio','coaching_role','preferred_formation','preferred_style','coaching_specialties','license_type','license_number','license_issuing_body','license_issue_date','license_expiry_date','license_status','is_active'];
  else raise exception 'Updates not enabled for this entity'; end if;
 end if;
 for v_key in select jsonb_object_keys(p_changes) loop if not(v_key=any(v_allowed)) then raise exception 'Field not permitted for role: %',v_key using errcode='42501'; end if; end loop;
 if p_entity='players' then
  select to_jsonb(p) into v_before from public.players p where p.id=p_id for update;
  if v_before is null then raise exception 'Player not found'; end if;
  update public.players p set
   full_name=case when p_changes?'full_name' then nullif(p_changes->>'full_name','') else p.full_name end,
   preferred_name=case when p_changes?'preferred_name' then nullif(p_changes->>'preferred_name','') else p.preferred_name end,
   date_of_birth=case when p_changes?'date_of_birth' then (p_changes->>'date_of_birth')::date else p.date_of_birth end,
   position=case when p_changes?'position' then (p_changes->>'position')::public.player_position else p.position end,
   nationality=case when p_changes?'nationality' then nullif(p_changes->>'nationality','') else p.nationality end,
   height_cm=case when p_changes?'height_cm' then nullif(p_changes->>'height_cm','')::numeric else p.height_cm end,
   weight_kg=case when p_changes?'weight_kg' then nullif(p_changes->>'weight_kg','')::numeric else p.weight_kg end,
   preferred_foot=case when p_changes?'preferred_foot' then nullif(p_changes->>'preferred_foot','')::public.preferred_foot else p.preferred_foot end,
   jersey_number=case when p_changes?'jersey_number' then nullif(p_changes->>'jersey_number','')::integer else p.jersey_number end,
   bio=case when p_changes?'bio' then nullif(p_changes->>'bio','') else p.bio end,
   is_active=case when p_changes?'is_active' then (p_changes->>'is_active')::boolean else p.is_active end,
   is_free_agent=case when p_changes?'is_free_agent' then (p_changes->>'is_free_agent')::boolean else p.is_free_agent end,
   updated_at=now() where p.id=p_id returning to_jsonb(p) into v_after;
 elsif p_entity='coaches' then
  select to_jsonb(c) into v_before from public.coaches c where c.id=p_id for update;
  if v_before is null then raise exception 'Coach not found'; end if;
  update public.coaches c set
   full_name=case when p_changes?'full_name' then nullif(p_changes->>'full_name','') else c.full_name end,
   preferred_name=case when p_changes?'preferred_name' then nullif(p_changes->>'preferred_name','') else c.preferred_name end,
   bio=case when p_changes?'bio' then nullif(p_changes->>'bio','') else c.bio end,
   coaching_role=case when p_changes?'coaching_role' then nullif(p_changes->>'coaching_role','') else c.coaching_role end,
   preferred_formation=case when p_changes?'preferred_formation' then nullif(p_changes->>'preferred_formation','') else c.preferred_formation end,
   preferred_style=case when p_changes?'preferred_style' then nullif(p_changes->>'preferred_style','') else c.preferred_style end,
   coaching_specialties=case when p_changes?'coaching_specialties' then p_changes->'coaching_specialties' else c.coaching_specialties end,
   license_type=case when p_changes?'license_type' then nullif(p_changes->>'license_type','') else c.license_type end,
   license_number=case when p_changes?'license_number' then nullif(p_changes->>'license_number','') else c.license_number end,
   license_issuing_body=case when p_changes?'license_issuing_body' then nullif(p_changes->>'license_issuing_body','') else c.license_issuing_body end,
   license_issue_date=case when p_changes?'license_issue_date' then nullif(p_changes->>'license_issue_date','')::date else c.license_issue_date end,
   license_expiry_date=case when p_changes?'license_expiry_date' then nullif(p_changes->>'license_expiry_date','')::date else c.license_expiry_date end,
   license_status=case when p_changes?'license_status' then nullif(p_changes->>'license_status','') else c.license_status end,
   is_active=case when p_changes?'is_active' then (p_changes->>'is_active')::boolean else c.is_active end,
   updated_at=now() where c.id=p_id returning to_jsonb(c) into v_after;
 end if;
 insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data) values(auth.uid(),p_entity,p_id,'update',v_before,v_after);
 return jsonb_build_object('saved',true,'entity',p_entity,'id',p_id,'role',v_role);
end $$;

create or replace function public.mcp_create_player(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_base_role text; v_id uuid; v_row jsonb;
begin
 select role::text into v_base_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or not (v_base_role='developer' or exists(select 1 from private.mcp_admin_role_assignments a where a.profile_id=auth.uid() and a.revoked_at is null)) then raise exception 'MCP access denied' using errcode='42501'; end if;
 if p_payload is null or jsonb_typeof(p_payload)<>'object' or nullif(trim(p_payload->>'full_name'),'') is null or nullif(p_payload->>'date_of_birth','') is null or nullif(p_payload->>'position','') is null then raise exception 'Nama, tarikh lahir dan posisi wajib diisi'; end if;
 insert into public.players(full_name,date_of_birth,position,nationality,is_active,is_demo,is_free_agent,profile_visibility,verification_status)
 values(trim(p_payload->>'full_name'),(p_payload->>'date_of_birth')::date,(p_payload->>'position')::public.player_position,coalesce(nullif(p_payload->>'nationality',''),'Malaysia'),false,false,true,'private','pending')
 returning id into v_id;
 select to_jsonb(p) into v_row from public.players p where p.id=v_id;
 insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data) values(auth.uid(),'players',v_id,'insert','{}'::jsonb,v_row);
 return jsonb_build_object('created',true,'id',v_id,'status','pending');
end $$;

create or replace function public.mcp_list_users(p_search text default '',p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role text; v_rows jsonb; v_q text:='%'||coalesce(trim(p_search),'')||'%';
begin
 select role::text into v_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or v_role<>'developer' then raise exception 'Developer access required' using errcode='42501'; end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
  select p.id,p.email,p.full_name,p.role::text role,p.is_active,p.created_at,
   exists(select 1 from private.mcp_admin_role_assignments a where a.profile_id=p.id and a.revoked_at is null) as mcp_access
  from public.profiles p where coalesce(p.email,'') ilike v_q or coalesce(p.full_name,'') ilike v_q
  order by p.created_at desc limit least(greatest(coalesce(p_limit,100),1),100)
 ) x;
 return v_rows;
end $$;

create or replace function public.mcp_set_admin_access(p_profile_id uuid,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role text; v_old public.user_role;
begin
 select role::text into v_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or v_role<>'developer' then raise exception 'Developer access required' using errcode='42501'; end if;
 if p_profile_id is null or p_profile_id=auth.uid() then raise exception 'Cannot change own access'; end if;
 select role into v_old from public.profiles where id=p_profile_id for update;
 if not found then raise exception 'User not found'; end if;
 if v_old='developer' then raise exception 'Developer role cannot be changed through Admin Access'; end if;
 if p_enabled then
  insert into private.mcp_admin_role_assignments(profile_id,previous_role,assigned_by,assigned_at,revoked_by,revoked_at)
  values(p_profile_id,v_old,auth.uid(),now(),null,null)
  on conflict(profile_id) do update set previous_role=excluded.previous_role,assigned_by=excluded.assigned_by,assigned_at=now(),revoked_by=null,revoked_at=null;
 else
  update private.mcp_admin_role_assignments set revoked_by=auth.uid(),revoked_at=now() where profile_id=p_profile_id and revoked_at is null;
 end if;
 insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data)
 values(auth.uid(),'profiles',p_profile_id,'update',
  jsonb_build_object('role',v_old::text,'mcp_access',not p_enabled),jsonb_build_object('role',v_old::text,'mcp_access',p_enabled));
 return jsonb_build_object('ok',true,'role',v_old::text,'mcp_access',p_enabled);
end $$;
