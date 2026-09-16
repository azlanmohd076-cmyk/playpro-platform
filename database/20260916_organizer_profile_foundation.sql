-- PlayPro Organizer Profile Foundation
-- Applied to production playpro2 as organizer_profile_foundation.

create table if not exists public.organizers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  organizer_code text not null unique,
  organizer_type text not null default 'individual',
  display_name text not null,
  legal_name text,
  description text,
  phone text,
  whatsapp text,
  email text,
  logo_url text,
  city text,
  state text,
  country text not null default 'Malaysia',
  profile_visibility text not null default 'public',
  verification_status text not null default 'pending',
  verified_at timestamptz,
  verified_by uuid references public.profiles(id),
  profile_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organizers_visibility_check check (profile_visibility in ('public','followers','private')),
  constraint organizers_verification_check check (verification_status in ('pending','verified','rejected','suspended')),
  constraint organizers_type_check check (organizer_type in ('individual','club','academy','school','university','company','ngo','association','government','community','other'))
);

create index if not exists idx_organizers_profile_id on public.organizers(profile_id);
create index if not exists idx_organizers_verification on public.organizers(verification_status);

insert into public.profile_role_profiles(profile_id, role_code, subject_id)
select o.profile_id, 'organizer', o.id
from public.organizers o
where not exists (
  select 1 from public.profile_role_profiles r
  where r.profile_id=o.profile_id and r.role_code='organizer'
);

create or replace function public.create_organizer_profile(
  p_organizer_type text,
  p_display_name text,
  p_description text default null,
  p_phone text default null,
  p_whatsapp text default null,
  p_email text default null,
  p_city text default null,
  p_state text default null
) returns uuid
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_profile uuid := auth.uid();
  v_id uuid;
  v_code text;
  v_verified boolean;
begin
  if v_profile is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select exists(select 1 from public.identity_verifications iv where iv.profile_id=v_profile and iv.subject_type='organizer' and iv.status='verified') into v_verified;
  if not v_verified then raise exception 'Organizer KYC verification is required before profile creation' using errcode='42501'; end if;
  if p_display_name is null or btrim(p_display_name)='' then raise exception 'Organizer display name is required'; end if;
  if exists(select 1 from public.organizers where profile_id=v_profile) then raise exception 'Organizer profile already exists'; end if;
  v_code := 'ORG-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into public.organizers(profile_id,organizer_code,organizer_type,display_name,description,phone,whatsapp,email,city,state,verification_status,profile_completed_at)
  values(v_profile,v_code,p_organizer_type,btrim(p_display_name),p_description,p_phone,p_whatsapp,p_email,p_city,p_state,'pending',now()) returning id into v_id;
  insert into public.profile_role_profiles(profile_id,role_code,subject_id) values(v_profile,'organizer',v_id)
  on conflict (profile_id,role_code) do update set subject_id=excluded.subject_id,is_active=true,updated_at=now();
  return v_id;
end; $$;

alter table public.organizers enable row level security;
drop policy if exists organizers_public_read on public.organizers;
create policy organizers_public_read on public.organizers for select using (profile_visibility='public' or profile_id=auth.uid());
drop policy if exists organizers_owner_update on public.organizers;
create policy organizers_owner_update on public.organizers for update using (profile_id=auth.uid()) with check (profile_id=auth.uid());
revoke insert,delete on public.organizers from anon,authenticated;
grant select,update on public.organizers to authenticated;
revoke execute on function public.create_organizer_profile(text,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.create_organizer_profile(text,text,text,text,text,text,text,text) to authenticated;

drop trigger if exists trg_organizers_updated_at on public.organizers;
create trigger trg_organizers_updated_at before update on public.organizers for each row execute function public.update_updated_at();
