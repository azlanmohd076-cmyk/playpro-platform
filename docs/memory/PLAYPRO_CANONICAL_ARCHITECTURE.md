# PLAYPRO CANONICAL ARCHITECTURE — CURRENT OWNER BASELINE

**Status:** CANONICAL DESIGN REFERENCE · documentation only  
**Last locked decisions:** DEC-072…DEC-075  
**Implementation status:** no DDL / migration / deployment is implied by this file.

> This file is the current operational summary for future AI/CTO/Reviewer sessions. It supplements the historical `DECISIONS.md` and does not delete or rewrite historical decisions.

## 1. Match operating model

A match has **1 referee + 2 linesmen + 2 observers/admins** appointed by the organiser for that fixture.

- The two observers record match data independently.
- **Observer A does not approve Observer B, and Observer B does not approve Observer A.** The former peer-approval model is superseded.
- One appointed observer is the **MATCH START OPERATOR**.
- Only the MATCH START OPERATOR starts the match clock and match state.
- Both observers may record live events such as goals, cards, substitutions and other configured events without waiting for approval.
- The same MATCH START OPERATOR ends the match.
- After END, PlayPro produces a **MATCH REPORT** from the observation/event record.
- Before referee approval, the observer/admin side may correct the report/data; corrections must remain auditable.
- The referee receives the report and can **APPROVE** or **RETURN FOR CORRECTION**.
- RETURN FOR CORRECTION sends the report back for correction and resubmission.
- APPROVE creates the **OFFICIAL MATCH RECORD** and locks the official result.
- After lock, normal users cannot edit the official record. PlayPro may perform a controlled correction with mandatory audit trail; the original value/history must remain traceable.

## 2. Official record and standings

The existing `match_results` structure already contains the officiality/ratification fields. The current design decision is to **PAUT** the new official-record workflow to the existing gate rather than create a parallel result table.

Canonical transition:

`LIVE OBSERVATION → MATCH REPORT → REFEREE APPROVE → is_official=true + ratified_by + ratified_at + entered_by → OFFICIAL MATCH RECORD → LOCK → DERIVED HISTORY/STATISTICS`

Existing standings automation must be preserved and reviewed before migration. Do not create a second source of truth for standings.

## 3. Observer data

Observer data is **OBSERVATION**, not automatically official merely because it was entered live.

The system must retain:

- who recorded the event;
- when it was recorded;
- fixture and team/player context;
- event sequence/time;
- corrections/voids where supported;
- the final referee decision;
- the audit history of any post-approval PlayPro correction.

## 4. Suspension engine

Suspension is a **ledger**, not a requirement to re-register a player for every match.

Canonical rule:

`sanction created → SUSPENSION LEDGER → qualifying official fixtures served → remaining matches recalculated → eligibility restored`

A player **does not need to be registered again** for a suspended match. The suspension counter advances from the team's **official qualifying fixtures**, subject to the competition's configured rules.

This prevents the loophole where a club intentionally omits a suspended player from the next registration and accidentally/strategically stops the suspension clock.

### Registration vs eligibility

`REGISTERED ≠ ELIGIBLE`

A player may remain a registered member of the competition/team while being `NOT ELIGIBLE` because an active suspension or ban applies.

The coordinator/admin should see the player as unavailable (including a red/ineligible UI state), and the system must block an ineligible player from being selected/used where the competition rule requires it.

### Suspension ledger must know

1. sanction source;
2. player;
3. team/competition context;
4. sanction reason;
5. total matches imposed;
6. matches served;
7. qualifying fixtures;
8. fixtures that do not count;
9. current remaining balance;
10. completion status;
11. start fixture;
12. rule/configuration version;
13. who imposed it;
14. when imposed;
15. notes/provenance;
16. related incident/event;
17. appeal status/outcome;
18. audit timestamps/actors as required by the final schema.

The number of matches is **configurable by competition rule**. Current PlayPro defaults discussed by Owner are 2 matches for a direct red card and 1 match for a second-yellow dismissal; these must not be hard-coded as universal FIFA law.

## 5. Three-month PlayPro ban

A separate disciplinary sanction exists for serious incidents such as fighting or assaulting an official.

The **3-month ban is a PlayPro rule**, not a claim that FIFA universally mandates exactly three months.

When imposed, the player's eligibility becomes unavailable for the ban period and the profile/card UI may display **BANNED**. The source of truth is the ban status/disciplinary record, not the colour of the UI.

### Referee incident action

The referee report can identify the incident, affected player/team, evidence/data from observers and the reason for the proposed sanction.

Candidate reasons include:

1. fighting;
2. assaulting/striking a referee or match official;
3. falsifying player information;
4. identity/age fraud;
5. serious misconduct;
6. violent conduct;
7. threatening/intimidating a match official;
8. deliberate manipulation of match data/result;
9. repeated disciplinary misconduct;
10. other — **mandatory written reason**.

The final reason catalogue remains a configurable design item until formally sealed.

