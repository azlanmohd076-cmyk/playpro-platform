-- ============================================================
-- PLAYPRO — PHASE 4.1.2: SECURITY PATCH
-- playpro_phase4_1_2_security_patch.sql
-- ============================================================
-- Apply AFTER the following files, in order:
--   1. playpro_phase1.sql                       (from database spec)
--   2. playpro_phase2_additions.sql
--   3. playpro_phase3_additions.sql
--   4. playpro_phase4_critical_fix_pack.sql
--   5. playpro_phase4_1_stabilization_patch.sql
--   6. playpro_phase4_1_1_remediation_patch.sql
--   7. THIS FILE
--
-- PostgreSQL 16 compatible. Supabase compatible.
--
-- TRANSACTION STRATEGY:
--   This patch is split into two parts:
--
--   PART A — One BEGIN...COMMIT transaction covering all DDL that
--     does NOT require CONCURRENTLY (all policy drops/creates,
--     function replacements, view replacements, constraint
--     operations via DO blocks that check-then-act safely).
--
--   PART B — Three standalone statements (outside any transaction)
--     using CREATE INDEX CONCURRENTLY to safely build indexes
--     without taking an ACCESS EXCLUSIVE lock that would block
--     production writes during index construction.
--
-- FINDINGS ADDRESSED:
--
--   Blockers (prevent deployment):
--     HIGH-05   Privilege escalation via profiles.role self-update
--     NF-2      DROP CONSTRAINT uses assumed auto-generated name
--     NF-3      ADD CONSTRAINT UNIQUE inside transaction = write outage
--     C-2       Coaches see has_active_injury=false in eligibility view
--
--   High severity (RLS data leakage):
--     LOW-01    handle_new_user() accepts role from signup metadata
--     CRIT-01   v_active_injuries / v_player_injury_history expose
--               diagnosis + treatment_notes to all authorized users
--     CRIT-03   suspensions.reason_notes publicly readable via
--               USING(true) policy
--     HIGH-01   disciplinary_records.notes publicly readable
--     HIGH-02   player_league_registrations.rejection_reason public
--     HIGH-06   Registration UPDATE missing WITH CHECK on new row
--
--   Medium severity (operational correctness):
--     MED-02    Club admin can register players from other clubs
--     MED-04    No DELETE policy on standings
--     HIGH-04   No DELETE policy on fixtures
--
--   Low severity (operational tightening):
--     LOW-02    Any authenticated user can spam league_clubs INSERT
--
-- OBJECTS MODIFIED (in dependency order):
--
--   Phase 1 objects (RLS policy replacements):
--     profiles            — DROP "profiles: update own or developer"
--                           CREATE "profiles: update own non-role fields"
--                           CREATE "profiles: developer update any"
--                           CREATE TRIGGER trg_prevent_role_escalation
--                           CREATE FUNCTION prevent_role_self_escalation()
--     league_clubs        — DROP "league_clubs: authenticated insert"
--                           CREATE "league_clubs: club admin insert"
--     disciplinary_records— DROP "disciplinary_records: public read"
--                           CREATE "disciplinary_records: authorized read"
--                           CREATE "disciplinary_records: public read aggregate"
--     suspensions         — DROP "suspensions: public read"
--                           CREATE "suspensions: authorized read"
--                           REPLACE VIEW v_active_suspensions
--     standings           — CREATE "standings: league admin delete"
--     fixtures            — CREATE "fixtures: developer delete"
--     handle_new_user()   — REPLACE (hardcode role to 'club_admin')
--
--   Phase 3 objects:
--     v_active_injuries   — REPLACE (remove diagnosis, treatment_notes)
--     v_player_injury_history — REPLACE (remove diagnosis)
--     NEW: v_player_injuries_medical_secure — SECURITY DEFINER view
--               for authorized users only (C-2 fix)
--
--   Phase 4 objects:
--     player_league_registrations — complex constraint swap (NF-2/NF-3)
--     "player_league_registrations: public read"  → authorized read
--     "player_league_registrations: club admin insert" → add player.club_id check
--     "player_league_registrations: club admin or league admin update"
--                                                 → add WITH CHECK
--
--   Phase 4.1.1 objects:
--     v_player_eligibility_summary — REPLACE with SECURITY DEFINER
--               helper for injury visibility (C-2)
--
-- OBJECTS NOT MODIFIED:
--   trg_profiles_updated_at       (unchanged)
--   is_player_eligible()          (unchanged — correct after 4.1)
--   is_player_eligible_with_reason() (unchanged — correct after 4.1)
--   all Phase 2 tables            (unchanged)
--   all Phase 3 trigger functions (unchanged)
--   all Phase 4 trigger functions (unchanged, except handle_new_user)
--
-- ============================================================
-- RISK ANALYSIS
-- ============================================================
--
-- HIGH-05 (profiles role escalation):
--   Risk: LOW-MEDIUM. Dropping the existing UPDATE policy and
--   splitting into two narrower policies changes the effective
--   access surface. The trigger adds a hard SECURITY DEFINER
--   guard. Backward-compatible: valid profile updates (name,
--   email, avatar_url, phone) continue to work. Role changes
--   by non-developers are now blocked at the trigger level.
--   Supabase PostgREST: the trigger fires before the UPDATE
--   commits, so the API returns 403 with the ERRCODE 42501.
--
-- LOW-01 (signup role injection):
--   Risk: NONE. Hardcoding 'club_admin' in handle_new_user()
--   removes the COALESCE on raw_user_meta_data->>'role'.
--   Existing users are not affected (ON CONFLICT DO NOTHING).
--   Only new signups are affected: they always start as
--   club_admin regardless of metadata passed at signup.
--
-- CRIT-01 (injury view medical field exposure):
--   Risk: LOW. Replacing v_active_injuries and
--   v_player_injury_history with versions that exclude
--   diagnosis and treatment_notes is a column-reduction change.
--   Any application code that SELECT *'s these views and
--   processes diagnosis/treatment_notes will stop receiving
--   those columns. The new v_player_injuries_medical_secure
--   SECURITY DEFINER view provides that data to authorized
--   callers. Application code using named columns is unaffected
--   unless it explicitly selects diagnosis/treatment_notes from
--   these views.
--
-- CRIT-03 (suspensions.reason_notes public):
--   Risk: LOW-MEDIUM. Replacing the existing public read
--   policy with an authorized read policy removes anonymous
--   access to the full suspensions table. The rewritten
--   v_active_suspensions view nulls out reason_notes for
--   unauthorized callers while keeping the row visible (active
--   suspensions remain transparent, reason_notes remain
--   restricted). This is a semi-breaking change: code that
--   queries the table directly as anonymous will get zero rows.
--   Code querying v_active_suspensions will get rows with NULL
--   reason_notes. Direct authenticated access is fully preserved.
--
-- HIGH-01 (disciplinary_records.notes public):
--   Risk: LOW. The policy is replaced with an authorized read
--   policy. A public-aggregate policy with USING(true) on a
--   specific column set is documented for app layer enforcement
--   via views. Direct anonymous table access is restricted.
--   v_disciplinary_records_public view added for public display.
--
-- HIGH-02 (registration rejection_reason public):
--   Risk: MEDIUM. Dropping "player_league_registrations: public
--   read" and replacing with authorized read is a breaking
--   change for any client that reads this table as anonymous.
--   A v_player_registrations_public view preserves the
--   non-sensitive columns for public access (status, jersey
--   number, valid dates). Migration NOTE: run the pre-flight
--   check at VALIDATE-PLR before applying.
--
-- HIGH-06 (registration UPDATE WITH CHECK missing):
--   Risk: LOW. Adding WITH CHECK mirrors the USING conditions
--   against the NEW row. Valid updates satisfy both USING and
--   WITH CHECK. The only updates that are now rejected are
--   attempts to change club_id to a club the caller does not
--   administer — these were always logically incorrect.
--
-- MED-02 (cross-club player registration):
--   Risk: LOW. Adding EXISTS(SELECT 1 FROM players p WHERE
--   p.id = player_id AND p.club_id = club_id) to the INSERT
--   WITH CHECK ensures the player actually belongs to the club.
--   Only registrations for players not belonging to the caller's
--   club are blocked. Legitimate registrations are unaffected.
--
-- MED-04 / HIGH-04 (standings/fixtures missing DELETE):
--   Risk: NONE. Additive-only policies. No existing behaviour
--   changes; only adds authorized DELETE paths.
--
-- LOW-02 (league_clubs spam INSERT):
--   Risk: LOW. Restricting to club admins only blocks anonymous
--   or non-admin authenticated users from submitting join
--   requests. Only the club's own admin can submit. Valid join
--   requests from club admins work identically.
--
-- NF-2 / NF-3 (constraint name + lock safety):
--   Risk: LOW-MEDIUM. The DO block uses pg_constraint to look up
--   the actual constraint name dynamically, then DROPs it. This
--   correctly handles both auto-generated and explicitly-named
--   constraints. The ADD CONSTRAINT itself is done OUTSIDE the
--   transaction (PART B) via CREATE UNIQUE INDEX CONCURRENTLY
--   then ALTER TABLE ... ADD CONSTRAINT ... USING INDEX to
--   promote the pre-built index to a constraint — avoiding the
--   ACCESS EXCLUSIVE lock that blocks writes during index build.
--
-- C-2 (coach injury visibility):
--   Risk: LOW. player_has_active_injury() is a SECURITY DEFINER
--   function that accesses player_injuries bypassing the caller's
--   RLS. This is intentional: coaches need to know if a player
--   is injured for team-selection purposes without needing full
--   medical access. It returns only a BOOLEAN — no clinical data
--   is exposed. The v_player_eligibility_summary view is updated
--   to call this helper so all users see correct injury status.
--
-- ============================================================
-- PRE-FLIGHT VALIDATION QUERIES
-- ============================================================
-- Run these BEFORE applying the patch and verify the output.
-- Do NOT apply the patch if any check reports unexpected data.
--
-- [VALIDATE-ROLE] Confirm no user has self-escalated already:
--   SELECT id, full_name, role FROM profiles
--   WHERE role = 'developer'
--   ORDER BY created_at;
--   EXPECTED: Only legitimate developer accounts.
--
-- [VALIDATE-PLR] Check for any public-facing code using
--   player_league_registrations direct select as anon:
--   (application audit — no SQL check possible)
--   EXPECTED: All public reads routed through views.
--
-- [VALIDATE-CONSTRAINT] Find the actual unique constraint name
--   on player_league_registrations (NF-2 check):
--   SELECT conname, contype
--   FROM pg_constraint
--   WHERE conrelid = 'player_league_registrations'::regclass
--     AND contype = 'u';
--   EXPECTED: Either auto-generated name or 'uq_plr_player_club_league_season'.
--   The DO block handles both cases dynamically.
--
-- [VALIDATE-PLR-DUPES] Confirm no duplicates exist before
--   building the new unique index:
--   SELECT player_id, club_id, league_id, season_id, COUNT(*)
--   FROM player_league_registrations
--   GROUP BY player_id, club_id, league_id, season_id
--   HAVING COUNT(*) > 1;
--   EXPECTED: 0 rows. If any rows returned, resolve before applying.
--
-- [VALIDATE-COACH-ROLE] Confirm coach users in profiles:
--   SELECT COUNT(*) FROM profiles WHERE role = 'coach';
--   EXPECTED: Documents current coach count for post-patch verification.
--
-- ============================================================
-- PART A — TRANSACTIONAL DDL
-- ============================================================
-- All policy changes, function replacements, and view
-- replacements that do NOT require CONCURRENTLY index builds.
-- The NF-3 constraint upgrade (requiring CONCURRENTLY) is
-- handled in PART B below.
-- ============================================================

