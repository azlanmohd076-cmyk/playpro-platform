# BRIEF UPDATE SITUASI — PLAYPRO
## Status Terkini untuk CTO / Agent Seterusnya

**Tarikh:** 2026-07-26
**Menggantikan:** `PLAYPRO_AGENT5_MASTER_BRIEF_PROMPT.md` (Seksyen 4, 5, 9, 13)
**Status kerja:** P0 siap dibaiki & diuji — **belum dijalankan pada database produksi**

> Copy-paste dokumen ini ke chatbox CTO baharu. Ia mengandungi status
> sebenar yang telah disahkan melalui ujian, bukan andaian.

---

# 1. RINGKASAN SATU PERENGGAN

`Failed to fetch` **bukan bug kod**. Hostname Supabase
`muirhenvjruvfxenoaxm.supabase.co` **tidak wujud dalam DNS dunia** — projek
paused atau deleted. Selain itu, **3 bug tambahan** ditemui yang akan tetap
merosakkan pendaftaran walaupun backend hidup semula. Ketiga-tiganya sudah
dibaiki dan **diuji hidup pada PostgreSQL 17**. Satu **kebocoran data peribadi
(PDPA)** turut ditemui dan sudah disediakan patch. Semua kerja masih dalam
working copy — **belum commit, belum push, belum jalan pada DB bos**.

---

# 2. PUNCA UTAMA — BUKTI, BUKAN TEKAAN

## 2.1 Backend mati

```
Cloudflare DNS : NXDOMAIN
Google DNS     : NXDOMAIN
curl           : Could not resolve host
Semakan akhir  : 2026-07-26 15:23 UTC — masih NXDOMAIN
```

Kawalan: `supabase.co` resolve normal. `random-xyz.supabase.co` juga NXDOMAIN
(tiada wildcard). Jadi NXDOMAIN untuk projek bos ialah isyarat sebenar.

## 2.2 Apa yang BUKAN puncanya — sudah diuji dan ditolak

| Teori dalam brief lama | Keputusan | Bukti |
|---|---|---|
| CORS | **Ditolak** | CORS perlu sambungan TCP. DNS gagal dahulu. |
| Cache Vercel | **Ditolak** | md5 live `index.html` = md5 repo HEAD (`dc8dc654`) |
| Frontend rosak | **Ditolak** | Semua 15 modul loader pulangkan HTTP 200 |
| Anon key expired | **Ditolak** | JWT sah sehingga 2036, `role=anon` |
| Kebocoran service_role | **Tiada** | Imbas semua fail — hanya anon key |

**Kesimpulan:** pipeline deploy bos sebenarnya **sihat**. Kerosakan tertumpu
pada lapisan identiti dan backend.

---

# 3. TIGA BUG TERSEMBUNYI (P0)

Outage DNS menyembunyikan bug ini. Ia akan muncul sebaik backend hidup.

## B1 — Enum `user_role` tiada `player` dan `referee` 🔴

```
ENUM  : developer, league_founder, league_admin, club_admin, coach, technical_assessor
UI hantar : player, coach, club_admin, league_admin, referee
```

`player` juga ialah nilai lalai JS (`||'player'`). Pendaftaran pemain — laluan
paling tinggi volum dalam produk — mati dengan `22P02`.

## B2 — Semua signup jadi `club_admin` 🔴

`playpro_phase4_1_2_security_patch.sql` menetapkan `role := 'club_admin'` secara
hardcode dalam `handle_new_user()`, mengabaikan metadata.

**Inilah punca sebenar** aduan *"role router gagal"* dan *"data coach belum cukup
lengkap"*. Data coach tidak pernah hilang — pengguna itu tidak pernah disimpan
sebagai coach.

## B3 — Setiap tulisan profil ditolak `42501` 🔴

Trigger sudah cipta baris profil. Client kemudian `upsert(...role...)` → jadi
UPDATE → `trg_prevent_role_escalation` menolak kerana role berbeza.

## B4 — Kenapa tiada siapa nampak 🔴

```js
catch(e){ console.warn('profiles insert on register:', e.message); }
```

supabase-js **resolve** dengan `{data, error}`, ia **tidak throw**. Blok `catch`
itu kod mati. Setiap kegagalan tulis profil senyap sepenuhnya.

**Inilah mekanisme di sebalik *"data pemain hilang / bercampur"*.** Data tidak
hilang — ia tidak pernah berjaya disimpan.

