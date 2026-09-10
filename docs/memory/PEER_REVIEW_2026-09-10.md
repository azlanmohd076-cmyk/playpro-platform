# PEER_REVIEW_2026-09-10 — Semakan bebas ChatGPT (bekas CTO) terhadap `playpro2` live

**Kenapa fail ini wujud:** ChatGPT membuat semakan **read-only terus ke GitHub + Supabase live** dan menemui beberapa angka dalam `docs/memory/` kami **sudah lapuk**. Bahan sebegini selalunya mati dalam tetingkap chat. Ia disimpan di sini supaya menjadi **sebahagian daripada memori projek**, bukan kenangan sesi.

| | |
|---|---|
| **Penyemak** | ChatGPT (peranan baharu: **Reviewer**; bekas CTO) — ada akses live ke GitHub **dan** Supabase |
| **Tarikh** | 2026-09-10 |
| **Kaedah** | Query metadata Supabase + advisor + GitHub API. **Tiada perubahan dibuat** pada repo atau DB (disahkan oleh keadaan repo: `main` masih `23569ac`) |
| **Status angka di bawah** | `DISAHKAN-BY-REVIEWER` = disahkan oleh penyemak melalui akses live yang **CTO semasa tidak punya**. Bukan `DISAHKAN-BY-CTO`. Sandbox Arena **tiada** TLS ke Supabase (`ENVIRONMENT.md` §5) |
| **Pengiktirafan CTO** | Angka `14 fungsi / 57 policy / 0 migration tracked` yang kami bawa dari `docs/PLAYPRO_SYSTEM_CONTRACT.md` (audit 27–28 Ogos) dan daripada perbualan CEO **adalah LAPUK untuk keadaan live**. Ia bertanda `DILAPORKAN` dalam dokumen kami, tetapi itu **tidak** menjadikannya betul. Dimaafkan diri, dibetulkan di `EVIDENCE.md` §C + `ENVIRONMENT.md` §2 |

---

## 1. Ditegulkan (semakan bebas mengesahkan dapatan CTO)

- **1 repo sahaja** (`azlanmohd076-cmyk/playpro-platform`), default `main`; tiada "repo `playpro`/`playpro2`" → **kesilapan kategori #1** yang kami betulkan adalah betul.
- PR #5: OPEN, belum di-merge, `mergeable=true`, **8 commit · 9 fail · +1,343 · −0**, `ahead_by=8`, `behind_by=0`.
- PR #5 **tidak** menyentuh `public/*` mahupun `src/*`; SQL export hanya fail teks, tidak dijalankan.
- `supabase/migrations` di `main` → **404**, dan wujud di `phase-2/canonical-model` sebagai `PHASE2_DEV_BASELINE.sql`.
- Isu keselamatan/performance yang kami senaraikan: **`referees` RLS-on/0 policy** · **13 `SECURITY DEFINER` boleh dipanggil `authenticated`** · **leaked-password protection DISABLED** · **24 FK tanpa index** · **35 index tidak digunakan** · **16 kumpulan policy permissive berganda** · **18 auth/RLS initplan** → semua **disahkan live**, bukan lagi laporan.
- `match_events` + `match_participants` + `match_admin_assignments` + `match_playing_time` **memang wujud** di produksi, dan **tiada dalam Git** → sebab `WO-08` itu sendiri.
- `match_events.sequence` dibekalkan pada rekod → kebimbangan `P1-5` (Fasa 2C) **belum semestinya selesai**.
- Legacy `playpro`: **5 jadual public tanpa RLS** + `team_coaches`/`tournament_teams`/`users` RLS-on tiada policy + `check_suspensions()`/`update_standings()` amaran `search_path` mutable → **kini disahkan live** (dulu `DILAPORKAN`).
- Pendekatan `WO-08` = betul, dan **baseline mesti dari live, bukan daripada laporan/`database/*.sql`/frontend/andaian**.

## 2. Yang MEMBETULKAN dokumen kami

| Dakwaan kami | Live sebenarnya (penyemak) | Tindakan |
|---|---|---|
| `playpro2` = **14 fungsi** | **20 fungsi** | `EVIDENCE.md` §C dibetulkan |
| `playpro2` = **57 policy** | **61 policy** | sama |
| `playpro2` = **0 migration tracked** | **4 migration** (lihat §4) | sama — dan ini yang paling besar |
| Jadual 21 (anggaran "~21") | **21 tepat**, senarai penuh ada | senarai disimpan di §3 |
| Views 5 · Triggers 16 | **sama** ✔ | — |
| "7 fail memori" (BOUNDARIES §7, log DECISIONS) | **9 fail** | dibetulkan; angka "7" hanya betul untuk **commit pertama** `a7288b9` (+671) |

