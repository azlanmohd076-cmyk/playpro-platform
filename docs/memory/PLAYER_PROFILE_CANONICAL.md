# PLAYPRO PLAYER PROFILE — CANONICAL BUILD BASELINE

**Status:** PLAYER FOUNDATION IMPLEMENTED · 2026-09-12

## 1. Canonical flow

`SIGN UP → CHOOSE PLAYER → PLAYER ONBOARDING → PLAYER PROFILE → ATTRIBUTE/DNA → PLAYER CARD → FOOTBALL PASSPORT → MATCH HISTORY → CAREER HISTORY → VERIFY → CLUB → TOURNAMENT`

The current player build keeps each information group separated while presenting the player profile as a compact, data-first football record. A normal PlayPro account does **not** need KYC. A player becomes **Verified** only after the KYC process required when entering a club/competition.

## 2. Sign-up

Supported registration methods for the player entry point:
- email + password;
- Google OAuth;
- Facebook OAuth.

The account is created as `player`; the browser never writes the authoritative role into `profiles`.

## 3. Player onboarding

Separate screens:
1. **Identity:** editable full/legal name before KYC, optional preferred name, optional bio, date of birth, nationality.
2. **Football profile:** position, preferred foot, jersey number, height, weight, photo.
3. **Display + privacy:** choose whether the public display uses legal name or preferred name; Public or Private profile.

After KYC is verified, `players.full_name` becomes locked to the verified legal name. `preferred_name` remains editable. `display_name_mode` controls which name is shown on the profile and Player Card.

## 4. Profile

The player profile is intentionally **CM01/02-inspired: dense, data-first and immediately readable**, not a form-like dossier. Identity, club and key facts sit beside the main football data. Social activity lives in a separate **Wall** tab.

Private profile behaviour:
- public users cannot view the full profile;
- a user can request Follow;
- the player can approve/reject/block the request;
- approved followers can view the profile while it remains private.

## 5. Football DNA / attributes

The production `player_attribute_state` legacy/current structure is preserved. The current player UI exposes the 18 existing attributes rather than replacing the legacy model.

Scale:
- 0 = not assessed;
- 1–5 = red;
- 6–10 = yellow;
- 11–15 = blue;
- 16–20 = green.

Players cannot self-assign attributes. Coach assessment and later organic match-derived movement are separate sources. The AI engine is intentionally **not active in this phase**; no AI is allowed to silently alter a player's attributes.

## 6. Player Card

The card is a separate shareable product surface. It uses player profile + DNA and exposes six position-relevant attributes. The face-stat philosophy references the familiar FIFA/EA six-stat card model (outfield: PAC/SHO/PAS/DRI/DEF/PHY; goalkeeper uses a dedicated GK set), while PlayPro's underlying DNA remains its own 1–20 intellectual property. citeturn1search0turn1search3

Current presentation ladder:
`0–19 BASIC · 20–39 NOVICE · 40–59 INTERMEDIATE · 60–79 ADVANCED · 80–100 PRO`

The tier names remain provisional until the Owner locks the final terminology.

Disciplinary state is part of the card state: an active suspension causes the card to switch to a darker disciplinary presentation and show the action/reason. When the suspension completes, the card returns automatically to its normal presentation. The source is the disciplinary/suspension record, not manual card editing.

## 7. Football Passport

The Football Passport is the lifelong football record. It is **not** the user's MyKad/passport number.

After successful KYC, PlayPro generates a sequential platform user number and a human-readable Passport ID:

`PREFIX-STATE-USERNO`

Example:
`ZLAN-05-0001` = PlayPro user #1 with birth-state code 05.
`ZLAN-05-1127` = PlayPro user #1,127.
`ZLAN-05-500027` = PlayPro user #500,027.

The numeric sequence is stored separately from the display string so it can scale to hundreds of thousands/millions without introducing `K`/`KK` ambiguity. The legal identity remains separate from the display name.

## 8. Social wall

Player status updates are supported through a separate Wall tab so the core profile does not become cluttered. Posts are limited to 500 characters in the current foundation.

## 9. KYC / Verified

KYC is **conditional**, not part of ordinary account use. The player can remain an unverified normal user. KYC is requested when the player needs to enter a club or competition.

Current backend foundation:
- generic `identity_verifications` table for player/coach/club-owner/organizer/referee subjects;
- supported ID types: `mykad`, `mykid`, `passport`;
- raw identity numbers are not stored by the player profile API;
- KYC request status is tracked as `pending / verified / rejected / cancelled`;
- privileged PlayPro verification approval updates the verified legal name, verification timestamp and Passport ID.

The small Verified badge is shown on the relevant role profile after `verification_status='verified'`.

## 10. Match-data relationship

Official match data will feed player history automatically only after the referee approval → official record gate. The player profile must never require an observer to manually copy match statistics into the profile.

The current profile already calls the official match-history RPC. Further career aggregation remains a separate implementation layer.

## 11. Current implementation status

- 🟢 **Implemented:** player sign-up entry with email/password, Google and Facebook OAuth.
- 🟢 **Implemented:** player onboarding identity, football profile, display-name choice and Public/Private visibility.
- 🟢 **Implemented:** 18-attribute DNA presentation with 1–20 scale and colour bands.
- 🟢 **Implemented:** CM-style player profile hub with DNA, Card, Passport, Match History, Career and Wall surfaces.
- 🟢 **Implemented:** Player Card surface and disciplinary-state backend hook.
- 🟢 **Implemented foundation:** conditional KYC request, verification state and sequential Passport ID generation on privileged approval.
- 🟡 **Next:** complete KYC document capture/provider verification and connect club/competition entry gates.
- 🟡 **Next:** coach assessment request + payment split.
- 🟡 **Next:** organic attribute algorithm.
- ⚪ **Deferred:** AI attribute engine until the measurement methodology is proven.
- 🟡 **Next:** full career-history aggregation and historical record migration.
- 🟡 **Next:** production marketplace/physical card fulfilment.

## 12. Non-negotiable data principles

1. Legal identity, public display name and preferred name are separate concepts.
2. KYC is the authority that locks legal identity; users cannot edit verified legal name.
3. Player DNA is never self-assigned.
4. Match-derived attribute movement must be deterministic, auditable and based on official records before it is activated.
5. AI cannot silently become a source of truth for DNA.
6. Player Card is a product/IP surface, not a disposable UI thumbnail.
7. Football Passport is a lifelong record and must survive club changes, career breaks and role expansion.