---

# 4. DUA PEMBETULAN PENTING KEPADA BRIEF LAMA

## 4.1 Cadangan §13-B dalam brief lama TIDAK MENCUKUPI

Brief lama cadang tambah `email` ke dalam upsert. Diuji pada PostgreSQL 17:

| Ujian | Keputusan sebenar |
|---|---|
| A — kod lama (tiada `email`) | `23502` null value in column "email" |
| B — cadangan brief (+`email`) | `42501` cannot modify your own role |
| C — B + role `player` | `22P02` invalid input value for enum |

Menambah `email` sahaja hanya **mengalihkan** kegagalan dari ralat A ke ralat B.
Pendaftaran tetap rosak. Ketiga-tiga bug mesti dibaiki serentak.

## 4.2 Pembetulan kepada laporan pertama saya sendiri

Laporan pertama saya kata `42501` muncul dahulu. **Itu salah.** Ujian sebenar
tunjuk susunan ialah `23502` → `42501` → `22P02`. Bug dan pembetulan tidak
berubah; hanya susunan yang saya tersilap. Direkodkan supaya tepat.

---

# 5. APA YANG SUDAH SIAP & DIUJI

## 5.1 Patch database

`database/model6_p0_auth_identity_repair.sql`

| Bahagian | Fungsi |
|---|---|
| PART A | Tambah `player` + `referee` ke enum |
| B.1 | `playpro_safe_signup_role()` — allow-list |
| B.2 | Bina semula `handle_new_user()` — role sebenar dipulihkan |
| B.3 | `ensure_profile_after_signup()` — satu-satunya laluan tulis client |
| B.4 | `get_my_profile()` — sumber kebenaran role router |
| B.5 | Backfill: auth user yatim, emel NULL, pulih role |

**Keselamatan dikekalkan.** `developer`, `league_founder`, `technical_assessor`
kekal **tidak boleh** diperoleh melalui signup. `trg_prevent_role_escalation`
kekal utuh.

## 5.2 Keputusan ujian hidup (PostgreSQL 17.10)

Skema sebenar dari repo dimuatkan (21 jadual), persekitaran Supabase ditiru
(`auth.users`, `auth.uid()`, RLS).

**7 pendaftaran diuji selepas patch:**

| Diminta | Disimpan | Keputusan |
|---|---|---|
| `player` | `player` | betul |
| `coach` | `coach` | betul |
| `club_admin` | `club_admin` | betul |
| `league_admin` | `league_admin` | betul |
| `referee` | `referee` | betul |
| `jurulatih` (alias BM) | `coach` | betul |
| `developer` (serangan) | `player` | **disekat** |

**Keputusan akhir: 9/9 profil ada role yang betul.**

Turut disahkan: self-heal akaun yatim · backfill pulih role · guard escalation
masih menyekat (`42501`) · patch idempotent.

## 5.3 Bug ditemui dalam arahan patch saya sendiri

Jalankan Part A + B serentak pada DB yang ada pengguna yatim:

```
ERROR: unsafe use of new value "player" of enum type user_role
→ seluruh patch ROLLBACK, 0 profil dibaiki
```

Part A dahulu, kemudian Part B → berjaya. Supabase SQL Editor balut setiap
"Run" dalam satu transaksi, jadi ini **perangkap sebenar**. Amaran keras sudah
dimasukkan ke dalam header patch.

## 5.4 Kod frontend

| Fail | Perubahan |
|---|---|
| `src/modules/auth/auth-session.service.js` | **BAHARU** — tidak pernah tulis `role`, ada preflight probe |
| `public/index.html` | **4** tulisan role client dibuang (1 register + 3 onboarding) |
| `public/model6-loader.js` | Daftar servis auth baharu |
| `js/shared_dashboard_components.js` | Baiki SyntaxError (`b=18`) yang matikan seluruh fail |
| `public/p0_auth_doctor.html` | **BAHARU** — alat diagnosis backend |

## 5.5 Pengesahan

```
38/38 fail JS lulus node --check
52/52 ujian unit lulus
 9 LULUS / 0 GAGAL pada PostgreSQL sebenar
```

---

# 6. PENEMUAN BAHARU — BELUM DIBAIKI

## 6.1 🔴 KEBOCORAN DATA PERIBADI (PDPA) — paling serius

```sql
CREATE POLICY "profiles: public read" ON profiles FOR SELECT USING (true);
```

