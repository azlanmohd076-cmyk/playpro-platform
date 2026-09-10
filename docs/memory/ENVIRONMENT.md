# ENVIRONMENT.md — Apa Yang Benar-Benar Wujud (jangan reka yang lain)

Disediakan oleh CTO (Arena), 2026-09-10. `DISAHKAN` = diukur dari API GitHub / fail repo. `DILAPORKAN` = disebut dalam perbualan/audit Owner; **tidak** boleh disahkan dari sandbox Arena (rangkaian ke `supabase.com` disekat TLS — semakan saya gagal dengan `curl` exit 35).

---

## 1. GitHub — **SATU** repo sahaja

| Perkara | Nilai | Status |
|---|---|---|
| Repo | `azlanmohd076-cmyk/playpro-platform` (public, default `main`) | DISAHKAN |
| Repo lain milik akaun | **tiada** — `gh api users/azlanmohd076-cmyk/repos` memulangkan 1 rekod | DISAHKAN |
| Jumlah fail dikesan | 127 | DISAHKAN |
| Jumlah commit di `main` | 235 (HEAD `23569ac`) | DISAHKAN |
| Ruleset / branch protection | `rulesets` → `0` item; `branches/main/protection` → **403** (token CTO tak cukup skop, jadi status sebenar mungkin "tiada" atau "tak boleh dilihat") | DISAHKAN (sebahagian) |
| Workflow | `.github/workflows/playpro-shell-v1.yml` — **menyunting `public/index.html` + `public/playpro_public.html` dan push auto-commit ke `main`** (contoh: `fd0fadf` oleh `github-actions[bot]`) | DISAHKAN |
| `.github/skills/ui-ux-pro-max/SKILL.md` | **mati** (dead skill), jangan rujuk | DISAHKAN |

> **KESILAPAN RASMI #1** (lihat `AGENTS.md` §2): ayat *"bina baru dalam repo `playpro`, beku repo `playpro2`"* **tidak boleh dilaksanakan** — itu **projek Supabase**, bukan repo. Jangan cipta repo kedua; satu-satunya code truth ialah `playpro-platform`.

---

## 2. Supabase — **3 projek** (ini yang "dibeku/dihidupkan" dalam perbualan)

| Projek | Peranan | Keadaan (DILAPORKAN, Owner perlu sahkan sendiri) |
|---|---|---|
| **`playpro2`** | **PRODUKSI / AKTIF** — skema kanonik (17 → ~21 jadual selepas Fasa-3), 5 views, 14 fungsi, 16 trigger, 57 policy, **0 migration tracked** | AKTIF. **Skema JANGAN disentuh** tanpa work order + turutan 7 langkah Fasa 2C |
| **`playpro`** | **LEGACY** — skema lama (`users, players, teams, team_coaches, tournaments, tournament_teams, matches, standings, player_cards, player_stats, trainings, training_attendance, player_evaluations, activity_logs, suspensions`), fungsi `check_suspensions()`, `update_standings()`, migrasi `20250903093256_raspy_thunder`; row: `teams`=1, `users`=2, lain 0 | Dilaporkan **diaktifkan semula** untuk pemeriksaan; **5 jadual RLS DISABLED** → pendedahan langsung selagi AKTIF |
| **`playpro1`** | projek **kosong** (0 jadual aplikasi) selepas restore — pernah dipakai untuk forensik "Azlan" | Dilaporkan **di-pause semula** untuk menjimatkan kuota |

**Had kuota free tier: 2 projek aktif.** Inilah sebab sebenar CEO dulu pause/restore berkali-kali. Implikasi untuk AI: **anda tidak boleh "buka satu projek dev baharu" sesuka hati** — ia memaksa satu projek lain di-pause, dan itu mungkin produksi.

**`sirr` = LUAR SKOP.** Keputusan Owner 2026-09-10: `sirr` ialah **aplikasi lain yang tiada kaitan dengan PlayPro**; ia hanya **berkongsian kuota Supabase free tier** yang sama, dan itulah sebabnya ia disebut-sebut dalam perbualan (di-pause untuk memberi ruang projek PlayPro). Peraturan: **jangan** sentuh, jangan cadang pause/restore, jangan masukkan ke dalam mana-mana pelan PlayPro. Kalau diperlukan slot: Owner yang pilih projek mana dikorbankan.

