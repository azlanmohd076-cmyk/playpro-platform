-- PlayPro accredited coach assessment workflow.
-- Applied to production on 2026-11-14. Official assessment is separate
-- from demo fixtures and from player identity/KYC verification.

create table if not exists public.coach_accreditations (
 id uuid primary key default gen_random_uuid(),
 coach_profile_id uuid not null unique references public.profiles(id) on delete cascade,
 accreditation_level smallint not null check(accreditation_level between 1 and 7),
 status text not null default 'active' check(status in ('active','suspended','revoked')),
 accredited_at timestamptz not null default now(),
 expires_at timestamptz,
 accredited_by uuid not null references public.profiles(id),
 notes text, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(expires_at is null or expires_at>accredited_at)
);
create index if not exists coach_accreditations_active_idx on public.coach_accreditations(coach_profile_id,status,expires_at);
alter table public.coach_accreditations enable row level security;
drop policy if exists coach_accreditations_read_own_or_developer on public.coach_accreditations;
create policy coach_accreditations_read_own_or_developer on public.coach_accreditations
 for select to authenticated using(coach_profile_id=(select auth.uid()) or (select public.get_my_role())='developer');
revoke all on public.coach_accreditations from anon,authenticated;
grant select on public.coach_accreditations to authenticated;

create table if not exists public.player_assessment_records (
 id uuid primary key default gen_random_uuid(),
 player_id uuid not null references public.players(id) on delete cascade,
 coach_profile_id uuid not null references public.profiles(id),
 accreditation_level smallint not null check(accreditation_level between 1 and 7),
 attributes jsonb not null,
 notes text, assessed_at timestamptz not null default now(),
 constraint player_assessment_records_all_18 check (
  jsonb_typeof(attributes)='object' and attributes ?& array[
   'passing','dribbling','finishing','first_touch','tackling','heading',
   'pace','stamina','strength','agility','leadership','composure','teamwork',
   'work_rate','positioning','vision','decision_making','anticipation'])
 )
);
create index if not exists player_assessment_records_player_date_idx on public.player_assessment_records(player_id,assessed_at desc);
alter table public.player_assessment_records enable row level security;
drop policy if exists assessment_records_read_authenticated on public.player_assessment_records;
create policy assessment_records_read_authenticated on public.player_assessment_records
 for select to authenticated using(
  coach_profile_id=(select auth.uid()) or (select public.get_my_role())='developer'
  or exists(select 1 from public.players p where p.id=player_assessment_records.player_id and p.profile_id=(select auth.uid()))
 );
revoke all on public.player_assessment_records from anon,authenticated;
grant select on public.player_assessment_records to authenticated;

-- Legacy table has incompatible attribute names and permissive RLS policies.
drop policy if exists "Membenarkan bacaan penilaian" on public.player_assessments;
drop policy if exists "Membenarkan technical_assessor membuat penilaian" on public.player_assessments;
drop policy if exists "player_assessments: assessor insert" on public.player_assessments;
drop policy if exists "player_assessments: assessor or developer update" on public.player_assessments;
drop policy if exists "player_assessments: public read" on public.player_assessments;
revoke all on public.player_assessments from anon,authenticated;

create or replace function public.set_coach_accreditation(
 p_coach_profile_id uuid,p_level smallint,p_status text default 'active',
 p_expires_at timestamptz default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_admin uuid := (select auth.uid());
begin
 if v_admin is null or (select public.get_my_role()) is distinct from 'developer'::public.user_role then
  raise exception 'FORBIDDEN: only PlayPro Developer can manage coach accreditation';
 end if;
 if p_status not in ('active','suspended','revoked') then raise exception 'Invalid accreditation status'; end if;
 if p_status='active' and (p_level is null or p_level not between 1 and 7) then raise exception 'Accreditation level must be 1–7'; end if;
 if not exists(select 1 from public.profiles where id=p_coach_profile_id and is_active=true) then raise exception 'Coach profile not found or inactive'; end if;
 update public.profiles set role='technical_assessor'::public.user_role,updated_at=now() where id=p_coach_profile_id;
 insert into public.coach_accreditations(coach_profile_id,accreditation_level,status,accredited_at,expires_at,accredited_by,notes,updated_at)
 values(p_coach_profile_id,coalesce(p_level,1),p_status,now(),p_expires_at,v_admin,nullif(btrim(p_notes),''),now())
 on conflict(coach_profile_id) do update set accreditation_level=excluded.accreditation_level,status=excluded.status,
  accredited_at=case when excluded.status='active' then now() else public.coach_accreditations.accredited_at end,
  expires_at=excluded.expires_at,accredited_by=excluded.accredited_by,notes=excluded.notes,updated_at=now();
 return jsonb_build_object('ok',true,'coach_profile_id',p_coach_profile_id,'level',p_level,'status',p_status);
end $$;
revoke all on function public.set_coach_accreditation(uuid,smallint,text,timestamptz,text) from public,anon,authenticated;
grant execute on function public.set_coach_accreditation(uuid,smallint,text,timestamptz,text) to authenticated;

create or replace function public.get_assessment_workspace()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid := (select auth.uid()); v_level smallint; v_players jsonb;
begin
 if v_uid is null
  or not exists(select 1 from public.profiles pr where pr.id=v_uid and pr.is_active=true and pr.role='technical_assessor')
  or not exists(select 1 from public.coach_accreditations ca where ca.coach_profile_id=v_uid and ca.status='active'
    and (ca.expires_at is null or ca.expires_at>now()) and ca.accreditation_level between 1 and 7) then
  raise exception 'FORBIDDEN: active PlayPro coach accreditation Level 1–7 required';
 end if;
 select accreditation_level into v_level from public.coach_accreditations where coach_profile_id=v_uid and status='active'
  and (expires_at is null or expires_at>now());
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'full_name',case when p.display_name_mode='legal' then p.full_name else coalesce(nullif(btrim(p.preferred_name),''),p.full_name) end,
  'position',p.position::text,'club_name',c.name,'assessment_source',coalesce(s.source,'none'),
  'assessed_count',(select count(*) from jsonb_each(to_jsonb(s)-'player_id'-'source'-'confidence'-'updated_at') e where e.value<>'null'::jsonb)
 ) order by p.full_name),'[]'::jsonb) into v_players
 from public.players p left join public.clubs c on c.id=p.club_id left join public.player_attribute_state s on s.player_id=p.id
 where p.is_active=true and coalesce(p.is_demo,false)=false;
 return jsonb_build_object('ok',true,'coach_level',v_level,'players',v_players);
