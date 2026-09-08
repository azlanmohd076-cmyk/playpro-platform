# PlayPro Phase 2B — Migration & Dependency Reconciliation v1

Status: DESIGN / DEVELOPMENT ONLY
Branch: `phase-2/canonical-model`
Production schema changes: NONE

## 1. Objective

Reconcile the existing PlayPro code/database foundation with the canonical Phase 2 model before any production migration.

Principle:

`CURRENT DB + CURRENT CODE → RECONCILIATION → CANONICAL CONTRACT → MIGRATION`

No destructive migration is authorized at this stage.

## 2. Reconciliation rules

Each existing object receives one disposition:

- KEEP — already aligned with the canonical model.
- EVOLVE — keep identity but add/adjust fields or constraints.
- COMPATIBILITY — retain temporarily while a generic canonical object is introduced.
- REBUILD — replace implementation while preserving required business meaning.
- REMOVE — dead/obsolete after dependency verification.
- DEFER — valid future capability but not required for the stable core.

## 3. Existing foundation disposition

### KEEP / EVOLVE

`profiles`
- KEEP as the application identity anchor.
- EVOLVE for public/private profile boundaries and KYC linkage.
- Do not duplicate user identity in domain tables.

`players`
- KEEP as the player identity table.
- EVOLVE with canonical player status and identity constraints.
- `profile_id` remains the user-player link.
- `club_id` must not become the historical club-membership source of truth.

`clubs`
- KEEP as the club entity.
- EVOLVE toward explicit membership/admin relationships.

`coaches`
- KEEP.
- EVOLVE toward capability-based authorization rather than one global role.

`referees`
- KEEP.
- EVOLVE authorization and RLS.
- Referee capability must remain independent from Match Observer capability.

## 4. Competition compatibility strategy

Current `leagues` is retained temporarily because existing fixtures, standings, discipline and staff relationships use `league_id`.

Canonical product concept: `competition`.

Migration strategy:

1. Introduce generic competition contract.
2. Map existing `leagues` records to competition identity.
3. Keep compatibility references during code migration.
4. Move new code to generic competition semantics.
5. Remove legacy naming only after repository and database dependencies are zero.

Do NOT rename/drop `leagues` in the first migration.

`league_staff` → EVOLVE/COMPATIBILITY
`league_clubs` → EVOLVE into competition-club registration
`fixtures` → EVOLVE into competition match scheduling
`standings` → KEEP but generalize around competition

## 5. Match foundation disposition

`fixtures`
- KEEP as match fixture identity initially.
- Add canonical matchday state/participant relationships.

`match_results`
- KEEP as a derived/ratified match result projection.
- It must not become the live event source of truth.

`player_match_stats`
- KEEP as a derived match-stat projection.
- Live events generate/update it.
- Direct manual edits must be restricted.

New canonical source:

`match_events`

This becomes the authoritative append-oriented event store for Match Observer.

## 6. Discipline disposition

`disciplinary_records`
- KEEP/EVOLVE.
- Generated from validated card/discipline events where applicable.

`suspensions`
- KEEP/EVOLVE.
- Must participate in backend eligibility checks.

Existing automatic suspension triggers are retained initially but must be reviewed so they cannot conflict with the new event pipeline.

## 7. Assessments disposition

`player_assessments`
- KEEP as assessment input/history.
- EVOLVE with assessor capability, provenance, assessment status and versioning.

`coach_assessments`
- KEEP/EVOLVE.

`club_assessments`
- KEEP/EVOLVE.

Assessment input is not the same thing as the canonical Player DNA history. DNA becomes a derived/provenance-aware layer.

## 8. New canonical domain groups

### Identity & authorization

- `user_capabilities`
- `verification_cases`

### Player identity/history

- `player_club_memberships`
- `player_passports`
- `player_cards`

### Competition

- `competitions` (generic canonical entity)
- `competition_formats`
- `competition_rules`
- `competition_clubs`
- `competition_player_registrations`
- `competition_squads`

### Matchday

- `match_participants`
- `match_observer_assignments`
- `match_events`
- `match_playing_time`

### Performance

- `player_dna_snapshots`
- `player_development_snapshots` (after event pipeline stabilisation)

