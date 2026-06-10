-- ============================================================
-- PLAYPRO — PHASE 4.1.1: REMEDIATION PATCH
-- playpro_phase4_1_1_remediation_patch.sql
-- ============================================================
-- Apply AFTER playpro_phase4_1_stabilization_patch.sql is applied.
-- Fixes 6 verified findings from the Phase 4.1 audit review.
--
-- PostgreSQL 16 compatible. Supabase compatible.
-- Single transaction. All changes are targeted and minimal.
--
-- ============================================================
-- DEPENDENCY ANALYSIS
-- ============================================================
--
-- Objects modified by this patch (in dependency order):
--
--   1. validate_referee_no_conflict()    [H-2]
--      ← used by trg_validate_referee_conflict ON referee_assignments
--      ← trigger binding unchanged; function replaced in-place
--
--   2. idx_seasons_league_active         [M-2]
--      ← used by planner for queries: WHERE league_id=X AND status='active'
--      ← replaced by idx_seasons_one_active_per_league (Phase 4.1)
--      ← safe to drop; the unique index serves all the same queries
--
--   3. idx_plr_approved                  [H-1]
--      ← used by is_player_eligible() step 8 lookup
--      ← recreated with season_id added as 4th column
--      ← drop + recreate is a metadata operation; no data loss
--
--   4. idx_plr_player_created            [H-3]
--      ← new index; used by v_player_eligibility_summary subquery
--      ← supports: ORDER BY plr.created_at DESC LIMIT 1
--
--   5. v_player_eligibility_summary      [C-3, C-2]
--      ← standalone view; no other object depends on it
--      ← rewritten with LEFT JOIN LATERAL; identical output columns
--      ← comment updated to document coach RLS behavior (C-2)
--
--   6. Rollback SQL for is_player_eligible()  [C-1]
--      ← no executable SQL in this transaction
--      ← rollback bodies added to the rollback section at file bottom
--
-- Objects NOT modified:
--   - trg_validate_referee_conflict    (trigger still calls same function)
--   - is_player_eligible()            (not changed in forward patch)
--   - is_player_eligible_with_reason() (not changed in forward patch)
--   - All RLS policies                (not changed)
--   - All other tables and triggers   (not changed)
--
-- ============================================================
-- RISK ANALYSIS
-- ============================================================
--
-- H-2 (validate_referee_no_conflict):
--   Risk: LOW. Adding NOT FOUND guards makes the function MORE
--   restrictive — previously NULL-propagation caused silent pass.
--   Now invalid referee/fixture IDs produce clear errors.
--   Backward-compatible: valid assignments behave identically.
--   Deployment risk: none — trigger fires only on INSERT/UPDATE
--   to referee_assignments, which is a low-frequency operation.
--
-- M-2 (drop idx_seasons_league_active):
--   Risk: LOW. The unique index idx_seasons_one_active_per_league
--   covers all queries that idx_seasons_league_active served.
--   Verified: both are partial WHERE status='active'; the status
--   column in the old index body is logically redundant.
--   Dropping an index does not affect data. The planner
--   automatically uses the remaining unique index.
--
-- H-1 (rebuild idx_plr_approved with season_id):
--   Risk: LOW. Drop + CREATE INDEX inside a transaction takes an
--   AccessExclusive lock for the CREATE duration. At low row
--   counts this is sub-second. The UNIQUE constraint index
--   (uq_plr_player_club_league_season) remains throughout and
--   can serve eligibility queries during the rebuild window.
--   No reads are blocked; writes to player_league_registrations
--   are briefly blocked during index build.
--   For production with large tables: consider running the
--   index creation with CONCURRENTLY outside this transaction.
--
-- H-3 (new idx_plr_player_created):
--   Risk: LOW. Additive-only index. Never affects correctness.
--   May briefly lock player_league_registrations during creation.
--   For production: consider CONCURRENTLY outside transaction.
--
-- C-3 (v_player_eligibility_summary rewrite):
--   Risk: LOW. View is replaced with identical output columns
--   and identical business logic. LEFT JOIN LATERAL produces
--   the same rows. No application code calling this view by
--   column name is broken. The COMMENT is updated.
--
-- C-2 (coach RLS documentation):
--   Risk: NONE. Comment-only change on the view.
--   Design ruling: coach visibility of injury data is a product
--   decision that requires explicit authorization before any
--   RLS change. This patch documents the behavior; it does not
--   change security policy.
--
-- C-1 (rollback SQL completeness):
--   Risk: NONE in forward direction. The rollback section below
--   now contains complete bodies for is_player_eligible() and
--   is_player_eligible_with_reason() restoring Phase 4.0 behavior.
--
-- ============================================================
-- DEPLOYMENT ORDER
-- ============================================================
-- 1. Apply playpro_phase1.sql
-- 2. Apply playpro_phase2_additions.sql
-- 3. Apply playpro_phase3_additions.sql
-- 4. Apply playpro_phase4_critical_fix_pack.sql
-- 5. Apply playpro_phase4_1_stabilization_patch.sql
-- 6. Apply THIS FILE (playpro_phase4_1_1_remediation_patch.sql)
-- ============================================================

BEGIN;

