# PLAYPRO MIGRATION PLAN — MATCH OPERATIONS

**Status:** MIGRATION PLAN · NOT APPLIED
**Source:** `SCHEMA_DESIGN_MATCH_OPERATIONS.md`

## 1. Safety rule

This file is a plan for implementation. It is not an instruction to execute DDL against production. The production schema must be snapshotted and reconciled before any migration is applied.

## 2. Existing structures to preserve

- `match_results` remains the official result source and existing `is_official` / `ratified_by` / `ratified_at` / `entered_by` gate remains the integration point.
- Existing standings automation is preserved.
- Existing `match_events` remains the observation/event source.
- Existing `suspensions` remains the starting ledger rather than creating a parallel suspension table.
- Existing `fixtures.referee_id` is preserved until the referee-assignment migration is reviewed.

## 3. Planned migration units

### M01 — Match report/version layer

Add a report layer that references a fixture and its observation state. It must support draft, submitted, returned and approved states, report versioning, return reasons and referee approval metadata.

### M02 — Officialization + lock

Adapt the existing finalization path so referee approval, not observer finalization, is the officialization gate. The implementation must write the existing ratification fields and then enforce the post-ratification lock.

### M03 — Referee assignments

Create/normalize one fixture-official assignment source covering referee, two linesmen, two observers and the start operator. Existing `fixtures.referee_id` is retained as compatibility/derivation until the migration review decides its final role.

### M04 — Suspension engine

Extend the existing suspension ledger and replace registration-based serving logic with qualifying official team fixtures. A player can remain registered but ineligible. The service counter must advance even when the suspended player is not registered for that individual match.

### M05 — Incident + discipline

Add incident provenance and sanction linkage. Support fighting, assault on match official, falsified information/identity, serious misconduct, violent conduct, threats/intimidation, deliberate manipulation, repeated misconduct and `Other` with mandatory reason.

### M06 — Ban + eligibility

Represent the PlayPro 3-month ban as configurable platform/competition policy. Expose `BANNED` / `NOT ELIGIBLE` at the point where a lineup or match participant is selected. UI colour is presentation only.

### M07 — Appeals

Add appeal lifecycle and non-refundable RM100 fee record, reviewer, evidence references, outcome and mandatory decision reason. Corrections to sanction/eligibility must be auditable.

### M08 — Venue / pitch / slot

Normalize venue/pitch identity and availability so a venue can contain multiple pitch areas and a fixture cannot reserve the same pitch/slot twice.

### M09 — Competition rule configuration

Implement the 17 Phase-A rule areas at competition scope. Store rule/configuration version with sanctions and fixture decisions where required for historical reproducibility.

## 4. Required invariants

- `REFEREE APPROVE → OFFICIAL → LOCK`.
- Observer-to-observer approval is impossible.
- Only the assigned start operator can START and END.
- Observers can record independently during LIVE.
- Returned reports can be corrected and resubmitted.
- Official records cannot be silently edited.
- `REGISTERED ≠ ELIGIBLE`.
- Suspension service depends on qualifying official team fixtures, not registration presence.
- A ban blocks eligibility for its configured period.
- Walkover/forfeit/reschedule outcomes come from competition rules and incident records.
- Official history is derived from the official record.

## 5. Required test matrix

At minimum test:

1. normal match → approve → official → locked;
2. report returned → correction → resubmission → approve;
3. observer A records without observer B approval;
4. observer B records without observer A approval;
5. non-start-operator cannot start/end;
6. direct red card suspension;
7. second-yellow dismissal suspension;
8. suspended player absent from next squad still serves qualifying fixture;
9. suspended player cannot be selected while balance remains;
10. ban blocks selection;
11. appeal uphold/modify/revoke with fee retained;
12. weather postponement → reschedule;
13. no-show → configured walkover;
14. disciplinary forfeit → configured result/points;
15. four simultaneous pitches do not collide;
16. official result updates standings exactly once;
17. post-lock unauthorized update is rejected;
18. PlayPro correction records old and new values plus actor/time/reason.

## 6. Rollout

`DEV → TEST → REVIEW → OWNER APPROVAL → PRODUCTION`

No production migration is considered complete until the migration, tests, authorization boundaries and rollback/forward-fix procedure are all recorded.
