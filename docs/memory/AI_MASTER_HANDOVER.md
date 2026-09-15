# PLAYPRO — MASTER AI CONTINUITY HANDOVER

> **READ THIS FIRST if a new AI/agent takes over PlayPro.**
> This document is the continuity checkpoint for the Owner. It is intentionally operational: preserve decisions, inspect real Git/Supabase state, avoid loops, and continue building.

## 0. OWNER / WORKING STYLE

Owner: **Azlan / Lan**.

PlayPro is being built as a real football ecosystem, not a football game or a collection of disconnected pages. The Owner is a non-coder and expects the AI to act as a senior CEO/CTO: decisive, economical with tokens, evidence-driven, and execution-oriented. Do not repeatedly ask questions that have already been decided below. If a genuine new business decision is unavoidable, ask only that decision; otherwise solve it and continue.

**Do not enter an endless architecture-review loop.** The architecture has already been extensively reviewed/frozen. The current priority is implementation and integration, with clear BUILT / PARTIAL / DESIGNED / NOT STARTED status.

---

## 1. CURRENT REPOSITORY / LIVE ENVIRONMENT

GitHub repository: `azlanmohd076-cmyk/playpro-platform`

Default branch: `main`.

At handover creation, GitHub `main` points to:
- SHA: `8ab67357aec9c950d0ee80d4d5d39c84d5fcc8b7`
- Commit: `feat(referee): wire assignment accept decline actions`
- Date: 2026-09-14 15:03 UTC.

Existing Arena branch `arena/01a089e0-playpro-platform` currently points to:
- SHA: `a6d35615b4759c4ec2c99f6d55e6234e0572e80b`
- Commit: `fix: publish current PlayPro modules at live routes`
- Date: 2026-09-13 10:22 UTC.

**Important:** do not assume the Arena branch is the latest source. `main` is currently ahead and is the production repository baseline unless a newer branch/PR is explicitly verified.

Supabase production project:
- Name: `playpro2`
- Project ref: `muirhenvjruvfxenoaxm`
- Status: `ACTIVE_HEALTHY`
- Region: `ap-south-1`
- PostgreSQL 17.

`playpro1` is not the target production database. `sirr` is a separate app and is not PlayPro.

---

## 2. NON-NEGOTIABLE PRODUCT VISION

PlayPro = **real football identity + participation + performance + discipline + digital governance infrastructure**.

Mental model:

`ONE ECOSYSTEM → CANONICAL DOMAIN MODEL → CLEAR SOURCE OF TRUTH → DERIVED PROJECTIONS`

Data must move through the ecosystem. Avoid duplicate registration and fake/unlinked identities.

The platform eventually connects:

`USER → ROLE PROFILE(S) → KYC/VERIFICATION → PLAYER/COACH/REFEREE/CLUB OWNER/ORGANISER → CLUB/TEAM → COMPETITION → MATCH → OBSERVER/REFEREE → OFFICIAL RECORD → STATS/DISCIPLINE/HISTORY → PASSPORT`

A single real PlayPro user can have multiple role profiles simultaneously:
- Player
- Coach
- Club Owner
- Organiser
- Referee
- other approved operational roles as authorised.

No second account should be required merely because the same person takes another football role.

---

## 3. PLAYER — APPROVED PRODUCT MODEL

### Registration / onboarding

`SIGN UP → CHOOSE PLAYER → PLAYER ONBOARDING → PLAYER PROFILE → DNA/ATTRIBUTES → PLAYER CARD → FOOTBALL PASSPORT → MATCH/CAREER HISTORY → KYC/VERIFIED → CLUB / COMPETITION`

Sign-up must support:
- normal/manual account creation;
- Google login/signup;
- Facebook login/signup.

A new user can enter a preferred real name and/or nickname before KYC, but KYC becomes authoritative for legal identity.

### Identity / display name

Before KYC:
- user can enter real name and nickname;
- editable according to profile rules.

