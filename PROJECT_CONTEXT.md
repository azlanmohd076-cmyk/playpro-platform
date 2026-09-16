# PlayPro — Project Context

**Repository:** `azlanmohd076-cmyk/playpro-platform`
**Production branch:** `main`
**Supabase:** `playpro2` / `muirhenvjruvfxenoaxm`
**Vercel:** `playpro-platform`

## Important files

| File | Purpose |
|---|---|
| `public/index.html` | Legacy/canonical large PlayPro shell and existing inline UI logic. ~6,128 lines; contains legacy UI plus many inline handlers. Treat as high-risk legacy surface. |
| `public/js/supabase.js` | Canonical browser Supabase client, session/auth helpers, cache, realtime helpers and global auth utilities. |
| `public/js/repositories.js` | Browser data repository layer; normalises DB data and exposes domain repositories. |
| `public/player_signup.html` | Player registration entry; email/password plus Google/Facebook OAuth. |
| `public/player_onboarding_v2.html` | Player onboarding: identity, football profile, display-name mode and privacy. |
| `public/player_profile_cm.html` | CM01/02-style player profile hub: DNA, card, passport, match history, career and wall. |
| `public/player_card_v2.html` | Shareable Player Card presentation. |
| `public/player_kyc.html` | Player KYC document upload and KYC status surface. |
| `public/kyc_review.html` | Privileged KYC review surface. |
| `public/coach_profile.html` | Coach profile surface and coach role presentation. |
| `public/club.html` / club module pages | Club identity, roster/team/squad and club operations surfaces. |
| `public/referee.html` and referee module pages | Referee profile, accreditation and match-official operations. |
| `public/organizer*.html` | Organizer identity and organizer/event surfaces. |
| `supabase/functions/kyc-verify-player/index.ts` | Server-side Google Document AI player KYC processing. Google service credentials stay server-side. |
| `supabase/functions/kyc-review-player/*` | Privileged KYC review/approval path. |
| `supabase/migrations/` | Production schema/function changes tracked in Git. Do not assume a migration file is live without checking Supabase migration history. |
| `docs/memory/AI_HANDOVER.md` | Master continuation context and engineering guardrails. |
| `docs/memory/PLAYER_PROFILE_CANONICAL.md` | Canonical player flow and current player implementation baseline. |
| `docs/memory/INDEX_HTML_MAP.md` | Forensic map of the large legacy `public/index.html`. |
| `docs/memory/CTO_PRODUCTION_BASELINE_2026-09-14.md` | Production Git/Supabase/Vercel baseline and current engineering sequence. |
| `database/` | SQL history/reference. Production application must be verified against live Supabase before assuming parity. |
| `vercel.json` | Vercel deployment configuration; `public` is the output surface. |

## Main browser/auth functions

### Auth/client
- `Auth.session()` — current Supabase session.
- `Auth.profile()` — current `profiles` row.
- `Auth.signIn()` — email/password sign-in.
- `Auth.signUp()` — email/password registration.
- `Auth.signOut()` — sign out.
- `Auth.onStateChange()` — auth-state subscription.
- `Auth.uid()` — current auth UUID.
- `Auth.hasRole()` — profile-role check.
- `mustLogin()` — global login guard for legacy inline handlers; uses `Auth.session()` and redirects unauthenticated users to the existing player sign-up/login surface.
- `Realtime.clubFeed()` / `notifications()` / `fixtureFeed()` — realtime helpers.

### Player
- `register_my_player()` — canonical player creation RPC.
- `get_player_profile()` — player profile projection.
- `update_my_player_profile()` — player profile update RPC.
- `follow_player()` / `unfollow_player()` / `respond_player_follow()` — player social graph.
- `get_player_match_history()` — official match history projection.
- `get_player_card_state()` — disciplinary/card state.
- `request_player_kyc_document()` — document-backed player KYC request.
- `get_my_player_kyc_status()` — player KYC status.
- `approve_player_kyc()` / `reject_player_kyc()` — privileged KYC decision path.

### Match / discipline
- `finalize_match()` — official referee approval/finalization gate.
- `auto_suspend_on_red_card()` — suspension creation from disciplinary match events using competition-rule configuration.
- `advance_suspensions_on_official_result()` — suspension ledger progression on qualifying official results.
- `recalculate_standings()` — standings recalculation.