*(Pembetulan daripada CTO: dalam pusingan sebelum ini saya bertanya "adakah `sirr` perlu dihidupkan semula" seolah-olah ia tanggungjawab PlayPro. Itu salah tafsir saya terhadap bahan perbualan — soalan itu bukan urusan PlayPro.)*

---

## 3. Deployment / hosting

| Perkara | Nilai | Status |
|---|---|---|
| Vercel | `vercel.json` → `outputDirectory: "public"`, rewrites: `/`→`index.html`, `/app`→`app.html`, `/card`→`player_card.html`, `/ops`→`dev_panel.html` | DISAHKAN |
| Kesan penting | Fail di `/js/*.js` (akar) **tidak dihidang** (404) kerana hanya `public/` yang di-deploy. `public/js/*.js` = versi yang hidup | DISAHKAN |
| `public/index.html` | Aplikasi produksi sebenar, 1,204,835 B / 6,127 baris | DISAHKAN |
| Konfigurasi auth | `window.PLAYPRO_SUPABASE_REDIRECT_URL = 'https://v0.app/chat/api/supabase/redirect/…'` (baris 16) — redirect masih lalu infrastruktur **V0** | DISAHKAN |
| Domain live yang dipakai Owner | `v0.app` / Vercel preview (disebut dalam audit 27 Ogos) | DILAPORKAN |

---

## 4. Struktur fail yang penting (ringkas)

```
public/index.html            ← 1.2 MB monolith: aplikasi + PII ujian + logik privasi pelayar
public/*.html                ← 17 halaman di tahap atas (README kata "8 HTML" → SALAH)
public/js/  vs  js/          ← salinan; md5 setakat ini sama (repositories.js, supabase.js)
src/modules/…               ← vs public/src/modules/… → MASIH DRIFT (tidak sama)
database/*.sql              ← 29 fail SQL LEGACY: skema lama; HATI-HATI:
                               database/playpro_phase2_additions.sql:431 CREATE TABLE match_events
                               → nama LANGGAR dengan jadual Fasa-3 di produksi
supabase/migrations/        ← TIADA di main. Hanya ada di branch phase-2/canonical-model
                               (1 fail: PHASE2_DEV_BASELINE.sql, 18,638 baita)
docs/memory/                ← direktori ini (MASTER CONTEXT, PR #5)
AGENTS.md                   ← peraturan tetap, dibaca semua AI
```

---

## 5. Batas kemampuan CTO di dalam sandbox Arena (baca ini sebelum marahkan AI)

| Cuba | Hasil |
|---|---|
| `curl https://api.supabase.com` / `muirhenvjruvfxenoaxm.supabase.co` | **gagal** (HTTP 000 / TLS exit 35) → tiada cara sahkan DB/RPC/RLS dari sini |
| `git fetch` refs branch `phase-*` | **tiada tracking ref** → guna `gh api .../contents/<path>?ref=<branch>` atau `git/trees/<sha>` |
| `gh api` untuk secrets / hooks / deploy keys / branch protection | **403 Resource not accessible by integration** → CTO tak boleh semak atau cipta ruleset; **Owner** perlu buat dalam UI GitHub |
| Tulis ke `main` secara terus | **Boleh** secara teknikal, **DILARANG** oleh `DEC-020` |
| `npm test` / `node --check` | Jalan dan berkesan — ini satu-satunya gerbang mekanikal yang kita ada sekarang |

---

## 6. Aset yang **tidak** wujud (jangan tunggu, jangan cari)

- Tiada `AGENTS.md` sebelum PR ini · Tiada `docs/memory/` · Tiada `STATE.md`/`DECISIONS.md` versi terdahulu
- Tiada workflow CI ujian · Tiada PR untuk `phase-1/system-contract` & `phase-2/canonical-model`
- Tiada migrasi untuk Fasa-3 · Tiada rujukan kepada `match_state`, `record_match_event`, `void_match_event`, `match_playing_time`, `match_admin_assignments` **dalam mana-mana fail repo** (saya `grep` semua `*.sql`/`*.js`/`*.html` → 0 padanan)
- Tiada teks penuh Blueprint v1.3 dalam Git (§1–64 hanya ada dalam perbualan Owner) → **WO-01**
- Hash yang dipetik dalam dokumen Julai (`ff7b756`, `263d816`, `2624711` dsb.) **memang ADA** di `main` — jangan percaya kata orang "sejarah dah hilang"; ia nampak hilang hanya kerana clone Arena adalah shallow (1 commit).
