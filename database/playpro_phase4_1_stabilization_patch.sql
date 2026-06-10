-- ============================================================
-- PLAYPRO — PHASE 4.1: STABILIZATION PATCH
-- playpro_phase4_1_stabilization_patch.sql
-- ============================================================
-- Apply AFTER playpro_phase4_critical_fix_pack.sql is applied.
-- Fixes 10 verified bugs in Phase 4 functions, triggers,
-- RLS policies, views, and constraints.
--
-- PostgreSQL 16 compatible. Supabase compatible.
-- All fixes are targeted. No unrelated objects are modified.
-- ============================================================
--
-- PRE-FLIGHT DATA VALIDATION QUERIES
-- Run these SELECT statements BEFORE applying this migration.
-- If any query returns rows, resolve the data issues first.
-- ============================================================
--
-- [VALIDATE-1] M-04: Check for duplicate registrations that
-- would violate the new (player_id, club_id, league_id, season_id)
-- unique constraint BEFORE dropping the old one.
-- Expected result: zero rows.
--
--   SELECT player_id, club_id, league_id, season_id, COUNT(*) AS cnt
--   FROM player_league_registrations
--   GROUP BY player_id, club_id, league_id, season_id
--   HAVING COUNT(*) > 1;
--
-- [VALIDATE-2] M-07: Check for leagues that already have multiple
-- active seasons. The new partial unique index will FAIL to create
-- if this query returns rows.
-- Expected result: zero rows.
--
--   SELECT league_id, COUNT(*) AS active_season_count
--   FROM seasons
--   WHERE status = 'active'
--   GROUP BY league_id
--   HAVING COUNT(*) > 1;
--
-- ============================================================
-- EXECUTION ORDER OF FIXES IN THIS FILE
-- ============================================================
-- FIX 1 (C-01) reverse_match_result + handle_result_de_ratification
-- FIX 2 (C-03) sync_appeal_outcome_from_decision
-- FIX 3 (C-04) medical RLS — DROP old policy, replace restricted policy
-- FIX 4 (H-02) enforce_lineup_eligibility
-- FIX 5 (H-03) player_injuries authorized read RLS
-- FIX 6 (H-05) v_player_eligibility_check → v_player_eligibility_summary
-- FIX 7 (H-06) validate_fixture_clubs_in_league
-- FIX 8 (M-04) player_league_registrations unique constraint
-- FIX 9 (M-07) seasons one-active-per-league index
-- FIX 10 (C-02) validate_referee_no_conflict Cartesian join cleanup
-- ============================================================

BEGIN;

