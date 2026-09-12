# PLAYPRO PLAYER PROFILE — CANONICAL BUILD BASELINE

**Status:** IMPLEMENTED FOUNDATION · 2026-09-12

## 1. Canonical flow

`SIGN UP → CHOOSE PLAYER → PLAYER ONBOARDING → PLAYER PROFILE → ATTRIBUTE/DNA → PLAYER CARD → FOOTBALL PASSPORT → MATCH HISTORY → CAREER HISTORY → VERIFY → CLUB → TOURNAMENT`

This build starts with the player and deliberately keeps each information group on its own page/step. A normal PlayPro account does **not** need KYC. A player becomes **Verified** only after the KYC process required when entering a club/competition.

## 2. Sign-up

Supported registration methods for the player entry point:
- email + password;
- Google OAuth;
- Facebook OAuth.

The account is created as `player`; the browser never writes the authoritative role into `profiles`.

## 3. Player onboarding

Separate screens:
1. **Identity:** full name, optional preferred name, optional bio, date of birth, nationality.
2. **Football profile:** position, preferred foot, jersey number, height, weight, photo.
3. **Privacy:** Public or Private.

No DNA/attributes are entered by the player.

## 4. Profile

The player profile is data-first. Core identity stays visible in the main profile while social activity lives in a separate **Wall** tab. The player can edit permitted profile fields later.

Private profile behaviour:
- public users cannot view the full profile;
- a user can request Follow;
- the player can approve/reject/block the request;
- approved followers can view the profile while it remains private.

## 5. Football DNA / attributes

The production `player_assessments` legacy structure is preserved as historical assessment evidence. The new `player_attribute_state` table is the current 18-attribute presentation/state layer.

Scale:
- 0 = not assessed;
- 1–5 = red;
- 6–10 = yellow;
- 11–15 = blue;
- 16–20 = green.

Players cannot self-assign attributes. Coach assessment and later organic match-derived movement are separate sources. The AI engine is intentionally **not active in this phase**; no AI is allowed to silently alter a player's attributes.

## 6. Player Card

The card is a separate shareable product surface. It uses player profile + DNA and exposes six position-relevant attributes. Card tier terminology is provisional until the Owner locks the final names.

Current presentation ladder:
`0–19 BASIC · 20–39 NOVICE · 40–59 INTERMEDIATE · 60–79 ADVANCED · 80–100 PRO`

## 7. Football Passport

The Football Passport number is platform-generated and remains attached to the player's lifelong football record. Match history, career history and verified achievements are intended to accumulate rather than disappear when a player changes club or stops playing.

## 8. Social wall

Player status updates are supported through a separate Wall tab so the core profile does not become cluttered. Posts are limited to 500 characters in the current foundation.

## 9. Security boundary

Raw `players` reads are no longer the public profile API. Public profile access uses `get_player_profile()`, which returns safe profile data and honours Public/Private + approved follower state. KYC identifiers are not exposed by the player profile RPC.

## 10. Match-data relationship

Official match data will feed player history automatically only after the referee approval → official record gate. The player profile must never require an observer to manually copy match statistics into the profile.

## 11. Deferred by design

- KYC document capture/verification UI;
- coach assessment request + payment split;
- organic attribute algorithm;
- AI attribute engine;
- full career-history migration;
- production marketplace/physical card fulfilment.

These are not forgotten; they are the next layers on top of the player foundation.