Satu perkara yang **bukan** kesilapan fakta tapi salah dibaca: `STATE.md` §0(4) menulis `0 migration tracked` **di `main`** (sisi GitHub) — itu betul dan penyemak sendiri sahkan (404). Yang salah ialah **`ENVIRONMENT.md` §2** dan **`EVIDENCE.md` §C** memakai angka yang sama untuk sisi **Supabase** tanpa membezakan kedua-dua tempat. Pemisahan "Git vs DB" kini dijadikan peraturan penulisan (lihat §6).

## 3. Senarai 21 jadual live `playpro2` — `DISAHKAN-BY-REVIEWER`

```
profiles  leagues  league_staff  clubs  league_clubs  players  coaches  fixtures
match_results  player_match_stats  disciplinary_records  suspensions  standings
player_assessments  coach_assessments  club_assessments  referees
match_participants  match_admin_assignments  match_events  match_playing_time
```

**TIDAK wujud** di live: `organizers` · `organizations` · `teams` · club membership · team assignment · competition categories · competition registrations · squads · `verification_cases` · `capabilities` · kad/pasport pemain · riwayat kerjaya · follow/sosial · payment · wallet.

Implikasi yang wajib dibaca oleh sesi seterusnya (ini lanjutan fakta, bukan keputusan):
- Domain v1.3 **belum tercermin** di DB. Fasa A (Identity & Trust) **bukan** "kemaskan yang sedia ada" sepenuhnya — sebahagiannya **inapan kosong** (`capabilities`, `verification_cases`).
- `DEC-023` (R-02: `leagues` → `Competition.format` + view keserasian) kini ada tanah nyata: **`competitions` tiada**, **`leagues`/`league_staff`/`league_clubs` ada**.
- **`teams` tiada langsung** → rantai `DEC-003` (`Competition → Category → Participation → Team → Squad → Player`) belum mula dibina.

## 4. 4 migration yang wujud di `playpro2` (dan apa maksudnya)

```
20260908175624  phase3_security_boundary_hardening
20260908182106  phase3_match_stat_reconciliation_contract
20260908184858  phase3_match_event_engine_foundation
20260909003126  phase3_match_observer_rpc_engine_v1
```

Makna yang tepat, dan ini yang ramai silap baca:
1. **Bukan** "Git dah ada migration". Git `main` tetap **404**. Yang ada = **Supabase menyimpan sejarah migrasinya sendiri**.
2. Maknanya Fasa-3 **memang melalui tracking Supabase**, jadi nama+version **boleh dipulihkan**, tetapi **teks SQL-nya tiada di mana-mana dalam Git**.
3. Maka `0001_baseline.sql` **tidak boleh** dijana dengan "salin 4 fail itu" — failnya tidak ada. Ia mesti **introspeksi DB** (`EVIDENCE.md` §D / `WO-08`) **lalu** direkonsiliasi dengan 4 version ini supaya nama/fasa sepadan.
4. Ini **mengukuh**, bukan melemahkan, `DEC-022`: gerbang eksport dahulu adalah tepat sebab *hanya* introspeksi boleh memberi DDL sebenar.

## 5. jurang SEMASA → SASARAN (direkod supaya tidak perlu ditemui semula)

