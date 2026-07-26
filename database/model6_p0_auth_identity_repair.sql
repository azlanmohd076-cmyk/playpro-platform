-- ============================================================
-- PlayPro Model 6 — P0 AUTH / IDENTITY INTEGRITY REPAIR
-- File: database/model6_p0_auth_identity_repair.sql
-- Author: Agent 5 (CTO Copilot)  |  Date: 2026-07-26
-- ============================================================
--
-- SCOPE
--   Repairs the signup -> profiles integrity chain.
--   This patch does NOT fix "Failed to fetch". That symptom is a
--   DNS/infrastructure failure (the Supabase project hostname does
--   not resolve). See PLAYPRO_P0_DIAGNOSIS_2026-07-26.md Section 1.
--   Run this patch AFTER the Supabase project is restored/recreated.
--
-- WHAT IS BROKEN (verified by static analysis of this repo)
--   B1. ENUM MISMATCH (fatal, silent)
--       user_role ENUM = developer, league_founder, league_admin,
--                        club_admin, coach, technical_assessor
--       Signup UI sends = player, coach, club_admin, league_admin, referee
--       -> 'player' and 'referee' are NOT valid enum values.
--       -> 'player' is also the JS default fallback (||'player').
--       -> Result: invalid input value for enum user_role (SQLSTATE 22P02)
--          on the most common signup path in the entire product.
--
--   B2. ROLE IS OVERWRITTEN AT SIGNUP
--       playpro_phase4_1_2_security_patch.sql replaced handle_new_user()
--       to HARDCODE role := 'club_admin', ignoring signup metadata.
--       -> Every coach / player / referee signup silently becomes club_admin.
--       -> This is a direct cause of "role router gagal" and
--          "data coach belum cukup lengkap".
--
--   B3. CLIENT UPSERT COLLIDES WITH THE ROLE-ESCALATION GUARD
--       handle_new_user() already INSERTs the profiles row.
--       The client then calls .upsert({...role}, {onConflict:'id'}),
--       which becomes an UPDATE. trg_prevent_role_escalation then
--       raises SQLSTATE 42501 because NEW.role <> OLD.role and the
--       caller is not a developer.
--       -> Profile write fails on EVERY signup.
--
-- DESIGN DECISION (security-preserving)
--   Role is owned by the SECURITY DEFINER trigger, sourced from signup
--   metadata but filtered through an explicit ALLOW-LIST.
--   The client NEVER writes profiles.role again.
--   trg_prevent_role_escalation is left INTACT (no security regression).
--
--   Self-serve roles (allowed at signup):
--     player, coach, club_admin, league_admin, referee
--   Privileged roles (NEVER self-assignable, must be granted by a developer):
--     developer, league_founder, technical_assessor
--     ('technical_assessor' = PCSAP certified assessor. Per the business
--      model this must be EARNED via the mock exam, never claimed.)
--
-- IDEMPOTENT: safe to re-run.
-- ============================================================


-- ============================================================
-- PART A — ENUM EXTENSION  (MUST RUN OUTSIDE A TRANSACTION)
-- ============================================================
-- ############################################################
-- #  AMARAN / WARNING — JANGAN LANGKAU / DO NOT SKIP         #
-- #                                                          #
-- #  Highlight PART A sahaja, tekan Run. TUNGGU siap.        #
-- #  Kemudian barulah highlight PART B dan tekan Run.        #
-- #                                                          #
-- #  Highlight PART A ONLY and Run it. WAIT. Then run PART B.#
-- ############################################################
--
-- SEBAB / WHY — ini BUKAN teori. Diuji pada PostgreSQL 17:
--
--   Jalankan A+B serentak pada DB yang ADA auth user yatim
--   berperanan 'player'/'referee':
--     ERROR: unsafe use of new value "player" of enum type user_role
--     -> keseluruhan patch ROLLBACK, backfill GAGAL, 0 profile dibaiki.
--
--   Jalankan A dahulu, kemudian B:
--     -> backfill berjaya: yatim1=player, yatim2=referee. OK.
--
-- PostgreSQL melarang penggunaan nilai enum baharu di dalam
-- transaksi yang sama yang menambahnya. Supabase SQL editor
-- membalut setiap "Run" dalam satu transaksi, jadi susunan ini
-- WAJIB dipatuhi.

ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'player';
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'referee';

-- ============================================================
-- ^^^ BERHENTI DI SINI. Tekan Run untuk PART A sahaja. ^^^
-- ^^^ STOP HERE. Run PART A, wait, THEN run PART B.    ^^^
-- ============================================================


-- ============================================================
-- PART B — TRIGGER, RPC, BACKFILL
-- ============================================================
BEGIN;

