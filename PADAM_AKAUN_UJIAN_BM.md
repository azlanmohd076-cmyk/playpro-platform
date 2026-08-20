# Cara Padam 8 Akaun Ujian — Panduan Lengkap

**Tarikh:** 2026-07-26
**Kenapa perlu:** Akaun ini saya cipta untuk mengesahkan patch P0 berfungsi.
Ia bukan pengguna sebenar dan patut dibuang supaya statistik bos bersih.

---

## Senarai akaun yang perlu dipadam

Semua berakhir dengan `@playpro-test.my`:

| # | Emel | Role |
|---|---|---|
| 1 | `ujian.pemain.1785083424@playpro-test.my` | player |
| 2 | `uji.coach.1785083441@playpro-test.my` | coach |
| 3 | `uji.club_admin.1785083441@playpro-test.my` | club_admin |
| 4 | `uji.league_admin.1785083441@playpro-test.my` | league_admin |
| 5 | `uji.referee.1785083441@playpro-test.my` | referee |
| 6 | `uji.jurulatih.1785083441@playpro-test.my` | coach |
| 7 | `uji.developer.1785083441@playpro-test.my` | player |
| 8 | `uji.technical_assessor.1785083441@playpro-test.my` | player |

> **PENTING:** Tiada satu pun akaun sebenar bos berakhir dengan
> `@playpro-test.my`. Domain itu sengaja saya pilih supaya senang ditapis
> dan mustahil terkena akaun sah.

---

# KAEDAH 1 — SQL Editor (disyorkan, paling cepat)

Satu arahan padam semuanya. Kerana `profiles.id` ada
`REFERENCES auth.users(id) ON DELETE CASCADE`, memadam dari `auth.users`
akan **automatik** memadam baris `profiles` yang berkaitan.

## Langkah 1 — Lihat dahulu sebelum padam (WAJIB)

Tampal ini ke SQL Editor, tekan Run:

```sql
SELECT id, email, created_at
FROM auth.users
WHERE email LIKE '%@playpro-test.my'
ORDER BY email;
```

**Sahkan bos nampak tepat 8 baris**, dan semuanya berakhir dengan
`@playpro-test.my`. Jika bilangannya lain, **BERHENTI** dan beritahu saya.

## Langkah 2 — Padam

Selepas sahkan senarai betul, tampal ini dan Run:

```sql
DELETE FROM auth.users
WHERE email LIKE '%@playpro-test.my';
```

Jangkaan: `Success. No rows returned` atau mesej menunjukkan 8 baris dipadam.

## Langkah 3 — Sahkan sudah bersih

```sql
SELECT
  (SELECT count(*) FROM auth.users WHERE email LIKE '%@playpro-test.my') AS auth_baki,
  (SELECT count(*) FROM profiles  WHERE email LIKE '%@playpro-test.my') AS profil_baki,
  (SELECT count(*) FROM profiles) AS jumlah_profil_sekarang;
```

Jangkaan:

| auth_baki | profil_baki | jumlah_profil_sekarang |
|---|---|---|
| 0 | 0 | **29** |

29 ialah bilangan asal bos sebelum saya buat ujian.

---

# KAEDAH 2 — Melalui Dashboard (jika lebih selesa klik)

1. Buka https://supabase.com/dashboard
2. Pilih projek `muirhenvjruvfxenoaxm`
3. Menu kiri → **Authentication** → **Users**
4. Dalam kotak carian, taip: `playpro-test`
5. Bos akan nampak 8 pengguna
6. Bagi setiap satu: klik **⋮** (tiga titik di kanan) → **Delete user** → sahkan

Ulang 8 kali. Lebih perlahan, tetapi bos nampak setiap satu sebelum padam.

---

# Kenapa saya tidak boleh padam sendiri

Memadam pengguna memerlukan kunci **`service_role`** — kunci pentadbir penuh
yang boleh memintas semua RLS dan membaca/menulis segala-galanya dalam
database bos.

Saya hanya ada kunci **`anon`** (yang memang terdedah dalam HTML awam bos).

Saya **tidak** meminta kunci `service_role`, dan bos **tidak sepatutnya**
memberikannya kepada sesiapa — termasuk saya. Kunci itu sepatutnya hanya
wujud di dalam Supabase dashboard dan pelayan backend bos sahaja.

Ini sebabnya langkah padam ini perlu bos buat sendiri.

---

# Nota keselamatan

Jangan ubah suai `LIKE '%@playpro-test.my'` kepada corak yang lebih luas.
Contohnya `LIKE '%uji%'` akan turut memadam akaun sah yang mengandungi
perkataan "uji" pada emel mereka.

Jika bos ragu-ragu, jalankan Langkah 1 dahulu dan kira baris.
