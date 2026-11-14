# PlayPro Prototype 2.0 — Journey 01: Login to Player Profile

Status: Phase 1 audit draft  
Date: 15 November 2026  
Branch: `feat/playpro-prototype-2.0`  
Data boundary: synthetic prototype data only; no production Supabase writes.

## Goal

Show the complete first-time player journey from the PlayPro entry point to a created Player Profile. The flow must feel like one continuous product, not a collection of disconnected forms.

## Current production baseline found in repository

Evidence inspected:
- `public/index.html`: shared login/register modal, email/password login, Google/Facebook/X OAuth entry points, password reset, role selection, registration and post-login routing.
- `public/player_signup.html`: dedicated player signup page with email/password, Google and Facebook OAuth. It redirects an authenticated session to player onboarding.
- `public/player_onboarding_v2.html`: three onboarding screens:
  1. Identity — legal name, preferred name, bio, date of birth, nationality.
  2. Football profile — primary position, dominant foot, jersey number, height, weight and profile photo.
  3. Display name and privacy — legal/preferred display name and public/private visibility.
- `public/player_profile_cm.html`: profile hub with DNA, Player Card, Football Passport, official match history, career and Wall.
- `docs/memory/PLAYER_PROFILE_CANONICAL.md`: canonical player product baseline.
- `docs/memory/PLAYER_PROFILE_LIVE_AUDIT_2026-11-13.md`: live implementation and outstanding defects.

## Target experience — screen by screen

### 0. PlayPro entry / welcome

Purpose: explain what PlayPro is and provide one obvious next action.

Primary actions:
- Log masuk
- Daftar akaun

Do not send a new user directly to a role-specific legacy page before the account journey is clear.

### 1. Authentication

Login mode:
- Email
- Password
- Show/hide password
- Forgot password
- Continue with Google
- Link to create account

Registration mode:
- Select role first; Player is the simplest default entry for this journey.
- Name, email and password for email registration.
- Google OAuth where configured.
- Explain email confirmation if the auth provider requires it.

States to design:
- idle, submitting, success, invalid credentials, unconfirmed email, network/server unavailable, OAuth cancelled/failed, password reset sent.

Important: distinguish a genuine credential error from a network/server error. Never tell a user their password is wrong when the service is unreachable.

### 2. Choose role

For this journey the user selects **Player**.

The role choice is an account/workspace context, not a second identity. Do not create another account when an existing user adds another role later.

### 3. Account creation and confirmation

Create the authentication account through the supported auth flow. If email confirmation is required, show a clear confirmation state and a way to resume after confirmation.

Do not show a blank page or lose the user's intended Player journey after an OAuth redirect.

### 4. Onboarding step 1 — identity

Fields:
- Legal/full name
- Preferred name (optional)
- Short bio (optional)
- Date of birth
- Nationality

Explain that legal identity and public display name are separate. If identity has already been verified, do not ask the user to re-enter or alter locked verified identity fields.

### 5. Onboarding step 2 — football profile

Fields:
- Main position
- Dominant foot
- Jersey number
- Height
- Weight
- Profile photo (current production supports it)

Prototype 2.0 decision: **do not provide photo/video upload controls** in this prototype. Use a neutral avatar/placeholder and keep the storage boundary simple. Existing production photo capability is not to be deleted or silently downgraded; it is simply excluded from this prototype UI pending the storage decision.

Use sensible optionality: only block profile creation for fields proven essential by the backend contract. Do not turn every football fact into a mandatory form field.

### 6. Onboarding step 3 — display and privacy

Fields:
- Display name mode: preferred name or legal name.
- Profile visibility: Public or Private.

Explain Public/Private in plain language. Do not expose legal identity documents or sensitive KYC fields on a public profile.

### 7. Create player profile

Show a concise review/confirmation state. On success:
- Create the player profile once.
- Preserve the authenticated session.
- Route directly to the newly created Player Profile.
- Show a clear success message and one useful next action.
- Do not require KYC merely to create or view the basic player profile.