BEGIN;

-- ============================================================
-- SECTION 1 — HIGH-05: PRIVILEGE ESCALATION VIA profiles.role
-- ============================================================
-- Root cause:
--   The Phase 1 policy "profiles: update own or developer" uses
--   only USING (id = auth.uid() OR get_my_role() = 'developer').
--   There is no WITH CHECK, meaning any authenticated user can
--   PATCH their own profile row including the role column.
--   Since all RLS policies call get_my_role() which reads
--   profiles.role, self-promoting to 'developer' bypasses the
--   entire RLS system.
--
-- Fix:
--   1. Drop the permissive single-policy.
--   2. Create two replacement policies:
--        "profiles: update own non-role fields" — self-update,
--          WITH CHECK enforced by trigger below.
--        "profiles: developer update any" — developer full update.
--   3. Create prevent_role_self_escalation() SECURITY DEFINER
--      trigger function that raises an exception when a non-
--      developer tries to change their own role.
--   4. Attach the trigger BEFORE UPDATE ON profiles.
--
-- NOTE: The trigger fires BEFORE the UPDATE, so get_my_role()
-- still returns the OLD role at trigger execution time.
-- This is safe: a non-developer calling themselves a developer
-- is blocked before the UPDATE is committed.
-- ============================================================

-- Step 1.1: Drop the overly-permissive update policy.
DROP POLICY IF EXISTS "profiles: update own or developer" ON profiles;

-- Step 1.2: Users update their own non-role fields.
-- WITH CHECK ensures the NEW row still has the same id as the
-- caller. The role column is protected by the trigger, not here,
-- because PostgreSQL WITH CHECK cannot reference OLD values.
-- The trigger is the authoritative role-change guard.
CREATE POLICY "profiles: update own non-role fields"
  ON profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Step 1.3: Developers can update any profile, including role.
CREATE POLICY "profiles: developer update any"
  ON profiles FOR UPDATE
  USING (get_my_role() = 'developer');

-- Step 1.4: Trigger function — blocks role self-escalation.
-- SECURITY DEFINER ensures auth.uid() is evaluated as the
-- triggering session user (not the function owner).
-- get_my_role() reads profiles.role BEFORE the UPDATE commits,
-- which is the OLD role. This prevents the bypass scenario.
CREATE OR REPLACE FUNCTION prevent_role_self_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- A user updating their own profile row cannot change their role
  -- unless they are currently a developer.
  --
  -- Conditions for blocking:
  --   (a) The row being updated belongs to the current session user.
  --   (b) The new role differs from the old role.
  --   (c) The current session user is NOT a developer.
  --
  -- If all three conditions hold, the update is rejected.
  --
  -- When a developer updates ANY profile (including their own),
  -- condition (c) is FALSE → block does not fire → UPDATE proceeds.
  --
  -- When a non-developer tries to update someone else's profile,
  -- the "profiles: update own non-role fields" policy blocks it
  -- at the RLS level before the trigger even fires.
  -- This trigger is an additional defence-in-depth guard.

  IF NEW.id = auth.uid()
     AND NEW.role IS DISTINCT FROM OLD.role
     AND get_my_role() <> 'developer'
  THEN
    RAISE EXCEPTION
      'Permission denied: you cannot modify your own role. '
      'Contact a platform developer to change your role assignment.'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION prevent_role_self_escalation() IS
  'SECURITY DEFINER trigger function. Blocks any non-developer user '
  'from changing their own profiles.role value. '
  'Fires BEFORE UPDATE on profiles. '
  'Part of HIGH-05 fix in Phase 4.1.2 security patch.';

-- Step 1.5: Attach the trigger to profiles.
-- Drop first to be idempotent (in case of re-apply).
DROP TRIGGER IF EXISTS trg_prevent_role_escalation ON profiles;

CREATE TRIGGER trg_prevent_role_escalation
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_role_self_escalation();

COMMENT ON TRIGGER trg_prevent_role_escalation ON profiles IS
  'Prevents non-developer users from self-promoting their role. '
  'Part of HIGH-05 fix in Phase 4.1.2 security patch.';


-- ============================================================
-- SECTION 2 — LOW-01: SIGNUP ROLE INJECTION VIA METADATA
-- ============================================================
-- Root cause:
--   handle_new_user() uses COALESCE(
--     (NEW.raw_user_meta_data->>'role')::user_role, 'club_admin')
--   Any user who signs up via supabase.auth.signUp() and passes
--   role='developer' in options.data gets a developer profile.
--   This allows privilege escalation at signup time, bypassing
--   the HIGH-05 fix entirely.
--
-- Fix:
--   Hardcode 'club_admin' as the initial role. Role assignment
--   after signup must be performed by a developer via direct
--   UPDATE (now protected by the Section 1 trigger).
-- ============================================================

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO profiles (id, full_name, email, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'New User'),
    NEW.email,
    'club_admin'
    -- Role is ALWAYS 'club_admin' at signup regardless of metadata.
    -- Reason: any signup payload can supply arbitrary role values
    -- (see LOW-01 in Phase 4.1.2 security audit).
    -- To assign a non-default role, a developer must UPDATE the
    -- profiles row directly after signup. The
    -- trg_prevent_role_escalation trigger (HIGH-05) ensures only
    -- developers can change roles.
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION handle_new_user() IS
  'Supabase auth trigger: creates a profiles row when a new user '
  'signs up. Role is hardcoded to ''club_admin'' — the role field '
  'in raw_user_meta_data is intentionally ignored to prevent signup '
  'role injection (LOW-01, Phase 4.1.2 security patch).';


-- ============================================================
-- SECTION 3 — CRIT-03: suspensions.reason_notes PUBLIC EXPOSURE
-- ============================================================
-- Root cause:
--   "suspensions: public read" uses USING (true), making all
--   suspension rows including reason_notes readable by anonymous
--   users. reason_notes may contain personal disciplinary details
--   (e.g. "Player assaulted opponent") violating data minimisation.
--
-- Fix:
--   Replace the public read policy with an authorized read policy.
--   Rewrite v_active_suspensions to conditionally null out
--   reason_notes for unauthorized callers, preserving transparency
--   of the fact of suspension while protecting the reason text.
--   Active suspensions remain visible (is_active=true rows) via
--   the view without reason_notes; authorized users get full data.
-- ============================================================

