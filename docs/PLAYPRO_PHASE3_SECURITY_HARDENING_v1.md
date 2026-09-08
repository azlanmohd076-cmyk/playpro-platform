# PLAYPRO PHASE 3 — SECURITY HARDENING v1

**Status:** Security contract / implementation gate — no production schema change authorized by this document

**Branch:** `phase-2/canonical-model`

**Scope:** Authorization, RLS, SECURITY DEFINER lockdown, Match Observer authority, finalized-match locking, KYC gates, public/private data, assessment permissions, referee permissions, competition organizer permissions.

---

## 1. Security objective

PlayPro must enforce authorization at the database boundary, not merely in the frontend.

The frontend may hide buttons, but the database/RPC layer must reject unauthorized actions.

Core rule:

> **UI visibility is convenience. Backend authorization is security.**

The Match Observer panel is an operator surface. An observer selects a preloaded player and an event; PlayPro validates the event, stores it as the source of truth, and derives the resulting match/player/club/competition state.

---

## 2. Canonical authorization model

Authorization is capability- and scope-based. The legacy `profiles.role` field is not a sufficient authorization boundary.

Canonical capability examples:

- `player`
- `coach`
- `referee`
- `club_admin`
- `organizer`
- `competition_admin`
- `match_observer`
- `match_main_observer`
- `technical_assessor`
- `developer`
- `system_admin`

A user may hold multiple capabilities simultaneously.

Capability status must be checked from trusted server-side data. Client-editable user metadata must never determine authorization.

---

## 3. Match Observer security model

Every match must have, before kickoff:

1. exactly one active Main Match Observer;
2. exactly one active Team A Observer;
3. exactly one active Team B Observer;
4. valid match participants/squads;
5. eligibility checks completed for registered players.

Default rule: one person must not silently serve as both Team A and Team B Observer.

### 3.1 Team Observer permissions

A Team A Observer may:

- view the assigned match;
- view the match-ready player/squad data needed for operation;
- record Team A events;
- correct/void Team A live events while the match is editable;
- view relevant live match state.

A Team A Observer may NOT:

- record a Team B event;
- start the match;
- end the match;
- finalize the match;
- reopen a finalized match;
- modify another team's event without an explicit future emergency override capability.

Team B is symmetrical.

### 3.2 Main Match Observer permissions

The Main Match Observer may:

- view the complete match;
- START the match;
- END the match;
- CONFIRM/FINALIZE the match;
- manage lifecycle state;
- record/correct events where explicitly permitted by the event authorization contract;
- resolve operational corrections before finalization.

The Main Observer does not gain unrestricted developer privileges.

### 3.3 Developer/System Admin

Only Developer/System Admin may:

- reopen a finalized match;
- correct finalized source events;
- trigger an audited recalculation after a finalized correction;
- perform system-level repair.

Every such action must create an audit record containing actor, timestamp, target, reason, before/after state, and recalculation status.

---

## 4. Match lifecycle security

Canonical lifecycle:

`scheduled -> ready -> live -> ended -> finalized`

Allowed transitions:

| Transition | Authorized actor |
|---|---|
| scheduled → ready | competition/match admin according to readiness rules |
| ready → live | Main Match Observer only |
| live → ended | Main Match Observer only |
| ended → finalized | Main Match Observer only |
| finalized → reopened | Developer/System Admin only |

Normal observers cannot bypass lifecycle state by directly inserting/updating derived result fields.

---

## 5. Live event security

Canonical flow:

`Observer UI -> authorized event RPC -> validated match_events -> derived data`

The client should not directly mutate derived score/stat/discipline/standings records as an alternative path.

The event RPC must validate at minimum:

- authenticated identity;
- observer assignment;
- match state;
- event team scope;
- player belongs to the relevant match/club/team;
- player is eligible to participate in the current state;
- event is logically possible for the player's current state;
- event timestamp/sequence validity;
- finalized-lock rules;
- correction authorization.

### 5.1 Event scope

Team A Observer:

`event.team_id = assigned Team A`

Team B Observer:

`event.team_id = assigned Team B`

Main Observer:

- lifecycle authority;
- explicitly permitted event/correction scope.

Developer/System Admin:

- audited override only.

---

## 6. Correction model

Live corrections are required because match operators can make human mistakes.

Examples:

- wrong goal;
- disallowed goal;
- wrong player;
- wrong team;
- wrong card;
- incorrect substitution;
- accidental duplicate event.

Preferred mechanism:

> **Void/correct the original event rather than silently destroying its history.**

A correction must preserve:

- original event ID;
- correction actor;
- correction time;
- correction reason;
- replacement/corrective event where applicable.

Derived state must be recalculated or adjusted atomically where practical.

---

## 7. Finalization lock

When Main Match Observer presses **CONFIRM MATCH**:

- match state becomes `finalized`;
- normal observers lose write access;
- normal match admins lose write access;
- direct client writes to derived match/player/discipline/standings data are rejected;
- event corrections are rejected unless performed through the developer override workflow.

Frontend locking is not sufficient. The database/RPC layer must enforce the lock.

---

## 8. Playing-time security

Playing time is derived from validated events, not from a client-supplied minutes field.

Examples:

- starter: `PLAYER_START -> PLAYER_OUT` or `MATCH_END`;
- substitute: `SUBSTITUTION_IN -> PLAYER_OUT` or `MATCH_END`.

The observer UI may show the clock, but the clock is not the source of truth.

The backend must reject impossible intervals, duplicate active states, and unauthorized manual minute manipulation.

---

## 9. Discipline security

Cards originate from validated match events.

The system derives:

`event -> disciplinary record -> suspension rule -> future eligibility`

Ordinary clients must not be able to manufacture a suspension or erase a disciplinary consequence by editing a derived table directly.

Existing auto-suspension triggers/functions must be reconciled with the event pipeline to avoid duplicate or conflicting writes.

---

## 10. Eligibility security

Before match registration, PlayPro must evaluate:

- player identity;
- active status;
- competition registration;
- club/team relationship;
- KYC requirements where applicable;
- suspension status;
- category/age restrictions;
- competition-specific rules;
- duplicate participation constraints.

The backend should expose a structured eligibility result such as:

```text
eligible: true/false
reasons: []
checks: {}
```

The UI consumes this result instead of implementing its own authoritative eligibility logic.

---

## 11. KYC security

KYC is a protected-action gate, not a universal identity requirement.

Ordinary browsing, registration, and public profile creation can exist without KYC.

Protected actions may require KYC, including:

- joining a club where identity verification is required;
- creating/operating a competition as organizer;
- other privileged official actions.

KYC state machine:

`NOT_REQUIRED -> REQUIRED -> SUBMITTED -> IN_REVIEW -> VERIFIED`

Rejected path:

`IN_REVIEW -> REJECTED -> RESUBMISSION`

Revocation:

`VERIFIED -> REVOKED`

KYC verification does not itself mean a competition is Official or that a user has every organizer/admin authority.

---

## 12. Public/private player data

Public player profile should expose only intentionally public fields.

Sensitive identity/KYC information must not be exposed through public player views.

Particular care is required for:

- identity document information;
- private contact details;
- verification documents;
- guardian information;
- internal assessment metadata;
- fraud/security signals.

`Player Profile`, `Football Passport`, and `Player Card` are representations of the same canonical player identity, not separate player records.

---

## 13. Assessment security

`player_assessments`, `coach_assessments`, and `club_assessments` require scoped authorization.

A generic authenticated-user INSERT policy is not sufficient.

Assessment permissions must validate:

- assessor capability;
- assessor scope;
- target entity;
- assessment type;
- competition/club relationship where applicable;
- provenance and versioning rules.

Public profile views should expose only the assessment information explicitly classified as public.

---

## 14. Referee security

`public.referees` currently has RLS enabled but no policy. This is a concrete Phase 3 finding.

