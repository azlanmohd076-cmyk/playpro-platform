-- ============================================================
-- PlayPro P1-C — BUANG POLICY "TERBUKA" YANG MEMBOCORKAN DATA
-- File: database/model6_p1c_purge_open_policies.sql
-- Tarikh: 2026-07-26
-- KEUTAMAAN: KRITIKAL
-- ============================================================
--
-- MASALAH (disahkan pada produksi)
--   RLS SUDAH aktif (relrowsecurity = true) dan policy selamat
--   sudah dipasang. TETAPI emel masih bocor dan sesiapa masih
--   boleh menulis.
--
--   Punca: bilangan policy tidak sepadan dengan fail migrasi.
--     profiles : dijangka 5, sebenar 6   (+1 tidak dikenali)
--     players  : dijangka 3, sebenar 6   (+3 tidak dikenali)
--
--   Policy RLS bersifat PERMISSIVE — ia digabung dengan OR,
--   bukan AND. Satu policy `USING (true)` membatalkan SEMUA
--   policy ketat yang lain.
--
--   Bukti pada simulasi:
--     tambah 1 policy USING(true)  -> anon nampak semua baris
--     buang policy itu             -> anon nampak 0 baris
--
--   Policy sebegini biasanya ditambah semasa debugging
--   ("Enable read access for all users" ialah template lalai
--   dalam UI Supabase) dan terlupa dibuang.
--
-- APA YANG PATCH INI BUAT
--   Ia TIDAK membuang policy secara membabi buta. Ia hanya
--   membuang policy yang syaratnya benar-benar terbuka, iaitu
--   qual/with_check bersamaan 'true'.
--
--   Policy yang menyebut auth.uid(), get_my_role(), is_club_admin()
--   atau apa-apa syarat sebenar akan DIKEKALKAN.
--
--   PENGECUALIAN: policy SELECT terbuka pada 'clubs' dan
--   'organizations' dikekalkan, kerana senarai kelab/organisasi
--   memang sepatutnya boleh dilihat awam dan tidak mengandungi
--   data peribadi.
--
-- IDEMPOTENT: selamat dijalankan berulang kali.
-- ============================================================

-- ------------------------------------------------------------
-- BAHAGIAN 1 — LAPORAN: apa yang akan dibuang
--              (jalankan dahulu untuk melihat)
-- ------------------------------------------------------------
SELECT
  tablename                                   AS jadual,
  policyname                                  AS policy_akan_dibuang,
  cmd                                         AS operasi,
  COALESCE(qual,'-')                          AS syarat_baca,
  COALESCE(with_check,'-')                    AS syarat_tulis
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('profiles','players','clubs','organizations')
  AND (
        COALESCE(btrim(qual),'')       = 'true'
     OR COALESCE(btrim(with_check),'') = 'true'
      )
  -- kekalkan bacaan awam yang sah untuk kelab & organisasi
  AND NOT (tablename IN ('clubs','organizations') AND cmd = 'SELECT')
ORDER BY tablename, cmd, policyname;


-- ------------------------------------------------------------
-- BAHAGIAN 2 — BUANG
-- ------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  n INT := 0;
BEGIN
  FOR r IN
    SELECT tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('profiles','players','clubs','organizations')
      AND (
            COALESCE(btrim(qual),'')       = 'true'
         OR COALESCE(btrim(with_check),'') = 'true'
          )
      AND NOT (tablename IN ('clubs','organizations') AND cmd = 'SELECT')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, r.tablename);
    RAISE NOTICE 'DIBUANG: %.% ', r.tablename, r.policyname;
    n := n + 1;
  END LOOP;

  IF n = 0 THEN
    RAISE NOTICE 'Tiada policy terbuka dijumpai.';
  ELSE
    RAISE NOTICE 'Jumlah policy terbuka dibuang: %', n;
  END IF;
END $$;


-- ------------------------------------------------------------
-- BAHAGIAN 3 — PASTIKAN POLICY SELAMAT WUJUD
--              (jaring keselamatan jika tersilap terbuang)
-- ------------------------------------------------------------
BEGIN;

-- profiles: baca sendiri sahaja
DROP POLICY IF EXISTS "profiles: read own or developer" ON profiles;
CREATE POLICY "profiles: read own or developer"
  ON profiles FOR SELECT
  USING (id = auth.uid() OR get_my_role() = 'developer');

-- profiles: kemas kini sendiri (role dijaga oleh trigger)
DROP POLICY IF EXISTS "profiles: update own non-role fields" ON profiles;
CREATE POLICY "profiles: update own non-role fields"
  ON profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "profiles: developer update any" ON profiles;
CREATE POLICY "profiles: developer update any"
  ON profiles FOR UPDATE
  USING (get_my_role() = 'developer');

-- profiles: insert sendiri (diperlukan oleh trigger signup)
DROP POLICY IF EXISTS "profiles: insert own" ON profiles;
CREATE POLICY "profiles: insert own"
  ON profiles FOR INSERT
  WITH CHECK (id = auth.uid());

-- profiles: padam - developer sahaja
DROP POLICY IF EXISTS "profiles: developer delete" ON profiles;
CREATE POLICY "profiles: developer delete"
  ON profiles FOR DELETE
  USING (get_my_role() = 'developer');

-- players: bacaan awam kekal (data pemain memang awam),
-- tetapi tulis mesti terhad kepada admin kelab.
DROP POLICY IF EXISTS "players: public read" ON players;
CREATE POLICY "players: public read"
  ON players FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "players: club admin insert" ON players;
CREATE POLICY "players: club admin insert"
  ON players FOR INSERT
  WITH CHECK (
    get_my_role() IN ('developer','club_admin')
    AND (club_id IS NULL OR is_club_admin(club_id))
  );

DROP POLICY IF EXISTS "players: club admin or developer update" ON players;
CREATE POLICY "players: club admin or developer update"
  ON players FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
  );

COMMIT;


-- ------------------------------------------------------------
-- BAHAGIAN 4 — PENGESAHAN
-- ------------------------------------------------------------
SELECT
  tablename  AS jadual,
  policyname AS policy_tinggal,
  cmd        AS operasi,
  CASE
    WHEN COALESCE(btrim(qual),'')='true' OR COALESCE(btrim(with_check),'')='true'
      THEN 'TERBUKA'
    ELSE 'selamat'
  END        AS status
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('profiles','players','clubs','organizations')
ORDER BY tablename, cmd, policyname;

-- Selepas ini, ujian dari luar TANPA login sepatutnya:
--   GET   /rest/v1/profiles?select=email  -> []
--   PATCH /rest/v1/profiles?id=eq.<x>     -> 0 baris diubah
--   GET   /rest/v1/public_profiles        -> ada data (tiada emel)
