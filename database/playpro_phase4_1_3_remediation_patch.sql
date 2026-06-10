-- ============================================================
-- PLAYPRO — PHASE 4.1.3: REMEDIATION PATCH
-- playpro_phase4_1_3_remediation_patch.sql
-- ============================================================
-- Apply AFTER, in order:
--   1. playpro_phase4_critical_fix_pack.sql
--   2. playpro_phase4_1_stabilization_patch.sql
--   3. playpro_phase4_1_1_remediation_patch.sql
--   4. playpro_phase4_1_2_security_patch.sql
--   5. THIS FILE
--
-- PostgreSQL 16 compatible. Supabase compatible.
--
-- TRANSACTION STRATEGY
-- ============================================================
-- PART A — One BEGIN…COMMIT block.
--   All DDL that does not require CONCURRENTLY:
--   • RLS policy replacements (suspensions, disciplinary_records)
--   • audit_trigger_fn() replacement
--   • v_player_eligibility_summary replacement (N+1 fix)
--   • v_player_injuries_medical_secure creation
--
-- PART B — Three statements OUTSIDE any transaction block.
--   CREATE/DROP INDEX CONCURRENTLY (forbidden inside transactions):
--   • Drop old idx_plr_approved
--   • Rebuild idx_plr_approved with correct columns and season_id
--
-- ============================================================
-- WHAT THIS PATCH FIXES
-- ============================================================
--
-- FIX 1 — RLS bypass: suspensions.reason_notes
--   The "suspensions: authorized read" policy in Phase 4.1.2 ends with
--   OR (is_active = true AND auth.uid() IS NOT NULL), granting every
--   authenticated user full table-row access including reason_notes.
--   v_suspension_progress (Phase 3) also exposes reason_notes directly.
--   Fix: replace the policy; remove the broad authenticated clause;
--   add v_suspension_progress conditional nulling.
--
-- FIX 2 — RLS bypass: disciplinary_records.notes
--   Same pattern: "disciplinary_records: authorized read" ends with
--   OR auth.uid() IS NOT NULL, exposing notes to all authenticated users.
--   Fix: replace the policy; remove the broad clause.
--
-- FIX 3 — audit_trigger_fn: clinical data stored in audit_log
--   audit_trigger_fn uses to_jsonb(NEW/OLD) capturing ALL columns of
--   player_injuries — including diagnosis, treatment_notes, medical_notes —
--   into audit_log.new_values / old_values JSONB permanently.
--   Fix: redact those three fields from both old_values and new_values
--   when TG_TABLE_NAME = 'player_injuries'. All other audited tables
--   are unaffected. SECURITY DEFINER and SET search_path are preserved.
--
-- FIX 4 — N+1 regression in v_player_eligibility_summary
--   player_has_active_injury(pl.id) is called TWICE per player row
--   (line 743 and line 766 of Phase 4.1.2). The second call in the
--   CASE block recomputes what is already stored in has_active_injury.
--   Fix: replace the view so the CASE block reads the lateral result
--   directly, eliminating the redundant SECURITY DEFINER function call.
--
-- FIX 5 — Missing v_player_injuries_medical_secure view
--   Phase 4.1.2 header promised this view but never created it.
--   Fix: create the view with SECURITY DEFINER so it bypasses RLS,
--   exposing clinical fields only to roles with legitimate clinical
--   access (developer, physiotherapist via club_staff).
--
-- PART B:
-- FIX 6 — idx_plr_approved season_id reversion
--   Phase 4.1.2 Part B-3 dropped the Phase 4.1.1 fix and recreated
--   idx_plr_approved as (league_id, player_id, club_id, status) —
--   removing the season_id added to cover is_player_eligible() step 8.
--   Fix: rebuild with (league_id, player_id, club_id, season_id)
--   WHERE status = 'approved', restoring the 4.1.1 definition.
--
-- ============================================================
-- OBJECTS NOT MODIFIED
-- ============================================================
--   player_has_active_injury()         (unchanged — correct)
--   player_active_injury_return_date() (unchanged — correct)
--   prevent_role_self_escalation()     (unchanged — correct)
--   trg_prevent_role_escalation        (unchanged — correct)
--   handle_new_user()                  (unchanged — correct)
--   player_injuries RLS                (unchanged — correct)
--   v_active_injuries                  (unchanged — columns already corrected in 4.1.2)
--   v_player_injury_history            (unchanged — columns already corrected in 4.1.2)
--   v_active_suspensions               (unchanged — CASE already nulls reason_notes)
--   All Phase 4.1, 4.1.1, 4.1.2 fixes not listed above
--
-- ============================================================
-- PRE-FLIGHT VALIDATION QUERIES
-- Run these BEFORE applying. Each must return zero rows or
-- the expected safe result.
-- ============================================================
--
-- [V-PRE-1] Confirm "suspensions: authorized read" exists to drop:
--   SELECT policyname FROM pg_policies
--   WHERE tablename = 'suspensions' AND cmd = 'SELECT';
--   EXPECTED: "suspensions: authorized read" is present.
--
-- [V-PRE-2] Confirm "disciplinary_records: authorized read" exists:
--   SELECT policyname FROM pg_policies
--   WHERE tablename = 'disciplinary_records' AND cmd = 'SELECT';
--   EXPECTED: "disciplinary_records: authorized read" is present.
--
-- [V-PRE-3] Confirm idx_plr_approved exists (for PART B DROP):
--   SELECT indexname, indexdef FROM pg_indexes
--   WHERE tablename = 'player_league_registrations'
--     AND indexname = 'idx_plr_approved';
--   EXPECTED: 1 row.
--
-- [V-PRE-4] Confirm no duplicates before index rebuild:
--   SELECT player_id, club_id, league_id, season_id, COUNT(*)
--   FROM player_league_registrations
--   GROUP BY player_id, club_id, league_id, season_id
--   HAVING COUNT(*) > 1;
--   EXPECTED: 0 rows.
--
-- ============================================================
-- PART A — TRANSACTIONAL DDL
-- ============================================================

