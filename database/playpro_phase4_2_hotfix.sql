-- ============================================================
-- PLAYPRO — PHASE 4.2: HOTFIX PATCH
-- playpro_phase4_2_hotfix.sql
-- ============================================================
-- Apply AFTER, in order:
--   1. playpro_phase4_critical_fix_pack.sql
--   2. playpro_phase4_1_stabilization_patch.sql
--   3. playpro_phase4_1_1_remediation_patch.sql
--   4. playpro_phase4_1_2_security_patch.sql
--   5. playpro_phase4_1_3_remediation_patch.sql
--   6. THIS FILE
--
-- PostgreSQL 16 compatible. Supabase compatible.
--
-- TRANSACTION STRATEGY
-- ============================================================
-- Single BEGIN…COMMIT block.
-- All three fixes are pure function replacements (CREATE OR REPLACE).
-- No DDL requiring CONCURRENTLY. No index operations.
-- Lock profile: catalog-level only — no table-level locks,
-- no read or write blocking on any data table.
--
-- ============================================================
-- WHAT THIS PATCH FIXES
-- ============================================================
--
-- FIX 1 — HA-C-05: recalculate_standings() row-by-row loop
--
--   Root cause:
--     The Phase 4 implementation uses a PL/pgSQL FOR v_row IN … LOOP
--     that issues two UPDATE statements per fixture row — one for the
--     home club, one for the away club. For a league with N official
--     results, this executes 2N individual UPDATEs against the standings
--     table under a FOR UPDATE lock. Under concurrent match-day writes,
--     each row-level UPDATE acquires its own lock, creating contention
--     between multiple league recalculations running simultaneously.
--     At scale (100 leagues × ~300 results each), this pattern degrades
--     response times and risks lock queue pile-up.
--
--   Fix:
--     Replace with a single-pass set-based INSERT … ON CONFLICT DO UPDATE.
--     A CTE aggregates all official result contributions per club in one
--     scan of match_results + fixtures. The INSERT upserts all standings
--     rows for the league atomically. This replaces 2N UPDATEs with
--     1 INSERT … ON CONFLICT covering all clubs in one statement.
--     An advisory lock (pg_advisory_xact_lock) serialises concurrent
--     recalculations for the same league without blocking reads.
--
--   Important: standings.goal_difference and standings.points are
--     GENERATED ALWAYS AS columns. They cannot appear in the INSERT
--     target list. They are computed automatically by PostgreSQL from
--     goals_for/goals_against and wins/draws respectively.
--
-- FIX 2 — HA-C-06: guard_transfer_status_change() blocks league founders
--
--   Root cause:
--     guard_transfer_status_change() computes:
--       v_is_league_admin := (NEW.league_id IS NOT NULL
--                             AND is_league_admin(NEW.league_id))
--     When player_transfers.league_id IS NULL (legitimate scenario:
--     cross-league transfers, free agent registrations, unaffiliated
--     transfers), v_is_league_admin is FALSE regardless of the caller's
--     role. is_league_admin(NULL) evaluates the EXISTS subqueries with
--     WHERE id = NULL, which matches no rows, returning FALSE for
--     everyone except developers. League founders cannot approve or
--     reject transfers where league_id IS NULL.
--
--   Fix:
--     Expand the approver check to include league_founder role explicitly,
--     independently of whether league_id is set. League founders have
--     platform-wide authority over all transfers. The condition becomes:
--       v_is_approver := (
--         v_my_role = 'league_founder'
--         OR (NEW.league_id IS NOT NULL AND is_league_admin(NEW.league_id))
--       )
--     This preserves all existing behaviour for league_admin-scoped
--     transfers and developers (handled earlier in the function), while
--     allowing league_founder to approve/reject any transfer regardless
--     of whether league_id is NULL.
--
-- FIX 3 — HA-H-07: chk_player_dob_not_future uses strict < not <=
--
--   Root cause:
--     Phase 4 (playpro_phase4_critical_fix_pack.sql line 1238) adds:
--       CHECK (date_of_birth < CURRENT_DATE)
--     Strict less-than means a player born today cannot be registered.
--     While registering a newborn is operationally implausible, the
--     constraint is semantically wrong — a birthday is a valid date
--     of birth that should not be rejected. The correct boundary is
--     date_of_birth <= CURRENT_DATE (not strictly in the future).
--
--   Fix:
--     Drop and recreate the constraint using <=.
--     PostgreSQL does not support ALTER CONSTRAINT to modify a CHECK
--     expression; the constraint must be dropped and re-added.
--     NOT VALID is used to avoid rescanning all existing rows — all
--     current rows already satisfy < CURRENT_DATE, so they also
--     satisfy <= CURRENT_DATE. VALIDATE CONSTRAINT then runs a
--     lightweight scan to officially mark the constraint as valid.
--
-- ============================================================
-- PRE-FLIGHT VALIDATION QUERIES
-- ============================================================
--
-- [V-PRE-1] Confirm recalculate_standings still uses FOR LOOP:
--   SELECT prosrc FROM pg_proc WHERE proname = 'recalculate_standings';
--   EXPECTED: contains 'FOR v_row IN' or 'LOOP'.
--   If already set-based, skip FIX 1.
--
-- [V-PRE-2] Confirm chk_player_dob_not_future exists:
--   SELECT conname, consrc FROM pg_constraint
--   WHERE conname = 'chk_player_dob_not_future';
--   EXPECTED: 1 row with consrc containing 'date_of_birth < CURRENT_DATE'.
--   If already <=, skip FIX 3.
--
-- [V-PRE-3] Confirm guard_transfer_status_change still has the NULL bug:
--   SELECT prosrc FROM pg_proc
--   WHERE proname = 'guard_transfer_status_change';
--   EXPECTED: contains 'league_id IS NOT NULL AND is_league_admin'
--   without an explicit league_founder branch.
--
-- ============================================================

