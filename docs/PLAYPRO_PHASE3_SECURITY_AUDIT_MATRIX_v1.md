# PLAYPRO PHASE 3 — SECURITY AUDIT MATRIX v1

**Branch:** `phase-2/canonical-model`

**Purpose:** Record the current security classification before implementing the Match Observer authorization boundary.

## 1. Current function classification

| Object | Current security posture | Target classification | Action |
|---|---|---|---|
| `ensure_profile_after_signup(text,text)` | SECURITY DEFINER; authenticated RPC | SELF | Retain temporarily; require `auth.uid()` and narrow self-scope |
| `get_my_profile()` | SECURITY DEFINER; authenticated RPC | SELF | Candidate for SECURITY INVOKER after profile SELECT policy validation |
| `get_my_role()` | SECURITY DEFINER; authenticated RPC | SELF | Candidate for invoker/capability helper redesign |
| `is_club_admin(uuid)` | SECURITY DEFINER; authenticated RPC | SCOPED_ADMIN | Redesign around trusted capability/membership model |
| `is_league_admin(uuid)` | SECURITY DEFINER; authenticated RPC | SCOPED_ADMIN | Redesign around competition capability/scope |
| `is_league_founder_or_developer()` | SECURITY DEFINER; authenticated RPC | CAPABILITY | Replace legacy role dependency with trusted capability model |
| `register_my_player(jsonb)` | SECURITY DEFINER; authenticated RPC | SELF | Retain only after removing broken KYC column write and enforcing self-scope |
| `auto_suspend_on_red_card()` | SECURITY DEFINER trigger | INTERNAL | Client EXECUTE revoked; reconcile with canonical event pipeline |
| `auto_suspend_on_yellow_accumulation()` | SECURITY DEFINER trigger | INTERNAL | Client EXECUTE revoked; reconcile with canonical event pipeline |
| `update_standings_on_official_result()` | SECURITY DEFINER trigger | INTERNAL | Client EXECUTE revoked; replace with event-derived standings later |
| `handle_new_user()` | SECURITY DEFINER trigger | INTERNAL | Client EXECUTE revoked |
| `prevent_role_self_escalation()` | SECURITY DEFINER trigger | INTERNAL | Client EXECUTE revoked; authorization model must move to capabilities |
| `update_updated_at()` | SECURITY INVOKER trigger | INTERNAL | Pin search_path |

## 2. Current view classification

| View | Target classification | Required review |
|---|---|---|
| `v_player_profiles` | PUBLIC_READ with intentionally public fields | Remove security-definer behavior after checking columns/RLS semantics |
| `v_standings` | PUBLIC_READ | Must expose competition standings without bypassing intended row security |
| `v_top_scorers` | PUBLIC_READ | Must derive from canonical match events eventually |
| `v_discipline_summary` | PUBLIC_READ / SCOPED depending on fields | Ensure private disciplinary/KYC data is not exposed |
| `v_active_suspensions` | SCOPED_READ | Suspension data must not become unrestricted private-data leakage |

## 3. Referee policy requirement

`public.referees` has RLS enabled but no policies.

Do not add a blanket authenticated policy. Final policy must distinguish:

- public referee profile fields;
- self-management;
- appointment/competition administration;
- Match Observer assignment;
- developer/system administration.

## 4. Match Observer authorization contract

### Team A Observer

Allowed:

- read assigned match;
- read Team A participants;
- record Team A live events;
- void/correct Team A live events before finalization where permitted.

Denied:

- Team B events;
- START;
- END;
- FINALIZE;
- REOPEN finalized match.

### Team B Observer

Symmetrical to Team A.

### Main Match Observer

Allowed:

- read complete match;
- START;
- END;
- FINALIZE;
- explicitly permitted live event/correction operations.

Denied:

- developer/system-level finalized-match repair unless separately holding that capability.

### Developer/System Admin

Allowed only through audited privileged operations:

- reopen finalized match;
- correct finalized source event;
- recalculate derived state;
- system repair.

## 5. Required invariant

The backend must enforce:

```text
Observer UI
    ↓
Authorized RPC
    ↓
Validated match event
    ↓
Source-of-truth event ledger
    ↓
Derived score / player stats / discipline / playing time / standings / passport
```

Direct client writes to derived state are not an alternative path.

## 6. Next implementation gate

Before creating Match Observer RPCs, inspect the exact active schemas and policies for:

- `fixtures`
- `match_results`
- `player_match_stats`
- `disciplinary_records`
- `suspensions`
- `standings`
- `players`
- `clubs`
- `profiles`
- `referees`

Then implement the smallest compatible authorization boundary without rewriting the application.