If save fails, preserve entered values and explain how to retry. Avoid creating duplicate player rows on repeated taps.

### 8. Player Profile — first landing

The first screen should establish football identity immediately:
- Player name and display identity
- Position, club/free-agent state and basic facts
- Verification state, without making unverified status feel like an error
- Clear access to Football DNA / attributes
- Player Card
- Football Passport
- Match History
- Career / development history
- Wall / status posts

Important data states:
- If the player has no assessment data, show **BELUM DINILAI**. Do not show OVR 0 or fabricate ratings.
- If no official match data exists, show an honest empty state.
- If KYC is not complete, explain that the basic profile remains usable; KYC is requested only at a controlled official-action gate.
- Player Card and Football Passport remain visible as product features, with accurate pending/unverified states where appropriate.

## Returning-user branches

### Existing account with a Player Profile
Login → existing account/session → Home. The user can open My Profile from the persistent navigation. Do not force onboarding again.

### Existing account without a Player Profile
Login → detect missing Player profile → resume the incomplete Player onboarding. Preserve any already-saved fields where supported.

### Existing verified user adding Player role
Use the same account and identity verification. Do not repeat identity KYC. Ask only for missing Player-specific football details.

### User already has another role
Offer Add role / Switch workspace from the account-role control. Do not create another login or duplicate identity.

## Navigation and interaction requirements

- One continuous visual shell from login through onboarding to profile.
- Mobile-first, responsive layout.
- Progress indicator for the three onboarding steps.
- Back/Next navigation preserves values.
- Inline validation and readable errors.
- Primary CTA always clear.
- Every button has a meaningful action.
- After profile creation, land directly on the created profile.
- No photo/video upload controls in Prototype 2.0.
- No production database writes or production auth credentials in the prototype.

## Audit findings / issues to resolve in Phase 1

1. There are two player entry paths: the shared `index.html` registration flow and dedicated `player_signup.html`. The prototype should present one consistent entry experience, not two competing signup journeys.
2. The dedicated player signup currently sends users directly to onboarding after signup/OAuth. The shared app has a role-selection and authenticated-user routing flow. These must be reconciled into one understandable journey.
3. The current onboarding has three screens, but the football profile screen includes a photo upload control. Remove that control from the Prototype 2.0 UI only; do not delete production capability or data.
4. The target UX must explicitly route to the newly created Player Profile after successful creation.
5. Returning player users should not be forced through onboarding again.
6. The current Player Profile already contains the essential football IP surfaces. Keep and reorganise them; do not replace them with a generic social profile.
7. Current live audit states all five player DNA rows have no rated canonical attributes. The correct UI state is BELUM DINILAI; never fabricate OVR.
8. Current live audit identifies unresolved assessment/DNA mapping, assessment write security, private-profile match-history RPC visibility, and follower approval UI gaps. These are known production integration risks, not problems to conceal with prototype mock data.
9. Current canonical profile includes a separate Wall tab; Prototype 2.0 may present the social activity in a clearer profile section while preserving all football data.

## Phase 1 acceptance criteria

- [ ] One clear entry point for Login and Registration.
- [ ] Email/password and supported OAuth paths are represented.
- [ ] Error, loading, confirmation and recovery states are mapped.
- [ ] Player role selection is explicit for new accounts.
- [ ] Three short onboarding steps are mapped.
- [ ] No media upload control in Prototype 2.0.
- [ ] Profile creation routes directly to the Player Profile.
- [ ] Existing users are not forced to repeat onboarding or KYC.
- [ ] DNA, Player Card, Passport, match history, career/development and Wall remain accessible.
- [ ] Honest empty states are specified; no fabricated ratings or records.
- [ ] No production database writes from prototype.

## Not in scope for this journey

- Coach, club owner, organizer and referee onboarding screens.
- KYC document capture and human review workflow.
- Production schema changes or migrations.
- Production deployment or merging PR #60.
