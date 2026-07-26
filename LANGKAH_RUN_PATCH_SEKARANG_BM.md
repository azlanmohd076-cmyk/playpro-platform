# LANGKAH RUN PATCH — DISEMAK PADA DB SEBENAR BOS

**Tarikh:** 2026-07-26 · 16:16 UTC
**Status backend:** HIDUP (baru pulih)

---

## BERITA BAIK — backend bos sudah hidup

```
DNS Cloudflare : 172.64.149.246, 104.18.38.10   -> RESOLVE
DNS Google     : sama                            -> RESOLVE
/auth/v1/health: HTTP 200  GoTrue v2.193.1       -> SIHAT
/rest/v1/...   : HTTP 200                        -> SIHAT
```

Ralat `42601` yang bos dapat itu sebenarnya **petanda baik** — ia bermakna SQL
Editor berjaya sambung ke database dan cuba tafsir teks yang bos tampal. Ia
cuma tidak faham `database/model6_p0_auth_identity_repair.sql` kerana itu nama
fail, bukan kod SQL.

---

## PENEMUAN PENTING — ARAHAN BERUBAH

Saya imbas database produksi bos sebelum bos Run. **Enum `user_role` di
produksi SUDAH ADA `player` dan `referee`.**

| Nilai enum | Status di produksi |
|---|---|
| developer, league_founder, league_admin | ada |
| club_admin, coach, technical_assessor | ada |
| **player** | **SUDAH ADA** |
| **referee** | **SUDAH ADA** |

Ini bermakna database bos sudah **drift** daripada fail migrasi dalam repo —
seseorang atau patch lain sudah menambah nilai itu sebelum ini.

### Kesannya kepada bos: KERJA JADI LEBIH MUDAH

Amaran "PART A dan PART B mesti berasingan" itu **tidak lagi terpakai** untuk
database bos, kerana `ALTER TYPE ... ADD VALUE IF NOT EXISTS` akan jadi
no-op (tiada apa berlaku) memandangkan nilai itu sudah wujud.

Saya sudah uji senario ini secara khusus:

```
Simulasi: enum SUDAH ada player+referee, ada pengguna yatim role 'player'
Jalankan SELURUH patch dalam SATU transaksi
Keputusan: TIADA RALAT — backfill berjaya
```

> **Bos boleh tampal seluruh fail dan tekan Run SEKALI SAHAJA.**

---

## KEADAAN SEBENAR DATABASE BOS

| Perkara | Nilai |
|---|---|
| Jumlah profil | **29** |
| coach | 20 |
| player | 7 |
| developer | 1 |
| club_admin | 1 |
| Jadual Model 6 | `certified_assessors`, `agent_wallets`, `organizations`, `player_passports` — semua ada |
| Kolum onboarding | `ic_number`, `date_of_birth` — sudah ada |
| RPC P0 | **BELUM ADA** (`get_my_profile` -> 404) |

Jadi: skema banyak sudah lengkap, cuma **patch P0 belum dijalankan**.

---

## AMARAN KESELAMATAN — DISAHKAN DALAM PRODUKSI

Saya uji tanpa log masuk, guna hanya anon key yang ada dalam HTML awam:

```
GET /rest/v1/profiles?select=full_name,email,role

HTTP 200
poid        | d07***@gmail.com    | coach
Syukri Nor  | syu***@playpro.my   | coach
Azlan Mohd  | azl***@gmail.com    | developer
```

**29 profil terdedah**, termasuk emel bos sendiri dan status `developer` bos.

Sesiapa yang buka view-source pada laman PlayPro boleh ambil anon key dan
muat turun senarai penuh ini. Ini bukan teori — saya baru sahaja buat.

Patch penutupnya sudah sedia: `database/model6_p1_profiles_privacy.sql`
(jalankan **selepas** P0 lulus).

---

# CARA RUN — IKUT LANGKAH INI

## LANGKAH 1 — Buka fail sebenar

Dalam VS Code atau editor bos, buka:

```
database/model6_p0_auth_identity_repair.sql
```

## LANGKAH 2 — Salin SEMUA kandungan

- Klik dalam fail
- `Ctrl + A` (Mac: `Cmd + A`) — pilih semua
- `Ctrl + C` (Mac: `Cmd + C`) — salin

Bos akan salin lebih kurang **330 baris** kod SQL. Ia bermula dengan:

```sql
-- ============================================================
-- PlayPro Model 6 — P0 AUTH / IDENTITY INTEGRITY REPAIR
```

Kalau yang bos nampak cuma satu baris teks pendek, itu **nama fail**, bukan
kandungan. Pastikan fail betul-betul terbuka.

## LANGKAH 3 — Tampal ke Supabase SQL Editor

1. Buka https://supabase.com/dashboard
2. Pilih projek `wxalcnpsbijxfmnzswxd`
3. Menu kiri -> **SQL Editor**
4. **Padam** teks lama dalam editor (yang menyebabkan ralat 42601)
5. Tampal kod SQL yang bos salin tadi
6. Tekan **Run** (atau `Ctrl + Enter`)

## LANGKAH 4 — Apa yang bos patut nampak

**Berjaya:**

```
Success. No rows returned
```

Itu normal — patch ini cipta fungsi dan trigger, ia tidak pulangkan data.

**Jika nampak ralat**, salin mesej penuh dan hantar kepada saya. Jangan cuba
baiki sendiri.

---

## LANGKAH 5 — Sahkan (WAJIB)

Buka fail `database/model6_p0_verify.sql`, salin semua, tampal ke SQL
Editor, tekan Run.

Bos akan dapat **9 baris keputusan**. Semua mesti `LULUS`:

| # | Ujian | Jangkaan |
|---|---|---|
| 1 | ENUM user_role | LULUS |
| 2 | Trigger on_auth_user_created | LULUS |
| 3 | Fungsi RPC P0 (3 fungsi) | LULUS |
| 4 | Allow-list role | LULUS |
| 5 | Auth user tanpa profile | LULUS |
| 6 | Profile tanpa emel | LULUS |
| 7 | Guard escalation masih aktif | LULUS |
| 8 | Taburan role | MAKLUMAT |
| 9 | Role perlu dipulihkan | LULUS atau PERHATIAN |

### Nota tentang ujian #9

Database bos ada **20 coach** dan **1 club_admin**. Jika ujian #9 tunjuk
`PERHATIAN`, itu bermakna ada akaun yang role-nya pernah dileperkan jadi
`club_admin` oleh bug lama.

**Jangan jalankan backfill B.5.3 secara automatik.** Lihat dahulu senarai yang
dipaparkan, sahkan ia betul, baru beritahu saya — kita semak bersama.

---

## SELEPAS SEMUA LULUS — beritahu saya

Saya akan pandu langkah seterusnya:

1. **Uji pendaftaran hidup** — saya boleh sahkan dari luar sama ada role
   disimpan dengan betul
2. **Jalankan patch PDPA** — tutup kebocoran 29 emel + nombor IC
3. **Commit & push** — deploy kod frontend

---

## RINGKASAN UNTUK BOS

| Perkara | Status |
|---|---|
| Backend Supabase | hidup semula |
| Patch P0 | menunggu bos Run |
| Cara Run | **sekali gus** (enum sudah ada, tak perlu asing A/B) |
| Kebocoran PDPA | masih terbuka — 29 emel terdedah |
| Kod frontend | siap, belum push |

**Tindakan bos sekarang:** salin kandungan fail (bukan nama fail), tampal,
Run.
