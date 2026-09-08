# PlayPro Phase 2 — Canonical Schema Specification v1

**Status:** Design / reconciliation only — NO production schema changes
**Branch:** `phase-2/canonical-model`
**Purpose:** Convert the approved canonical model into an implementable table, column, constraint, index, RPC, trigger and view contract. This document is the gate before migration SQL.

---

## 0. Governing rules

1. Do not rebuild the database from old architecture claims (for example 85 tables) without evidence.
2. Existing active football-core tables are evolved where practical; compatibility is preferred over destructive renaming.
3. `LIVE EVENT -> VALIDATED EVENT STORE -> DERIVED DATA` is the source-of-truth rule for match data.
4. A frontend role string is never an authorization boundary.
5. KYC is a protected-action gate, not an authority grant.
6. Player Card is an identity representation of `players.id`, never a second player record.
7. Club membership and competition registration are historical relationships.
8. Derived statistics must not be independently editable by ordinary application clients.
9. Corrections to live events are auditable (`void/correct`), not silent history mutation.
10. Migrations are additive-first; no production DDL is authorized by this document.

---

# 1. Canonical identity and capability layer

## 1.1 `profiles` — KEEP / EVOLVE

Existing table remains the application profile linked to Supabase Auth.

### Canonical columns

- `id uuid PK` — equals authenticated user id.
- `full_name text NOT NULL`
- `email text NOT NULL`
- `role user_role` — **legacy compatibility only**, not the long-term authorization source.
- `avatar_url text NULL`
- `phone text NULL`
- `is_active boolean NOT NULL DEFAULT true`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

### Required evolution

- Do not use `role` for capability authorization.
- Identity/KYC document data must not be written to a nonexistent `identification_number` column. KYC data belongs in the verification domain.
- Add unique/index strategy for normalized email only if compatible with existing Auth/profile lifecycle.

---

## 1.2 `user_capabilities` — NEW

One user may hold multiple capabilities.

### Columns

- `id uuid PK DEFAULT gen_random_uuid()`
- `profile_id uuid NOT NULL FK profiles.id`
- `capability text NOT NULL` — controlled enum/check: `player`, `coach`, `referee`, `club_admin`, `organizer`, `match_observer`, `competition_admin`, `technical_assessor`, `developer`
- `status text NOT NULL DEFAULT 'active'` — `active`, `suspended`, `revoked`
- `granted_by uuid NULL FK profiles.id`
- `granted_at timestamptz NOT NULL DEFAULT now()`
- `revoked_at timestamptz NULL`
- `metadata jsonb NOT NULL DEFAULT '{}'::jsonb`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

### Constraints/indexes

- unique active capability per user: `(profile_id, capability)`
- index `(profile_id, status)`
- index `(capability, status)`

---

## 1.3 `verification_cases` — NEW

Canonical KYC/verification state machine.

### Columns

- `id uuid PK`
- `profile_id uuid NOT NULL FK profiles.id`
- `verification_type text NOT NULL` — initially `identity`
- `status text NOT NULL DEFAULT 'not_required'` — `not_required`, `required`, `submitted`, `in_review`, `verified`, `rejected`, `resubmission`, `revoked`
- `document_type text NULL`
- `document_last4 text NULL` — never store raw document number in normal application tables.
- `submitted_at timestamptz NULL`
- `reviewed_at timestamptz NULL`
- `reviewed_by uuid NULL FK profiles.id`
- `rejection_reason text NULL`
- `expires_at timestamptz NULL`
- `metadata jsonb NOT NULL DEFAULT '{}'::jsonb`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

### Security

Raw identity documents should use controlled private storage if ever required; database tables should contain minimum necessary metadata.

---

# 2. Player identity layer

## 2.1 `players` — KEEP / EVOLVE

Existing player identity remains canonical.

### Existing canonical columns