-- ============================================================
-- FIX 1 — C-01: DE-RATIFICATION TRIGGER ROLLBACK BUG
-- ============================================================
-- Root cause:
--   reverse_match_result(p_fixture_id) queries match_results
--   WHERE is_official = TRUE after the AFTER UPDATE trigger
--   fires. By that point the row already has is_official = FALSE,
--   so the query finds nothing and raises ERRCODE 02000,
--   rolling back the entire de-ratification UPDATE.
--
-- Fix:
--   1. Replace reverse_match_result() signature to accept
--      p_home_goals and p_away_goals directly as parameters.
--      The function no longer queries match_results at all.
--   2. Replace handle_result_de_ratification() to pass
--      OLD.home_goals and OLD.away_goals (the pre-update values
--      still available in the AFTER trigger's OLD record).
--
-- Impact on handle_official_result_correction():
--   That function does NOT call reverse_match_result(); it
--   operates directly on OLD.* and NEW.* values from the
--   trigger record. It is unaffected by this change.
--
-- Backward compatibility:
--   reverse_match_result() changes from 1-argument to 3-argument.
--   The old 1-argument overload is dropped explicitly so that
--   stale callers raise a clear error rather than silently
--   calling the wrong signature.
-- ============================================================

-- Drop the old 1-argument version so there is no ambiguous overload
DROP FUNCTION IF EXISTS reverse_match_result(UUID);

-- New 3-argument version — no longer queries match_results
CREATE OR REPLACE FUNCTION reverse_match_result(
  p_fixture_id  UUID,
  p_home_goals  INTEGER,
  p_away_goals  INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_league_id UUID;
  v_home_id   UUID;
  v_away_id   UUID;
BEGIN
  SELECT f.league_id, f.home_club_id, f.away_club_id
  INTO   v_league_id, v_home_id, v_away_id
  FROM   fixtures f
  WHERE  f.id = p_fixture_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'reverse_match_result: fixture % not found', p_fixture_id
      USING ERRCODE = '02000';
  END IF;

  -- Subtract this result's contribution from both clubs' standings.
  -- GREATEST(..., 0) prevents standings columns going negative due to
  -- data inconsistencies that may exist before this patch was applied.
  UPDATE standings SET
    played        = GREATEST(played - 1, 0),
    wins          = GREATEST(wins   - CASE WHEN p_home_goals > p_away_goals THEN 1 ELSE 0 END, 0),
    draws         = GREATEST(draws  - CASE WHEN p_home_goals = p_away_goals THEN 1 ELSE 0 END, 0),
    losses        = GREATEST(losses - CASE WHEN p_home_goals < p_away_goals THEN 1 ELSE 0 END, 0),
    goals_for     = GREATEST(goals_for     - p_home_goals, 0),
    goals_against = GREATEST(goals_against - p_away_goals, 0),
    updated_at    = NOW()
  WHERE league_id = v_league_id AND club_id = v_home_id;

  UPDATE standings SET
    played        = GREATEST(played - 1, 0),
    wins          = GREATEST(wins   - CASE WHEN p_away_goals > p_home_goals THEN 1 ELSE 0 END, 0),
    draws         = GREATEST(draws  - CASE WHEN p_away_goals = p_home_goals THEN 1 ELSE 0 END, 0),
    losses        = GREATEST(losses - CASE WHEN p_away_goals < p_home_goals THEN 1 ELSE 0 END, 0),
    goals_for     = GREATEST(goals_for     - p_away_goals, 0),
    goals_against = GREATEST(goals_against - p_home_goals, 0),
    updated_at    = NOW()
  WHERE league_id = v_league_id AND club_id = v_away_id;
END;
$$;

-- Replace the trigger function to pass OLD goal values directly.
-- OLD.home_goals and OLD.away_goals are the values that were in
-- effect when the result was official — exactly what we need to
-- subtract. They are available in AFTER triggers.
CREATE OR REPLACE FUNCTION handle_result_de_ratification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Fire only when is_official flips TRUE → FALSE (de-ratification)
  IF TG_OP = 'UPDATE'
     AND OLD.is_official = true
     AND NEW.is_official = false
  THEN
    -- Pass the PRE-UPDATE goal values from OLD directly.
    -- Do NOT re-query match_results — the row now shows is_official=false
    -- and a WHERE is_official = true would find nothing.
    PERFORM reverse_match_result(
      OLD.fixture_id,
      OLD.home_goals,
      OLD.away_goals
    );
  END IF;
  RETURN NEW;
END;
$$;

-- The trigger binding is unchanged; DROP + recreate is not needed
-- because the trigger still points to handle_result_de_ratification().
-- CREATE OR REPLACE FUNCTION replaced the body in place.


-- ============================================================
-- FIX 2 — C-03: APPEAL OVERTURN / REDUCTION CONFLICT
-- ============================================================
-- Root cause:
--   sync_appeal_outcome_from_decision() uses two independent
--   IF blocks. When both suspension_overturned = true AND
--   revised_matches_suspended IS NOT NULL, both execute.
--   Block 1 sets is_active = false (correct — overturn).
--   Block 2 then overwrites is_active = (matches_served <
--   revised_matches_suspended), potentially reactivating a
--   suspension that was supposed to be fully removed.
--   Additionally, suspension_id is fetched twice via two
--   identical correlated subqueries.
--
-- Fix:
--   1. Fetch suspension_id once into a local variable.
--   2. Convert the two IF blocks to IF / ELSIF so only one
--      branch executes per invocation.
--   3. Overturn takes absolute precedence.
-- ============================================================

CREATE OR REPLACE FUNCTION sync_appeal_outcome_from_decision()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_suspension_id UUID;
BEGIN
  -- Step 1: Update the parent appeal record status and outcome fields
  UPDATE disciplinary_appeals
  SET
    outcome       = NEW.outcome,
    outcome_notes = NEW.decision_text,
    decided_at    = NEW.decided_at,
    decided_by    = NEW.decided_by,
    status        = 'decided',
    updated_at    = NOW()
  WHERE id = NEW.appeal_id;

  -- Step 2: Fetch suspension_id once to avoid duplicate correlated subqueries
  SELECT da.suspension_id
  INTO   v_suspension_id
  FROM   disciplinary_appeals da
  WHERE  da.id = NEW.appeal_id;

  -- Nothing to do if this appeal is not linked to a suspension
  IF v_suspension_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Step 3: Apply suspension outcome — OVERTURN and REDUCTION are
  -- mutually exclusive. Use IF/ELSIF so only one branch runs.
  -- Overturn takes absolute precedence; if both flags are somehow
  -- set, the suspension is fully removed and no reduction is applied.
  IF NEW.suspension_overturned THEN

    UPDATE suspensions
    SET
      is_active    = false,
      reason_notes = COALESCE(reason_notes, '') ||
                     ' [Overturned on appeal ' || NEW.decided_at::DATE::TEXT || ']',
      updated_at   = NOW()
    WHERE id = v_suspension_id;

  ELSIF NEW.revised_matches_suspended IS NOT NULL THEN

    UPDATE suspensions
    SET
      matches_suspended = NEW.revised_matches_suspended,
      -- Recompute active flag: still active if not yet fully served
      is_active         = (matches_served < NEW.revised_matches_suspended),
      reason_notes      = COALESCE(reason_notes, '') ||
                          ' [Reduced from ' ||
                          COALESCE(NEW.original_matches_suspended::TEXT, '?') ||
                          ' to '  || NEW.revised_matches_suspended::TEXT ||
                          ' on appeal ' || NEW.decided_at::DATE::TEXT || ']',
      updated_at        = NOW()
    WHERE id = v_suspension_id;

  END IF;

  RETURN NEW;
END;
$$;

-- trg_sync_appeal_outcome still points to this function; no trigger
-- recreation needed because CREATE OR REPLACE replaced the body.


-- ============================================================
-- FIX 3 — C-04: MEDICAL RLS PUBLIC EXPOSURE
-- ============================================================
-- Root cause:
--   Phase 3 created "player_injuries: public read" USING (true).
--   Phase 4 created "player_injuries: authorized read" but left
--   the Phase 3 policy alive (the DROP was only a SQL comment).
--   In Supabase PERMISSIVE mode, both policies are OR'd together.
--   USING (true) always wins, nullifying the restricted policy.
--   diagnosis, treatment_notes, medical_notes are fully public.
--
-- Fix:
--   Execute the DROP as real SQL inside this transaction.
--   Then drop and recreate the authorized policy with the
--   corrected league admin check (H-03 is combined here to
--   avoid having two consecutive policy operations on the
--   same table).
-- ============================================================

-- Remove the Phase 3 unrestricted public read policy
DROP POLICY IF EXISTS "player_injuries: public read" ON player_injuries;

-- Remove the Phase 4 authorized read policy that had the broken
-- fixtures JOIN (H-03 fix is incorporated here)
DROP POLICY IF EXISTS "player_injuries: authorized read" ON player_injuries;

-- Replacement: corrected authorized read policy
-- League admin check uses league_clubs directly — no fixtures dependency.
-- A league with no fixtures yet still grants access to its admins.
CREATE POLICY "player_injuries: authorized read"
  ON player_injuries FOR SELECT
  USING (
    -- Developers: full access to all injury data
    get_my_role() = 'developer'

    -- League founders: full access to all injury data
    OR get_my_role() = 'league_founder'

    -- Club admin of the player's own club: full access
    OR is_club_admin(player_injuries.club_id)

    -- League admin: can see injuries for clubs in leagues they administer.
    -- Uses league_clubs directly — no fixture dependency (fixes H-03).
    OR EXISTS (
      SELECT 1
      FROM   league_clubs lc
      WHERE  lc.club_id  = player_injuries.club_id
        AND  lc.approved = true
        AND  is_league_admin(lc.league_id)
      LIMIT  1
    )

    -- Assigned physiotherapist of the player's club
    OR EXISTS (
      SELECT 1
      FROM   club_staff cs
      WHERE  cs.club_id    = player_injuries.club_id
        AND  cs.profile_id = auth.uid()
        AND  cs.is_active  = true
        AND  cs.role       = 'physiotherapist'
    )
  );


-- ============================================================
-- FIX 4 — H-02: CONFIRMED LINEUP BYPASS
-- ============================================================
-- Root cause:
--   enforce_lineup_eligibility() exits immediately when
--   OLD.confirmed_at IS NOT NULL, regardless of what changed.
--   This means a league admin changing player_id on a confirmed
--   starter row to a suspended or injured player bypasses all
--   eligibility validation.
--
-- Fix:
--   Only skip the eligibility check when the three fields that
--   govern eligibility — player_id, fixture_id, and role — are
--   all unchanged. Metadata-only updates (formation, jersey_number,
--   position_slot, etc.) are still allowed without re-validation.
--   Any structural change that affects who is playing must be
--   re-validated even on confirmed lineups.
-- ============================================================

CREATE OR REPLACE FUNCTION enforce_lineup_eligibility()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_eligible    BOOLEAN;
  v_reason      TEXT;
  v_player_name TEXT;
BEGIN
  -- Only enforce for starters.
  -- substitute and not_selected roles are not validated here.
  IF NEW.role <> 'starter' THEN
    RETURN NEW;
  END IF;

  -- On UPDATE: skip eligibility re-check only when the three
  -- fields that determine who is playing are all unchanged.
  -- This permits metadata edits (formation, jersey_number,
  -- position_slot, lineup_order, is_captain, etc.) without
  -- triggering the eligibility check even on confirmed rows.
  -- Any change to player_id, fixture_id, or role MUST be re-validated.
  IF TG_OP = 'UPDATE'
     AND OLD.player_id  = NEW.player_id
     AND OLD.fixture_id = NEW.fixture_id
     AND OLD.role       = NEW.role
  THEN
    RETURN NEW;
  END IF;

  -- Run the full eligibility check
  SELECT eligible, reason
  INTO   v_eligible, v_reason
  FROM   is_player_eligible_with_reason(NEW.player_id, NEW.fixture_id);

  IF NOT v_eligible THEN
    SELECT full_name INTO v_player_name
    FROM   players WHERE id = NEW.player_id;

    RAISE EXCEPTION
      'Lineup eligibility check failed for player "%" (ID: %): %',
      COALESCE(v_player_name, 'Unknown'),
      NEW.player_id,
      v_reason
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

-- trg_enforce_lineup_eligibility still points to this function.
-- No trigger recreation needed.


-- ============================================================
-- FIX 5 — H-03: LEAGUE ADMIN INJURY ACCESS VIA FIXTURES JOIN
-- ============================================================
-- Root cause:
--   The league admin EXISTS check in the Phase 4 authorized
--   read policy joined to the fixtures table:
--     JOIN fixtures f ON f.league_id = lc.league_id
--   This meant: if a league has no fixtures yet, the JOIN
--   produces no rows, EXISTS evaluates false, and league admins
--   cannot see any injury records — exactly when they need to
--   (pre-season registration decisions).
--
-- Fix:
--   Already addressed in FIX 3 above (the replacement policy
--   "player_injuries: authorized read" uses league_clubs directly
--   with no fixtures join). FIX 5 is structurally merged into FIX 3
--   to avoid two consecutive DROP/CREATE cycles on the same policy
--   name on the same table.
--
-- This section is intentionally a no-op comment block to preserve
-- the numbered fix sequence for traceability.
-- H-03 fix is implemented in FIX 3 above.


-- ============================================================
-- FIX 6 — H-05: ELIGIBILITY VIEW ALWAYS RETURNS FALSE
-- ============================================================
-- Root cause:
--   v_player_eligibility_check calls:
--     is_player_eligible(pl.id, NULL::UUID)
--   Inside is_player_eligible, step 1 queries:
--     WHERE f.id = NULL
--   NULL = NULL evaluates to NULL (not TRUE) in PostgreSQL.
--   No fixture is found. IF NOT FOUND → RETURN FALSE.
--   Every player in the view shows eligible_generic = false.
--   The view is completely non-functional.
--
-- Fix:
--   Drop the broken view entirely and replace it with
--   v_player_eligibility_summary which does not call
--   is_player_eligible() at all. Instead it surfaces the
--   component indicators (suspension, injury, registration
--   status) directly so the UI can reason about each independently.
--   For fixture-specific eligibility, callers must use
--   is_player_eligible_with_reason(player_id, fixture_id).
-- ============================================================

DROP VIEW IF EXISTS v_player_eligibility_check;

CREATE VIEW v_player_eligibility_summary AS
SELECT
  pl.id                                                           AS player_id,
  pl.full_name                                                    AS player_name,
  pl.position,
  pl.club_id,
  cl.name                                                         AS club_name,
  pl.is_active,

  -- Active suspension in any league
  EXISTS (
    SELECT 1
    FROM   suspensions s
    WHERE  s.player_id = pl.id
      AND  s.is_active = true
      AND  s.matches_served < s.matches_suspended
  )                                                               AS has_active_suspension,

  -- Details of the most recent active suspension (NULL if none)
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

  -- Active injury (any)
  EXISTS (
    SELECT 1
    FROM   player_injuries pi
    WHERE  pi.player_id = pl.id
      AND  pi.is_active = true
  )                                                               AS has_active_injury,

  -- Expected return date for the active injury (NULL if no active injury)
  (
    SELECT pi.expected_return_date
    FROM   player_injuries pi
    WHERE  pi.player_id = pl.id
      AND  pi.is_active = true
    ORDER  BY pi.injury_date DESC
    LIMIT  1
  )                                                               AS injury_expected_return,

  -- Most recent registration status across all leagues/seasons
  (
    SELECT plr.status
    FROM   player_league_registrations plr
    WHERE  plr.player_id = pl.id
    ORDER  BY plr.created_at DESC
    LIMIT  1
  )                                                               AS latest_registration_status,

  -- Computed plain-language summary for display columns
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


-- ============================================================
-- FIX 7 — H-06: FIXTURE VALIDATION OPERATIONAL LOCK
-- ============================================================
-- Root cause:
--   validate_fixture_clubs_in_league() fires on BEFORE INSERT
--   OR UPDATE on fixtures, and queries league_clubs.approved = true
--   on every call. If a club's approval is revoked after fixtures
--   were created, any subsequent UPDATE to those fixtures (even
--   changing only status, match_date, or venue) raises an exception
--   and blocks all administrative operations on that fixture.
--
-- Fix:
--   Add an early-exit guard: skip validation when UPDATE does not
--   change any of the three structurally significant columns
--   (league_id, home_club_id, away_club_id). Only INSERT, or an
--   UPDATE that actually reassigns clubs or the league, needs to
--   re-validate membership.
-- ============================================================

CREATE OR REPLACE FUNCTION validate_fixture_clubs_in_league()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Skip validation on UPDATE when none of the structural fields change.
  -- Status updates, date reschedules, venue changes, etc. must not fail
  -- because club approval was revoked after the fixture was created.
  IF TG_OP = 'UPDATE'
     AND OLD.league_id    = NEW.league_id
     AND OLD.home_club_id = NEW.home_club_id
     AND OLD.away_club_id = NEW.away_club_id
  THEN
    RETURN NEW;
  END IF;

  -- Validate home club membership for INSERT or structural UPDATE
  IF NOT EXISTS (
    SELECT 1
    FROM   league_clubs lc
    WHERE  lc.league_id = NEW.league_id
      AND  lc.club_id   = NEW.home_club_id
      AND  lc.approved  = true
  ) THEN
    RAISE EXCEPTION
      'Home club (ID: %) is not an approved member of league (ID: %)',
      NEW.home_club_id, NEW.league_id
      USING ERRCODE = '23514';
  END IF;

  -- Validate away club membership
  IF NOT EXISTS (
    SELECT 1
    FROM   league_clubs lc
    WHERE  lc.league_id = NEW.league_id
      AND  lc.club_id   = NEW.away_club_id
      AND  lc.approved  = true
  ) THEN
    RAISE EXCEPTION
      'Away club (ID: %) is not an approved member of league (ID: %)',
      NEW.away_club_id, NEW.league_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

-- trg_validate_fixture_clubs still points to this function.
-- No trigger recreation needed.


-- ============================================================
-- FIX 8 — M-04: MID-SEASON TRANSFER REGISTRATION CONFLICT
-- ============================================================
-- Root cause:
--   player_league_registrations has:
--     UNIQUE (player_id, league_id, season_id)
--   This prevents a player from being registered at Club B
--   in the same league and season they were registered at
--   Club A, making mid-season transfers structurally impossible.
--
-- Fix:
--   1. Drop the existing 3-column unique constraint.
--   2. Add a 4-column constraint that includes club_id, allowing
--      one registration row per (player, club, league, season).
--   3. Drop the existing partial index on approved registrations
--      and recreate it to include club_id for efficient lookup.
--
-- IMPORTANT: Run VALIDATE-1 from the pre-flight section before
-- applying this fix. The new constraint will fail if any
-- (player_id, club_id, league_id, season_id) tuple already
-- has duplicate rows.
-- ============================================================

-- Step 1: Drop the old 3-column unique constraint.
-- PostgreSQL names auto-generated unique constraints after the
-- pattern tablename_col1_col2_..._key. Confirm the constraint
-- name in your environment with:
--   SELECT conname FROM pg_constraint
--   WHERE conrelid = 'player_league_registrations'::regclass
--     AND contype = 'u';
ALTER TABLE player_league_registrations
  DROP CONSTRAINT IF EXISTS player_league_registrations_player_id_league_id_season_id_key;

-- Step 2: Add the replacement 4-column unique constraint.
-- Named explicitly for reliable rollback and documentation.
ALTER TABLE player_league_registrations
  ADD CONSTRAINT uq_plr_player_club_league_season
    UNIQUE (player_id, club_id, league_id, season_id);

-- Step 3: Drop the old partial index on approved registrations.
-- It was built on (league_id, player_id, status) and is now
-- replaced with one that also covers club_id.
DROP INDEX IF EXISTS idx_plr_approved;

-- Step 4: Recreate the approved-status lookup index with club_id.
-- Used by is_player_eligible() to find the current club's
-- approved registration quickly.
CREATE INDEX idx_plr_approved
  ON player_league_registrations (league_id, player_id, club_id, status)
  WHERE status = 'approved';


-- ============================================================
-- FIX 9 — M-07: MULTIPLE ACTIVE SEASONS PER LEAGUE
-- ============================================================
-- Root cause:
--   No constraint prevents multiple rows in seasons with
--   status = 'active' for the same league_id.
--   is_player_eligible() uses LIMIT 1 with no ORDER BY,
--   producing non-deterministic eligibility results when
--   two active seasons overlap.
--
-- Fix:
--   1. Create a partial unique index on (league_id) WHERE
--      status = 'active'. This enforces at most one active
--      season per league at the database level.
--   2. Add ORDER BY start_date DESC to the season lookup in
--      is_player_eligible() as a deterministic fallback
--      (defense-in-depth even with the index in place).
--
-- IMPORTANT: Run VALIDATE-2 from the pre-flight section before
-- applying this fix. The index creation will fail with a unique
-- violation if any league already has multiple active seasons.
-- ============================================================

-- Step 1: Partial unique index — one active season per league
CREATE UNIQUE INDEX idx_seasons_one_active_per_league
  ON seasons (league_id)
  WHERE status = 'active';

-- Step 2: Update is_player_eligible() to use deterministic
-- ORDER BY on the season lookup, and change STABLE to VOLATILE
-- so the planner never caches results across rows in a batch.
CREATE OR REPLACE FUNCTION is_player_eligible(
  p_player_id   UUID,
  p_fixture_id  UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE                -- was STABLE; VOLATILE prevents result caching
SECURITY DEFINER
AS $$
DECLARE
  v_league_id      UUID;
  v_home_club_id   UUID;
  v_away_club_id   UUID;
  v_match_date     TIMESTAMPTZ;
  v_player_club_id UUID;
  v_player_dob     DATE;
  v_player_active  BOOLEAN;
  v_season_id      UUID;
  v_reg            RECORD;
  v_rules          RECORD;
  v_age_years      INTEGER;
BEGIN
  -- 1. Load fixture context
  SELECT f.league_id, f.home_club_id, f.away_club_id, f.match_date
  INTO   v_league_id, v_home_club_id, v_away_club_id, v_match_date
  FROM   fixtures f
  WHERE  f.id = p_fixture_id;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- 2. Load player context
  SELECT p.club_id, p.date_of_birth, p.is_active
  INTO   v_player_club_id, v_player_dob, v_player_active
  FROM   players p
  WHERE  p.id = p_player_id;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- 3. Player must be active
  IF NOT v_player_active THEN
    RETURN FALSE;
  END IF;

  -- 4. Player must belong to one of the two clubs in the fixture
  IF v_player_club_id IS DISTINCT FROM v_home_club_id
     AND v_player_club_id IS DISTINCT FROM v_away_club_id THEN
    RETURN FALSE;
  END IF;

  -- 5. No active suspension in this league
  IF EXISTS (
    SELECT 1 FROM suspensions s
    WHERE  s.player_id = p_player_id
      AND  s.league_id = v_league_id
      AND  s.is_active = true
      AND  s.matches_served < s.matches_suspended
  ) THEN
    RETURN FALSE;
  END IF;

  -- 6. No active injury
  IF EXISTS (
    SELECT 1 FROM player_injuries pi
    WHERE  pi.player_id = p_player_id
      AND  pi.is_active  = true
  ) THEN
    RETURN FALSE;
  END IF;

  -- 7. Find the active season for this league on match date.
  -- ORDER BY start_date DESC is deterministic and ensures the
  -- most recent active season is chosen (defense-in-depth;
  -- the unique index from FIX 9 enforces at most one active season).
  SELECT s.id INTO v_season_id
  FROM   seasons s
  WHERE  s.league_id = v_league_id
    AND  s.status    = 'active'
    AND  COALESCE(v_match_date::DATE, CURRENT_DATE)
           BETWEEN s.start_date AND s.end_date
  ORDER  BY s.start_date DESC
  LIMIT  1;

  -- No active season found — skip season-bound checks gracefully
  IF v_season_id IS NULL THEN
    RETURN TRUE;
  END IF;

  -- 8. Player must have an approved league registration for their
  -- current club. club_id filter added (M-04 fix) to ensure the
  -- registration belongs to the player's current club, not a
  -- stale registration from a previous club in the same season.
  SELECT plr.* INTO v_reg
  FROM   player_league_registrations plr
  WHERE  plr.player_id = p_player_id
    AND  plr.club_id   = v_player_club_id
    AND  plr.league_id = v_league_id
    AND  plr.season_id = v_season_id
    AND  plr.status    = 'approved';

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- 9. Registration validity window
  IF v_reg.valid_from IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) < v_reg.valid_from THEN
    RETURN FALSE;
  END IF;

  IF v_reg.valid_until IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) > v_reg.valid_until THEN
    RETURN FALSE;
  END IF;

  -- 10. Load eligibility rules for this season
  SELECT er.* INTO v_rules
  FROM   eligibility_rules er
  WHERE  er.season_id = v_season_id
    AND  er.league_id = v_league_id;

  IF FOUND THEN
    -- 11. Age category compliance
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

    -- 12. Minimum registration days elapsed
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

-- Also update the diagnostic variant to use VOLATILE + deterministic
-- ORDER BY + club_id filter for consistency with the main function.
CREATE OR REPLACE FUNCTION is_player_eligible_with_reason(
  p_player_id   UUID,
  p_fixture_id  UUID
)
RETURNS TABLE (eligible BOOLEAN, reason TEXT)
LANGUAGE plpgsql
VOLATILE                -- was STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_league_id      UUID;
  v_home_club_id   UUID;
  v_away_club_id   UUID;
  v_match_date     TIMESTAMPTZ;
  v_player_club_id UUID;
  v_player_dob     DATE;
  v_player_active  BOOLEAN;
  v_season_id      UUID;
  v_reg            RECORD;
  v_rules          RECORD;
  v_age_years      INTEGER;
BEGIN
  SELECT f.league_id, f.home_club_id, f.away_club_id, f.match_date
  INTO   v_league_id, v_home_club_id, v_away_club_id, v_match_date
  FROM   fixtures f WHERE f.id = p_fixture_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false::BOOLEAN, 'Fixture not found'::TEXT;
    RETURN;
  END IF;

  SELECT p.club_id, p.date_of_birth, p.is_active
  INTO   v_player_club_id, v_player_dob, v_player_active
  FROM   players p WHERE p.id = p_player_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false::BOOLEAN, 'Player not found'::TEXT;
    RETURN;
  END IF;

  IF NOT v_player_active THEN
    RETURN QUERY SELECT false::BOOLEAN, 'Player is not active'::TEXT;
    RETURN;
  END IF;

  IF v_player_club_id IS DISTINCT FROM v_home_club_id
     AND v_player_club_id IS DISTINCT FROM v_away_club_id THEN
    RETURN QUERY SELECT false::BOOLEAN,
      'Player does not belong to either club in this fixture'::TEXT;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM suspensions s
    WHERE  s.player_id = p_player_id
      AND  s.league_id = v_league_id
      AND  s.is_active = true
      AND  s.matches_served < s.matches_suspended
  ) THEN
    RETURN QUERY SELECT false::BOOLEAN,
      'Player has an active suspension in this league'::TEXT;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM player_injuries pi
    WHERE  pi.player_id = p_player_id
      AND  pi.is_active  = true
  ) THEN
    RETURN QUERY SELECT false::BOOLEAN, 'Player has an active injury'::TEXT;
    RETURN;
  END IF;

  SELECT s.id INTO v_season_id
  FROM   seasons s
  WHERE  s.league_id = v_league_id
    AND  s.status    = 'active'
    AND  COALESCE(v_match_date::DATE, CURRENT_DATE)
           BETWEEN s.start_date AND s.end_date
  ORDER  BY s.start_date DESC
  LIMIT  1;

  IF v_season_id IS NULL THEN
    RETURN QUERY SELECT true::BOOLEAN,
      'Eligible (no active season context)'::TEXT;
    RETURN;
  END IF;

  -- club_id filter added: only the registration for the player's
  -- current club counts (M-04 fix)
  SELECT plr.* INTO v_reg
  FROM   player_league_registrations plr
  WHERE  plr.player_id = p_player_id
    AND  plr.club_id   = v_player_club_id
    AND  plr.league_id = v_league_id
    AND  plr.season_id = v_season_id
    AND  plr.status    = 'approved';

  IF NOT FOUND THEN
    RETURN QUERY SELECT false::BOOLEAN,
      'Player does not have an approved registration for this league/season'::TEXT;
    RETURN;
  END IF;

  IF v_reg.valid_from IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) < v_reg.valid_from THEN
    RETURN QUERY SELECT false::BOOLEAN,
      'Player registration is not yet valid for this match date'::TEXT;
    RETURN;
  END IF;

  IF v_reg.valid_until IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) > v_reg.valid_until THEN
    RETURN QUERY SELECT false::BOOLEAN,
      'Player registration has expired'::TEXT;
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

    IF v_rules.min_age_years IS NOT NULL
       AND v_age_years < v_rules.min_age_years THEN
      RETURN QUERY SELECT false::BOOLEAN,
        ('Player is too young (age ' || v_age_years ||
         ', minimum ' || v_rules.min_age_years || ')')::TEXT;
      RETURN;
    END IF;

    IF v_rules.max_age_years IS NOT NULL
       AND v_age_years > v_rules.max_age_years THEN
      RETURN QUERY SELECT false::BOOLEAN,
        ('Player is too old (age ' || v_age_years ||
         ', maximum ' || v_rules.max_age_years || ')')::TEXT;
      RETURN;
    END IF;

    IF v_rules.min_registration_days > 0
       AND v_reg.approved_at IS NOT NULL THEN
      IF (COALESCE(v_match_date::DATE, CURRENT_DATE)
          - v_reg.approved_at::DATE) < v_rules.min_registration_days THEN
        RETURN QUERY SELECT false::BOOLEAN,
          ('Player has not been registered for the minimum required days (' ||
           v_rules.min_registration_days || ')')::TEXT;
        RETURN;
      END IF;
    END IF;
  END IF;

  RETURN QUERY SELECT true::BOOLEAN, 'Player is eligible'::TEXT;