-- ============================================================
-- FIX H-2: validate_referee_no_conflict() NULL propagation
-- ============================================================
-- Finding: VALID
--
-- Root cause (verified from source):
--   Lines 1056 and 1061 of Phase 4.1 perform SELECT INTO without
--   IF NOT FOUND guards. If NEW.referee_id does not match any row
--   in referees (possible because BEFORE triggers fire before FK
--   constraint validation in PostgreSQL), v_referee_profile_id
--   remains NULL. All three conflict checks then evaluate:
--     WHERE c.admin_id = NULL           → no rows matched
--     WHERE co.profile_id = NULL        → no rows matched
--     WHERE cs.profile_id = NULL        → no rows matched
--   All EXISTS() return false. Function returns NEW silently.
--   The referee conflict check is completely bypassed.
--
--   Similarly, if NEW.fixture_id does not resolve (edge case in
--   a concurrent delete race before FK validation), v_home_club_id
--   and v_away_club_id are NULL. The IN(NULL, NULL) expressions
--   evaluate to NULL in all three guards — silent bypass.
--
-- Fix:
--   Add explicit IF NOT FOUND guards after each SELECT INTO.
--   Referee not found: RAISE EXCEPTION — fail loudly, block insert.
--   Fixture not found: RAISE EXCEPTION — fail loudly, block insert.
--   This is the correct behavior: a referee_assignment must always
--   reference a valid referee profile and a valid fixture. Silent
--   pass is never acceptable.
--
-- Backward compatibility:
--   All valid inputs (existing referee + existing fixture) are
--   unaffected. The new exceptions only fire on data integrity
--   violations that should never occur in correct operation.
-- ============================================================

CREATE OR REPLACE FUNCTION validate_referee_no_conflict()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_referee_profile_id UUID;
  v_home_club_id       UUID;
  v_away_club_id       UUID;
BEGIN
  -- ── Resolve the referee's system profile ─────────────────
  -- Fail loudly if referee_id does not resolve.
  -- In PostgreSQL, BEFORE triggers fire before FK validation,
  -- so a stale or invalid referee_id may reach this point.
  SELECT r.profile_id
  INTO   v_referee_profile_id
  FROM   referees r
  WHERE  r.id = NEW.referee_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'validate_referee_no_conflict: referee record not found '
      'for referee_id %. Cannot validate conflict of interest.',
      NEW.referee_id
      USING ERRCODE = '02000';
  END IF;

  -- ── Resolve the fixture's two clubs ──────────────────────
  -- Fail loudly if fixture_id does not resolve.
  SELECT f.home_club_id, f.away_club_id
  INTO   v_home_club_id, v_away_club_id
  FROM   fixtures f
  WHERE  f.id = NEW.fixture_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'validate_referee_no_conflict: fixture record not found '
      'for fixture_id %. Cannot validate conflict of interest.',
      NEW.fixture_id
      USING ERRCODE = '02000';
  END IF;

  -- ── Guard 1: Referee is club administrator of either club ─
  IF EXISTS (
    SELECT 1 FROM clubs c
    WHERE  c.admin_id = v_referee_profile_id
      AND  c.id IN (v_home_club_id, v_away_club_id)
  ) THEN
    RAISE EXCEPTION
      'Conflict of interest: referee (profile ID: %) is an '
      'administrator of one of the clubs in fixture (ID: %).',
      v_referee_profile_id, NEW.fixture_id
      USING ERRCODE = '23514';
  END IF;

  -- ── Guard 2: Referee is an active coach at either club ────
  IF EXISTS (
    SELECT 1 FROM coaches co
    WHERE  co.profile_id = v_referee_profile_id
      AND  co.club_id    IN (v_home_club_id, v_away_club_id)
      AND  co.is_active  = true
  ) THEN
    RAISE EXCEPTION
      'Conflict of interest: referee (profile ID: %) is an '
      'active coach at one of the clubs in fixture (ID: %).',
      v_referee_profile_id, NEW.fixture_id
      USING ERRCODE = '23514';
  END IF;

  -- ── Guard 3: Referee is active club staff at either club ──
  IF EXISTS (
    SELECT 1 FROM club_staff cs
    WHERE  cs.profile_id = v_referee_profile_id
      AND  cs.club_id    IN (v_home_club_id, v_away_club_id)
      AND  cs.is_active  = true
  ) THEN
    RAISE EXCEPTION
      'Conflict of interest: referee (profile ID: %) is active '
      'club staff at one of the clubs in fixture (ID: %).',
      v_referee_profile_id, NEW.fixture_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

-- trg_validate_referee_conflict still points to this function.
-- No trigger recreation needed.


-- ============================================================
-- FIX M-2: Drop redundant idx_seasons_league_active
-- ============================================================
-- Finding: VALID
--
-- Root cause (verified from source):
--   Phase 4 created:
--     idx_seasons_league_active
--       ON seasons(league_id, status) WHERE status = 'active'
--
--   Phase 4.1 created:
--     idx_seasons_one_active_per_league
--       UNIQUE ON seasons(league_id) WHERE status = 'active'
--
--   Both indexes have the identical WHERE status = 'active' partial
--   predicate. Any query that could use idx_seasons_league_active
--   can equally use idx_seasons_one_active_per_league.
--
--   The 'status' column in idx_seasons_league_active's key is
--   logically redundant: because the partial predicate already
--   restricts to status = 'active', storing status in the key
--   adds no discriminating power — every indexed row has
--   status = 'active'. The effective key is just (league_id).
--
--   This means idx_seasons_league_active is a strict subset of
--   idx_seasons_one_active_per_league's capability, with the
--   additional overhead of maintaining a second B-tree structure
--   on every INSERT, UPDATE, and DELETE to the seasons table.
--
-- Safety note:
--   The unique index MUST exist before dropping this one.
--   Since Phase 4.1 created it unconditionally and we are
--   running after Phase 4.1, the unique index is guaranteed present.
--   Using DROP INDEX IF EXISTS for idempotency.
--
-- Queries currently using idx_seasons_league_active:
--   SELECT ... FROM seasons WHERE league_id = X AND status = 'active'
--   → the unique index covers this identically.
--   → no query regression possible.
-- ============================================================

