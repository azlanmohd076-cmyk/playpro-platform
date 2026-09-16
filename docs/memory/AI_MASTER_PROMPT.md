# PLAYPRO — AI MASTER PROMPT / CTO BUILD BRIEF

## 0. READ THIS FIRST

You are the next AI/CTO continuing development of **PlayPro**.

Do not treat this as a new project. Do not rebuild PlayPro from zero. Do not redesign the product because a newer visual style looks more modern.

Before touching code, read:

- `docs/memory/AI_HANDOVER.md`
- `docs/memory/PLAYPRO_CANONICAL_ARCHITECTURE.md`
- `docs/memory/DECISIONS.md`
- `docs/memory/BOUNDARIES.md`
- `docs/memory/ENVIRONMENT.md`
- `docs/memory/BACKLOG.md`
- current production truth / evidence files

Then inspect the actual GitHub repository and live Supabase `playpro2` state. Do not trust an old audit when live evidence is available.

The operating loop is:

`INSPECT → REASON → IMPLEMENT → TEST → VERIFY → COMMIT → DEPLOY WHEN SAFE → VERIFY PRODUCTION`

Do not stop at “the code looks correct”.

---

# 1. MOST IMPORTANT OWNER DIRECTIVE — UI

## PRESERVE THE OLD PLAYPRO UI

The original PlayPro UI is a **production/product asset**. It is the canonical visual baseline.

The rule is:

> **PRESERVE → AUDIT → REPAIR → IMPROVE**
>
> **NOT: REPLACE → REDESIGN → HOPE**

A previous AI introduced a newer generic dashboard/dossier-style UI. The Owner explicitly rejected that direction.

### ABSOLUTE PROHIBITION

**DO NOT TURN PLAYPRO INTO A DOSSIER UI.**

Do not use a generic SaaS dashboard aesthetic as the new PlayPro identity.

Do not replace the old football UI with:

- giant generic profile cards;
- excessive whitespace;
- generic “business dashboard” tiles;
- document/dossier layouts;
- generic modern admin-panel styling;
- a new landing page that hides or replaces the existing football UI;
- a completely different visual language merely because it is easier to code.

If a new page is required, it must feel like it belongs to the existing PlayPro application.

## What the old UI represents

The recovered old PlayPro source was identified in Git history at:

`36ec85739ac89fcbe3bdd0c27a73b8ca28abd963`

That source contains the established PlayPro football-platform identity, including the header/search treatment, Transfermarkt-style football navigation, bottom navigation, LIVE, CARI, MYTEAM, KEDAI, Passport and the existing football-oriented information density.

The Owner prefers the information-dense football-management-game character of **Championship Manager 01/02** for player data presentation, especially attributes and player information. This is a reference for information architecture and feel, not a request to clone copyrighted artwork or UI assets.

### Therefore:

**Old UI + new functions = target.**

Not:

**new UI + old functions = target.**

---

# 2. OLD UI vs REJECTED NEW UI

## OLD / CANONICAL DIRECTION

Characteristics to preserve:

- football-first information density;
- compact navigation;
- obvious football entities and relationships;
- player/club/team/match context visible without excessive drilling;
- Transfermarkt-like football information organisation;
- LIVE / CARI / MYTEAM / KEDAI shell where applicable;
- football-management-game style attribute presentation;
- Passport as a real career/history product surface;
- visual continuity across Player, Coach, Club, Referee and Organiser profiles;
- pages that feel like parts of one football ecosystem.

## REJECTED DOSSIER/DASHBOARD DIRECTION

Do not make PlayPro look like:

- a CRM;
- a corporate HR dossier;
- a generic analytics SaaS;
- a profile document with decorative cards replacing functional football data;
- a landing-page product where the actual modules are hidden behind generic tiles.

The new architecture is allowed to change **what the UI can do**, but it must not erase **how PlayPro feels**.

---

# 3. UI CHANGE POLICY

Every UI change must pass these questions:

1. Is the existing UI already capable of expressing the new function?
2. Can the function be added without changing the established visual language?
3. Is a new page genuinely required?
4. Can the new page reuse the old header, navigation, spacing, typography, tabs, cards, badges, tables, football terminology and interaction patterns?
5. Does the new screen look like PlayPro, or does it look like a different SaaS application?

If it looks like a different application, **stop and redesign the implementation inside the old language**.

Never perform a wholesale UI replacement without explicit Owner authorization.

---

# 4. PLAYPRO PRODUCT PRINCIPLE

PlayPro is not merely a football website.

It is a **real-world football identity, participation, performance, discipline, history and governance ecosystem**.

The fundamental principle is:

`ONE USER IDENTITY → MULTIPLE VALID ROLES → LINKED FOOTBALL DATA → ONE CANONICAL HISTORY`

A real user can progressively hold:

- Player
- Coach
- Club Owner
- Club Staff/Admin
- Referee
- Organiser
- Observer where permitted
- other approved capabilities

Do not create duplicate accounts for different roles.

Role profiles attach to the same user identity.

---

# 5. PLAYER — TARGET EXPERIENCE

The Player journey is:

`SIGN UP → CHOOSE PLAYER → PLAYER ONBOARDING → PLAYER PROFILE → ATTRIBUTES / DNA → PLAYER CARD → FOOTBALL PASSPORT → MATCH HISTORY → CAREER HISTORY → KYC / VERIFIED → CLUB / COMPETITION`

The Player profile must not be one giant form. Separate the data into appropriate pages/modules.

### Identity / name

Before KYC:

- user may enter legal name;
- user may enter display/nickname name;
- user may edit permitted identity fields;
- user may choose whether the profile/player card displays legal name or nickname, subject to privacy rules.

After KYC:

- legal name is synchronized from the verified identity document;
- verified legal name becomes locked;
- nickname remains editable;
- user can choose display mode according to PlayPro privacy/display rules.

### Player attributes

- scale: **1–20**;
- new/unassessed player attributes remain unassessed/null at the canonical data layer;
- presentation may use the agreed colour bands;
- player cannot arbitrarily self-edit attributes;
- official coach assessment and validated performance-derived mechanisms are the sources;
- attribute history must be preserved;
- future organic performance algorithms must be explainable, versioned and auditable.

### Player Card

Player Card is a major PlayPro product/IP surface.

It is not the source of truth.

It is generated from canonical player identity/profile + DNA/attributes + status.

The card may evolve visually according to the player's current progression/hierarchy.

Discipline affects card presentation automatically:

- active disciplinary action can darken/change the card;
- the card displays the relevant disciplinary notice/status;
- after the sanction expires, the card returns to the appropriate normal state automatically.

The Player Card may later support physical/digital collectible products and revenue models.

### Football Passport

Football Passport is the permanent longitudinal record of the player's football life.

It should preserve:

- identity;
- clubs;
- teams/squads;
- competitions;
- matches;
- minutes;
- statistics;
- assessments;
- attributes/DNA progression;
- discipline;
- achievements;
- career history.

Passport is a projection/history product, not the source of truth.

---

# 6. COACH

Coach is another role profile on the same user identity.

Flow:

`USER → CHOOSE COACH → SIMPLE ONBOARDING → KYC → VERIFIED COACH → COACH PROFILE COMPLETION → LICENSES → COACH ATTRIBUTES → CLUB / PRIVATE PLAYER WORK → CAREER HISTORY`

KYC is required early because a coach must be a real, valid person even when working privately with players.

KYC data is locked after verification; non-KYC coach profile data remains editable.

Coach profile should include:

- verified identity;
- personal details;
- profile photo;
- contact details as permitted;
- official FAM/FIFA/AFC or other recognised licence evidence;
- PlayPro Level 1–5 licence/certification;
- coach attributes;
- disciplinary status / coach card;
- career history when real participation data exists.

Two separate PlayPro certification tracks exist conceptually:

1. **Player Assessment Certification** — allows the coach to assess player attributes according to the level/certification obtained.
2. **Coach Attribute Certification** — evaluates the coach's own coaching attributes.

Coach attributes can come from:

- PlayPro assessment/course/exam;
- organic performance data derived from real team/competition outcomes.

Do not invent final formulas without Owner-approved methodology. Preserve provenance.

---

# 7. CLUB

Club flow:

`USER / PLAYER / COACH / REFEREE / ANY VALID USER → OWNER KYC → CREATE CLUB → CLUB IDENTITY → CLUB PROFILE → CLUB VERIFIED → STAFF/ADMIN → COACH → PLAYER → TEAM/SQUAD`

Club types must be extensible and can include, for example:

- professional club;
- semi-professional club;
- amateur competitive club;
- grassroots football academy;
- school / university / educational institution club;
- government department / agency club;
- women's football club;
- other approved organisation types.

Club type does not restrict the club's squad categories.

A club can create squads from **U6 through Veteran**, including multiple teams per category:

`U6 A/B/C... → ... → U23 A/B/C... → OPEN → VETERAN`

Squads do not exist until created by an authorised club owner/coach/admin.

Player eligibility for age-category squad placement must use verified football age/birth-year rules. A player cannot be placed into an age category below the applicable birth-year eligibility.

Club profile includes:

- club name;
- logo;
- owner;
- founded year;
- ROS/registration number where available;
- location;
- training ground(s);
- Google Maps pin/location;
- contact phone / WhatsApp link;
- club history;
- achievements;
- staff/admin;
- coaches;
- teams/squads;
- training schedules;
- fixtures.

Training-ground location is a future foundation for pitch discovery and booking.

---

# 8. CLUB MEMBERSHIP

Do not add users by name as the primary mechanism.

Preferred identity lookup:

- PlayPro Passport ID;
- PlayPro user ID;
- verified identity identifier where appropriate and privacy-safe.

Avoid relying on names because names can collide.

Membership can begin through:

1. Club invites user;
2. User requests to join club;
3. Other approved recruitment/offer mechanism.

For paid membership:

`INVITE/REQUEST → TERMS/FEES → USER ACCEPTANCE → PAYMENT → PLAYPRO PAYMENT VERIFICATION → ACTIVE MEMBERSHIP`

PlayPro fee model currently envisioned includes a **5% platform transaction fee** for supported club fee collection, subject to final commercial confirmation.

Coach/staff membership itself does not require player registration fees.

The club may choose whether to use PlayPro's fee collection system.

Payment, registration, approval and membership are separate states.

Do not merge them into one status.

---

# 9. TEAM / SQUAD / TMR

Every squad has its own page.

The squad page should include:

- staff;
- coach;
- player list;
- age category;
- formation;
- training;
- fixtures;
- match history;
- Team Match Room (TMR).

The squad is the operational bridge into competition participation.

When a squad enters a competition, the canonical squad/player data should flow into the organiser/competition/observer ecosystem automatically where eligibility permits.

Do not ask the organiser to manually re-register every player when canonical PlayPro data already exists.

### TMR principle

Do not create a permanent pile of independent match boards.

TMR is a reusable team-facing operational surface tied to **fixtures/matches**.

Each match gets its own match context and record. After the match, the operational state becomes part of the match record/history and is not a permanent duplicate dashboard.

---

# 10. REFEREE

Use **Pengadil / Referee**, not the Indonesian term “wasit”.

Referee has a real user profile.

Referee flow:

`USER → CHOOSE REFEREE → KYC → REFEREE PROFILE → OFFICIAL LICENCE → PLAYPRO ACCREDITATION → REFEREE STATS → MATCH ASSIGNMENT`

Official licence evidence may include recognised FAM/AFC/FIFA or relevant authority credentials.

PlayPro accreditation has two conceptual stages:

1. PlayPro system/function orientation;
2. refresher/observer-integrity training to reduce recurring operational errors.

Observer does not necessarily require PlayPro referee accreditation, but the referee is the match authority and must understand the observer workflow.

Referee statistics may come from:

- PlayPro accreditation/assessment;
- organic real-match data.

Referee can be invited/assigned or offer/request availability for competitions.

Payments for referee services should use PlayPro payment infrastructure when that workflow is enabled.

---

# 11. ORGANISER

Organiser is a first-class role/profile.

The Organiser/Event Console is **one shop inside PlayPro City**, not the whole city.

`PLAYPRO CITY = WHOLE PLATFORM`

`ORGANISER EVENT CONSOLE = ONE PRODUCT SURFACE INSIDE IT`

Organiser identity/ownership must be tied to a real PlayPro user or organisation model. Do not create fake organiser identities.

Organiser handles competition operations; PlayPro provides identity, data, payment, integrity and platform infrastructure.

---

# 12. MATCH / OFFICIAL RECORD

Locked flow:

`ORGANIZER SETUP → OFFICIAL FIXTURE → REFEREE + LINESMEN + OBSERVERS → MATCH START OPERATOR START → OBSERVERS RECORD → MATCH START OPERATOR END → MATCH REPORT → REFEREE APPROVE / RETURN → OFFICIAL MATCH RECORD → LOCK → DERIVED HISTORY/STATS/STANDINGS/DISCIPLINE`

Referee approval is the official gate.

Main observer is **not** the finalizer.

Match observations are not automatically official merely because an observer recorded them.

Official result is the source for downstream derived records.

Once officially locked, corrections must be controlled, audited and versioned.

---

# 13. DISCIPLINE / SUSPENSION

Discipline flow:

`EVENT → REFEREE REPORT / MATCH REPORT → SANCTION → SUSPENSION/BAN STATUS → ELIGIBILITY`

Suspension duration must come from competition/platform configuration, not hard-coded fallbacks.

Current PlayPro configuration includes the agreed current values for direct red and second-yellow dismissal; do not present these as universal FIFA rules.

A suspension is a ledger/history object, not merely a flag.

The system must track qualifying fixtures served and prevent double counting.

Player Card / Coach Card can reflect active discipline automatically.

---

# 14. RATING / REPUTATION