| ID temuan | Fakta live | Sasaran v1.3 | Status |
|---|---|---|---|
| **DRIFT-007** | `players.club_id` wujud, FK → `clubs.id` (juga `profile_id`) | `Player → Club Membership → Team Assignment` | 🔴 GAP — **jangan ubah sekarang**; input wajib fasa skema |
| **DRIFT-008** | `match_events.team_id` → **`clubs.id`**; `match_participants.club_id` → `clubs.id`. Tiada `teams` | `CLUB → TEAM → PARTICIPATION → SQUAD → MATCH` | 🔴 GAP paling dalam: "team" hari ini = kelab |
| **DRIFT-009** | `match_results` simpan gol/possession/shots/kad; `player_match_stats` simpan goals/assists/shots/kad/saves/`minutes_played` | `match_events` = **satu-satunya** kebenaran; statistik = **terkira** | 🔴 **DUA/BERBILANG SUMBER KEBENARAN** — perlu `RECONCILE` (mungkin mekanisme Fasa-3 sudah menjaganya; **belum disahkan**). Keputusan: semak definisi fungsi + 4 migration **sebelum** baseline diterima |
| **DRIFT-010** | `match_participants.is_eligible boolean` + `eligibility_reasons jsonb` | Eligibility = kitaran hayat **berasingan**; `ACTIVE ≠ ELIGIBLE` (`MA-02`) | 🟡 Boleh kekal sebagai **snapshot terkira** — tetapi mesti **dikunci secara tertulis** sebagai `Eligibility Engine → snapshot`, bukan sumber kebenaran. Fasa skema wajib memutuskan |
| **DRIFT-011** | `player_assessments` ada lajur skor + `assessor_id` → `profiles.id`; tiada rantaian pengesahan penilai | `Coach (certified) → Assessment (append-only, versioned) → Verified Attribute Version → OVR` (`DEC-016`) | 🟠 Jadual ada, **model tadbir urus tiada**. Lajur `weight` tunggal **dilarang** (`DEC-028`) |
| **DRIFT-012** | Fungsi live termasuk `get_my_role`, `is_club_admin`, `is_league_admin`, `is_league_founder_or_developer`, `match_observer_scope_for` — semua `SECURITY DEFINER` + boleh dipanggil `authenticated` | Model **capability** menggantikan `profiles.role` | 🟠 Bukti bahawa "logik peran an" masih hidup dan *boleh dipanggil* — bukan sekadar isu grant, ini isu **semantik** yang menyentuh `DEC-009` |

**`playpro1`:** penyemak **tidak** dapat mengaksesnya (connection timeout) → status rasmi **`TAK SEMAK`**, bukan "kosong". Dakwaan "0 jadual aplikasi" yang kami bawa dari perbualan CEO diturunkan taraf kepada `DILAPORKAN (Owner, 2026-09-09)` → `WO-26`.

## 6. Peraturan penulisan baharu yang lahir daripada review ini (ditaruh ke `AGENTS.md`)

> Setiap nombor tentang **struktur pangkalan data** wajib menyatakan **sumbernya secara eksplisit**: `[GIT]` (apa yang ada dalam repo) atau `[DB]` (apa yang ada di Supabase). Dua-dua pernah disamakan dalam dokumen kami, dan itulah sebabnya "0 migration" dibaca sebagai dua perkara berbeza. Nombor `[DB]` juga wajib ada **tarikh + kaedah**, dan **tidak boleh dikekalkan sebagai kebenaran selepas 1 minggu**.

## 7. Tiga benda yang kami perlukan daripada Penyemak (dia ada akses, kami tidak)

1. **Jalankan `docs/memory/sql/PRODUCTION_TRUTH_EXPORT.sql`** (28 blok, read-only) di `playpro2` dan tampal balik keluaran **q03b** (adakah `profiles.identification_number` wujud?), **q12** (kewujudan `fixtures.match_state` + objek Fasa-3), **q10** (senarai 61 policy penuh), **q20/q21** (DDL jadual + fungsi). Empat blok ini sahaja sudah menamatkan hujah DRIFT-009 dan akar WO-09.
2. **Salin teks 4 migration** itu (Supabase → Migration history / SQL editor snippet) supaya Git boleh memilikinya, bukan hanya namanya. Selepas itu `0001_baseline.sql` boleh disahkan silang.
3. **Sahkan/nafikan** satu angka kami yang belum dia sentuh: `rows` — `profiles` 4 · `players` 3 (Adam, ds, lokmn) · lain 0. Kalau betul, senarai `WO-02` (buang data ujian) boleh dilaksanakan dengan tepat.

Kami **tidak** meminta dia mengubah apa-apa. `ENVIRONMENT.md` §5 kekal: CTO semasa tak boleh semak DB dari sandbox — itulah sebabnya review dia bernilai, dan itulah sebabnya kami minta output, bukan opini.

## 8. Keputusan yang dikekalkan (tiada yang berubah pada tadbir urus)

🟢 v1.3 kekal beku · 🟢 PR #5 diteruskan untuk semakan CEO/Owner · 🟡 dokumen `docs/memory/` = **konteks + daftar keputusan**, **bukan** gambaran live DB (dan memang itu tujuannya) · 🔴 **jangan ubah Supabase produksi** · 🔴 **jangan ubah `main`** · 🔴 **fasa skema belum dibuka** · 🟦 gerbang seterusnya **`WO-08`**.
