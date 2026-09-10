# BACKLOG.md — Work Order (status rasmi, jangan kerjakan yang DITANGGUH)

Format: setiap kerja = satu WO. AI hanya execute WO berstatus `DILULUSKAN` yang fasanya sudah dibuka. `DITANGGUH` = dilarang mula walaupun nampak mudah. `BLOCKED` = tunggu jawaban CEO/Owner — **tulis soalan, jangan teka jawapan.**

Status semasa diubah pada 2026-09-10 selepas CEO (Gemini) menjawab K1–K5 → `DECISIONS.md` §F (`DEC-021`…`DEC-026`).

| WO | Kerja | Status | Kenapa / syarat |
|---|---|---|---|
| **WO-01** | Tampal **teks penuh Blueprint v1.3 §1–64** ke `docs/memory/BLUEPRINT_V1.3.md` (fail mentah, jangan tulis semula) | 🔴 **DILULUSKAN — hanya Owner/Gemini boleh buat** | CTO tidak punya sumber sahih; menaip semula = risiko ralat. Owner copy-paste dari chat, AI hanya commit. **Selagi ini belum selesai, v1.3 masih tebusan had token chat.** |
| **WO-02** | Buang data ujian rakan dari `public/index.html` (baris 4228–4232) + auto-seed `PLAYPRO_REGISTRY_V3` (~4302) + gate `loggedInUser="Azlan"` (~3601); **kekal rekod Azlan** sebagai persona rujukan dalam dokumen sahaja | 🟠 **DILULUSKAN-PRINSIP — pelaksanaan pada fasa PELAKSANAAN** | Menyentuh UI produksi → wajib PR + ujian, bukan edit terus. Rujuk `DEC-019`, `BOUNDARIES.md` §5 |
| **WO-02b** | Kaedah buang data ujian: **(A) forward-only** vs **(B) rewrite sejarah git** | ⚪ **DEFAULT (A) BERKUAT KUASA** (Owner belum jawab; `DECISIONS.md` §G). Veto boleh diberikan bila-bila masa | (B) kos nyata: SHA **235 commit** bertukar → 4 PR lama terpinggir, branch `phase-1`/`phase-2` (11 commit) kena repush, deployment Vercel + CDN refresh, `playpro-shell-bot` trigger semula, dan hash yang dipetik dokumen Julai (yang saya sahkan **ADA**) jadi tak sah. Data = **bukan data sebenar** → CTO menasihatkan **(A)** + notis. Jangan mula (B) tanpa kelulusan bertulis |
| **WO-03** | Pecah `public/index.html`. **Diubahsuai selepas pemetaan:** punca sebenar ialah 4 gambar base64 (72.5%), bukan kod | 🔴 **DILULUSKAN (K5 / DEC-026) — dipecah 03a / 03b / 03c** | Peta + dry-run + prosedur penuh: `docs/memory/INDEX_HTML_MAP.md` |
| **WO-03a** | Luaarkan 4 blob base64 → **2 fail** (`public/assets/splash.jpg`, `public/assets/logo.jpg`; logo dideduplikasi 3→1). `index.html`: 1,204,835 → **331,345 B (-72.5%)**. Tiada perubahan logik | 🟢 **DIUKUR + DI dry-run BERJAYA — menunggu laluan PR sah** | Dry-run: `npm test` **identik** (5/4/1, kegagalan sama pra-wujud). Had sesi Arena: sesi ini hanya boleh push ke branch sesi → PR kod ini dibuka **selepas PR #5 digabung**, atau Owner benarkan commit kod masuk PR #5 (soalan **Q5**) |
| **WO-03b** | Modularisasi 160 KB JS (128 fungsi tingkat-atas) → 6 modul | 🟡 **DITANGGUH sehingga 03a + `WO-05` CI hijau** | Kekangan keras: **71 fungsi mesti kekal global** (dipanggil 172 atribut `on*=`); jangan tukar `type="module"` tanpa audit `defer`/tertib muat; jangan cipta salinan ketiga `js/` ↔ `public/js/` |
| **WO-03c** | Kecil/optimum JPEG (logo 90 KB, splash 385 KB) + WebP | ⛔ **BLOCKED — keputusan visual Owner** | Mengubah rupa halaman. CTO tidak akan buat sorok-sorok |
| **WO-04** | Ruleset `main`: PR wajib + 1 review + larang force-push/padam branch | 🔴 **DILULUSKAN — Owner buat di UI GitHub** | Token `gh` sesi CTO dapat **403** untuk `rulesets`/branch-protection. Tanpa ini `DEC-020` cuma janji |
| **WO-05** | CI workflow: `npm test` + `node --check` + sanity `supabase/migrations` + semak `assets/` ada rujukan; jalan setiap PR | 🔴 **DILULUSKAN-PRINSIP — PR kecil selepas PR #5** | Gerbang merah = tak boleh merge = satu-satunya kawalan yang AI tak boleh pujuk |
| **WO-06** | Hijaukan `tests/repository-sync.test.js` §2 (padanan teks literal → ujian **kelakuan**) | 🟠 **DILULUSKAN (test sahaja)** | Sebab tepat didokumenkan di `STATE.md` §4. **Jangan** ubah `obComplete()`; jangan tambah `throw` palsu demi hijau |
| **WO-07** | Tanda `README.md`, `docs/ARCHITECTURE.md`, `docs/DEPLOYMENT.md`, `docs/DATABASE.md`, `docs/TROUBLESHOOTING.md` dengan notis `⚠️ SUPERSEDED — baca docs/memory/STATE.md` (1 baris di atas fail; jangan padam) | 🟠 **DILULUSKAN-PRINSIP** | Antara punca terbesar halusinasi skema. Doc-only, risiko rendah. Senarai bukti: `EVIDENCE.md` §E |
| **WO-08** | **Eksport kebenaran produksi** → `supabase/migrations/0001_baseline.sql` **di branch** | 🔴 **KEUTAMAAN #1 — DILULUSKAN (K2 / DEC-022)** | **Kit sedia:** `docs/memory/sql/PRODUCTION_TRUTH_EXPORT.sql` (28 blok, **diaudit read-only oleh parser SQL: 0 aksi tulis**). Owner jalankan di `playpro2` **dan** `playpro`. **Boleh mula hari ini** — SELECT sahaja, tidak menunggu sesiapa |
| **WO-09** | Baiki `register_my_player()` (jangan tulis `profiles.identification_number`; ikut R-03 **yang kini DIJAWAB: DEC-029**) | 🟠 **HALANGAN SEMANTIK TIADA LAGI — tinggal halangan gerbang**: pelaksanaan = **DDL produksi** → terikat 7 langkah Fasa 2C | ⚠️ **Kos yang Owner kena tahu: pendaftaran pemain di produksi KEKAL ROSAK sehingga `WO-08` → baseline → Fasa 2C langkah 1–6 selesai.** Tiada jalan pintas yang selamat; inilah sebab kita tidak "edit laju di Dashboard" |
| **WO-10** | Selaraskan `auto_suspend_on_red_card()` 1 → **2** perlawanan + ujian (`DECISIONS.md` §E) | 🟡 **BLOCKED (fasa PELAKSANAAN)** | Gerbang sama dengan WO-09; sepatutnya masuk **satu** PR DDL yang sama, dengan body semasa disalin dari `q22` export |
| **WO-11** | Lepaskan `playpro-shell-v1.yml` daripada hak `contents: write` (bot tidak boleh push ke `main`) | 🟠 **DILULUSKAN-PRINSIP** | Bot pernah menyunting `index.html` + push sendiri (`fd0fadf`). Selepas `WO-04`, uji sama ada ruleset sudah menghalang bot; jika belum, ini penyelesaian pastinya |
| **WO-12** | Padam `.github/skills/ui-ux-pro-max/SKILL.md` (dead) + selesaikan drift `src/` ↔ `public/src/` | 🟡 **DITANGGUH** | Kebersihan; jangan campur dengan fasa lain |
| **WO-13** | Alihkan redirect auth keluar dari `v0.app` ke domain PlayPro sendiri | 🟡 **BLOCKED — Owner (perniagaan + DNS)** | Baris 16 `index.html`. Selagi belum selesai, aliran login bergantung infrastruktur V0 |
| **WO-14** | `sirr` (aplikasi lain milik Owner) | ⚫ **LUAR SKOP — jangan sentuh, jangan cadang apa-apa** | Keputusan Owner 2026-09-10. Hanya berkongsi kuota Supabase free tier |
| **WO-15** | Gabungkan branch memori yang tertinggal ke `main` sebagai PR: `phase-1/system-contract` (1 commit — `docs/PLAYPRO_SYSTEM_CONTRACT.md`) + `phase-2/canonical-model` (10 commit — 9 dokumen Fasa 2/2B/2C/3 + `supabase/migrations/PHASE2_DEV_BASELINE.sql`) | 🟠 **DILULUSKAN-PRINSIP — merge tetap perlu kelulusan Owner** | Disemak: `ahead_by` 1 dan 10, `behind_by` 5, **tiada PR untuk kedua-duanya**. **Ubat amnesia paling murah**: kontrak + gerbang 7 langkah + baseline dev sudah ditulis tapi `main` tidak tahu. **Tiada DDL dijalankan** — fail SQL itu teks baseline dev sahaja |
| **WO-16** | Butiran dasar `R-03a`: siapa **melulus/menolak** dokumen LANJUT, **tempoh sah laku** pengesahan, tindakan apabila **tamat**, dan hak **rayuan** | 🟡 **BLOCKED — CEO (soalan perniagaan, bukan teknikal)** | `DEC-029` sudah buka *tahap*, bukan *proses*. Fasa A boleh mula direka tanpa ini **asalkan** laluan kelulusan ditinggalkan sebagai RPC tertakluk polisi; CTO tidak akan tetapkan lalai diam-diam |
| **WO-17** | Simpanan dokumen pengesahan (bucket + polisi akses + retensi) untuk tahap LANJUT | 🟡 **DITANGGUH sehingga fasa SKEMA** | Keperluan direkod dalam `DEC-029`; **imej dokumen DILARANG** muncul dalam public view (`PHASE2C P1-9`, `DEC-019`) |