- `id uuid PK`
- `full_name text NOT NULL`
- `date_of_birth date NOT NULL`
- `position player_position NOT NULL`
- `preferred_foot preferred_foot NULL`
- `photo_url text NULL`
- `club_id uuid NULL FK clubs.id` — **legacy current-club projection**
- `jersey_number integer NULL`
- `nationality text NULL`
- `is_active boolean NOT NULL DEFAULT true`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`
- `profile_id uuid NULL FK profiles.id`
- `height_cm numeric NULL`
- `weight_kg numeric NULL`

### Evolution

- Keep `club_id` temporarily for compatibility and current-club projection.
- Historical membership must move to `player_club_memberships`.
- Passport/DNA/development fields must not be stuffed into `players`; keep domain tables separate.
- `profile_id` should become unique where product rules allow one player identity per user.

---

## 2.2 `player_club_memberships` — NEW

Historical player-club relationship.

### Columns

- `id uuid PK`
- `player_id uuid NOT NULL FK players.id`
- `club_id uuid NOT NULL FK clubs.id`
- `membership_type text NOT NULL DEFAULT 'player'` — `player`, `trial`, `academy`, `loan`, `guest`
- `shirt_number integer NULL`
- `start_date date NOT NULL`
- `end_date date NULL`
- `status text NOT NULL DEFAULT 'active'` — `active`, `ended`, `suspended`
- `source text NULL`
- `created_by uuid NULL FK profiles.id`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

### Constraints

- `end_date >= start_date` when end date exists.
- prevent overlapping active membership for the same player/club/type where business rules require it.
- index `(player_id, status, start_date DESC)`
- index `(club_id, status)`

---

## 2.3 `player_cards` — NEW

Operational matchday identity.

### Columns

- `id uuid PK`
- `player_id uuid NOT NULL UNIQUE FK players.id`
- `card_number text NOT NULL UNIQUE`
- `qr_token_hash text NOT NULL UNIQUE`
- `status text NOT NULL DEFAULT 'active'` — `active`, `suspended`, `revoked`
- `issued_at timestamptz NOT NULL DEFAULT now()`
- `expires_at timestamptz NULL`
- `last_issued_at timestamptz NULL`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

### Rule

QR resolves to the canonical player/card lookup. It must never encode an authorization decision by itself.

---

## 2.4 Passport foundation

### `player_passports` — NEW

One current passport record per player.

Columns:

- `id uuid PK`
- `player_id uuid NOT NULL UNIQUE FK players.id`
- `passport_number text NOT NULL UNIQUE`
- `status text NOT NULL DEFAULT 'active'`
- `issued_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

### `player_passport_entries` — NEW

Longitudinal football history.

- `id uuid PK`
- `player_id uuid NOT NULL FK players.id`
- `entry_type text NOT NULL` — `club`, `competition`, `assessment`, `match`, `award`, `discipline`, `development`
- `club_id uuid NULL FK clubs.id`
- `competition_id uuid NULL FK leagues.id during compatibility phase`
- `fixture_id uuid NULL FK fixtures.id`
- `source_id uuid NULL`
- `event_date timestamptz NULL`
- `title text NOT NULL`
- `summary text NULL`
- `metadata jsonb NOT NULL DEFAULT '{}'::jsonb`
- `created_at timestamptz NOT NULL DEFAULT now()`

Indexes: `(player_id, event_date DESC)`, `(entry_type, event_date DESC)`.

---

# 3. Club and staff layer

## 3.1 `clubs` — KEEP / EVOLVE

Keep existing columns. `admin_id` is compatibility projection; durable club administration should be represented by capability/assignment records.

Recommended additions only after code reconciliation:

- `slug text UNIQUE NULL`
- `status text NOT NULL DEFAULT 'active'`
- `description text NULL`
- `updated_at` retained.

Do not remove `admin_id` until all consumers are migrated.

## 3.2 `club_members` — NEW (optional but recommended)

For non-player club staff/admin relationships.

