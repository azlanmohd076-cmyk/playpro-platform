create table if not exists private.account_security_audit (
  id bigint generated always as identity primary key,
  actor_profile_id uuid references public.profiles(id) on delete set null,
  subject_profile_id uuid not null references public.profiles(id) on delete restrict,
  event_type text not null check (event_type in ('account_deactivated','account_reactivated','role_restored')),
  role_code text,
  role_codes text[] not null default '{}',
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists account_security_audit_subject_created_idx
  on private.account_security_audit(subject_profile_id,created_at desc);

alter table private.account_security_audit enable row level security;
revoke all on private.account_security_audit from public, anon, authenticated;

create or replace function public.playpro_handle_account_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_roles text[] := '{}';
begin
  if old.is_active is true and new.is_active is false then
    select coalesce(array_agg(rp.role_code order by rp.role_code),'{}'::text[])
      into v_roles
    from public.profile_role_profiles rp
    where rp.profile_id=new.id and rp.is_active is true;

    update public.profile_role_profiles
       set is_active=false, updated_at=now()
     where profile_id=new.id and is_active is true;

    insert into private.account_security_audit(
      actor_profile_id,subject_profile_id,event_type,role_codes,details
    ) values (
      auth.uid(),new.id,'account_deactivated',v_roles,
      jsonb_build_object('account_is_active',false,'role_capabilities_revoked',cardinality(v_roles))
    );

  elsif old.is_active is false and new.is_active is true then
    insert into private.account_security_audit(
      actor_profile_id,subject_profile_id,event_type,details
    ) values (
      auth.uid(),new.id,'account_reactivated',
      jsonb_build_object('account_is_active',true,'role_restore_required',true)
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_playpro_account_status_change on public.profiles;
create trigger trg_playpro_account_status_change
after update of is_active on public.profiles
for each row
when (old.is_active is distinct from new.is_active)
execute function public.playpro_handle_account_status_change();

create or replace function public.playpro_restore_profile_role(
  p_profile_id uuid,
  p_role_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_updated integer;
begin
  perform public.playpro_require_active_account();
  if (select public.get_my_role()) is distinct from 'developer'::public.user_role then
    raise exception 'DEVELOPER_REQUIRED' using errcode='42501';
  end if;
  if p_profile_id is null or nullif(btrim(p_role_code),'') is null then
    raise exception 'PROFILE_AND_ROLE_REQUIRED' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id=p_profile_id and p.is_active is true
  ) then
    raise exception 'TARGET_ACCOUNT_MUST_BE_ACTIVE' using errcode='42501';
  end if;

  update public.profile_role_profiles
     set is_active=true,updated_at=now()
   where profile_id=p_profile_id
     and role_code=lower(btrim(p_role_code))
     and is_active=false;
  get diagnostics v_updated = row_count;
  if v_updated=0 then
    raise exception 'INACTIVE_ROLE_LINK_NOT_FOUND' using errcode='P0002';
  end if;

  insert into private.account_security_audit(
    actor_profile_id,subject_profile_id,event_type,role_code,details
  ) values (
    auth.uid(),p_profile_id,'role_restored',lower(btrim(p_role_code)),
    jsonb_build_object('restored_by_active_developer',true)
  );

  return jsonb_build_object('success',true,'profile_id',p_profile_id,'role_code',lower(btrim(p_role_code)));
end;
$function$;

revoke all on function public.playpro_restore_profile_role(uuid,text) from public,anon;
grant execute on function public.playpro_restore_profile_role(uuid,text) to authenticated,service_role;

create or replace function public.get_my_role()
returns public.user_role
language sql
stable
security definer
set search_path = ''
as $function$
  select case when p.is_active is true then p.role else null end
  from public.profiles p
  where p.id=(select auth.uid());
$function$;

create or replace function public.is_club_admin(club_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select public.playpro_account_is_active()
    and (
      public.get_my_role() = 'developer'::public.user_role
      or exists (
        select 1 from public.clubs c
        where c.id=club_uuid and c.admin_id=(select auth.uid())
      )
    );
$function$;

create or replace function public.is_league_admin(league_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select public.playpro_account_is_active()
    and (
      public.get_my_role() = 'developer'::public.user_role
      or exists (
        select 1 from public.leagues l
        where l.id=league_uuid and l.founder_id=(select auth.uid())
      )
      or exists (
        select 1 from public.league_staff ls
        where ls.league_id=league_uuid
          and ls.profile_id=(select auth.uid())
          and ls.role='league_admin'
      )
    );
$function$;

create or replace function public.is_league_founder_or_developer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select public.playpro_account_is_active()
    and public.get_my_role() in ('developer'::public.user_role,'league_founder'::public.user_role);
$function$;

create or replace function public.playpro_club_verification_queue()
returns table(
  club_id uuid, club_name text, club_code text, club_type text,
  verification_status text, verification_note text, owner_profile_id uuid,
  owner_name text, created_at timestamptz, member_count bigint, team_count bigint
)
language sql
stable
security definer
set search_path = ''
as $function$
  select c.id,c.name,c.club_code,c.club_type,c.verification_status,c.verification_note,
         c.owner_profile_id,p.full_name,c.created_at,
         (select count(*) from public.club_memberships m where m.club_id=c.id and m.status='active'),
         (select count(*) from public.club_teams t where t.club_id=c.id and t.status='active')
  from public.clubs c
  left join public.profiles p on p.id=c.owner_profile_id
  where exists (
    select 1 from public.profiles me
    where me.id=(select auth.uid())
      and me.role::text='developer'
      and me.is_active is true
  )
  order by case c.verification_status
    when 'under_review' then 1 when 'pending' then 2 when 'rejected' then 3
    when 'suspended' then 4 else 5 end,c.created_at desc;
$function$;

do $block$
declare
  v_def text;
  v_pos integer;
  v_oid oid;
  v_name text;
begin
  for v_name in select unnest(array['playpro_membership_lookup']) loop
    select p.oid,pg_get_functiondef(p.oid) into v_oid,v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=v_name;
    if v_oid is null then raise exception 'Function not found: %',v_name; end if;
    if position('playpro_require_active_account' in v_def)=0 then
      v_pos:=strpos(lower(v_def),'begin');
      if v_pos=0 then raise exception 'BEGIN not found in %',v_name; end if;
      v_def:=overlay(v_def placing
        'BEGIN PERFORM public.playpro_require_active_account();'
        from v_pos for 5);
      execute v_def;
    end if;
  end loop;
end;
$block$;