-- ------------------------------------------------------------
-- B.1  Role allow-list helper
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION playpro_safe_signup_role(p_role TEXT)
RETURNS user_role
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role TEXT := lower(trim(coalesce(p_role, '')));
BEGIN
  -- Malay / alias normalisation coming from the legacy UI.
  v_role := CASE v_role
    WHEN 'pemain'         THEN 'player'
    WHEN 'jurulatih'      THEN 'coach'
    WHEN 'pengurus_kelab' THEN 'club_admin'
    WHEN 'club_manager'   THEN 'club_admin'
    WHEN 'manager'        THEN 'club_admin'
    WHEN 'penganjur_liga' THEN 'league_admin'
    WHEN 'pengadil'       THEN 'referee'
    ELSE v_role
  END;

  -- ALLOW-LIST. Anything else (including 'developer',
  -- 'league_founder', 'technical_assessor', or garbage input)
  -- collapses to the safest default: 'player'.
  IF v_role IN ('player', 'coach', 'club_admin', 'league_admin', 'referee') THEN
    RETURN v_role::user_role;
  END IF;

  RETURN 'player'::user_role;
END;
$$;

COMMENT ON FUNCTION playpro_safe_signup_role(TEXT) IS
  'Maps untrusted signup metadata role -> a safe user_role. '
  'Privileged roles (developer, league_founder, technical_assessor) '
  'can never be obtained through signup. Replaces the blanket '
  'club_admin hardcode from Phase 4.1.2 (LOW-01) without reopening '
  'the privilege-escalation hole.';


-- ------------------------------------------------------------
-- B.2  Rebuild handle_new_user()
--      Fixes B2 (hardcoded club_admin) while keeping LOW-01 closed.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO profiles (id, full_name, email, role, phone)
  VALUES (
    NEW.id,
    COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'full_name'), ''), 'New User'),
    NEW.email,                                   -- satisfies email NOT NULL
    playpro_safe_signup_role(NEW.raw_user_meta_data->>'role'),
    NULLIF(trim(COALESCE(NEW.raw_user_meta_data->>'phone', '')), '')
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never let profile creation abort the auth signup itself.
  -- A missing profile is recoverable (see ensure_profile_after_signup);
  -- a failed auth signup is not.
  RAISE WARNING 'handle_new_user failed for %: % (%)', NEW.id, SQLERRM, SQLSTATE;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION handle_new_user() IS
  'Auth trigger: creates the profiles row at signup. Role is derived '
  'from signup metadata through playpro_safe_signup_role() allow-list. '
  'P0 repair 2026-07-26: restores real role assignment (player/coach/'
  'club_admin/league_admin/referee) that Phase 4.1.2 had flattened to '
  'club_admin, without allowing privileged self-assignment.';