- `id uuid PK`
- `club_id uuid NOT NULL FK clubs.id`
- `profile_id uuid NOT NULL FK profiles.id`
- `membership_type text NOT NULL` — `admin`, `manager`, `staff`, `coach`, `medical`, `observer`
- `status text NOT NULL DEFAULT 'active'`
- `start_at timestamptz NOT NULL DEFAULT now()`
- `end_at timestamptz NULL`
- `created_by uuid NULL FK profiles.id`

Unique active `(club_id, profile_id, membership_type)`.

---

# 4. Generic competition layer

## 4.1 Strategy: compatibility-first

Do **not** immediately rename `leagues` to `competitions`. Existing application code and foreign keys depend on `league_id`.

Canonical product semantics become **Competition**, while `leagues` is the first compatibility storage layer. A later migration can introduce a true `competitions` table if the codebase is ready.

### `leagues` — KEEP / EVOLVE now

Existing fields remain:

- `id`
- `name`
- `logo_url`
- `description`
- `season`
- `status`
- `founder_id`
- `yellow_card_threshold`
- `red_card_ban_matches`
- timestamps

Recommended additions:

- `competition_type text NOT NULL DEFAULT 'league'` — `league`, `group`, `knockout`, `hybrid`, `round_robin`, `single_match`, `friendly`
- `visibility text NOT NULL DEFAULT 'public'`
- `official_status text NOT NULL DEFAULT 'unofficial'` — `unofficial`, `pending_review`, `official`, `suspended`, `retired`
- `organizer_type text NULL` — `individual`, `club`, `academy`, `community`, `association`, `company`, `organization`
- `organizer_profile_id uuid NULL FK profiles.id`
- `rules jsonb NOT NULL DEFAULT '{}'::jsonb`
- `format_config jsonb NOT NULL DEFAULT '{}'::jsonb`
- `start_date date NULL`
- `end_date date NULL`

The existing `founder_id` remains compatibility data until organizer assignment is migrated.

---

## 4.2 `competition_staff` — NEW / generalize `league_staff`

- `id uuid PK`
- `competition_id uuid NOT NULL FK leagues.id`
- `profile_id uuid NOT NULL FK profiles.id`
- `assignment_type text NOT NULL` — `organizer`, `admin`, `developer`, `match_observer`, `technical_assessor`, `discipline_admin`
- `status text NOT NULL DEFAULT 'active'`
- `appointed_by uuid NULL FK profiles.id`
- `appointed_at timestamptz NOT NULL DEFAULT now()`
- `revoked_at timestamptz NULL`

Unique active `(competition_id, profile_id, assignment_type)`.

Existing `league_staff` remains during compatibility migration.

---

## 4.3 `competition_clubs` — generalized `league_clubs`

Canonical replacement for league membership.

- `id uuid PK`
- `competition_id uuid NOT NULL FK leagues.id`
- `club_id uuid NOT NULL FK clubs.id`
- `status text NOT NULL DEFAULT 'pending'` — `pending`, `approved`, `rejected`, `withdrawn`
- `approved_by uuid NULL FK profiles.id`
- `approved_at timestamptz NULL`
- `joined_at timestamptz NOT NULL DEFAULT now()`
- `seed integer NULL`
- `group_code text NULL`
- `created_at timestamptz NOT NULL DEFAULT now()`

Unique `(competition_id, club_id)`.

Existing `league_clubs` remains until consumers migrate.

---

## 4.4 `competition_player_registrations` — NEW

Separates competition eligibility from club membership.

- `id uuid PK`
- `competition_id uuid NOT NULL FK leagues.id`
- `player_id uuid NOT NULL FK players.id`
- `club_id uuid NOT NULL FK clubs.id`
- `registration_status text NOT NULL DEFAULT 'pending'` — `pending`, `approved`, `rejected`, `withdrawn`
- `shirt_number integer NULL`
- `registered_at timestamptz NOT NULL DEFAULT now()`
- `approved_by uuid NULL FK profiles.id`
- `approved_at timestamptz NULL`
- `metadata jsonb NOT NULL DEFAULT '{}'::jsonb`

