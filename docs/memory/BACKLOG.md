# BACKLOG.md — Work Order (status rasmi, jangan kerjakan yang DITANGGUH)

Format: setiap kerja = satu WO. AI hanya execute WO yang statusnya `DILULUSKAN` dan fasanya sesuai. `DITANGGUH` = dilarang mula, walaupun nampak "senang". `BLOCKED` = tunggu jawaban dari CEO/Owner (tulis soalan, jangan teka).

| WO | Kerja | Status | Kenapa / syarat |
|---|---|---|---|
| **WO-01** | Tampal **teks penuh Blueprint v1.3 §1–64** ke `docs/memory/BLUEPRINT_V1.3.md` (fail mentah, jangan tulis semula) | 🔴 **DILULUSKAN — tetapi HANYA Owner/Gemini boleh buat** | CTO tidak ada sumber sahih; menaip semula = risiko ralat. Owner copy-paste teks penuh dari chat CEO, AI cuma commit. **Sebelum ini, v1.3 belum selamat daripada token-limit.** |
| **WO-02** | Buang data ujian rakan dari `public/index.html` (baris 4228–4232) + auto-seed `PLAYPRO_REGISTRY_V3` (4302) + gate `loggedInUser="Azlan"` (3601); **kekal rekod Azlan** sebagai persona rujukan dalam dokumen sahaja | 🟠 **DILULUSKAN-PRINSIP — pelaksanaan menunggu fasa PELAKSANAAN** | Ia menyentuh UI produksi. Perlu PR + ujian, bukan edit terus. Rujuk `DEC-019`, `BOUNDARIES.md` §5 |
| **WO-02b** | Putuskan kaedah "buang dari sejarah git + CDN": **(A) forward-only** (buang sekarang, sejarah kekal) atau **(B) rewrite sejarah** (`git filter-repo`) | 🟡 **BLOCKED — keputusan Owner wajib** | (B) **kos nyata**: 235 commit jadi SHA baharu → 4 PR lama menunjuk commit terpinggir, branch `phase-1`/`phase-2` (11 commit) perlu repush, semua deployment Vercel + cache CDN perlu redeploy, `playpro-shell-bot` akan trigger lagi. Data = **bukan data sebenar** → menurut CTO, (A) + NOTIS sudah memadai; (B) hanya kalau Owner mahu "kosongkan rekod" demi prinsip. Jangan mula (B) tanpa kelulusan bertulis |
| **WO-03** | Pecah `public/index.html` (1.2 MB monolith) → modul yang dimuatkan | 🟡 **CADANGAN DITERIMA-PRINSIP, belum dijadual** | Ini **ubat mechanistic** bagi halusinasi AI (bacaan terpotong). Lakukan **selepas** MASTER CONTEXT, sebelum/selari fasa skema supaya AI tidak lagi buta. Jangan sentuh logik semasa memecah |
| **WO-04** | Ruleset `main`: PR wajib + 1 review + larang force-push/padam branch | 🔴 **DILULUSKAN — perlu Owner di UI GitHub** | Token `gh` dalam sesi CTO mendapat **403** untuk `rulesets`/branch-protection → CTO tak boleh cipta. Tanpa ini, `DEC-020` cuma janji |
| **WO-05** | CI workflow: `npm test` + `node --check` + `git ls-files supabase/migrations` sanity, jalan setiap PR | 🔴 **DILULUSKAN-PRINSIP** (CTO boleh tulis dalam PR berasingan selepas MASTER CONTEXT) | "Gerbang merah = tak boleh merge" = satu-satunya enforcement yang AI tak boleh langkau |
| **WO-06** | Hijaukan `tests/repository-sync.test.js` §2 (tukar padanan teks literal → ujian **kelakuan**) | 🟠 **DILULUSKAN (test sahaja)** | Sebab tepat: `tests/repository-sync.test.js:27` mendesak padanan teks persis `if(playerResult.error) throw playerResult.error`, manakala `public/index.html:5042-5043` mengangkat ralat sebagai `rpcError||!rpcOk` → `toast`. Niat dipenuhi, teks lapuk. **Jangan** ubah `obComplete()`; jangan tambah `throw` palsu demi hijau |
| **WO-07** | Tandai `README.md`, `docs/ARCHITECTURE.md`, `docs/DEPLOYMENT.md`, `docs/DATABASE.md`, `docs/TROUBLESHOOTING.md` dengan notis `⚠️ SUPERSEDED — baca docs/memory/STATE.md` (1 baris atas fail; jangan padam) | 🟠 **DILULUSKAN-PRINSIP** | Ia antara sebab terbesar halusinasi skema. Doc-only, risiko rendah |
| **WO-08** | **Eksport kebenaran produksi** → fail `docs/memory/PRODUCTION_TRUTH_<tarikh>.md` (Owner jalankan SQL read-only §D `EVIDENCE.md`), kemudian CTO rekonsiliasi menjadi `supabase/migrations/0001_baseline.sql` **di branch** | 🔴 **KEUTAMAAN TERTINGGI selepas MASTER CONTEXT digabung** | Sekarang Supabase, bukan GitHub, yang jadi memori. Tiada DDL Fasa-3 di Git. **Sebelum** mana-mana "reka bentuk skema" |
| **WO-09** | Baiki `register_my_player()` (jangan tulis `profiles.identification_number`; ikut R-03) | 🟡 **BLOCKED** | Perlu jawaban CEO: sama ada `verification_cases` dibuka sekarang atau kemudian. Ini **langkah pertama Golden Path rosak** → CEO kena tahu |
| **WO-10** | Selaraskan `auto_suspend_on_red_card()` 1 → **2** perlawanan + ujian (DEC §E) | 🟡 **BLOCKED (fasa PELAKSANAAN)** | Perubahan logik produksi; perlu DDL → terikat turutan 7 langkah Fasa 2C |
| **WO-11** | LEPASKAN `playpro-shell-v1.yml` daripada hak `contents: write` (bot jangan boleh push ke `main`) | 🟠 **DILULUSKAN-PRINSIP** | Bot pernah menyunting `index.html` + push sendiri (`fd0fadf`) |
| **WO-12** | Padam `.github/skills/ui-ux-pro-max/SKILL.md` (dead) + selesaikan drift `src/` ↔ `public/src/` | 🟡 **DITANGGUH** | Kebersihan; jangan buat sambil-sambil fasa lain |
| **WO-13** | Tetapkan redirect auth keluar dari `v0.app` ke domain PlayPro sendiri | 🟡 **BLOCKED — perlu Owner (keputusan perniagaan+DNS)** | Baris 16 `index.html`. Selagi tak selesai, aliran login bergantung alat AI |
| **WO-14** | `sirr` (aplikasi lain Owner) | ⚫ **LUAR SKOP — jangan sentuh, jangan cadang apa-apa** | Keputusan Owner 2026-09-10. Hanya berkongsi kuota Supabase free tier |

