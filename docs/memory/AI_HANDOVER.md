# AI HANDOVER — PLAYPRO CURRENT STATE

**READ THIS BEFORE MODIFYING PLAYPRO.**

## Current source of truth

For the current match/discipline architecture, read:

1. `docs/memory/PLAYPRO_CANONICAL_ARCHITECTURE.md` — current Owner-approved operational architecture.
2. `docs/memory/DECISIONS.md` — historical append-only decision register. Do not delete history.
3. `docs/memory/BOUNDARIES.md` — lifecycle and authority boundaries.
4. `docs/memory/ENVIRONMENT.md` — repository/Supabase environment.
5. `docs/memory/BACKLOG.md` — work orders and gates.

## Locked match flow

`ORGANIZER SETUP → OFFICIAL FIXTURE → 1 REFEREE + 2 LINESMEN + 2 OBSERVERS → MATCH START OPERATOR START → OBSERVERS RECORD INDEPENDENTLY → MATCH START OPERATOR END → MATCH REPORT → REFEREE APPROVE / RETURN → OFFICIAL MATCH RECORD → LOCK → DERIVE HISTORY/STATS/STANDINGS/DISCIPLINE`

**Do not restore observer-to-observer approval.**

## Locked discipline flow

`EVENT → REFEREE REPORT / MATCH REPORT → SANCTION → SUSPENSION/BAN STATUS → ELIGIBILITY`

Suspensions count against qualifying **official team fixtures**, not against registration attempts. A suspended player does not have to be re-registered for every match. `REGISTERED ≠ ELIGIBLE`.

PlayPro's 3-month ban is a PlayPro competition/platform rule and must not be described as a universal FIFA rule. Appeal fee is RM100 and is non-refundable.

## Safe engineering rules

- Preserve provenance and audit history.
- Do not silently create a second source of truth.
- Do not hard-code competition-specific rules where configuration is required.
- Do not perform DDL/migrations/deployment merely to make a design document look complete.
- If a live object already exists, inspect it before proposing a replacement.
- If an old decision conflicts with a later Owner decision, mark it `SUPERSEDED`; do not erase it.
- Never assume a table/column/function is absent from production because a Git migration file does not contain it.
- Never treat a row count or a textual search as proof of a design fact without measuring the actual object.

## Current Supabase reference

`playpro2` = `muirhenvjruvfxenoaxm` and is ACTIVE_HEALTHY.

As of the latest inspection, the live schema includes `match_results` (37 columns), `match_events` (17), `player_match_stats` (16), `suspensions` (12), `referees` (7), `standings` (12), and `fixtures` (18). `user_role` already contains `referee` and `league_staff_role` also contains `referee`.

These are production facts, not permission to change them. Follow the project gates before DDL.

## Next work

Do not loop back into already settled observer/approval/suspension questions.

Next concrete work:

1. reconcile the production baseline against Git migrations;
2. complete schema mapping for official match record, report version/lock, suspension ledger, incident causes, venue/slot availability and competition rules;
3. produce the next architecture map from **competition setup → fixture scheduling → match operations → post-match officialization → discipline → history**;
4. only then implement approved schema/UI/RPC changes through the required review gates.

## Schema review completed — 2026-09-12

The live `playpro2` schema was inspected read-only and the next match-operations map was advanced to schema design. Important findings now recorded in `SCHEMA_REVIEW_MATCH_OPERATIONS.md`:

- `finalize_match()` currently equates main-observer finalization with finalization; this conflicts with the locked referee-review gate and must be changed during implementation.
- `auto_suspend_on_red_card()` currently falls back to 1 match; the canonical rule is configurable and must be driven by competition configuration/ledger provenance rather than a blind default change.
- `suspensions` is the existing foundation and must be extended, not duplicated.
- `referee_assignments`, `match_reports`, appeal, incident, venue/pitch/slot and competition-rule configuration objects are not present in the current public table list and therefore are migration targets.
- Existing match policies are currently broader than the final authority model; RLS/RPC boundaries must be tightened/extended during implementation without weakening legitimate public reads.

The concrete schema design and migration plan are in:

- `docs/memory/SCHEMA_DESIGN_MATCH_OPERATIONS.md`
- `docs/memory/MIGRATION_PLAN_MATCH_OPERATIONS.md`
- `docs/memory/architecture/NEXT_MAP_MATCH_OPERATIONS.md`

**Do not repeat the same audit. Continue from these artifacts.**

## Owner intent

Keep moving. Minimize repeated audits. Every audit must close a specific gate or produce a concrete artifact. When a safe implementation step is authorized by the current gates, execute it and record the result in Git; do not return merely to ask a question that is already answered in the canonical documents.
