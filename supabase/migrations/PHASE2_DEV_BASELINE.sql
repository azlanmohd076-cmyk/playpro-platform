-- PlayPro Phase 2 Development Baseline
-- DESIGN/REVIEW ONLY. DO NOT RUN AGAINST PRODUCTION.
-- Generated from docs/PLAYPRO_PHASE2_SCHEMA_SPEC_v1.md
-- Strategy: additive-first, compatibility-first, no destructive DDL.

begin;

create extension if not exists pgcrypto;

-- ============================================================
-- 1. Identity / capability
-- ============================================================

create table if not exists public.user_capabilities (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  capability text not null check (capability in (
    'player','coach','referee','club_admin','organizer','match_observer',
    'competition_admin','technical_assessor','developer'
  )),
  status text not null default 'active' check (status in ('active','suspended','revoked')),
  granted_by uuid null references public.profiles(id),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id, capability)
);

create index if not exists idx_user_capabilities_profile_status
  on public.user_capabilities(profile_id, status);
create index if not exists idx_user_capabilities_capability_status
  on public.user_capabilities(capability, status);

create table if not exists public.verification_cases (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  verification_type text not null default 'identity',
  status text not null default 'not_required' check (status in (
    'not_required','required','submitted','in_review','verified','rejected','resubmission','revoked'
  )),
  document_type text null,
  document_last4 text null,
  submitted_at timestamptz null,
  reviewed_at timestamptz null,
  reviewed_by uuid null references public.profiles(id),
  rejection_reason text null,
  expires_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_verification_cases_profile_status
  on public.verification_cases(profile_id, status);

-- ============================================================
-- 2. Player history / identity representations
-- ============================================================

create table if not exists public.player_club_memberships (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,
  membership_type text not null default 'player' check (membership_type in ('player','trial','academy','loan','guest')),
  shirt_number integer null,
  start_date date not null,
  end_date date null,
  status text not null default 'active' check (status in ('active','ended','suspended')),
  source text null,
  created_by uuid null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);

create index if not exists idx_player_club_memberships_player
  on public.player_club_memberships(player_id, status, start_date desc);
create index if not exists idx_player_club_memberships_club
  on public.player_club_memberships(club_id, status);

create table if not exists public.player_cards (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null unique references public.players(id) on delete cascade,
  card_number text not null unique,
  qr_token_hash text not null unique,
  status text not null default 'active' check (status in ('active','suspended','revoked')),
  issued_at timestamptz not null default now(),
  expires_at timestamptz null,
  last_issued_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.player_passports (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null unique references public.players(id) on delete cascade,
  passport_number text not null unique,
  status text not null default 'active' check (status in ('active','suspended','revoked')),
  issued_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.player_passport_entries (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players(id) on delete cascade,
  entry_type text not null check (entry_type in ('club','competition','assessment','match','award','discipline','development')),
  club_id uuid null references public.clubs(id),
  competition_id uuid null references public.leagues(id),
  fixture_id uuid null references public.fixtures(id),
  source_id uuid null,
  event_date timestamptz null,
  title text not null,
  summary text null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_player_passport_entries_player_date
  on public.player_passport_entries(player_id, event_date desc);
create index if not exists idx_player_passport_entries_type_date
  on public.player_passport_entries(entry_type, event_date desc);

-- ============================================================
-- 3. Club staff relationships
-- ============================================================

create table if not exists public.club_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  membership_type text not null check (membership_type in ('admin','manager','staff','coach','medical','observer')),
  status text not null default 'active' check (status in ('active','ended','suspended')),
  start_at timestamptz not null default now(),
  end_at timestamptz null,
  created_by uuid null references public.profiles(id),
  created_at timestamptz not null default now(),
  check (end_at is null or end_at >= start_at)
);

create unique index if not exists uq_club_members_active
  on public.club_members(club_id, profile_id, membership_type)
  where status = 'active';

-- ============================================================
-- 4. Competition compatibility layer
-- Existing leagues table remains canonical storage during transition.
-- ============================================================

alter table public.leagues add column if not exists competition_type text not null default 'league';
alter table public.leagues add column if not exists visibility text not null default 'public';
alter table public.leagues add column if not exists official_status text not null default 'unofficial';
alter table public.leagues add column if not exists organizer_type text null;
alter table public.leagues add column if not exists organizer_profile_id uuid null references public.profiles(id);
alter table public.leagues add column if not exists rules jsonb not null default '{}'::jsonb;
alter table public.leagues add column if not exists format_config jsonb not null default '{}'::jsonb;
alter table public.leagues add column if not exists start_date date null;
alter table public.leagues add column if not exists end_date date null;

create table if not exists public.competition_staff (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.leagues(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  assignment_type text not null check (assignment_type in ('organizer','admin','developer','match_observer','technical_assessor','discipline_admin')),
  status text not null default 'active' check (status in ('active','revoked')),
  appointed_by uuid null references public.profiles(id),
  appointed_at timestamptz not null default now(),
  revoked_at timestamptz null,
  unique (competition_id, profile_id, assignment_type)
);

create index if not exists idx_competition_staff_competition_status
  on public.competition_staff(competition_id, status);

create table if not exists public.competition_clubs (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.leagues(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','rejected','withdrawn')),
  approved_by uuid null references public.profiles(id),
  approved_at timestamptz null,
  joined_at timestamptz not null default now(),
  seed integer null,
  group_code text null,
  created_at timestamptz not null default now(),
  unique (competition_id, club_id)
);

create index if not exists idx_competition_clubs_status
  on public.competition_clubs(competition_id, status);

create table if not exists public.competition_player_registrations (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.leagues(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,
  registration_status text not null default 'pending' check (registration_status in ('pending','approved','rejected','withdrawn')),
  shirt_number integer null,
  registered_at timestamptz not null default now(),
  approved_by uuid null references public.profiles(id),
  approved_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  unique (competition_id, player_id)
);

create index if not exists idx_comp_player_reg_comp_club_status
  on public.competition_player_registrations(competition_id, club_id, registration_status);
create index if not exists idx_comp_player_reg_player_status
  on public.competition_player_registrations(player_id, registration_status);

create table if not exists public.competition_formats (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null unique references public.leagues(id) on delete cascade,
  format_type text not null,
  group_count integer null,
  teams_per_group integer null,
  legs integer not null default 1 check (legs > 0),
  points_win integer not null default 3,
  points_draw integer not null default 1,
  points_loss integer not null default 0,
  tie_breakers jsonb not null default '["points","goal_difference","goals_for"]'::jsonb,
  progression_rules jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 5. Matchday source-of-truth layer
-- ============================================================

alter table public.fixtures add column if not exists match_state text not null default 'scheduled';
alter table public.fixtures add column if not exists period_length_minutes integer not null default 45;
alter table public.fixtures add column if not exists extra_time_allowed boolean not null default false;
alter table public.fixtures add column if not exists group_code text null;
alter table public.fixtures add column if not exists bracket_node jsonb null;

create table if not exists public.match_participants (
  id uuid primary key default gen_random_uuid(),
  fixture_id uuid not null references public.fixtures(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete restrict,
  club_id uuid not null references public.clubs(id) on delete restrict,
  squad_status text not null default 'selected' check (squad_status in ('selected','starter','substitute','unused','withdrawn')),
  jersey_number integer null,
  position_at_match player_position null,
  eligibility_snapshot jsonb not null default '{}'::jsonb,
  registered_by uuid null references public.profiles(id),
  registered_at timestamptz not null default now(),
  unique (fixture_id, player_id)
);

create index if not exists idx_match_participants_fixture_club
  on public.match_participants(fixture_id, club_id);
create index if not exists idx_match_participants_player
  on public.match_participants(player_id, fixture_id);

create unique index if not exists uq_match_participants_jersey
  on public.match_participants(fixture_id, club_id, jersey_number)
  where jersey_number is not null;

create table if not exists public.match_admin_assignments (
  id uuid primary key default gen_random_uuid(),
  fixture_id uuid not null references public.fixtures(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  assignment_type text not null check (assignment_type in ('match_observer','match_admin','referee')),
  status text not null default 'active' check (status in ('active','revoked')),
  appointed_by uuid null references public.profiles(id),
  appointed_at timestamptz not null default now(),
  revoked_at timestamptz null,
  unique (fixture_id, profile_id, assignment_type)
);

create index if not exists idx_match_admin_assignments_fixture_status
  on public.match_admin_assignments(fixture_id, status);

create table if not exists public.match_events (
  id uuid primary key default gen_random_uuid(),
  fixture_id uuid not null references public.fixtures(id) on delete cascade,
  competition_id uuid null references public.leagues(id),
  event_type text not null check (event_type in (
    'MATCH_START','MATCH_END','PLAYER_START','SUBSTITUTION_IN','SUBSTITUTION_OUT',
    'GOAL','ASSIST','YELLOW_CARD','RED_CARD','SHOT','SHOT_ON_TARGET','SAVE',
    'CORNER','FOUL','OFFSIDE','PENALTY_TAKEN','PENALTY_SCORED','MOTM','OTHER'
  )),
  period integer null,
  minute integer null,
  second integer null,
  club_id uuid null references public.clubs(id),
  player_id uuid null references public.players(id),
  related_player_id uuid null references public.players(id),
  sequence bigint not null,
  recorded_by uuid not null references public.profiles(id),
  recorded_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  voided_at timestamptz null,
  voided_by uuid null references public.profiles(id),
  void_reason text null,
  unique (fixture_id, sequence),
  check (minute is null or minute >= 0),
  check (second is null or (second >= 0 and second < 60))
);

create index if not exists idx_match_events_fixture_sequence
  on public.match_events(fixture_id, sequence);
create index if not exists idx_match_events_player_time
  on public.match_events(player_id, recorded_at);
create index if not exists idx_match_events_type
  on public.match_events(event_type, recorded_at);

create table if not exists public.match_playing_time (
  id uuid primary key default gen_random_uuid(),
  fixture_id uuid not null references public.fixtures(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete restrict,
  start_event_id uuid null references public.match_events(id),
  end_event_id uuid null references public.match_events(id),
  start_minute integer not null,
  end_minute integer null,
  minutes_played numeric(7,2) not null default 0,
  calculation_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (fixture_id, player_id, start_event_id)
);

create index if not exists idx_match_playing_time_player
  on public.match_playing_time(player_id, fixture_id);
create index if not exists idx_match_playing_time_fixture
  on public.match_playing_time(fixture_id, club_id);

-- ============================================================
-- 6. DNA provenance foundation
-- ============================================================

create table if not exists public.player_dna_snapshots (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players(id) on delete cascade,
  source_type text not null check (source_type in ('assessment','match','training','manual','system')),
  source_id uuid null,
  dna_overall numeric(6,2) null,
  dna_technical numeric(6,2) null,
  dna_physical numeric(6,2) null,
  dna_mental numeric(6,2) null,
  dna_tactical numeric(6,2) null,
  band text null,
  calculation_version integer not null default 1,
  effective_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_player_dna_player_effective
  on public.player_dna_snapshots(player_id, effective_at desc);

-- ============================================================
-- 7. RLS baseline
-- ============================================================

alter table public.user_capabilities enable row level security;
alter table public.verification_cases enable row level security;
alter table public.player_club_memberships enable row level security;
alter table public.player_cards enable row level security;
alter table public.player_passports enable row level security;
alter table public.player_passport_entries enable row level security;
alter table public.club_members enable row level security;
alter table public.competition_staff enable row level security;
alter table public.competition_clubs enable row level security;
alter table public.competition_player_registrations enable row level security;
alter table public.competition_formats enable row level security;
alter table public.match_participants enable row level security;
alter table public.match_admin_assignments enable row level security;
alter table public.match_events enable row level security;
alter table public.match_playing_time enable row level security;
alter table public.player_dna_snapshots enable row level security;

-- Policies are intentionally NOT created in this baseline.
-- They require the Phase 3 security contract and must be written only after
-- function/capability semantics are verified. This prevents accidental broad access.

-- ============================================================
-- 8. Explicitly deferred
-- ============================================================
-- No destructive rename/drop.
-- No production execution.
-- No training/development intelligence tables yet.
-- No broad public policies.
-- No automatic DNA triggers yet.
-- No replacement of existing standings/suspension triggers yet.

commit;