RLS PostgreSQL menapis **baris**, bukan **lajur**. Diuji **tanpa log masuk**:

```
full_name      | email                | role
Cikgu Siti     | coach2@playpro.my    | coach
En Kelab       | pengurus@playpro.my  | club_admin
```

Kunci anon tertanam dalam **10 fail HTML awam**. Sesiapa boleh:

```
GET /rest/v1/profiles?select=email,full_name,role
```

dan muat turun **senarai emel penuh semua pengguna PlayPro**.

**Lebih teruk:** RPC `get_public_coach_profile()` — `SECURITY DEFINER`, `GRANT`
kepada `anon` — memulangkan `ic_number` dan `passport_number`. Sesiapa boleh
dapat **nombor IC** mana-mana jurulatih.

**Patch sudah sedia:** `database/model6_p1_profiles_privacy.sql`
Diuji: anon baca `profiles` → **0 baris**; carian jurulatih & emel sendiri masih
berfungsi. Kod frontend turut dibetulkan.

## 6.2 🟡 Role `player` tiada kuasa tulis langsung

Imbasan 57 policy RLS:

```
get_my_role() = 'developer'    → 10 policy
get_my_role() = 'club_admin'   →  2 policy
get_my_role() = 'player'       →  0 policy   ← SIFAR
get_my_role() = 'referee'      →  0 policy   ← SIFAR
```

Ini konsisten dengan Model 6 (*"pemain ialah pembekal data"*), **tetapi**
bermakna onboarding pemain akan gagal jika ia cuba tulis terus ke `players`.
Perlu semakan seni bina.

## 6.3 🟡 Celah `club_id IS NULL`

Policy izinkan `club_id NULL`. Pemain "yatim" tercipta, dan **tiada sesiapa
boleh mengeditnya selepas itu** (policy UPDATE perlu `is_club_admin(club_id)`).
Diuji: 0 baris dikemas kini. Ini sepadan dengan aduan *"data pemain bercampur"*.

## 6.4 🟡 Sesiapa boleh cipta kelab

`clubs: authenticated insert WITH CHECK (true)`. Diuji: akaun **pemain** berjaya
cipta kelab dan jadi `admin_id`. Bukan naik taraf penuh (masih tak boleh daftar
pemain), tetapi membenarkan kelab sampah tanpa had.

## 6.5 🟡 `/js/*.js` 404 di produksi

`vercel.json` set `outputDirectory: public`, jadi folder `js/` di root **tidak
pernah di-deploy**. 4 halaman command center memuat 5 skrip tersebut — semua
404 di live.

## 6.6 🟡 Isu lain

| Isu | Kesan |
|---|---|
| Drift `src/` ↔ `public/src/` | `league-os.service.js`, `passport.service.js` tiada dalam mirror |
| Fungsi pendua | `safeSet`, `aksiLikeHub`, `hantarKomenHub` ×2 |
| 45 panggilan localStorage, 9 catch senyap | Sumber kebenaran bercampur (P1 brief lama) |
| URL+key hardcode dalam 10 HTML | Tukar projek = 10 suntingan manual |

---

# 7. STATUS SEBENAR — DISEMAK SEMULA

| Bidang | Brief lama | Nilaian sebenar | Nota |
|---|---|---|---|
| Database foundation | 50–60% | **45%** | Percanggahan enum/trigger adalah fatal |
| Auth/onboarding | 10–20% | **15% → ~70%** selepas patch + restore |
| Frontend stability | 10–20% | **25%** | Pipeline deploy sihat; monolith rapuh |
| Security/RLS | 50–60% | **40%** | Kebocoran PDPA belum ditutup |
| UI/UX polish | 10–15% | **10%** | Tidak disentuh |
| Commercial readiness | 10–15% | **10%** | Tidak berubah |

---

# 8. FAIL BAHARU DALAM REPO

```
database/model6_p0_auth_identity_repair.sql   ← patch utama P0
database/model6_p0_verify.sql                 ← 9 semakan pengesahan
database/model6_p1_profiles_privacy.sql       ← tutup kebocoran PDPA
public/p0_auth_doctor.html                    ← alat diagnosis backend
src/modules/auth/auth-session.service.js      ← + mirror public/src
tests/auth-session.test.js                    ← 52 ujian, tiada install
PLAYPRO_P0_DIAGNOSIS_2026-07-26.md            ← laporan teknikal (EN)
PANDUAN_PEMULIHAN_P0_BM.md                    ← panduan 6 langkah (BM)
PLAYPRO_KAJIAN_TRIGGER_RLS_CACHE_BM.md        ← trigger + RLS + cache (BM)
```