---

| **WO-15** | Gabungkan branch memori yang tertinggal ke `main` sebagai PR: `phase-1/system-contract` (1 commit — `docs/PLAYPRO_SYSTEM_CONTRACT.md`) + `phase-2/canonical-model` (10 commit — 9 dokumen Fasa 2/2B/2C/3 + `supabase/migrations/PHASE2_DEV_BASELINE.sql`) | 🟡 **DILULUSKAN-PRINSIP — merge tetap perlu kelulusan Owner** | Disemak: `ahead_by` 1 dan 10, `behind_by` 5, **tiada PR untuk kedua-duanya**. Ini **ubat amnesia paling murah**: kontrak + gerbang 7 langkah + baseline dev sudah ditulis orang, tapi `main` tidak tahu. **Tiada DDL dijalankan** — fail SQL itu teks baseline dev sahaja; merge = dokumen masuk Git |

## Susun atur fasa selepas PR ini digabung

```
1. WO-01 (Owner tampal v1.3)          ── selari dengan
2. WO-08 (eksport kebenaran produksi) + WO-15 (gabungkan branch memori) ── selesai → baru
3. REKA BENTUK SKEMA (teks cadangan sahaja, tiada DDL dijalankan)
4. SEMAKAN SKEMA (audit + P1 list) → 5. PELAN MIGRASI → 6. PELAKSANAAN → 7. UJIAN (MA-01…MA-04)
   (WO-04/05/06/07/11 boleh berjalan pada bila-bila masa — ia hanya infrastruktur GitHub/test/doc)
```

## Soalan yang menunggu jawaban CEO (Gemini) — jangan teka

1. **R-01…R-07** (`DECISIONS.md` §D) — khususnya **R-02** (peta `leagues`/`tournaments` → `Competition.format`) dan **R-05** (formula OVR) kerana kedua-duanya menyekat reka bentuk skema.
2. Adakah **WO-08 diutamakan dahulu** (disyorkan CTO) atau skema direka dari kosong atas andaian?
3. `verification_cases` dibuka dalam fasaIdentity&Trust atau ditangguh (menyelesaikan WO-09)?
4. Setuju CTO mulakan **WO-03 (pecah monolith)** **sebelum** fasa skema? (Keputusan: ya/tidak. Tiada implikasi DB.)
5. Kelulusan kaedah **WO-02b (A atau B)**.
