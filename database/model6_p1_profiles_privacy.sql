-- ============================================================
-- PlayPro P1 — TUTUP KEBOCORAN EMEL PADA JADUAL profiles
-- File: database/model6_p1_profiles_privacy.sql
-- Tarikh: 2026-07-26
-- ============================================================
--
-- MASALAH (disahkan secara hidup pada PostgreSQL 17)
--   database/01_phase1_core_schema.sql:1595
--
--     CREATE POLICY "profiles: public read"
--       ON profiles FOR SELECT
--       USING (true);          <-- SESIAPA SAHAJA, termasuk anon
--
--   Diuji sebagai pengguna TANPA login (RLS dikuatkuasakan):
--     SELECT full_name, email, role FROM profiles;
--     -> 15 baris dipulangkan, TERMASUK emel penuh setiap pengguna.
--
--   Kunci anon PlayPro tertanam dalam 10 fail HTML awam. Sesiapa
--   boleh ambil kunci itu dan tarik SELURUH senarai emel pengguna
--   dengan satu permintaan REST:
--     GET /rest/v1/profiles?select=email,full_name,role
--
--   Ini kebocoran data peribadi (PDPA Malaysia) dan senarai emel
--   siap untuk spam/phishing.
--
-- KENAPA IA WUJUD
--   Aplikasi memang perlu paparkan nama + peranan secara awam
--   (carian pemain, kad jurulatih awam). Tetapi 'USING (true)'
--   mendedahkan SEMUA lajur, bukan hanya yang sepatutnya awam.
--   RLS PostgreSQL menapis BARIS, bukan LAJUR.
--
-- PENYELESAIAN
--   1. Ganti policy awam dengan policy yang hanya benarkan
--      pengguna melihat baris SENDIRI secara penuh.
--   2. Sediakan VIEW awam yang hanya dedahkan lajur selamat
--      (id, full_name, role, avatar_url) — tiada emel, tiada telefon.
--   3. Kekalkan akses penuh untuk developer.
--
-- KESAN KEPADA APLIKASI
--   Kod yang membaca 'profiles' untuk paparan awam mesti bertukar
--   kepada 'public_profiles'. Cari dalam kod:
--     .from('profiles').select(...)
--   Jika ia untuk paparan orang lain -> tukar ke 'public_profiles'.
--   Jika ia untuk diri sendiri -> biarkan (policy 'lihat sendiri' cukup).
--
-- IDEMPOTENT: selamat dijalankan berulang kali.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Buang policy bocor
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "profiles: public read" ON profiles;

-- ------------------------------------------------------------
-- 2. Pengguna hanya nampak baris sendiri; developer nampak semua
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "profiles: read own or developer" ON profiles;
CREATE POLICY "profiles: read own or developer"
  ON profiles FOR SELECT
  USING (
    id = auth.uid()
    OR get_my_role() = 'developer'
  );

-- ------------------------------------------------------------
-- 3. VIEW awam — hanya lajur yang memang patut awam
--    security_invoker = false (default) supaya view ini
--    memintas RLS jadual asas secara terkawal.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW public_profiles AS
SELECT
  id,
  full_name,
  role,
  avatar_url,
  is_active
FROM profiles
WHERE is_active = true;

COMMENT ON VIEW public_profiles IS
  'Paparan awam profil: TIADA emel, TIADA telefon, TIADA IC. '
  'Guna view ini untuk carian pemain/jurulatih dan kad awam. '
  'Menggantikan policy "profiles: public read" yang membocorkan emel.';

GRANT SELECT ON public_profiles TO anon, authenticated;

