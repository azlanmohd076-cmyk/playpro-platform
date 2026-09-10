# STATE.md — Keadaan PlayPro (satu-satunya sumber status)

Tarikh: 2026-09-10 (Asia/Kuala_Lumpur) · Disusun: Arena (CTO) · Diperintah oleh: Owner (Azlan)
Cara baca: `DISAHKAN` = saya ukur sendiri dalam repo/GitHub hari ini. `DILAPORKAN` = disebut dalam perbualan/audit, **belum** boleh disahkan dari sandbox. Jangan campur dua-dua.

---

## 0. Enam baris yang AI baru kena faham

1. PlayPro = platform ekosistem bola sepak akar umbi (Owner → Organizer → Competition → Match → Data → Intelligence → Services → Revenue).
2. Struktur maklumat **sudah dibekukan** dalam Blueprint v1.3 (17 keputusan + 3 senario penerimaan). Ia ada di `DECISIONS.md` sebagai ringkasan; **teks penuh §1–64 belum ada dalam Git** → `BACKLOG.md` WO-01.
3. Fasa sekarang = **MASTER CONTEXT** — ditulis sebagai **PR #5**, dan CEO sudah jawab K1–K5 (direkod `DEC-021`…`DEC-026`). **Reka bentuk skema BELUM bermula dan DILARANG bermula** sehingga `WO-08` (eksport kebenaran produksi) selesai.
4. `0 migration tracked` di `main`. Seluruh enjin statistik perlawanan Fasa-3 wujud **di Supabase sahaja**, tidak di Git → Git belum jadi memori projek.
5. `public/index.html` (1.2 MB) **ialah aplikasi produksi sebenar**, bukan placeholder; ia punca halusinasi AI sebab alat pembaca terpotong (lihat `AGENTS.md` §3).
6. Tiada enforcement mekanikal: `rulesets: []`, tiada CI ujian, workflow bot boleh push ke `main`. Semua peraturan "main dilindungi" sekarang **hanya janji dalam dokumen**.

---

## 1. Struktur tadbir urus — keputusan Owner 2026-09-10 (DISAHKAN sebagai arahan)

| Peranan | Siapa | Bidangnya | Had keras |
|---|---|---|---|
| **CEO** | Gemini | meluluskan/menolak dasar, skop, urutan fasa; menjawab soalan semantik | tidak menulis kod, tidak mengubah skema |
| **CTO** | Arena (sesi ini) | menyediakan dokumen, forensik repo, pelaksanaan selepas kelulusan | **tidak meluluskan reka bentuknya sendiri**; tidak menyentuh produksi |
| **Reviewer** | ChatGPT (bila had limit pulih) | semakan bebas ke atas setiap PR, mencari percanggahan dengan `DECISIONS.md` | tidak menggabung PR |
| **Owner** | Azlan | satu-satunya yang boleh ubah keputusan beku, meluluskan merge, meluluskan DDL | — |

Sebab perubahan: had penggunaan (rate limit) ChatGPT mengganggu kesinambungan kerja. **Rantai ini bergantung pada Owner menampal dokumen, bukan pada ingatan sesi.** Setiap AI yang mula bekerja mesti baca `AGENTS.md` → `STATE.md` dahulu.

---

## 2. SETUJU & BEKU (tidak boleh dibahaskan semula)

- 17 keputusan teras + 3 senario penerimaan + 7 item terbuka → `DECISIONS.md`.
- Skop terkunci daripada perbualan CEO/CTO 8–9 Sept:
  - `leagues` **tidak** dibuang/tukar nama dalam migrasi pertama.
  - Tiada jadual dicipta **hanya kerana** kod legacy atau `database/*.sql` menyebutnya.
  - `match_events` = **satu-satunya kebenaran perlawanan** (event-sourced).
  - Model **capability** menggantikan `profiles.role`.
  - UI shell dikunci → `AGENTS.md` §7.
- Data ujian/registry hardcoded (kawan-kawan Owner) = **buang**, **kecuali** rekod **Azlan** yang dikekalkan sebagai **persona rujukan pembangunan** (bukan seed, bukan default, bukan localStorage) → `BOUNDARIES.md` §5 + `DECISIONS.md` DEC-019.

