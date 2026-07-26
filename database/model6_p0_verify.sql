-- ============================================================
-- PlayPro P0 — SKRIP PENGESAHAN / VERIFICATION SCRIPT
-- Jalankan SELEPAS model6_p0_auth_identity_repair.sql
-- Read-only. Tidak mengubah apa-apa data.
--
-- Cara guna: copy-paste seluruh fail ini ke Supabase SQL Editor,
-- tekan Run. Semua baris mesti menunjukkan 'LULUS'.
-- ============================================================

SELECT '=== PENGESAHAN P0 PLAYPRO ===' AS tajuk;

-- ------------------------------------------------------------
-- 1. ENUM mesti ada 'player' dan 'referee'
-- ------------------------------------------------------------
SELECT
  '1. ENUM user_role' AS ujian,
  CASE WHEN bool_and(ada) THEN 'LULUS' ELSE 'GAGAL — jalankan PART A' END AS keputusan,
  (SELECT string_agg(enumlabel, ', ' ORDER BY enumsortorder)
     FROM pg_enum WHERE enumtypid='user_role'::regtype) AS butiran
FROM (
  SELECT EXISTS(SELECT 1 FROM pg_enum
                 WHERE enumtypid='user_role'::regtype AND enumlabel='player') AS ada
  UNION ALL
  SELECT EXISTS(SELECT 1 FROM pg_enum
                 WHERE enumtypid='user_role'::regtype AND enumlabel='referee')
) t;

-- ------------------------------------------------------------
-- 2. Trigger signup mesti terpasang dan aktif
-- ------------------------------------------------------------
SELECT
  '2. Trigger on_auth_user_created' AS ujian,
  CASE WHEN count(*)=1 THEN 'LULUS' ELSE 'GAGAL — trigger hilang' END AS keputusan,
  COALESCE(string_agg(tgname,', '),'(tiada)') AS butiran
FROM pg_trigger
WHERE tgrelid='auth.users'::regclass AND NOT tgisinternal
  AND tgname='on_auth_user_created' AND tgenabled='O';

-- ------------------------------------------------------------
-- 3. Ketiga-tiga fungsi P0 mesti wujud
-- ------------------------------------------------------------
SELECT
  '3. Fungsi RPC P0' AS ujian,
  CASE WHEN count(*)=3 THEN 'LULUS' ELSE 'GAGAL — jalankan PART B' END AS keputusan,
  count(*)||' daripada 3: '||COALESCE(string_agg(proname,', '),'') AS butiran
FROM pg_proc
WHERE proname IN ('playpro_safe_signup_role','ensure_profile_after_signup','get_my_profile');

-- ------------------------------------------------------------
-- 4. Pemetaan role — keselamatan allow-list
-- ------------------------------------------------------------
SELECT
  '4. Allow-list role' AS ujian,
  CASE WHEN playpro_safe_signup_role('player')::text='player'
        AND playpro_safe_signup_role('referee')::text='referee'
        AND playpro_safe_signup_role('coach')::text='coach'
        AND playpro_safe_signup_role('jurulatih')::text='coach'
        AND playpro_safe_signup_role('developer')::text='player'
        AND playpro_safe_signup_role('technical_assessor')::text='player'
        AND playpro_safe_signup_role(NULL)::text='player'
       THEN 'LULUS' ELSE 'GAGAL' END AS keputusan,
  'developer->'||playpro_safe_signup_role('developer')::text||
  ', jurulatih->'||playpro_safe_signup_role('jurulatih')::text AS butiran;

-- ------------------------------------------------------------
-- 5. Tiada auth user yatim
-- ------------------------------------------------------------
SELECT
  '5. Auth user tanpa profile' AS ujian,
  CASE WHEN count(*)=0 THEN 'LULUS' ELSE 'GAGAL — jalankan backfill B.5.1' END AS keputusan,
  count(*)||' yatim' AS butiran
FROM auth.users u LEFT JOIN profiles p ON p.id=u.id
WHERE p.id IS NULL AND u.email IS NOT NULL;

-- ------------------------------------------------------------
-- 6. Tiada profile tanpa emel
-- ------------------------------------------------------------
SELECT
  '6. Profile tanpa emel' AS ujian,
  CASE WHEN count(*)=0 THEN 'LULUS' ELSE 'GAGAL — jalankan backfill B.5.2' END AS keputusan,
  count(*)||' rekod' AS butiran
FROM profiles WHERE email IS NULL OR trim(email)='';

-- ------------------------------------------------------------
-- 7. Guard naik taraf role MESTI kekal (tiada regresi keselamatan)
-- ------------------------------------------------------------
SELECT
  '7. Guard trg_prevent_role_escalation' AS ujian,
  CASE WHEN count(*)=1 THEN 'LULUS' ELSE 'GAGAL — RISIKO KESELAMATAN' END AS keputusan,
  CASE WHEN count(*)=1 THEN 'masih terpasang' ELSE 'HILANG' END AS butiran
FROM pg_trigger
WHERE tgrelid='profiles'::regclass AND tgname='trg_prevent_role_escalation';

-- ------------------------------------------------------------
-- 8. Taburan role semasa (maklumat — bukan lulus/gagal)
-- ------------------------------------------------------------
SELECT
  '8. Taburan role' AS ujian,
  'MAKLUMAT' AS keputusan,
  COALESCE(string_agg(role::text||'='||bil, ', ' ORDER BY bil DESC),'(kosong)') AS butiran
FROM (SELECT role, count(*) AS bil FROM profiles GROUP BY role) t;

-- ------------------------------------------------------------
-- 9. Akaun yang role-nya mungkin dileperkan jadi club_admin
--    (jika >0, pertimbangkan backfill B.5.3)
-- ------------------------------------------------------------
SELECT
  '9. Role perlu dipulihkan' AS ujian,
  CASE WHEN count(*)=0 THEN 'LULUS' ELSE 'PERHATIAN — lihat B.5.3' END AS keputusan,
  count(*)||' akaun club_admin yang asalnya lain' AS butiran
FROM profiles p JOIN auth.users u ON u.id=p.id
WHERE p.role='club_admin'
  AND playpro_safe_signup_role(u.raw_user_meta_data->>'role')::text <> 'club_admin';

SELECT '=== TAMAT — semua mesti LULUS sebelum teruskan ===' AS tajuk;