Unique `(competition_id, player_id)`.
Indexes `(competition_id, club_id, registration_status)` and `(player_id, registration_status)`.

---

## 4.5 `competition_formats` — NEW

Reusable format definition.

- `id uuid PK`
- `competition_id uuid NOT NULL UNIQUE FK leagues.id`
- `format_type text NOT NULL`
- `group_count integer NULL`
- `teams_per_group integer NULL`
- `legs integer NOT NULL DEFAULT 1`
- `points_win integer NOT NULL DEFAULT 3`
- `points_draw integer NOT NULL DEFAULT 1`
- `points_loss integer NOT NULL DEFAULT 0`
- `tie_breakers jsonb NOT NULL DEFAULT '["points","goal_difference","goals_for"]'::jsonb`
- `progression_rules jsonb NOT NULL DEFAULT '{}'::jsonb`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

This allows league/group/knockout/hybrid behavior without hard-coding a separate engine per format.

---

# 5. Matchday layer

## 5.1 `fixtures` — KEEP / EVOLVE

Existing fixture is the match scheduling identity.

Retain:

- `id`
- `league_id`
- `home_club_id`
- `away_club_id`
- `match_date`
- `venue`
- `round`
- `round_name`
- `status`
- `referee_id`
- `created_by`
- timestamps

Recommended additions:

- `match_state text NOT NULL DEFAULT 'scheduled'` — `scheduled`, `registration`, `live`, `half_time`, `finished`, `abandoned`, `postponed`, `cancelled`
- `period_length_minutes integer NOT NULL DEFAULT 45`
- `extra_time_allowed boolean NOT NULL DEFAULT false`
- `group_code text NULL`
- `bracket_node jsonb NULL`
- `updated_at` retained.

---

## 5.2 `match_participants` — NEW

Authoritative matchday participant list.

- `id uuid PK`
- `fixture_id uuid NOT NULL FK fixtures.id`
- `player_id uuid NOT NULL FK players.id`
- `club_id uuid NOT NULL FK clubs.id`
- `squad_status text NOT NULL DEFAULT 'selected'` — `selected`, `starter`, `substitute`, `unused`, `withdrawn`
- `jersey_number integer NULL`
- `position_at_match player_position NULL`
- `eligibility_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb`
- `registered_by uuid NULL FK profiles.id`
- `registered_at timestamptz NOT NULL DEFAULT now()`

Unique `(fixture_id, player_id)`.
Unique `(fixture_id, club_id, jersey_number)` where jersey number is not null.

A participant must pass backend eligibility before becoming active in the match.

---

## 5.3 `match_admin_assignments` — NEW

Supports organizer-appointed observer/admin and referee-as-observer.

- `id uuid PK`
- `fixture_id uuid NOT NULL FK fixtures.id`
- `profile_id uuid NOT NULL FK profiles.id`
- `assignment_type text NOT NULL` — `match_observer`, `match_admin`, `referee`
- `status text NOT NULL DEFAULT 'active'`
- `appointed_by uuid NULL FK profiles.id`
- `appointed_at timestamptz NOT NULL DEFAULT now()`
- `ended_at timestamptz NULL`

Unique active `(fixture_id, profile_id, assignment_type)`.

---

# 6. Live Match Observer engine

## 6.1 `match_events` — NEW, PRIMARY MATCH SOURCE OF TRUTH

### Columns

- `id uuid PK`
- `fixture_id uuid NOT NULL FK fixtures.id`
- `competition_id uuid NOT NULL FK leagues.id`
- `event_type text NOT NULL`
- `period text NOT NULL` — `1H`, `2H`, `ET1`, `ET2`, `PENALTY_SHOOTOUT`, `OTHER`
- `match_minute integer NOT NULL DEFAULT 0`
- `match_second integer NOT NULL DEFAULT 0`
- `club_id uuid NULL FK clubs.id`
- `player_id uuid NULL FK players.id`
- `related_player_id uuid NULL FK players.id`
- `sequence_no bigint NOT NULL`
- `recorded_by uuid NOT NULL FK profiles.id`
- `recorded_at timestamptz NOT NULL DEFAULT now()`
- `metadata jsonb NOT NULL DEFAULT '{}'::jsonb`
- `voided_at timestamptz NULL`
- `voided_by uuid NULL FK profiles.id`
- `void_reason text NULL`
- `corrected_event_id uuid NULL FK match_events.id`

