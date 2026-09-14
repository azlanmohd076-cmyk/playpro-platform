# PLAYPRO — CTO PRODUCTION BASELINE

**Date:** 2026-09-14
**Purpose:** Establish the current verified engineering baseline before further implementation. This document is an evidence record, not a replacement for the canonical architecture or historical decisions.

## 1. Connected system baseline

- GitHub repository: `azlanmohd076-cmyk/playpro-platform`
- Default branch: `main`
- Current main HEAD verified: `3252f823ac94fc05265d274097262ac2bed09e08`
- Supabase canonical project: `playpro2` / `muirhenvjruvfxenoaxm`
- Supabase status: ACTIVE_HEALTHY
- Supabase region: ap-south-1
- Supabase PostgreSQL: 17.6.1.111
- Vercel project: `playpro-platform`
- Current production deployment is READY and points to main commit `3252f823ac94fc05265d274097262ac2bed09e08`.

## 2. Important branch finding

`arena/next-match-operations` is not the production branch. It diverges from main: it is 6 commits ahead and 47 commits behind, with merge base `fc1b45fc11795a3b3f28721631a3b7bd6b4a339c`. Its six commits are documentation/schema-design work for match operations.

Therefore it must not be treated as the current production source of truth. The production baseline is `main` plus the live `playpro2` schema.

## 3. Production schema has advanced beyond the older match-operations audit

The live Supabase migration history now includes, among others:

- `20260908175624_phase3_security_boundary_hardening`
- `20260908182106_phase3_match_stat_reconciliation_contract`
- `20260908184858_phase3_match_event_engine_foundation`
- `20260909003126_phase3_match_observer_rpc_engine_v1`
- `20260911183052_fix_match_referee_finalization_and_configured_suspensions`
- `20260911183122_fix_suspension_rule_lookup_team_context`
- `20260912084844_20260912_referee_assignment_source_and_finalize_gate`
- `20260912141501_player_identity_display_kyc_passport_v1`
- `20260912141516_player_kyc_approval_passport_sequence_v1`
- `20260912141942_player_onboarding_identity_lock_v1`
- `20260912152505_player_kyc_google_document_ai_integration_v1`
- `20260912220203_coach_profile_v2`
- `20260912224937_20260913_coach_profile_role_kyc_foundation_v2`
- `20260912224956_20260913_coach_kyc_approval_gate`
- `20260912225428_20260913_coach_kyc_identity_lock_enforcement`
- `20260913053403_20260913_club_ecosystem_foundation`
- `20260913053750_20260913_club_roster_access_controls`
- `20260913053907_20260913_club_tactical_template`
- `20260913070217_club_membership_referee_rating_foundation_v2`
- `20260913070407_club_membership_workflow_and_referee_access`
- `20260913070432_club_membership_referee_security_hardening`
- `20260913101526_20260913_club_operations_control_and_payment_gate`
- `20260913101615_20260913_referee_profile_license_accreditation_workflow`

This supersedes the older 2026-09-12 conclusion that referee assignments and competition rule configuration were absent from production. They now exist in the live generated schema.

## 4. Live domain baseline verified from generated Supabase types

The current public schema contains substantial production domains including:

- identity/profile and role registry;
- players and player assessments;
- player attribute state;
- coaches, coach assessments, coach attribute state and certification workflow;
- clubs, club types, club memberships, teams, team staff, team players, tactics and training sessions;
- club membership requests, membership settings and payment records;
- leagues, league staff and league clubs;
- fixtures, match participants, match events, match playing time, match results and match administration assignments;
- referee profiles, referee attribute state, referee assignments, referee license documents and referee accreditations;
- discipline, suspensions and competition rule configuration;
- standings;
- player follows, posts and profile ratings;
- identity verification.

The current generated types also expose `v_referee_match_stats`, `v_player_profiles`, `v_top_scorers`, `v_standings`, `v_active_suspensions` and `v_discipline_summary`.

## 5. Current security baseline

Supabase security advisors currently report:

- 1 public table with RLS disabled: `competition_rule_config`.
- 1 RLS-enabled table without policy: `referees`.
- 1 SECURITY DEFINER view: `v_referee_match_stats`.
- 51 SECURITY DEFINER functions executable by `anon`.
- 64 SECURITY DEFINER functions executable by `authenticated`.
- leaked-password protection disabled.

These findings are the current production security gate. They are not merely historical findings.

## 6. Current performance baseline

Supabase performance advisors report:

- 60 unindexed foreign keys.
- 29 RLS policies with auth initialization-plan inefficiency.
- 73 unused indexes.
- 20 multiple-permissive-policy findings.
- 3 duplicate-index findings.

Unused indexes are not automatically deletion candidates while the dataset is small. FK coverage and duplicate policy/index cleanup should be handled deliberately after functional contracts are stable.

## 7. Vercel production baseline

The current production deployment is READY and was created from main commit `3252f823...` with message `fix: make Club Center the production entry point`.

The Vercel runtime error aggregation for the last 24 hours reports **no runtime errors**.

This does not prove end-to-end correctness; it only establishes that the deployed application is not currently emitting aggregated runtime errors in the selected window.

## 8. Architectural diagnosis

The earlier diagnosis of architecture drift remains valid, but it must now be refined:

The problem is no longer accurately described as “the production database has only the original 17 core tables.” Production has materially expanded through the September 2026 migrations.

The current engineering risk is instead **contract drift between the latest production schema, the main branch source code, older architecture documents, and still-unmerged Arena design branches**.

The correct strategy remains:

`PRODUCTION TRUTH → CONTRACT RECONCILIATION → SECURITY HARDENING → E2E GOLDEN PATHS → FEATURE COMPLETION → PRODUCTION`

not a rewrite.

## 9. Immediate CTO work sequence

1. Reconcile `main` source tree against the live generated Supabase contract.
2. Reconcile Git migration files against live migration history and identify any untracked/externally-applied schema changes.
3. Reconcile current canonical architecture documents with the live schema, marking stale statements as superseded rather than deleting history.
4. Establish one application Supabase client/auth/repository contract.
5. Close the highest-risk authorization findings before opening new sensitive workflows.
6. Build and verify the Player → KYC → Passport/identity golden path.
7. Build and verify Club → membership → payment → PlayPro verification → squad path.
8. Build and verify Competition → fixture → officials → observer → referee approval → official result path.
9. Build and verify official result → statistics → standings → discipline → eligibility path.
10. Only after those paths pass, proceed to deeper DNA/Passport intelligence, social and talent-discovery layers.

## 10. Non-negotiable engineering rule

No hard-coded legacy Azlan data. Azlan remains a reference persona/UX fixture only.

No second source of truth for official match results, standings, player identity or suspension state.

No destructive rewrite of working PlayPro architecture merely to make the codebase look cleaner.

Every production change must be traceable to a migration/commit, verified, and reflected in the canonical project documentation.
