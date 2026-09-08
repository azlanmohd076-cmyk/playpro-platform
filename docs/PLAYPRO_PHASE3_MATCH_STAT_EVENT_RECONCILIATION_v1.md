# PLAYPRO PHASE 3 — MATCH STAT & EVENT RECONCILIATION v1

**Branch:** `phase-2/canonical-model`

**Status:** Contract locked for implementation design. No Match Observer RPCs are introduced by this document.

## 1. Core principle

> **OBSERVER OPERATES, SYSTEM COMPUTES.**

The observer records a validated football event. The event ledger is the source of truth. Player statistics, team statistics, match result, discipline, standings, Passport history and coach KPI are derived from that event stream.

Canonical flow:

```text
Observer UI
  -> authorized RPC
  -> validated match event
  -> match event ledger (SOURCE OF TRUTH)
  -> player/team/match derived statistics
  -> discipline / eligibility
  -> result / standings / Passport / coach KPI
```

Direct client edits to derived statistics are not a canonical path.

## 2. Observer model

Every match has:

- Team A Observer
- Team B Observer
- Main Match Observer

Team observers operate only their assigned team's live events. Main Observer controls START, END and FINALIZE. Developer/System Admin alone may reopen or repair finalized source events through audited privileged operations.

The UI should preload match participants, Player Cards, jersey numbers, starting XI/bench and available event controls. Backend authorization remains mandatory even if the UI hides a button.

## 3. Canonical event families

Initial event vocabulary:

- MATCH_START
- PERIOD_START
- PERIOD_END
- MATCH_END
- PLAYER_IN
- PLAYER_OUT
- GOAL
- OWN_GOAL
- SHOT_ON_TARGET
- SHOT_OFF_TARGET
- PENALTY_KICK
- PENALTY_SCORED
- PENALTY_MISSED
- PENALTY_SAVED
- PENALTY_SHOOTOUT_TAKEN
- PENALTY_SHOOTOUT_SCORED
- PENALTY_SHOOTOUT_MISSED
- ASSIST
- FOUL
- CORNER
- FREE_KICK
- OFFSIDE
- YELLOW_CARD
- SECOND_YELLOW
- RED_CARD
- SAVE
- POSSESSION_START
- POSSESSION_STOP
- EXTRA_TIME_START
- EXTRA_TIME_END

Possession is interval-based rather than a manually edited percentage.

## 4. Locked statistical semantics

### Shots

```text
TOTAL SHOTS = SHOTS ON TARGET + SHOTS OFF TARGET + MATCH PENALTY ATTEMPTS
```

A penalty shootout attempt is not a match shot.

### Own goal

An own-goal event is retained as `OWN_GOAL`. The player whose kick/attempt caused the own goal receives a shot, and the team receives the corresponding shot. The initiating player is recorded as the PlayPro-defined assist attribution for the own goal.

### Extra time

Stoppage/injury time is part of the normal match clock. Example: 90+5 is represented as minute 95 and is not an extra-time goal.

A genuine 30-minute extra-time period is represented as ET1 (15 min) and ET2 (15 min). A goal at minute 95 during genuine extra time remains minute 95 in the timeline and is also classified as an extra-time goal.

### Penalty shootout

Shootout penalties are recorded as `PENALTY_SHOOTOUT_*`. They affect shootout statistics and `penalties_taken` where applicable, but do not become match goals and do not become match shots/SOT.

### Clean sheet

Clean sheet is derived automatically when the match ends. The observer never enters a clean-sheet stat manually. Goalkeeper attribution follows the eventual playing-interval/competition rule for the goalkeeper(s) involved.

### Possession

Possession is derived from intervals created when the ball changes team possession.

Example:

```text
00:00-00:12 Team A
00:12-00:19 Team B
00:19-00:44 Team A
```

The system can calculate possession live, at half-time, after full time, and for extra-time periods. The displayed percentage is derived, not stored as an observer-entered percentage.

### Fouls

A foul is a player-level event and also increments the team's match foul count. Competition-level team totals are accumulated from match events. This supports Fair Play analysis and coach KPI.

### Corner / offside / free kick

These are event-level statistics. Where an individual player is known, the event is attributed to that player and also increments the team statistic. Where no individual attribution is applicable, the team event remains valid without forcing a fake player attribution.

### Cards

- `YELLOW_CARD` = first/ordinary yellow event.
- `SECOND_YELLOW` = second yellow event and automatically produces red-card status.
- `RED_CARD` = direct red-card event.

Both second-yellow and direct-red result in the player being sent off. Under the locked PlayPro rule, a red card automatically creates a **2-match suspension**.

## 5. Player derived statistics

Legacy `player_match_stats` fields map as follows:

