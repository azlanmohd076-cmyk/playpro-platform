# PlayPro Phase 2 — Canonical Model v1

**Status:** Design / reconciliation only — NO production schema changes
**Branch:** `phase-2/canonical-model`
**Purpose:** Turn the approved product rules into a concrete canonical entity, event, permission and migration model before any database DDL is applied.

---

## 1. Non-negotiable architecture

### Source of truth

`LIVE MATCH EVENT -> VALIDATED EVENT STORE -> DERIVED MATCH / PLAYER / CLUB / COMPETITION DATA`

A real-world fact is recorded once. Derived values are not manually duplicated across multiple screens.

### Identity principle

`User Account -> Capability -> Domain Entity`

A user can hold multiple capabilities at the same time. A global single-role field must not be the long-term authorization model.

### KYC principle

KYC is a verification gate for protected actions. KYC does not equal authorization, and KYC is not required merely to browse PlayPro or exist as a player.

### Matchday principle

`Player Card = operational matchday identity`

Player Card must resolve to a canonical player and support QR/Player ID plus manual search, followed by backend eligibility evaluation.

---

## 2. Canonical entity relationship map

```text
USER ACCOUNT
    |
    +---- USER CAPABILITIES ------------------------------+
    |                                                     |
    +---- PROFILE                                         |
    |                                                     |
    +---- KYC / VERIFICATION -----------------------------+
    |                                                     |
    +---- PLAYER -----------------------------------------+
    |       |                                             |
    |       +---- FOOTBALL PASSPORT                       |
    |       |       +---- CLUB HISTORY                    |
    |       |       +---- COMPETITION HISTORY             |
    |       |       +---- ASSESSMENTS / DNA               |
    |       |       +---- PERFORMANCE / DEVELOPMENT       |
    |       |                                             |
    |       +---- PLAYER CARD                             |
    |                                                     |
    +---- COACH ------------------------------------------+
    |                                                     |
    +---- REFEREE ----------------------------------------+
                                                          |
CLUB <----------------------------------------------------+
  |
  +---- CLUB MEMBERSHIPS / ROSTER                         |
  +---- CLUB ADMINS                                       |
  +---- CLUB ASSESSMENTS                                  |
  |
  +-----------------------------+
                                |
COMPETITION <-------------------+
  |
  +---- ORGANIZER / STAFF / MATCH ADMINS
  +---- FORMAT + RULES
  +---- COMPETITION CLUBS / TEAMS
  +---- COMPETITION PLAYER REGISTRATIONS / SQUADS
  +---- FIXTURES
          |
          +---- MATCH / MATCH STATE
          |       |
          |       +---- MATCH PARTICIPANTS
          |       +---- LIVE EVENTS
          |       |       +-- goal / assist
          |       |       +-- card / discipline
          |       |       +-- shot / SOT / save
          |       |       +-- corner / foul / offside
          |       |       +-- substitution IN / OUT
          |       |       +-- start / end
          |       |       +-- MOTM
          |       |
          |       +---- PLAYING TIME (derived from events)
          |       +---- PLAYER MATCH STATS (derived)
          |       +---- MATCH RESULT (derived/ratified)
          |
          +---- STANDINGS / COMPETITION AGGREGATES
          +---- DISCIPLINE / SUSPENSIONS
```

### Canonical relationship rules

1. `profiles.id` represents the application identity linked to Auth.
2. `players.profile_id` links a user to a player identity; a player may exist without a club.
3. Club membership must be historical, not represented only by `players.club_id`.
4. Competition registration is separate from club membership.
5. Match participation is separate from competition registration and must pass eligibility checks.
6. A referee is an officiating capability/entity and can also be appointed as Match Admin/Observer.
7. Organizer, Club Admin, Referee, Coach and Match Observer are capabilities/assignments, not mutually exclusive identities.
8. Player Card is a representation of a canonical player, not a second player record.

---

## 3. Canonical domain objects

