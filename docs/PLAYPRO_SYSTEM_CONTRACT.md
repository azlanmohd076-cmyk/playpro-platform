# PLAYPRO SYSTEM CONTRACT v1.0

**Status:** Phase 1 — Source of Truth  
**Branch:** `phase-1/system-contract`  
**Purpose:** Establish a single engineering contract for PlayPro before schema or feature development continues.

> This document is the authority for future implementation decisions. It deliberately separates the **current verified system** from the **target product architecture** so that planned capabilities are not mistaken for capabilities that already exist.

---

## 1. Engineering Rules

1. Do not add a new feature until its role, data model, permissions, repository path and acceptance criteria are defined.
2. No developer/AI may invent a table, RPC, view, trigger or field and treat it as existing.
3. Every database change must be delivered through a versioned migration.
4. Every application data access path must map to a real database object or an explicitly approved future object.
5. RLS is part of the feature contract, not a later security step.
6. Security-sensitive operations must use server-side authorization; client-side role checks are never sufficient.
7. Main/production is protected from experimental work. Changes are developed on branches and reviewed before merge.
8. Documentation must be updated when the implementation changes.

---

## 2. Current Verified Platform Baseline

The active Supabase project currently contains a substantially smaller schema than the historical architecture documentation describes.

### Verified current public schema

| Object | Current count |
|---|---:|
| Tables | 17 |
| Views | 5 |
| Materialized views | 0 |
| Functions | 14 |
| Non-internal triggers | 16 |
| RLS policies | 57 |
| Edge Functions | 0 |
| Tracked Supabase migrations | 0 |

These numbers are an audit baseline, not a product target.

### Core verified tables

- `profiles`
- `players`
- `clubs`
- `coaches`
- `leagues`
- `league_staff`
- `league_clubs`
- `fixtures`
- `match_results`
- `player_match_stats`
- `disciplinary_records`
- `suspensions`
- `standings`
- `player_assessments`
- `coach_assessments`
- `club_assessments`
- `referees`

### Core verified views

- `v_active_suspensions`
- `v_discipline_summary`
- `v_player_profiles`
- `v_standings`
- `v_top_scorers`

### Verified application/database bridge

The application contains a Supabase client bridge and repository abstraction. The recent code history also contains work around secure player registration, authentication/session handling and repository synchronization.

---

## 3. Current Roles

The product currently exposes the following role concepts in its application/database design:

| Role | Intended responsibility | Status |
|---|---|---|
| Player | Own football identity, passport and player data | Core foundation exists |
| Coach | Manage/assess players and team football operations | Core role exists; scope needs reconciliation |
| Club Manager/Admin | Manage club and club membership | Core role exists; club data currently empty |
| League Organizer/Admin | Operate competitions and league data | Core role exists; league data currently empty |
| Referee | Officiate matches and submit/confirm match information | Core table exists; access policy needs definition |
| Developer/System Admin | Platform-level administration | Role checks exist; permissions need formal matrix |

**Rule:** Role names may not be changed or expanded without updating this contract.

---

## 4. Authorization Model — Target Contract

The following is the target permission model to be implemented and verified in Phase 3. It is **not** a claim that all permissions are currently correct.

| Actor | Default scope |
|---|---|
| Anonymous | Publicly approved data only |
| Authenticated Player | Own private data + approved public football data |
| Coach | Players/teams explicitly assigned to the coach |
| Club Admin | Club-owned/managed data and approved club operations |
| League Admin/Organizer | League-owned competition data |
| Referee | Assigned fixtures and officiating operations |
| Assessor | Assessment operations explicitly assigned to the assessor |
| Developer | System administration only |

Authorization must be enforced by database/RPC/RLS controls where data security is involved.

---

## 5. Canonical Football Domain

The football domain is divided into the following bounded areas.

### A. Identity

- Authentication
- Profile
- Role
- Verification/identity information

### B. Player

- Player identity
- Position
- Preferred foot
- Physical profile
- Club relationship
- Jersey number
- Active status

