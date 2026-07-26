-- ============================================================
-- PlayPro P0-B — PASANG SEMULA GUARD NAIK TARAF ROLE
-- File: database/model6_p0b_escalation_guard.sql
-- Tarikh: 2026-07-26
-- KEUTAMAAN: KRITIKAL — jalankan SEGERA
-- ============================================================
--
-- MASALAH (disahkan secara langsung pada produksi)
--   Guard trg_prevent_role_escalation TIDAK WUJUD dalam database
--   produksi. Patch playpro_phase4_1_2_security_patch.sql nampaknya
--   tidak pernah dijalankan sepenuhnya.
--
--   Bukti — ujian sebenar pada produksi 2026-07-26:
--     1. Daftar akaun biasa (role = player)
--     2. Log masuk, dapat token authenticated
--     3. PATCH /rest/v1/profiles?id=eq.<saya> {"role":"developer"}
--     4. HTTP 200 -> role bertukar kepada 'developer'
--
--   Sesiapa yang mendaftar akaun PlayPro boleh menjadikan diri
--   mereka DEVELOPER dengan satu permintaan HTTP.
--
--   Peranan developer memberi akses kepada 10+ policy RLS termasuk:
--     - baca/tulis SEMUA profil
--     - padam profil
--     - kemas kini mana-mana pemain, kelab, liga
--     - akses master_benchmarks dan data sensitif lain
--
--   (Akaun ujian yang digunakan sudah diturunkan semula kepada
--    'player'. Tiada akaun sebenar terjejas — hanya 1 developer
--    sah kekal.)
--
-- KENAPA PATCH P0 TIDAK MENUTUPNYA
--   Patch P0 mengunci laluan SIGNUP (role datang dari allow-list
--   di dalam trigger). Ia tidak menyentuh laluan UPDATE, kerana
--   andaian asalnya guard Phase 4.1.2 sudah terpasang. Andaian itu
--   salah untuk database ini.
--
-- IDEMPOTENT: selamat dijalankan berulang kali.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Fungsi guard
--    Menyekat pengguna daripada menukar role SENDIRI.
--    Developer masih boleh menukar role orang lain.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION prevent_role_self_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_my_role TEXT;
BEGIN
  -- Tiada perubahan role -> benarkan (kemas kini nama/telefon/avatar)
  IF NEW.role IS NOT DISTINCT FROM OLD.role THEN
    RETURN NEW;
  END IF;

  -- Tiada sesi (service_role / trigger dalaman) -> benarkan
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  -- Baca role SEMASA pemanggil terus dari jadual.
  -- Tidak guna get_my_role() supaya tidak terikat pada baris
  -- yang sedang dikemas kini.
  SELECT role::text INTO v_my_role
    FROM profiles
   WHERE id = auth.uid();

  -- Developer boleh menukar role sesiapa
  IF v_my_role = 'developer' THEN
    RETURN NEW;
  END IF;

  -- Bukan developer + cuba tukar role -> SEKAT
  RAISE EXCEPTION
    'Permission denied: anda tidak boleh menukar peranan akaun. '
    'Hubungi pentadbir PlayPro untuk perubahan peranan.'
    USING ERRCODE = '42501';
END;
$$;

COMMENT ON FUNCTION prevent_role_self_escalation() IS
  'Menyekat naik taraf peranan sendiri. Dipasang semula 2026-07-26 '
  'selepas disahkan HILANG dalam produksi — sesiapa boleh menjadikan '
  'diri developer melalui PATCH /rest/v1/profiles.';

-- ------------------------------------------------------------
-- 2. Pasang trigger
-- ------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prevent_role_escalation ON profiles;
CREATE TRIGGER trg_prevent_role_escalation
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_role_self_escalation();

-- ------------------------------------------------------------
-- 3. Pertahanan lapisan kedua — policy RLS
--    Trigger ialah guard utama. Policy ini memastikan pengguna
--    hanya boleh mengemas kini baris sendiri.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "profiles: update own or developer"      ON profiles;
DROP POLICY IF EXISTS "profiles: update own non-role fields"   ON profiles;
DROP POLICY IF EXISTS "profiles: developer update any"         ON profiles;

CREATE POLICY "profiles: update own non-role fields"
  ON profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY "profiles: developer update any"
  ON profiles FOR UPDATE
  USING (get_my_role() = 'developer');

COMMIT;


-- ============================================================
-- PENGESAHAN — jalankan selepas patch
-- ============================================================
-- 1) Trigger terpasang (mesti 1 baris):
--    SELECT tgname FROM pg_trigger
--     WHERE tgrelid='profiles'::regclass
--       AND tgname='trg_prevent_role_escalation';
--
-- 2) Ujian sebenar dari aplikasi:
--    - log masuk sebagai akaun biasa
--    - cuba PATCH /rest/v1/profiles?id=eq.<diri> {"role":"developer"}
--    - JANGKAAN: HTTP 403 / 400 dengan kod 42501
--
-- 3) Senarai developer (semak tiada yang mencurigakan):
--    SELECT full_name, email, role FROM profiles WHERE role='developer';
-- ============================================================