### Event catalogue

`MATCH_START`, `MATCH_END`, `PLAYER_START`, `SUBSTITUTION_IN`, `SUBSTITUTION_OUT`, `GOAL`, `ASSIST`, `YELLOW_CARD`, `RED_CARD`, `SHOT`, `SHOT_ON_TARGET`, `SAVE`, `CORNER`, `FOUL`, `OFFSIDE`, `PENALTY_TAKEN`, `PENALTY_SCORED`, `MOTM`, `OTHER`.

### Constraints

- `match_minute >= 0`
- `match_second between 0 and 59`
- sequence unique per fixture
- event player must be a match participant for player-specific event types
- event club must be one of fixture home/away clubs where applicable
- no ordinary client UPDATE/DELETE permissions
- corrections use void/correct workflow.

Indexes:

- `(fixture_id, sequence_no)`
- `(fixture_id, event_type, match_minute)`
- `(player_id, recorded_at DESC)`
- `(club_id, recorded_at DESC)`

---

## 6.2 `match_playing_intervals` — NEW

Validated/derived playing-time ledger.

- `id uuid PK`
- `fixture_id uuid NOT NULL FK fixtures.id`
- `player_id uuid NOT NULL FK players.id`
- `club_id uuid NOT NULL FK clubs.id`
- `start_event_id uuid NOT NULL FK match_events.id`
- `end_event_id uuid NULL FK match_events.id`
- `start_minute integer NOT NULL`
- `end_minute integer NULL`
- `minutes_played integer NOT NULL DEFAULT 0`
- `status text NOT NULL DEFAULT 'open'` — `open`, `closed`, `invalid`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `updated_at timestamptz NOT NULL DEFAULT now()`

Unique open interval per `(fixture_id, player_id)`.

Minutes are derived from validated start/IN/OUT/end events, not from the frontend clock.

---

# 7. Derived performance and result layer

## 7.1 `player_match_stats` — KEEP / DERIVED PROJECTION

Retain current fields:

- fixture/player/club identifiers
- started
- minutes_played
- goals
- assists
- shots
- shots_on_target
- yellow_cards
- red_cards
- saves
- clean_sheet
- timestamps

Recommended additions:

- `corners integer NOT NULL DEFAULT 0`
- `fouls integer NOT NULL DEFAULT 0`
- `offsides integer NOT NULL DEFAULT 0`
- `penalties_taken integer NOT NULL DEFAULT 0`
- `penalties_scored integer NOT NULL DEFAULT 0`
- `rating numeric(5,2) NULL`
- `derived_at timestamptz NOT NULL DEFAULT now()`

Unique `(fixture_id, player_id)`.

Client writes should be removed/restricted once event projection is active.

---

## 7.2 `match_results` — KEEP / DERIVED + RATIFIED

Current result table remains.

Rule:

- live score comes from `match_events`.
- `match_results` is the current result projection and official/ratified record.
- standings update from ratified result according to competition rules.

Do not allow ordinary clients to arbitrarily modify official results.

---

## 7.3 `standings` — KEEP / DERIVED

Current table remains as a competition projection.

Unique `(league_id, club_id)` should be enforced if not already present.

No manual standings edits by normal users.

---

# 8. Discipline

## 8.1 `disciplinary_records` — KEEP / EVENT-SOURCE COMPATIBILITY

Existing table remains for compatibility, but future card records should originate from `match_events`.

Add where needed:

- `event_id uuid NULL FK match_events.id`
- `competition_id uuid NULL FK leagues.id` if needed during transition

