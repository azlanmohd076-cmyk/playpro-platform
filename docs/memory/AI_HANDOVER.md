# AI HANDOVER — PLAYPRO CURRENT STATE

**READ THIS BEFORE MODIFYING PLAYPRO.**

## Current source of truth

For current product/domain/implementation state, read in this order:

1. `docs/memory/AI_MASTER_PROMPT.md` — canonical working brief for the next AI/CTO session, including the locked UI preservation rule.
2. `docs/memory/PLAYPRO_CANONICAL_ARCHITECTURE.md` — current Owner-approved operational architecture.
3. `docs/memory/DECISIONS.md` — historical append-only decision register. Do not delete history.
4. `docs/memory/BOUNDARIES.md` — lifecycle and authority boundaries.
5. `docs/memory/ENVIRONMENT.md` — repository/Supabase environment.
6. `docs/memory/BACKLOG.md` — work orders and gates.

## UI CANONICAL RULE — OWNER LOCK

**The existing PlayPro UI is a production asset and must be preserved.**

The target is **PRESERVE → AUDIT → REPAIR → IMPROVE**, not **REPLACE → REDESIGN → HOPE**.

The historical PlayPro UI baseline recovered from Git includes the original football-platform shell, search/header treatment, Transfermarkt-style navigation, bottom navigation, LIVE, CARI, MYTEAM, KEDAI, Passport and the existing football-oriented information density. The recovered source was identified at commit `36ec85739ac89fcbe3bdd0c27a73b8ca28abd963`. Do not replace that identity with a generic SaaS dashboard, landing page, card-grid “dossier”, or unrelated modern design.

### Explicit prohibition: DOSSIER UI

**DO NOT USE THE DOSSIER STYLE AS THE CANONICAL PLAYPRO UI.**

A previous newer UI surface was experienced by the Owner as a dossier/dashboard redesign and is rejected. Do not copy its visual language merely because it is newer. Do not rebuild the application around large generic profile cards, dashboard tiles, excessive whitespace, generic SaaS panels, or a document/dossier presentation when the old PlayPro surface already provides the appropriate football UI language.

### What “new UI” means for PlayPro

“New UI” means **new capability implemented inside the old UI language**:

- keep the old shell, navigation logic, football-data density and visual character;
- improve layout, responsive behaviour, information hierarchy, accessibility and interaction where genuinely useful;
- add Player, Coach, Club, Referee, Organiser, KYC, DNA, Attributes, Card, Passport, Membership, Squad, TMR, Competition, Payment and other new functions as native extensions of the existing UI;
- do not redesign an existing screen from scratch unless the Owner explicitly authorizes a replacement;
- when a new page is necessary, it must look and behave as a natural PlayPro sibling of the old pages, not as a separate SaaS product.

### Player UI reference

The Player profile should preserve the football-management-game character that the Owner prefers, especially the information density and attribute presentation associated with Championship Manager 01/02. The recovered Azlan persona is a **reference persona / UX fixture**, not production source data.

The target experience is:

`PLAYER → PROFILE → FOOTBALL DNA → ATTRIBUTES → PLAYER CARD → FOOTBALL PASSPORT → MATCH/CARRER HISTORY → KYC/VERIFIED`

Player Card is a presentation/product layer, not the source of truth. Attributes/DNA are data-driven and must come from the approved assessment/performance architecture.

## Locked match flow

`ORGANIZER SETUP → OFFICIAL FIXTURE → 1 REFEREE + 2 LINESMEN + 2 OBSERVERS → MATCH START OPERATOR START → OBSERVERS RECORD INDEPENDENTLY → MATCH START OPERATOR END → MATCH REPORT → REFEREE APPROVE / RETURN → OFFICIAL MATCH RECORD → LOCK → DERIVE HISTORY/STATS/STANDINGS/DISCIPLINE`

**Do not restore observer-to-observer approval.**

## Locked discipline flow

`EVENT → REFEREE REPORT / MATCH REPORT → SANCTION → SUSPENSION/BAN STATUS → ELIGIBILITY`