-- Safety guard: only drop if the unique replacement exists.
-- This prevents data access issues if this patch is somehow
-- applied out of order (before Phase 4.1).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename  = 'seasons'
      AND indexname  = 'idx_seasons_one_active_per_league'
  ) THEN
    RAISE EXCEPTION
      'Safety check failed: idx_seasons_one_active_per_league does not exist. '
      'Apply playpro_phase4_1_stabilization_patch.sql before this patch.'
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;

DROP INDEX IF EXISTS idx_seasons_league_active;


-- ============================================================
-- FIX H-1: Rebuild idx_plr_approved with season_id
-- ============================================================
-- Finding: PARTIALLY VALID — incomplete index, fix justified
--
-- Root cause (verified from source):
--   After Phase 4.1, idx_plr_approved is:
--     (league_id, player_id, club_id, status) WHERE status='approved'
--
--   The primary query in is_player_eligible() step 8 is:
--     WHERE plr.player_id = p_player_id
--       AND plr.club_id   = v_player_club_id
--       AND plr.league_id = v_league_id
--       AND plr.season_id = v_season_id       ← NOT in index
--       AND plr.status    = 'approved'
--
--   The index can narrow to (league_id, player_id, club_id) matching
--   rows, but must then heap-fetch each row to evaluate season_id.
--   For a player with registrations across multiple seasons (which is
--   the expected production state), this causes unnecessary heap fetches.
--
--   Adding season_id as the 4th indexed column makes the index fully
--   covering for this query: all five filter conditions are satisfied
--   from the index alone without a heap visit.
--
--   The UNIQUE constraint index (player_id, club_id, league_id, season_id)
--   also serves this query but starts with player_id; the partial index
--   starting with league_id is retained for queries that filter by
--   league_id alone (e.g. "all approved players in a league/season").
--
-- Note: This DROP + CREATE acquires AccessExclusive during the build.
--   For large tables in production, run this outside a transaction
--   using CREATE INDEX CONCURRENTLY. The unique constraint index
--   (uq_plr_player_club_league_season) covers all queries during
--   the brief rebuild window.
-- ============================================================

DROP INDEX IF EXISTS idx_plr_approved;

CREATE INDEX idx_plr_approved
  ON player_league_registrations (league_id, player_id, club_id, season_id)
  WHERE status = 'approved';

COMMENT ON INDEX idx_plr_approved IS
  'Partial index for approved registration lookups. '
  'Covers is_player_eligible() step 8: '
  'WHERE player_id=? AND club_id=? AND league_id=? AND season_id=? AND status=approved. '
  'season_id added in Phase 4.1.1 to eliminate heap fetches on season filter.';


-- ============================================================
-- FIX H-3: Add index for latest_registration_status subquery
-- ============================================================
-- Finding: VALID
--
-- Root cause (verified from source):
--   v_player_eligibility_summary contains a correlated subquery:
--     SELECT plr.status
--     FROM   player_league_registrations plr
--     WHERE  plr.player_id = pl.id
--     ORDER  BY plr.created_at DESC
--     LIMIT  1
--
--   No index exists on (player_id, created_at). The query uses
--   idx_plr_player (player_id only) to find all rows for a player,
--   then sorts them by created_at in memory before applying LIMIT 1.
--   For a player with registrations across multiple leagues and
--   seasons, this causes an in-memory sort per player row in the view.
--
--   With 50,000 active players, a full view scan runs 50,000
--   in-memory sorts. The index enables an index-scan-with-ordering
--   that avoids the sort entirely: the database walks the index
--   in DESC created_at order and stops at the first match.
--
-- Index design:
--   (player_id, created_at DESC) — matches the query predicate
--   (player_id = ?) and ORDER direction (created_at DESC LIMIT 1).
--   PostgreSQL can use a LIMIT 1 on a correctly-ordered index
--   without scanning or sorting all matching rows.
-- ============================================================

CREATE INDEX idx_plr_player_created
  ON player_league_registrations (player_id, created_at DESC);

COMMENT ON INDEX idx_plr_player_created IS
  'Supports ORDER BY created_at DESC LIMIT 1 queries per player. '
  'Used by v_player_eligibility_summary latest_registration_status column. '
  'Added in Phase 4.1.1.';