Unique/event deduplication should use event identity rather than approximate player/date matching.

## 8.2 `suspensions` — KEEP / AUTOMATED

Current suspension fields remain.

Recommended additions:

- `source_event_id uuid NULL FK match_events.id`
- `served_at timestamptz NULL`
- `notes jsonb NOT NULL DEFAULT '{}'::jsonb`

Eligibility must query active suspension state server-side.

---

# 9. Assessment / DNA layer

## 9.1 `player_assessments` — KEEP / SECURE

Current 18+ attribute inputs remain as assessment evidence.

Assessment values are inputs, not the final immutable DNA identity.

Recommended metadata:

- `assessment_type text NOT NULL DEFAULT 'technical'`
- `assessment_version text NOT NULL DEFAULT 'v1'`
- `source_context jsonb NOT NULL DEFAULT '{}'::jsonb`
- `status text NOT NULL DEFAULT 'valid'` — `draft`, `valid`, `voided`

## 9.2 `player_dna_snapshots` — NEW

Calculated DNA state at a point in time.

- `id uuid PK`
- `player_id uuid NOT NULL FK players.id`
- `assessment_id uuid NULL FK player_assessments.id`
- `overall numeric(5,2) NULL`
- `technical numeric(5,2) NULL`
- `physical numeric(5,2) NULL`
- `mental numeric(5,2) NULL`
- `tactical numeric(5,2) NULL`
- `band text NULL`
- `calculation_version text NOT NULL`
- `calculated_at timestamptz NOT NULL DEFAULT now()`
- `calculation_metadata jsonb NOT NULL DEFAULT '{}'::jsonb`

Index `(player_id, calculated_at DESC)`.

## 9.3 `player_dna_current` — NEW VIEW

Current/latest valid DNA snapshot per player. Prefer a view over duplicated mutable columns in `players`.

---

# 10. Development layer — DEFER implementation until event pipeline stable

The following concepts are approved but should not be implemented before M6/M7 is stable:

- training sessions
- attendance
- fitness snapshots
- fatigue
- morale
- injury risk
- development projections
- position familiarity
- weekly training score

The first development metrics should be derived from trusted match/assessment data: appearances, starts, minutes, performance trend and assessment progression.

---

# 11. Canonical RPC contract

RPCs are the server-side business boundary. Exact signatures may be adjusted during implementation, but these contracts are the target.

## Identity

### `get_my_profile()`
Returns current authenticated profile. Existing RPC: KEEP/SECURE.

### `get_my_capabilities()`
Returns active capabilities for `auth.uid()`.

### `has_capability(p_capability text)`
Returns boolean. SECURITY DEFINER with fixed search path and controlled EXECUTE grants.

### `require_capability(p_capability text)`
Raises authorization error if current user lacks capability.

## Player

### `get_my_player_id()`
Returns canonical player id for current profile. Required because repository code already expects this concept.

### `register_my_player(p_payload jsonb)`
Existing RPC: KEEP/REPAIR. Must never write nonexistent `profiles.identification_number`. KYC document data belongs in verification flow.

### `get_player_card(p_card_number text)`
Returns minimum public/matchday identity fields.

### `check_player_eligibility(p_fixture_id uuid, p_player_id uuid)`
Returns structured:

- `eligible boolean`
- `reasons jsonb`
- `checks jsonb`

This is the authoritative match registration gate.

## Competition

### `create_competition(p_payload jsonb)`
Requires organizer capability + required KYC state.

### `assign_competition_staff(p_competition_id uuid, p_profile_id uuid, p_assignment_type text)`
Requires competition authority.

### `register_competition_club(p_competition_id uuid, p_club_id uuid)`
Requires appropriate organizer/admin authority.

### `register_competition_player(p_competition_id uuid, p_player_id uuid, p_club_id uuid)`
Runs registration validation.

## Matchday

### `register_match_player(p_fixture_id uuid, p_player_id uuid)`
Runs eligibility then creates participant.

