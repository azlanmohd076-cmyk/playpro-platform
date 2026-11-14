create or replace function public.playpro_account_is_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.is_active is true
  );
$function$;

revoke all on function public.playpro_account_is_active() from public, anon;
grant execute on function public.playpro_account_is_active() to authenticated, service_role;

create or replace function public.playpro_require_active_account()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null
     or not public.playpro_account_is_active() then
    raise exception 'ACCOUNT_DISABLED_OR_INACTIVE'
      using errcode = '42501';
  end if;
end;
$function$;

revoke all on function public.playpro_require_active_account() from public, anon;
grant execute on function public.playpro_require_active_account() to authenticated, service_role;

create or replace function public.playpro_is_club_manager(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select public.playpro_account_is_active()
    and exists (
      select 1
      from public.clubs c
      where c.id = p_club_id
        and (
          c.owner_profile_id = (select auth.uid())
          or c.admin_id = (select auth.uid())
          or exists (
            select 1
            from public.club_memberships m
            where m.club_id = c.id
              and m.profile_id = (select auth.uid())
              and m.role_code in ('owner','admin')
              and m.status = 'active'
          )
        )
    );
$function$;

drop policy if exists "club_memberships_manage" on public.club_memberships;
create policy "club_memberships_manage"
on public.club_memberships
for all to authenticated
using (public.playpro_is_club_manager(club_id))
with check (public.playpro_is_club_manager(club_id));

drop policy if exists "club_teams_manage" on public.club_teams;
create policy "club_teams_manage"
on public.club_teams
for all to authenticated
using (public.playpro_is_club_manager(club_id))
with check (public.playpro_is_club_manager(club_id));

drop policy if exists "profiles: developer delete" on public.profiles;
create policy "profiles: developer delete"
on public.profiles
for delete to authenticated
using (
  public.playpro_account_is_active()
  and (select public.get_my_role()) = 'developer'::public.user_role
);

drop policy if exists "profiles: developer update any" on public.profiles;
create policy "profiles: developer update any"
on public.profiles
for update to authenticated
using (
  public.playpro_account_is_active()
  and (select public.get_my_role()) = 'developer'::public.user_role
)
with check (
  public.playpro_account_is_active()
  and (select public.get_my_role()) = 'developer'::public.user_role
);

drop policy if exists "profiles: update own non-role fields" on public.profiles;
create policy "profiles: update own non-role fields"
on public.profiles
for update to authenticated
using (
  id = (select auth.uid())
  and public.playpro_account_is_active()
)
with check (
  id = (select auth.uid())
  and public.playpro_account_is_active()
);

drop policy if exists "profile_role_profiles_owner_insert" on public.profile_role_profiles;
create policy "profile_role_profiles_owner_insert"
on public.profile_role_profiles
for insert to authenticated
with check (
  profile_id = (select auth.uid())
  and public.playpro_account_is_active()
);

drop policy if exists "profile_role_profiles_owner_update" on public.profile_role_profiles;
create policy "profile_role_profiles_owner_update"
on public.profile_role_profiles
for update to authenticated
using (
  profile_id = (select auth.uid())
  and public.playpro_account_is_active()
)
with check (
  profile_id = (select auth.uid())
  and public.playpro_account_is_active()
);
