# PlayPro — Kajian Trigger, RLS & Cache

**Tarikh:** 2026-07-26
**Kaedah:** Semua keputusan diuji hidup pada PostgreSQL 17.10 dengan RLS **dikuatkuasakan penuh**, bukan dibaca dari kod.

---

# BAHAGIAN 1 — Mekanisme Trigger `on_auth_user_created`

## 1.1 Apa itu, dalam satu ayat

Ia jambatan automatik antara sistem auth Supabase (`auth.users`) dan jadual aplikasi bos (`profiles`). Tanpa ia, pengguna boleh log masuk tetapi tidak wujud di dalam app.

## 1.2 Spesifikasi sebenar (disahkan dari `pg_trigger`)

| Sifat | Nilai | Maksud |
|---|---|---|
| Peringkat | `ROW` | Jalan sekali bagi setiap pengguna baharu |
| Masa | `AFTER` | Jalan **selepas** `auth.users` berjaya disimpan |
| Peristiwa | `INSERT` | Hanya pendaftaran baharu |
| Status | `aktif` | Sedang berjalan |
| Mod | `SECURITY DEFINER` | Jalan sebagai **pemilik**, bukan pengguna |
| `search_path` | `public, pg_temp` | Dikunci — halang serangan search_path |

## 1.3 Kenapa `SECURITY DEFINER` itu penting

Semasa pendaftaran, pengguna **belum ada sesi**. `auth.uid()` masih kosong, jadi RLS akan menyekat sebarang tulisan ke `profiles`.

`SECURITY DEFINER` bermakna fungsi berjalan dengan kuasa pemiliknya, bukan pemanggil. Itulah yang membenarkan baris profil dicipta sebelum pengguna "wujud" dari sudut RLS.

Risikonya: fungsi berkuasa penuh. Sebab itu `search_path` dikunci — tanpa kunci itu, penyerang boleh cipta jadual palsu bernama `profiles` dalam skema lain dan menipu fungsi.

## 1.4 Aliran sebenar

```
Pengguna tekan "Buat Akaun"
        │
        ▼
supabase.auth.signUp({ email, password, options:{ data:{ full_name, role, phone } } })
        │
        ▼
Supabase masukkan baris ke auth.users
   ├─ raw_user_meta_data  <── options.data disimpan di sini
        │
        ▼
TRIGGER on_auth_user_created menyala (AFTER INSERT, FOR EACH ROW)
        │
        ▼
handle_new_user() berjalan sebagai SECURITY DEFINER
   ├─ full_name := metadata->>'full_name'  (lalai 'New User')
   ├─ email     := NEW.email               ← dari auth, bukan dari client
   ├─ role      := playpro_safe_signup_role(metadata->>'role')  ← ALLOW-LIST
   └─ phone     := metadata->>'phone'
        │
        ▼
INSERT INTO profiles ... ON CONFLICT (id) DO NOTHING
        │
        ▼
Client panggil ensure_profile_after_signup()  ← jaring keselamatan
        │
        ▼
Role router baca get_my_profile() → buka onboarding yang betul
```

## 1.5 Empat mekanisme pertahanan — semua diuji

### (a) Allow-list role — bukan sekadar terima metadata

Metadata datang dari client, jadi ia **tidak boleh dipercayai**. Sesiapa boleh hantar `role: 'developer'`.

| Metadata dihantar | Disimpan | Keputusan ujian |
|---|---|---|
| `coach` | `coach` | betul |
| `player` | `player` | betul |
| `jurulatih` | `coach` | alias BM dipetakan |
| `{}` (kosong) | `player` | lalai selamat |
| `<script>alert(1)</script>` | `player` | sampah ditolak |
| `developer` | `player` | **naik taraf disekat** |
| `technical_assessor` | `player` | **mesti diperoleh via PCSAP** |

### (b) `ON CONFLICT (id) DO NOTHING` — tidak menimpa

Jika baris profil sudah wujud, trigger **tidak** menulis ganti.

Diuji: pengguna tukar nama kepada "Nama Diubah Pengguna" → kekal selepas trigger berjalan semula. Perubahan pengguna tidak dipadam.

### (c) Handler `EXCEPTION` — pendaftaran tidak boleh dikorbankan

Ini keputusan reka bentuk paling penting dalam patch.

Diuji dengan sengaja merosakkan fungsi supaya ia `RAISE EXCEPTION`:

```
WARNING: handle_new_user failed for 3b2b3ecb-...: kerosakan sengaja (P0001)
NOTICE:  auth.users BERJAYA (signup diselamatkan)
NOTICE:    -> profile dicipta? 0
```

Falsafahnya:

> Profil yang hilang **boleh dipulihkan**. Pendaftaran yang gagal **tidak boleh**.

Tanpa handler ini, satu ralat kecil dalam trigger akan menyebabkan **seluruh pendaftaran gagal** — pengguna tidak boleh masuk langsung.

### (d) Self-heal semasa log masuk

Pengguna yang profilnya gagal tadi kemudian log masuk:

```json
{"ok": true, "role": "coach", "email": "trig_rosak@x.my", "full_name": "Ujian Rosak"}
```

Profil dicipta secara automatik dengan role yang **betul**. Rantaian pemulihan lengkap.

## 1.6 Had yang perlu bos tahu

**(i) Trigger hanya pada `INSERT`.** Tiada trigger untuk `UPDATE` atau `DELETE` pada `auth.users`. Jika pengguna tukar emel di Supabase Auth, `profiles.email` **tidak** ikut berubah — ia akan jadi basi.

**(ii) Padam berfungsi melalui CASCADE, bukan trigger.**

```
profiles.id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE
```

Diuji: padam `auth.users` → profil ikut terpadam. Berfungsi betul.

**(iii) Emel pendua ditolak di peringkat auth.** Diuji: `23505 duplicate key`. Pendaftaran gagal sepenuhnya — tiada baris yatim tertinggal.

---

# BAHAGIAN 2 — Perbezaan RLS: Pemain vs Pengurus

> **Nota kaedah — penting.** Percubaan pertama saya memberi keputusan **palsu** kerana saya diuji sebagai superuser, yang **memintas RLS sepenuhnya**. Saya cipta peranan `app_user` (`NOSUPERUSER`, `NOBYPASSRLS`) yang setara dengan `authenticated` Supabase, dan ulang semula. Keputusan di bawah adalah yang sah.

## 2.1 Penemuan asas: tiada policy untuk `player`

Saya imbas 57 policy dalam skema:

```
get_my_role() = 'developer'                    10 policy
get_my_role() IN ('technical_assessor', ...)    3 policy
get_my_role() = 'club_admin' AND is_club_admin  2 policy
get_my_role() = 'player'                        0 policy   ← SIFAR
get_my_role() = 'referee'                       0 policy   ← SIFAR
```

**Implikasi seni bina:** dalam PlayPro, `player` **bukan** peranan berkuasa. Ia adalah identiti *rujukan*. Pemain tidak menulis data mereka sendiri — kelab dan penilai yang menulisnya.

Ini sejajar dengan Model 6 dalam brief bos: *"Pemain bukan target monetisasi utama. Pemain ialah pembekal data."* Tetapi ia bermakna **onboarding pemain akan gagal** jika ia cuba menulis terus ke `players`.

## 2.2 Matriks kuasa sebenar (diuji hidup)

| Tindakan | Pemain | Pengurus Kelab |
|---|---|---|
| Baca `players` | ✅ semua | ✅ semua |
| **Tulis** `players` (INSERT) | ❌ **42501** | ✅ kelab sendiri |
| Kemas kini pemain kelab sendiri | ❌ 0 baris | ✅ 2 baris |
| Kemas kini pemain kelab **lain** | ❌ | ❌ **isolasi berfungsi** |
| Cipta kelab | ✅ **ya** | ✅ ya |
| Kemas kini kelab sendiri | ✅ jika `admin_id` | ✅ |
| Tukar role sendiri | ❌ 42501 | ❌ 42501 |

## 2.3 Mekanisme di sebalik isolasi kelab

```sql
-- players: club admin insert
WITH CHECK (
  get_my_role() IN ('developer','club_admin')
  AND (club_id IS NULL OR is_club_admin(club_id))
)
```

`is_club_admin()` menyemak `clubs.admin_id = auth.uid()`. Jadi pengurus Kelab B **tidak boleh** sentuh pemain Kelab A — diuji dan disahkan (`42501`).

## 2.4 Tiga isu yang saya jumpa

### Isu A — Celah `club_id IS NULL` 🟡

Policy membenarkan `club_id IS NULL`. Diuji: pengurus **berjaya** cipta pemain tanpa kelab.