## Main Supabase domains/tables

Production has materially expanded beyond the original core schema. Important domains include:

- `profiles`
- `profile_role_profiles` / role-registry structures
- `players`
- `player_attribute_state`
- `player_assessments`
- `player_follows`
- `player_posts`
- `player_match_stats`
- `player_match_playing_time` / match-playing-time structures
- `identity_verifications`
- `clubs`
- `club_types`
- `club_memberships`
- `club_membership_requests`
- `club_membership_payments`
- `teams`
- `team_players`
- `team_staff`
- tactical/template structures
- `coaches`
- coach attribute/assessment/certification structures
- `referees`
- `referee_assignments`
- referee license/accreditation structures
- `leagues`
- `league_staff`
- `league_clubs`
- `fixtures`
- `match_participants`
- `match_events`
- `match_playing_time`
- `match_results`
- `match_admin_assignments`
- `competition_rule_config`
- `suspensions`
- `disciplinary_records`
- `standings`
- organizer/competition identity structures
- KYC private storage bucket: `kyc-documents`

Exact live columns/policies are governed by the live Supabase schema, not this summary.

## Current major features

- Multi-role PlayPro identity: one user can accumulate Player, Coach, Club Owner, Organizer and Referee role profiles.
- Player onboarding with editable pre-KYC legal/display identity and preferred name.
- KYC-gated verification; verified legal identity is locked while preferred/display name remains editable.
- Football DNA / player attributes on a 1–20 scale; player cannot self-assign attributes.
- Coach assessment and future organic match-performance attribute movement are separate sources.
- Player Card with six position-relevant visible stats and disciplinary visual state.
- Football Passport as lifelong football record.
- Player follow/private-profile/social-wall foundation.
- Coach profile, licensing and PlayPro accreditation foundation.
- Club identity, verification, staff, teams/squads, membership workflow and payment-gate foundation.
- Team/squad as the source for competition registration rather than duplicate player registration.
- Referee profile, official license upload, PlayPro accreditation and referee assignment/finalization workflow.
- Organizer/event console as one product surface inside the wider PlayPro platform, not the whole platform.
- Match observer and referee approval architecture.
- Official match result, standings, discipline and suspension flows.
- Google Document AI-backed server-side player KYC processing foundation.

## Important current engineering state

- `main` currently tracks production work and is actively deploying through Vercel.
- The latest known main commit before this context update was the KYC-storage security commit; this context file should be refreshed whenever major production work changes.
- `public/index.html` is a large legacy surface. The repository documentation records ~6,128 lines and heavy inline/base64 content. Do not rewrite it casually.
- `public/js/supabase.js` is the canonical browser auth/client helper and now exposes `window.mustLogin` for legacy inline handlers.
- The repository has both legacy and newer role-specific pages. Verify actual route wiring before declaring a feature live.
- Production Supabase has materially more schema than the old architecture audit. Always distinguish BUILT, PARTIAL, DESIGNED ONLY and NOT STARTED using Git + live DB evidence.

## Known engineering risks / rules

1. Do not create duplicate sources of truth for identity, official match result, standings or suspension state.
2. Do not treat an architecture box as proof that a feature is built.
3. Do not silently alter production schema because a frontend expects a column.
4. Do not store Google service-account credentials in browser code or Git.
5. Do not let KYC provider output itself become the final PlayPro verification decision; privileged PlayPro approval is the gate.
6. Do not let users self-assign Football DNA.
7. Do not activate AI as a hidden source of player attributes; the future organic-attribute methodology must be deterministic and auditable before activation.
8. Referee approval, not observer finalization, is the official match gate.
9. Suspension length comes from competition-rule configuration and suspension ledger state, not a hard-coded fallback.
10. Azlan/persona data is reference UX only; never seed production with fabricated personal data.
11. Keep the Owner's locked product decisions in `docs/memory/DECISIONS.md` and continue from `docs/memory/AI_HANDOVER.md` rather than reopening settled decisions.

## Latest maintenance note

The browser auth guard `mustLogin()` was added to the canonical `public/js/supabase.js` helper using the existing `Auth.session()` system. The requested large `public/index.html` syntax fault still requires exact source-line verification before anyone should claim that line 6003 is repaired; GitHub's content API refuses to return this >1 MB file through the connected file reader, so no speculative rewrite of the large HTML file is permitted.