### `assign_match_admin(p_fixture_id uuid, p_profile_id uuid, p_assignment_type text)`
Organizer/competition authority only.

## Live event

### `record_match_event(p_fixture_id uuid, p_event jsonb)`
Primary write API for Match Observer.

Must:
1. authenticate caller;
2. verify observer/admin/referee assignment;
3. validate event envelope;
4. validate participant/team state;
5. insert event with sequence;
6. update derived projections atomically where practical;
7. return event + affected match/player/club summary.

### `void_match_event(p_event_id uuid, p_reason text)`
Authorized correction only.

### `rebuild_match_projection(p_fixture_id uuid)`
Admin/recovery function to deterministically recompute derived data from non-voided events. Not a normal UI operation.

## Discipline / standings

### `is_player_suspended(p_player_id uuid, p_fixture_id uuid)`
Server-side eligibility helper.

### `rebuild_competition_standings(p_competition_id uuid)`
Controlled recovery/admin operation.

## DNA

### `calculate_player_dna(p_player_id uuid, p_assessment_id uuid)`
Creates a versioned DNA snapshot from assessment inputs.

### `get_player_current_dna(p_player_id uuid)`
Returns latest valid snapshot.

## Development

### `compute_weekly_training_score()`
Existing repository expectation must be either implemented against the final model or removed from repository usage. Do not recreate blindly.

---

# 12. Trigger contract

Triggers should be used for integrity and tightly coupled derived effects, not as an untraceable replacement for all business logic.

### Required trigger/processor concepts

1. `match_events` insert → validate/project event effects.
2. `RED_CARD` / yellow threshold → discipline/suspension workflow.
3. match completion → close open playing intervals.
4. ratified official result → standings projection.
5. assessment valid → DNA snapshot generation where explicitly enabled.
6. `updated_at` maintenance on mutable domain tables.

### Important

The system must avoid trigger chains that recursively update the same source object. Event processing must be idempotent.

---

# 13. Views / read models

Existing views remain during migration:

- `v_active_suspensions`
- `v_discipline_summary`
- `v_player_profiles`
- `v_standings`
- `v_top_scorers`

Target additional views:

- `v_player_current_dna`
- `v_player_passport`
- `v_player_card_public`
- `v_fixture_live_state`
- `v_fixture_player_minutes`
- `v_competition_eligibility_summary`
- `v_competition_player_stats`

Read views should expose only fields appropriate to their audience.

---

# 14. Index strategy

Minimum high-value indexes:

- players(profile_id)
- players(club_id, is_active)
- player_club_memberships(player_id, status, start_date DESC)
- player_club_memberships(club_id, status)
- player_cards(card_number)
- player_cards(qr_token_hash)
- player_passport_entries(player_id, event_date DESC)
- user_capabilities(profile_id, status)
- user_capabilities(capability, status)
- verification_cases(profile_id, status)
- competition_clubs(competition_id, status)
- competition_player_registrations(competition_id, club_id, registration_status)
- competition_player_registrations(player_id, registration_status)
- fixtures(league_id, match_date)
- fixtures(home_club_id, match_date)
- fixtures(away_club_id, match_date)
- match_participants(fixture_id, club_id)
- match_events(fixture_id, sequence_no)
- match_events(fixture_id, event_type, match_minute)
- match_events(player_id, recorded_at DESC)
- match_playing_intervals(fixture_id, player_id)
- player_match_stats(fixture_id, player_id)
- disciplinary_records(player_id, league_id, match_date)
- suspensions(player_id, league_id, is_active)
- player_dna_snapshots(player_id, calculated_at DESC)

Every foreign key used in frequent authorization/filter paths must have a covering index or be explicitly justified.

---

# 15. RLS / permission contract

### Anonymous

- read public player/club/competition views only.
- no writes.
- no private KYC data.

### Registered user

- read/write own profile where allowed.
- create own player identity through controlled RPC.
- no direct privileged writes.

### Player

- manage own permitted profile fields.
- view own Passport/Card.
- participate in protected flows after required verification.