After KYC:
- legal/full name is taken from verified identity document and is not user-editable;
- nickname remains editable;
- user can choose whether public-facing profile/player-card display uses legal name or nickname, subject to privacy/verification rules.

### Football DNA / attributes

- New player attributes are `NULL` / not assessed; do not invent values.
- Attribute scale is **1–20**.
- Visual bands: 1–5 red, 5–10 yellow, 10–15 blue, 15–20 green.
- Player cannot self-assign official attributes.
- Coach assessment and later organic/performance-derived mechanisms are separate provenance sources.
- LTO/match data must flow automatically from finalised official match events; do not make observers re-enter player statistics manually.
- AI-based attribute evolution is a future research/product block. Do not introduce an opaque AI scoring engine prematurely. A deterministic, explainable mathematical model with provenance/audit is preferred for the eventual organic attribute system.

### Coach assessment economics / concept

Owner has discussed a proposed assessment fee of **RM100/player**, split conceptually:
- PlayPro RM70
- assessing coach RM30.

This price is **not yet an immutable commercial decision**. Build the architecture so the fee can be configured.

### Player Card

Player Card is a major PlayPro IP/product, not a simple badge.

It is shareable on social media and from the player profile. It evolves visually with DNA/overall level and can later support physical/digital merchandise revenue.

Proposed DNA/card progression currently discussed:
- 1–20: basic
- 20–40: novice
- 40–60: intermediate
- 60–80: advanced
- 80–100: expert/pro

These labels remain open to refinement.

Card must include six key attributes appropriate to the player position, inspired by the usefulness/readability of FIFA/football-game cards, while remaining PlayPro IP rather than copying another product.

**Discipline state:** when a player is under disciplinary action, the card should automatically enter a dark/penalty visual state and show the relevant action/notice. When the suspension/discipline ends, the card automatically returns to normal state.

### Football Passport

Football Passport is one of PlayPro's highest-value long-term assets.

It is a persistent career record across the user's football life: clubs, teams, competitions, matches, minutes, stats, assessments, discipline, achievements and other provenance-backed history. It should survive gaps in playing career and remain shareable as a long-term football memory.

Passport is a **projection/history view**, not the source of truth.

### Player profile UI

Owner prefers a **Championship Manager 2001/02-style information-dense football-management UI**, not a generic modern dossier. The recovered Azlan player data/design is a reference persona and UX reference, not a privileged production source.

---

## 4. COACH — APPROVED PRODUCT MODEL

Coach is another role profile of the same PlayPro user.

Flow:

`USER SIGNUP → CHOOSE COACH → SIMPLE ONBOARDING (NAME/PHONE) → KYC → KYC-GENERATED IDENTITY → COACH PROFILE ONBOARDING → COACH PROFILE`

Coach KYC is required early because a coach must be a legitimate identifiable person, including when acting as a private coach.

KYC/legal identity fields become locked after verification. Non-KYC coach information remains editable.

Coach profile should show verification in the **personal-detail/header area**, not as an isolated bottom block.

Coach licence section has two distinct tracks:
1. official football licence: FAM/AFC/FIFA or applicable recognised authority, with document upload/verification;
2. PlayPro licence levels **1–5**, earned through PlayPro courses.

### Coach PlayPro certification has TWO purposes

1. **Player-assessment certification track** — enables the coach to perform player attribute assessments, subject to the course/level scope.
2. **Coach-own-attribute certification track** — courses/exams assess the coach and establish the coach's own attributes.

The five-course concept maps progressively to attribute bands:
- Course 1 → 1–5
- Course 2 → 5–10
- Course 3 → 10–15
- Course 4 → 15–20 (as the progression design develops)
- Course 5 → highest/specialist certification scope and governance.

Do not interpret this as permission for a coach to assign arbitrary values. Assessment must follow PlayPro measurement standards and certification scope.

### Coach attributes

