# AI HANDOVER — PLAYPRO CURRENT STATE

**READ THIS BEFORE MODIFYING PLAYPRO.**

## Current source of truth

For the current match/discipline and product architecture, read:

1. `docs/memory/PLAYPRO_CANONICAL_ARCHITECTURE.md` — current Owner-approved operational architecture.
2. `docs/memory/DECISIONS.md` — historical append-only decision register. Do not delete history.
3. `docs/memory/BOUNDARIES.md` — lifecycle and authority boundaries.
4. `docs/memory/ENVIRONMENT.md` — repository/Supabase environment.
5. `docs/memory/BACKLOG.md` — work orders and gates.

## Owner product direction — current build order

PlayPro is one connected ecosystem. A user has one PlayPro identity and may activate multiple role profiles without creating another account:

`USER → PLAYER / COACH / CLUB OWNER / ORGANISER / REFEREE`

Role profiles are extensions of the same verified user identity. They must never become disconnected duplicate identities.

Current product build order:

`PLAYER → COACH → CLUB → REFEREE → ORGANISER`

KYC is the identity/verification layer that links the role profiles to a real person. A normal user may exist without KYC; a role requiring verified identity must complete the relevant KYC gate.

## Player — current approved model

Player onboarding is deliberately separated into stages; do not put all player data into one giant form.

`SIGN UP → CHOOSE PLAYER → PLAYER ONBOARDING → PLAYER PROFILE → DNA/ATTRIBUTES → PLAYER CARD → FOOTBALL PASSPORT → MATCH/CAREER HISTORY → KYC/VERIFIED → CLUB → COMPETITION`

Signup supports manual registration plus **Google and Facebook** sign-in.

Before KYC, the player may maintain both a legal-name field and a preferred/nickname/display name. After KYC, the legal identity name is taken from the verified identity document and is immutable except through an authorised KYC/legal-name correction flow. The user can choose whether the public profile and Player Card display the verified real name or the nickname/display name, subject to privacy rules.

Player attributes are not user-entered. New/unassessed players begin with no assessed attribute value. The football attribute scale is **1–20** with the agreed presentation bands:

- 1–5 = red
- 5–10 = yellow
- 10–15 = blue
- 15–20 = green

Official player assessment is performed by PlayPro-accredited coaches. Match/LTO performance can later produce organic performance-derived attribute movement. The long-term attribute algorithm must be deterministic, explainable, versioned and auditable; do not invent or silently change the scoring formula.

The Player Card is a separate product surface, not a simple database card. It is a shareable/evolving identity and marketing asset derived from player profile + DNA. It may change visual tier as DNA changes and must visibly reflect disciplinary status. A disciplinary sanction can darken the card and display the action; the card automatically returns to its normal state after the sanction ends.

Football Passport is the permanent career-history projection: a player's football journey, participation, clubs, teams, matches, statistics, achievements, discipline and relevant historical records. It is not a disposable current-profile snapshot.

## Coach — current approved model

Coach is another role profile on the same PlayPro user identity.

`USER → COACH → SIMPLE ONBOARDING → KYC → KYC-GENERATED PROFILE → COACH ONBOARDING → LICENSES → PLAYPRO ACCREDITATION → CLUB/TEAM → CAREER/PERFORMANCE HISTORY`

Coach KYC is required from the beginning because a coach must be a known/legitimate person even when operating privately rather than through a club. KYC-derived identity data is immutable except authorised correction; coaching information remains editable.

Coach profile UI keeps **Verification** with the personal details area near the top. The licence area has two distinct tracks:

1. Official FAM/AFC/FIFA (or recognised governing-body) licence, including supporting document upload and verification.
2. PlayPro accreditation level 1–5, earned through PlayPro courses.

There are two PlayPro coach certification tracks:

- **Player Assessment track:** accreditation permits the coach to assess player attributes within the authorised 1–20 band. Five courses progressively authorise higher attribute bands; the exact assessment module is a later implementation block.
- **Coach Attribute track:** the coach is assessed by the PlayPro panel and receives their own coach attributes.

Coach attributes also have an organic performance component derived from team/competition results and LTO data. The authoritative algorithm is future IP and must be versioned/auditable rather than manually altered.

