# Panduan Pemulihan P0 PlayPro — Bahasa Malaysia

**Tarikh:** 2026-07-26
**Untuk:** Pemilik projek PlayPro
**Status patch:** Sudah diuji pada PostgreSQL 17 sebenar — 9 LULUS / 0 GAGAL

---

## Ringkasan dalam satu perenggan

Backend Supabase bos **tidak wujud** — hostname `wxalcnpsbijxfmnzswxd.supabase.co`
tidak boleh dicari dalam DNS dunia. Itulah punca `Failed to fetch`. Selain itu, saya
jumpa **3 bug lagi** yang akan tetap merosakkan pendaftaran walaupun selepas backend
dipulihkan. Ketiga-tiga bug itu sudah dibaiki, dan kali ini saya **betul-betul uji**
patch tersebut pada PostgreSQL sebenar — bukan sekadar baca kod.

---

## LANGKAH 1 — Semak dashboard Supabase (hanya bos boleh buat)

Saya tiada akses dashboard bos, jadi langkah ini wajib bos sendiri.

1. Buka https://supabase.com/dashboard
2. Cari projek dengan ref: **`wxalcnpsbijxfmnzswxd`**

Kemudian ikut keadaan:

### Jika projek **PAUSED** (berkemungkinan besar)

- Tekan butang **Restore** / **Resume**
- Tunggu status bertukar kepada **Active** (biasanya 2–5 minit)
- Teruskan ke LANGKAH 2

> Projek free tier Supabase akan auto-pause selepas lebih kurang 7 hari tiada
> aktiviti. Bila paused, DNS berhenti berfungsi — inilah yang berlaku.

### Jika projek **DELETED** / tiada langsung

Projek perlu dibina semula:

1. Cipta projek Supabase baharu
2. Jalankan **semua** fail dalam folder `/database` mengikut urutan nama
3. Jalankan patch P0 (LANGKAH 3 di bawah)
4. Kemas kini URL + anon key dalam **10 fail HTML**:

```
public/index.html
public/app.html
public/dev_panel.html
public/player_card.html
public/portals.html            (jika ada config)
public/playpro_public.html
public/match_observer.html
public/coach_command_center.html
public/club_command_center.html
public/parent_command_center.html
public/player_command_center.html
```

Cari baris ini dalam setiap fail dan tukar:

```js
window.PLAYPRO_SUPABASE_URL='https://PROJEK_BARU.supabase.co';
window.PLAYPRO_SUPABASE_ANON_KEY='eyJ...';
```

---

## LANGKAH 2 — Sahkan backend sudah hidup

Buka dalam browser:

```
https://playpro-platform.vercel.app/p0_auth_doctor.html
```

Paste URL + anon key, tekan **Run diagnosis**.

- Kalau nampak **"Host reachable"** hijau → teruskan ke LANGKAH 3
- Kalau masih merah **"Cannot reach"** → projek belum aktif, tunggu atau semak semula

Alat ini read-only. Ia tidak cipta pengguna dan tidak tulis apa-apa data.

---

## LANGKAH 3 — Jalankan patch P0 (PALING PENTING)

Buka **Supabase SQL Editor**, kemudian buka fail:

```
database/model6_p0_auth_identity_repair.sql
```

### ⚠️ AMARAN — jangan jalankan sekali gus

Fail ini ada **PART A** dan **PART B**. Ia **MESTI** dijalankan berasingan.

**Ini bukan teori — saya sudah uji dan buktikan:**

| Cara | Keputusan sebenar (PostgreSQL 17) |
|---|---|
| A + B serentak | `ERROR: unsafe use of new value "player"` → **semua rollback, 0 profile dibaiki** |
| A dahulu, kemudian B | **Berjaya** — backfill jalan, semua role betul |

### Cara betul:

1. **Highlight PART A sahaja** (2 baris `ALTER TYPE`), tekan **Run**
2. Tunggu sampai siap
3. **Highlight PART B**, tekan **Run**

Sebab: PostgreSQL tidak benarkan nilai enum baharu digunakan dalam transaksi yang
sama yang menambahnya. Supabase SQL Editor balut setiap "Run" dalam satu transaksi.

---

## LANGKAH 4 — Sahkan patch berjaya

Dalam SQL Editor, jalankan fail:

```
database/model6_p0_verify.sql
```

**Semua 9 baris mesti tunjuk `LULUS`.** Kalau ada `GAGAL`, jangan teruskan — hantar
hasilnya kepada saya.

Yang diperiksa:

| # | Ujian |
|---|---|
| 1 | ENUM sudah ada `player` + `referee` |
| 2 | Trigger `on_auth_user_created` aktif |
| 3 | 3 fungsi RPC P0 wujud |
| 4 | Allow-list keselamatan berfungsi (`developer` → `player`) |
| 5 | Tiada auth user yatim |
| 6 | Tiada profile tanpa emel |
| 7 | Guard naik taraf role masih terpasang |
| 8 | Taburan role (maklumat) |
| 9 | Tiada role yang perlu dipulihkan |

---

## LANGKAH 5 — Deploy kod frontend

**Jangan deploy sebelum LANGKAH 3 siap.** Kod baharu memanggil RPC
`ensure_profile_after_signup`. Kalau RPC belum wujud, pendaftaran tidak akan lengkap.

```bash
cd /home/user/repo
git add -A
git commit -m "P0: repair auth/profile integrity + verification tooling"
git push
```

Vercel akan auto-deploy. Tunggu siap, kemudian clear cache browser.

---

## LANGKAH 6 — Uji 6 aliran (brief §13-F)

Uji satu per satu di https://playpro-platform.vercel.app/

- [ ] Daftar sebagai **Pemain**
- [ ] Daftar sebagai **Jurulatih**
- [ ] Daftar sebagai **Pengurus Kelab**
- [ ] Log masuk akaun sedia ada
- [ ] Log keluar → log masuk semula
- [ ] Refresh page (session kekal?)

Selepas setiap pendaftaran, semak dalam Supabase:

```sql
SELECT full_name, email, role FROM profiles ORDER BY created_at DESC LIMIT 5;
```

Role mesti **sepadan** dengan apa yang dipilih semasa daftar.

---

## Apa yang sudah dibuktikan berfungsi

Saya pasang PostgreSQL 17, bina semula persekitaran Supabase (auth.users, auth.uid(),
RLS), muatkan skema **sebenar** dari repo bos (21 jadual), dan jalankan patch.

**Sebelum patch — bug disahkan:**

| Bug | Ralat sebenar |
|---|---|
| Enum | `22P02` — `player` dan `referee` ditolak |
| Role | Jurulatih daftar → disimpan sebagai `club_admin` |
| Guard | `42501` — upsert client ditolak |
| Emel | `23502` — email NOT NULL dilanggar |

**Selepas patch — 7 pendaftaran diuji:**

| Diminta | Disimpan | Keputusan |
|---|---|---|
| `player` | `player` | betul |
| `coach` | `coach` | betul |
| `club_admin` | `club_admin` | betul |
| `league_admin` | `league_admin` | betul |
| `referee` | `referee` | betul |
| `jurulatih` | `coach` | alias BM berfungsi |
| `developer` (cubaan serangan) | `player` | **disekat** |

Keputusan akhir: **9/9 profile ada role yang betul.**

Turut disahkan:
- Self-heal: akaun yatim dapat profile bila log masuk
- Backfill pulihkan `coach` yang tersalah jadi `club_admin`
- Keselamatan kekal: pengguna masih **tidak boleh** naik taraf diri jadi `developer`
- Patch selamat dijalankan berulang kali (idempotent)

---

## Pembetulan kepada laporan pertama saya

Dalam laporan pertama saya kata upsert gagal dahulu dengan ralat role-escalation.
**Itu salah.** Ujian sebenar tunjuk ralat `NOT NULL` emel yang muncul dahulu, barulah
`42501`, barulah `22P02`.

Tiga bug itu tetap sama dan pembetulannya tetap sama — cuma susunannya saya tersilap.
Saya betulkan supaya rekod tepat.

**Yang lebih penting:** ini mengesahkan cadangan dalam brief asal (§13-B, tambah
`email` sahaja) memang **tidak mencukupi**. Ia cuma alihkan kegagalan dari ralat A ke
ralat B.

---

## Fail-fail penting

| Fail | Fungsi |
|---|---|
| `database/model6_p0_auth_identity_repair.sql` | Patch utama — **jalankan ini** |
| `database/model6_p0_verify.sql` | Skrip pengesahan — **jalankan selepas patch** |
| `public/p0_auth_doctor.html` | Alat diagnosis backend |
| `src/modules/auth/auth-session.service.js` | Servis auth baharu |
| `tests/auth-session.test.js` | 52 ujian unit |
| `PLAYPRO_P0_DIAGNOSIS_2026-07-26.md` | Laporan teknikal penuh (English) |

---

**Langkah bos sekarang: buka dashboard Supabase.** Semua yang lain sudah siap dan
sudah diuji. Tanpa backend hidup, tiada apa yang boleh bergerak.