The reference is Championship Manager-style coaching attributes. Current live conceptual attributes include:
- adaptability
- coaching goalkeepers
- coaching outfield
- coaching youth
- determination
- discipline
- judging player ability
- judging player potential
- man management
- motivating
- physiotherapy
- tactical knowledge.

Coach attributes can have two provenance sources:
1. PlayPro course/exam assessment;
2. organic performance from team/competition results and LTO/match data.

Coach career history is only populated once the coach actually joins clubs/teams and participates in competition/match operations. Do not fabricate history.

Coach can also receive disciplinary actions and should have a coach-card state analogous to the player disciplinary-card mechanism.

Current live DB already contains coach-related tables including `coach_assessments`, `coach_attribute_state`, `coach_certification_courses`, and `coach_certification_requests`. Inspect before creating replacements.

---

## 5. CLUB — APPROVED PRODUCT MODEL / NEXT MAJOR BUILD

Club is a real ecosystem object owned/managed by real PlayPro users.

Flow:

`USER/PLAYER/COACH/REFEREE/ANYONE → OWNER KYC → CREATE CLUB → CLUB IDENTITY → CLUB PROFILE → CLUB VERIFIED → STAFF/ADMIN → COACH → PLAYER → TEAM/SQUAD`

### Club identity/profile

Core profile fields:
- club name
- logo
- owner profile
- year founded
- ROS registration number (optional)
- club type
- location
- training ground(s)
- contact phone / WhatsApp link
- club history
- competition record and achievements where data exists.

Club type must NOT restrict squad age selection. Current categories envisioned include:
- professional club
- semi-professional club
- amateur club
- grassroots football academy
- school / university / education institution club
- government department/agency club
- women's football club
- other configurable types as the product evolves.

Squads can run from **U6 through veteran**, regardless of club type.

### Training ground / venue

Club owner should be able to pin training-ground locations using map integration (Google Maps is the intended reference). This will later support organiser venue discovery and a future PlayPro pitch-booking marketplace.

Do not build the full venue-booking marketplace prematurely, but preserve the venue/location model so future booking/availability can connect cleanly.

### Staff/admin/people

All staff, coaches, players and operational people must reference real PlayPro users/role profiles. No fake free-text person records for official participation.

### Team / squad

A club starts with no squads until owner/coach creates them.

Squad creation onboarding should ask:
- age/category (U6 … U23, Open, Veteran)
- team label (A/B/C/D…)
- squad details.

Age eligibility is based on the player's verified football age/birth-year rules. Example: a player verified as age 10 cannot be placed in U7/U8/U9 but can be placed in U10+ subject to competition rules. `OPEN` has no age ceiling. Veteran starts at 35+ in the current product rule.

Each squad is its own page.

### Interactive squad/team board

Each squad page should have:
- roster
- coach/staff
- formation selector
- interactive pitch
- drag/drop players into positions
- click player → player profile
- next fixtures
- training schedule
- Team Match Room (TMR).

The Owner's reference layout is a football pitch with formation choices and draggable player markers.

### TMR / Match Board

TMR belongs inside the squad/team context. It must not create a permanent pile of duplicate match boards.

Correct model:
- every actual fixture gets one **fixture/match instance**;
- the team opens that fixture's TMR from the team's upcoming/current match list;
- match state/events are persisted against the fixture/match ID;
- after finalisation, the live operational board becomes read-only/archive view;
- the same team page can show historical match-room links without creating duplicate match objects;
- coach analytics can have a post-match snapshot/export, but the snapshot is a presentation/analysis artifact, not the official source of truth.

Do NOT use screenshots as the official match record. The canonical record is structured event data + official result + audit trail.

### Automatic competition registration

This is a core PlayPro IP:

`CLUB → TEAM/SQUAD → REGISTER TEAM INTO COMPETITION → ROSTER/PLAYER DATA FLOWS AUTOMATICALLY`

