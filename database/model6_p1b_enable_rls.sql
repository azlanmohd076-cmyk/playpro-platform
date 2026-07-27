-- ============================================================
-- PlayPro P1-B — DAYAKAN RLS (ROW LEVEL SECURITY)
-- File: database/model6_p1b_enable_rls.sql
-- Tarikh: 2026-07-26
-- KEUTAMAAN: KRITIKAL — jalankan SEGERA
-- ============================================================
--
-- MASALAH (disahkan secara langsung pada produksi)
--   Policy RLS wujud, TETAPI RLS tidak pernah DIDAYAKAN pada
--   jadual-jadual utama. Dalam PostgreSQL, policy tidak berkuat
--   kuasa langsung selagi jadual tidak ENABLE ROW LEVEL SECURITY.
--
--   Ini sebabnya patch P1 (privacy) nampak "Success" tetapi emel
--   masih bocor — policy baharu dicipta, tetapi diabaikan.
--
--   Bukti ujian pada produksi 2026-07-26, tanpa log masuk,
--   hanya guna anon key yang ada dalam HTML awam:
--
--     GET   /rest/v1/profiles?select=email      -> 29 emel penuh
--     PATCH /rest/v1/profiles?id=eq.<sesiapa>   -> HTTP 204 BERJAYA
--             {"full_name":"DICEROBOH ANON"}
--
--   Nama pengguna sebenar berjaya ditukar oleh pelawat tanpa akaun.
--   (Nama tersebut telah dipulihkan semula kepada asal.)
--
--   Jadual terjejas: profiles, players, clubs, organizations
--
--   Ini bermakna sesiapa sahaja boleh:
--     - baca semua emel pengguna
--     - tukar nama/data mana-mana pemain
--     - ubah maklumat mana-mana kelab
--     - padam rekod
--
-- KENAPA INI BERLAKU
--   Fail 01_phase1_core_schema.sql ada baris ENABLE ROW LEVEL
--   SECURITY, tetapi bahagian itu nampaknya tidak pernah berjaya
--   dijalankan pada database ini — atau RLS dimatikan kemudian
--   semasa debugging dan tidak dihidupkan semula.
--
-- IDEMPOTENT: selamat dijalankan berulang kali.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Dayakan RLS pada jadual teras
-- ------------------------------------------------------------
ALTER TABLE profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE players       ENABLE ROW LEVEL SECURITY;
ALTER TABLE clubs         ENABLE ROW LEVEL SECURITY;

-- organizations wujud dalam Model 6; dayakan jika ada
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='organizations') THEN
    EXECUTE 'ALTER TABLE organizations ENABLE ROW LEVEL SECURITY';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 2. Pastikan policy SELECT profiles adalah yang selamat
--    (patch P1 sudah cipta, ini cuma jaring keselamatan)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "profiles: public read" ON profiles;

DROP POLICY IF EXISTS "profiles: read own or developer" ON profiles;
CREATE POLICY "profiles: read own or developer"
  ON profiles FOR SELECT
  USING (
    id = auth.uid()
    OR get_my_role() = 'developer'
  );

-- ------------------------------------------------------------
-- 3. organizations perlu policy baca; tanpa policy, RLS akan
--    menyekat SEMUA bacaan dan memecahkan app.
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='organizations') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='organizations' AND cmd='SELECT'
    ) THEN
      EXECUTE 'CREATE POLICY "organizations: public read" ON organizations FOR SELECT USING (true)';
    END IF;
  END IF;
END $$;

COMMIT;


-- ============================================================
-- PENGESAHAN — jalankan selepas patch
-- ============================================================
-- 1) Semua jadual teras mesti relrowsecurity = true:
--
--    SELECT relname AS jadual, relrowsecurity AS rls_aktif
--      FROM pg_class
--     WHERE relname IN ('profiles','players','clubs','organizations')
--       AND relkind = 'r'
--     ORDER BY relname;
--
-- 2) profiles mesti ada policy SELECT yang selamat:
--
--    SELECT policyname, cmd FROM pg_policies
--     WHERE tablename='profiles' ORDER BY cmd;
--
-- 3) Ujian sebenar dari luar (tanpa login):
--    GET /rest/v1/profiles?select=email   -> sepatutnya []
--    GET /rest/v1/public_profiles         -> sepatutnya ada data
-- ============================================================