end $$;
revoke all on function public.get_assessment_workspace() from public,anon,authenticated;
grant execute on function public.get_assessment_workspace() to authenticated;

create or replace function public.submit_player_assessment(p_player_id uuid,p_attributes jsonb,p_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid := (select auth.uid()); v_level smallint;
 v_keys text[] := array['passing','dribbling','finishing','first_touch','tackling','heading','pace','stamina','strength','agility','leadership','composure','teamwork','work_rate','positioning','vision','decision_making','anticipation'];
 v_key text; v_value numeric;
begin
 if v_uid is null
  or not exists(select 1 from public.profiles pr where pr.id=v_uid and pr.is_active=true and pr.role='technical_assessor')
  or not exists(select 1 from public.coach_accreditations ca where ca.coach_profile_id=v_uid and ca.status='active'
   and (ca.expires_at is null or ca.expires_at>now()) and ca.accreditation_level between 1 and 7) then
  raise exception 'FORBIDDEN: only active PlayPro accredited coaches Level 1–7 may submit assessments';
 end if;
 select accreditation_level into v_level from public.coach_accreditations where coach_profile_id=v_uid and status='active'
  and (expires_at is null or expires_at>now());
 if not exists(select 1 from public.players where id=p_player_id and is_active=true and coalesce(is_demo,false)=false) then
  raise exception 'Player not found or demo fixtures cannot receive official assessments';
 end if;
 if p_attributes is null or jsonb_typeof(p_attributes)<>'object' or (select count(*) from jsonb_object_keys(p_attributes))<>18 then
  raise exception 'Exactly 18 attributes are required';
 end if;
 foreach v_key in array v_keys loop
  if not(p_attributes?v_key) then raise exception 'Missing attribute: %',v_key; end if;
  if jsonb_typeof(p_attributes->v_key)<>'number' then raise exception 'Attribute % must be numeric',v_key; end if;
  v_value:=(p_attributes->>v_key)::numeric;
  if v_value<>trunc(v_value) or v_value<1 or v_value>20 then raise exception 'Attribute % must be an integer from 1 to 20',v_key; end if;
 end loop;
 insert into public.player_assessment_records(player_id,coach_profile_id,accreditation_level,attributes,notes)
 values(p_player_id,v_uid,v_level,p_attributes,nullif(btrim(p_notes),''));
 insert into public.player_attribute_state(player_id,passing,dribbling,finishing,first_touch,tackling,heading,
  pace,stamina,strength,agility,leadership,composure,teamwork,work_rate,positioning,vision,decision_making,anticipation,source,confidence,updated_at)
 values(p_player_id,(p_attributes->>'passing')::smallint,(p_attributes->>'dribbling')::smallint,
  (p_attributes->>'finishing')::smallint,(p_attributes->>'first_touch')::smallint,(p_attributes->>'tackling')::smallint,
  (p_attributes->>'heading')::smallint,(p_attributes->>'pace')::smallint,(p_attributes->>'stamina')::smallint,
  (p_attributes->>'strength')::smallint,(p_attributes->>'agility')::smallint,(p_attributes->>'leadership')::smallint,
  (p_attributes->>'composure')::smallint,(p_attributes->>'teamwork')::smallint,(p_attributes->>'work_rate')::smallint,
  (p_attributes->>'positioning')::smallint,(p_attributes->>'vision')::smallint,(p_attributes->>'decision_making')::smallint,
  (p_attributes->>'anticipation')::smallint,'coach_assessment',100,now())
 on conflict(player_id) do update set passing=excluded.passing,dribbling=excluded.dribbling,finishing=excluded.finishing,
  first_touch=excluded.first_touch,tackling=excluded.tackling,heading=excluded.heading,pace=excluded.pace,stamina=excluded.stamina,
  strength=excluded.strength,agility=excluded.agility,leadership=excluded.leadership,composure=excluded.composure,
  teamwork=excluded.teamwork,work_rate=excluded.work_rate,positioning=excluded.positioning,vision=excluded.vision,
  decision_making=excluded.decision_making,anticipation=excluded.anticipation,source='coach_assessment',confidence=100,updated_at=now();
 return jsonb_build_object('ok',true,'player_id',p_player_id,'coach_level',v_level,'attributes_count',18,'assessed_at',now());
end $$;
revoke all on function public.submit_player_assessment(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.submit_player_assessment(uuid,jsonb,text) to authenticated;