Organisers should not manually re-register every player if the team is already a valid PlayPro squad. Eligibility, KYC, age, membership and competition rules should drive acceptance.

---

## 6. CLUB MEMBERSHIP / FEES — LOCKED CONCEPT

A club may add a person using identifiers, not ambiguous names.

Accepted lookup mechanisms include:
- PlayPro Passport/Player ID
- PlayPro user ID
- national ID/IC where permitted and securely handled.

Avoid name-only matching because names are not unique.

Two principal entry paths:

### A. Club invitation
`CLUB → FIND REAL USER → INVITE → TERMS/FEES → USER ACCEPTS → PAYMENT (if applicable) → PLAYPRO PAYMENT VERIFICATION → ACTIVE MEMBERSHIP`

### B. User request
`USER → REQUEST TO JOIN CLUB → CLUB APPROVES → TERMS/FEES → PAYMENT (if applicable) → PLAYPRO PAYMENT VERIFICATION → ACTIVE MEMBERSHIP`

Coach/staff membership itself does not require a joining payment by default, while player membership fees may apply.

Club membership fee collection is an **optional PlayPro service** for clubs/academies that opt into it. PlayPro can present membership-fee information to players and later connect it to wallet/payment/settlement.

PlayPro platform fee concept: **5% transaction fee** for supported transactions. Treat this as configurable/commercial policy until formally locked.

Separate:
- invitation/request status
- membership status
- payment status
- approval/verification status.

Never collapse them into one boolean.

---

## 7. REFEREE / PENGADIL — APPROVED PRODUCT MODEL

Use the Malaysian term **referee/pengadil**, not “wasit”.

Referee has a first-class profile like player/coach.

Official licence can be FAM/AFC/FIFA or other recognised authority. Licence documents are uploaded to PlayPro for verification.

Referee has attributes/statistics with two provenance sources:
1. PlayPro certification/course performance;
2. organic LTO/match performance.

PlayPro referee certification currently has two broad purposes:
1. introduction/training on PlayPro match functions;
2. refreshment course with observer workflow to reduce repeated operational mistakes.

Observers do **not** need PlayPro certification just to act as observers. The referee is the match authority and must understand observer operation.

### Referee match model

The latest approved architecture includes official fixture staffing with a referee plus linesmen/other officials and **two team-scoped observers**, one for each team. The observer is not the final authority.

Locked principle:

`OBSERVERS RECORD → MATCH ENDS → MATCH REPORT → REFEREE APPROVE / RETURN FOR CORRECTION → OFFICIAL RESULT → LOCK → DERIVED STATS/DISCIPLINE/HISTORY`

The main observer must not be treated as finaliser.

### Referee assignment

`referee_assignments` is the authoritative assignment source for match officials. `fixtures.referee_id` is a derivation/legacy reference and must not silently become a second source of truth.

Referees can offer/apply for appointments. Organisers can assign/invite them. Payments for official services should flow through PlayPro when enabled.

### Non-official / in-house matches

PlayPro can support casual/in-house matches using TMR, observers and referee functions for familiarisation and organisation. They are not official records merely because the app was used.

Official/friendly competitions that explicitly use an officially recognised referee can be treated according to the competition's official-status rules.

---

## 8. ORGANISER / COMPETITION CONSOLE

Important mental model:

**PlayPro City = whole platform.**

**Organiser/Event Console = one “kedai” inside the city.**

Do not call the organiser event console the whole architecture/city.

Organiser is a first-class identity/role. An organiser can be an individual, club, academy, school, company, NGO, association, etc.

Conceptually:

`USER → ORGANISER/ORGANIZATION → COMPETITION → PARTICIPANTS → MATCHES`

Organiser is not automatically a regulator. Official/recognised status is separate.

Competition engine must support configurable formats and rules rather than hard-coded U-level assumptions.

