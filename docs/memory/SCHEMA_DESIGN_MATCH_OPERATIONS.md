# PLAYPRO SCHEMA DESIGN — MATCH OPERATIONS

**Status:** SCHEMA DESIGN · NOT DEPLOYED
**Basis:** Owner decisions DEC-072…DEC-075 + live `playpro2` inspection 2026-09-12

## 1. Objective

Fit the canonical football operation into the existing production schema without creating competing sources of truth.

Canonical flow:

`FIXTURE → CREW → START/END → OBSERVATION → MATCH REPORT → REFEREE REVIEW → OFFICIAL MATCH RECORD → DERIVATIONS`

Discipline is downstream of the official record and incident/report data:

`EVENT/INCIDENT → REFEREE REPORT → SANCTION → SUSPENSION/BAN → ELIGIBILITY`

## 2. Production objects already present

Verified live in `playpro2`:

- `fixtures` — 18 columns
- `match_results` — 37 columns
- `match_events` — 17 columns
- `player_match_stats` — 16 columns
- `match_participants`
- `match_playing_time`
- `match_admin_assignments`
- `suspensions` — 12 columns
- `referees`
- `disciplinary_records`
- `standings`
- `leagues`, `league_clubs`, `league_staff`
- `clubs`, `players`, `coaches`, `profiles`

Important live facts:

- `match_results` already has `is_official`, `ratified_by`, `ratified_at`, `entered_by`.
- `match_results` already contains team-level cards and match statistics.
- `match_events` already records `recorded_by`, `recorded_at`, sequence/time, and supports voiding with reason/auditor fields.
- `fixtures` already has `referee_id`, `match_state`, `status`, `period_minutes`, `extra_time_minutes`, `group_code` and `bracket_node`.
- `suspensions` already has player, league, reason, imposed length, served count, start fixture, notes and active state.
- Live `user_role` already contains `referee`.

## 3. Production gaps to model

The following are **design targets**, not evidence that no similar object exists elsewhere. They must be reconciled against the full production baseline before DDL.

### 3.1 Match report

Target: `match_reports` as the report/version layer above the existing `match_results` row.

Required concepts:

- fixture id;
- report version;
- generated/edited timestamps;
- report status: draft / submitted / returned / approved;
- observer corrections before approval;
- referee review decision;
- return reason;
- approval actor/time;
- link to the exact observation/event state used to generate the report.

The report is **not** a second official result source. `match_results` remains the official result gate.

### 3.2 Official lock

Do not create a duplicate official-result table.

After referee approval:

- write `match_results.is_official = true`;
- write `ratified_by`, `ratified_at`, `entered_by` as defined by DEC-073;
- preserve existing standings trigger behaviour;
- prevent ordinary post-ratification edits through the approved RLS/RPC boundary;
- any PlayPro correction must create an audit record and preserve the prior value/provenance.

### 3.3 Referee assignment

Target: `referee_assignments` as the single source of truth for fixture officials.

The model must support the six existing role concepts represented by the project architecture, including:

- referee;
- linesman/assistant referee roles;
- observer A;
- observer B;
- match start operator.

A start operator is one of the two observers, not a third observer role.

`fixtures.referee_id` is retained during design review as an existing reference/derivation. Do not silently drop it.

### 3.4 Suspension ledger

Existing `suspensions` is the starting point. It currently has 12 columns and is insufficient for every canonical ledger concept.

Design extension must cover:

- sanction source/type;
- competition/team context;
- total imposed;
- served;
- qualifying fixture rule;
- qualifying fixture count/source;
- remaining;
- completion;
- start fixture;
- rule/configuration version;
- imposed by/time;
- related incident/event;
- appeal state/outcome;
- audit provenance.

Core rule:

`REGISTERED ≠ ELIGIBLE`.

A suspended player does **not** need re-registration each match. The engine counts qualifying official fixtures played by the player's team, even if that player is absent from the squad for the suspended fixture.

The engine must therefore define a qualifying fixture independently of player registration.

### 3.5 Ban / disciplinary incident

Target model must represent an incident separately from its sanction.

Incident concepts:

- fixture;
- player/team/official affected;
- incident time;
- observer evidence references;
- referee report reference;
- reason code/category;
- free-text reason where `Other` is selected;
- decision status;
- sanction;
- fine;
- match outcome consequence;
- appeal relationship.

The PlayPro 3-month ban is a platform/competition rule and remains configurable. It must not be presented as universal FIFA law.

### 3.6 Appeals

Target model must represent:

- appellant type (player/coach/club);
- appellant identity;
- sanction/incident under appeal;
- RM100 payment record;
- submitted/reviewed/decided timestamps;
- reviewer;
- outcome: `UPHOLD`, `MODIFY`, `REVOKE`;
- mandatory decision reason;
- resulting sanction/eligibility state;
- audit trail.

The RM100 fee remains non-refundable regardless of outcome.

### 3.7 Venue / pitch / slot

Live production currently has fixtures with a text `venue` field. The design must support multiple physical pitches/areas at the same venue and prevent overlapping fixtures.

Target concepts:

`VENUE → PITCH → AVAILABILITY SLOT → FIXTURE`

This supports the Owner's Piala Merdeka U10 example: four simultaneous pitches, four simultaneous fixtures, with no accidental double booking.

### 3.8 Competition rules

DEC-075 locks all 17 rule areas into Phase A.

The design target is a competition-scoped rule configuration rather than global constants.

Examples include:

- match duration;
- extra time;
- card/suspension rules;
- ban duration;
- walkover/forfeit;
- disciplinary result;
- replay/reschedule;
- eligibility;
- scoring/standings consequence;
- fixture qualification;
- relevant format-specific rules.

Exact final field names/enums must be derived during schema review from the existing production types and migrations; this document deliberately does not invent SQL names where production evidence is incomplete.

## 4. Derivation chain

`OFFICIAL MATCH RECORD`

→ standings

→ player appearances/minutes/statistics

→ team/club history

→ coach history/rating inputs

→ disciplinary ledger

→ suspension/banned status

→ eligibility for future fixtures

The official record is the historical anchor. Downstream profiles should derive from it rather than allowing independent edits to create conflicting statistics.

## 5. Implementation order

1. Production baseline export/reconciliation.
2. Schema design review against every live object.
3. Migration plan with backward compatibility.
4. RLS/RPC authorization design.
5. Automated tests for lifecycle and eligibility.
6. Apply migration in development.
7. Verify real flows with test fixtures.
8. Owner approval for production.
9. Production deployment.

## 6. Explicit non-actions

- No peer observer approval.
- No re-registration requirement for suspension service.
- No second official-result table.
- No hard-coded universal FIFA claim.
- No direct production DDL from this document.
- No deletion of historical decision records.