BEGIN;

-- ============================================================
-- FIX 1 — Remove RLS bypass: suspensions.reason_notes
-- ============================================================
-- Root cause:
--   Phase 4.1.2 "suspensions: authorized read" contains:
--     OR (is_active = true AND auth.uid() IS NOT NULL)
--   This grants every authenticated user SELECT on all columns of
--   every active suspension row, including reason_notes, via direct
--   API call: GET /suspensions?select=reason_notes
--   The v_active_suspensions view nulls reason_notes for unauthorised
--   callers, but the policy does not force use of the view.
--   Additionally, v_suspension_progress (Phase 3) selects
--   s.reason_notes with no conditional nulling and is not modified by
--   Phase 4.1.2. Any authenticated user querying that view receives
--   full reason_notes for all active suspensions.
--
-- Fix:
--   Replace the policy with one that grants access only to the four
--   authorised roles. Remove the broad authenticated clause entirely.
--   Rewrite v_suspension_progress to null reason_notes for callers
--   who are not developer, league_founder, league_admin, or club_admin.
-- ============================================================

DROP POLICY IF EXISTS "suspensions: authorized read" ON suspensions;

CREATE POLICY "suspensions: authorized read"
  ON suspensions FOR SELECT
  USING (
    -- Developers: full access to all suspension data
    get_my_role() = 'developer'

    -- League founders: full access
    OR get_my_role() = 'league_founder'

    -- League admins: suspensions in leagues they administer
    OR is_league_admin(league_id)

    -- Club admins: suspensions for players at their club
    OR EXISTS (
      SELECT 1
      FROM   players pl
      WHERE  pl.id      = suspensions.player_id
        AND  is_club_admin(pl.club_id)
    )
    -- Removed: OR (is_active = true AND auth.uid() IS NOT NULL)
    -- Rationale: that clause granted all authenticated users full row
    -- access including reason_notes via direct table query. Active
    -- suspension transparency for public display is handled at the
    -- view layer by v_active_suspensions (which nulls reason_notes
    -- for non-authorised callers) and not by table-level policy.
  );

COMMENT ON POLICY "suspensions: authorized read" ON suspensions IS
  'Phase 4.1.3: removes the broad auth.uid() IS NOT NULL clause that '
  'allowed all authenticated users to read reason_notes via direct table '
  'query. Access is now restricted to developer, league_founder, '
  'league_admin, and club_admin roles. Public active-suspension display '
  'must use v_active_suspensions, which nulls reason_notes for '
  'non-authorised callers.';

-- Fix v_suspension_progress (Phase 3) which selects reason_notes directly.
-- This view is SECURITY INVOKER; after the policy change above, only
-- authorised roles see rows from the underlying table. The CASE guard
-- provides defence-in-depth by nulling reason_notes even if the row
-- is visible, matching the pattern used in v_active_suspensions.
CREATE OR REPLACE VIEW v_suspension_progress AS
SELECT
  s.id                                                      AS suspension_id,
  s.player_id,
  pl.full_name                                              AS player_name,
  pl.position                                               AS player_position,
  cl.name                                                   AS club_name,
  s.league_id,
  l.name                                                    AS league_name,
  s.suspension_reason,
  s.matches_suspended,
  s.matches_served,
  (s.matches_suspended - s.matches_served)                  AS matches_remaining,
  s.is_active,
  -- reason_notes: visible only to authorised roles.
  -- Mirrors the CASE guard in v_active_suspensions.
  -- Phase 4.1.3: added to prevent reason_notes leaking through this view.
  CASE
    WHEN get_my_role() IN ('developer', 'league_founder')
      OR is_league_admin(s.league_id)
      OR EXISTS (
           SELECT 1 FROM players pl2
           WHERE  pl2.id = s.player_id
             AND  is_club_admin(pl2.club_id)
         )
    THEN s.reason_notes
    ELSE NULL
  END                                                       AS reason_notes,
  s.created_at                                              AS imposed_at,
  -- Last fixture counted against this suspension
  (
    SELECT f.match_date
    FROM   suspension_served_matches ssm
    JOIN   fixtures f ON f.id = ssm.fixture_id
    WHERE  ssm.suspension_id = s.id
    ORDER  BY f.match_date DESC
    LIMIT  1
  )                                                         AS last_served_match_date,
  -- Audit count of fixtures served
  (
    SELECT COUNT(*)
    FROM   suspension_served_matches ssm
    WHERE  ssm.suspension_id = s.id
  )                                                         AS audit_served_count