### Coach

- team/assigned-player scope only.

### Club Admin

- own club scope.
- manage club roster and authorized competition registrations.

### Organizer

- own competitions and assigned competition scope.
- cannot self-declare official status.

### Match Observer / Match Admin

- write live events only for assigned fixture(s).
- cannot alter unrelated matches.

### Referee

- officiating scope.
- may also receive Match Observer assignment independently.

### Competition Admin

- competition scope.
- can ratify results and manage competition rules according to policy.

### Technical Assessor

- assessment scope only.

### Developer/System Admin

- controlled system operations.

### SECURITY DEFINER rules

Every SECURITY DEFINER function must:

- use explicit `search_path` (`public, pg_temp` or safer equivalent);
- validate `auth.uid()`;
- avoid trusting caller-supplied profile ids;
- have minimum required EXECUTE grants;
- avoid leaking sensitive row data through error messages.

---

# 16. Existing schema defects to fix before M2

1. `register_my_player()` references `profiles.identification_number`, but active `profiles` has no such column. **Must fix.**
2. `referees` has RLS enabled but no policies. Define intended public/private access before use.
3. Multiple permissive/overlapping policies require consolidation.
4. SECURITY DEFINER functions/views exposed to API roles require privilege review.
5. Foreign keys without supporting indexes require review.
6. Leaked-password protection is currently disabled and must be addressed before production auth hardening.
7. `players.club_id` is a current-state shortcut and must not remain the only membership history.
8. Existing repository calls to absent RPCs/tables must be classified as restore/redesign/remove/defer before Phase 4.

---

# 17. Migration order

### M0 — snapshot
No schema change.

### M1 — safety
- fix concrete function/schema mismatch;
- add safe indexes/constraints;
- consolidate obvious authorization hazards where non-breaking.

### M2 — identity
- user capabilities;
- verification cases;
- capability helpers.

### M3 — player
- membership history;
- Player Card;
- Passport foundation.

### M4 — competition
- competition metadata additions;
- formats;
- generalized staff;
- competition clubs;
- player registration.

### M5 — matchday
- participants;
- assignments;
- eligibility RPC.

### M6 — event engine
- match events;
- event validation;
- playing intervals;
- projection processor.

### M7 — derived football data
- player stats;
- discipline;
- suspensions;
- standings.

### M8 — DNA
- versioned snapshots;
- current DNA view.

### M9 — repository/UI reconciliation
- every repository call mapped to canonical schema/RPC.

### M10 — E2E
Golden Player Path + Golden Match Path.

### M11 — production
Only after explicit release gate.

---

# 18. Golden tests required before production

## Golden Player Path

`register -> profile -> player -> card -> passport -> protected action/KYC -> club membership -> assessment -> DNA`

## Golden Match Path

`competition -> club registration -> player registration -> fixture -> participant -> eligibility -> observer assignment -> MATCH_START -> PLAYER_START -> substitution -> goal/card/etc -> MATCH_END -> minutes -> player stats -> discipline -> result -> standings -> Passport`

### Mandatory assertion

A single live event must not require a second manual update on another screen to make the system correct.

---

# 19. Phase 2 schema gate

This specification is considered implementation-ready only when:

- [x] canonical domains defined
- [x] existing tables classified
- [x] new tables identified
- [x] primary relationships defined
- [x] live event source of truth defined
- [x] playing-time model defined
- [x] capability model defined
- [x] KYC model defined
- [x] competition model defined
- [x] Player Card defined
- [x] Passport foundation defined
- [x] RPC contract defined
- [x] trigger contract defined
- [x] view/read-model contract defined
- [x] index strategy defined
- [x] RLS authorization contract defined
- [x] known code/schema defects recorded
- [ ] actual migration SQL written
- [ ] dev branch migration tested
- [ ] application repository fully reconciled
- [ ] production approval

**Conclusion:** This document is the schema contract, not the migration. No production database has been changed by creating this document.