Player, Coach, Referee and Club can have a user rating/reputation mechanism.

Ratings must be separated from official football performance attributes.

Do not let arbitrary public ratings directly rewrite OVR or official attributes.

---

# 15. DEVELOPER MASTER CONTROL

PlayPro requires a dedicated developer/master control surface for authorised PlayPro Owner/Executive/Developer personnel.

It must allow authorised operators to manage/repair approved platform data without manually opening the database for routine administrative corrections.

This must be capability/context controlled and audited.

Never expose unrestricted database mutation to normal users.

Never create a client-side path that lets an ordinary user escalate to developer privileges.

---

# 16. SOURCE OF TRUTH

Always distinguish:

- identity source;
- KYC source;
- profile source;
- assessment source;
- match-event source;
- official-result source;
- discipline source;
- payment source;
- derived presentation.

Never create a second source merely because a UI needs a value.

Player Card, Passport, OVR, summaries and dashboards are projections/derived products unless explicitly designated otherwise.

---

# 17. MAP STATUS

The architecture/build map must visibly distinguish:

- 🟢 BUILT / VERIFIED
- 🟡 PARTIAL / FOUNDATION
- 🔵 DESIGNED ONLY
- 🔴 NOT STARTED / MISSING
- ⚠️ ARCHITECTURE DEBT / DRIFT
- ❓ NOT YET PROVEN

A box on the map is never proof of implementation.

Every completion claim must be tied to actual Git/Supabase/runtime evidence.

The map is a **PlayPro system map**, not a city illustration and not merely an organiser map.

---

# 18. IMPLEMENTATION PRIORITY

The next AI must stop spending cycles rewriting settled architecture.

Work through concrete product paths:

### Phase A — Player

`SIGN UP → PLAYER → PROFILE → KYC → VERIFIED → DNA/ATTRIBUTES → CARD → PASSPORT`

### Phase B — Coach

`SIGN UP → COACH → KYC → PROFILE → LICENCE → PLAYPRO CERTIFICATION → ATTRIBUTES`

### Phase C — Club

`OWNER KYC → CREATE CLUB → CLUB PROFILE → VERIFICATION → STAFF → COACH → PLAYER MEMBERSHIP → TEAM/SQUAD → TMR`

### Phase D — Referee

`KYC → PROFILE → OFFICIAL LICENCE → PLAYPRO ACCREDITATION → STATS → ASSIGNMENT`

### Phase E — Organiser / Competition

`ORGANISER → COMPETITION → RULES → REGISTRATION → SQUAD → FIXTURE → REFEREE/OBSERVER → MATCH → OFFICIAL RESULT`

### Phase F — Financial layer

`REGISTRATION / MEMBERSHIP FEES → PAYMENT → PLAYPRO FEE → SETTLEMENT → FUTURE WALLET`

### Phase G — Derived intelligence

`OFFICIAL MATCH DATA → STATS → DISCIPLINE → ELIGIBILITY → HISTORY → DNA / PERFORMANCE INTELLIGENCE`

---

# 19. ENGINEERING BEHAVIOUR

Do not repeatedly ask the Owner questions that have already been answered in project history.

When a problem is found:

1. inspect it;
2. determine whether it is code, schema, configuration, deployment or data drift;
3. repair it if within the locked architecture and authorised scope;
4. test it;
5. commit it;
6. deploy when safe;
7. verify the actual production surface.

Do not return merely with a list of problems if the problem can be safely fixed within the existing approved architecture.

Do not silently change a locked business rule.

If a genuine new product decision is unavoidable, isolate it as a decision/change request rather than contaminating the rest of the implementation.

---

# 20. FINAL ACCEPTANCE TEST

The work is not “done” because:

- Vercel says READY;
- a migration exists;
- a table exists;
- a page renders;
- a screenshot looks good;
- a local test passes.

The real gate is:

`USER ACTION → UI → BACKEND → SUPABASE → DERIVED STATE → UI`

and the complete path must be verifiable.

For UI work, also verify:

- the old PlayPro visual language is still recognisable;
- no dossier redesign has replaced it;
- existing routes/functions were not silently broken;
- mobile layout works;
- direct navigation works;
- refresh works;
- real production data is used where required;
- no fake demo data is presented as real;
- the new function is actually connected to the canonical data model.

## FINAL COMMAND

**Build the new PlayPro on top of the old PlayPro. Do not replace the old PlayPro with a new-looking application.**

Preserve its identity. Improve its usability. Add the new ecosystem capabilities. Keep the football-management information density. Keep the data connected. Keep the history permanent. Keep the source of truth clean.

**PlayPro should feel like the same application becoming vastly more capable — not like a different application wearing the PlayPro name.**
