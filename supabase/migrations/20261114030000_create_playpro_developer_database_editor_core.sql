-- PlayPro Developer Master Database Editor: secure live search, create and update.
create schema if not exists private;
create table if not exists private.developer_editor_audit (
  id bigserial primary key, actor_profile_id uuid not null references public.profiles(id),
  entity text not null, record_id uuid not null,
  action text not null check (action in ('insert','update')),
  before_data jsonb not null, after_data jsonb not null, changed_at timestamptz not null default now()
);
alter table private.developer_editor_audit enable row level security;
revoke all on schema private from public,anon,authenticated;
revoke all on table private.developer_editor_audit from public,anon,authenticated;

create or replace function public.developer_editor_overview()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='developer'::public.user_role and p.is_active=true) then raise exception 'Developer access required'; end if;
 select jsonb_build_object(
 'players',(select count(*) from public.players),'active_players',(select count(*) from public.players where is_active),
 'demo_players',(select count(*) from public.players where is_demo),'coaches',(select count(*) from public.coaches),
 'active_coaches',(select count(*) from public.coaches where is_active),'clubs',(select count(*) from public.clubs),
 'pending_coach_kyc',(select count(*) from public.identity_verifications where subject_type='coach' and status='pending'),
 'player_assessments',(select count(*) from public.player_assessment_records),
 'accredited_coaches',(select count(*) from public.coach_accreditations where status='active')) into v_result;
 return v_result;
end; $$;

create or replace function public.developer_editor_search(p_entity text,p_search text default '',p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_rows jsonb; v_q text:='%'||coalesce(trim(p_search),'')||'%'; v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='developer'::public.user_role and p.is_active=true) then raise exception 'Developer access required'; end if;
 if p_entity='players' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (select id,full_name,preferred_name,date_of_birth,position::text position,nationality,club_id,is_active,is_demo,demo_level,verification_status,football_passport_no,created_at from public.players where coalesce(full_name,'') ilike v_q or coalesce(preferred_name,'') ilike v_q or coalesce(football_passport_no,'') ilike v_q order by created_at desc limit v_limit)x;
 elsif p_entity='coaches' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (select c.id,c.profile_id,c.full_name,c.preferred_name,c.coaching_role,c.license_type,c.license_status,c.verification_status,c.is_active,c.coach_code,c.club_id,a.accreditation_level,a.status assessor_status from public.coaches c left join public.coach_accreditations a on a.coach_profile_id=c.profile_id where coalesce(c.full_name,'') ilike v_q or coalesce(c.preferred_name,'') ilike v_q or coalesce(c.coach_code,'') ilike v_q order by c.created_at desc limit v_limit)x;
 elsif p_entity='clubs' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (select id,name,club_code,club_type,city,state,country,home_venue,verification_status,visibility,created_at from public.clubs where coalesce(name,'') ilike v_q or coalesce(club_code,'') ilike v_q or coalesce(city,'') ilike v_q order by created_at desc limit v_limit)x;
 elsif p_entity='assessments' then
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (select a.id,a.player_id,p.full_name player_name,a.coach_profile_id,co.full_name coach_name,a.accreditation_level,a.assessed_at,a.notes from public.player_assessment_records a join public.players p on p.id=a.player_id left join public.coaches co on co.profile_id=a.coach_profile_id where coalesce(p.full_name,'') ilike v_q or coalesce(co.full_name,'') ilike v_q order by a.assessed_at desc limit v_limit)x;
 else raise exception 'Unsupported editor entity'; end if;
 return v_rows;
end; $$;

