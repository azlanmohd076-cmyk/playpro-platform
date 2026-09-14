# PlayPro — Current Production Truth

**Effective:** 2026-09-14  
**Status:** Canonical working baseline for future AI sessions

## Supersedes

This document supersedes older PlayPro audit snapshots that describe the production system as only the original core schema or that treat the Arena match-operations branch as production truth. Those statements are historical and must not be used to plan current work.

## Current truth

- GitHub production source: `azlanmohd076-cmyk/playpro-platform`, branch `main`.
- Supabase production project: `playpro2` (`muirhenvjruvfxenoaxm`).
- Vercel production project: `playpro-platform`.
- Live production schema includes player, coach, club, competition, fixture, match-event, referee, discipline, suspension, standings, KYC/identity and related operational domains.
- The `arena/next-match-operations` branch is design/work history, not production truth.
- Production root now uses the new PlayPro production home surface; existing module routes remain available.

## Execution order

1. Contract reconciliation: source tree ↔ live Supabase schema ↔ migration history ↔ architecture docs.
2. Golden-path implementation and E2E verification.
3. Production UI completion and UX verification.
4. Production deployment verification.
5. Security hardening is a final phase, deliberately deferred while the system is being built and there is no production user dataset. This is a sequencing decision, not a statement that the findings are acceptable for a public data-bearing launch.

## Required loop

`inspect → reason → implement → test → verify → commit → deploy when safe → verify production`

## Non-negotiables

- No hard-coded legacy Azlan data as production truth.
- No duplicate source of truth for official results, standings, identity or suspension state.
- No destructive rewrite merely to make the codebase look cleaner.
- Every production change must be traceable to a commit/migration and verified on the deployed surface.
- A historical audit must never override live schema/source/deployment evidence.

## Current security backlog (deferred)

The Supabase security advisor currently reports RLS/policy/function/view findings and password-protection configuration findings. These are intentionally parked until the final production-hardening phase per the current project execution decision.

## Current performance backlog

The performance advisor reports foreign-key index coverage, RLS auth initialization-plan inefficiencies, unused indexes, permissive-policy overlaps and duplicate indexes. These are to be addressed after the functional contracts stabilize, with evidence-based cleanup rather than blind deletion.