**Semua masih uncommitted.** Belum `git push`, belum deploy.

---

# 9. APA YANG BELUM DAPAT DISAHKAN

Kejujuran teknikal (peraturan #1 brief lama):

1. **Tiada ujian signup hidup pada projek bos** — backend tidak resolve.
2. **Patch belum dijalankan pada DB produksi** — saya tiada kredensial, dan
   saya tidak meminta.
3. Ujian guna **binaan semula** skema dari fail migrasi. DB produksi mungkin
   sudah drift. Sebab itu `model6_p0_verify.sql` wujud.
4. Objek `storage.*` dilangkau secara tempatan (khusus Supabase) — tiada kaitan
   dengan auth.
5. Backfill role (B.5.3) sengaja dibiar **commented out** — perlu semakan mata
   sebelum dijalankan.

---

# 10. TINDAKAN SETERUSNYA — MENUNGGU KEPUTUSAN BOS

## Yang perlu bos buat (tiada siapa lain boleh)

**LANGKAH 1** — Buka https://supabase.com/dashboard, cari ref
`muirhenvjruvfxenoaxm`. Laporkan statusnya: **Paused / Deleted / Active**.

Tanpa maklumat ini, tiada apa yang boleh bergerak.

## Keputusan yang menunggu arahan bos

| # | Soalan | Pilihan |
|---|---|---|
| 1 | Projek Supabase | Restore? Atau bina baharu? |
| 2 | Selepas P0, mana dahulu? | (a) Patch PDPA `model6_p1_profiles_privacy.sql` — **saya syorkan** (b) Club Passport (c) UI/UX polish |
| 3 | Commit & push sekarang? | Ya (siap sedia deploy) / Tunggu bos review kod dahulu |
| 4 | Skill `ui-ux-pro-max` | Lengkapkan (enjin + 1.2 MB data hilang)? Atau biar? |

## Baris gilir kerja (selepas bos putuskan)

```
P0  Pulihkan Supabase + jalankan patch auth        ← BLOKED, tunggu bos
P1  Tutup kebocoran PDPA (emel + IC)               ← patch sedia
P2  Baiki celah club_id NULL + hadkan cipta kelab
P2  Semak semula onboarding pemain (role tiada kuasa tulis)
P3  Pindahkan js/ ke public/ (404 di live)
P3  Bersihkan sumber kebenaran (45 localStorage)
P4  Club Passport & Manager Workspace
P5  League OS MVP UI
P6  UI/UX polish
```

---

# 11. PERATURAN KERJA — KEKAL SAMA

1. Jangan claim siap kalau belum test.
2. Jangan tambah feature besar sebelum auth stabil.
3. Jangan edit `public/index.html` kecuali perlu dan minimum.
4. Module baharu → `/src/modules` + mirror ke `/public/src/modules`.
5. Wajib `node --check` untuk JS yang diubah.
6. DB write sensitif → RPC `SECURITY DEFINER`.
7. Jangan expose token rahsia.
8. Patch kecil → test → baru push.
9. Tunggu deploy Vercel siap sebelum claim.
10. **BAHARU:** `ALTER TYPE ... ADD VALUE` mesti berasingan daripada kod yang
    menggunakannya. Terbukti menyebabkan rollback penuh.

---

# 12. AYAT PENUTUP UNTUK CTO

PlayPro **bukan** projek yang rosak teruk. Pipeline deploy sihat, foundation
Model 6 wujud, dan modul-modul memang ada.

Masalahnya tertumpu pada **satu lapisan**: identiti. Bila lapisan itu rosak,
setiap flow di atasnya — Coach, Player, Manager, Wallet, League OS — nampak
rosak juga.

Baiki lapisan identiti, dan satu kelas simptom hilang serentak.

**Tetapi:** kebocoran emel + nombor IC adalah risiko undang-undang, bukan
sekadar bug. Dari sudut PDPA ia lebih berat daripada login rosak. Ia perlu
ditutup sebaik P0 selesai — jangan tolak ke belakang barisan.

```
Langkah bos sekarang: semak dashboard Supabase, laporkan status.
Semua kod dan patch sudah siap dan diuji, menunggu backend hidup.
```

---

**TAMAT BRIEF UPDATE**