The coach profile has its own coach ID/card and disciplinary state. Coach career history is derived only after actual club/team/competition participation produces evidence.

## Shared role-profile rule

Every PlayPro user may have any combination of:

`PLAYER + COACH + CLUB OWNER + ORGANISER + REFEREE`

The UI should remain structurally consistent across role profiles while each role exposes its own domain data, permissions, certification, history and card. Never create a second user merely because the person activates another role.

The live `user_role` enum already includes `developer`, `league_founder`, `league_admin`, `club_admin`, `coach`, `technical_assessor`, `player`, `referee`, `club_owner`, and `organizer`. Do not add duplicate identity concepts without inspecting the live model first.

## Club — current approved model

Club flow:

`USER/PLAYER/COACH/REFEREE/ANYONE → CLUB OWNER + KYC → CREATE CLUB → CLUB IDENTITY → CLUB PROFILE → CLUB VERIFIED → STAFF/ADMIN → COACH → PLAYER → TEAM/SQUAD`

Club identity/profile includes name, logo, owner profile, founding year, optional ROS registration, contact/WhatsApp, location, training grounds, and historical achievements/competition record.

Club type is configurable and does not restrict the age categories the club may create. Current examples include professional, semi-professional, amateur league club, grassroots football academy, school/university/institutional club, government-agency/department club and women's football club. The model must remain extensible.

Training grounds should support a Google Maps location/pin. Future roadmap: pitch/venue owners can link venues to PlayPro so users and organisers can search and eventually book pitches through PlayPro. Do not implement booking/custody mechanics prematurely.

Club membership is linked to real PlayPro users. Preferred lookup/add mechanisms are:

1. PlayPro ID / Passport ID;
2. verified identity/IC number where authorised;
3. player/coach request to join the club.

Name-only lookup is not the authoritative identity mechanism because names can collide.

Club invitation/acceptance/payment/verification must remain separate states. Where a club enables PlayPro fee collection, PlayPro is the payment/verification layer and charges the agreed platform fee (currently specified by Owner as 5% for the relevant transaction flow). Coaches/staff do not pay a club-entry fee. The fee-collection feature is optional per club, not mandatory for every club.

Teams/squads are created by the club owner or authorised coach. A club can create categories from **U6 through U23**, open-age, and veteran (35+), with multiple teams per category such as U7A/U7B/U7C. Squad membership must use real PlayPro profiles and enforce age/eligibility rules from KYC/competition rules.

Each team/squad has its own page and a contextual **Team Match Room (TMR)**. TMR is not club history. It is the operational/analysis surface for a particular fixture and must be instantiated per match/fixture, then retained as match evidence/history rather than creating one permanent board per team. Match data flows from fixture → TMR → observer/referee operations → official result → history/statistics/discipline.

The squad page includes formation selection and an interactive pitch. Coaches can place/drag real squad players into positions and open the player's real PlayPro profile from the pitch. The squad is the source used for competition participation so organisers do not manually recreate player registrations.

Training schedules, locations and upcoming fixtures belong to the club/team operations surfaces and must link back to the same team, venue and fixture objects.

## Referee — current approved model

Referee is a first-class role profile on the same PlayPro user identity.

`USER → REFEREE → ONBOARDING → KYC → OFFICIAL LICENCE → PLAYPRO REFEREE ACCREDITATION → REFEREE ID/CARD → ASSIGNMENT`

Official referee licence evidence (FAM/AFC/FIFA or recognised authority) is uploaded for PlayPro verification. Referee profile has its own referee ID/card and disciplinary state.

PlayPro referee accreditation currently has **2 levels**:

1. Level 1 — orientation to PlayPro and match-operation functions.
2. Level 2 — refreshment and observer protocol to reduce repeated operational mistakes.

Observers do not require PlayPro accreditation. The referee is the operational head of the observer structure for the match.

Referee statistics can have two sources: accreditation/assessment-derived capability and organic LTO/match performance. Do not invent the final referee rating formula before the scoring model is designed and versioned.

Referee can participate in official competitions through assignment/invitation or by offering availability. Payments for official referee work must flow through the future PlayPro payment system rather than ad-hoc parallel payment records.