---

## 3. BELUM WUJUD (supaya tiada yang menganggapnya siap)

| Perkara | Status sebenar |
|---|---|
| `supabase/migrations/` di `main` | **Tiada**. Fail `PHASE2_DEV_BASELINE.sql` hanya ada pada branch `phase-2/canonical-model`. |
| DDL Fasa-3 (event + RPC observer) | **Tiada dalam Git langsung.** Wujud di Supabase (DILAPORKAN). |
| Teks penuh Blueprint v1.3 §1–64 | **Tiada dalam Git.** Ada dalam perbualan sahaja. WO-01. |
| CI ujian (`npm test` dalam workflow) | **Tiada.** |
| Branch protection / ruleset `main` | **Tiada** — `gh api repos/…/rulesets` → `0` item. |
| Dokumen status auto-dibaca (`AGENTS.md`) | **Dicipta sekarang** (PR ini). |
| **PR #5 digabung** | ❌ **MASIH TUNGGU.** 6 commit di atas `main` (+1,332 baris, `behind_by=0` → tiada konflik, boleh merge sekarang). Selagi belum masuk `main`, memori projek ini hidup di **branch** — iaitu tepat penyakit yang kita cuba ubati. Saranan CTO: **bekukan penambahan, merge sekarang**, dan buka PR kod berasingan untuk `WO-03a` |
| Halangan semantik fasa A | **Kosong** — CEO jawab G1–G4: OVR = konfigurasi berversi (DEC-027/028), tahap KYC ASAS/LANJUT (DEC-029), urutan A→J disahkan (DEC-030). Yang tinggal menghalang = `WO-08` (eksport) + gerbang DDL, bukan soalan falsafah |
| `register_my_player()` | **Rosak**: masih menulis `profiles.identification_number` sedangkan lajur itu tiada → **langkah pertama Golden Path gagal** (DILAPORKAN, padan DRIFT-005). CEO luluskan pembetulan (K4/DEC-025) tetapi ia **DDL produksi** → tetap terikat gerbang Fasa 2C; **produksi kekal rosak** sehingga baseline siap. Bukti lajur dijana oleh `sql/PRODUCTION_TRUTH_EXPORT.sql` q03b |
| `tests/repository-sync.test.js` | **MERAH 1/5** — lihat §4. |
| Penyahbekuan `playpro` (legacy, RLS mati) | Perlu keputusan Owner; risiko hidup semasa projek AKTIF. |

---

## 4. Gerbang automatik (apa yang merah hari ini) — DISAHKAN

`npm test` (10 Sept, sandbox Arena):

| Suite | Keputusan |
|---|---|
| `tests/auth-session.test.js` | ✅ 52/52 |
| `tests/obcomplete-register.test.js` | ✅ 34/34 |
| `tests/server.test.js` | ✅ 3/3 |
| `tests/repository-sync.test.js` | ❌ **1/5** |

Punca §4 **bukan** bug aplikasi — ia dua sesi Arena pada 27 Ogos yang bertembung (disahkan dengan `node --test tests/repository-sync.test.js`):

```
tests/repository-sync.test.js:27   assert.match(onboarding, /if\(playerResult\.error\) throw playerResult\.error/)
                                    ↑ mahu padanan teks PERSIS, tanpa ruang
public/index.html:5029-5043        var rpcError=playerResult?.error;
                                   if(rpcError||!rpcOk){ errMsg = rpcError?.message || … ; toast(…) }
                                    ↑ ralat RPC SEMEMANGNYA diangkat — cuma dalam bentuk lain
public/index.html:5247             if(playerResult.error) throw playerResult.error;   ← string itu kini hidup di FUNGSI LAIN
```
Kesimpulan: **niat ujian dipenuhi, tekstnya lapuk.** PR #3 menulis guard padanan teks literal; PR #4 menulis semula `obComplete()` untuk guna RPC `register_my_player` → guard itu merah walaupun kelakuan betul. Perbaikan = **betulkan test menjadi ujian kelakuan** (WO-06), **jangan** ubah `obComplete()`. Contoh ini sebabnya `AGENTS.md` §1 melarang guard jenis padanan teks: ia pecah bila kod jadi *lebih baik*.