---

## Susun atur pelaksanaan selepas PR #5 digabung

```
HARI INI (boleh paralel, tiada risiko DB):
  WO-01  Owner/Gemini tampal teks penuh v1.3
  WO-04  Owner cipta ruleset main (4 minit, UI GitHub)
  WO-08  Owner jalankan sql/PRODUCTION_TRUTH_EXPORT.sql di playpro2 + playpro  ← read-only
  Q3,Q4,Q5 dijawab Owner

LEPAS PR #5 (dokumen) DIJUALUSKAN:
  WO-15  gabungkan branch phase-1 + phase-2      (PR #6, doc + SQL teks)
  WO-06  hijaukan repository-sync                (PR #7, test sahaja)
  WO-05  CI workflow                              (PR #8)
  WO-11  bot jadi read-only                       (PR #9)
  WO-07  tanda SUPERSEDED                         (PR #10)
  WO-03a luaran aset index.html                    (PR #11 — PR *kod* pertama, selepas CI ada)

BARU DIBUKA:
  rekonsiliasi WO-08 → 0001_baseline.sql di branch → Fasa 2C langkah 1–6 →
  REKA BENTUK SKEMA (teks cadangan, tiada DDL dijalankan)
```

---

## Soalan yang MASIH TERBUKA (pusingan 2 — selepas K1…K5)