Informal/in-house matches may use the same Match Board/Observer/Referee tooling for organisation and familiarity but are not automatically official records. Official recognition depends on the defined official-competition/referee rules.

## Rating / integrity layer

Player, coach, referee and club profiles have a PlayPro user-rating mechanism. Ratings are user-generated integrity/reputation signals and must remain separate from football attributes, DNA, eligibility, certification and disciplinary source data. The exact four rating reasons/options are Owner-defined product data and must not be conflated with OVR/DNA.

## KYC / verification boundary

KYC is not the same thing as public-profile visibility and not the same thing as an official football credential.

- Normal PlayPro user: may use the platform without KYC and remains unverified.
- Player: KYC is required when entering the verified football ecosystem where identity proof is needed (for example club/competition participation).
- Coach: KYC is required at coach onboarding.
- Club owner: KYC is required before creating/operating a verified club.
- Referee: KYC is required before verified referee operation.
- Organiser: identity/ownership/KYC requirements apply according to the organiser verification model.

A verified role displays a small verified badge on the user's relevant profile. Do not expose KYC documents publicly.

## Player/Coach/Club/Referee data integrity

PlayPro's core IP is the connected data graph:

`ONE REAL USER → ROLE PROFILES → CLUB → TEAM/SQUAD → COMPETITION → FIXTURE/MATCH → OBSERVER EVENTS → REFEREE APPROVAL → OFFICIAL RECORD → STATS/DISCIPLINE/HISTORY/PASSPORT`

Do not duplicate registration data when an existing PlayPro identity/profile can be linked. Do not allow fabricated users to stand in for real participants.

## Locked match flow

`ORGANIZER SETUP → OFFICIAL FIXTURE → 1 REFEREE + 2 LINESMEN + 2 OBSERVERS → MATCH START OPERATOR START → OBSERVERS RECORD INDEPENDENTLY → MATCH START OPERATOR END → MATCH REPORT → REFEREE APPROVE / RETURN → OFFICIAL MATCH RECORD → LOCK → DERIVE HISTORY/STATS/STANDINGS/DISCIPLINE`

**Do not restore observer-to-observer approval.**

Referee approval is the official gate. Main observer is not the finalizer.

## Locked discipline flow

`EVENT → REFEREE REPORT / MATCH REPORT → SANCTION → SUSPENSION/BAN STATUS → ELIGIBILITY`

Suspensions count against qualifying **official team fixtures**, not against registration attempts. A suspended player does not have to be re-registered for every match. `REGISTERED ≠ ELIGIBLE`.

Direct red-card and second-yellow suspension lengths are configuration values in the competition-rule/suspension ledger model, not hard-coded universal constants. The existing suspension ledger records serving-fixture evidence and prevents double counting.

PlayPro's 3-month ban is a PlayPro competition/platform rule and must not be described as a universal FIFA rule. Appeal fee is RM100 and is non-refundable.

## Implemented correction — 2026-09-12

The two live production defects identified by Owner were corrected in `playpro2` and the migration was committed in Git:

1. `finalize_match(uuid)` is **referee-gated**. The appointed referee must be the authenticated user and have `user_role = referee`. The main observer can no longer finalize the match. Referee approval writes the existing `match_results.is_official / ratified_by / ratified_at / entered_by` gate, then moves the ended fixture to `finalized`.
2. `auto_suspend_on_red_card()` no longer has the obsolete `COALESCE(..., 1)` fallback. Suspension length is read from `competition_rule_config`; current PlayPro configuration rows are seeded as **2 matches for direct red** and **1 match for second-yellow dismissal**. These are configuration values, not universal FIFA constants.
3. An official-result trigger advances active suspensions by qualifying official fixture for the sanctioned player's club. The suspended player does **not** need to be registered or selected in the serving match. The start fixture is excluded, and served fixture IDs are recorded to prevent double counting.
4. The existing `suspensions` table records the club context, rule configuration, remaining matches, served fixture IDs and completion timestamp needed for the ledger mechanism.

## Recent implementation context — club/referee surfaces