Repo lain yang disemak: `node --check` lulus untuk semua `.js`/`.mjs` (0 ralat sintaks). `md5sum` mengesahkan `js/repositories.js` ≡ `public/js/repositories.js` dan `js/supabase.js` ≡ `public/js/supabase.js`; **`src/` ≠ `public/src/`** (masih drift).

---

## 5. Risiko aktif yang perlu Owner sedar (bukan untuk dibaiki sekarang)

1. `public/index.html` **awam** (repo public + dihidang Vercel) mengandungi registry hardcoded bernombor-pasport-gaya + DOB untuk 6 orang bernama → data ujian, keputusan: buang (WO-02).
2. Gate privasi biodata ditentukan oleh **padanan string nama** `Azlan`/`L.Rom` di pelayar → sesiapa menamakan profilnya `Azlan` lulus. Frontend bukan sempadan keselamatan.
3. `PLAYPRO_SUPABASE_REDIRECT_URL` → `https://v0.app/...` (baris 16): aliran e-mel/login masih bergantung infrastruktur V0 yang sudah diputuskan untuk diputuskan.
4. Workflow `playpro-shell-v1.yml` menyunting `index.html` + `playpro_public.html` dan **push sendiri ke `main`** (commit `fd0fadf`, `github-actions[bot]`) → fail sumber berubah tanpa kelulusan.
5. `playpro` (legacy) dilaporkan AKTIF dengan **5 jadual RLS DISABLED** → pendedahan langsung selagi hidup; kuota free tier hanya 2 projek aktif, maka restore/pause jadi rebutan.
6. Dokumen lama di `main` **menyesatkan** (README "8 HTML" vs 17 fail HTML; `docs/ARCHITECTURE.md` 85 jadual = rekaan; `docs/DEPLOYMENT.md` nama migrasi 14/15 tidak wujud; `database/*.sql` skema lama yang **langgar nama** dengan jadual Fasa-3 — `database/playpro_phase2_additions.sql:431 CREATE TABLE match_events`). Butiran + bukti arahan: `EVIDENCE.md` §E.

---

## 6. Snapshot GitHub — DISAHKAN 2026-09-10

```
repo            : azlanmohd076-cmyk/playpro-platform  (AWAM, default branch: main)
commit main     : 23569ac  "docs: add PLAYPRO_BUSINESS_MODEL master strategic reference"
                  author: Rom <azlanmohd076@gmail.com>  ·  push terus ke main, TANPA PR/review
jumlah commit   : 235
fail dikesan    : 127
branch          : main · phase-1/system-contract (ahead 1, TIADA PR) · phase-2/canonical-model (ahead 10, TIADA PR)
                  arena/01a040d8-* (#3 MERGED) · arena/01a0424f-* (#4 MERGED) · v0/azlanmohd076-8144-* (#2) · v0/worldohsem-7845-*
PR              : #1 #2 #3 #4 — keempat-empatnya MERGED. Dua branch memori FASA TERTINGGAL tanpa PR.
ruleset         : 0 (kosong)   ·   akses semak secrets/hooks/keys/branch-protection → 403 (token CTO tak cukup skop)
Actions         : "PlayPro Shell v1" lulus 2026-09-09 pada 23569ac (bot auto-commit ke main)
```

**Kesan yang perlu Owner faham:** branch `phase-1` dan `phase-2` (11 commit dokumen + SQL baseline Fasa-2) belum masuk `main`. Ia *wujud di GitHub* tetapi tiada dalam aliran kerja mana-mana sesi baharu. Sebarang AI yang hanya baca `main` akan mengira Fasa-1/2/2B/2C belum dibuat — itulah "amnesia" yang anda rasa.

---

## 7. Log peristiwa — 2026-09-10 (petang)