Suspensions count against qualifying **official team fixtures**, not against registration attempts. A suspended player does not have to be re-registered for every match. `REGISTERED ≠ ELIGIBLE`.

PlayPro's 3-month ban is a PlayPro competition/platform rule and must not be described as a universal FIFA rule. Appeal fee is RM100 and is non-refundable.

## Implemented correction — 2026-09-12

The two live production defects identified by Owner are corrected in `playpro2` and the migration is committed in Git:

1. `finalize_match(uuid)` is **referee-gated**. The appointed referee must be the authenticated user and must have `user_role = referee`. The main observer can no longer finalize the match. Referee approval writes the existing `match_results.is_official / ratified_by / ratified_at / entered_by` gate, then moves the ended fixture to `finalized`.
2. `auto_suspend_on_red_card()` no longer has the obsolete `COALESCE(..., 1)` fallback. Suspension length is read from `competition_rule_config`; current PlayPro configuration rows are seeded as **2 matches for direct red** and **1 match for second-yellow dismissal**. These are configuration values, not universal FIFA constants.
3. An official-result trigger advances active suspensions by qualifying official fixture for the sanctioned player's club. The suspended player does **not** need to be registered or selected in the serving match. The start fixture is excluded, and served fixture IDs are recorded to prevent double counting.
4. The existing `suspensions` table now records the club context, rule configuration, remaining matches, served fixture IDs and completion timestamp needed for the ledger mechanism.

## Product map boundary — important

Do **not** call the Organiser/Event map the whole “PlayPro City”.

`PLAYPRO CITY = keseluruhan platform`

`ORGANISER EVENT CONSOLE = satu “kedai” di dalam bandar PlayPro`

The organiser/event area is one product surface inside the wider platform. It must not be mistaken for the entire platform architecture.

The next build-map work must identify what is already **BUILT / PARTIAL / DESIGNED ONLY / NOT STARTED** inside the wider PlayPro platform. Known major areas requiring concrete implementation work include:

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

A box on a map is **not** evidence that the feature has been built. Future AI must verify actual Git/Supabase implementation before marking a box complete.

## Engineering rules

- Preserve provenance and audit history.
- Do not silently create a second source of truth.
- Do not hard-code competition-specific rules where configuration is required.
- Do not perform DDL/migrations/deployment merely to make a design document look complete.
- If a live object already exists, inspect it before proposing a replacement.
- If an old decision conflicts with a later Owner decision, mark it `SUPERSEDED`; do not erase it.
- Never assume a table/column/function is absent from production because a Git migration file does not contain it.
- Never treat a row count or textual search as proof of a design fact without measuring the actual object.
- Do not reopen settled Owner decisions merely because a new AI session cannot remember them.
- Minimize repeated audits: each audit must close a gate, fix a concrete defect, or produce a concrete artifact.

## Current Supabase reference

`playpro2` = `muirhenvjruvfxenoaxm` and is the primary production reference.

As of the latest handover, the live schema includes `match_results`, `match_events`, `player_match_stats`, `suspensions`, `referees`, `standings`, and `fixtures`; `user_role` already contains `referee` and `league_staff_role` also contains `referee`.

These are production facts, not blanket permission to change unrelated objects. Follow the project gates before unrelated DDL.

## Next work

Do not loop back into already settled observer/approval/suspension questions.

Next work is **product implementation**, not another documentation-only cycle:

1. Read `AI_MASTER_PROMPT.md` and the canonical architecture/decision files.
2. Reconcile the current Git/Supabase implementation against the product map.
3. Preserve the recovered legacy UI as the visual baseline.
4. Implement missing functionality incrementally inside that UI language.
5. Verify Player → KYC → Passport and the subsequent Coach → Club → Referee → Organiser paths end-to-end.
6. Commit and deploy only after tests and production verification pass.

**Owner intent:** keep moving. Do not waste sessions recreating architecture that is already settled, and do not replace the UI identity again.