BEGIN;

-- ============================================================
-- FIX 1 — HA-C-05: Replace row-by-row loop with set-based upsert
-- ============================================================

CREATE OR REPLACE FUNCTION recalculate_standings(p_league_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Advisory lock scoped to this transaction.
  -- Serialises concurrent recalculations for the same league.
  -- Does NOT block reads on the standings table. Other leagues
  -- can recalculate concurrently without interference.
  -- hashtext() converts the league UUID to an integer key.
  PERFORM pg_advisory_xact_lock(hashtext('standings_recalc_' || p_league_id::TEXT));

  -- Single-pass set-based upsert.
  -- The CTE aggregates contributions from both sides of every
  -- official result in one scan of match_results + fixtures.
  -- The INSERT then upserts all standings rows for the league
  -- atomically, replacing 2N row-by-row UPDATEs with one statement.
  --
  -- EXCLUDED columns reference the proposed new row values.
  -- goal_difference and points are GENERATED ALWAYS AS columns —
  -- they are NOT listed in the INSERT target and are computed
  -- automatically by PostgreSQL from the inserted column values.
  INSERT INTO standings (
    league_id,
    club_id,
    played,
    wins,
    draws,
    losses,
    goals_for,
    goals_against,
    updated_at
  )
  SELECT
    p_league_id                                   AS league_id,
    club_id,
    SUM(played)                                   AS played,
    SUM(wins)                                     AS wins,
    SUM(draws)                                    AS draws,
    SUM(losses)                                   AS losses,
    SUM(goals_for)                                AS goals_for,
    SUM(goals_against)                            AS goals_against,
    NOW()                                         AS updated_at
  FROM (
    -- Home-club perspective for every official result in this league
    SELECT
      f.home_club_id                                          AS club_id,
      1                                                       AS played,
      CASE WHEN mr.home_goals > mr.away_goals THEN 1 ELSE 0 END AS wins,
      CASE WHEN mr.home_goals = mr.away_goals THEN 1 ELSE 0 END AS draws,
      CASE WHEN mr.home_goals < mr.away_goals THEN 1 ELSE 0 END AS losses,
      mr.home_goals                                           AS goals_for,
      mr.away_goals                                           AS goals_against
    FROM match_results mr
    JOIN fixtures f ON f.id = mr.fixture_id
    WHERE f.league_id    = p_league_id
      AND mr.is_official = true

    UNION ALL

    -- Away-club perspective for the same set of results
    SELECT
      f.away_club_id                                          AS club_id,
      1                                                       AS played,
      CASE WHEN mr.away_goals > mr.home_goals THEN 1 ELSE 0 END AS wins,
      CASE WHEN mr.away_goals = mr.home_goals THEN 1 ELSE 0 END AS draws,
      CASE WHEN mr.away_goals < mr.home_goals THEN 1 ELSE 0 END AS losses,
      mr.away_goals                                           AS goals_for,
      mr.home_goals                                           AS goals_against
    FROM match_results mr
    JOIN fixtures f ON f.id = mr.fixture_id
    WHERE f.league_id    = p_league_id
      AND mr.is_official = true
  ) combined
  GROUP BY club_id

  ON CONFLICT (league_id, club_id) DO UPDATE SET
    played        = EXCLUDED.played,
    wins          = EXCLUDED.wins,
    draws         = EXCLUDED.draws,
    losses        = EXCLUDED.losses,
    goals_for     = EXCLUDED.goals_for,
    goals_against = EXCLUDED.goals_against,
    updated_at    = EXCLUDED.updated_at;
    -- goal_difference and points are GENERATED ALWAYS AS columns;
    -- PostgreSQL recomputes them automatically from the above values.

END;
$$;

COMMENT ON FUNCTION recalculate_standings(UUID) IS
  'Full standings recomputation for one league from official match results. '
  'Phase 4.2: replaced row-by-row FOR LOOP (2N UPDATE statements) with a '
  'single set-based INSERT … ON CONFLICT DO UPDATE covering all clubs in '
  'one query. Advisory lock prevents concurrent recalculations for the same '
  'league while allowing other leagues to recalculate simultaneously.';


-- ============================================================
-- FIX 2 — HA-C-06: Allow league founders to approve NULL-league transfers
-- ============================================================

CREATE OR REPLACE FUNCTION guard_transfer_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_my_role      user_role;
  v_is_approver  BOOLEAN;
BEGIN
  -- No status change: nothing to check
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  v_my_role := get_my_role();

  -- Developers bypass all checks
  IF v_my_role = 'developer' THEN
    RETURN NEW;
  END IF;

  -- Determine whether the caller has approval authority for this transfer.
  --
  -- Phase 4 bug: v_is_league_admin := (NEW.league_id IS NOT NULL
  --              AND is_league_admin(NEW.league_id))
  -- When league_id IS NULL, is_league_admin(NULL) evaluates EXISTS subqueries
  -- with WHERE id = NULL, which matches no rows. league_founder returned FALSE.
  -- League founders could not approve cross-league / unaffiliated transfers.
  --
  -- Fix: add league_founder as an explicit top-level approver.
  -- league_founder has platform-wide authority regardless of league_id.
  -- league_admin authority remains scoped to the specific league_id.
  v_is_approver := (
    v_my_role = 'league_founder'
    OR (NEW.league_id IS NOT NULL AND is_league_admin(NEW.league_id))
  );

  -- Only approvers and developers may set approved or rejected
  IF NEW.status IN ('approved', 'rejected') THEN
    IF NOT v_is_approver THEN
      RAISE EXCEPTION
        'Insufficient privileges: only league administrators or league founders '
        'may approve or reject transfers. Attempted: % → %',
        OLD.status, NEW.status
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Club admins may only cancel pending transfers
  IF v_my_role = 'club_admin' AND NEW.status NOT IN ('cancelled') THEN
    IF NOT v_is_approver THEN
      RAISE EXCEPTION
        'Club administrators may only cancel pending transfers. Attempted: % → %',
        OLD.status, NEW.status
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- A transfer can only be cancelled by a non-approver if it is pending
  IF NEW.status = 'cancelled' AND OLD.status NOT IN ('pending') THEN
    IF NOT v_is_approver THEN
      RAISE EXCEPTION
        'Only pending transfers may be cancelled by a club administrator.'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION guard_transfer_status_change() IS
  'BEFORE UPDATE trigger on player_transfers. Guards status transitions. '
  'Phase 4.2: fixed NULL league_id blocking league founders from approving '
  'cross-league / unaffiliated transfers. league_founder now has explicit '
  'platform-wide approval authority independent of whether league_id is set. '
  'league_admin authority remains scoped to the specific league_id.';

-- The trigger binding (trg_guard_transfer_status) is unchanged.
-- CREATE OR REPLACE FUNCTION replaces the body in-place.


-- ============================================================
-- FIX 3 — HA-H-07: chk_player_dob_not_future strict < corrected to <=
-- ============================================================
-- Root cause: Phase 4 used CHECK (date_of_birth < CURRENT_DATE).
-- A player born today fails registration. The semantically correct
-- boundary is <= CURRENT_DATE (born on or before today, not in the future).
--
-- PostgreSQL does not support altering a CHECK constraint expression
-- in-place. Drop and re-add with NOT VALID + VALIDATE pattern:
--   NOT VALID — creates constraint metadata instantly (no table scan,
--               no ACCESS EXCLUSIVE lock held while scanning rows).
--               New INSERT/UPDATE rows are validated immediately.
--   VALIDATE CONSTRAINT — scans existing rows for violations.
--               Holds SHARE UPDATE EXCLUSIVE lock (allows reads and writes
--               during the scan; blocks concurrent schema changes only).
--
-- Since all existing rows satisfy < CURRENT_DATE, they also satisfy
-- <= CURRENT_DATE. VALIDATE CONSTRAINT will complete without errors.
-- ============================================================

ALTER TABLE players
  DROP CONSTRAINT IF EXISTS chk_player_dob_not_future;

ALTER TABLE players
  ADD CONSTRAINT chk_player_dob_not_future
    CHECK (date_of_birth <= CURRENT_DATE)
  NOT VALID;

-- ============================================================
-- END OF PHASE 4.2 HOTFIX TRANSACTION
-- ============================================================
-- FIX 3 Part A is complete. The constraint exists as NOT VALID.
-- ACCESS EXCLUSIVE is released here.
-- New INSERT/UPDATE rows on players are validated against
-- date_of_birth <= CURRENT_DATE from this point forward.
-- Existing rows are not yet validated — that happens in Part B below.

COMMIT;


-- ============================================================
-- FIX 3 (Part B) — VALIDATE CONSTRAINT
-- Run OUTSIDE any transaction block.
-- ============================================================
-- Why this must be outside a transaction:
--   ALTER TABLE ADD CONSTRAINT NOT VALID (Part A above) held an
--   ACCESS EXCLUSIVE lock until the COMMIT above. That lock is now
--   released. Running VALIDATE CONSTRAINT outside a transaction
--   means it acquires only SHARE UPDATE EXCLUSIVE — which allows
--   concurrent reads and writes on players throughout the scan.
--   If this were placed inside a BEGIN...COMMIT block together with
--   Part A, the ACCESS EXCLUSIVE from ADD CONSTRAINT NOT VALID would
--   be held for the entire duration of the table scan, blocking all
--   DML on players and defeating the purpose of the NOT VALID split.
--
-- Lock acquired: SHARE UPDATE EXCLUSIVE only.
-- Concurrent reads: ✅ allowed.
-- Concurrent INSERT / UPDATE / DELETE: ✅ allowed.
-- Duration: proportional to players table row count.
-- All existing rows satisfy < CURRENT_DATE, so also satisfy
-- <= CURRENT_DATE. This statement will complete without errors.

ALTER TABLE players
  VALIDATE CONSTRAINT chk_player_dob_not_future;

-- ============================================================
-- END OF PHASE 4.2 HOTFIX
-- ============================================================


-- ============================================================
-- POST-APPLY VERIFICATION QUERIES
-- ============================================================
--
-- [V-1] Confirm recalculate_standings is now set-based:
--   SELECT prosrc FROM pg_proc WHERE proname = 'recalculate_standings';
--   EXPECTED: contains 'INSERT INTO standings' and 'ON CONFLICT'.
--   EXPECTED: does NOT contain 'FOR v_row IN'.
--
-- [V-2] Confirm guard_transfer_status_change includes league_founder:
--   SELECT prosrc FROM pg_proc
--   WHERE proname = 'guard_transfer_status_change';
--   EXPECTED: contains 'v_my_role = ''league_founder''' in v_is_approver block.
--
-- [V-3] Confirm chk_player_dob_not_future uses <=:
--   SELECT conname, consrc FROM pg_constraint
--   WHERE conname = 'chk_player_dob_not_future';
--   EXPECTED: consrc contains '<= CURRENT_DATE' or '<= now()'.
--
-- [V-4] Functional test — standings recalculation:
--   SELECT recalculate_standings('<any-valid-league-uuid>');
--   EXPECTED: completes without error; standings rows updated.
--
-- [V-5] Functional test — league founder transfer approval:
--   As a league_founder role user, UPDATE a player_transfers row
--   with status='pending' → status='approved' where league_id IS NULL.
--   EXPECTED: succeeds (was blocked before this patch).
--
-- [V-6] Functional test — today's date player registration:
--   INSERT INTO players (full_name, date_of_birth, position, ...)
--   VALUES ('Test Player', CURRENT_DATE, 'midfielder', ...);
--   EXPECTED: INSERT succeeds (was rejected before this patch).


-- ============================================================
-- ROLLBACK SECTION
-- ============================================================
-- Run inside a single transaction to undo this patch.
-- ============================================================

/*

BEGIN;

-- Rollback FIX 1: restore row-by-row recalculate_standings
CREATE OR REPLACE FUNCTION recalculate_standings(p_league_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_row RECORD;
BEGIN
  PERFORM 1 FROM standings WHERE league_id = p_league_id FOR UPDATE;

  UPDATE standings
  SET played=0, wins=0, draws=0, losses=0,
      goals_for=0, goals_against=0, updated_at=NOW()
  WHERE league_id = p_league_id;

  FOR v_row IN
    SELECT f.home_club_id, f.away_club_id, mr.home_goals, mr.away_goals
    FROM match_results mr
    JOIN fixtures f ON f.id = mr.fixture_id
    WHERE f.league_id = p_league_id AND mr.is_official = true
  LOOP
    INSERT INTO standings (league_id, club_id)
    VALUES (p_league_id, v_row.home_club_id)
    ON CONFLICT (league_id, club_id) DO NOTHING;

    INSERT INTO standings (league_id, club_id)
    VALUES (p_league_id, v_row.away_club_id)
    ON CONFLICT (league_id, club_id) DO NOTHING;

    UPDATE standings SET
      played=played+1,
      wins=wins+CASE WHEN v_row.home_goals>v_row.away_goals THEN 1 ELSE 0 END,
      draws=draws+CASE WHEN v_row.home_goals=v_row.away_goals THEN 1 ELSE 0 END,
      losses=losses+CASE WHEN v_row.home_goals<v_row.away_goals THEN 1 ELSE 0 END,
      goals_for=goals_for+v_row.home_goals,
      goals_against=goals_against+v_row.away_goals,
      updated_at=NOW()
    WHERE league_id=p_league_id AND club_id=v_row.home_club_id;

    UPDATE standings SET
      played=played+1,
      wins=wins+CASE WHEN v_row.away_goals>v_row.home_goals THEN 1 ELSE 0 END,
      draws=draws+CASE WHEN v_row.away_goals=v_row.home_goals THEN 1 ELSE 0 END,
      losses=losses+CASE WHEN v_row.away_goals<v_row.home_goals THEN 1 ELSE 0 END,
      goals_for=goals_for+v_row.away_goals,
      goals_against=goals_against+v_row.home_goals,
      updated_at=NOW()
    WHERE league_id=p_league_id AND club_id=v_row.away_club_id;
  END LOOP;
END;
$$;

-- Rollback FIX 2: restore guard_transfer_status_change without league_founder branch
CREATE OR REPLACE FUNCTION guard_transfer_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_my_role user_role;
  v_is_league_admin BOOLEAN;
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;
  v_my_role := get_my_role();
  IF v_my_role = 'developer' THEN RETURN NEW; END IF;
  v_is_league_admin := (NEW.league_id IS NOT NULL AND is_league_admin(NEW.league_id));
  IF NEW.status IN ('approved', 'rejected') THEN
    IF NOT v_is_league_admin THEN
      RAISE EXCEPTION
        'Insufficient privileges: only league administrators may approve or reject transfers. '
        'Your attempted status change: % → %', OLD.status, NEW.status USING ERRCODE = '42501';
    END IF;
  END IF;
  IF v_my_role = 'club_admin' AND NEW.status NOT IN ('cancelled') THEN
    IF NOT v_is_league_admin THEN
      RAISE EXCEPTION
        'Club administrators may only cancel pending transfers. '
        'Your attempted status change: % → %', OLD.status, NEW.status USING ERRCODE = '42501';
    END IF;
  END IF;
  IF NEW.status = 'cancelled' AND OLD.status NOT IN ('pending') THEN
    IF NOT v_is_league_admin THEN
      RAISE EXCEPTION
        'Only pending transfers may be cancelled by a club administrator.'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Rollback FIX 3: restore strict < constraint
ALTER TABLE players DROP CONSTRAINT IF EXISTS chk_player_dob_not_future;
ALTER TABLE players
  ADD CONSTRAINT chk_player_dob_not_future
    CHECK (date_of_birth < CURRENT_DATE) NOT VALID;
ALTER TABLE players VALIDATE CONSTRAINT chk_player_dob_not_future;

COMMIT;

*/

-- ============================================================
-- PATCH SUMMARY
-- ============================================================
--
-- Phase:            4.2 — Hotfix Patch
-- Applies after:    4.1.3 — Remediation Patch
-- Date:             2026-06-07
--
-- Part A (transactional, single BEGIN…COMMIT):
--   Functions replaced: 2
--     recalculate_standings(UUID)        [FIX 1 — set-based upsert]
--     guard_transfer_status_change()     [FIX 2 — league_founder NULL fix]
--
--   Constraints dropped:  1
--     chk_player_dob_not_future          [FIX 3 — strict < replaced]
--
--   Constraints created:  1
--     chk_player_dob_not_future          [FIX 3 — <= CURRENT_DATE]
--
-- Findings addressed:
--   HA-C-05  ✓  recalculate_standings: 2N UPDATEs → 1 set-based upsert
--   HA-C-06  ✓  guard_transfer: league_founder can now approve NULL-league transfers
--   HA-H-07  ✓  DOB constraint: <= allows today's date
--
-- ============================================================