A policy must be designed based on the final referee product contract rather than adding a blanket authenticated policy.

Referee capability and match appointment are distinct concepts.

A referee may also be appointed as Match Observer, but that does not automatically grant Team A/Team B observer scope or Main Observer lifecycle authority.

---

## 15. Competition organizer security

Organizer types include:

- individual;
- club;
- academy;
- community;
- association;
- company/organization.

Organizer capability requires the appropriate verification/protected-action checks.

Organizer ownership is scoped to competitions they own/manage. It does not grant unrestricted access to every competition or every club/player.

`Official` status is a separate authorization/recognition decision and must not be inferred solely from KYC or organizer capability.

---

## 16. SECURITY DEFINER lockdown

Current active project findings include:

- 5 security-definer views;
- 8 functions with mutable search_path;
- 12 SECURITY DEFINER functions executable by `anon`;
- 12 SECURITY DEFINER functions executable by `authenticated`.

These are Phase 3 hardening targets.

Rules:

1. Prefer `SECURITY INVOKER` where possible.
2. Where `SECURITY DEFINER` is genuinely required, explicitly verify `auth.uid()` and authorization inside the function.
3. Use a controlled search path.
4. Revoke unnecessary `EXECUTE` privileges.
5. Do not expose privileged maintenance functions as public RPC endpoints.
6. Keep privileged internal helpers out of the exposed API schema where practical.
7. Re-run security advisors after changes.

Supabase currently recommends security-invoker views for views that should obey underlying RLS policies. citeturn0search0turn0search1

---

## 17. Existing security findings to remediate

### Critical implementation targets

1. Security-definer views:
   - `v_discipline_summary`
   - `v_player_profiles`
   - `v_active_suspensions`
   - `v_standings`
   - `v_top_scorers`

2. Mutable search path:
   - `update_updated_at`
   - `get_my_role`
   - `is_league_admin`
   - `is_club_admin`
   - `is_league_founder_or_developer`
   - `update_standings_on_official_result`
   - `auto_suspend_on_red_card`
   - `auto_suspend_on_yellow_accumulation`

3. Excess SECURITY DEFINER EXECUTE exposure:
   - `auto_suspend_on_red_card`
   - `auto_suspend_on_yellow_accumulation`
   - `ensure_profile_after_signup`
   - `get_my_profile`
   - `get_my_role`
   - `handle_new_user`
   - `is_club_admin`
   - `is_league_admin`
   - `is_league_founder_or_developer`
   - `prevent_role_self_escalation`
   - `register_my_player`
   - `update_standings_on_official_result`

4. `public.referees` has RLS but no policies.

5. Leaked-password protection is disabled.

6. `register_my_player()` has a known compatibility defect: it attempts to update `profiles.identification_number`, but that column is absent from the active `profiles` table. KYC identity documents belong in the dedicated verification domain.

---

## 18. Data API exposure rule

New `public` tables must not be assumed to be automatically exposed to the Data API.

Supabase changed Data API exposure defaults in 2026; explicit grants may be required depending on project settings. RLS and grants are separate controls. citeturn0search5

For every new canonical table, verify:

- whether Data API exposure is required;
- which roles need table privileges;
- RLS policies;
- whether direct table writes should be allowed at all;
- whether writes must instead occur through an RPC.

---

## 19. Required Match Observer RPC boundary

The eventual implementation should expose narrow operations rather than unrestricted table writes.

Conceptual RPC contract:

- `prepare_match()`
- `start_match()`
- `record_match_event()`
- `void_match_event()`
- `correct_match_event()`
- `end_match()`
- `finalize_match()`
- `reopen_finalized_match()` — developer only
- `recalculate_match()` — privileged/audited only

Exact function names remain subject to code/database reconciliation before migration.

The event RPC should accept a compact operator action such as:

`match_id + player_id + event_type + event metadata`

The server determines the authoritative event sequence, validates scope/state, records the event, and updates derived projections.

---

## 20. Security acceptance tests

### Match Observer

