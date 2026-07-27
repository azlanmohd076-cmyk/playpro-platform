# Arahan Git Push — PlayPro P0 + P1

**Tarikh:** 2026-07-26
**Status database:** Semua patch sudah dijalankan dan disahkan
**Status kod:** 5 commit siap tempatan, menunggu push

---

## PENTING — baca dahulu

Semua kerja ini ada dalam **workspace saya**, bukan dalam komputer bos.
Bos tidak boleh terus `git push` dari VS Code kerana fail-fail ini belum
wujud di sisi bos.

Ada **dua cara**. Pilih satu.

---

# CARA A — Bos salin fail secara manual (paling mudah difahami)

Sesuai jika bos mahu lihat dan sahkan setiap fail sebelum masuk repo.

## Fail BAHARU yang perlu dicipta

Cipta fail-fail ini dalam projek bos, salin kandungan dari chat:

```
database/model6_p0_auth_identity_repair.sql
database/model6_p0_verify.sql
database/model6_p0b_escalation_guard.sql
database/model6_p1_profiles_privacy.sql
database/model6_p1b_enable_rls.sql
database/model6_p1c_purge_open_policies.sql
public/p0_auth_doctor.html
src/modules/auth/auth-session.service.js
public/src/modules/auth/auth-session.service.js
tests/auth-session.test.js
```

## Fail yang perlu DIUBAH

```
public/index.html                            (buang 4 tulisan role, error jujur)
public/model6-loader.js                      (daftar auth-session.service.js)
js/shared_dashboard_components.js            (baiki SyntaxError b=18 -> b:18)
src/modules/search/role-search-router.js     (buang emel/IC dari carian)
public/src/modules/search/role-search-router.js
```

Kemudian:

```bash
git add -A
git commit -m "P0+P1: repair auth identity, close PDPA leak, enable RLS"
git push origin main
```

---

# CARA B — Saya beri patch, bos apply (lebih tepat)

Ini cara yang saya syorkan. Tiada risiko tersalah salin.

## Langkah 1 — minta saya jana fail patch

Cakap kepada saya: **"jana patch file"**

Saya akan hasilkan satu fail `playpro-p0-p1.patch` dalam workspace.
Bos muat turun fail itu.

## Langkah 2 — apply dalam repo bos

```bash
cd /path/ke/playpro-platform
git checkout main
git pull origin main

git apply --check playpro-p0-p1.patch    # semak dahulu, tiada perubahan
git apply playpro-p0-p1.patch            # apply sebenar

git status                                # lihat apa yang berubah
```

## Langkah 3 — commit & push

```bash
git add -A
git commit -m "P0+P1: repair auth identity, close PDPA leak, enable RLS

- Fix enum missing player/referee (22P02 killed all player signups)
- Restore real role assignment (was hardcoded club_admin)
- Remove all 4 client-side profiles.role writes (42501 rejections)
- Add auth-session.service.js with honest error classification
- Reinstall role escalation guard (anyone could become developer)
- Close PDPA leak: 29 emails + coach IC/passport were public
- Enable RLS and purge permissive USING(true) policies
- Fix SyntaxError in shared_dashboard_components.js"

git push origin main
```

---

# APA YANG AKAN DI-PUSH

## 5 commit

| Commit | Kandungan |
|---|---|
| `ff7b756` | P0 auth identity repair + tooling |
| `263d816` | P0-B guard naik taraf role |
| `5e396fb` | Panduan padam akaun ujian |
| `fb26fe6` | P1-B dayakan RLS |
| `2624711` | P1-C buang policy terbuka |

## Statistik

```
23 fail berubah
+4,627 baris
-50 baris
```

## Imbasan keselamatan sebelum push

```
JWT baharu dalam perubahan     : tiada
service_role key               : TIADA
kata laluan ujian dalam kod    : 0
fail .env / credential         : tiada
```

Selamat untuk repo awam.

---

# SELEPAS PUSH — WAJIB

## 1. Tunggu Vercel siap deploy

Buka dashboard Vercel, pastikan status **Ready** dan commit hash sepadan.

## 2. Bersihkan cache browser

Buka Console (F12), tampal:

```js
(function bersihkanPlayPro(){
  var dibuang = [];
  Object.keys(localStorage).forEach(function(k){
    if (/^PLAYPRO_|^pp_|^sb-|supabase/i.test(k)) {
      localStorage.removeItem(k); dibuang.push(k);
    }
  });
  Object.keys(sessionStorage).forEach(function(k){
    if (/^PLAYPRO_|^pp_|^sb-|supabase/i.test(k)) {
      sessionStorage.removeItem(k); dibuang.push('session:'+k);
    }
  });
  console.log('Dibuang '+dibuang.length+' item:', dibuang);
  location.reload(true);
})();
```

## 3. Sahkan versi baharu dimuatkan

```js
console.log('Auth service:', window.PlayProModel6?.Auth?.Session?.version);
// Sepatutnya: "1.0.0-p0"
console.log('Ralat loader:', window.PlayProModel6?.loadErrors);
// Sepatutnya: []
```

Jika `undefined`, cache lama masih ada atau deploy belum siap.

## 4. Uji 6 aliran

- [ ] Daftar sebagai Pemain
- [ ] Daftar sebagai Jurulatih
- [ ] Daftar sebagai Pengurus Kelab
- [ ] Log masuk akaun sedia ada
- [ ] Log keluar → log masuk semula
- [ ] Refresh (session kekal?)

Selepas setiap pendaftaran, semak dalam SQL Editor:

```sql
SELECT full_name, email, role, created_at
FROM profiles
ORDER BY created_at DESC
LIMIT 5;
```

Role mesti sepadan dengan pilihan semasa daftar.

## 5. Uji carian jurulatih

Ini yang paling penting selepas patch privasi. Carian sepatutnya
berfungsi semula menggunakan `search_public_profiles`, dan **tidak
lagi** memaparkan emel atau nombor IC.

---

# JIKA ADA MASALAH SELEPAS DEPLOY

## Carian coach kosong

Kod baharu guna RPC `search_public_profiles`. Sahkan ia wujud:

```sql
SELECT proname FROM pg_proc WHERE proname='search_public_profiles';
```

## Login berjaya tetapi profil kosong

Sahkan RPC P0 wujud:

```sql
SELECT proname FROM pg_proc
WHERE proname IN ('get_my_profile','ensure_profile_after_signup');
```

## Nak patah balik (rollback)

```bash
git revert --no-commit 2624711 fb26fe6 263d816 5e396fb ff7b756
git commit -m "Revert P0+P1"
git push origin main
```

**AMARAN:** revert kod **tidak** membatalkan perubahan database.
Patch SQL kekal. Jika bos revert kod tetapi kekalkan SQL, carian coach
akan pecah kerana kod lama cuba baca `profiles` yang kini disekat RLS.
Beritahu saya dahulu sebelum revert.
