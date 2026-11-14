# PLAYPRO COACH PROFILE — IMPLEMENTATION BASELINE

**Status:** COACH PROFILE UI REBUILT · LIVE BACKEND FOUNDATION REPAIRED · DEMO PAGES ADDED

## Canonical coach flow

`ONE PLAYPRO USER → ADD COACH ROLE → SIMPLE IDENTITY (name + phone) → KYC → PLAYPRO VERIFICATION → COACH DETAILS → COACH PROFILE`

A user does not create a second account to become a coach. `profile_role_profiles` is the multi-role registry; `profiles.role` remains a legacy primary-role field and is not the complete role source of truth.

## Identity and KYC

- Legal/full name is sourced from the approved identity document and locked after verification.
- Preferred name and non-KYC coaching information remain editable.
- Coach KYC uses the private `kyc-documents` bucket and `identity_verifications`.
- Document processing by Google Document AI is not final PlayPro approval.
- Only privileged PlayPro review can approve/reject Coach KYC.

## Coach profile UI

`public/coach_profile_v2.html` is now aligned with the Player Profile visual language: dark football-first presentation, compact hero, tabs, football attributes, license details and clear status indicators. It supports login, adding the Coach persona to the current account, profile editing, KYC submission/processing, loading Coach attributes and submitting certification requests.

## Coach attributes

Scale: `0–20`. Unassessed attributes remain `NULL` in the canonical database; the UI renders them as not assessed, not as fabricated scores.

The 12 attributes are:

1. Adaptability
2. Coaching Goalkeepers
3. Coaching Outfield Players
4. Working with Youngsters
5. Determination
6. Discipline
7. Judging Player Ability
8. Judging Player Potential
9. Man Management
10. Motivating
11. Physiotherapy
12. Tactical Knowledge

Values are not user-editable. The eventual organic performance engine based on official competition/LTO data remains unimplemented and must be deterministic, explainable and auditable.

## Two separate certification tracks

- **Track A — Player Assessment Authority:** certification course Levels 1–5. This is distinct from the operational Player DNA assessor accreditation Level 1–7, which is separately granted by an authorised Developer through `coach_accreditations`.
- **Track B — Coach Attribute Certification:** evaluates the Coach's own coaching attributes, also through course Levels 1–5.

The request and review RPCs now use the current database columns, keep the two tracks separate, prevent duplicate open requests, require verified Coach KYC before requesting, and restrict review to Developer. The legacy request RPC is routed through the same guarded workflow. A request approval schedules the course; it does not fabricate a passed certificate.

## Player assessment authority

Official Player DNA submissions use the canonical 18 Player attributes, scale 1–20, through `get_assessment_workspace()` and `submit_player_assessment()`. They require an active Technical Assessor profile with active operational accreditation Level 1–7. Demo players are excluded. Assessment history records coach identity, level and timestamp.

## Coach demo pages

Three separate static pages exist under `public/demo-coaches/`:

- `coach-demo-level-1.html`
- `coach-demo-level-3.html`
- `coach-demo-level-5.html`

These are fictional UI fixtures only. They are labelled DEMO / NOT VERIFIED and do not create real Coach accounts, real KYC status, licences, or assessment authority.

## Deliberately not implemented yet

- Organic Coach attribute calculation from official team/competition/LTO performance.
- Coach career-history derivation from official club/team/competition records.
- Final Coach Card artwork/evolution/collectible commerce.
- Club appointment workflow.
- Final accreditation scheduling/exam administration UI and full practical/video exam workflow.

These remain future work; the current profile, KYC, certification request and Player DNA assessment foundations are separate and must not be conflated.
