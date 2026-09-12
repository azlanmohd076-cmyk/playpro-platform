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

## Implemented correction — 2026-09-12

The two live production defects identified by Owner are now corrected in `playpro2` and the migration is committed in Git:

1. `finalize_match(uuid)` is now **referee-gated**. The appointed referee must be the authenticated user and must have `user_role = referee`. The main observer can no longer finalize the match. Referee approval writes the existing `match_results.is_official / ratified_by / ratified_at / entered_by` gate, then moves the ended fixture to `finalized`.
2. `auto_suspend_on_red_card()` no longer has the obsolete `COALESCE(..., 1)` fallback. Suspension length is read from `competition_rule_config`; current PlayPro configuration rows are seeded as **2 matches for direct red** and **1 match for second-yellow dismissal**. These are configuration values, not universal FIFA constants.
3. An official-result trigger advances active suspensions by qualifying official fixture for the sanctioned player's club. The suspended player does **not** need to be registered or selected in the serving match. The start fixture is excluded, and served fixture IDs are recorded to prevent double counting.
4. The existing `suspensions` table now records the club context, rule configuration, remaining matches, served fixture IDs and completion timestamp needed for the ledger mechanism.

## Product map boundary — important

Do **not** call the Organiser/Event map the whole “PlayPro City”.

The correct mental model is:

`PLAYPRO CITY = keseluruhan platform`

`ORGANISER EVENT CONSOLE = satu “kedai” di dalam bandar PlayPro`

The organiser/event area is one product surface inside the wider platform. It must not be mistaken for the entire platform architecture.

The next build-map work must therefore identify what is already **designed** versus what is actually **built** inside the wider PlayPro platform. Known major areas still requiring concrete implementation work include:

- player KYC / verification;
- Player DNA;
- player attributes and Football Passport;
- coach profile;
- referee profile;
- organiser profile / organiser identity and ownership model;
- eWallet and payment system;
- competition setup and rules;
- team/club participation and squad/registration;
- match operations;
- post-match official record;
- discipline, suspension, ban and appeal;
- persistent player/team/coach history and indices.

A box on a map is **not** evidence that the feature has been built. Future AI must verify the actual implementation before marking a box complete.

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

As of the latest inspection, the live schema includes `match_results` (37 columns), `match_events` (17), `player_match_stats` (16), `suspensions` (now extended by the 2026-09-12 migration), `referees` (7), `standings` (12), and `fixtures` (18). `user_role` already contains `referee` and `league_staff_role` also contains `referee`.

These are production facts, not permission to change them. Follow the project gates before unrelated DDL.

## Next work

Do not loop back into already settled observer/approval/suspension questions.

Next concrete work:

1. verify the 2026-09-12 migration in production and its Git copy remain identical;
2. move to the **next product build map**, beginning with the wider platform rather than treating the organiser/event console as the whole city;
3. distinguish every major area into **BUILT / PARTIAL / DESIGNED ONLY / NOT STARTED** using actual Git/Supabase evidence;
4. prioritise the next implementation block instead of producing another documentation-only loop.

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