-- ============================================================
-- FIX C-3: Rewrite v_player_eligibility_summary with LATERAL
-- ============================================================
-- Finding: VALID (Performance Improvement)
--
-- Root cause (verified from source):
--   The Phase 4.1 view executes 7 correlated subqueries per player row:
--     1. EXISTS(suspensions) → has_active_suspension
--     2. SELECT s.league_id FROM suspensions → suspended_in_league_id
--     3. SELECT matches_remaining FROM suspensions → suspension_matches_remaining
--     4. EXISTS(player_injuries) → has_active_injury
--     5. SELECT expected_return_date FROM player_injuries → injury_expected_return
--     6. SELECT plr.status FROM player_league_registrations → latest_registration_status
--     7-8. CASE block re-evaluates suspensions and player_injuries (×2 repeats)
--
--   Total: 7+ subqueries per row × 50,000 players = 350,000+ subqueries
--   on a full view scan.
--
-- Fix:
--   Replace with LEFT JOIN LATERAL for suspensions and player_injuries.
--   Each lateral executes ONCE per player, providing all needed columns.
--   The CASE block then reads from the lateral alias (no re-query).
--   latest_registration_status retains its correlated subquery form
--   (supported by the new idx_plr_player_created index from H-3 above).
--
-- Output column contract (must be identical to Phase 4.1 version):
--   player_id, player_name, position, club_id, club_name, is_active,
--   has_active_suspension, suspended_in_league_id,
--   suspension_matches_remaining, has_active_injury,
--   injury_expected_return, latest_registration_status, eligible_summary
--
-- Business logic preserved exactly:
--   - Suspension: is_active = true AND matches_served < matches_suspended
--   - Most recent active suspension: ORDER BY created_at DESC LIMIT 1
--   - Injury: is_active = true
--   - Most recent active injury: ORDER BY injury_date DESC LIMIT 1
--   - Registration: most recent by created_at DESC LIMIT 1
--   - eligible_summary: Inactive → Suspended → Injured → Available
--   - Only active players (is_active = true) included
--
-- C-2 design ruling (coach visibility):
--   Coaches (user_role = 'coach') do NOT appear in the
--   "player_injuries: authorized read" RLS policy. This means
--   when a coach queries this view, the player_injuries lateral
--   returns zero rows (RLS filters them), producing:
--     has_active_injury = false
--     injury_expected_return = NULL
--     eligible_summary = 'Available' (for otherwise-available players)
--
--   This is a KNOWN UX INCONSISTENCY, not a security bug:
--   - Medical data (diagnosis, treatment notes) is correctly protected
--   - The injury AVAILABILITY STATUS (is_active = true/false) is
--     arguably non-sensitive operational data that coaches need
--   - HOWEVER: changing the RLS policy to include coaches is a
--     product decision that requires explicit authorization from
--     data protection / league governance stakeholders
--   - Until that decision is made, the current behavior is documented
--     here and in the view comment. No RLS change is applied in this
--     patch.
--
--   If injury availability should be exposed to coaches, the safest
--   fix is a SECURITY DEFINER function that returns only is_active
--   status without clinical fields, callable from the view. This
--   is NOT implemented here pending product decision.
-- ============================================================

DROP VIEW IF EXISTS v_player_eligibility_summary;

CREATE VIEW v_player_eligibility_summary AS
SELECT
  pl.id                                                 AS player_id,
  pl.full_name                                          AS player_name,
  pl.position,
  pl.club_id,
  cl.name                                               AS club_name,
  pl.is_active,

  -- has_active_suspension: TRUE if player has any active ban
  -- Source: suspensions lateral join (single pass per player)
  (susp.player_id IS NOT NULL)                          AS has_active_suspension,

  -- suspended_in_league_id: league of most recent active suspension
  susp.league_id                                        AS suspended_in_league_id,

  -- suspension_matches_remaining: matches left to serve
  susp.matches_remaining                                AS suspension_matches_remaining,

  -- has_active_injury: TRUE if player has any active injury record
  -- NOTE: coaches (user_role='coach') do not have access to player_injuries
  -- via RLS. For coaches, this column returns FALSE even when the player
  -- IS injured. This is a known UX inconsistency pending product decision.
  -- See patch notes in playpro_phase4_1_1_remediation_patch.sql (C-2).
  (inj.player_id IS NOT NULL)                           AS has_active_injury,

  -- injury_expected_return: most recent active injury return date
  -- Returns NULL for coaches due to RLS on player_injuries (see C-2 above).
  inj.expected_return_date                              AS injury_expected_return,

  -- latest_registration_status: most recent registration across all leagues/seasons
  -- Supported by idx_plr_player_created (added in H-3 above).
  (
    SELECT plr.status
    FROM   player_league_registrations plr
    WHERE  plr.player_id = pl.id
    ORDER  BY plr.created_at DESC
    LIMIT  1
  )                                                     AS latest_registration_status,

  -- eligible_summary: plain-language availability status for display
  -- Priority: Inactive > Suspended > Injured > Available
  -- Note: 'Injured' may show 'Available' for coaches due to RLS (see C-2).
  CASE
    WHEN NOT pl.is_active          THEN 'Inactive'
    WHEN susp.player_id IS NOT NULL THEN 'Suspended'
    WHEN inj.player_id  IS NOT NULL THEN 'Injured'
    ELSE                                 'Available'
  END                                                   AS eligible_summary

FROM players pl
JOIN clubs cl ON cl.id = pl.club_id

-- ── Suspension lateral: single pass per player ────────────
-- Retrieves the most recent active suspension in one scan.
-- Replaces 3 correlated subqueries from the Phase 4.1 version.
LEFT JOIN LATERAL (
  SELECT
    s.player_id,
    s.league_id,
    (s.matches_suspended - s.matches_served) AS matches_remaining
  FROM   suspensions s
  WHERE  s.player_id      = pl.id
    AND  s.is_active       = true
    AND  s.matches_served  < s.matches_suspended
  ORDER  BY s.created_at DESC
  LIMIT  1
) susp ON true

-- ── Injury lateral: single pass per player ────────────────
-- Retrieves the most recent active injury in one scan.
-- Replaces 2 correlated subqueries from the Phase 4.1 version.
-- Subject to player_injuries RLS: coaches receive NULL rows.
LEFT JOIN LATERAL (
  SELECT
    pi.player_id,
    pi.expected_return_date
  FROM   player_injuries pi
  WHERE  pi.player_id = pl.id
    AND  pi.is_active  = true
  ORDER  BY pi.injury_date DESC
  LIMIT  1
) inj ON true

WHERE pl.is_active = true;

