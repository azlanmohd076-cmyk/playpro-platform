begin;
create table if not exists public.coach_certification_requests (
 id uuid primary key default gen_random_uuid(),
 coach_id uuid not null references public.coaches(id) on delete cascade,
 track text not null check (track in ('player_assessment_authority','coach_attribute_certification')),
 requested_level integer not null check (requested_level between 1 and 5),
 note text,
 status text not null default 'pending' check (status in ('pending','approved','rejected','withdrawn')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.coach_certification_requests enable row level security;
drop policy if exists coach_certification_requests_owner_read on public.coach_certification_requests;
create policy coach_certification_requests_owner_read on public.coach_certification_requests for select to authenticated using (exists(select 1 from public.coaches c where c.id=coach_id and c.profile_id=auth.uid()));
drop policy if exists coach_certification_requests_owner_insert on public.coach_certification_requests;
create policy coach_certification_requests_owner_insert on public.coach_certification_requests for insert to authenticated with check (exists(select 1 from public.coaches c where c.id=coach_id and c.profile_id=auth.uid()));
commit;
