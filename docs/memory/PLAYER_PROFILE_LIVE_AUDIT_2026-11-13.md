# PlayPro Player Profile — Live Audit
**Tarikh:** 13 November 2026  
**Skop:** Player Profile, Player Card, social follow flow, assessment data dependency  
**Database:** `playpro2` (`muirhenvjruvfxenoaxm`)

## Work merged and deployed

- **PR #21** — logout now uses local sign-out, verifies session removal, and clears only the PlayPro auth token on failure.
- **PR #22** — expanded Player Profile editor: display name, display-name mode, bio, nationality, visibility, position, preferred foot, jersey, height, weight and photo upload.
- **PR #23** — fixed private-profile Follow request: target player is assigned before the restricted state renders; pending requests show a disabled state.
- **PR #24** — Player Card now uses only the canonical 18 DNA attributes; OVR stays hidden until all 18 have valid 1–20 values; detailed positions render.
- **PR #25** — Follow UI reflects approved/pending/no relationship and supports unfollow.

Latest production deployment at audit time: `969b0bcfc76509a9099b6fbbc9fa9362f29b08ce` — READY.  
Production URL: https://playpro-platform-9fo9j58vj-playpro.vercel.app

Both inline JavaScript blocks in the updated profile page and the Player Card passed syntax compilation. This is not a substitute for authenticated browser E2E tests.

## Live data facts

| Table | Rows |
|---|---:|
| players | 5 |
| player_attribute_state | 5 |
| player_assessments | 0 |
| player_match_stats | 0 |
| player_posts | 0 |
| player_follows | 0 |

All five `player_attribute_state` rows have `source='none'`, `confidence=0`, and no rated canonical attributes. Therefore the correct UI state is **BELUM DINILAI**, not OVR 0 or BASIC.

The `player-photos` bucket exists, is public-read, and has an authenticated INSERT policy. The Profile editor uploads a unique object path and persists its public URL through the existing `update_my_player_profile` RPC.

## Blocking data and governance defects

1. **DNA schema mismatch:** canonical v1 is 18 outfield attributes. The live `player_assessments` table stores a different 19-field legacy set (including crossing, determination, decisions, balance and three GK fields). There is no verified one-to-one mapping for all canonical attributes.
2. **No assessment-to-DNA pipeline:** no trigger/function currently syncs `player_assessments` into `player_attribute_state`.
3. **Assessor panel does not match production:** UI says 18 attributes and scale 1–100; live table has 19 legacy fields and CHECK constraints 1–20. Its history query requests `created_at`, but the live table has `assessed_at`.
4. **Assessor directory access:** the assessor UI queries `players` directly, but live SELECT policy on `players` is owner-only. Do not solve this by granting broad SELECT; create a role-checked minimal RPC.
5. **Assessment RLS:** live `player_assessments` has permissive public SELECT and an authenticated INSERT policy with `WITH CHECK (true)`. Restrict only after Phase 2C baseline/reconciliation.
6. **Match-history RPC:** `get_player_match_history` is SECURITY DEFINER and callable by anon; current body does not enforce private-profile visibility. The profile UI hides restricted data, but direct RPC calls bypass UI.
7. **Follow approvals:** follower can send a request and the backend `respond_player_follow` exists, but the owner-facing page lacks a safe follower-summary RPC to identify pending requesters. Owner approval/rejection UI remains incomplete.

## Phase 2C boundary

The SQL file `docs/memory/sql/PLAYER_PROFILE_GOVERNANCE_DRAFT.sql` remains DRAFT ONLY. Do not apply it until the required production truth export and baseline reconciliation are complete. No production DDL was executed during this audit.

## Completion gate

Player Profile cannot be marked fully complete until:
- canonical assessment storage and multi-assessor aggregation are approved;
- a secure assessor directory and assessment write path are implemented;
- assessment data flows into the 18 canonical attributes;
- private follower requests can be approved/rejected by the owner;
- match-history visibility is enforced inside the RPC;
- authenticated browser tests verify profile editing, photo upload, follow/unfollow, private requests, Wall and official match history.