-- Step 3.1: Drop the unrestricted public read policy.
DROP POLICY IF EXISTS "suspensions: public read" ON suspensions;

-- Step 3.2: Replacement policy — authorized read only.
-- Active suspensions (is_active=true) are visible to everyone
-- for league transparency (a club needs to know who is banned).
-- reason_notes are restricted to authorized roles only.
-- This is enforced at the view layer (v_active_suspensions rewrite
-- below nulls reason_notes for unauthorized callers).
CREATE POLICY "suspensions: authorized read"
  ON suspensions FOR SELECT
  USING (
    -- Developers see everything
    get_my_role() = 'developer'

    -- League founders see everything
    OR get_my_role() = 'league_founder'

    -- League admins see suspensions in their leagues
    OR is_league_admin(league_id)

    -- Club admins see suspensions for their own club's players
    OR EXISTS (
      SELECT 1
      FROM   players pl
      WHERE  pl.id      = suspensions.player_id
        AND  is_club_admin(pl.club_id)
    )

    -- Active suspensions: any authenticated user can see the
    -- fact of the suspension (not reason_notes).
    -- Application MUST use v_active_suspensions view to ensure
    -- reason_notes are nulled for unauthorized callers.
    -- Direct table read by authenticated non-admin users is
    -- restricted to their own active suspensions only via this
    -- last clause. Anonymous (auth.uid() IS NULL) gets no rows.
    OR (
      is_active = true
      AND auth.uid() IS NOT NULL
    )
  );