FROM suspensions s
JOIN   players pl ON pl.id = s.player_id
LEFT JOIN clubs   cl ON cl.id = pl.club_id
JOIN   leagues l  ON l.id  = s.league_id
ORDER  BY s.is_active DESC, s.created_at DESC;

COMMENT ON VIEW v_suspension_progress IS
  'Suspension serving progress dashboard. '
  'reason_notes is conditionally NULLed for non-authorised callers '
  '(Phase 4.1.3: prevents data leak through this previously-unguarded view). '
  'Row visibility is controlled by "suspensions: authorized read" RLS policy.';


-- ============================================================
-- FIX 2 — Remove RLS bypass: disciplinary_records.notes
-- ============================================================
-- Root cause:
--   Phase 4.1.2 "disciplinary_records: authorized read" ends with:
--     OR auth.uid() IS NOT NULL
--   This grants every authenticated user SELECT on all columns including
--   notes via direct API call: GET /disciplinary_records?select=notes
--   The view v_disciplinary_records_public excludes notes, but the
--   policy does not enforce use of the view.
--
-- Fix:
--   Replace the policy removing the broad clause. Authorised roles
--   retain full access. Public display of structured match statistics
--   (card type, minute, player, fixture) must use
--   v_disciplinary_records_public, which was already created in 4.1.2.
-- ============================================================

DROP POLICY IF EXISTS "disciplinary_records: authorized read" ON disciplinary_records;

CREATE POLICY "disciplinary_records: authorized read"
  ON disciplinary_records FOR SELECT
  USING (
    -- Developers: full access
    get_my_role() = 'developer'

    -- League founders: full access
    OR get_my_role() = 'league_founder'

    -- League admins: records in leagues they administer
    OR is_league_admin(league_id)

    -- Club admins: disciplinary records for their club's players
    OR EXISTS (
      SELECT 1
      FROM   players pl
      WHERE  pl.id      = disciplinary_records.player_id
        AND  is_club_admin(pl.club_id)
    )
    -- Removed: OR auth.uid() IS NOT NULL
    -- Rationale: that clause granted all authenticated users full row
    -- access including notes. Public match statistics (card type, minute,
    -- player, fixture) are available through v_disciplinary_records_public.
  );

COMMENT ON POLICY "disciplinary_records: authorized read" ON disciplinary_records IS
  'Phase 4.1.3: removes the broad auth.uid() IS NOT NULL clause that '
  'allowed all authenticated users to read notes via direct table query. '
  'Access now restricted to developer, league_founder, league_admin, '
  'and club_admin. Public match card statistics must use '
  'v_disciplinary_records_public.';