| Perkara | Hasil |
|---|---|
| CEO (Gemini) jawab K1–K5 melalui Owner | Direkod sebagai `DEC-021`…`DEC-026` (petikan verbatim + nota CTO berlabel). **R-02 selesai**; **R-05 separuh** → `R-05a OPEN` (pemberat belum diberi) |
| Keutamaan kerja berubah | `WO-08` (eksport produksi → `0001_baseline.sql`) = **#1** (DEC-022). Tiada reka bentuk skema sebelum itu |
| Pemetaan `index.html` | Dapatan: **72.5% fail = 4 gambar base64** (513,088 B dalam SATU baris 1602); logo yang sama ditampal **3×** (md5 `da3f7d647592`). JS sebenar 160,556 B · CSS 71,194 B · hanya `index.html` terjejas (17 HTML lain bersih) |
| Dry-run `WO-03a` (di luar repo; `main` tidak disentuh) | `index.html` 1,204,835 → **331,345 B (-72.5%)** · baris tetap 6,128 · `npm test` **identik** sebelum/selepas (5/4/1 — kegagalan sama, pra-wujud). Butiran: `INDEX_HTML_MAP.md` |
| Kit `WO-08` | `docs/memory/sql/PRODUCTION_TRUTH_EXPORT.sql` — 28 blok, **diaudit read-only dengan parser SQL (0 aksi tulis)** |
| Yang **belum** dilakukan | `WO-01` (teks penuh v1.3 — hanya Owner/Gemini) · `WO-04` (ruleset — token CTO dapat 403) · `WO-02b` (A/B belum dijawab) · apa-apa DDL (dilarang) · apa-apa suntingan `public/*` (belum ada laluan PR kod) |
| 2026-09-10 (petang 2) | `DEC-027`…`DEC-030` direkod (G1–G4). Halangan semantik Fasa A **kosong**; `WO-16` (`R-03a`: proses kelulusan/retensi/rayuan) + `WO-17` (simpanan dokumen) dibuka sebagai kerja tertangguh. Default `Q3/Q4/Q5` ditetapkan supaya Owner tidak ditanya lagi |
| 2026-09-10 (malam 2) | CEO jawab J1–J3 → `DEC-034`…`DEC-036`. **Pembetulan konsistensi pertama dilaksanakan:** `BOUNDARIES.md` §1 `EXPIRED` → `INELIGIBLE_EXPIRED` atas kebenaran bertulis J2. `DEC-037` **dikosongkan** untuk kes "langgar gerbang `DEC-022`" supaya nombor tak bercanggah. J3 CEO (retensi) melahirkan `WO-21` + `WO-22`. **`WO-20` (landasan dev) masih terbuka** — ia J3 yang berbeza, label `J3-TIDAK-KENA` |
| 2026-09-10 (malam) | `DEC-031`…`DEC-033` direkod (H1–H3). **R-01/WO-16 ditutup.** Fasa A disahkan (i)–(v). **Dua teguran CTO dibuka:** typo `INELEGIBLE_EXPIRED`, dan percanggahan "segera" (H3) vs gerbang `DEC-022`/Fasa 2C — penyelesaian 3 bahagian (a/b/c) dicatat di `DECISIONS.md` §H. `WO-19` (venue, Fasa C) + `WO-20` (landasan dev; saranan: unpause `playpro1` + pause `playpro` legacy) ditambah |
| 2026-09-10 (malam 3) | Pembetulan diri CTO: STATE menulis "7 commit" sedangkan `compare/main...arena/01a089e0` = **ahead_by 6**. Dibaiki. (Contoh disiplin yang diminta: nombor dikutip dari API, bukan ingatan — termasuk nombor yang saya sendiri tulis 10 minit lepas) |
| 2026-09-10 (malam 4) | `DEC-038` (K1): ASAS = sah selagi akaun hidup; LANJUT = 12 bulan rolling. Tiada beban pembaharuan tahunan akar umbi, tiada penyingkiran pemain amatur tengah musim. Satu syarat penerimaan ditambah: **umur dikira dari `date_of_birth`, bukan dari kesegaran pengesahan**. **Penambahan ke PR #5 DIBEKUKAN** selepas ini — walau apa pun jawapan seterusnya, ia masuk PR #6 selepas PR #5 digabung |