COMMENT ON VIEW v_player_eligibility_summary IS
  'Player availability dashboard. Uses LEFT JOIN LATERAL for performance '
  '(replaces 7 correlated subqueries from Phase 4.1 with 2 lateral joins). '
  ''
  'COACH VISIBILITY NOTE (C-2): Users with user_role=''coach'' do not '
  'appear in the player_injuries RLS policy. When a coach queries this view, '
  'has_active_injury returns FALSE and eligible_summary may show ''Available'' '
  'for injured players. This is a known UX inconsistency pending a product '
  'decision on whether coaches should see injury availability status. '
  'See playpro_phase4_1_1_remediation_patch.sql FIX C-3 for full details. '
  ''
  'For fixture-specific eligibility, call: '
  'is_player_eligible_with_reason(player_id, fixture_id).';


-- ============================================================
-- END OF FORWARD MIGRATION
-- ============================================================

COMMIT;


-- ============================================================
-- VERIFICATION QUERIES
-- Run these after applying the migration to confirm correctness.
-- ============================================================

-- [V-1] Verify validate_referee_no_conflict has NOT FOUND guards
-- Expected: function body contains 'IF NOT FOUND'
--
-- SELECT prosrc FROM pg_proc
-- WHERE proname = 'validate_referee_no_conflict'
--   AND pronargs = 0;
-- (Check that result contains two 'IF NOT FOUND' blocks)

-- [V-2] Verify idx_seasons_league_active is gone
-- Expected: 0 rows
--
-- SELECT indexname FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND tablename  = 'seasons'
--   AND indexname  = 'idx_seasons_league_active';

-- [V-3] Verify idx_seasons_one_active_per_league still exists
-- Expected: 1 row, isunique = true
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND tablename  = 'seasons'
--   AND indexname  = 'idx_seasons_one_active_per_league';

-- [V-4] Verify idx_plr_approved now includes season_id
-- Expected: indexdef contains 'season_id'
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND tablename  = 'player_league_registrations'
--   AND indexname  = 'idx_plr_approved';

-- [V-5] Verify idx_plr_player_created exists
-- Expected: 1 row
--
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND tablename  = 'player_league_registrations'
--   AND indexname  = 'idx_plr_player_created';

-- [V-6] Verify v_player_eligibility_summary uses lateral joins
-- Expected: view definition contains 'LATERAL'
--
-- SELECT definition FROM pg_views
-- WHERE schemaname = 'public'
--   AND viewname   = 'v_player_eligibility_summary';

-- [V-7] Smoke test: view returns correct columns
-- Expected: columns match Phase 4.1 output contract
--
-- SELECT column_name, ordinal_position
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name   = 'v_player_eligibility_summary'
-- ORDER BY ordinal_position;
-- Expected columns (in order):
--   player_id, player_name, position, club_id, club_name, is_active,
--   has_active_suspension, suspended_in_league_id,
--   suspension_matches_remaining, has_active_injury,
--   injury_expected_return, latest_registration_status, eligible_summary

-- [V-8] Verify is_player_eligible is still VOLATILE (Phase 4.1 behavior preserved)
-- Expected: provolatile = 'v'
--
-- SELECT proname, provolatile
-- FROM pg_proc
-- WHERE proname IN ('is_player_eligible', 'is_player_eligible_with_reason')
--   AND pronargs = 2;


-- ============================================================
-- ROLLBACK SQL
-- Run this entire block to undo ALL changes in this patch.
-- Execute as a single transaction.
--
-- IMPORTANT — C-1 fix:
--   This rollback section also contains the COMPLETE bodies for
--   is_player_eligible() and is_player_eligible_with_reason()
--   as they existed in Phase 4.0 (before Phase 4.1 changed them).
--   Phase 4.1's own rollback section was MISSING these bodies
--   (finding C-1). They are provided here for completeness.
--   If rolling back Phase 4.1 without rolling back Phase 4.1.1 first,
--   use only the "PHASE 4.1 ROLLBACK" section at the end.
-- ============================================================