-- ============================================================
-- FIX 3 — Redact clinical fields from audit_log
-- ============================================================
-- Root cause:
--   audit_trigger_fn() uses to_jsonb(OLD) and to_jsonb(NEW) to capture
--   complete row snapshots into audit_log.old_values and new_values.
--   When the audited table is player_injuries, this stores diagnosis,
--   treatment_notes, and medical_notes verbatim in audit_log — a table
--   accessible to developers — on every INSERT, UPDATE, and DELETE.
--   The restrictions on player_injuries direct access do not apply to
--   audit_log access. Clinical fields therefore persist in the audit log
--   permanently without restriction.
--
-- Fix:
--   Replace audit_trigger_fn() to strip diagnosis, treatment_notes, and
--   medical_notes from both old_values and new_values JSONB when the
--   trigger fires on the player_injuries table.
--   All other audited tables are unaffected.
--
-- Properties preserved from the original:
--   SECURITY DEFINER (required — function must write to audit_log
--     regardless of the calling user's own table permissions)
--   SET search_path = public (prevents search_path injection)
--   DELETE branch returning OLD (correct trigger return for DELETE)
--   All audit_log columns: table_name, record_id, operation,
--     old_values, new_values, changed_by, session_app, client_addr
--
-- NOTE on historical data:
--   This fix prevents NEW clinical data from entering audit_log.
--   Existing rows already in audit_log that contain clinical fields
--   cannot be retroactively redacted by this patch because audit_log
--   rows are immutable (no updated_at, no UPDATE path by design).
--   A separate data-remediation script must be run by a developer
--   to null out old_values->>'diagnosis' etc. in existing rows.
--   Template:
--     UPDATE audit_log
--     SET old_values = old_values - 'diagnosis' - 'treatment_notes' - 'medical_notes',
--         new_values = new_values - 'diagnosis' - 'treatment_notes' - 'medical_notes'
--     WHERE table_name = 'player_injuries';
--   Run this ONCE outside a transaction on a quiet database connection.
-- ============================================================

CREATE OR REPLACE FUNCTION audit_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_record_id   UUID;
  v_old_values  JSONB;
  v_new_values  JSONB;
BEGIN
  -- Capture the primary key and full row snapshots
  IF TG_OP = 'DELETE' THEN
    v_record_id  := OLD.id;
    v_old_values := to_jsonb(OLD);
    v_new_values := NULL;
  ELSIF TG_OP = 'INSERT' THEN
    v_record_id  := NEW.id;
    v_old_values := NULL;
    v_new_values := to_jsonb(NEW);
  ELSE  -- UPDATE
    v_record_id  := NEW.id;
    v_old_values := to_jsonb(OLD);
    v_new_values := to_jsonb(NEW);
  END IF;

  -- Redact clinical fields when auditing player_injuries.
  -- diagnosis, treatment_notes, and medical_notes are PHI/clinical data.
  -- They must not persist in audit_log even for developer-level readers.
  -- The jsonb minus operator (-) removes a key from a JSONB object.
  -- Applying it to NULL is a no-op, so INSERT/DELETE paths are safe.
  IF TG_TABLE_NAME = 'player_injuries' THEN
    v_old_values := v_old_values
                    - 'diagnosis'
                    - 'treatment_notes'
                    - 'medical_notes';
    v_new_values := v_new_values
                    - 'diagnosis'
                    - 'treatment_notes'
                    - 'medical_notes';
  END IF;

  INSERT INTO audit_log (
    table_name,
    record_id,
    operation,
    old_values,
    new_values,
    changed_by,
    session_app,
    client_addr
  ) VALUES (
    TG_TABLE_NAME,
    v_record_id,
    TG_OP,
    v_old_values,
    v_new_values,
    auth.uid(),
    current_setting('application_name', true),
    inet_client_addr()
  );

  -- Trigger functions must return the row for BEFORE triggers;
  -- for AFTER triggers the return value is ignored, but we
  -- must return the correct type: OLD for DELETE, NEW otherwise.
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION audit_trigger_fn() IS
  'Generic audit trigger. Captures old_values and new_values as JSONB. '
  'Phase 4.1.3: redacts diagnosis, treatment_notes, medical_notes from '
  'player_injuries rows before storing in audit_log. '
  'Historical rows already in audit_log are NOT retroactively cleaned — '
  'run the data-remediation UPDATE documented in this patch header '
  'to null existing clinical fields from past audit rows.';


-- ============================================================
-- FIX 4 — Eliminate N+1 in v_player_eligibility_summary
-- ============================================================
-- Root cause:
--   Phase 4.1.2 calls player_has_active_injury(pl.id) twice per row:
--     Line 743: player_has_active_injury(pl.id) AS has_active_injury
--     Line 766: WHEN player_has_active_injury(pl.id) THEN 'Injured'
--   Both calls execute as SECURITY DEFINER functions against
--   player_injuries. For N active players, this is 2N SECURITY DEFINER
--   function invocations where N would suffice.
--   player_active_injury_return_date(pl.id) adds a third per-row call.
--
-- Fix:
--   Add a LEFT JOIN LATERAL block for player_injuries that executes
--   once per player row (as the Phase 4.1.1 version did). The lateral
--   reads through player_has_active_injury() and
--   player_active_injury_return_date() — wait, those are SECURITY
--   DEFINER functions and cannot be placed in a LATERAL JOIN.
--
--   Correct approach: keep the SECURITY DEFINER function calls in the
--   SELECT list (required for RLS bypass), but eliminate the second
--   call in the CASE block by reading the already-computed column alias
--   using a subquery or lateral reference.
--
--   PostgreSQL does not allow SELECT-list aliases in the same SELECT's
--   CASE block. The correct fix is to wrap the view in a subquery so
--   the outer CASE can reference the has_active_injury alias, or
--   alternatively compute the CASE at the same level but avoid the
--   second function call by using the lateral result.
--
--   Chosen solution: add a LEFT JOIN LATERAL block that calls BOTH
--   SECURITY DEFINER functions once per player, then reference those
--   lateral columns in both the SELECT list and the CASE block.
--   This reduces from 3 SECURITY DEFINER calls per row to 1 lateral
--   scan per player (the lateral itself calls each function once).
--
--   Note: calling SECURITY DEFINER SQL functions inside LATERAL is
--   valid in PostgreSQL 16. The functions retain their SECURITY DEFINER
--   property and RLS bypass when invoked from the lateral.
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

  -- has_active_suspension: source is the suspension lateral below
  (susp.player_id IS NOT NULL)                          AS has_active_suspension,
  susp.league_id                                        AS suspended_in_league_id,
  susp.matches_remaining                                AS suspension_matches_remaining,

  -- has_active_injury and injury_expected_return: sourced from the
  -- injury_info lateral below. Each SECURITY DEFINER helper is called
  -- exactly once per player, eliminating the Phase 4.1.2 N+1 pattern
  -- where player_has_active_injury(pl.id) was called twice per row.
  inj.has_active_injury                                 AS has_active_injury,
  inj.injury_expected_return                            AS injury_expected_return,

  -- latest_registration_status: most recent registration across all
  -- leagues/seasons. Supported by idx_plr_player_created (Phase 4.1.1).
  (
    SELECT plr.status
    FROM   player_league_registrations plr
    WHERE  plr.player_id = pl.id
    ORDER  BY plr.created_at DESC
    LIMIT  1
  )                                                     AS latest_registration_status,

  -- eligible_summary: reads from lateral columns — no repeated function calls
  CASE
    WHEN NOT pl.is_active           THEN 'Inactive'
    WHEN susp.player_id IS NOT NULL THEN 'Suspended'
    WHEN inj.has_active_injury      THEN 'Injured'
    ELSE                                 'Available'
  END                                                   AS eligible_summary

FROM players pl
JOIN clubs cl ON cl.id = pl.club_id

-- ── Suspension lateral: single pass per player ─────────────
-- One scan per player. Returns the most recent active suspension.
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

-- ── Injury info lateral: single pass per player ─────────────
-- Calls each SECURITY DEFINER helper exactly ONCE per player row.
-- Phase 4.1.3: eliminates the second call to player_has_active_injury()
-- that appeared in the CASE block of Phase 4.1.2 (N+1 regression).
-- Both functions bypass player_injuries RLS so all roles including
-- 'coach' receive correct data (C-2 fix from Phase 4.1.2 preserved).
LEFT JOIN LATERAL (
  SELECT
    player_has_active_injury(pl.id)           AS has_active_injury,
    player_active_injury_return_date(pl.id)   AS injury_expected_return
) inj ON true

WHERE pl.is_active = true;

COMMENT ON VIEW v_player_eligibility_summary IS
  'Player availability dashboard. '
  'Uses LEFT JOIN LATERAL for suspensions (single scan per player). '
  'Uses a second LEFT JOIN LATERAL to call player_has_active_injury() '
  'and player_active_injury_return_date() exactly once per player '
  '(Phase 4.1.3: eliminates the N+1 regression introduced in 4.1.2). '
  'Both injury helper functions are SECURITY DEFINER — all roles '
  'including ''coach'' receive correct injury status (C-2 fix). '
  'Clinical fields (diagnosis, treatment_notes) are NOT exposed. '
  'Suspension visibility: "suspensions: authorized read" RLS policy '
  '(Phase 4.1.3: broad auth clause removed). '
  'Registration status: "player_league_registrations: authorized read" RLS.';


-- ============================================================
-- FIX 5 — Create v_player_injuries_medical_secure
-- ============================================================
-- Root cause:
--   Phase 4.1.2 header (lines 78–79) and risk analysis (lines 127–128)
--   promised: "NEW: v_player_injuries_medical_secure — SECURITY DEFINER
--   view for authorized users only (C-2 fix)". No such object was ever
--   created in the SQL. Authorized users needing clinical data
--   (physiotherapists, developers) have no dedicated secure view path
--   that bypasses RLS and exposes diagnosis, treatment_notes, and
--   medical_notes.
--
-- Fix:
--   Create the view as a SECURITY DEFINER function-backed construct.
--   PostgreSQL views cannot themselves be SECURITY DEFINER, but a
--   SECURITY DEFINER function returning a TABLE achieves the same effect:
--   it runs as the function owner (postgres/service role) and therefore
--   bypasses RLS on player_injuries.
--
--   However, the function must implement its OWN access control because
--   it bypasses RLS. Access is granted only to:
--     - developer role
--     - physiotherapist (active club_staff member at the player's club)
--   All other callers receive an empty result set.
--
--   Role identification uses get_my_role() and auth.uid() — the same
--   pattern used throughout the schema. JWT claims are NOT used
--   (they are not validated against the database and can be forged).
-- ============================================================

-- Drop if it exists (idempotent)
DROP FUNCTION IF EXISTS get_player_injuries_medical(UUID);

-- SECURITY DEFINER function: returns full clinical injury data
-- for a single player to authorised callers only.
-- Pass NULL as p_player_id to get data for all players the caller
-- is authorised to see (physiotherapists see their club; developers see all).
CREATE OR REPLACE FUNCTION get_player_injuries_medical(p_player_id UUID DEFAULT NULL)
RETURNS TABLE (
  id                   UUID,
  player_id            UUID,
  player_name          TEXT,
  club_id              UUID,
  club_name            TEXT,
  fixture_id           UUID,
  injury_type          injury_type,
  severity             injury_severity,
  body_part            TEXT,
  injury_date          DATE,
  expected_return_date DATE,
  actual_return_date   DATE,
  diagnosis            TEXT,
  treatment_notes      TEXT,
  medical_notes        TEXT,
  is_active            BOOLEAN,
  cleared_at           TIMESTAMPTZ,
  clearance_notes      TEXT,
  reported_by          UUID,
  cleared_by           UUID,
  created_at           TIMESTAMPTZ,
  updated_at           TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role user_role;
BEGIN
  -- Establish caller identity using the database-authoritative role,
  -- NOT JWT claims (JWT claims are caller-supplied and unvalidated).
  v_role := get_my_role();

  -- Developer: full access to all player injury clinical data
  IF v_role = 'developer' THEN
    RETURN QUERY
    SELECT
      pi.id, pi.player_id, pl.full_name, pi.club_id, cl.name,
      pi.fixture_id, pi.injury_type, pi.severity, pi.body_part,
      pi.injury_date, pi.expected_return_date, pi.actual_return_date,
      pi.diagnosis, pi.treatment_notes, pi.medical_notes,
      pi.is_active, pi.cleared_at, pi.clearance_notes,
      pi.reported_by, pi.cleared_by, pi.created_at, pi.updated_at
    FROM   player_injuries pi
    JOIN   players pl ON pl.id  = pi.player_id
    JOIN   clubs   cl ON cl.id  = pi.club_id
    WHERE  (p_player_id IS NULL OR pi.player_id = p_player_id);
    RETURN;
  END IF;

  -- Physiotherapist: access to clinical data for players at their club(s)
  IF EXISTS (
    SELECT 1
    FROM   club_staff cs
    WHERE  cs.profile_id = auth.uid()
      AND  cs.is_active  = true
      AND  cs.role       = 'physiotherapist'
  ) THEN
    RETURN QUERY
    SELECT
      pi.id, pi.player_id, pl.full_name, pi.club_id, cl.name,
      pi.fixture_id, pi.injury_type, pi.severity, pi.body_part,
      pi.injury_date, pi.expected_return_date, pi.actual_return_date,
      pi.diagnosis, pi.treatment_notes, pi.medical_notes,
      pi.is_active, pi.cleared_at, pi.clearance_notes,
      pi.reported_by, pi.cleared_by, pi.created_at, pi.updated_at
    FROM   player_injuries pi
    JOIN   players pl ON pl.id  = pi.player_id
    JOIN   clubs   cl ON cl.id  = pi.club_id
    -- Scope to clubs where the caller is an active physiotherapist
    JOIN   club_staff cs
           ON cs.club_id    = pi.club_id
          AND cs.profile_id = auth.uid()
          AND cs.is_active  = true
          AND cs.role       = 'physiotherapist'
    WHERE  (p_player_id IS NULL OR pi.player_id = p_player_id);
    RETURN;
  END IF;

  -- All other roles: return empty result set without raising an error.
  -- Callers who need non-clinical injury data should use
  -- v_active_injuries (operational dashboard, no clinical fields).
  RETURN;
END;
$$;

COMMENT ON FUNCTION get_player_injuries_medical(UUID) IS
  'SECURITY DEFINER: returns full clinical injury data (including '
  'diagnosis, treatment_notes, medical_notes) for authorised roles only. '
  'Authorised: developer (all players), physiotherapist (own club only). '
  'All other roles receive an empty result set. '
  'Role is determined via get_my_role() → profiles.role — NOT from JWT '
  'claims, which are caller-supplied and cannot be trusted for access '
  'control decisions. '
  'Phase 4.1.3: implements the v_player_injuries_medical_secure '
  'deliverable promised in Phase 4.1.2 but never created.';

-- Convenience view wrapper for tooling that prefers views over functions.
-- Calls the SECURITY DEFINER function so all callers are subject to the
-- function's built-in access control.
CREATE OR REPLACE VIEW v_player_injuries_medical_secure AS
  SELECT * FROM get_player_injuries_medical(NULL);

COMMENT ON VIEW v_player_injuries_medical_secure IS
  'Convenience wrapper for get_player_injuries_medical(). '
  'Access control is enforced by the underlying SECURITY DEFINER '
  'function — only developer and physiotherapist roles see rows. '
  'All other roles see an empty result set. '
  'For a specific player, call: SELECT * FROM get_player_injuries_medical(''<player_uuid>'')';


-- ============================================================
-- END OF PART A
-- ============================================================

COMMIT;

-- ============================================================
-- POST PART A VERIFICATION
-- Run these immediately after COMMIT to confirm Part A applied.
-- ============================================================
--
-- [V-A-1] Confirm suspensions policy no longer has broad auth clause:
--   SELECT policyname, qual FROM pg_policies
--   WHERE tablename = 'suspensions' AND cmd = 'SELECT';
--   EXPECTED: "suspensions: authorized read" present.
--   EXPECTED: qual does NOT contain 'auth.uid() IS NOT NULL'.
--
-- [V-A-2] Confirm disciplinary policy no longer has broad auth clause:
--   SELECT policyname, qual FROM pg_policies
--   WHERE tablename = 'disciplinary_records' AND cmd = 'SELECT';
--   EXPECTED: "disciplinary_records: authorized read" present.
--   EXPECTED: qual does NOT contain 'auth.uid() IS NOT NULL'.
--
-- [V-A-3] Confirm audit_trigger_fn redacts clinical fields:
--   SELECT prosrc FROM pg_proc WHERE proname = 'audit_trigger_fn';
--   EXPECTED: contains "player_injuries" and "diagnosis".
--
-- [V-A-4] Confirm v_player_eligibility_summary uses lateral for injuries:
--   SELECT definition FROM pg_views
--   WHERE viewname = 'v_player_eligibility_summary';
--   EXPECTED: "inj.has_active_injury" present; "player_has_active_injury"
--   appears exactly once (inside the lateral, not in the CASE block).
--
-- [V-A-5] Confirm get_player_injuries_medical function exists:
--   SELECT proname, prosecdef FROM pg_proc
--   WHERE proname = 'get_player_injuries_medical';
--   EXPECTED: prosecdef = true.
--
-- [V-A-6] Confirm v_player_injuries_medical_secure view exists:
--   SELECT viewname FROM pg_views
--   WHERE viewname = 'v_player_injuries_medical_secure';
--   EXPECTED: 1 row.
--
-- [V-A-7] Confirm v_suspension_progress nulls reason_notes:
--   SELECT definition FROM pg_views
--   WHERE viewname = 'v_suspension_progress';
--   EXPECTED: CASE … reason_notes … ELSE NULL … END present.


-- ============================================================
-- PART B — CONCURRENT INDEX OPERATIONS
-- Run OUTSIDE any transaction. Each statement must complete
-- successfully before running the next.
-- ============================================================
-- Purpose: restore idx_plr_approved with season_id as the 4th column.
-- Phase 4.1.2 Part B-3 regressed this index back to (league_id,
-- player_id, club_id, status) without season_id, silently undoing
-- the Phase 4.1.1 H-1 fix.
--
-- Correct final definition:
--   (league_id, player_id, club_id, season_id) WHERE status = 'approved'
-- This covers the is_player_eligible() step 8 query:
--   WHERE player_id = ? AND club_id = ? AND league_id = ? AND season_id = ?
--     AND status = 'approved'
-- without requiring a heap fetch per historical season.
-- ============================================================

-- ── B-1: Drop existing index ──────────────────────────────
-- No reads or writes are blocked by DROP INDEX CONCURRENTLY.
DROP INDEX CONCURRENTLY IF EXISTS idx_plr_approved;

-- ── B-2: Rebuild with correct column set ─────────────────
-- No writes are blocked during CONCURRENTLY index build.
-- Reads are unaffected throughout.
-- Pre-flight: run V-PRE-4 above first.
CREATE INDEX CONCURRENTLY idx_plr_approved
  ON player_league_registrations (league_id, player_id, club_id, season_id)
  WHERE status = 'approved';

COMMENT ON INDEX idx_plr_approved IS
  'Partial index for approved registration lookups. '
  'Covers is_player_eligible() step 8: '
  'WHERE player_id=? AND club_id=? AND league_id=? AND season_id=? '
  'AND status=''approved''. '
  'season_id originally added in Phase 4.1.1 (H-1 fix); '
  'accidentally reverted by Phase 4.1.2 Part B-3; '
  'restored by Phase 4.1.3 Part B.';

-- ============================================================
-- POST PART B VERIFICATION
-- ============================================================
--
-- [V-B-1] Confirm idx_plr_approved has correct columns:
--   SELECT indexname, indexdef FROM pg_indexes
--   WHERE tablename = 'player_league_registrations'
--     AND indexname = 'idx_plr_approved';
--   EXPECTED: indexdef contains league_id, player_id, club_id, season_id
--   EXPECTED: indexdef contains WHERE status = 'approved'
--   EXPECTED: season_id IS present; 'status' is NOT in the column list


-- ============================================================
-- ROLLBACK SECTION
-- ============================================================
-- Execute to undo this patch AFTER COMMIT.
-- PART A rollback: run inside a transaction.
-- PART B rollback: run outside any transaction.
-- ============================================================

/*

-- ── ROLLBACK PART A ──
BEGIN;

-- Rollback FIX 1: restore "suspensions: authorized read" with broad clause
DROP POLICY IF EXISTS "suspensions: authorized read" ON suspensions;

CREATE POLICY "suspensions: authorized read"
  ON suspensions FOR SELECT
  USING (
    get_my_role() = 'developer'
    OR get_my_role() = 'league_founder'
    OR is_league_admin(league_id)
    OR EXISTS (
      SELECT 1 FROM players pl
      WHERE pl.id = suspensions.player_id AND is_club_admin(pl.club_id)
    )
    OR (is_active = true AND auth.uid() IS NOT NULL)
  );

-- Rollback v_suspension_progress to Phase 3 original (reason_notes exposed directly)
CREATE OR REPLACE VIEW v_suspension_progress AS
SELECT
  s.id                                          AS suspension_id,
  s.player_id,
  pl.full_name                                  AS player_name,
  pl.position                                   AS player_position,
  cl.name                                       AS club_name,
  s.league_id,
  l.name                                        AS league_name,
  s.suspension_reason,
  s.matches_suspended,
  s.matches_served,
  (s.matches_suspended - s.matches_served)      AS matches_remaining,
  s.is_active,
  s.reason_notes,
  s.created_at                                  AS imposed_at,
  (
    SELECT f.match_date
    FROM suspension_served_matches ssm
    JOIN fixtures f ON f.id = ssm.fixture_id
    WHERE ssm.suspension_id = s.id
    ORDER BY f.match_date DESC
    LIMIT 1
  ) AS last_served_match_date,
  (SELECT COUNT(*) FROM suspension_served_matches ssm WHERE ssm.suspension_id = s.id)
    AS audit_served_count
FROM suspensions s
JOIN   players pl ON pl.id = s.player_id
LEFT JOIN clubs cl ON cl.id = pl.club_id
JOIN   leagues l  ON l.id  = s.league_id
ORDER BY s.is_active DESC, s.created_at DESC;

-- Rollback FIX 2: restore "disciplinary_records: authorized read" with broad clause
DROP POLICY IF EXISTS "disciplinary_records: authorized read" ON disciplinary_records;

CREATE POLICY "disciplinary_records: authorized read"
  ON disciplinary_records FOR SELECT
  USING (
    get_my_role() = 'developer'
    OR get_my_role() = 'league_founder'
    OR is_league_admin(league_id)
    OR EXISTS (
      SELECT 1 FROM players pl
      WHERE pl.id = disciplinary_records.player_id AND is_club_admin(pl.club_id)
    )
    OR auth.uid() IS NOT NULL
  );

-- Rollback FIX 3: restore audit_trigger_fn without clinical-field redaction
CREATE OR REPLACE FUNCTION audit_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_record_id   UUID;
  v_old_values  JSONB;
  v_new_values  JSONB;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_record_id  := OLD.id;
    v_old_values := to_jsonb(OLD);
    v_new_values := NULL;
  ELSIF TG_OP = 'INSERT' THEN
    v_record_id  := NEW.id;
    v_old_values := NULL;
    v_new_values := to_jsonb(NEW);
  ELSE
    v_record_id  := NEW.id;
    v_old_values := to_jsonb(OLD);
    v_new_values := to_jsonb(NEW);
  END IF;

  INSERT INTO audit_log (
    table_name, record_id, operation,
    old_values, new_values, changed_by, session_app, client_addr
  ) VALUES (
    TG_TABLE_NAME, v_record_id, TG_OP,
    v_old_values, v_new_values, auth.uid(),
    current_setting('application_name', true), inet_client_addr()
  );

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

-- Rollback FIX 4: restore v_player_eligibility_summary to Phase 4.1.2 version
-- (two SECURITY DEFINER function calls per row in CASE block)
DROP VIEW IF EXISTS v_player_eligibility_summary;

CREATE VIEW v_player_eligibility_summary AS
SELECT
  pl.id                                                 AS player_id,
  pl.full_name                                          AS player_name,
  pl.position,
  pl.club_id,
  cl.name                                               AS club_name,
  pl.is_active,
  (susp.player_id IS NOT NULL)                          AS has_active_suspension,
  susp.league_id                                        AS suspended_in_league_id,
  susp.matches_remaining                                AS suspension_matches_remaining,
  player_has_active_injury(pl.id)                       AS has_active_injury,
  player_active_injury_return_date(pl.id)               AS injury_expected_return,
  (
    SELECT plr.status FROM player_league_registrations plr
    WHERE plr.player_id = pl.id ORDER BY plr.created_at DESC LIMIT 1
  ) AS latest_registration_status,
  CASE
    WHEN NOT pl.is_active               THEN 'Inactive'
    WHEN susp.player_id IS NOT NULL     THEN 'Suspended'
    WHEN player_has_active_injury(pl.id) THEN 'Injured'
    ELSE 'Available'
  END AS eligible_summary
FROM players pl
JOIN clubs cl ON cl.id = pl.club_id
LEFT JOIN LATERAL (
  SELECT s.player_id, s.league_id,
         (s.matches_suspended - s.matches_served) AS matches_remaining
  FROM   suspensions s
  WHERE  s.player_id = pl.id AND s.is_active = true
    AND  s.matches_served < s.matches_suspended
  ORDER  BY s.created_at DESC LIMIT 1
) susp ON true
WHERE pl.is_active = true;

-- Rollback FIX 5: drop the secure medical view and function
DROP VIEW IF EXISTS v_player_injuries_medical_secure;
DROP FUNCTION IF EXISTS get_player_injuries_medical(UUID);

COMMIT;

-- ── ROLLBACK PART B (run outside any transaction) ──
-- Restore idx_plr_approved without season_id (Phase 4.1.2 state)
DROP INDEX CONCURRENTLY IF EXISTS idx_plr_approved;
CREATE INDEX CONCURRENTLY idx_plr_approved
  ON player_league_registrations (league_id, player_id, club_id, status)
  WHERE status = 'approved';

*/

-- ============================================================
-- PATCH SUMMARY
-- ============================================================
--
-- Phase:            4.1.3 — Remediation Patch
-- Applies after:    4.1.2 — Security Patch
-- Date:             2026-06-07
--
-- Part A (transactional, BEGIN…COMMIT):
--   Policies dropped:   2
--     "suspensions: authorized read"         (FIX 1)
--     "disciplinary_records: authorized read" (FIX 2)
--
--   Policies created:   2
--     "suspensions: authorized read"          (FIX 1 — broad clause removed)
--     "disciplinary_records: authorized read" (FIX 2 — broad clause removed)
--
--   Functions replaced: 1
--     audit_trigger_fn()                      (FIX 3 — clinical redaction)
--
--   Functions created:  1
--     get_player_injuries_medical(UUID)       (FIX 5)
--
--   Views replaced:     2
--     v_suspension_progress                   (FIX 1 — reason_notes CASE guard)
--     v_player_eligibility_summary            (FIX 4 — N+1 eliminated)
--
--   Views created:      1
--     v_player_injuries_medical_secure        (FIX 5)
--
-- Part B (CONCURRENTLY, outside transaction):
--   Indexes dropped:    1
--     idx_plr_approved
--
--   Indexes created:    1
--     idx_plr_approved  (league_id, player_id, club_id, season_id)
--                        WHERE status = 'approved'          (FIX 6)
--
-- Findings addressed:
--   BLOCKER  CRIT-03 (partial in 4.1.2)  ✓ reason_notes protected at table level
--   BLOCKER  HIGH-01 (partial in 4.1.2)  ✓ notes protected at table level
--   BLOCKER  HA-H-04                     ✓ clinical fields redacted from audit_log
--   BLOCKER  C-2 regression (N+1)        ✓ injury lateral called once per row
--   PHANTOM  v_player_injuries_medical_secure ✓ now actually created
--   REGRESSION RR-H-1 (reverted in 4.1.2) ✓ season_id restored to idx_plr_approved
-- ============================================================