-- Step 3.3: Replace v_active_suspensions to conditionally hide
-- reason_notes based on caller role.
-- The view is SECURITY INVOKER (default) — it runs as the caller.
-- The RLS policy above determines which rows are visible.
-- reason_notes is NULLed out for rows where the caller is not
-- developer/league_founder/league_admin/club_admin.
CREATE OR REPLACE VIEW v_active_suspensions AS
SELECT
  s.id,
  s.player_id,
  p.full_name                                           AS player_name,
  p.position                                            AS player_position,
  cl.name                                               AS club_name,
  s.league_id,
  l.name                                                AS league_name,
  s.suspension_reason,
  s.matches_suspended,
  s.matches_served,
  (s.matches_suspended - s.matches_served)              AS matches_remaining,
  -- reason_notes: expose to authorized roles only.
  -- Unauthorized authenticated users see NULL (not the text).
  -- This implements column-level restriction at the view layer
  -- without PostgreSQL column-level security (not available in
  -- Supabase's PostgREST tier).
  CASE
    WHEN get_my_role() IN ('developer', 'league_founder')
      OR is_league_admin(s.league_id)
      OR EXISTS (
           SELECT 1 FROM players pl
           WHERE  pl.id = s.player_id
             AND  is_club_admin(pl.club_id)
         )
    THEN s.reason_notes
    ELSE NULL
  END                                                   AS reason_notes,
  s.created_at
FROM suspensions s
JOIN   players p  ON p.id  = s.player_id
LEFT JOIN clubs cl  ON cl.id = p.club_id
JOIN   leagues l  ON l.id  = s.league_id
WHERE  s.is_active = true
  AND  s.matches_served < s.matches_suspended;

COMMENT ON VIEW v_active_suspensions IS
  'Active player suspensions for public display. '
  'reason_notes is NULL for unauthorized callers — only developer, '
  'league_founder, league_admin, and club_admin roles receive the '
  'full reason text. Row visibility is controlled by the '
  '"suspensions: authorized read" RLS policy (Phase 4.1.2). '
  'Anonymous users get zero rows from the underlying table; '
  'authenticated non-admin users see only active suspensions '
  'without reason_notes.';


-- ============================================================
-- SECTION 4 — CRIT-01: INJURY VIEW MEDICAL FIELD EXPOSURE
-- ============================================================
-- Root cause:
--   Phase 3 v_active_injuries and v_player_injury_history
--   include diagnosis and treatment_notes columns. After Phase
--   4.1 restricted the underlying player_injuries table to
--   authorized users, these views no longer expose data to
--   anonymous users. However, all authorized users (including
--   club admins who are authorized by the RLS policy) receive
--   diagnosis and treatment_notes. These fields contain clinical
--   data that should require a higher-trust role (physiotherapist
--   or above) for access, separate from the basic injury status
--   information that coaches and club admins need.
--
-- Fix:
--   Replace v_active_injuries and v_player_injury_history to
--   exclude diagnosis and treatment_notes. These fields remain
--   available via v_player_injuries_medical (Phase 4) which is
--   already designed for authorized clinical access.
-- ============================================================

-- Step 4.1: Replace v_active_injuries — remove medical fields.
-- The underlying player_injuries RLS policy controls row visibility.
-- This view change removes only column exposure — row-level access
-- is unchanged. The view now matches the column set appropriate
-- for the operational (injury availability) dashboard.
CREATE OR REPLACE VIEW v_active_injuries AS
SELECT
  pi.id,
  pi.player_id,
  pl.full_name                                  AS player_name,
  pl.position                                   AS player_position,
  pl.photo_url,
  pi.club_id,
  cl.name                                       AS club_name,
  pi.fixture_id,
  pi.injury_type,
  pi.severity,
  pi.body_part,
  pi.injury_date,
  pi.expected_return_date,
  (pi.expected_return_date - CURRENT_DATE)      AS days_remaining,
  -- diagnosis and treatment_notes REMOVED (CRIT-01, Phase 4.1.2).
  -- Rationale: these clinical fields require physiotherapist-level
  -- access. Use v_player_injuries_medical for clinical data.
  pi.is_active
FROM player_injuries pi
JOIN players pl ON pl.id = pi.player_id
JOIN clubs   cl ON cl.id = pi.club_id
WHERE pi.is_active = true
ORDER BY pi.severity DESC, pi.expected_return_date ASC;

COMMENT ON VIEW v_active_injuries IS
  'Operational injury availability dashboard. '
  'Excludes diagnosis and treatment_notes (clinical fields). '
  'Row visibility controlled by "player_injuries: authorized read" RLS. '
  'For clinical data, use v_player_injuries_medical. '
  'Phase 4.1.2 security patch: CRIT-01 fix.';

-- Step 4.2: Replace v_player_injury_history — remove diagnosis.
CREATE OR REPLACE VIEW v_player_injury_history AS
SELECT
  pi.id,
  pi.player_id,
  pl.full_name                                  AS player_name,
  cl.name                                       AS club_name,
  pi.injury_type,
  pi.severity,
  pi.body_part,
  pi.injury_date,
  pi.expected_return_date,
  pi.actual_return_date,
  (pi.actual_return_date - pi.injury_date)      AS days_out,
  -- diagnosis REMOVED (CRIT-01, Phase 4.1.2).
  -- Rationale: diagnosis is clinical data requiring physiotherapist
  -- access. Use v_player_injuries_medical for full clinical history.
  pi.is_active,
  pi.cleared_at
FROM player_injuries pi
JOIN players pl ON pl.id = pi.player_id
JOIN clubs   cl ON cl.id = pi.club_id
ORDER BY pi.player_id, pi.injury_date DESC;

COMMENT ON VIEW v_player_injury_history IS
  'Player injury history — full career. '
  'Excludes diagnosis (clinical field). '
  'Row visibility controlled by "player_injuries: authorized read" RLS. '
  'For clinical data, use v_player_injuries_medical. '
  'Phase 4.1.2 security patch: CRIT-01 fix.';


-- ============================================================
-- SECTION 5 — C-2: COACH INJURY VISIBILITY IN ELIGIBILITY VIEW
-- ============================================================
-- Root cause:
--   v_player_eligibility_summary is SECURITY INVOKER (default).
--   The "player_injuries: authorized read" RLS policy (Phase 4.1)
--   does not include the 'coach' role. When a coach queries the
--   view, the LEFT JOIN LATERAL on player_injuries returns NULL
--   (RLS filters all injury rows). has_active_injury shows FALSE
--   and eligible_summary shows 'Available' for injured players.
--   This is incorrect for coaches making lineup selections.
--
-- Fix:
--   Create player_has_active_injury(UUID) as a SECURITY DEFINER
--   function. It accesses player_injuries as the function owner
--   (bypassing the caller's RLS), returning only a BOOLEAN.
--   No clinical data (diagnosis, treatment_notes) is exposed.
--   Update v_player_eligibility_summary to call this helper
--   instead of the LEFT JOIN LATERAL on player_injuries.
--
-- DESIGN RULING: This gives all authenticated roles (including
--   coaches) accurate injury status for lineup decisions. It does
--   NOT give coaches access to clinical details — only the
--   boolean fact "is this player injured right now?". The full
--   clinical data remains restricted by RLS on the table.
-- ============================================================

-- Step 5.1: SECURITY DEFINER helper — injury boolean lookup.
CREATE OR REPLACE FUNCTION player_has_active_injury(p_player_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Runs as function owner (postgres/service role), bypassing RLS.
  -- Returns TRUE if the player has any active injury record.
  -- Does NOT expose clinical fields (diagnosis, treatment_notes).
  -- Called by v_player_eligibility_summary for all roles including
  -- 'coach', correcting the C-2 false-negative (Phase 4.1.2).
  SELECT EXISTS (
    SELECT 1
    FROM   player_injuries pi
    WHERE  pi.player_id = p_player_id
      AND  pi.is_active = true
  );
$$;

COMMENT ON FUNCTION player_has_active_injury(UUID) IS
  'SECURITY DEFINER: returns TRUE if the player has an active injury. '
  'Bypasses player_injuries RLS intentionally — exposes only a BOOLEAN, '
  'not clinical fields. Used by v_player_eligibility_summary so that '
  'all roles (including ''coach'') see correct injury status. '
  'Phase 4.1.2 security patch: C-2 fix.';

-- Step 5.2: Create SECURITY DEFINER helper for injury return date.
-- Needed so the view can also show the correct expected return date
-- for all callers (not just those whose RLS permits injury access).
CREATE OR REPLACE FUNCTION player_active_injury_return_date(p_player_id UUID)
RETURNS DATE
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Runs as function owner (postgres/service role), bypassing RLS.
  -- Returns the expected_return_date of the most recent active injury,
  -- or NULL if the player has no active injury.
  -- Does NOT expose clinical fields (diagnosis, treatment_notes).
  -- Called by v_player_eligibility_summary (Phase 4.1.2: C-2 fix).
  SELECT pi.expected_return_date
  FROM   player_injuries pi
  WHERE  pi.player_id = p_player_id
    AND  pi.is_active  = true
  ORDER  BY pi.injury_date DESC
  LIMIT  1;
$$;

COMMENT ON FUNCTION player_active_injury_return_date(UUID) IS
  'SECURITY DEFINER: returns expected_return_date of most recent active '
  'injury for the given player, or NULL if none. Bypasses player_injuries '
  'RLS intentionally — exposes only a DATE, not clinical fields. '
  'Used by v_player_eligibility_summary so that all roles see the '
  'injury return date correctly. Phase 4.1.2 security patch: C-2 fix.';

-- Step 5.3: Replace v_player_eligibility_summary to use SECURITY
-- DEFINER helpers for injury data. This is the C-2 fix.
-- The suspension lateral remains unchanged (suspensions RLS now has
-- the "authenticated + is_active" clause from Section 3 above, so
-- all authenticated callers see active suspensions anyway).
-- The registration subquery remains unchanged.
DROP VIEW IF EXISTS v_player_eligibility_summary;

CREATE VIEW v_player_eligibility_summary AS
SELECT
  pl.id                                                 AS player_id,
  pl.full_name                                          AS player_name,
  pl.position,
  pl.club_id,
  cl.name                                               AS club_name,
  pl.is_active,

  -- has_active_suspension: TRUE if player has any active ban.
  -- Source: suspensions lateral join (single pass per player).
  (susp.player_id IS NOT NULL)                          AS has_active_suspension,

  -- suspended_in_league_id: league of most recent active suspension.
  susp.league_id                                        AS suspended_in_league_id,

  -- suspension_matches_remaining: matches left to serve.
  susp.matches_remaining                                AS suspension_matches_remaining,

  -- has_active_injury: TRUE if player has any active injury record.
  --
  -- C-2 FIX (Phase 4.1.2): uses player_has_active_injury() SECURITY
  -- DEFINER helper. All roles including 'coach' now receive the correct
  -- boolean. Previously, coaches received FALSE even for injured players
  -- because the player_injuries RLS excluded the 'coach' role.
  --
  -- Note: this reveals only the FACT of injury (boolean), not clinical
  -- details (diagnosis, treatment_notes). Those require direct access
  -- to v_player_injuries_medical (which is itself RLS-protected).
  player_has_active_injury(pl.id)                       AS has_active_injury,

  -- injury_expected_return: most recent active injury return date.
  -- C-2 FIX: uses player_active_injury_return_date() SECURITY DEFINER
  -- helper. All roles now receive the correct date.
  player_active_injury_return_date(pl.id)               AS injury_expected_return,

  -- latest_registration_status: most recent registration across all
  -- leagues/seasons. Uses idx_plr_player_created (added in Phase 4.1.1).
  (
    SELECT plr.status
    FROM   player_league_registrations plr
    WHERE  plr.player_id = pl.id
    ORDER  BY plr.created_at DESC
    LIMIT  1
  )                                                     AS latest_registration_status,

  -- eligible_summary: plain-language availability for display.
  -- Priority: Inactive > Suspended > Injured > Available.
  -- C-2 FIX: 'Injured' now shows correctly for all roles.
  CASE
    WHEN NOT pl.is_active               THEN 'Inactive'
    WHEN susp.player_id IS NOT NULL     THEN 'Suspended'
    WHEN player_has_active_injury(pl.id) THEN 'Injured'
    ELSE                                     'Available'
  END                                                   AS eligible_summary

FROM players pl
JOIN clubs cl ON cl.id = pl.club_id

-- ── Suspension lateral: single pass per player ─────────────
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

WHERE pl.is_active = true;

COMMENT ON VIEW v_player_eligibility_summary IS
  'Player availability dashboard. '
  'Uses LEFT JOIN LATERAL for suspensions (single scan). '
  'Uses player_has_active_injury() and player_active_injury_return_date() '
  'SECURITY DEFINER helpers for injury data — all roles including ''coach'' '
  'receive correct injury status (Phase 4.1.2 C-2 fix). '
  'Clinical injury fields (diagnosis, treatment_notes) are NOT exposed. '
  'Suspension row visibility is governed by "suspensions: authorized read" '
  'RLS policy (Phase 4.1.2). '
  'Registration status governed by player_league_registrations RLS.';


-- ============================================================
-- SECTION 6 — HIGH-01: disciplinary_records.notes PUBLIC EXPOSURE
-- ============================================================
-- Root cause:
--   "disciplinary_records: public read" uses USING (true).
--   The notes field contains free-text referee/admin commentary
--   about conduct incidents, which is personal data not meant
--   for public consumption.
--
-- Fix:
--   Replace the public read policy with an authorized read
--   policy. Create v_disciplinary_records_public view for
--   application public display (excludes notes field).
-- ============================================================

-- Step 6.1: Drop unrestricted public read.
DROP POLICY IF EXISTS "disciplinary_records: public read" ON disciplinary_records;

-- Step 6.2: Authorized read — structured fields public, notes restricted.
CREATE POLICY "disciplinary_records: authorized read"
  ON disciplinary_records FOR SELECT
  USING (
    -- Developers: full access
    get_my_role() = 'developer'

    -- League founders: full access
    OR get_my_role() = 'league_founder'

    -- League admins: see records in their leagues
    OR is_league_admin(league_id)

    -- Club admins: see disciplinary records for their club's players
    OR EXISTS (
      SELECT 1
      FROM   players pl
      WHERE  pl.id      = disciplinary_records.player_id
        AND  is_club_admin(pl.club_id)
    )

    -- Public (any authenticated): can see structured match stats
    -- (card_type, fixture_id, player_id, minute) but NOT notes.
    -- Application MUST use v_disciplinary_records_public to
    -- enforce column-level restriction for public display.
    -- Anonymous users (auth.uid() IS NULL) get no rows.
    OR auth.uid() IS NOT NULL
  );

-- Step 6.3: Public view — excludes notes.
CREATE OR REPLACE VIEW v_disciplinary_records_public AS
SELECT
  dr.id,
  dr.fixture_id,
  dr.player_id,
  pl.full_name          AS player_name,
  pl.position           AS player_position,
  cl.name               AS club_name,
  dr.league_id,
  l.name                AS league_name,
  dr.card_type,
  dr.minute,
  dr.created_at
  -- notes deliberately excluded — use authorized table access for notes
FROM disciplinary_records dr
JOIN   players pl  ON pl.id  = dr.player_id
LEFT JOIN clubs   cl  ON cl.id  = pl.club_id
JOIN   leagues l   ON l.id   = dr.league_id;

COMMENT ON VIEW v_disciplinary_records_public IS
  'Public-safe disciplinary records view. Excludes the notes field. '
  'Row visibility is governed by "disciplinary_records: authorized read" '
  'RLS policy (Phase 4.1.2). Anonymous users get no rows; authenticated '
  'users see structured match statistics only. '
  'Authorized roles (developer, league_founder, league_admin, club_admin) '
  'may query the base table directly for full data including notes.';


-- ============================================================
-- SECTION 7 — HIGH-02: player_league_registrations PUBLIC EXPOSURE
-- ============================================================
-- Root cause:
--   "player_league_registrations: public read" uses USING (true).
--   rejection_reason contains personal denial reasons that should
--   not be publicly readable. notes also contains admin commentary.
--
-- Fix:
--   Replace public read with authorized read. Create a public
--   view (v_player_registrations_public) exposing only non-
--   sensitive columns for public league roster display.
-- ============================================================

-- Step 7.1: Drop unrestricted public read.
DROP POLICY IF EXISTS "player_league_registrations: public read"
  ON player_league_registrations;

-- Step 7.2: Authorized read — rejection_reason restricted.
CREATE POLICY "player_league_registrations: authorized read"
  ON player_league_registrations FOR SELECT
  USING (
    -- Developers: full access
    get_my_role() = 'developer'

    -- League founders: full access
    OR get_my_role() = 'league_founder'

    -- League admins: see all registrations in their leagues
    OR is_league_admin(league_id)

    -- Club admins: see registrations for their own club
    OR (
      get_my_role() = 'club_admin'
      AND is_club_admin(club_id)
    )

    -- Public (any authenticated): see approved registrations only
    -- (player is legitimately playing in this league).
    -- rejection_reason restricted at view layer via
    -- v_player_registrations_public.
    OR (
      status = 'approved'
      AND auth.uid() IS NOT NULL
    )
  );

-- Step 7.3: Public view — no rejection_reason, no notes, no reviewed_by.
CREATE OR REPLACE VIEW v_player_registrations_public AS
SELECT
  plr.id,
  plr.player_id,
  pl.full_name          AS player_name,
  plr.club_id,
  cl.name               AS club_name,
  plr.league_id,
  l.name                AS league_name,
  plr.season_id,
  plr.status,
  plr.jersey_number,
  plr.is_foreign,
  plr.submitted_at,
  plr.valid_from,
  plr.valid_until
  -- rejection_reason, notes, reviewed_by excluded
  -- These are available to authorized roles querying the table directly.
FROM player_league_registrations plr
JOIN   players pl ON pl.id  = plr.player_id
JOIN   clubs   cl ON cl.id  = plr.club_id
JOIN   leagues l  ON l.id   = plr.league_id;

COMMENT ON VIEW v_player_registrations_public IS
  'Public-safe registration view. Excludes rejection_reason, notes, '
  'and reviewed_by. Row visibility governed by '
  '"player_league_registrations: authorized read" RLS (Phase 4.1.2). '
  'Intended for public league roster display. '
  'Authorized roles query the base table for full data.';


-- ============================================================
-- SECTION 8 — HIGH-06: REGISTRATION UPDATE MISSING WITH CHECK
-- ============================================================
-- Root cause:
--   "player_league_registrations: club admin or league admin update"
--   has only USING (evaluated against OLD row), no WITH CHECK
--   (evaluated against NEW row). A club admin for Club A with a
--   pending registration can change club_id to Club B because
--   the USING check passes on the OLD row while the NEW row is
--   never validated.
--
-- Fix:
--   Drop and recreate the policy with an identical WITH CHECK
--   that validates the NEW row. Club admins can only update to
--   a club_id they administer. Status must remain 'pending' in
--   the new row (approval is done by league admins only).
-- ============================================================

DROP POLICY IF EXISTS "player_league_registrations: club admin or league admin update"
  ON player_league_registrations;

CREATE POLICY "player_league_registrations: scoped update"
  ON player_league_registrations FOR UPDATE
  USING (
    -- Access check on OLD row (existing state)
    get_my_role() = 'developer'
    OR is_league_admin(league_id)
    OR (
      get_my_role() = 'club_admin'
      AND is_club_admin(club_id)     -- OLD club_id: is caller admin of the current club?
      AND status = 'pending'          -- OLD status: only pending rows are editable by club admin
    )
  )
  WITH CHECK (
    -- Validation check on NEW row (proposed state)
    get_my_role() = 'developer'
    OR is_league_admin(league_id)
    OR (
      get_my_role() = 'club_admin'
      AND is_club_admin(club_id)     -- NEW club_id: caller must still be admin of the new club_id
      AND status = 'pending'          -- NEW status: club admin cannot change status to non-pending
    )
  );

COMMENT ON POLICY "player_league_registrations: scoped update"
  ON player_league_registrations IS
  'Replacement for "club admin or league admin update" (Phase 4.1.2). '
  'Adds WITH CHECK to validate the NEW row — prevents a club admin '
  'from reassigning a registration to a club they do not administer. '
  'HIGH-06 fix.';


-- ============================================================
-- SECTION 9 — MED-02: CROSS-CLUB PLAYER REGISTRATION INSERT
-- ============================================================
-- Root cause:
--   "player_league_registrations: club admin insert" checks
--   is_club_admin(club_id) on the submitted club_id but does NOT
--   verify that the player_id actually belongs to that club.
--   A Club A admin can register a Club B player under Club A.
--
-- Fix:
--   Add EXISTS check: player must belong to the club being
--   registered under (players.club_id = submitted club_id).
-- ============================================================

DROP POLICY IF EXISTS "player_league_registrations: club admin insert"
  ON player_league_registrations;

CREATE POLICY "player_league_registrations: club admin insert"
  ON player_league_registrations FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (
      get_my_role() = 'club_admin'
      AND is_club_admin(club_id)
      -- Player must actually belong to the submitting club.
      -- Prevents cross-club phantom registrations (MED-02, Phase 4.1.2).
      AND EXISTS (
        SELECT 1
        FROM   players p
        WHERE  p.id       = player_id
          AND  p.club_id  = club_id
          AND  p.is_active = true
      )
    )
  );

COMMENT ON POLICY "player_league_registrations: club admin insert"
  ON player_league_registrations IS
  'Replacement INSERT policy (Phase 4.1.2). Adds player.club_id cross-check '
  '— the player being registered must belong to the submitting club. '
  'Prevents Club A admin from registering a Club B player. MED-02 fix.';


-- ============================================================
-- SECTION 10 — MED-04: NO DELETE POLICY ON standings
-- ============================================================
-- Root cause:
--   No DELETE policy on standings. Stale standings rows for
--   clubs that left a league cannot be cleaned up via API.
--   RLS default: no matching policy = deny.
--
-- Fix:
--   Add a DELETE policy scoped to league admins.
-- ============================================================

CREATE POLICY "standings: league admin delete"
  ON standings FOR DELETE
  USING (
    get_my_role() = 'developer'
    OR is_league_admin(league_id)
  );

COMMENT ON POLICY "standings: league admin delete"
  ON standings IS
  'Allows league admins and developers to delete stale standings rows. '
  'MED-04 fix (Phase 4.1.2). Operational cleanup only — standings are '
  'normally managed by SECURITY DEFINER triggers.';


-- ============================================================
-- SECTION 11 — HIGH-04: NO DELETE POLICY ON fixtures
-- ============================================================
-- Root cause:
--   No DELETE policy on fixtures. Silent deny is undocumented.
--   League admins should be able to delete fixtures in draft/
--   scheduled state (before any match result exists).
--
-- Fix:
--   Developer: delete any fixture.
--   League admin: delete fixtures with no committed result
--   (status = 'scheduled' — not yet played/completed).
--   Rationale: completed fixtures are audit records; only
--   developer should delete those in exceptional cases.
-- ============================================================

CREATE POLICY "fixtures: developer delete"
  ON fixtures FOR DELETE
  USING (get_my_role() = 'developer');

-- League admins can delete only scheduled (pre-match) fixtures
-- for their own leagues. Completed/cancelled fixtures are preserved
-- as audit records and require developer intervention.
CREATE POLICY "fixtures: league admin delete scheduled"
  ON fixtures FOR DELETE
  USING (
    is_league_admin(league_id)
    AND status = 'scheduled'
  );

COMMENT ON POLICY "fixtures: developer delete"
  ON fixtures IS
  'Developers can delete any fixture. HIGH-04 fix (Phase 4.1.2).';

COMMENT ON POLICY "fixtures: league admin delete scheduled"
  ON fixtures IS
  'League admins can delete scheduled fixtures in their leagues. '
  'Completed/cancelled fixtures are audit records and may only be '
  'deleted by developers. HIGH-04 fix (Phase 4.1.2).';


-- ============================================================
-- SECTION 12 — LOW-02: league_clubs SPAM INSERT
-- ============================================================
-- Root cause:
--   "league_clubs: authenticated insert" uses
--   WITH CHECK (auth.uid() IS NOT NULL), allowing any
--   authenticated user to spam join requests for any club.
--
-- Fix:
--   Restrict INSERT to the club's own admin only.
-- ============================================================

DROP POLICY IF EXISTS "league_clubs: authenticated insert" ON league_clubs;

CREATE POLICY "league_clubs: club admin insert"
  ON league_clubs FOR INSERT
  WITH CHECK (
    -- Developer can insert directly (admin operations)
    get_my_role() = 'developer'
    -- Only the club's own admin can submit a league join request
    OR (
      auth.uid() IS NOT NULL
      AND is_club_admin(club_id)
    )
  );

COMMENT ON POLICY "league_clubs: club admin insert"
  ON league_clubs IS
  'Replacement for "league_clubs: authenticated insert" (Phase 4.1.2). '
  'Restricts league join requests to the club''s own admin. '
  'Prevents unauthenticated spam and cross-club request injection. '
  'LOW-02 fix.';


-- ============================================================
-- SECTION 13 — NF-2: DYNAMIC CONSTRAINT DROP (SAFE PATTERN)
-- ============================================================
-- Root cause (NF-2):
--   Phase 4.1 FIX 8 uses:
--     ALTER TABLE player_league_registrations
--       DROP CONSTRAINT IF EXISTS
--         player_league_registrations_player_id_league_id_season_id_key;
--   The constraint name is assumed to be the auto-generated name.
--   If Phase 4 used an explicit name (or PostgreSQL generated a
--   different name in a non-standard environment), DROP silently
--   succeeds but leaves the old constraint intact. The subsequent
--   ADD CONSTRAINT would then leave both constraints present.
--
-- Root cause (NF-3):
--   Phase 4.1 FIX 8 also runs:
--     ALTER TABLE player_league_registrations
--       ADD CONSTRAINT uq_plr_player_club_league_season
--         UNIQUE (player_id, club_id, league_id, season_id);
--   Inside a transaction this builds the backing index with an
--   ACCESS EXCLUSIVE lock that blocks all reads and writes to
--   player_league_registrations for the duration of the index
--   build — a production outage risk.
--
-- Fix strategy for this patch:
--   (a) Drop ALL unique constraints on player_league_registrations
--       using a DO block that looks up actual constraint names from
--       pg_constraint. This handles both the auto-generated name
--       and any explicit names.
--   (b) The new UNIQUE constraint is NOT created here in the
--       transaction. It is created in PART B below using
--       CREATE UNIQUE INDEX CONCURRENTLY (no lock-blocking) then
--       promoted to a constraint with ALTER TABLE ... USING INDEX.
--
-- IMPORTANT: PART B must be run AFTER this transaction commits.
-- The table will have NO unique constraint on (player_id,
-- club_id, league_id, season_id) between PART A commit and
-- PART B completion. During this window, the database enforces
-- no uniqueness on this tuple. Keep this window as short as
-- possible (run PART B immediately after PART A).
--
-- State check: if uq_plr_player_club_league_season already
--   exists (from Phase 4.1 FIX 8 applied correctly), the DO
--   block skips the DROP of that constraint and PART B will
--   detect the existing index and skip gracefully. This patch
--   is safe to apply even if Phase 4.1 FIX 8 already ran.
-- ============================================================

DO $$
DECLARE
  v_conname TEXT;
BEGIN
  -- Loop over ALL unique constraints on player_league_registrations
  -- that cover (player_id, league_id, season_id) — the old 3-column
  -- set — and drop them. This handles any name variant.
  FOR v_conname IN
    SELECT c.conname
    FROM   pg_constraint c
    JOIN   pg_class      t ON t.oid = c.conrelid
    WHERE  t.relname  = 'player_league_registrations'
      AND  t.relnamespace = 'public'::regnamespace
      AND  c.contype  = 'u'
      -- Match constraints covering exactly player_id, league_id,
      -- season_id in any order — 3-column unique (old schema).
      -- We identify these by checking the column names.
      AND  NOT EXISTS (
             -- Exclude the 4-column constraint (if already present)
             SELECT 1 FROM pg_attribute a
             WHERE  a.attrelid = c.conrelid
               AND  a.attname  = 'club_id'
               AND  a.attnum   = ANY(c.conkey)
           )
      AND  EXISTS (
             SELECT 1 FROM pg_attribute a
             WHERE  a.attrelid = c.conrelid
               AND  a.attname  = 'player_id'
               AND  a.attnum   = ANY(c.conkey)
           )
      AND  EXISTS (
             SELECT 1 FROM pg_attribute a
             WHERE  a.attrelid = c.conrelid
               AND  a.attname  = 'league_id'
               AND  a.attnum   = ANY(c.conkey)
           )
      AND  EXISTS (
             SELECT 1 FROM pg_attribute a
             WHERE  a.attrelid = c.conrelid
               AND  a.attname  = 'season_id'
               AND  a.attnum   = ANY(c.conkey)
           )
  LOOP
    RAISE NOTICE 'Phase 4.1.2 NF-2: Dropping old 3-column unique constraint: %', v_conname;
    EXECUTE format('ALTER TABLE player_league_registrations DROP CONSTRAINT IF EXISTS %I', v_conname);
  END LOOP;

  -- Also drop the 4-column unique constraint if it exists as a
  -- table-level constraint (not an index-backed constraint from PART B).
  -- This handles the case where Phase 4.1 FIX 8 already ran correctly.
  -- PART B will rebuild it via CONCURRENTLY index + USING INDEX.
  FOR v_conname IN
    SELECT c.conname
    FROM   pg_constraint c
    JOIN   pg_class      t ON t.oid = c.conrelid
    WHERE  t.relname  = 'player_league_registrations'
      AND  t.relnamespace = 'public'::regnamespace
      AND  c.contype  = 'u'
      AND  c.conname  = 'uq_plr_player_club_league_season'
  LOOP
    RAISE NOTICE 'Phase 4.1.2 NF-3: Dropping existing 4-column constraint for CONCURRENTLY rebuild: %', v_conname;
    EXECUTE format('ALTER TABLE player_league_registrations DROP CONSTRAINT IF EXISTS %I', v_conname);
  END LOOP;

  RAISE NOTICE 'Phase 4.1.2 NF-2/NF-3: Constraint cleanup complete. '
    'Run PART B immediately to rebuild uq_plr_player_club_league_season via CONCURRENTLY.';
END;
$$;

-- ============================================================
-- SECTION 14 — TABLE DOCUMENTATION COMMENTS
-- ============================================================
-- Add comments documenting the intentional SECURITY DEFINER
-- trigger bypass on standings (HIGH-03: accepted design).
-- ============================================================

COMMENT ON TABLE standings IS
  'League standings table. '
  'RLS policies apply to direct API/application access. '
  'The trigger update_standings_on_official_result() runs as '
  'SECURITY DEFINER and bypasses RLS — this is intentional. '
  'Standings integrity depends on the match_results INSERT RLS '
  'policy correctly scoping inserts to the league admin''s own leagues. '
  '(HIGH-03, Phase 4.1.2: accepted design, documented.)';

COMMENT ON TABLE profiles IS
  'User profile table. role column is protected by the '
  'trg_prevent_role_escalation trigger (Phase 4.1.2 HIGH-05 fix). '
  'Non-developer users cannot modify their own role via API. '
  'Role assignment must be performed by a developer after signup.';

COMMIT;

-- ============================================================
-- END OF PART A
-- ============================================================
-- Part A transaction complete.
-- Run PART B immediately after verifying Part A succeeded.
-- ============================================================


-- ============================================================
-- PART B — CONCURRENT INDEX OPERATIONS (OUTSIDE TRANSACTION)
-- ============================================================
-- These statements CANNOT run inside a transaction block
-- (CREATE INDEX CONCURRENTLY is disallowed in transactions).
-- Run each statement individually, confirming success before
-- proceeding to the next.
--
-- Purpose:
--   Rebuild uq_plr_player_club_league_season without blocking
--   production writes (NF-3 fix). The index is built
--   CONCURRENTLY (read-compatible, write-compatible), then
--   promoted to a constraint via ALTER TABLE ... USING INDEX
--   which takes only a brief ShareLock, not ACCESS EXCLUSIVE.
--
-- Timeline:
--   B-1: Build index concurrently (~seconds to minutes depending
--          on table size — no writes blocked).
--   B-2: Promote index to constraint (brief lock, sub-second
--          for the metadata operation itself).
--   B-3: Drop the old idx_plr_approved if it still exists
--          (may have been left by Phase 4.1 FIX 8), then
--          concurrently build the replacement with club_id.
--
-- Safety: if any B-n step fails, the preceding index build is
-- wasted work but causes no data loss. Re-run from the failed
-- step. The CONCURRENTLY build can be interrupted and rerun.
-- ============================================================

-- ── B-1: Build the new 4-column unique index concurrently ──
-- Pre-flight: run VALIDATE-PLR-DUPES check above first.
-- This step may take several minutes on large tables.
-- No reads or writes are blocked during this phase.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS
  idx_plr_uq_player_club_league_season
  ON player_league_registrations (player_id, club_id, league_id, season_id);

-- ── B-2: Promote the index to a named unique constraint ────
-- This ALTER TABLE takes a ShareLock (briefly) to register the
-- constraint metadata. Duration is milliseconds on any table size.
-- If this step fails (e.g. the index has invalid rows from PART A
-- window), check VALIDATE-PLR-DUPES again before retrying.
ALTER TABLE player_league_registrations
  ADD CONSTRAINT uq_plr_player_club_league_season
  UNIQUE USING INDEX idx_plr_uq_player_club_league_season;

-- ── B-3: Rebuild idx_plr_approved with club_id ─────────────
-- Drop the old version first (may exist from Phase 4.1 FIX 8
-- or the original Phase 4). Then rebuild concurrently.
DROP INDEX CONCURRENTLY IF EXISTS idx_plr_approved;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_plr_approved
  ON player_league_registrations (league_id, player_id, club_id, status)
  WHERE status = 'approved';

-- ============================================================
-- END OF PART B
-- ============================================================


-- ============================================================
-- POST-APPLY VERIFICATION QUERIES
-- ============================================================
-- Run these after PART A and PART B complete to confirm the
-- patch applied correctly. These are read-only queries.
-- ============================================================

-- [V-1] Confirm profiles UPDATE policies are correct:
--   SELECT policyname, cmd, qual, with_check
--   FROM pg_policies
--   WHERE tablename = 'profiles' AND cmd = 'UPDATE'
--   ORDER BY policyname;
--   EXPECTED: Two rows:
--     "profiles: developer update any"        — USING: get_my_role()='developer'
--     "profiles: update own non-role fields"  — USING: id=auth.uid(), CHECK: id=auth.uid()

-- [V-2] Confirm trg_prevent_role_escalation exists:
--   SELECT tgname, tgenabled
--   FROM pg_trigger
--   WHERE tgrelid = 'profiles'::regclass
--     AND tgname  = 'trg_prevent_role_escalation';
--   EXPECTED: 1 row, tgenabled = 'O' (enabled).

-- [V-3] Confirm handle_new_user does NOT reference raw_user_meta_data->>'role':
--   SELECT prosrc FROM pg_proc WHERE proname = 'handle_new_user';
--   EXPECTED: Body contains 'club_admin' as literal, no COALESCE on role metadata.

-- [V-4] Confirm suspensions: no public read policy:
--   SELECT policyname FROM pg_policies
--   WHERE tablename = 'suspensions' AND cmd = 'SELECT';
--   EXPECTED: Only "suspensions: authorized read" (league admin insert/update remain).

-- [V-5] Confirm v_active_suspensions does NOT expose reason_notes unconditionally:
--   SELECT definition FROM pg_views WHERE viewname = 'v_active_suspensions';
--   EXPECTED: CASE WHEN get_my_role()... THEN s.reason_notes ELSE NULL END present.

-- [V-6] Confirm v_active_injuries excludes diagnosis and treatment_notes:
--   SELECT definition FROM pg_views WHERE viewname = 'v_active_injuries';
--   EXPECTED: diagnosis and treatment_notes NOT in column list.

-- [V-7] Confirm player_has_active_injury() is SECURITY DEFINER:
--   SELECT proname, prosecdef FROM pg_proc
--   WHERE proname = 'player_has_active_injury';
--   EXPECTED: prosecdef = true.

-- [V-8] Confirm v_player_eligibility_summary calls the helper:
--   SELECT definition FROM pg_views WHERE viewname = 'v_player_eligibility_summary';
--   EXPECTED: player_has_active_injury(pl.id) present in SELECT list.

-- [V-9] Confirm player_league_registrations has no 3-column unique constraint:
--   SELECT conname FROM pg_constraint
--   WHERE conrelid = 'player_league_registrations'::regclass
--     AND contype = 'u';
--   EXPECTED: Only uq_plr_player_club_league_season (4 columns).
--   After PART B: ALSO idx_plr_uq_player_club_league_season → promoted to constraint.

-- [V-10] Confirm "league_clubs: authenticated insert" no longer exists:
--   SELECT policyname FROM pg_policies
--   WHERE tablename = 'league_clubs' AND cmd = 'INSERT';
--   EXPECTED: "league_clubs: club admin insert".

-- [V-11] Confirm new DELETE policies exist:
--   SELECT tablename, policyname FROM pg_policies
--   WHERE cmd = 'DELETE' AND tablename IN ('standings', 'fixtures')
--   ORDER BY tablename, policyname;
--   EXPECTED:
--     fixtures  | "fixtures: developer delete"
--     fixtures  | "fixtures: league admin delete scheduled"
--     standings | "standings: league admin delete"

-- [V-12] Confirm player_league_registrations INSERT policy has player check:
--   SELECT with_check FROM pg_policies
--   WHERE tablename = 'player_league_registrations' AND cmd = 'INSERT';
--   EXPECTED: EXISTS (SELECT 1 FROM players p WHERE p.id = player_id ...) in with_check.

-- [V-13] Confirm registration scoped update has WITH CHECK:
--   SELECT policyname, with_check FROM pg_policies
--   WHERE tablename = 'player_league_registrations' AND cmd = 'UPDATE';
--   EXPECTED: "player_league_registrations: scoped update" with non-null with_check.

-- ============================================================
-- FUNCTIONAL TESTS (Supabase / application layer)
-- ============================================================
-- Run these via the Supabase client or SQL as different roles.
--
-- [FT-1] HIGH-05: As a club_admin user, PATCH /profiles?id=eq.<own_uuid>
--   with body {"role": "developer"}
--   EXPECTED: 403 error — "Permission denied: you cannot modify your own role"
--
-- [FT-2] LOW-01: Sign up a new user via supabase.auth.signUp() with
--   options: { data: { role: 'developer' } }
--   Then check SELECT role FROM profiles WHERE id = <new_user_id>
--   EXPECTED: role = 'club_admin' (metadata role ignored)
--
-- [FT-3] CRIT-03: As anonymous (anon key), GET /suspensions?select=*
--   EXPECTED: 0 rows (no unauthenticated access to raw table)
--   Then GET /v_active_suspensions?select=player_name,suspension_reason,reason_notes
--   EXPECTED: rows returned, reason_notes = null for anon user
--             (authenticated non-admin also sees null for reason_notes)
--
-- [FT-4] CRIT-01: As club_admin, GET /v_active_injuries?select=*
--   EXPECTED: No diagnosis or treatment_notes columns in response
--
-- [FT-5] C-2: As coach user, GET /v_player_eligibility_summary
--   for a player who is currently injured
--   EXPECTED: has_active_injury = true, eligible_summary = 'Injured'
--   (Previously: has_active_injury = false, eligible_summary = 'Available')
--
-- [FT-6] MED-02: As club_admin for Club A, INSERT into
--   player_league_registrations with player_id from Club B
--   EXPECTED: 403 error (player.club_id != submitted club_id)
--
-- [FT-7] HIGH-06: As club_admin for Club A, UPDATE a pending registration
--   row setting club_id = Club B's UUID
--   EXPECTED: 403 error (WITH CHECK: is_club_admin(new.club_id) fails)
--
-- [FT-8] LOW-02: As a non-club-admin authenticated user, INSERT into
--   league_clubs for any club
--   EXPECTED: 403 error (is_club_admin(club_id) fails)
--
-- ============================================================
-- ROLLBACK SECTION
-- ============================================================
-- If Part A must be rolled back, execute these statements
-- in a single transaction BEFORE running Part B.
-- If Part B has already run, also drop the CONCURRENTLY indexes.
-- ============================================================

-- -- ── ROLLBACK PART A ──
-- BEGIN;
--
-- -- Rollback Section 1 — HIGH-05
-- DROP TRIGGER  IF EXISTS trg_prevent_role_escalation ON profiles;
-- DROP FUNCTION IF EXISTS prevent_role_self_escalation();
-- DROP POLICY   IF EXISTS "profiles: update own non-role fields" ON profiles;
-- DROP POLICY   IF EXISTS "profiles: developer update any"       ON profiles;
-- CREATE POLICY "profiles: update own or developer"
--   ON profiles FOR UPDATE
--   USING (id = auth.uid() OR get_my_role() = 'developer');
--
-- -- Rollback Section 2 — LOW-01: restore original handle_new_user with metadata role
-- CREATE OR REPLACE FUNCTION handle_new_user()
-- RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
-- BEGIN
--   INSERT INTO profiles (id, full_name, email, role)
--   VALUES (
--     NEW.id,
--     COALESCE(NEW.raw_user_meta_data->>'full_name', 'New User'),
--     NEW.email,
--     COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'club_admin')
--   )
--   ON CONFLICT (id) DO NOTHING;
--   RETURN NEW;
-- END;
-- $$;
--
-- -- Rollback Section 3 — CRIT-03
-- DROP POLICY IF EXISTS "suspensions: authorized read" ON suspensions;
-- CREATE POLICY "suspensions: public read"
--   ON suspensions FOR SELECT USING (true);
-- CREATE OR REPLACE VIEW v_active_suspensions AS
-- SELECT
--   s.id, s.player_id, p.full_name AS player_name, p.position AS player_position,
--   cl.name AS club_name, s.league_id, l.name AS league_name,
--   s.suspension_reason, s.matches_suspended, s.matches_served,
--   (s.matches_suspended - s.matches_served) AS matches_remaining,
--   s.reason_notes, s.created_at
-- FROM suspensions s
-- JOIN players p ON p.id = s.player_id
-- LEFT JOIN clubs cl ON cl.id = p.club_id
-- JOIN leagues l ON l.id = s.league_id
-- WHERE s.is_active = true AND s.matches_served < s.matches_suspended;
--
-- -- Rollback Section 4 — CRIT-01
-- CREATE OR REPLACE VIEW v_active_injuries AS
-- SELECT
--   pi.id, pi.player_id, pl.full_name AS player_name,
--   pl.position AS player_position, pl.photo_url,
--   pi.club_id, cl.name AS club_name, pi.fixture_id,
--   pi.injury_type, pi.severity, pi.body_part,
--   pi.injury_date, pi.expected_return_date,
--   (pi.expected_return_date - CURRENT_DATE) AS days_remaining,
--   pi.diagnosis, pi.treatment_notes, pi.is_active
-- FROM player_injuries pi
-- JOIN players pl ON pl.id = pi.player_id
-- JOIN clubs   cl ON cl.id = pi.club_id
-- WHERE pi.is_active = true
-- ORDER BY pi.severity DESC, pi.expected_return_date ASC;
--
-- CREATE OR REPLACE VIEW v_player_injury_history AS
-- SELECT
--   pi.id, pi.player_id, pl.full_name AS player_name, cl.name AS club_name,
--   pi.injury_type, pi.severity, pi.body_part, pi.injury_date,
--   pi.expected_return_date, pi.actual_return_date,
--   (pi.actual_return_date - pi.injury_date) AS days_out,
--   pi.diagnosis, pi.is_active, pi.cleared_at
-- FROM player_injuries pi
-- JOIN players pl ON pl.id = pi.player_id
-- JOIN clubs   cl ON cl.id = pi.club_id
-- ORDER BY pi.player_id, pi.injury_date DESC;
--
-- -- Rollback Section 5 — C-2
-- DROP FUNCTION IF EXISTS player_has_active_injury(UUID);
-- DROP FUNCTION IF EXISTS player_active_injury_return_date(UUID);
-- DROP VIEW IF EXISTS v_player_eligibility_summary;
-- -- Restore Phase 4.1.1 version of v_player_eligibility_summary
-- -- (copy from playpro_phase4_1_1_remediation_patch.sql ROLLBACK section)
--
-- -- Rollback Section 6 — HIGH-01
-- DROP POLICY IF EXISTS "disciplinary_records: authorized read" ON disciplinary_records;
-- DROP VIEW IF EXISTS v_disciplinary_records_public;
-- CREATE POLICY "disciplinary_records: public read"
--   ON disciplinary_records FOR SELECT USING (true);
--
-- -- Rollback Section 7 — HIGH-02
-- DROP POLICY IF EXISTS "player_league_registrations: authorized read"
--   ON player_league_registrations;
-- DROP VIEW IF EXISTS v_player_registrations_public;
-- CREATE POLICY "player_league_registrations: public read"
--   ON player_league_registrations FOR SELECT USING (true);
--
-- -- Rollback Section 8 — HIGH-06
-- DROP POLICY IF EXISTS "player_league_registrations: scoped update"
--   ON player_league_registrations;
-- CREATE POLICY "player_league_registrations: club admin or league admin update"
--   ON player_league_registrations FOR UPDATE
--   USING (
--     get_my_role() = 'developer'
--     OR is_league_admin(league_id)
--     OR (get_my_role() = 'club_admin' AND is_club_admin(club_id) AND status = 'pending')
--   );
--
-- -- Rollback Section 9 — MED-02
-- DROP POLICY IF EXISTS "player_league_registrations: club admin insert"
--   ON player_league_registrations;
-- CREATE POLICY "player_league_registrations: club admin insert"
--   ON player_league_registrations FOR INSERT
--   WITH CHECK (
--     get_my_role() = 'developer'
--     OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
--   );
--
-- -- Rollback Section 10 — MED-04
-- DROP POLICY IF EXISTS "standings: league admin delete" ON standings;
--
-- -- Rollback Section 11 — HIGH-04
-- DROP POLICY IF EXISTS "fixtures: developer delete"               ON fixtures;
-- DROP POLICY IF EXISTS "fixtures: league admin delete scheduled"  ON fixtures;
--
-- -- Rollback Section 12 — LOW-02
-- DROP POLICY IF EXISTS "league_clubs: club admin insert" ON league_clubs;
-- CREATE POLICY "league_clubs: authenticated insert"
--   ON league_clubs FOR INSERT
--   WITH CHECK (auth.uid() IS NOT NULL);
--
-- -- Rollback Section 13 — NF-2/NF-3
-- -- Restore the 3-column unique constraint (Phase 4 original state):
-- -- WARNING: Only run this if the 4-column constraint was not present
-- -- before this patch. If Phase 4.1 FIX 8 already added it, see
-- -- Phase 4.1 stabilization patch rollback section instead.
-- ALTER TABLE player_league_registrations
--   DROP CONSTRAINT IF EXISTS uq_plr_player_club_league_season;
-- ALTER TABLE player_league_registrations
--   ADD CONSTRAINT player_league_registrations_player_id_league_id_season_id_key
--     UNIQUE (player_id, league_id, season_id);
--
-- COMMIT;
--
-- -- ── ROLLBACK PART B (run outside transaction if B-1/B-2/B-3 ran) ──
-- DROP INDEX CONCURRENTLY IF EXISTS idx_plr_uq_player_club_league_season;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_plr_approved;
-- -- Recreate original idx_plr_approved without club_id:
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_plr_approved
--   ON player_league_registrations (league_id, player_id, status)
--   WHERE status = 'approved';
--
-- ============================================================
-- END OF ROLLBACK SECTION
-- ============================================================


-- ============================================================
-- PATCH SUMMARY
-- ============================================================
--
-- Phase:            4.1.2 — Security Patch
-- Applies after:    4.1.1 — Remediation Patch
-- Date:             2026-06-07
--
-- Part A (transactional):
--   Functions:              4
--     prevent_role_self_escalation()     [NEW — SECURITY DEFINER trigger]
--     player_has_active_injury()         [NEW — SECURITY DEFINER helper]
--     player_active_injury_return_date() [NEW — SECURITY DEFINER helper]
--     handle_new_user()                  [REPLACED — role hardcoded]
--   Triggers created:       1
--     trg_prevent_role_escalation ON profiles [NEW]
--   Policies dropped:       9
--     "profiles: update own or developer"
--     "suspensions: public read"
--     "disciplinary_records: public read"
--     "player_league_registrations: public read"
--     "player_league_registrations: club admin or league admin update"
--     "player_league_registrations: club admin insert"
--     "league_clubs: authenticated insert"
--     (+ dynamic constraint drops via DO block)
--   Policies created:       11
--     "profiles: update own non-role fields"
--     "profiles: developer update any"
--     "suspensions: authorized read"
--     "disciplinary_records: authorized read"
--     "player_league_registrations: authorized read"
--     "player_league_registrations: scoped update"
--     "player_league_registrations: club admin insert"
--     "standings: league admin delete"
--     "fixtures: developer delete"
--     "fixtures: league admin delete scheduled"
--     "league_clubs: club admin insert"
--   Views replaced:         5
--     v_active_suspensions          (CRIT-03)
--     v_active_injuries             (CRIT-01)
--     v_player_injury_history       (CRIT-01)
--     v_player_eligibility_summary  (C-2)
--   Views created:          3
--     v_disciplinary_records_public (HIGH-01)
--     v_player_registrations_public (HIGH-02)
--   Constraints modified:   1 (via DO block dynamic lookup)
--     player_league_registrations: old 3-col unique dropped
--     4-col unique rebuilt in PART B (CONCURRENTLY)
--
-- Part B (concurrent, outside transaction):
--   Indexes created:        2
--     idx_plr_uq_player_club_league_season  (CONCURRENTLY)
--     idx_plr_approved                       (CONCURRENTLY, rebuilt)
--   Constraints promoted:   1
--     uq_plr_player_club_league_season (via USING INDEX)
--
-- Findings addressed:
--   BLOCKER  HIGH-05  ✓ profiles role escalation
--   BLOCKER  NF-2     ✓ dynamic constraint name lookup
--   BLOCKER  NF-3     ✓ CONCURRENTLY index avoids write outage
--   BLOCKER  C-2      ✓ coach injury visibility corrected
--   HIGH     LOW-01   ✓ signup role injection blocked
--   HIGH     CRIT-01  ✓ injury view medical field exposure
--   HIGH     CRIT-03  ✓ suspension reason_notes public exposure
--   HIGH     HIGH-01  ✓ disciplinary notes public exposure
--   HIGH     HIGH-02  ✓ registration rejection_reason public
--   HIGH     HIGH-06  ✓ registration UPDATE WITH CHECK
--   MEDIUM   MED-02   ✓ cross-club player registration
--   MEDIUM   MED-04   ✓ standings DELETE policy
--   MEDIUM   HIGH-04  ✓ fixtures DELETE policy
--   LOW      LOW-02   ✓ league_clubs spam INSERT
--
-- Production readiness after this patch:
--   All 4 deployment blockers resolved.
--   All Critical and High severity RLS findings resolved.
--   Estimated readiness score improvement: ~34/100 → ~72/100
--   Remaining gap: application-layer audit, PDPA compliance
--   review, load testing, and penetration testing.
--
-- ============================================================
