# PlayPro Phase 2C — Match Observer Authority & Event Hardening v1

Status: DESIGN / REVIEW CONTRACT — NO PRODUCTION DDL
Branch: phase-2/canonical-model

## 1. Match Observer model

Every competitive match must have at least two active Match Observer assignments before kickoff:

- Team A Observer — responsible for Team A events/data.
- Team B Observer — responsible for Team B events/data.

A separate `match_admin` / Main Match Observer role controls the match lifecycle.

Only the Main Match Observer may execute:

- START MATCH
- STOP/END MATCH
- CONFIRM / FINALIZE MATCH

The Team A and Team B observers may record and correct match events during the live match, but may not start, stop, or finalize the match.

A referee may also be appointed as an observer, but the assignment must still be explicit and authorization is capability-based rather than inferred from a frontend role string.

## 2. Live event source of truth

Observer input is the authoritative operational input. Each accepted event is written once to `match_events` and then drives derived match statistics.

Conceptually:

`Observer input -> authorized event RPC -> validated match_events -> derived match/player/club data`

The browser must not directly own score, discipline, playing-time, or other derived truth.

## 3. Event correction while match is live

Human correction is expected and supported.

Before final confirmation, an observer may correct an event they are authorized to manage. Examples:

- goal entered incorrectly;
- goal subsequently disallowed;
- wrong player selected;
- wrong team selected;
- wrong card type;
- substitution corrected;
- shot/corner/foul corrected;
- other event metadata corrected.

Corrections must be auditable. Prefer append-oriented correction/void records rather than destructive history erasure.

The UI may expose an Edit/Void action, but the backend RPC remains the authorization boundary.

## 4. Finalization lock

When the Main Match Observer selects `CONFIRM MATCH` after the game has ended:

1. match lifecycle becomes finalized;
2. all match events become immutable to normal observers/admins;
3. derived match statistics are finalized;
4. player playing-time totals are finalized;
5. discipline/standings projections are finalized according to competition rules;
6. further normal observer edits are rejected by the backend.

The frontend lock is only UX. The database/RPC must enforce the lock.

## 5. Developer correction after finalization

Only an authorized PlayPro Developer/System Administrator may reopen or correct a finalized match.

Such correction must:

- identify the developer;
- identify the reason;
- preserve the previous finalized state;
- record the affected event(s);
- recompute all affected derived projections transactionally where practical;
- leave an audit trail.

No observer, referee, club admin, organizer, or ordinary competition admin may bypass finalization.

## 6. Minimum match state machine

`scheduled -> ready -> live -> ended -> finalized`

Invalid transitions must be rejected server-side.

- `scheduled -> ready`: assignments/participants/eligibility prepared.
- `ready -> live`: Main Match Observer only.
- `live -> ended`: Main Match Observer only.
- `ended -> finalized`: Main Match Observer only after confirmation.
- `finalized -> reopened`: Developer/System Admin only.

## 7. Observer assignment invariants

Before `ready`/kickoff:

- exactly one active Team A observer is required;
- exactly one active Team B observer is required;
- one Main Match Observer is required;
- the same person must not silently represent both teams unless explicitly allowed by a future emergency override policy;
- assignment status must be checked by backend authorization.

During live operation:

- Team A observer may write/correct Team A events;
- Team B observer may write/correct Team B events;
- Main Match Observer may manage lifecycle and may record/correct events according to explicit permission;
- no observer may mutate another team's events unless their assignment/capability explicitly permits it.

## 8. Derived statistics rule

There is no separate manual 'update match stats' workflow.

Accepted live events immediately feed the match statistics projection. If an event is corrected before finalization, affected projections are recalculated/reconciled immediately.

Examples:

`GOAL -> score + player goal + club goal`

`ASSIST -> player assist`

`YELLOW_CARD -> player card + discipline accumulation`

`RED_CARD -> player card + suspension workflow`

`SUBSTITUTION_IN/OUT -> playing-time interval`

`SHOT_ON_TARGET -> player/team shot-on-target totals`

`MATCH_END/FINALIZE -> final validation and lock`

## 9. Playing time

Playing time remains event-derived. The authoritative transitions are:

- `PLAYER_START`
- `SUBSTITUTION_IN`
- `SUBSTITUTION_OUT`
- `MATCH_END`

A clock display is informational. It must never be the sole source of truth.

## 10. Security consequences

The security phase must create explicit policies/RPC authorization for:

- main match observer lifecycle control;
- Team A observer event ownership;
- Team B observer event ownership;
- pre-finalization corrections;
- finalized-match read access;
- developer-only reopening/correction;
- derived-stat recalculation;
- event audit visibility.

The existing public `SECURITY DEFINER` functions must not be copied as a pattern. Sensitive operations should use tightly scoped authorization and explicit `auth.uid()` checks.

## 11. Acceptance tests

A future E2E test suite must prove at minimum:

1. Match cannot start without Team A observer + Team B observer + Main Observer.
2. Team A observer cannot start/stop/finalize.
3. Team B observer cannot start/stop/finalize.
4. Team A observer can record Team A goal.
5. Team A observer cannot record Team B goal unless explicitly authorized.
6. Team B observer can record Team B goal.
7. Observer can correct/void a live event.
8. Corrected goal immediately changes derived score/statistics.
9. Main Observer can end the match.
10. Main Observer can finalize the match.
11. Normal observers cannot edit after finalization.
12. Developer can reopen/correct a finalized match.
13. Developer correction is audited.
14. Playing time follows validated start/in/out/end events.
15. Discipline follows card events without manual duplicate entry.