The exact columns, constraints, indexes and RPC signatures are defined in `PLAYPRO_PHASE2_SCHEMA_SPEC_v1.md`.

## 9. Known current code/database defects to resolve

### 9.1 Registration identification field mismatch

Current `register_my_player()` attempts to update `profiles.identification_number`, while the active `profiles` schema does not currently expose that column.

Disposition: FIX before production registration is considered stable.

Preferred solution: introduce a dedicated KYC/identity document model rather than placing sensitive identity-document data directly in the general profile row.

### 9.2 Missing RPC dependencies

Repository code references functions such as:

- `get_my_player_id()`
- `compute_weekly_training_score()`

These must be classified as KEEP/REBUILD/REMOVE after repository-wide dependency verification.

No placeholder RPC should be created merely to silence frontend errors.

### 9.3 Advanced repository dependencies

Repository code references advanced objects that are absent from the active project, including player attribute/history, Passport history, development projection, fitness, morale, similarity, hidden attributes and position-familiarity objects.

Disposition: do not recreate all historical names blindly. Map each dependency to the canonical Phase 2 domain model, then update repository code deliberately.

## 10. Existing views

Current read models:

- `v_active_suspensions`
- `v_discipline_summary`
- `v_player_profiles`
- `v_standings`
- `v_top_scorers`

Disposition:

KEEP where business meaning remains valid; EVOLVE when underlying tables move; do not let views become hidden sources of truth.

## 11. Existing functions/triggers

Existing security-sensitive functions include profile/session helpers, role helpers, club/league admin checks, player registration, automatic suspension and standings updates.

Every SECURITY DEFINER function must receive an explicit security review before production migration:

- fixed `search_path`
- explicit authorization checks
- minimum EXECUTE grants
- no accidental privilege escalation
- no trust in client-supplied role fields
- correct ownership scope

Existing standings and suspension triggers must be reconciled with the new event-driven architecture.

## 12. Migration order

### M0 — Baseline
- Snapshot current schema/function/view/trigger/policy state.
- Confirm no production writes are required.

### M1 — Identity safety
- Fix profile/registration contract.
- Introduce capability and verification foundations.
- Harden sensitive function permissions.

### M2 — Player identity
- Player status constraints.
- Club membership history.
- Passport identity.
- Player Card identity.

### M3 — Competition canonical layer
- Generic competition entity.
- Format/rules.
- Competition clubs.
- Player registrations/squads.
- Compatibility with existing `leagues`.

### M4 — Matchday
- Match participants.
- Observer assignments.
- Eligibility RPC.

### M5 — Live event engine
- Match event store.
- Event validation.
- Event correction/void model.
- Atomic derived updates.

### M6 — Playing time & performance
- Playing-time ledger.
- Player match-stat projection.
- Discipline projection.
- Standings/result projection.

### M7 — Passport/DNA
- Passport history.
- DNA snapshots and provenance.
- Assessment linkage.

### M8 — Application reconciliation
- Repository methods.
- Supabase client binding.
- UI loading/error states.
- Remove dead/obsolete calls.

### M9 — E2E verification
- Golden Player Path.
- Golden Match Path.
- Security tests.
- Regression tests.

### M10 — Production approval
- Only after explicit review and passing verification.

## 13. Non-negotiable migration safety

1. Additive before destructive.
2. No direct production SQL during design.
3. No table rename/drop in the first migration.
4. No fake compatibility RPCs.
5. Preserve existing working registration/auth flows while replacing their internals safely.
6. Derived data must have a traceable source event/input.
7. Sensitive KYC data must not be exposed through public profile views.
8. RLS is part of the schema contract, not a later patch.
9. Every migration must have a rollback/forward-fix plan.

## 14. Current decision gate

The next implementation artifact is a DEVELOPMENT-ONLY migration baseline generated from the approved schema specification.

Before execution against any database, it must be checked for:

- SQL validity
- existing-object conflicts
- FK ordering
- enum compatibility
- index strategy
- RLS/policy correctness
- RPC SECURITY DEFINER safety
- trigger recursion
- repository compatibility

Production deployment remains blocked until these checks pass.