| Domain | Canonical object | Current active DB | Decision |
|---|---|---:|---|
| Identity | `profiles` | YES | KEEP / EVOLVE |
| Player | `players` | YES | KEEP / EVOLVE |
| Club | `clubs` | YES | KEEP / EVOLVE |
| Coach | `coaches` | YES | KEEP / EVOLVE |
| Referee | `referees` | YES | KEEP / SECURE |
| Competition | `leagues` | YES | REBUILD toward generic competition model |
| Competition staff | `league_staff` | YES | KEEP / GENERALIZE |
| Competition clubs | `league_clubs` | YES | KEEP / GENERALIZE |
| Fixture | `fixtures` | YES | KEEP / EVOLVE |
| Match result | `match_results` | YES | KEEP as derived/ratified result |
| Player match stats | `player_match_stats` | YES | KEEP as derived projection |
| Discipline | `disciplinary_records` | YES | KEEP / EVENT-SOURCE |
| Suspensions | `suspensions` | YES | KEEP / AUTOMATE |
| Standings | `standings` | YES | KEEP as derived projection |
| Player assessment | `player_assessments` | YES | KEEP / SECURE |
| Coach assessment | `coach_assessments` | YES | KEEP / SECURE |
| Club assessment | `club_assessments` | YES | KEEP / SECURE |
| Player Passport | none | NO | REBUILD |
| Player Card | none | NO | REBUILD |
| KYC state | incomplete | NO canonical object | REBUILD |
| User capabilities | single role field today | NO canonical object | REBUILD |
| Club membership history | current `players.club_id` only | NO | REBUILD |
| Competition format/rules | limited league fields | NO | REBUILD |
| Competition squad registration | none | NO | REBUILD |
| Match Observer assignment | none | NO | REBUILD |
| Match participants | none | NO | REBUILD |
| Live match events | none | NO | REBUILD |
| Playing-time event ledger | none | NO | REBUILD |
| DNA derived state/history | incomplete | NO | REBUILD |
| Development history | none | NO | DEFER until core event pipeline exists |

---

## 4. Match Observer event model

### Event envelope

Every live event should conceptually contain:

- `id`
- `match_id`
- `competition_id`
- `event_type`
- `period` (1H / 2H / ET1 / ET2 as applicable)
- `match_minute`
- `match_second` where useful
- `team_id` / club context where applicable
- `player_id` where applicable
- `related_player_id` for assist/substitution pairing where applicable
- `sequence_no`
- `recorded_by`
- `recorded_at`
- `metadata` for event-specific fields
- `voided_at` / `voided_by` / reason when correction is necessary

### Event types — initial catalogue

| Event | Primary effect |
|---|---|
| `MATCH_START` | starts validated match timeline |
| `MATCH_END` | closes timeline and derives final playing time |
| `PLAYER_START` | starting XI becomes active |
| `SUBSTITUTION_IN` | substitute becomes active |
| `SUBSTITUTION_OUT` | active player's time stops |
| `GOAL` | score + player goal |
| `ASSIST` | player assist |
| `YELLOW_CARD` | player discipline + match card |
| `RED_CARD` | player discipline + suspension workflow |
| `SHOT` | player/team shot |
| `SHOT_ON_TARGET` | player/team SOT |
| `SAVE` | goalkeeper save |
| `CORNER` | team corner |
| `FOUL` | team/player foul |
| `OFFSIDE` | team/player offside |
| `PENALTY_TAKEN` | penalty attempt |
| `PENALTY_SCORED` | penalty goal |
| `MOTM` | match award |
| `OTHER` | controlled extensibility |

### Event invariants

- A player event cannot reference a player who is not a valid match participant unless the event type explicitly permits it.
- `SUBSTITUTION_IN` and `SUBSTITUTION_OUT` must maintain active-player state.
- A player cannot be simultaneously active and inactive at the same event sequence point.
- `MATCH_START` can occur once.
- `MATCH_END` can occur once unless an audited correction workflow is used.
- Events are append-oriented; corrections should void/correct an event rather than silently mutate history.
- Event insertion and derived updates should be atomic where practical.

---

## 5. Playing-time calculation

### Rule

For each player:

`playing_minutes = sum(active intervals)`

Starting player:

`PLAYER_START -> first SUBSTITUTION_OUT OR MATCH_END`

Substitute:

`SUBSTITUTION_IN -> SUBSTITUTION_OUT OR MATCH_END`

### Example

- Match starts at 0'
- Player A starts
- Player A substituted at 63'
- Player B enters at 63'
- Match ends at 90'

Result:

- Player A = 63 minutes
- Player B = 27 minutes

If extra time is played, the event timeline continues through ET1/ET2 and the calculation uses the real validated interval.

### Important

The visible Match Observer clock is an operational aid only. It is **not** the database source of truth. Start/end/substitution events are.

---

## 6. Derived-data graph

```text
LIVE EVENT
   |
   +--> Match Score / Match Timeline
   |
   +--> Player Match Stats
   |       +--> goals
   |       +--> assists
   |       +--> shots
   |       +--> cards
   |       +--> saves
   |       +--> minutes
   |
   +--> Club Match Stats
   |
   +--> Discipline / Suspension Eligibility
   |
   +--> Competition Aggregates
   |
   +--> Standings (where applicable)
   |
   +--> Player Development Inputs
   |       +--> appearances
   |       +--> starts
   |       +--> minutes
   |       +--> performance history
   |
   +--> Football Passport History
```

No UI screen should become a second source of truth for these values.

---

## 7. Player eligibility model

Before `REGISTER_FOR_MATCH` or participation is accepted, backend evaluation must check:

1. Canonical player exists.
2. Player is active.
3. Player is registered to the relevant competition/team/squad.
4. Player-club relationship is valid for that competition.
5. Required KYC/verification state is satisfied for the action.
6. No active suspension blocks the match.
7. Competition age/category/position/registration rules pass.
8. Duplicate registration constraints pass.
9. Any competition-specific restrictions pass.

### Required backend outcome

Return a structured eligibility result, e.g.:

```text
eligible: true/false
reasons: []
checks: {
  identity,
  registration,
  club_relationship,
  kyc,
  suspension,
  competition_rules
}
```

UI red/green indicators are informational only. The backend decision is authoritative.

---

## 8. Capability / permission matrix

| Capability | Public browse | Own data | Team/club scope | Competition scope | Protected action |
|---|---:|---:|---:|---:|---:|
| Anonymous | YES | NO | NO | public only | NO |
| Registered user | YES | YES | NO | public only | limited |
| Player | YES | YES | own team scope | registered competitions | YES, according to policy |
| Coach | YES | YES | YES | assigned competitions | YES |
| Referee | YES | YES | NO | assigned officiating scope | YES |
| Club Admin | YES | YES | YES | club-owned/assigned | YES |
| Competition Organizer | YES | YES | own org scope | YES | YES |
| Match Observer/Admin | YES | YES | assigned match | assigned matches | live event write |
| League/Competition Admin | YES | YES | relevant clubs | YES | YES |
| Technical Assessor | YES | own assessment data | permitted assessment scope | where assigned | assessment write |
| Developer/System Admin | controlled | controlled | controlled | controlled | system-level |

### Authorization rule

Capability must be evaluated server-side. A frontend role string or client-controlled metadata must never be sufficient authorization.

---

## 9. KYC / verification state model

Minimum conceptual states:

`NOT_REQUIRED -> REQUIRED -> SUBMITTED -> IN_REVIEW -> VERIFIED`

Failure path:

`IN_REVIEW -> REJECTED -> RESUBMISSION`

Potential administrative state:

`VERIFIED -> REVOKED`

KYC verifies identity/status. It does **not** automatically grant official organizer status, league recognition or other authority.

---

## 10. Competition model

The current `leagues` table is the starting point, but the canonical product concept is broader: **Competition**.

Competition should support:

- league
- group stage
- knockout
- group + knockout
- round robin
- single/friendly match
- future rule-driven formats

A competition contains:

```text
Competition
  + lifecycle
  + official/unofficial state
  + organizer
  + format
  + rules
  + season
  + clubs/teams
  + squads
  + fixtures
  + match officials/admins
  + standings/progression
```

The format engine must not require a completely separate hard-coded application for each format.

---

## 11. Code ↔ DB reconciliation inventory

### Confirmed current DB foundation

- `profiles`
- `players`
- `clubs`
- `coaches`
- `referees`
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

### Known application expectations that are absent from the active DB

The current application/repository layer expects advanced player-development objects/fields including concepts such as:

- player attributes/history
- Passport score/history
- DNA overall/band/category scores
- fitness snapshots
- match sharpness
- fatigue
- morale
- injury-risk profile
- development projections
- position familiarity
- hidden attributes
- player similarity
- guardians
- weekly training scoring