Kesan: pemain "yatim" tercipta, dan **tiada sesiapa boleh mengeditnya selepas itu** — policy `UPDATE` memerlukan `is_club_admin(club_id)`, yang gagal apabila `club_id` NULL. Diuji: 0 baris dikemas kini.

Ini sepadan dengan aduan bos: *"banyak data pemain hilang / bercampur."*

### Isu B — Sesiapa boleh cipta kelab 🟡

```sql
CREATE POLICY "clubs: authenticated insert" ... WITH CHECK (true)
```

Diuji: akaun **pemain** berjaya cipta kelab dan menjadi `admin_id`-nya. Dia kemudian boleh mengedit kelab itu.

Dia **masih tidak boleh** daftar pemain (policy `players` memerlukan role `club_admin`), jadi ini bukan naik taraf penuh — tetapi ia membenarkan kelab sampah dicipta tanpa had.

### Isu C — 🔴 KEBOCORAN EMEL (paling serius)

```sql
CREATE POLICY "profiles: public read"
  ON profiles FOR SELECT
  USING (true);        -- SESIAPA SAHAJA
```

Diuji **tanpa log masuk**:

```
full_name      | email                | role
Cikgu Siti     | coach2@playpro.my    | coach
En Kelab       | pengurus@playpro.my  | club_admin
Penganjur Liga | liga@playpro.my      | league_admin
```

RLS PostgreSQL menapis **baris**, bukan **lajur**. `USING (true)` mendedahkan setiap lajur.

Kunci anon bos tertanam dalam **10 fail HTML awam**. Sesiapa boleh:

```
GET /rest/v1/profiles?select=email,full_name,role
```

dan memuat turun **senarai emel penuh setiap pengguna PlayPro**.

**Lebih teruk:** RPC `get_public_coach_profile()` — `SECURITY DEFINER`, diberi `GRANT` kepada `anon` — memulangkan `ic_number` dan `passport_number`. Sesiapa boleh dapat **nombor IC** mana-mana jurulatih. Ini pelanggaran PDPA.

## 2.5 Pembetulan: `database/model6_p1_profiles_privacy.sql`

| Perubahan | Kesan |
|---|---|
| Buang `profiles: public read` | Emel tidak lagi bocor |
| Policy baharu: baca sendiri / developer | Pengguna nampak diri sendiri sahaja |
| VIEW `public_profiles` | Hanya `id, full_name, role, avatar_url, is_active` |
| RPC `search_public_profiles()` | Carian selamat tanpa emel |
| Baiki `get_public_coach_profile()` | IC, pasport, emel, DOB **dibuang** |

**Diuji selepas patch:**

| Ujian | Sebelum | Selepas |
|---|---|---|
| Anon baca `profiles` | 15 baris + emel | **0 baris** |
| Anon baca `public_profiles` | — | 18 baris, tiada emel |
| Lajur dalam view | — | `id, role, is_active, full_name, avatar_url` |
| Pengguna baca emel sendiri | ✅ | ✅ masih berfungsi |
| Pengguna baca profil orang lain | 15 | **0** |
| Carian jurulatih | ✅ | ✅ masih berfungsi |

Kod frontend turut dikemas kini — `role-search-router.js` tidak lagi meminta `email`, `ic_number`, `passport_number`.

---

# BAHAGIAN 3 — Pembersihan Cache Browser

## 3.1 Bila ini perlu

Hanya selepas deploy. Jika app masih tunjuk kelakuan lama walaupun Vercel sudah siap deploy.

**Penting:** cache **tidak** akan membaiki `Failed to fetch`. Itu masalah DNS. Jangan buang masa membersih cache sebelum backend hidup.

## 3.2 Tiga lapisan cache yang berbeza

| Lapisan | Simpan apa | Cara bersih |
|---|---|---|
| HTTP cache | HTML, JS, CSS | Hard reload |
| localStorage | 45 panggilan dalam `index.html` | Kena buang manual |
| Sesi Supabase | Token auth | Logout, atau buang key `sb-*` |

Lapisan kedua paling kerap dilupakan. PlayPro simpan `PLAYPRO_REGISTRY_V3`, `PLAYPRO_HUB_POSTS_V2`, `PLAYPRO_NOTIFICATIONS_V2` — data lama boleh kekal walaupun selepas hard reload.