create or replace function public.developer_editor_update(p_entity text,p_id uuid,p_changes jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_before jsonb; v_after jsonb; v_updated_at timestamptz;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='developer'::public.user_role and p.is_active=true) then raise exception 'Developer access required'; end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'object' or p_changes='{}'::jsonb then raise exception 'No changes supplied'; end if;
 if p_entity='players' then
  select to_jsonb(t) into v_before from public.players t where t.id=p_id; if v_before is null then raise exception 'Player not found'; end if;
  update public.players t set full_name=case when p_changes?'full_name' then nullif(p_changes->>'full_name','') else t.full_name end,
  preferred_name=case when p_changes?'preferred_name' then nullif(p_changes->>'preferred_name','') else t.preferred_name end,
  nationality=case when p_changes?'nationality' then nullif(p_changes->>'nationality','') else t.nationality end,
  is_active=case when p_changes?'is_active' then (p_changes->>'is_active')::boolean else t.is_active end,
  is_free_agent=case when p_changes?'is_free_agent' then (p_changes->>'is_free_agent')::boolean else t.is_free_agent end,
  updated_at=now() where t.id=p_id returning t.updated_at,to_jsonb(t) into v_updated_at,v_after;
 elsif p_entity='coaches' then
  select to_jsonb(t) into v_before from public.coaches t where t.id=p_id; if v_before is null then raise exception 'Coach not found'; end if;
  update public.coaches t set full_name=case when p_changes?'full_name' then nullif(p_changes->>'full_name','') else t.full_name end,
  preferred_name=case when p_changes?'preferred_name' then nullif(p_changes->>'preferred_name','') else t.preferred_name end,
  bio=case when p_changes?'bio' then nullif(p_changes->>'bio','') else t.bio end,
  coaching_role=case when p_changes?'coaching_role' then nullif(p_changes->>'coaching_role','') else t.coaching_role end,
  license_number=case when p_changes?'license_number' then nullif(p_changes->>'license_number','') else t.license_number end,
  license_status=case when p_changes?'license_status' then nullif(p_changes->>'license_status','') else t.license_status end,
  is_active=case when p_changes?'is_active' then (p_changes->>'is_active')::boolean else t.is_active end,
  updated_at=now() where t.id=p_id returning t.updated_at,to_jsonb(t) into v_updated_at,v_after;
 elsif p_entity='clubs' then
  select to_jsonb(t) into v_before from public.clubs t where t.id=p_id; if v_before is null then raise exception 'Club not found'; end if;
  update public.clubs t set name=case when p_changes?'name' then nullif(p_changes->>'name','') else t.name end,
  description=case when p_changes?'description' then nullif(p_changes->>'description','') else t.description end,
  city=case when p_changes?'city' then nullif(p_changes->>'city','') else t.city end,
  state=case when p_changes?'state' then nullif(p_changes->>'state','') else t.state end,
  country=case when p_changes?'country' then nullif(p_changes->>'country','') else t.country end,
  home_venue=case when p_changes?'home_venue' then nullif(p_changes->>'home_venue','') else t.home_venue end,
  colours=case when p_changes?'colours' then nullif(p_changes->>'colours','') else t.colours end,
  updated_at=now() where t.id=p_id returning t.updated_at,to_jsonb(t) into v_updated_at,v_after;
 else raise exception 'Updates are not enabled for this entity'; end if;
 insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data) values(auth.uid(),p_entity,p_id,'update',v_before,v_after);
 return jsonb_build_object('entity',p_entity,'id',p_id,'updated_at',v_updated_at,'saved',true);
end; $$;

create or replace function public.developer_editor_create(p_entity text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_row jsonb;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='developer'::public.user_role and p.is_active=true) then raise exception 'Developer access required'; end if;
 if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Invalid payload'; end if;
 if p_entity='players' then
  if nullif(trim(p_payload->>'full_name'),'') is null or nullif(p_payload->>'date_of_birth','') is null or nullif(p_payload->>'position','') is null then raise exception 'Nama, tarikh lahir dan posisi wajib diisi'; end if;
  insert into public.players(full_name,date_of_birth,position,nationality,preferred_foot,is_active,is_demo,is_free_agent,profile_visibility,verification_status)
  values(trim(p_payload->>'full_name'),(p_payload->>'date_of_birth')::date,(p_payload->>'position')::public.player_position,nullif(p_payload->>'nationality',''),nullif(p_payload->>'preferred_foot','')::public.preferred_foot,false,false,true,'private','pending') returning id into v_id;
  select to_jsonb(p) into v_row from public.players p where p.id=v_id;
 elsif p_entity='clubs' then
  if nullif(trim(p_payload->>'name'),'') is null then raise exception 'Nama kelab wajib diisi'; end if;
  insert into public.clubs(name,city,state,country,home_venue,description,verification_status,visibility)
  values(trim(p_payload->>'name'),nullif(p_payload->>'city',''),nullif(p_payload->>'state',''),coalesce(nullif(p_payload->>'country',''),'Malaysia'),nullif(p_payload->>'home_venue',''),nullif(p_payload->>'description',''),'pending','private') returning id into v_id;
  select to_jsonb(c) into v_row from public.clubs c where c.id=v_id;
 else raise exception 'Creation is not enabled for this entity'; end if;
 insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data) values(auth.uid(),p_entity,v_id,'insert','{}'::jsonb,v_row);
 return jsonb_build_object('entity',p_entity,'id',v_id,'created',true,'status','pending');
end; $$;

revoke all on function public.developer_editor_overview() from public,anon;
revoke all on function public.developer_editor_search(text,text,integer) from public,anon;
revoke all on function public.developer_editor_update(text,uuid,jsonb) from public,anon;
revoke all on function public.developer_editor_create(text,jsonb) from public,anon;
grant execute on function public.developer_editor_overview() to authenticated;
grant execute on function public.developer_editor_search(text,text,integer) to authenticated;
grant execute on function public.developer_editor_update(text,uuid,jsonb) to authenticated;
grant execute on function public.developer_editor_create(text,jsonb) to authenticated;