| # | Soalan | Untuk | Kenapa penting |
|---|---|---|---|
| **Q1** | **R-05a:** apakah **nilai pemberat** setiap atribut dalam purata wajaran OVR, dan bagaimana bahagian fizikal vs teknikal dibahagi? | CEO | `DEC-024` beri **bentuk** formula, bukan **nombor**. Tanpa nombor, fasa skema tak boleh buka lajur/konfigurasi OVR. CTO **menolak meneka** |
| **Q2** | Pemberat itu **tetap** atau **berversi** (boleh berubah ikut musim/peraturan)? | CEO | Menentukan bentuk simpanan (jadual konfigurasi berversi) dan jejak provenance (DEC-015/016) |
| **Q3** | **WO-02b: (A) forward-only atau (B) rewrite sejarah git?** | **Owner** | Saya tidak akan putuskan ini; (B) menyentuh 235 commit + 4 PR + 2 branch |
| **Q4** | `"27091976-05-AZLN"` dalam rekod Azlan: pasport **sebenar** atau **rekaan**? Jika benar → saya tukar ke `EXMP-1976-0001` dalam dokumen | **Owner** | 15 saat; mengelak dokumen rujukan kita menjadi pendedahan PII anda sendiri |
| **Q5** | Laluan pelaksanaan **WO-03a**: (i) tunggu PR #5 digabung, buka PR kod baharu · (ii) Owner benarkan commit kod masuk PR #5 sekarang | **Owner** | Anda kata "mula sekarang" (K5); had teknikal sesi saya = hanya satu branch boleh dipush. Pilih laluan; jangan suruh saya langgar `DEC-020` |
| **Q6** | Baki item terbuka: **R-01** (organizer fizikal), **R-04** (custody — ditangguh oleh `DEC-006`, OK kekal OPEN), **R-07** (skop KEDAI). R-03 ✅ dijawab (`DEC-029`), R-06 ✅ disahkan (`DEC-030`) — **jangan tanya lagi** | CEO | Tiada satu pun menyekat pembukaan fasa SKEMA; R-01 mungkin menyentuh bentuk jadual organizer → jawab sebelum fasa C |

**Tiada satu pun soalan di atas boleh dijawab CTO dengan rekaan.** Q1/Q2 sudah dijawab (→ `DEC-027`/`DEC-028`); Q3/Q4/Q5 belum dijawab dan **default selamat sudah berkuat kuasa** (lihat `DECISIONS.md` §G) — Owner tidak akan ditanya ulang, hanya boleh veto.