Competition governs:
- categories/divisions
- registration
- eligibility
- squads
- rules
- fees
- payments
- approval
- fixtures
- matches
- officials
- observers
- results
- discipline
- disputes
- scheduling
- settlements.

---

## 9. KYC / VERIFIED MODEL

Player KYC is generally triggered when a player needs to enter a club/competition/official football workflow. A normal social user does not need to be KYC-verified merely to have an account.

Coach KYC is earlier/required as part of coach onboarding.

Referee/club-owner/organiser verification follows the relevant role's legitimacy requirements.

After KYC:
- legal identity is authoritative and protected from casual editing;
- user can still use a nickname/display-name mode where allowed;
- verified role profiles display a small verification badge, analogous to a social-platform verified icon.

Google Cloud/Google credential information supplied by the Owner is sensitive configuration. **Never commit OAuth secrets, private keys, service-account JSON, or credential material to Git.** Use environment/secret storage and only store public client IDs where appropriate.

---

## 10. DEVELOPER MASTER CONTROL PANEL

Owner wants a dedicated developer login/control surface for authorised PlayPro developer personnel so routine corrections/approvals do not require direct database manipulation.

Concept:

`DEVELOPER LOGIN → MASTER CONTROL PANEL → controlled operations across Player/Coach/Club/Organiser/Referee/Competition`

This is a high-privilege capability and must be strongly authorised/audited.

Only the Owner and designated PlayPro chief executive/executive authority should be able to grant/use the highest master-control privilege.

**Do not implement “unlimited raw SQL from the browser”.** Build controlled, auditable admin operations with explicit capabilities, before/after state, actor, reason, timestamp and immutable audit trail. Database superuser credentials must never be exposed to the frontend.

---

## 11. MATCH / DISCIPLINE — CRITICAL LOCKS

### Finalisation

The referee, not the main observer, is the official approval gate.

`finalize_match()` was corrected in the 2026-09-12 production migration so the appointed referee must be authenticated and have `user_role = referee`; referee approval writes the existing official-result fields and finalises the ended fixture.

### Suspension

Do not hard-code a universal one-match fallback.

Suspension duration must be read from competition/platform rule configuration and recorded in the suspension ledger. Current PlayPro configuration discussed/seeded:
- direct red → 2 matches
- second-yellow dismissal → 1 match.

These are PlayPro configuration values, not universal FIFA rules.

Suspension serving counts qualifying official team fixtures. It does not depend on the player being re-registered for every match. Start fixture is excluded and served fixture IDs should be recorded to prevent double counting.

### Event source of truth

Match events are canonical. Derived stats/history/discipline are projections.

Locked semantics include:
- total shots = on-target + off-target + valid match penalty attempt; shootout excluded;
- stoppage time represented by actual match minute (e.g. 90+5 → 95);
- genuine extra time is separate from normal 90-minute time;
- shootout is separate from match goals/shots;
- clean sheet is derived at match end;
- possession must come from actual event/interval logic, not arbitrary client clock;
- second yellow produces red-card state;
- corrections preserve original history, actor/time/reason and replacement event;
- finalised matches are locked except authorised correction/reopen workflow.

---

## 12. CURRENT LIVE DATABASE FACTS TO REMEMBER

The production reference is `playpro2`.

Known live facts from recent inspections:
- `user_role` contains: developer, league_founder, league_admin, club_admin, coach, technical_assessor, player, referee, club_owner, organizer.
- `coach_assessments` exists.
- `coach_attribute_state` exists.
- `coach_certification_courses` exists.
- `coach_certification_requests` exists.
- `players` has a legacy `football_passport_no` field in the current live model.
- Existing legacy player attribute infrastructure exists and is valuable reference material; do not replace it blindly.
- Current production has a mixture of legacy and newer structures. Inspect the actual live object before DDL.

Recent production correction already recorded in the current AI handover:
- referee-gated `finalize_match()`;
- configuration-driven suspension duration;
- suspension ledger serving mechanics;
- extended suspension context.