-- Ensure the trigger is actually attached (it may be missing on a
-- rebuilt project — this is the #1 cause of "auth user exists but
-- profile row does not").
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();


-- ------------------------------------------------------------
-- B.3  ensure_profile_after_signup()
--      The ONLY write path the client should use post-signup.
--      Fixes B3: no client-side role write -> no 42501 collision.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION ensure_profile_after_signup(
  p_full_name TEXT DEFAULT NULL,
  p_phone     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid   UUID := auth.uid();
  v_email TEXT;
  v_meta  JSONB;
  v_row   profiles%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT email, raw_user_meta_data
    INTO v_email, v_meta
    FROM auth.users
   WHERE id = v_uid;

  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Auth user % not found', v_uid USING ERRCODE = 'P0002';
  END IF;

  -- Self-heal: create the row if the trigger never fired.
  INSERT INTO profiles (id, full_name, email, role, phone)
  VALUES (
    v_uid,
    COALESCE(NULLIF(trim(COALESCE(p_full_name, '')), ''),
             NULLIF(trim(COALESCE(v_meta->>'full_name', '')), ''),
             'New User'),
    v_email,
    playpro_safe_signup_role(v_meta->>'role'),
    NULLIF(trim(COALESCE(p_phone, COALESCE(v_meta->>'phone',''))), '')
  )
  ON CONFLICT (id) DO NOTHING;

  -- Patch NON-ROLE fields only. role is deliberately excluded so the
  -- trg_prevent_role_escalation guard is never tripped.
  UPDATE profiles
     SET full_name  = COALESCE(NULLIF(trim(COALESCE(p_full_name,'')), ''), full_name),
         phone      = COALESCE(NULLIF(trim(COALESCE(p_phone,'')), ''), phone),
         email      = COALESCE(email, v_email),
         updated_at = NOW()
   WHERE id = v_uid
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'ok',        true,
    'id',        v_row.id,
    'full_name', v_row.full_name,
    'email',     v_row.email,
    'role',      v_row.role,
    'phone',     v_row.phone
  );
END;
$$;

REVOKE ALL   ON FUNCTION ensure_profile_after_signup(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ensure_profile_after_signup(TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION ensure_profile_after_signup(TEXT, TEXT) IS
  'Idempotent post-signup profile guarantee. Creates the profiles row '
  'if the auth trigger did not, then patches non-role fields. Returns '
  'the authoritative role for the role router. Client must call this '
  'INSTEAD OF writing to profiles directly.';


-- ------------------------------------------------------------
-- B.4  get_my_profile() — single source of truth for the router
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_my_profile()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object(
    'id', p.id, 'full_name', p.full_name, 'email', p.email,
    'role', p.role, 'phone', p.phone, 'is_active', p.is_active
  ) END
  FROM profiles p WHERE p.id = auth.uid();
$$;

REVOKE ALL   ON FUNCTION get_my_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_my_profile() TO authenticated;


-- ------------------------------------------------------------
-- B.5  BACKFILL — repair accounts already broken in production
-- ------------------------------------------------------------
-- B.5.1 auth users that never got a profiles row
INSERT INTO profiles (id, full_name, email, role, phone)
SELECT
  u.id,
  COALESCE(NULLIF(trim(u.raw_user_meta_data->>'full_name'), ''),
           split_part(u.email, '@', 1)),
  u.email,
  playpro_safe_signup_role(u.raw_user_meta_data->>'role'),
  NULLIF(trim(COALESCE(u.raw_user_meta_data->>'phone', '')), '')
FROM auth.users u
LEFT JOIN profiles p ON p.id = u.id
WHERE p.id IS NULL
  AND u.email IS NOT NULL
ON CONFLICT (id) DO NOTHING;

-- B.5.2 profiles with a NULL/blank email (repair from auth.users)
UPDATE profiles p
   SET email = u.email, updated_at = NOW()
  FROM auth.users u
 WHERE u.id = p.id
   AND (p.email IS NULL OR trim(p.email) = '')
   AND u.email IS NOT NULL;

-- B.5.3 OPTIONAL — reclaim roles flattened to club_admin by Phase 4.1.2.
--       Only touches users whose signup metadata clearly stated a
--       different self-serve role. Review the SELECT before running
--       the UPDATE.
--
-- SELECT p.id, p.email, p.role AS current_role,
--        playpro_safe_signup_role(u.raw_user_meta_data->>'role') AS intended_role
--   FROM profiles p JOIN auth.users u ON u.id = p.id
--  WHERE p.role = 'club_admin'
--    AND playpro_safe_signup_role(u.raw_user_meta_data->>'role') <> 'club_admin';
--
-- UPDATE profiles p
--    SET role = playpro_safe_signup_role(u.raw_user_meta_data->>'role'),
--        updated_at = NOW()
--   FROM auth.users u
--  WHERE u.id = p.id
--    AND p.role = 'club_admin'
--    AND playpro_safe_signup_role(u.raw_user_meta_data->>'role') <> 'club_admin';
--
-- NOTE: trg_prevent_role_escalation only blocks a user changing THEIR OWN
-- role (NEW.id = auth.uid()). Running this as the SQL-editor owner /
-- service role is not blocked.

COMMIT;


-- ============================================================
-- PART C — VERIFICATION (run after PART B; all must pass)
-- ============================================================
-- C.1 enum now contains player + referee
-- SELECT enumlabel FROM pg_enum
--  WHERE enumtypid = 'user_role'::regtype ORDER BY enumsortorder;

-- C.2 signup trigger is attached
-- SELECT tgname, tgenabled FROM pg_trigger
--  WHERE tgrelid = 'auth.users'::regclass AND NOT tgisinternal;

-- C.3 role mapping behaves
-- SELECT playpro_safe_signup_role('player')             AS should_be_player,
--        playpro_safe_signup_role('referee')            AS should_be_referee,
--        playpro_safe_signup_role('developer')          AS should_be_player,
--        playpro_safe_signup_role('technical_assessor') AS should_be_player,
--        playpro_safe_signup_role(NULL)                 AS should_be_player;

-- C.4 zero orphan auth users
-- SELECT count(*) AS orphan_auth_users
--   FROM auth.users u LEFT JOIN profiles p ON p.id = u.id
--  WHERE p.id IS NULL;

-- C.5 zero profiles missing email
-- SELECT count(*) AS profiles_missing_email
--   FROM profiles WHERE email IS NULL OR trim(email) = '';

-- C.6 escalation guard still armed (must return 1 row)
-- SELECT tgname FROM pg_trigger
--  WHERE tgrelid = 'profiles'::regclass
--    AND tgname = 'trg_prevent_role_escalation';
-- ============================================================