The repository contains the implemented referee operations surface from commit `0f94fd84063f564f75f396e39602e880bf8e1e73`, including referee onboarding, official licence upload/verification, PlayPro Level 1/2 accreditation requests, referee ID/card presentation and developer verification controls.

The live Supabase model inspected for coach/referee work includes `coach_assessments`, `coach_attribute_state`, `coach_certification_courses`, and `coach_certification_requests`. Coach attribute state includes fields such as adaptability, coaching goalkeepers/outfield/youth, determination, discipline, judging player ability/potential, man management, motivating, physiotherapy and tactical knowledge, with provenance fields such as source/confidence/assessed_at.

`football_passport_no` already exists in the live player-related model. Do not invent a duplicate passport identifier without inspecting the current schema.

The PlayPro identity role enum in live `playpro2` includes the role values required for the multi-role user model, including `player`, `coach`, `referee`, `club_owner`, and `organizer`, plus existing administrative roles.

## Product map boundary — important

Do **not** call the Organiser/Event map the whole “PlayPro City”.

The correct mental model is:

`PLAYPRO CITY = keseluruhan platform`

`ORGANISER EVENT CONSOLE = satu “kedai” di dalam bandar PlayPro`

The organiser/event area is one product surface inside the wider platform. It must not be mistaken for the entire platform architecture.

The next map must show each major surface as **BUILT / PARTIAL / DESIGNED ONLY / NOT STARTED**. The fact that an architecture box exists does not prove implementation.

Known major areas still requiring concrete implementation or completion include player KYC/verification completion, full Player DNA/attribute engine, Player Card productisation, Passport/history projections, coach certification/assessment module completion, club/team operations completion, referee statistics/assignment completion, organiser profile/identity, competition setup/rules, payment/eWallet/fee collection, social follow/privacy, ratings, and the final integrated front-end routing.

## Safe engineering rules

- Preserve provenance and audit history.
- Do not silently create a second source of truth.
- Do not hard-code competition-specific rules where configuration is required.
- Do not perform DDL/migrations/deployment merely to make a design document look complete.
- If a live object already exists, inspect it before proposing a replacement.
- If an old decision conflicts with a later Owner decision, mark it `SUPERSEDED`; do not erase history.
- Never assume a table/column/function is absent from production because a Git migration file does not contain it.
- Never treat a row count or textual search as proof of a design fact without measuring the actual object.
- KYC documents and identity evidence are private; never expose them through public profile endpoints.
- Keep payment, registration, approval, membership and eligibility as separate states.
- Keep official football data separate from social/reputation signals.
- Do not turn a temporary operational UI into a permanent source of truth when a fixture/match entity should own the data.

## Current Supabase reference

`playpro2` = `muirhenvjruvfxenoaxm` and is the active production reference.

Live facts currently established include:

- `user_role` includes `player`, `coach`, `referee`, `club_owner`, `organizer` and existing administrative roles.
- `football_passport_no` exists in the player-related live model.
- Coach assessment/certification/attribute-state tables exist in live production.
- The referee implementation uses the existing referee identity/verification model and PlayPro accreditation surfaces.
- The 2026-09-12 match finalization and suspension-rule corrections are applied as described above.

These are production facts, not blanket permission to make unrelated DDL. Inspect the live object before extending it.

## Current build status discipline

Use these exact labels when updating the product map:

- **BUILT** — concrete Git + live/runtime evidence exists.
- **PARTIAL** — some implementation exists, but the end-to-end path is incomplete.
- **DESIGNED ONLY** — architecture/UI/spec exists without verified working implementation.
- **NOT STARTED** — no meaningful implementation exists.

Never promote a feature from DESIGNED/PARTIAL to BUILT merely because a table, HTML page, migration file or diagram exists.

## Next work

Keep moving forward. Do not loop back into already settled observer/approval/suspension questions.

The next concrete work is the **wider product map and completion of the real connected surfaces**, then continue into the next role/domain build. Every work block should leave a concrete artifact or a working implementation; avoid documentation-only loops when implementation is already authorised.

**Owner intent:** keep moving. Minimize repeated audits. Do not ask the Owner to repeat decisions already recorded here or in `DECISIONS.md`. If the required direction is already explicit, execute it and record the result.