If exact current schema is needed, query/read production rather than relying on this static document.

---

## 13. BUILT / PARTIAL / DESIGNED / NOT STARTED — WORKING MAP

This is the working status, not a claim that every architecture box is implemented.

### BUILT / LIVE OR STRONGLY PRESENT
- Core user-role enum infrastructure, including referee.
- Existing legacy player attribute system.
- Existing coach assessment/certification structures.
- Existing match/fixture/event/result infrastructure.
- Referee assignment workflow exists in repository and recent main commits.
- Referee-gated finalisation / suspension corrections are implemented in production according to current handover.
- Legacy match/discipline infrastructure.
- Existing GitHub + Supabase integration.

### PARTIAL / NEEDS INTEGRATION
- Player profile as the new canonical product surface.
- Player identity/name/display mode and KYC linkage.
- Player DNA/attributes + organic evolution model.
- Player Card evolution/disciplinary presentation.
- Football Passport projection.
- Coach profile UI + complete certification UI.
- Referee profile and certification/stat presentation.
- Club profile / verification / staff/team/squad.
- Team Match Room and fixture-specific match-board experience.
- Competition registration automation from existing squads.
- KYC end-to-end frontend/backend integration.
- Payment architecture and transaction verification.

### DESIGNED BUT NOT YET PROVEN AS FULLY BUILT
- Organiser identity/profile/ownership model.
- Full competition self-service and rule engine.
- Complete club membership invitation/request/payment flow.
- Full venue discovery and future pitch-booking architecture.
- Social following/rating system.
- Developer master control panel.
- Complete audit/provenance UI.
- Complete career/passport projections.

### NOT STARTED / FUTURE
- Full wallet/eWallet/custody/settlement implementation.
- Full pitch booking marketplace.
- Mature AI/algorithmic organic attribute engine.
- Large-scale commercial card printing/collectibles system.
- Advanced scouting/marketing/sponsorship products.

**Rule:** a diagram box is never proof of implementation. Verify Git + live Supabase before changing a status to BUILT.

---

## 14. NEXT BUILD ORDER — DO NOT LOOP

The immediate product sequence is:

1. **Club** — finish the club “kedai”: identity, profile, verification, staff/admin, membership, teams/squads, interactive squad page, training, fixture list, TMR.
2. **Referee** — finish profile, licence verification, PlayPro certification, attributes/statistics, assignment/apply/offer flow, disciplinary state.
3. **Organiser** — first-class organiser identity/profile, organisation ownership, competition creation and management.
4. **Competition** — self-service setup, categories/rules/fees/registration/eligibility.
5. **End-to-end integration** — club squad → competition → fixture → referee/observer → TMR → official result → stats/discipline/history.
6. **Payments/wallet** — implement after transaction boundaries are stable.
7. **Developer master control** — controlled high-privilege admin tooling.

The Owner has already supplied the club flow and wants implementation to continue rather than return to generic architecture discussion.

---

## 15. TEAM MATCH ROOM — CANONICAL SOLUTION TO “TOO MANY MATCH BOARDS”

Never create one permanent board per team. Create one match room per **fixture instance**.

Example:

`U10A TEAM PAGE`
→ Upcoming Match 01 → TMR-01
→ Upcoming Match 02 → TMR-02
→ Upcoming Match 03 → TMR-03

After each match:
`TMR-01 → FINALIZED → LOCKED ARCHIVE`

The team page simply indexes these fixture rooms. Coach sees analysis/history; official data remains event/result based. A visual export/snapshot is optional and never replaces structured records.

This keeps the system scalable and preserves a clean source of truth.

---

## 16. PLAYER / COACH / REFEREE / CLUB RATING

PlayPro will eventually provide a social-integrity rating on people/entities.