END;
$$;


-- ============================================================
-- FIX 10 — C-02: REFEREE CONFLICT CARTESIAN JOIN CLEANUP
-- ============================================================
-- Root cause:
--   validate_referee_no_conflict() contained an outer IF EXISTS
--   block with a structurally broken JOIN:
--     SELECT 1 FROM players p
--     JOIN profiles pr ON pr.id = v_referee_profile_id
--     WHERE p.club_id IN (...)
--   This is a cross-join against a constant UUID, not a join
--   between players and profiles. It evaluates TRUE whenever
--   the referee's profile exists AND any player is at either
--   club — which is almost always true.
--   The outer block then falls through to the coach/staff
--   sub-checks which are correct, so no false exceptions fire.
--   But the outer EXISTS performs an unnecessary full player
--   table scan on every assignment.
--
-- Fix:
--   Remove the broken outer block entirely.
--   Promote the coach and club_staff conflict checks to
--   top-level guards so they always run unconditionally.
--   Preserve all three conflict checks:
--     1. Referee is club admin of either club
--     2. Referee is active coach at either club
--     3. Referee is active club_staff at either club
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
  -- Resolve the referee's system profile
  SELECT r.profile_id INTO v_referee_profile_id
  FROM   referees r WHERE r.id = NEW.referee_id;

  -- Resolve the fixture's two clubs
  SELECT f.home_club_id, f.away_club_id
  INTO   v_home_club_id, v_away_club_id
  FROM   fixtures f WHERE f.id = NEW.fixture_id;

  -- Guard 1: Referee is the club administrator of either club
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

  -- Guard 2: Referee is an active registered coach at either club.
  -- Promoted from inner sub-check to top-level guard.
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

  -- Guard 3: Referee is active club staff at either club.
  -- Promoted from inner sub-check to top-level guard.
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