## 3.3 Kaedah 1 — Hard reload (paling cepat)

| Sistem | Kekunci |
|---|---|
| Windows / Linux | `Ctrl` + `Shift` + `R` |
| Mac | `Cmd` + `Shift` + `R` |
| Chrome (buka DevTools) | Klik kanan butang reload → **Empty Cache and Hard Reload** |

## 3.4 Kaedah 2 — Bersih cache khusus PlayPro sahaja (disyorkan)

Buka Console (F12), tampal:

```js
(function bersihkanPlayPro(){
  var dibuang = [];
  // Buang kunci PlayPro dan sesi Supabase sahaja
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

Ini **tidak** menyentuh laman web lain. Lebih selamat daripada "Clear all browsing data".

## 3.5 Kaedah 3 — Bersih penuh (bila kaedah 2 gagal)

**Chrome / Edge:**
1. F12 → tab **Application**
2. **Storage** → **Clear site data**
3. Tandakan semua → **Clear site data**

**Firefox:**
1. F12 → **Storage** → klik kanan domain → **Delete All**

**Safari:**
1. Develop → **Empty Caches** (aktifkan menu Develop dalam Preferences → Advanced)

## 3.6 Kaedah 4 — Tetingkap Incognito (ujian paling bersih)

| Sistem | Kekunci |
|---|---|
| Chrome/Edge Windows | `Ctrl` + `Shift` + `N` |
| Chrome Mac | `Cmd` + `Shift` + `N` |
| Firefox | `Ctrl`/`Cmd` + `Shift` + `P` |

Gunakan ini untuk **mengesahkan** pembetulan berfungsi — tiada cache lama langsung.

## 3.7 Sahkan bos betul-betul dapat versi baharu

Dalam Console:

```js
// 1. Adakah servis auth baharu dimuatkan?
console.log('Auth service:', window.PlayProModel6?.Auth?.Session?.version);
// Sepatutnya: "1.0.0-p0"

// 2. Adakah semua modul dimuatkan tanpa ralat?
console.log('Ralat loader:', window.PlayProModel6?.loadErrors);
// Sepatutnya: []

// 3. Adakah localStorage sudah bersih?
console.log('Baki kunci PlayPro:',
  Object.keys(localStorage).filter(k => /^PLAYPRO_|^pp_/.test(k)));
```

Jika `version` `undefined` → cache lama masih ada, atau deploy belum siap.

## 3.8 Cache di sisi Vercel

Jika **semua** kaedah di atas gagal, masalahnya di CDN, bukan browser:

1. Dashboard Vercel → projek → **Deployments**
2. Sahkan deployment terkini **Ready** dan commit hash betul
3. **⋯** → **Redeploy** → **matikan** "Use existing Build Cache"

Untuk menyemak tanpa browser langsung:

```bash
curl -sI https://playpro-platform.vercel.app/model6-loader.js | grep -i "age\|cache\|etag"
```

`age` yang tinggi bermakna ia dihidangkan dari cache CDN.

## 3.9 Urutan disyorkan selepas deploy P0

```
1. Tunggu Vercel papar "Ready"
2. Buka Incognito → uji di sana dahulu
3. Jika berfungsi di Incognito tetapi tidak di tetingkap biasa → cache browser
4. Jalankan skrip Kaedah 2
5. Sahkan dengan skrip Bahagian 3.7
6. Barulah uji 6 aliran pendaftaran
```

---

# Ringkasan Tindakan

| Keutamaan | Tindakan | Siapa |
|---|---|---|
| **P0** | Pulihkan projek Supabase | **Bos** |
| **P0** | Jalankan `model6_p0_auth_identity_repair.sql` (A dahulu, kemudian B) | Bos |
| **P0** | Sahkan dengan `model6_p0_verify.sql` — 9 LULUS | Bos |
| **P1** | Jalankan `model6_p1_profiles_privacy.sql` — tutup kebocoran emel/IC | Bos |
| P2 | Baiki celah `club_id IS NULL` | Kemudian |
| P2 | Hadkan siapa boleh cipta kelab | Kemudian |
| P2 | Semak semula onboarding pemain (role `player` tiada kuasa tulis) | Kemudian |

**Status ujian:** 38/38 fail JS lulus · 52/52 ujian unit lulus · 9 LULUS / 0 GAGAL pada PostgreSQL sebenar.
