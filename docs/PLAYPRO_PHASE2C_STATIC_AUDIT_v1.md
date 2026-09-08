# PlayPro Phase 2C — Migration Static Audit v1

**Status:** Review complete — no production DDL executed
**Branch:** `phase-2/canonical-model`
**Scope:** `supabase/migrations/PHASE2_DEV_BASELINE.sql` against the active Supabase schema and canonical Phase 2 contract.

## 1. Executive result

The Phase 2 development baseline is structurally aligned with the canonical model and is appropriately additive-first. It does **not** yet qualify for production execution.

The active Supabase project was checked for the prerequisite foundation. The existing `player_position` enum is present, as are the core `profiles`, `players`, `clubs`, `leagues`, and `fixtures` tables used by the compatibility migration.

No Phase 2 tables have been applied to production during this audit.

## 2. Findings

### P0 — Production blockers

1. **No production migration yet — correct state.**
   The baseline must remain design/development-only until Phase 2C/Phase 3 security review is complete.

2. **RLS policies are intentionally absent from new tables.**
   This is acceptable for the review baseline, but the migration cannot be promoted without a complete Phase 3 policy contract. New tables include identity, KYC/verification, player identity, competition registration, match administration, live events, playing time and DNA data; they must not become client-writable by default.

3. **Live-event authorization cannot rely on table RLS alone.**
   `match_events` must be written through an authorized Match Observer/Match Admin path, preferably an RPC that validates assignment, participant identity, event invariants and sequence allocation atomically.

### P1 — Must resolve before migration approval

4. **Capability history design needs correction.**
   The baseline uses `unique(profile_id, capability)`. That prevents a clean revoke → regrant history. Canonical behavior requires capability status/history. Use an active-row uniqueness rule or a dedicated lifecycle model instead.

5. **Event sequence is client supplied.**
   `match_events.sequence` is unique per fixture but currently supplied by the caller. This is race-prone and allows ordering conflicts. Sequence allocation should be server-side inside the event-write RPC, with the database remaining authoritative.

6. **Playing-time intervals need stronger invariants.**
   The table permits multiple open intervals for the same player unless the event-writing layer prevents them. The event pipeline must guarantee one active interval per player and prevent impossible OUT/IN transitions.

7. **MATCH_START / MATCH_END uniqueness is not encoded.**
   The event contract requires one logical start and end per match, except for explicitly audited corrections. Enforce this in the event service and/or partial unique indexes over non-voided events.

8. **Competition registration needs eligibility enforcement.**
   `competition_player_registrations` correctly separates competition registration from club membership, but registration must be created/approved through a backend authorization path that checks the player's club relationship and competition rules.

9. **KYC data must stay out of public projections.**
   `verification_cases` contains verification metadata and must never be exposed through public player/club views. Phase 3 must explicitly control SELECT access.

### P2 — Hardening / quality

10. **No automatic updated_at mechanism is defined for new tables.**
    Existing PlayPro has an `update_updated_at()` function. The new tables should either use that trigger consistently or make timestamp ownership explicit in RPCs.

11. **Format/rule JSON needs contract validation.**
    JSONB is appropriate for extensibility, but competition creation/update RPCs must validate supported format types and required fields. Do not let arbitrary client JSON become executable business logic.

12. **Historical membership overlap needs a business invariant.**
    The baseline checks date ordering but does not prevent overlapping active memberships for the same player/club relationship. This should be handled before player-transfer history is considered authoritative.

13. **Compatibility fields on `leagues` and `fixtures` are correct for now.**
    Do not rename `leagues` to `competitions` or remove legacy fields until repository dependencies are fully migrated and verified.

## 3. Important confirmed compatibility points

- `public.profiles(id)` exists and is the correct application identity anchor.
- `public.players(id)` exists and is the correct player entity anchor.
- `public.clubs(id)` exists.
- `public.leagues(id)` exists and can serve as the temporary competition storage key.
- `public.fixtures(id)` exists and can serve as the match storage key.
- `player_position` exists with goalkeeper/defender/midfielder/forward and granular position values.
- The active database currently has no Phase 2 tables from the baseline, so there is no existing Phase 2 object collision to reconcile at this point.

## 4. Security observation from active project

The active project currently exposes multiple `SECURITY DEFINER` functions to API roles. This is not automatically a vulnerability, but it makes Phase 3 mandatory: each function must have explicit `search_path`, authorization checks, least-privilege execution grants and a documented reason for client exposure.

The existing `register_my_player()` also attempts to write `profiles.identification_number`, while the active `profiles` table does not contain that column. This remains a known production blocker and should be repaired by routing identity verification through `verification_cases`, not by adding sensitive KYC fields casually to `profiles`.

## 5. Decision

**Phase 2C static audit: PASS WITH REQUIRED CHANGES.**

The architecture is sound enough to continue. The baseline is not rejected; it needs hardening before any development migration is executed.

### Required next sequence

1. Correct capability lifecycle uniqueness.
2. Define server-authoritative live-event write contract.
3. Define playing-time and match-start/end invariants.
4. Define updated_at ownership.
5. Complete Phase 3 security policy matrix.
6. Produce a revised development baseline.
7. Only then consider a disposable Supabase development branch for migration execution testing.

**Production migration remains unauthorized.**