-- ------------------------------------------------------------
-- 4. RPC untuk cari pengguna mengikut peranan (ganti carian terus)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION search_public_profiles(
  p_role   TEXT DEFAULT NULL,
  p_query  TEXT DEFAULT NULL,
  p_limit  INT  DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  full_name TEXT,
  role TEXT,
  avatar_url TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT p.id, p.full_name, p.role::text, p.avatar_url
  FROM profiles p
  WHERE p.is_active = true
    AND (p_role  IS NULL OR p.role::text = lower(trim(p_role)))
    AND (p_query IS NULL OR p.full_name ILIKE '%'||trim(p_query)||'%')
  ORDER BY p.full_name
  LIMIT LEAST(GREATEST(COALESCE(p_limit,20),1),100);
$$;

REVOKE ALL   ON FUNCTION search_public_profiles(TEXT,TEXT,INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION search_public_profiles(TEXT,TEXT,INT) TO anon, authenticated;

COMMENT ON FUNCTION search_public_profiles(TEXT,TEXT,INT) IS
  'Carian profil selamat. Hanya memulangkan lajur awam. '
  'Emel dan telefon tidak pernah didedahkan.';

COMMIT;


-- ============================================================
-- PENGESAHAN — jalankan selepas patch
-- ============================================================
-- 1) Emel TIDAK lagi bocor kepada anon:
--    (jalankan sebagai peranan anon / tanpa login)
--    SELECT count(*) FROM profiles;        -- sepatutnya 0
--    SELECT count(*) FROM public_profiles; -- sepatutnya > 0
--
-- 2) Pengguna masih nampak diri sendiri:
--    SELECT email FROM profiles WHERE id = auth.uid();  -- 1 baris
--
-- 3) Carian masih berfungsi:
--    SELECT * FROM search_public_profiles('coach', NULL, 10);
--
-- 4) Tiada lajur sensitif dalam view:
--    SELECT column_name FROM information_schema.columns
--     WHERE table_name='public_profiles';
--    -- mesti TIADA: email, phone, ic_number, date_of_birth
-- ============================================================


-- ============================================================
-- BAHAGIAN 2 — TUTUP KEBOCORAN DALAM RPC "AWAM" SEDIA ADA
-- ============================================================
-- MASALAH:
--   get_public_coach_profile() (model6_public_coach_profile_rpc.sql)
--   ialah SECURITY DEFINER dan diberi GRANT kepada 'anon'.
--   Ia memulangkan:
--       email, ic_number, passport_number, date_of_birth
--   Sesiapa sahaja boleh panggil dengan mana-mana UUID jurulatih
--   dan dapat NOMBOR IC serta NOMBOR PASPORT mereka.
--
--   Ini lebih teruk daripada kebocoran emel: IC ialah pengenalan
--   diri rasmi Malaysia dan tertakluk kepada PDPA.
--
-- PEMBETULAN:
--   Buang lajur sensitif daripada balasan awam. Nama, peranan,
--   avatar dan kewarganegaraan sudah memadai untuk kad awam.
-- ============================================================

CREATE OR REPLACE FUNCTION get_public_coach_profile(p_profile_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_profile  JSONB;
  v_assessor JSONB;
BEGIN
  SELECT jsonb_build_object(
    'id',          p.id,
    'full_name',   p.full_name,
    'role',        p.role,
    'avatar_url',  p.avatar_url,
    'nationality', COALESCE(p.nationality, 'Malaysian')
    -- SENGAJA DIBUANG: email, ic_number, passport_number, date_of_birth
    -- Data peribadi tidak boleh didedahkan melalui endpoint awam.
  )
  INTO v_profile
  FROM profiles p
  WHERE p.id = p_profile_id
    AND p.role = 'coach';

  IF v_profile IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'COACH_PROFILE_NOT_FOUND');
  END IF;

  SELECT jsonb_build_object(
    'profile_id',          ca.profile_id,
    'license_type',        ca.license_type,
    'status',              ca.status,
    'trust_score',         ca.trust_score,
    'max_attribute_score', ca.max_attribute_score,
    'metadata',            COALESCE(ca.metadata, '{}'::jsonb)
  )
  INTO v_assessor
  FROM certified_assessors ca
  WHERE ca.profile_id = p_profile_id;

  RETURN jsonb_build_object(
    'success',  true,
    'profile',  v_profile,
    'assessor', COALESCE(v_assessor, '{}'::jsonb)
  );
END;
$$;

REVOKE ALL   ON FUNCTION get_public_coach_profile(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_public_coach_profile(UUID) TO anon, authenticated;

COMMENT ON FUNCTION get_public_coach_profile(UUID) IS
  'Kad jurulatih awam. P1 2026-07-26: emel, IC, nombor pasport dan '
  'tarikh lahir DIBUANG daripada balasan (kebocoran PDPA).';