- [ ] Match cannot become ready without A observer + B observer + Main Observer.
- [ ] Team A Observer can record Team A goal.
- [ ] Team A Observer cannot record Team B goal.
- [ ] Team B Observer can record Team B goal.
- [ ] Team observers cannot START.
- [ ] Team observers cannot END.
- [ ] Team observers cannot FINALIZE.
- [ ] Main Observer can START.
- [ ] Main Observer can END.
- [ ] Main Observer can FINALIZE.
- [ ] Live event correction works.
- [ ] Correction is audited.
- [ ] Corrected score/stats update immediately.
- [ ] Finalized match rejects ordinary edits.
- [ ] Developer can reopen.
- [ ] Developer correction is audited.
- [ ] Recalculation produces deterministic derived state.

### Playing time

- [ ] Starting XI receive time from validated start event.
- [ ] Substitution OUT stops the interval.
- [ ] Substitution IN starts the interval.
- [ ] MATCH_END closes active intervals.
- [ ] Duplicate impossible intervals are rejected.
- [ ] Client cannot directly assign arbitrary minutes.

### Discipline

- [ ] Yellow card creates the appropriate discipline consequence.
- [ ] Red card creates the appropriate discipline consequence.
- [ ] Suspension affects eligibility.
- [ ] Direct client edits cannot bypass suspension.
- [ ] Correction/void reverses or recalculates the consequence correctly.

### Identity / KYC

- [ ] User can register without KYC.
- [ ] Protected actions can require KYC.
- [ ] KYC does not automatically grant Official status.
- [ ] Private KYC data is not public.

### Security-definer audit

- [ ] Every remaining SECURITY DEFINER function has a documented reason.
- [ ] Search path is controlled.
- [ ] `anon` cannot call privileged maintenance functions.
- [ ] `authenticated` cannot call privileged maintenance functions without scope.
- [ ] Views obey intended RLS behavior.

---

## 21. Phase 3 implementation sequence

### P3.1 — Inventory and classify

Classify every current function/view/policy as:

`PUBLIC_READ | SELF | CAPABILITY | SCOPED_ADMIN | MATCH_OBSERVER | DEVELOPER_ONLY | INTERNAL`

### P3.2 — Lock privileged functions

Remove unnecessary anon/authenticated EXECUTE access and harden SECURITY DEFINER functions.

### P3.3 — Harden views

Convert appropriate views to security-invoker behavior or otherwise restrict exposure after validating their intended public/private semantics.

### P3.4 — Build capability helpers

Create the trusted authorization predicates required by the canonical model. Avoid using client-editable metadata for authorization.

### P3.5 — Match Observer authorization

Implement assignment-based match scope and lifecycle permissions.

### P3.6 — Event boundary

Define and test the narrow event RPC contract.

### P3.7 — Finalization lock

Enforce finalized-state write rejection at the database boundary.

### P3.8 — Data/privacy policies

Harden players, assessments, referees, KYC/verification, competition data and new Phase 2 tables.

### P3.9 — Auth hardening

Review leaked-password protection and sensitive account actions.

### P3.10 — Verification

Run SQL security tests, advisor checks and application-level regression tests before production migration.

---

## 22. Supabase-specific implementation note

RLS is a row filter, not a substitute for authorization design. `TO authenticated` alone is not sufficient authorization; policies need a trusted ownership/capability predicate. UPDATE policies require both `USING` and `WITH CHECK` when the updated identity/scope must remain constrained. citeturn0search0

SECURITY DEFINER functions bypass normal caller RLS and therefore require deliberate hardening. Supabase recommends security invoker by default for functions and controlled search paths for functions that genuinely need definer privileges. citeturn0search13

---

## 23. No-production-change rule

This document is a security contract and implementation gate.

It does **not** authorize production DDL or destructive changes.

Implementation must proceed in small, verifiable steps with:

`change -> test query -> advisor -> regression -> commit`

The Match Observer experience is a product requirement, but its authorization boundary must be implemented server-side before the UI is connected.
