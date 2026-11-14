drop policy if exists "league_clubs: authenticated insert" on public.league_clubs;
drop policy if exists "league_clubs: club admin insert" on public.league_clubs;
drop policy if exists "league_clubs: club manager verified insert" on public.league_clubs;

create policy "league_clubs: club manager verified insert"
on public.league_clubs
for insert
to authenticated
with check (
  approved is false
  and approved_by is null
  and approved_at is null
  and exists (
    select 1 from public.clubs c
    where c.id = league_clubs.club_id
      and c.verification_status = 'verified'
  )
  and (
    public.playpro_is_club_manager(club_id)
    or (select public.get_my_role()) = 'developer'::public.user_role
  )
);

comment on policy "league_clubs: club manager verified insert"
on public.league_clubs is
'Only an active club manager (or active Developer) may submit a verified club to a league. Submission must remain pending; submitters cannot self-approve.';