/*

BEGIN;

-- ── ROLLBACK H-2: Restore validate_referee_no_conflict WITHOUT guards ──

CREATE OR REPLACE FUNCTION validate_referee_no_conflict()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_referee_profile_id UUID;
  v_home_club_id       UUID;
  v_away_club_id       UUID;
BEGIN
  SELECT r.profile_id INTO v_referee_profile_id
  FROM   referees r WHERE r.id = NEW.referee_id;

  SELECT f.home_club_id, f.away_club_id
  INTO   v_home_club_id, v_away_club_id
  FROM   fixtures f WHERE f.id = NEW.fixture_id;

  IF EXISTS (
    SELECT 1 FROM clubs c
    WHERE  c.admin_id = v_referee_profile_id
      AND  c.id IN (v_home_club_id, v_away_club_id)
  ) THEN
    RAISE EXCEPTION
      'Conflict of interest: referee (profile ID: %) is an administrator '
      'of one of the clubs in fixture (ID: %).',
      v_referee_profile_id, NEW.fixture_id
      USING ERRCODE = '23514';
  END IF;

  IF EXISTS (
    SELECT 1 FROM coaches co
    WHERE  co.profile_id = v_referee_profile_id
      AND  co.club_id    IN (v_home_club_id, v_away_club_id)
      AND  co.is_active  = true
  ) THEN
    RAISE EXCEPTION
      'Conflict of interest: referee (profile ID: %) is an active coach '
      'at one of the clubs in fixture (ID: %).',
      v_referee_profile_id, NEW.fixture_id
      USING ERRCODE = '23514';
  END IF;

  IF EXISTS (
    SELECT 1 FROM club_staff cs
    WHERE  cs.profile_id = v_referee_profile_id
      AND  cs.club_id    IN (v_home_club_id, v_away_club_id)
      AND  cs.is_active  = true
  ) THEN
    RAISE EXCEPTION
      'Conflict of interest: referee (profile ID: %) is active club staff '
      'at one of the clubs in fixture (ID: %).',
      v_referee_profile_id, NEW.fixture_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

-- ── ROLLBACK M-2: Restore idx_seasons_league_active ──
-- Only needed if something specifically queries this index name;
-- functionally the unique index covers all the same queries.
CREATE INDEX IF NOT EXISTS idx_seasons_league_active
  ON seasons (league_id, status)
  WHERE status = 'active';

-- ── ROLLBACK H-1: Restore idx_plr_approved WITHOUT season_id ──
DROP INDEX IF EXISTS idx_plr_approved;
CREATE INDEX idx_plr_approved
  ON player_league_registrations (league_id, player_id, club_id, status)
  WHERE status = 'approved';

-- ── ROLLBACK H-3: Drop the new idx_plr_player_created index ──
DROP INDEX IF EXISTS idx_plr_player_created;

-- ── ROLLBACK C-3 + C-2: Restore Phase 4.1 version of the view ──
DROP VIEW IF EXISTS v_player_eligibility_summary;

CREATE VIEW v_player_eligibility_summary AS
SELECT
  pl.id                                                           AS player_id,
  pl.full_name                                                    AS player_name,
  pl.position,
  pl.club_id,
  cl.name                                                         AS club_name,
  pl.is_active,
  EXISTS (
    SELECT 1
    FROM   suspensions s
    WHERE  s.player_id = pl.id
      AND  s.is_active = true
      AND  s.matches_served < s.matches_suspended
  )                                                               AS has_active_suspension,
  (
    SELECT s.league_id
    FROM   suspensions s
    WHERE  s.player_id = pl.id
      AND  s.is_active = true
      AND  s.matches_served < s.matches_suspended
    ORDER  BY s.created_at DESC
    LIMIT  1
  )                                                               AS suspended_in_league_id,
  (
    SELECT (s.matches_suspended - s.matches_served)
    FROM   suspensions s
    WHERE  s.player_id = pl.id
      AND  s.is_active = true
      AND  s.matches_served < s.matches_suspended
    ORDER  BY s.created_at DESC
    LIMIT  1
  )                                                               AS suspension_matches_remaining,
  EXISTS (
    SELECT 1
    FROM   player_injuries pi
    WHERE  pi.player_id = pl.id
      AND  pi.is_active = true
  )                                                               AS has_active_injury,
  (
    SELECT pi.expected_return_date
    FROM   player_injuries pi
    WHERE  pi.player_id = pl.id
      AND  pi.is_active = true
    ORDER  BY pi.injury_date DESC
    LIMIT  1
  )                                                               AS injury_expected_return,
  (
    SELECT plr.status
    FROM   player_league_registrations plr
    WHERE  plr.player_id = pl.id
    ORDER  BY plr.created_at DESC
    LIMIT  1
  )                                                               AS latest_registration_status,
  CASE
    WHEN NOT pl.is_active                           THEN 'Inactive'
    WHEN EXISTS (
           SELECT 1 FROM suspensions s
           WHERE s.player_id = pl.id AND s.is_active = true
             AND s.matches_served < s.matches_suspended
         )                                          THEN 'Suspended'
    WHEN EXISTS (
           SELECT 1 FROM player_injuries pi
           WHERE pi.player_id = pl.id AND pi.is_active = true
         )                                          THEN 'Injured'
    ELSE                                                 'Available'
  END                                                             AS eligible_summary
FROM players pl
JOIN clubs cl ON cl.id = pl.club_id
WHERE pl.is_active = true;

COMMENT ON VIEW v_player_eligibility_summary IS
  'General availability indicators per player. '
  'Does NOT call is_player_eligible() — avoids the NULL fixture_id bug. '
  'For fixture-specific eligibility, call: '
  'is_player_eligible_with_reason(player_id, fixture_id).';

COMMIT;


-- ============================================================
-- PHASE 4.1 ROLLBACK — Complete is_player_eligible() restoration
-- ============================================================
-- C-1 FIX: The Phase 4.1 rollback section was MISSING the SQL
-- bodies to restore is_player_eligible() and
-- is_player_eligible_with_reason() to their Phase 4.0 state.
-- This section provides those bodies.
--
-- Use this block ONLY when rolling back Phase 4.1 itself
-- (not Phase 4.1.1). Run AFTER the Phase 4.1 rollback block
-- has restored the index and constraint changes.
-- ============================================================

BEGIN;

-- Restore is_player_eligible() to Phase 4.0 state:
--   - STABLE (not VOLATILE)
--   - No club_id filter in step 8
--   - No ORDER BY on season lookup (LIMIT 1 only)
CREATE OR REPLACE FUNCTION is_player_eligible(
  p_player_id   UUID,
  p_fixture_id  UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_league_id         UUID;
  v_home_club_id      UUID;
  v_away_club_id      UUID;
  v_match_date        TIMESTAMPTZ;
  v_player_club_id    UUID;
  v_player_dob        DATE;
  v_player_active     BOOLEAN;
  v_season_id         UUID;
  v_reg               RECORD;
  v_rules             RECORD;
  v_win_open          DATE;
  v_win_close         DATE;
  v_age_years         INTEGER;
BEGIN
  SELECT f.league_id, f.home_club_id, f.away_club_id, f.match_date
  INTO   v_league_id, v_home_club_id, v_away_club_id, v_match_date
  FROM   fixtures f
  WHERE  f.id = p_fixture_id;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  SELECT p.club_id, p.date_of_birth, p.is_active
  INTO   v_player_club_id, v_player_dob, v_player_active
  FROM   players p
  WHERE  p.id = p_player_id;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF NOT v_player_active THEN
    RETURN FALSE;
  END IF;

  IF v_player_club_id IS DISTINCT FROM v_home_club_id
     AND v_player_club_id IS DISTINCT FROM v_away_club_id THEN
    RETURN FALSE;
  END IF;

  IF EXISTS (
    SELECT 1 FROM suspensions s
    WHERE  s.player_id = p_player_id
      AND  s.league_id = v_league_id
      AND  s.is_active = true
      AND  s.matches_served < s.matches_suspended
  ) THEN
    RETURN FALSE;
  END IF;

  IF EXISTS (
    SELECT 1 FROM player_injuries pi
    WHERE  pi.player_id = p_player_id
      AND  pi.is_active  = true
  ) THEN
    RETURN FALSE;
  END IF;

  -- Phase 4.0: no ORDER BY, no club_id filter
  SELECT s.id INTO v_season_id
  FROM   seasons s
  WHERE  s.league_id = v_league_id
    AND  s.status    = 'active'
    AND  COALESCE(v_match_date::DATE, CURRENT_DATE) BETWEEN s.start_date AND s.end_date
  LIMIT  1;

  IF v_season_id IS NULL THEN
    RETURN TRUE;
  END IF;

  -- Phase 4.0: no club_id filter (pre-M-04 fix state)
  SELECT plr.* INTO v_reg
  FROM   player_league_registrations plr
  WHERE  plr.player_id = p_player_id
    AND  plr.league_id = v_league_id
    AND  plr.season_id = v_season_id
    AND  plr.status    = 'approved';

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF v_reg.valid_from IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) < v_reg.valid_from THEN
    RETURN FALSE;
  END IF;

  IF v_reg.valid_until IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) > v_reg.valid_until THEN
    RETURN FALSE;
  END IF;

  SELECT er.* INTO v_rules
  FROM   eligibility_rules er
  WHERE  er.season_id  = v_season_id
    AND  er.league_id  = v_league_id;

  IF FOUND THEN
    v_age_years := EXTRACT(YEAR FROM AGE(
      COALESCE(v_match_date::DATE, CURRENT_DATE),
      v_player_dob
    ))::INTEGER;

    IF v_rules.min_age_years IS NOT NULL
       AND v_age_years < v_rules.min_age_years THEN
      RETURN FALSE;
    END IF;

    IF v_rules.max_age_years IS NOT NULL
       AND v_age_years > v_rules.max_age_years THEN
      RETURN FALSE;
    END IF;

    IF v_rules.min_registration_days > 0
       AND v_reg.approved_at IS NOT NULL THEN
      IF (COALESCE(v_match_date::DATE, CURRENT_DATE)
          - v_reg.approved_at::DATE) < v_rules.min_registration_days THEN
        RETURN FALSE;
      END IF;
    END IF;
  END IF;

  RETURN TRUE;
END;
$$;

-- Restore is_player_eligible_with_reason() to Phase 4.0 state:
--   - STABLE (not VOLATILE)
--   - No club_id filter
--   - No ORDER BY on season lookup
--   - Untyped literal returns (SELECT false, 'text' — no ::BOOLEAN, ::TEXT casts)
CREATE OR REPLACE FUNCTION is_player_eligible_with_reason(
  p_player_id   UUID,
  p_fixture_id  UUID
)
RETURNS TABLE (
  eligible   BOOLEAN,
  reason     TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_league_id         UUID;
  v_home_club_id      UUID;
  v_away_club_id      UUID;
  v_match_date        TIMESTAMPTZ;
  v_player_club_id    UUID;
  v_player_dob        DATE;
  v_player_active     BOOLEAN;
  v_season_id         UUID;
  v_reg               RECORD;
  v_rules             RECORD;
  v_age_years         INTEGER;
BEGIN
  SELECT f.league_id, f.home_club_id, f.away_club_id, f.match_date
  INTO   v_league_id, v_home_club_id, v_away_club_id, v_match_date
  FROM   fixtures f WHERE f.id = p_fixture_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Fixture not found';
    RETURN;
  END IF;

  SELECT p.club_id, p.date_of_birth, p.is_active
  INTO   v_player_club_id, v_player_dob, v_player_active
  FROM   players p WHERE p.id = p_player_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Player not found';
    RETURN;
  END IF;

  IF NOT v_player_active THEN
    RETURN QUERY SELECT false, 'Player is not active';
    RETURN;
  END IF;

  IF v_player_club_id IS DISTINCT FROM v_home_club_id
     AND v_player_club_id IS DISTINCT FROM v_away_club_id THEN
    RETURN QUERY SELECT false, 'Player does not belong to either club in this fixture';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM suspensions s
    WHERE  s.player_id = p_player_id
      AND  s.league_id = v_league_id
      AND  s.is_active = true
      AND  s.matches_served < s.matches_suspended
  ) THEN
    RETURN QUERY SELECT false, 'Player has an active suspension in this league';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM player_injuries pi
    WHERE  pi.player_id = p_player_id
      AND  pi.is_active  = true
  ) THEN
    RETURN QUERY SELECT false, 'Player has an active injury';
    RETURN;
  END IF;

  -- Phase 4.0: no ORDER BY, no club_id filter
  SELECT s.id INTO v_season_id
  FROM   seasons s
  WHERE  s.league_id = v_league_id
    AND  s.status    = 'active'
    AND  COALESCE(v_match_date::DATE, CURRENT_DATE) BETWEEN s.start_date AND s.end_date
  LIMIT  1;

  IF v_season_id IS NULL THEN
    RETURN QUERY SELECT true, 'Eligible (no active season context)';
    RETURN;
  END IF;

  -- Phase 4.0: no club_id filter
  SELECT plr.* INTO v_reg
  FROM   player_league_registrations plr
  WHERE  plr.player_id = p_player_id
    AND  plr.league_id = v_league_id
    AND  plr.season_id = v_season_id
    AND  plr.status    = 'approved';

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Player does not have an approved registration for this league/season';
    RETURN;
  END IF;

  IF v_reg.valid_from IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) < v_reg.valid_from THEN
    RETURN QUERY SELECT false, 'Player registration is not yet valid for this match date';
    RETURN;
  END IF;

  IF v_reg.valid_until IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) > v_reg.valid_until THEN
    RETURN QUERY SELECT false, 'Player registration has expired';
    RETURN;
  END IF;

  SELECT er.* INTO v_rules
  FROM   eligibility_rules er
  WHERE  er.season_id = v_season_id AND er.league_id = v_league_id;

  IF FOUND THEN
    v_age_years := EXTRACT(YEAR FROM AGE(
      COALESCE(v_match_date::DATE, CURRENT_DATE),
      v_player_dob
    ))::INTEGER;

    IF v_rules.min_age_years IS NOT NULL AND v_age_years < v_rules.min_age_years THEN
      RETURN QUERY SELECT false,
        'Player is too young (age ' || v_age_years || ', minimum ' || v_rules.min_age_years || ')';
      RETURN;
    END IF;

    IF v_rules.max_age_years IS NOT NULL AND v_age_years > v_rules.max_age_years THEN
      RETURN QUERY SELECT false,
        'Player is too old (age ' || v_age_years || ', maximum ' || v_rules.max_age_years || ')';
      RETURN;
    END IF;

    IF v_rules.min_registration_days > 0 AND v_reg.approved_at IS NOT NULL THEN
      IF (COALESCE(v_match_date::DATE, CURRENT_DATE) - v_reg.approved_at::DATE)
         < v_rules.min_registration_days THEN
        RETURN QUERY SELECT false,
          'Player has not been registered for the minimum required days ('
          || v_rules.min_registration_days || ')';
        RETURN;
      END IF;
    END IF;
  END IF;

  RETURN QUERY SELECT true, 'Player is eligible';
END;
$$;

COMMIT;

*/