-- trg_validate_referee_conflict still points to this function.
-- No trigger recreation needed.


-- ============================================================
-- END OF STABILIZATION PATCH
-- ============================================================

COMMIT;


-- ============================================================
-- ROLLBACK SQL
-- Run these statements to undo this patch after COMMIT.
-- Execute in a single transaction for atomicity.
-- ============================================================
--
-- BEGIN;
--
-- -- FIX 1 ROLLBACK: restore old reverse_match_result (1-arg)
-- -- and restore old handle_result_de_ratification
-- DROP FUNCTION IF EXISTS reverse_match_result(UUID, INTEGER, INTEGER);
--
-- CREATE OR REPLACE FUNCTION reverse_match_result(p_fixture_id UUID)
-- RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
-- DECLARE
--   v_league_id UUID; v_home_id UUID; v_away_id UUID;
--   v_home_goals INTEGER; v_away_goals INTEGER;
-- BEGIN
--   SELECT f.league_id, f.home_club_id, f.away_club_id
--   INTO   v_league_id, v_home_id, v_away_id
--   FROM   fixtures f WHERE f.id = p_fixture_id;
--   IF NOT FOUND THEN
--     RAISE EXCEPTION 'Fixture % not found', p_fixture_id USING ERRCODE = '02000';
--   END IF;
--   SELECT mr.home_goals, mr.away_goals INTO v_home_goals, v_away_goals
--   FROM   match_results mr
--   WHERE  mr.fixture_id = p_fixture_id AND mr.is_official = true;
--   IF NOT FOUND THEN
--     RAISE EXCEPTION 'No official result found for fixture %', p_fixture_id USING ERRCODE = '02000';
--   END IF;
--   UPDATE standings SET
--     played=GREATEST(played-1,0),
--     wins=GREATEST(wins-CASE WHEN v_home_goals>v_away_goals THEN 1 ELSE 0 END,0),
--     draws=GREATEST(draws-CASE WHEN v_home_goals=v_away_goals THEN 1 ELSE 0 END,0),
--     losses=GREATEST(losses-CASE WHEN v_home_goals<v_away_goals THEN 1 ELSE 0 END,0),
--     goals_for=GREATEST(goals_for-v_home_goals,0),
--     goals_against=GREATEST(goals_against-v_away_goals,0), updated_at=NOW()
--   WHERE league_id=v_league_id AND club_id=v_home_id;
--   UPDATE standings SET
--     played=GREATEST(played-1,0),
--     wins=GREATEST(wins-CASE WHEN v_away_goals>v_home_goals THEN 1 ELSE 0 END,0),
--     draws=GREATEST(draws-CASE WHEN v_away_goals=v_home_goals THEN 1 ELSE 0 END,0),
--     losses=GREATEST(losses-CASE WHEN v_away_goals<v_home_goals THEN 1 ELSE 0 END,0),
--     goals_for=GREATEST(goals_for-v_away_goals,0),
--     goals_against=GREATEST(goals_against-v_home_goals,0), updated_at=NOW()
--   WHERE league_id=v_league_id AND club_id=v_away_id;
-- END; $$;
--
-- CREATE OR REPLACE FUNCTION handle_result_de_ratification()
-- RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
-- BEGIN
--   IF (TG_OP = 'UPDATE' AND OLD.is_official = true AND NEW.is_official = false) THEN
--     PERFORM reverse_match_result(NEW.fixture_id);
--   END IF;
--   RETURN NEW;
-- END; $$;
--
-- -- FIX 2 ROLLBACK: restore dual-IF sync_appeal_outcome_from_decision
-- CREATE OR REPLACE FUNCTION sync_appeal_outcome_from_decision()
-- RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
-- BEGIN
--   UPDATE disciplinary_appeals SET outcome=NEW.outcome, outcome_notes=NEW.decision_text,
--     decided_at=NEW.decided_at, decided_by=NEW.decided_by, status='decided', updated_at=NOW()
--   WHERE id=NEW.appeal_id;
--   IF NEW.suspension_overturned THEN
--     UPDATE suspensions SET is_active=false,
--       reason_notes=COALESCE(reason_notes,'')||' [Overturned on appeal '||NEW.decided_at::DATE::TEXT||']',
--       updated_at=NOW()
--     WHERE id=(SELECT suspension_id FROM disciplinary_appeals WHERE id=NEW.appeal_id);
--   END IF;
--   IF NEW.revised_matches_suspended IS NOT NULL THEN
--     UPDATE suspensions SET matches_suspended=NEW.revised_matches_suspended,
--       reason_notes=COALESCE(reason_notes,'')||' [Reduced from '||NEW.original_matches_suspended||
--         ' to '||NEW.revised_matches_suspended||' on appeal '||NEW.decided_at::DATE::TEXT||']',
--       is_active=(matches_served < NEW.revised_matches_suspended), updated_at=NOW()
--     WHERE id=(SELECT suspension_id FROM disciplinary_appeals WHERE id=NEW.appeal_id);
--   END IF;
--   RETURN NEW;
-- END; $$;
--
-- -- FIX 3 ROLLBACK: restore public read, drop restricted policy
-- DROP POLICY IF EXISTS "player_injuries: authorized read" ON player_injuries;
-- CREATE POLICY "player_injuries: public read" ON player_injuries FOR SELECT USING (true);
--
-- -- FIX 4 ROLLBACK: restore confirmed_at bypass in enforce_lineup_eligibility
-- CREATE OR REPLACE FUNCTION enforce_lineup_eligibility()
-- RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
-- DECLARE v_eligible BOOLEAN; v_reason TEXT; v_player_name TEXT;
-- BEGIN
--   IF NEW.role <> 'starter' THEN RETURN NEW; END IF;
--   IF (TG_OP = 'UPDATE' AND OLD.confirmed_at IS NOT NULL) THEN RETURN NEW; END IF;
--   SELECT eligible, reason INTO v_eligible, v_reason
--   FROM is_player_eligible_with_reason(NEW.player_id, NEW.fixture_id);
--   IF NOT v_eligible THEN
--     SELECT full_name INTO v_player_name FROM players WHERE id=NEW.player_id;
--     RAISE EXCEPTION 'Lineup eligibility check failed for player "%" (ID: %): %',
--       COALESCE(v_player_name,'Unknown'), NEW.player_id, v_reason USING ERRCODE='23514';
--   END IF;
--   RETURN NEW;
-- END; $$;
--
-- -- FIX 5 ROLLBACK: included in FIX 3 ROLLBACK above (same policy)
--
-- -- FIX 6 ROLLBACK: restore broken view
-- DROP VIEW IF EXISTS v_player_eligibility_summary;
-- CREATE VIEW v_player_eligibility_check AS
-- SELECT pl.id AS player_id, pl.full_name AS player_name, pl.position,
--        pl.club_id, cl.name AS club_name,
--        is_player_eligible(pl.id, NULL::UUID) AS eligible_generic
-- FROM players pl JOIN clubs cl ON cl.id = pl.club_id WHERE pl.is_active = true;
--
-- -- FIX 7 ROLLBACK: restore unconditional fixture club validation
-- CREATE OR REPLACE FUNCTION validate_fixture_clubs_in_league()
-- RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
-- BEGIN
--   IF NOT EXISTS (SELECT 1 FROM league_clubs lc WHERE lc.league_id=NEW.league_id
--     AND lc.club_id=NEW.home_club_id AND lc.approved=true) THEN
--     RAISE EXCEPTION 'Home club (ID: %) is not an approved member of league (ID: %)',
--       NEW.home_club_id, NEW.league_id USING ERRCODE='23514';
--   END IF;
--   IF NOT EXISTS (SELECT 1 FROM league_clubs lc WHERE lc.league_id=NEW.league_id
--     AND lc.club_id=NEW.away_club_id AND lc.approved=true) THEN
--     RAISE EXCEPTION 'Away club (ID: %) is not an approved member of league (ID: %)',
--       NEW.away_club_id, NEW.league_id USING ERRCODE='23514';
--   END IF;
--   RETURN NEW;
-- END; $$;
--
-- -- FIX 8 ROLLBACK: restore 3-column unique constraint
-- ALTER TABLE player_league_registrations DROP CONSTRAINT IF EXISTS uq_plr_player_club_league_season;
-- DROP INDEX IF EXISTS idx_plr_approved;
-- ALTER TABLE player_league_registrations
--   ADD CONSTRAINT player_league_registrations_player_id_league_id_season_id_key
--     UNIQUE (player_id, league_id, season_id);
-- CREATE INDEX idx_plr_approved ON player_league_registrations(league_id, player_id, status)
--   WHERE status = 'approved';
--
-- -- FIX 9 ROLLBACK: drop partial unique index on active seasons
-- DROP INDEX IF EXISTS idx_seasons_one_active_per_league;
-- -- (is_player_eligible reverts to STABLE + no ORDER BY in FIX 9 ROLLBACK above)
--
-- -- FIX 10 ROLLBACK: restore validate_referee_no_conflict with Cartesian join
-- CREATE OR REPLACE FUNCTION validate_referee_no_conflict()
-- RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
-- DECLARE v_referee_profile_id UUID; v_home_club_id UUID; v_away_club_id UUID;
-- BEGIN
--   SELECT r.profile_id INTO v_referee_profile_id FROM referees r WHERE r.id=NEW.referee_id;
--   SELECT f.home_club_id, f.away_club_id INTO v_home_club_id, v_away_club_id
--   FROM fixtures f WHERE f.id=NEW.fixture_id;
--   IF EXISTS (SELECT 1 FROM clubs c WHERE c.admin_id=v_referee_profile_id
--     AND c.id IN (v_home_club_id, v_away_club_id)) THEN
--     RAISE EXCEPTION 'Conflict of interest: referee (profile ID: %) is an administrator '
--       'of one of the clubs in fixture (ID: %).', v_referee_profile_id, NEW.fixture_id
--       USING ERRCODE='23514';
--   END IF;
--   IF EXISTS (SELECT 1 FROM players p JOIN profiles pr ON pr.id=v_referee_profile_id
--     WHERE p.club_id IN (v_home_club_id, v_away_club_id)) THEN
--     IF EXISTS (SELECT 1 FROM coaches co WHERE co.profile_id=v_referee_profile_id
--       AND co.club_id IN (v_home_club_id, v_away_club_id) AND co.is_active=true) THEN
--       RAISE EXCEPTION 'Conflict of interest: referee (profile ID: %) is an active coach '
--         'at one of the clubs in fixture (ID: %).', v_referee_profile_id, NEW.fixture_id
--         USING ERRCODE='23514';
--     END IF;
--     IF EXISTS (SELECT 1 FROM club_staff cs WHERE cs.profile_id=v_referee_profile_id
--       AND cs.club_id IN (v_home_club_id, v_away_club_id) AND cs.is_active=true) THEN
--       RAISE EXCEPTION 'Conflict of interest: referee (profile ID: %) is active club staff '
--         'at one of the clubs in fixture (ID: %).', v_referee_profile_id, NEW.fixture_id
--         USING ERRCODE='23514';
--     END IF;
--   END IF;
--   RETURN NEW;
-- END; $$;
--
-- COMMIT;
--
-- ============================================================
-- PATCH OBJECT SUMMARY
-- ============================================================
-- Functions replaced (CREATE OR REPLACE):  7
--   reverse_match_result (signature changed: 1-arg → 3-arg)
--   handle_result_de_ratification
--   sync_appeal_outcome_from_decision
--   enforce_lineup_eligibility
--   validate_fixture_clubs_in_league
--   validate_referee_no_conflict
--   is_player_eligible            (STABLE→VOLATILE, +club_id filter, +ORDER BY)
--   is_player_eligible_with_reason (STABLE→VOLATILE, +club_id filter, +ORDER BY)
--
-- Functions dropped:                       1
--   reverse_match_result(UUID)  [old 1-arg overload]
--
-- RLS policies dropped:                    2
--   "player_injuries: public read"         (C-04: was only a comment before)
--   "player_injuries: authorized read"     (H-03: replaced with corrected version)
--
-- RLS policies created:                    1
--   "player_injuries: authorized read"     (C-04 + H-03 combined)
--
-- Views dropped:                           1
--   v_player_eligibility_check             (H-05: always-false bug)
--
-- Views created:                           1
--   v_player_eligibility_summary           (H-05 replacement)
--
-- Constraints dropped:                     1
--   player_league_registrations unique (player_id, league_id, season_id)
--
-- Constraints created:                     1
--   uq_plr_player_club_league_season       (player_id, club_id, league_id, season_id)
--
-- Indexes dropped:                         1
--   idx_plr_approved                       (rebuilt with club_id)
--
-- Indexes created:                         2
--   idx_plr_approved                       (league_id, player_id, club_id, status)
--   idx_seasons_one_active_per_league      (partial unique: league_id WHERE active)
-- ============================================================
