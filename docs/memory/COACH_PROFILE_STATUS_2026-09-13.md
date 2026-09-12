# PLAYPRO — COACH PROFILE BUILD STATUS

**Date:** 2026-09-13
**Scope:** Coach identity/profile foundation + CM-style profile surface
**Status:** BUILT FOUNDATION / FRONT-END PROFILE PAGE ADDED

## 1. Implemented

- Existing `public.coaches` model extended without deleting legacy columns/data.
- Human-facing `coach_code` generated as `COA-000001`, etc.
- Coach-specific profile fields: preferred name, bio, visibility, display-name mode, coaching role, formation, style, specialties.
- License fields: type, number, issuing body, issue/expiry dates, and license status.
- Coach verification state prepared for KYC; unverified by default.
- Multi-role identity bridge `profile_role_profiles` added so one account can carry player/coach/club-owner/organiser/referee identities without deleting the existing `profiles.role` model.
- CM-style coach attribute state added on 1–20 scale; `0` means not yet assessed.
- Five PlayPro accreditation-course records and accreditation-request workflow added. Course 1–5 bands are represented; Course 5 is the practical/final certification gate.
- Coach disciplinary record foundation added, including active/completed/appealed/revoked status, suspension/ban information, evidence and provenance.
- Existing `save_coach_onboarding_profile()` upgraded to create/update the actual `coaches` record and role bridge instead of only changing `profiles`/assessor data.
- New standalone `public/coach_profile_v2.html` added with compact CM-style information-dense UI.
- Vercel route `/coach-profile` added for the new page.

## 2. CM-style design direction

The coach profile deliberately uses a compact database/management-game layout rather than a modern social dossier: dense information panels, table-like rows, 1–20 attributes, staff-role information, preferred formation/style, accreditation progression and disciplinary state.

The attribute model is informed by the CM01/02 staff model: Coaching Goalkeepers, Coaching Outfield Players, Working with Youngsters, Motivating and Discipline are core training-oriented attributes; Tactical Knowledge, Determination, Adaptability and Man Management are also retained as useful staff attributes. CM01/02 references also describe specialised coaching areas and preferred formation/style. This is inspiration for PlayPro UI/model semantics, not a claim that PlayPro uses CM's proprietary calculations.

## 3. Intentionally NOT built yet

- Coach assessment module itself (measurement workflow/equipment and assessor scoring UI).
- Automatic coach-attribute evolution algorithm.
- Player assessment billing/payout implementation.
- Full KYC submission/review UX for coach; existing identity-verification infrastructure is shared and ready to be linked.
- Club appointment/acceptance workflow for coach.
- Coach career history derivation from official fixtures.
- Full coach card artwork/evolution/revenue product system; current profile page has the card-state surface only.
- Developer master-control implementation beyond existing developer/RLS foundations.

## 4. Important boundaries

- KYC is required before a coach is accepted into a club, while an ordinary coach profile can exist unverified.
- The user's display-name choice is separate from legal identity. KYC/identity data must not be treated as an editable public nickname.
- Coach accreditation controls the authority to assess **players**. It does not mean a coach may self-edit player attributes.
- Existing legacy `coach_assessments` remains intact. The new 1–20 `coach_attribute_state` is the PlayPro presentation/state foundation and should be reconciled with the legacy 1–100 assessment structure during the later assessment-engine design rather than silently deleting or rewriting it.
- Existing player/match systems remain untouched by this coach-profile migration.

## 5. Next build gate: CLUB

The coach profile is now sufficiently modelled to move to the club build. Club work should connect:

`USER → CLUB OWNER ROLE → CREATE CLUB → CLUB IDENTITY → OWNER/KYC → CLUB PROFILE → STAFF/COACH APPOINTMENT → PLAYER REGISTRATION → TEAM/SQUAD → COMPETITION`

The club build must use the coach/profile identity already established here and must not create a second user/coach identity model.