### C. Football Passport

Target capability:
- Persistent football identity
- Player football profile
- Assessment history
- Passport score/band
- Football DNA

**Important:** advanced Passport/DNA fields currently referenced by application code must not be assumed to exist in the active database until reconciled in Phase 2.

### D. Assessment

Current foundation:
- `player_assessments`
- `coach_assessments`
- `club_assessments`

Player assessment data includes a broad attribute set covering technical, physical, mental, tactical and goalkeeper-related inputs.

Target:
- controlled assessment workflow
- assessor authorization
- historical records
- derived DNA calculation
- auditability

### E. Club

- Club identity
- Club management
- Coaches
- Players
- Competition participation

### F. League

- League identity
- League staff
- Participating clubs
- Fixtures
- Results
- Standings

### G. Match

- Fixture
- Match result
- Player match statistics
- Referee/officiating
- Discipline
- Standings impact

### H. Discipline

Current foundation includes:
- `disciplinary_records`
- `suspensions`
- automatic suspension/disciplinary triggers
- active suspension and discipline views

### I. Intelligence / Marketplace / Development

These are product targets and must not be treated as implemented merely because frontend/repository references exist:

- Player development
- Training
- Fitness
- Morale
- Injury risk
- Player similarity
- Scout marketplace
- Market value
- Advanced analytics
- Recommendations/AI intelligence
- Wallet/transactions
- Social/community features

These areas require explicit schema and business-rule mapping before implementation.

---

## 6. Canonical Database Contract

### Identity

`profiles` is the canonical application profile record linked to authenticated users.

### Player

`players` is the canonical football-player record.

Current verified player fields include core identity/football fields such as name, date of birth, position, preferred foot, photo, club relationship, jersey number, nationality, active status, profile relationship, height and weight.

### Competition

The canonical competition chain is:

`leagues → league_clubs → fixtures → match_results → standings`

### Match statistics

`player_match_stats` is the canonical match-level player statistics table.

### Assessment

`player_assessments`, `coach_assessments` and `club_assessments` are the current assessment foundation.

### Discipline

`disciplinary_records` and `suspensions` are the canonical disciplinary records.

### Referee

`referees` is the canonical referee record. Its intended read/write access must be formally defined before exposing referee workflows.

---

## 7. Canonical RPC / Database Functions

Verified application-relevant functions include:

- `get_my_profile()`
- `get_my_role()`
- `register_my_player(jsonb)`
- `ensure_profile_after_signup(...)`
- `is_club_admin(uuid)`
- `is_league_admin(uuid)`
- `is_league_founder_or_developer()`

Additional automatic competition/discipline functions exist.

### Known mismatch requiring Phase 2 repair

`register_my_player()` currently attempts to update `profiles.identification_number` when an identification number is supplied, while the verified `profiles` schema does not contain that column. This must be resolved before the registration workflow is declared production-safe.

### Missing functions referenced by application code

The repository references functions including:

- `get_my_player_id()`
- `compute_weekly_training_score()`

These are not present in the verified current public function set. They must be treated as **missing dependencies**, not silently recreated during feature work.

---

## 8. Repository Contract

Application repository methods are an abstraction layer over Supabase.

For every repository method, the following must eventually be documented:

```text
UI / module
    ↓
Repository method
    ↓
Table / View / RPC
    ↓
RLS / authorization
    ↓
Business rule / trigger
    ↓
Returned domain object
```

A repository method that references a non-existent table, column or RPC is considered **broken integration**, even if the frontend compiles.

---

## 9. UI-to-Domain Contract

The primary user journeys are:

### Player journey

`Register → Authenticate → Profile → Player → Football Passport → Assessment → DNA`

### Club journey

`Create/verify Club → Club Admin → Add/approve Players → Coach/Staff → Club operations`

### League journey

`Create League → Staff → Register Clubs → Fixtures → Referee → Match → Result → Stats → Discipline → Standings`

### Development journey

`Player → Assessment → Training/Development data → Progress history → Updated football profile`