Known referenced RPC concepts that require reconciliation include:

- `get_my_player_id()`
- `compute_weekly_training_score()`

These must be classified before implementation: restore, redesign, remove or defer.

### Confirmed schema/code defect to resolve

`register_my_player()` currently attempts to update `profiles.identification_number`, while the active `profiles` table does not contain that column. This is a concrete code-to-schema mismatch and must be fixed before relying on that path for KYC/identity data.

### Important architectural conclusion

The repository layer is not itself proof that a table should be recreated. The canonical model and product rules decide what survives.

---

## 12. KEEP / REBUILD / REMOVE / DEFER decision rules

### KEEP

Use when the active DB object is part of the real football foundation and can be reconciled without violating the canonical model.

### REBUILD

Use when the concept is required but the current schema is too narrow, e.g. generic Competition, capabilities, live events, Player Card, Passport history, competition registrations.

### REMOVE

Use only after confirming no active product path depends on the object and after a replacement/retirement plan exists.

### DEFER

Use for downstream intelligence that requires stable event data, such as similarity, market value, advanced recommendations and marketplace intelligence.

---

## 13. Migration sequence

No migration should be applied to production until this sequence has been reviewed and tested.

### M0 — Baseline snapshot

- Capture current schema inventory.
- Capture functions/triggers/policies/views.
- Capture row counts.
- Record current application commit.
- Record active Supabase project ref.

### M1 — Safety / contract fixes

- Fix concrete code/schema mismatches.
- Establish explicit constraints/indexes needed by current data.
- Do not change business semantics yet.

### M2 — Identity + capability foundation

- Capability assignments.
- Verification/KYC state.
- Protected-action authorization helpers.

### M3 — Player identity foundation

- Player membership history.
- Player Card identity contract.
- Passport foundation/history.

### M4 — Competition foundation

- Generic competition metadata.
- organizer assignments.
- format/rules.
- competition club/team registration.
- competition squad/player registration.

### M5 — Matchday foundation

- match participants.
- Match Admin/Observer assignments.
- eligibility evaluation.

### M6 — Live event engine

- immutable/auditable event ledger.
- event validation.
- event processing.
- atomic derived updates.

### M7 — Performance / discipline propagation

- playing time.
- player match stats.
- discipline/suspension integration.
- standings/result propagation.

### M8 — DNA / development integration

- assessment provenance.
- DNA derivation.
- development metrics from validated match history.

### M9 — UI/repository reconnection

- remove dead calls.
- align repositories with canonical RPC/table contracts.
- remove silent empty fallbacks for production-critical paths.

### M10 — E2E validation

Golden Player Path + Competition/Match Observer Path.

### M11 — Production promotion

Only after tests, security review and rollback rehearsal pass.

---

## 14. Rollback strategy

Every schema change must be independently reversible where practical.

### Required controls

- One logical migration per bounded concern.
- Backward-compatible additions before destructive changes.
- Do not drop/rename a live column until code no longer depends on it.
- Prefer additive schema migration followed by code cutover followed by cleanup.
- Keep old derived projections during transition until new event-driven projection is verified.
- Never delete historical match events to correct a derived value; correct/void the event with an audit trail.

### Deployment order

`DB additive change -> compatibility code -> verification -> traffic/cutover -> cleanup migration`

### Rollback order

`stop new writes -> restore compatible application path -> reverse safe migration -> verify data integrity`

If a migration cannot be safely reversed, the migration plan must document why and provide a data restoration strategy before approval.

---

## 15. Phase 2 definition of done

Phase 2 is complete only when the following are documented and internally consistent:

- [x] Canonical product principles
- [x] Initial ER/domain map
- [x] Match Observer event catalogue
- [x] Playing-time rules
- [x] Derived-data graph
- [x] Eligibility model
- [x] Capability matrix
- [x] KYC state model
- [x] Competition format model
- [x] Code-to-DB reconciliation inventory
- [x] Migration sequence
- [x] Rollback strategy
- [ ] Exact final table/column/RPC specification
- [ ] Security policy specification per canonical object
- [ ] Migration SQL
- [ ] Development-branch verification
- [ ] Production migration approval

**No production schema changes are authorized by this document.**