-- ============================================================
-- PATCH SUMMARY
-- ============================================================
--
-- Migration: playpro_phase4_1_1_remediation_patch.sql
-- Prerequisite: playpro_phase4_1_stabilization_patch.sql applied
--
-- Findings addressed:
--
--   H-2 [VALID] validate_referee_no_conflict NULL bypass
--       Action:  Added IF NOT FOUND guards after both SELECT INTO
--                statements. Referee lookup and fixture lookup now
--                fail with explicit exceptions on NOT FOUND.
--       Objects: validate_referee_no_conflict() replaced in-place
--       Risk:    LOW — more restrictive, no valid-input regression
--
--   M-2 [VALID] idx_seasons_league_active redundant
--       Action:  Dropped idx_seasons_league_active. The unique
--                partial index idx_seasons_one_active_per_league
--                (Phase 4.1) covers all the same query patterns
--                and enforces the one-active-season constraint.
--       Objects: INDEX idx_seasons_league_active dropped
--       Risk:    LOW — write savings; no query regression
--
--   H-1 [PARTIALLY VALID] idx_plr_approved incomplete
--       Action:  Dropped and recreated idx_plr_approved with
--                season_id as 4th column, making it fully covering
--                for the is_player_eligible() step 8 lookup.
--       Objects: INDEX idx_plr_approved rebuilt
--       Risk:    LOW — brief AccessExclusive during build
--
--   H-3 [VALID] Missing (player_id, created_at DESC) index
--       Action:  Created idx_plr_player_created to support
--                ORDER BY plr.created_at DESC LIMIT 1 queries
--                in v_player_eligibility_summary.
--       Objects: INDEX idx_plr_player_created created
--       Risk:    LOW — additive index, no behavior change
--
--   C-3 [VALID] v_player_eligibility_summary excessive subqueries
--       Action:  Rewrote view using LEFT JOIN LATERAL. Reduced
--                from 7 correlated subqueries per row to 2 lateral
--                joins + 1 correlated subquery. Identical output
--                columns and business logic preserved exactly.
--       Objects: VIEW v_player_eligibility_summary replaced
--       Risk:    LOW — identical output; performance improvement only
--
--   C-2 [PARTIALLY VALID] Coach injury visibility UX inconsistency
--       Action:  Documented in view COMMENT. No RLS change applied.
--                Changing injury_authorized_read to include coaches
--                is a product decision requiring explicit stakeholder
--                authorization. The inconsistency (coaches see
--                eligible_summary='Available' for injured players)
--                is a known design gap, not a security bug.
--       Objects: VIEW v_player_eligibility_summary COMMENT updated
--       Risk:    NONE — comment only
--
--   C-1 [VALID] Incomplete rollback for is_player_eligible()
--       Action:  Added complete Phase 4.0 function bodies to the
--                rollback section (PHASE 4.1 ROLLBACK block) in
--                this file. No forward SQL changed.
--       Objects: Rollback SQL only (commented block)
--       Risk:    NONE — no forward change
--
-- Indexes created:     2  (idx_plr_player_created, idx_plr_approved rebuilt)
-- Indexes dropped:     2  (idx_seasons_league_active, old idx_plr_approved)
-- Functions replaced:  1  (validate_referee_no_conflict)
-- Views replaced:      1  (v_player_eligibility_summary)
-- Tables modified:     0
-- RLS policies:        0  changed
-- Triggers:            0  changed
-- ============================================================
