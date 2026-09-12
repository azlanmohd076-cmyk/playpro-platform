# PLAYPRO COACH PROFILE — IMPLEMENTATION BASELINE

**Status:** IMPLEMENTED FOUNDATION · Supabase live + frontend route

## Canonical coach flow

`USER SIGN UP/LOGIN → CHOOSE COACH → SIMPLE IDENTITY (name + phone) → KYC → PLAYPRO VERIFICATION → COACH DETAILS → COACH PROFILE`

A user does not create a second account to become a coach. PlayPro supports a multi-role persona model: `player`, `coach`, `club_owner`, `organizer`, `referee`. `profile_role_profiles` is the role-profile registry; legacy `profiles.role` is not the multi-role source of truth.

## Identity rule

Before KYC, coach identity can be entered as onboarding data. After PlayPro approves KYC:

- legal/full name comes from the verified identity document;
- legal name is locked;
- date of birth is locked as verified identity data;
- preferred name remains editable;
- non-KYC coaching profile data remains editable;
- verification badge is shown only after KYC is verified.

## Coach profile data

The profile separates identity from coaching information. Current implemented fields include coaching role, official FAM/FIFA/AFC licence information, licence number/body/dates/status, preferred formation, preferred style, specialties, biography, verification state, discipline state, coach card state and PlayPro licence level.

## Coach attributes

Scale: `0–20`; `0` means not yet assessed.

Attributes:

1. Adaptability
2. Coaching Goalkeepers
3. Coaching Outfield Players
4. Working with Youngsters
5. Determination
6. Level of Discipline
7. Judging Player Ability
8. Judging Player Potential
9. Man Management
10. Motivating
11. Physiotherapy
12. Tactical Knowledge

The attribute value is not user-editable.

### Two sources of coach attributes

**Track B — Coach Attribute Certification:** the coach is assessed by a PlayPro panel through the PlayPro accreditation/exam process.

**Organic performance:** later, official competition performance from LTO/match data contributes to increases/decreases. This calculation engine is deliberately not hard-coded yet; it must be designed with a defensible mathematical model before enforcement.

## Two PlayPro accreditation tracks

**Track A — Player Assessment Authority**

Allows an accredited coach to assess Player DNA. Five levels establish the assessment authority bands:

- Level 1: 1–5
- Level 2: 5–10
- Level 3: 10–15
- Level 4: 15–20
- Level 5: final/practical authority

**Track B — Coach Attribute Certification**

The coach's own attributes are assessed/certified by the PlayPro panel. The same five-level course structure is retained, but it is a separate certification purpose from authority to assess players.

The database now records `certification_track` separately so these two purposes cannot be silently conflated.

## KYC

Coach KYC uses the existing private `kyc-documents` storage and `identity_verifications` model. A dedicated `kyc-verify-coach` Edge Function calls Google Document AI using the already configured server-side Google credentials/environment and never exposes service-account credentials to the browser.

Client flow:

`CREATE COACH → REQUEST KYC → PRIVATE DOCUMENT UPLOAD → GOOGLE DOCUMENT AI → PLAYPRO REVIEW → APPROVE → VERIFIED`

`approve_coach_kyc()` is privileged; normal coach users cannot self-verify.

## Discipline / Coach Card

Coach has its own coach card state and disciplinary state. The foundation supports `ACTIVE`, `DIMMED`, `SUSPENDED`, and `BANNED` states. Final sanction calculation remains governed by the canonical PlayPro disciplinary design.

## Frontend

`public/coach_profile_v2.html` is the CM-style Coach onboarding/profile screen. It uses the same compact database-screen visual language intended for PlayPro rather than a generic SaaS dossier.

## Deliberately not implemented yet

- full PlayPro assessment/equipment workflow;
- mathematical organic coach-attribute engine from LTO performance;
- coach career-history derivation from official club/competition records;
- final Coach Card artwork/evolution/collectible commerce;
- Club appointment workflow;
- final accreditation scheduling/exam administration UI.

These are next-stage work, not missing identity/profile foundations.