## 6. Match incidents and outcomes

A match may end normally or be affected by an incident/operational condition. The organiser's competition configuration determines the available rules and consequences.

Examples:

- **Team B fails to appear:** Team A may receive a 3–0 walkover where that competition rule is configured.
- **Fighting attributable to Team B:** Team A may receive a 3–0 disciplinary result where configured.
- **Both teams responsible:** competition rules may award a draw/no replay and impose configured sanctions/fines.
- **Weather:** match is postponed/rescheduled and a new fixture is created/managed by the scheduling system.
- Other causes must remain explicit incident records rather than being hidden inside a generic fixture status.

`3–0`, fines, suspension lengths and replay policy are **competition rules/configuration**, not universal hard-coded constants.

## 7. Appeals

Player / coach / club may request PlayPro review of a red card, suspension, ban or disciplinary decision.

Canonical flow:

`APPEAL REQUEST → RM100 fee → PLAYPRO REVIEW → UPHOLD / MODIFY / REVOKE → reason required → update sanction/eligibility/history`

The **RM100 appeal fee is non-refundable**, whether the original sanction is upheld, modified or revoked.

PlayPro review may consult:

- referee report;
- observer records;
- match report/version history;
- audit trail;
- relevant evidence.

A decision cannot be stored as a bare label only; the reason must be retained.

## 8. Competition formats

The match/discipline engine must support multiple competition formats. At minimum the organiser configuration must distinguish the rules needed for:

- friendly;
- tournament/group stage;
- knockout;
- league;
- other competition formats approved by the platform.

Rules must be configured at **competition setup**, not assumed globally.

The organiser must be able to define the relevant rule areas before fixtures are generated/played, including match duration, extra time, disciplinary rules, walkover/forfeit treatment, postponement/rescheduling, eligibility and other competition-specific rules.

## 9. Example: Piala Merdeka U10

24 teams → 4 groups × 6 teams.  
Four pitch areas → 4 matches can run simultaneously.

Each match:

`1 referee + 2 linesmen + 2 observers`

Each observer is assigned a team-side observation scope, but both observers may record the match independently. One observer starts/ends the fixture.

The observer panel is therefore an **observation workstation**, not a peer-approval workstation.

## 10. Post-match history

Once the referee approves the report and the official record is locked, match information becomes part of persistent history and feeds the appropriate profiles/indices.

### Player

- appearances;
- minutes played;
- goals/assists;
- cards and discipline;
- configured match statistics;
- competition history.

### Team / Club

- results;
- goals for/against;
- possession and match statistics where captured;
- disciplinary record;
- competition history;
- cumulative performance indices.

### Coach

- team/competition history;
- results and performance record;
- relevant configured statistics;
- rating inputs derived from official match history.

History is **append-only in meaning**: a correction creates an auditable new state/change; it must not silently erase provenance.

## 11. Current production facts — verified 2026-09-12

The active development/production reference is `playpro2` (`muirhenvjruvfxenoaxm`). It is ACTIVE_HEALTHY. `playpro` and `playpro1` are separate Supabase projects and currently are not to be treated as the same database.

The live `playpro2` schema already contains `match_results`, `match_events`, `player_match_stats`, `suspensions`, `referees`, `referee_assignments`-related design evidence, and `venues`/venue scheduling structures. The current database inspection also confirms `user_role` already contains `referee` and `league_staff_role` contains `referee`.

Important: the presence of existing columns/tables/enums is **evidence**, not permission to alter them. Schema changes remain governed by the project's baseline/schema gates.

## 12. LOCKED decisions from Owner

- **DEC-072:** referee is a first-class `user_role` using the approved `model6` direction; do not invent a third parallel role system.
- **DEC-073:** referee APPROVE writes the officiality through the existing `match_results.is_official` / `ratified_by` / `ratified_at` / `entered_by` gate.
- **DEC-074:** `referee_assignments` is the single source of truth for fixture officials; `fixtures.referee_id` is treated as derivation/reference pending schema review, not a reason to silently drop data.
- **DEC-075:** all 17 competition-rule configuration areas belong to Phase A.

## 13. Non-negotiable boundaries

- No peer approval between the two observers.
- No requirement to re-register suspended players each match.
- No silent edits after official approval.
- No separate competing source of truth for official results/standings.
- No hard-coded universal claim that PlayPro's disciplinary numbers are FIFA rules.
- No DDL/deployment merely because a design gap was discovered.
- Historical decisions remain in the repository; superseded decisions are marked, not deleted.

## 14. Next engineering gate

The next work is not another discussion of the same match flow. The repository should now move through:

`PRODUCTION TRUTH → SCHEMA DESIGN → SCHEMA REVIEW → MIGRATION PLAN → OWNER APPROVAL → IMPLEMENTATION → TEST → DEPLOY`

Before implementation, the actual production baseline must be captured and reconciled with the Git migration files. After that gate, the approved match/report/suspension/ban/appeal design can be mapped into concrete schema objects and then UI/RPC work.