### Scout journey

`Player/Passport → Search → Verification → Scout data → Opportunity/Marketplace`

Only the first two journeys and the competition foundation should be considered current implementation targets until Phase 2 reconciliation is complete.

---

## 10. Security Contract

The following are mandatory before production:

- RLS enabled on exposed tables.
- Policies must be intentional, non-overlapping where possible and scoped to the correct actor.
- No public write access to sensitive football/assessment records unless explicitly required and controlled.
- `SECURITY DEFINER` functions must have deliberate `search_path`, ownership and execute privileges.
- Security-sensitive functions must not trust user-editable metadata for authorization.
- Public views must expose only intended public fields.
- Player identity/private data must be separated from public football profile data where appropriate.
- Referee access must be explicitly designed.
- Assessment write permissions must be explicitly designed.
- Authentication security settings must be reviewed before launch.
- Foreign-key indexes and other performance/security-adjacent database hygiene must be addressed during hardening.

---

## 11. Data Ownership Rules

Every important record must have a clear owner/scope.

Examples:

- Profile → authenticated user
- Player → player/profile
- Club → club administration
- League → league administration/founder
- Fixture → league/competition
- Match result → authorized match official/league workflow
- Assessment → authorized assessor/assessment workflow
- Suspension → competition/disciplinary authority

If ownership cannot be stated clearly, the feature is not ready for implementation.

---

## 12. Current Drift Register

The following are formally recorded as reconciliation items.

### DRIFT-001 — Architecture documentation vs active database

Historical architecture documentation describes approximately 85 tables, 86 functions, ~99 triggers and 6 materialized views, while the current verified project contains 17 tables, 14 functions, 16 non-internal triggers and 0 materialized views.

**Action:** Reconcile architecture documentation with the real active schema. Do not restore historical objects blindly.

### DRIFT-002 — Player advanced attributes

Repository/application code expects advanced DNA, Passport, fitness, morale, injury, development, market and related fields that are not present in the current `players` table.

**Action:** Build the canonical target model in Phase 2.

### DRIFT-003 — Missing advanced tables

Repository code references multiple advanced player/development tables that are absent from the current database.

**Action:** Classify each reference as KEEP / REBUILD / REMOVE / DEFER.

### DRIFT-004 — Missing RPC dependencies

Some repository methods reference functions not present in the current database.

**Action:** Resolve each dependency through the contract before coding against it.

### DRIFT-005 — Registration identification field

The player registration RPC references `profiles.identification_number`, which is absent from the current profile schema.

**Action:** Decide canonical storage and repair via migration.

### DRIFT-006 — RLS policy design

The active database contains numerous permissive/overlapping policies, including hotspots around player visibility and assessment access.

**Action:** Formal permission matrix and policy rewrite in Phase 3.

---

## 13. Definition of Done for Phase 1

Phase 1 is complete when:

- [x] A dedicated engineering branch exists.
- [x] A canonical system contract exists.
- [x] Current verified schema is separated from target architecture.
- [x] Roles are defined.
- [x] Core football domain is defined.
- [x] Repository/database contract is defined.
- [x] Security principles are defined.
- [x] Major known drift items are recorded.
- [ ] All repository methods are mapped to real DB objects.
- [ ] All current tables/columns/functions/policies are reconciled in the detailed Phase 2 blueprint.
- [ ] User/product decisions that affect the target schema are confirmed.

The unchecked items intentionally roll into Phase 2 rather than being guessed.

---

## 14. Next Phase Gate

**Phase 2 cannot begin schema implementation until this contract is accepted as the working source of truth.**

Phase 2 will produce:

1. Canonical database map.
2. Full application-code → database dependency map.
3. KEEP / REBUILD / REMOVE / DEFER classification.
4. Target schema for Football Passport, DNA, Development and related core systems.
5. Migration strategy from the current 17-table foundation.
6. Exact list of schema changes required before reconnecting advanced frontend modules.

**Principle:** We are reconstructing and stabilising PlayPro — not rewriting it from zero.