| Legacy field | Canonical source | Rule |
|---|---|---|
| started | PLAYER_START / starting lineup | Derived from match participation |
| minutes_played | PLAYER_IN/OUT + period boundaries | Derived from validated playing intervals |
| goals | GOAL | Increment scorer only; own goals use separate attribution |
| assists | ASSIST / goal attribution rule | Derived from goal event attribution |
| shots | SOT + off-target + valid match penalty + own-goal attempt | Derived |
| shots_on_target | SHOT_ON_TARGET | Derived |
| yellow_cards | YELLOW_CARD | Derived |
| red_cards | RED_CARD or SECOND_YELLOW->RED | Derived |
| saves | SAVE / valid penalty-save event | Derived |
| clean_sheet | Match-end derivation | Derived |

## 6. Team/match derived statistics

Legacy `match_results` fields map as follows:

| Legacy field | Canonical source | Status |
|---|---|---|
| home_goals / away_goals | GOAL + OWN_GOAL | Derived match score |
| possession | POSSESSION_START/STOP intervals | Derived live/HT/final percentage |
| shots | SOT + off-target + valid match penalties | Derived |
| shots_on_target | SHOT_ON_TARGET | Derived |
| corners | CORNER | Derived |
| free_kicks | FREE_KICK | Derived |
| offsides | OFFSIDE | Derived |
| fouls | FOUL | Derived from player/team event |
| yellow_cards | YELLOW_CARD | Derived |
| red_cards | RED_CARD / SECOND_YELLOW | Derived |
| saves | SAVE | Derived |
| penalties_scored | PENALTY_SCORED during match | Derived |
| penalties_taken | match penalty attempts + shootout attempts, with separate shootout context | Derived |
| extra_time | EXTRA_TIME_START/END or match configuration | Derived/configured |
| home_et_goals / away_et_goals | GOAL during genuine ET | Derived |
| is_official | match lifecycle/finalization policy | Derived state, not observer stat |
| ratified_by / ratified_at | finalization/audit | Audit metadata |
| entered_by | event actor/audit | Audit metadata |

## 7. Discipline and eligibility

Cards originate from validated match events. Derived discipline creates disciplinary records and suspension consequences.

For red cards:

```text
RED_CARD
  -> player sent off
  -> automatic suspension = 2 matches
```

For second yellow:

```text
YELLOW_CARD #1
  -> SECOND_YELLOW
  -> automatic RED_CARD status
  -> suspension = 2 matches
```

Suspension state is not directly edited by the observer.

## 8. Corrections

Human mistakes are expected. Source events must be corrected using void/correction semantics rather than silently deleting history.

A correction must preserve:

- original event ID;
- original actor;
- original event time/sequence;
- correction actor;
- correction timestamp;
- correction reason;
- replacement event when applicable.

Derived state must be recalculated from the valid event ledger.

## 9. Legacy compatibility boundary

The current active database contains legacy tables:

- `match_results`
- `player_match_stats`
- `disciplinary_records`
- `suspensions`
- `standings`

These remain compatibility/derived surfaces during migration. They must not become competing sources of truth.

The existing official-result standings trigger is therefore treated as a temporary compatibility path. It has already been hardened so an already-official result is not counted repeatedly and points/goal difference are maintained.

## 10. Current security observations

Current RLS policies still expose broad authenticated DML grants at the table level while policies restrict many write paths to league/club administration. This must be reconciled with the application write paths before broad grants are removed.

Current policy dependencies still use legacy role helpers such as `get_my_role()`, `is_club_admin()` and `is_league_admin()`. These are transitional and must eventually map to the canonical capability model.

The current disciplinary triggers automatically create suspensions from direct `disciplinary_records` inserts. Under the canonical architecture, this logic must move behind the validated event pipeline so an observer cannot manufacture discipline by writing the derived table directly.

## 11. Implementation gate

Do not implement the Match Observer RPC layer until the following are designed together:

1. `match_participants`
2. `match_admin_assignments`
3. `match_events`
4. playing-time derivation
5. event authorization
6. derived stat recalculation
7. discipline derivation
8. finalization lock
9. correction/reopen audit
10. compatibility views/materialization strategy for legacy consumers

## 12. Acceptance scenario

A golden test match must prove:

- Team A Observer records Ali goal -> score, player goal and team shot derive automatically.
- Ali SOT increments SOT and total shots exactly once.
- Ali off-target increments total shots exactly once.
- A match penalty increments penalty taken and total shots, without double counting.
- Own goal preserves own-goal identity while the initiating kick contributes a shot.
- 90+5 is represented as minute 95 without ET classification.
- genuine ET goal at minute 95 is classified as ET goal.
- shootout penalty changes shootout result but not match goals.
- possession switches by interval and produces live, HT and final percentages.
- foul increments player and team foul totals.
- corner/offside/free-kick can support individual attribution and team totals.
- second yellow automatically produces red status.
- direct red automatically creates a two-match suspension.
- clean sheet is calculated automatically at match end.
- voiding/correcting an event recalculates all affected derived statistics.
- finalized matches reject ordinary observer writes.

---

**Decision:** This document locks the Match Stat/Event semantic contract for the next implementation stage. No competing manual-stat path should be introduced.