Owner concept: all users can rate players/coaches/referees/clubs using a small set of PlayPro-defined reason/options. This rating is separate from:
- football attributes;
- DNA/OVR;
- eligibility;
- discipline.

It must be designed against abuse/manipulation, with provenance and moderation.

---

## 17. SOURCE-OF-TRUTH RULES

1. Identity/KYC = legal identity source.
2. Role profile = role-specific presentation/permissions projection.
3. Club membership = relationship history, not just `players.club_id`.
4. Team membership = assignment under a club membership.
5. Competition participation = explicit registration/eligibility, not automatic merely from club membership.
6. Match events = source for match-derived statistics.
7. Referee approval = official-result gate.
8. Discipline record/suspension ledger = discipline source.
9. Player Card = projection/product surface.
10. Football Passport = career/history projection.
11. Ratings = social-integrity projection, separate from football ability.
12. Payments/transactions/fees/refunds/settlements must remain separate states and records.
13. No duplicated “shadow” sources merely to make a UI easier.

---

## 18. ENGINEERING / SAFETY RULES

- Never expose service-account credentials or private keys.
- Never put secrets in Git.
- Never treat frontend fields as authoritative for role/permission.
- Backend/RLS must enforce authorisation.
- Never silently apply a migration because the design document says a table should exist.
- Inspect production before DDL.
- Preserve legacy data and provenance.
- Prefer additive, reversible migrations when possible.
- Keep migration history coherent.
- Do not use screenshots as official data storage.
- Do not replace live legacy attribute structures until mapping and migration are understood.
- Do not activate orphan frontend code merely because it exists in `public/src`.
- Do not confuse `playpro2` with `playpro1` or `sirr`.
- Do not claim “KYC complete” merely because a credential exists; prove the complete user journey and verification state.

---

## 19. HOW A NEW AI SHOULD TAKE OVER

### First 10 minutes

1. Read this file.
2. Read `docs/memory/AI_HANDOVER.md`.
3. Read `docs/memory/PLAYPRO_CANONICAL_ARCHITECTURE.md`.
4. Read `docs/memory/DECISIONS.md`.
5. Read `docs/memory/BOUNDARIES.md`.
6. Check GitHub `main` and active branches/PRs.
7. Check Supabase `playpro2` status and inspect only the tables/functions relevant to the current work.

### Then immediately

Create a compact status table:

`AREA | BUILT | PARTIAL | DESIGNED | NOT STARTED | NEXT ACTION`

Do not spend the session recreating the architecture map unless a concrete contradiction exists.

### If the previous AI “stuck”

Do NOT assume the project is lost.

The project state exists in:
- GitHub repository history/branches;
- Supabase `playpro2` production database;
- the canonical docs under `docs/memory/`.

The correct recovery action is **read → verify → continue**, not redesign from zero.

### If Owner says “teruskan sampai siap”

Execute the next defined work block. Do not ask the Owner to re-explain decisions already captured here. Stop only for a genuinely new business choice, destructive ambiguity, missing credential/permission, or safety-critical action that cannot be inferred from existing rules.

---

## 20. CURRENT OWNER DIRECTION

The Owner explicitly wants PlayPro built as an integrated ecosystem where:

`USER → ROLE → KYC → CLUB/TEAM → COMPETITION → MATCH → OFFICIAL DATA → PERFORMANCE/DISCIPLINE → PASSPORT`

is one continuous data chain.

The key competitive IP is **not merely the UI**. It is the connected real-life football data model: a player/coach/referee/club/organiser is a real identity; squads feed competitions; competitions feed matches; match events feed official records; official records feed statistics, discipline, ratings and career history; the Passport preserves the person's football history.

The next AI must protect that principle while actually building the product.

---

## 21. HANDOVER CHECKPOINT

**Status:** CONTINUITY DOCUMENT CREATED.

**Do not restart architecture. Do not repeatedly ask settled questions. Verify the live state and continue from the next build block.**

_Last updated for continuity: 2026-09-15._
