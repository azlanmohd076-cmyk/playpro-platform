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

---

## 9. Addendum CTO — apa yang `[GIT]` beritahu kami yang semakan live tak nampak

Semakan Reviewer melihat **struktur** DB. Empat temuan di bawah hanya boleh dilihat dari **sisi kod**, dan ketiganya mengubah keutamaan kerja. Semua boleh dihasilkan semula dengan arahan di hujung seksyen ini.

**DRIFT-013 🔴 P0 — `match_observer.html` mungkin tidak menulis apa-apa.**
```
public/match_observer.html:1120  async function finaliseMatch() {          ← butang "💾 Finalise & Update Stats"
public/match_observer.html:1125    if (typeof simulateDBWrite === 'function') {
public/match_observer.html:1126      const result = await simulateDBWrite();
public/match_observer.html:1127      if (result && !result.ok && result.reason !== 'no_fixture') {
public/match_observer.html:1128        toast('⚠️ Save issue — data preserved locally. Retry when online.');
public/match_observer.html:1140  function simulateDBWrite() {
public/match_observer.html:1141    console.log('[Observer] No fixture wired — local session only.');
public/match_observer.html:1142    return Promise.resolve({ ok: false, reason: 'no_fixture' });
public/match_observer.html:1133  toast('✅ Match complete — DNA & Passport updated');   ← diluar cabang ralat
```
Override sebenar (`ObserverDI.finalise` dalam `dashboard_integration.js`) **404 di produksi** — fail itu hanya ada di `js/`, manakala `vercel.json` menghidang `public/` sahaja. Rantainya: penulis tunggal tidak dimuat → fallback mengembalikan `reason:'no_fixture'` → cabang ralat **mengecualikan** sebab itu secara khusus → **tiada amaran**, hanya ✅. `match_observer.html` tidak mengandungi satu pun `.from(`/`.rpc(` penulisan.
Status CTO: **disahkan pada tahap kod**, belum disahkan pada tahap pelayar (saya tidak boleh melayari laman live dari sandbox). Kalau ini betul, **statistik perlawanan padang tidak pernah masuk DB** — itu lebih besar daripada mana-mana isu grant.

**DRIFT-014 🔴 — penulis yang 404 itu menunjuk ke skema yang SUDAH BERBEZA.**
`public/js/repositories.js:1100-1119` (`MatchRepo.saveEvents`) melakukan `SB.from('match_events').insert(rows)` dengan lajur: `fixture_id, event_type, minute, added_time, period, player_id, secondary_player_id, club_id, home_score_at_event, away_score_at_event, is_cancelled`.
Berbanding lajur `match_events` **live** yang Reviewer laporkan (`fixture_id, event_type, team_id, player_id, related_player_id, minute, second, period, sequence, metadata, recorded_by, recorded_at, voided_at, voided_by, void_reason`): **6 lajur dihantar yang tiada di live**, dan **7 lajur wajib/audit ditinggalkan** (tiada `sequence`, `recorded_by`, `voided_*`).
⇒ Bahaya sebenar: kalau sesi seterusnya "membaiki 404" dengan menyalin `js/dashboard_integration.js` ke `public/js/`, dia **mengaktifkan laluan tulis yang pasti ralat lajur**, dan yang lebih buruk — laluan itu **melangkau RPC observer** serta semakan autoriti + agihan `sequence` (Fasa 2C `P1-5`). Jadi `P1-5` bukan sahaja relevan (seperti kata Reviewer), ia **punca reka bentuk dua buah arkitektur yang bersaing** dalam satu projek.

**DRIFT-015 🟠 — DRIFT-009 Reviewer ada laluan penulisan klien, bukan sekadar penyimpanan berganda.**
`repositories.js:1128` (`savePlayerStats`) membuat `from('player_match_stats').upsert(rows, {onConflict:'fixture_id,player_id'})` **sebelum** "mencetus pipeline" — komen pada baris 1164 menyatakan reka bentuknya: `trg_fixture_status_pipeline` pada `fixtures` → `run_post_match_pipeline()`. Jadi reka bentuk **lama** = *klien tulis jadual mentah → trigger derive*, manakala Fasa-3 **live** = *RPC observer ialah satu-satunya penulis event-driven*. Dua model ini tidak boleh hidup serentak; ini keputusan fasa skema (→ `WO-24`), bukan kerja keemasan.

**DRIFT-016 🟠 — 3 skrip yang langsung tidak dimuat di produksi.**
Diukur (bukan diingat): `public/` mengandungi **17 halaman `.html`**; **16 rujukan** `<script src="/js/...">` menghala ke **3 fail yang tidak wujud** di `public/js/` — `vercel.json`: `outputDirectory: "public"`, fail hanya ada di `js/` (akar):
```
/js/dashboard_integration.js        → club_command_center, coach_command_center, match_observer,
                                      parent_command_center, player_command_center, playpro_public
/js/playpro_audit_fixes.js          → 6 halaman di atas
/js/shared_dashboard_components.js  → 4 command center
Jumlah rujukan 404: 6 + 6 + 4 = 16. Semakan lengkap: tiada skrip /js/* LAIN yang 404.
```
Maknanya: **pembaikan audit yang ditulis sebagai `playpro_audit_fixes.js` tidak pernah berjalan di produksi**, walaupun failnya ada dalam repo dan ada dalam sejarah git. Kelas ralat yang sama seperti `is_club_admin`: bukan isu pangkalan data, isu **laluan hidang** — dan sebab itu `docs/DEPLOYMENT.md` (yang menamakan migrasi palsu) bahaya.

Dua berita baik yang keluar dari semakan yang sama: (i) URL Supabase **konsisten** — `muirhenvjruvfxenoaxm.supabase.co` pada 11 fail, tiada split-brain projek; (ii) tiada satu pun halaman yang menulis `match_results` dari klien, jadi `DRIFT-009` kemungkinan besar memang dijaga oleh mekanisme pelayan (itu yang saya minta bukti, bukan andaian).
Awas satu: `connection_test.html:15` dan `p0_auth_doctor.html` dikonfigurasi lalai ke `https://xxxx.supabase.co` → **alat doktor yang sepatutnya menangkap semua ini tidak boleh jalan sebagaimana adanya**.

Arahan sahkan (saya jalankan ini, bukan ingatan):
```bash
sed -n '1120,1143p' public/match_observer.html
sed -n '1100,1132p' public/js/repositories.js
for f in $(grep -rl 'src="/js/' --include=*.html public/); do for p in $(grep -o '/js/[a-z_]*\.js' $f|sort -u); do test -f public$p || echo "404 $f -> $p"; done; done
grep -n "PLAYPRO_SUPABASE_URL=" public/*.html | head
```


### 9.6 Kebolehcapaian — ditulis semula selepas Owner bertanya "mana fail `match_observer.html` ni?"

Diukur 2026-09-10, disahkan melalui GitHub API (bukan ingatan):

1. **Fail itu wujud, dan ada di `main`.** `public/match_observer.html` · **61,219 B** · **1,394 baris** · blob `be7b98c6`
   · md5 `f15a4167b70b9834bc5100722ac4c6cb` · **IDENTIKAL** di `main` dan di branch CTO. Ia di dalam `public/` — bukan
   di `docs/memory/`, bukan di akar repo, jadi cari dalam folder `public` di GitHub UI.
2. **Ia halaman YATIM.** `public/index.html` mengandungi **0** rujukan ke `match_observer` (`grep -c` = 0). Satu-satunya
   jalan masuk: **2 butang dalam `coach_command_center.html`** (L218 "Open Match Observer →" dan L324
   "⚡ Open Match Observer"), kedua-duanya `window.open('match_observer.html','_blank')`. Dalam shell yang
   dikunci (LIVE/CARI/MYTEAM/KEDAI) halaman ini **tidak pernah muncul** — itu sebab yang paling munasabah
   mengapa DRIFT-013 (kiyasan berjaya) kekal tak perasan selama ini. **Bukan sahaja penulisnya 404, mangsanya
   pun sukar ditemui.**
3. **Cara buka untuk `WO-28`:** taip terus `https://playpro-platform.vercel.app/match_observer.html` (domain yang
   disebut dalam `PANDUAN_PEMULIHAN_P0_BM.md:74,161` dan `PLAYPRO_KAJIAN_TRIGGER_RLS_CACHE_BM.md:354`) ATAU buka
   `coach_command_center.html` → klik "Open Match Observer". CTO **tidak dapat mengesahkan** mana-mana satunya
   hidup: egress sandbox ke Vercel disekat (`curl` → `SSL_ERROR_SYSCALL`, HTTP 000) seperti juga ke Supabase, dan
   domain sebenar belum disahkan milik projek ini (`WO-18`).
4. **`WO-30` separuh terjawab dari sisi `[GIT]`:** anon key di `index.html:15` ialah **key sebenar, bukan placeholder**.
   Claims yang dinyahkod: `iss=supabase`, `ref=muirhenvjruvfxenoaxm`, `role=anon`, `iat=2026-04-30` (208 aksara) —
   ref-nya sepadan dengan URL di L14. Jadi apl memang **diterajui** ke projek itu. Yang tinggal: **nama** projek bagi
   ref itu. Cara 10 saat, tanpa SQL: di Supabase dashboard, buka projek dan lihat baris alamat
   `https://supabase.com/dashboard/project/<ref>` — `<ref>` yang bersamaan `muirhenvjruvfxenoaxm` itulah DB yang apl guna.
5. `index.html:16` = `PLAYPRO_SUPABASE_REDIRECT_URL='https://v0.app/chat/api/supabase/redirect/sWOYxw7xZPa'` —
   **baris 16**, tepat; mengesahkan `WO-13` (alur login masih bergantung pada platform binaan v0).

---

## 10. SEMAKAN KEDUA Reviewer (R2, 2026-09-10) + balasan CTO

R2 = semakan silang GitHub + Supabase `playpro2` oleh ChatGPT (Reviewer). Pengakuan dia: tidak ubah apa-apa, tiada SQL write, tiada migration, tiada repo write. Verdict: 🟢 **WORK ACCEPTED AS FORENSIC BASELINE**, 🔴 **NOT ACCEPTED AS PRODUCTION-READY** + 🟡 **"jangan coding dulu"** + **"aku tidak nampak keperluan untuk Arena repair apa-apa daripada dapatan ini sekarang"**. Verdict ini **bukan kelulusan** (reviewer → bukan approver) tetapi **diambil sebagai teguhan**: ia sepadan dengan `DEC-022` (gerbang `WO-08`) dan larangan DDL Fasa 2C yang sedia ada.

### 10.1 Fakta `[DB]` baharu yang CTO terima sebagai keadaan sebenar DB

Label: `DISAHKAN-BY-REVIEWER` (2026-09-10, SQL Editor + Security Advisor pada `playpro2`). **Bukan** `DISAHKAN-BY-CTO` → sandbox CTO masih tiada egress rangkaian (`ENVIRONMENT.md` §5).

| # | Fakta R2 | Kesan ke atas dokumen / kerja kami |
|---|---|---|
| 1 | Ref `muirhenvjruvfxenoaxm` = projek **`playpro2`** (DB yang apl guna) | `WO-30` **tertutup separuh** → forensik kita pada projek yang betul. Disokong `[GIT]`: `index.html:14` **dan** `app.html:12` memakai ref yang sama; anon key L15 dinyahkod `ref=muirhenvjruvfxenoaxm` |
| 2 | `run_post_match_pipeline()` **TIADA** di skema `public` | `DRIFT-015` **NAIK taraf**: bukan dua arkitektur bersaing → yang satu memang tidak wujud |
| 3 | `trg_fixture_status_pipeline` **TIADA**; trigger pada `fixtures` hanya `trg_fixtures_updated_at` → `update_updated_at()` | Komen `repositories.js:1163` menerangkan DB yang **tidak wujud** → `completeFixture()` tidak akan pernah mengira apa-apa |
| 4 | `profiles.identification_number` **TIADA** | **Punca `WO-09` disahkan dari live**, bukan lagi hipotesis `[GIT]` |
| 5 | `verification_cases` **TIADA** | Selari `DEC-025`: ini kerja fasa skema, bukan kecacatan yang perlu "dibaiki" sekarang |
| 6 | `match_events` = 18 lajur + `UNIQUE(fixture_id, sequence)` + index fixture/time/team/player | Mengesahkan lajur yang dilanggar oleh `saveEvents()` (`DRIFT-014`) |
| 7 | Keistimewaan `authenticated` pada `match_events`: `SELECT=true`, `INSERT/UPDATE/DELETE=false` | Menjawab soalan (d) CTO → **tiada INSERT terus** → `DRIFT-014` **diturunkan taraf** (lih. 10.3) |
| 8 | RPC observer `start_match / record_match_event / end_match / finalize_match / void_match_event / match_observer_scope_for` **wujud**; `SECURITY DEFINER`, `search_path=public,pg_temp`, ada semakan skop pemerhati | Migrasi Fasa-3 itu **sah sebagai asas**; masalahnya pada pautan apl (§10.4) |
| 9 | `players.club_id` + FK `players_club_id_fkey → clubs(id) ON DELETE SET NULL` | `DRIFT-007` disahkan; arahan R2 **jangan buang** → tag `LEGACY/TRANSITIONAL` dalam rekonsiliasi |
| 10 | `leagues`, `league_staff`, `league_clubs` + `fixtures.league_id`, `standings.league_id`, `disciplinary_records.league_id`; **tiada `competitions`** | 100% sepadan dengan skop terkunci + `DEC-023` (pandangan serasi, bukan penamaan semula) |
| 11 | Tiada `organizers` / `organizations` / `competition_organizers` | Domain Organizer = fasa skema selepas baseline. Jangan bina secara spontan |
| 12 | `player_assessments` = `player_id, assessor_id, passing, crossing, tackling, …` | Rantai pengesah (verifier) masih tiada → `DEC-016` / `DRIFT-011` kekal terbuka |
| 13 | `record_match_event()` mengira `max(sequence)+1` (juga `start_match`/`end_match`) | **Pengesahan `P1-5` Fasa-2C** → risiko kekonkurenan 🟡 , bukan kecemasan |
| 14 | Advisor: `referees` RLS ON / 0 policy · 13 fungsi `SECURITY DEFINER` · perlindungan kata laluan bocor **dimatikan** · **24 FK tanpa index · 35 index tidak digunakan · 18 penemuan auth-RLS initplan · 16 penemuan policy permissive berganda** | Angka 18 dan 16 **baharu** bagi kami; direkod di `EVIDENCE.md` §C berlabel `[DB]` |
| 15 | Teks migrasi **disimpan** oleh Supabase dalam `supabase_migrations.schema_migrations.statements` | Mengubah kaedah `WO-23`: teks 4 migration boleh diperoleh dengan **satu SELECT read-only** → `DEC-040 (PROPOSED)` |

### 10.2 Yang R2 sahkan betul (tiada apa-apa untuk diperdebatkan lagi)

Satu repo kanonik → `playpro2` = projek apl → angka hidup 21/5/20/16/61 → 4 versi migrasi di `[DB]` dan 0 fail di `[GIT]` (dua-dua betul serentak) → PR #5 dokumentasi sahaja, belum digabung → Azlan sebagai persona rujukan → sempadan RPC `match_events` wujud → INSERT terus oleh `authenticated` disekat → arah siasatan drift apl↔DB betul → 404 `dashboard_integration.js` sah dari struktur repo → `players.club_id` masih bercanggah dengan model keahlian. Dan dia menolak dengan betul idea **menambah lajur semata-mata** untuk "menyelesaikan" drift.

### 10.3 Pembetulan ke atas diri CTO (2) → R2 mengubah dua kesimpulan aku

1. **`DRIFT-014` DITURUNKAN taraf.** Aku tulis: kalau orang "baiki 404" dengan menyalin `js/dashboard_integration.js` → `public/js/`, ia akan "mengaktifkan laluan tulis yang pasti ralat lajur". Selepas R2: `authenticated` **tiada INSERT** pada `match_events` → sisipan itu **DITOLAK (42501)**, bukan menulis data rosak. Bahaya sebenar bertukar: bukan kerosakan data, tetapi **ilusi "sudah disambungkan"** (ralat RLS yang orang biasa tidak baca). `WO-29` (larangan menyalin) **kekal**, dengan sebab yang betul.
2. **Angka "13 RPC yang klien jangkakan" perlu dirinci, bukan dibuang.** Diukur semula dengan kaedah tepat (kira `.rpc('nama')` dalam skrip klasik) → **7 nama sahaja**: `ensure_profile_after_signup`(4) · `search_players`(3) · `run_post_match_pipeline`(2) · `register_my_player`(2) · `get_my_player_id`(2) · `refresh_all_public_views`(1) · `compute_weekly_training_score`(1). Enam nama lagi (`get_my_profile`, `get_public_coach_profile`, `process_assessment_payment`, `process_coach_mock_exam_result`, `save_club_manager_onboarding_profile`, `save_coach_onboarding_profile`) **tiada dalam skrip yang dimuat halaman** → ia hidup dalam `public/src/modules/**` yang **tidak dimuat mana-mana pelayar** (§10.4 `DRIFT-017`). Satu padanan `function_name` ialah pemboleh ubah dinamik, bukan nama RPC → dibuang.

### 10.4 Temuan CTO yang R2 belum nampak (hanya boleh dilihat dari sisi `[GIT]`)

🔴 **`DRIFT-017` → "otak" produk tidak dimuat langsung ke pelayar.**
`public/src/` mengandungi **15 fail `.js`**, termasuk `modules/league-os/matchday-engine.js`, `modules/league-os/eligibility-engine.js`, `modules/verification/verification.service.js`, `modules/wallet/wallet.service.js`, `modules/passport/passport-status.js`, `modules/scout-marketplace/scout.service.js`, `modules/auth/auth-session.service.js`. Diukur dengan **empat** pemeriksaan bebas ke atas `public/*.html` + `public/js/*.js`: rujukan `modules/` = **0** · `<script type="module">` = **0** · `import(` = **0** · `src="…/src/…"` = **0**. → Enjin kelayakan, pasport, pengesahan organisasi, dompet dan modul jurulatih **tidak pernah berjalan di pelayar**. Calon penjelasan terbaik bagi rasa "PlayPro kosong walaupun DB ada": logik produk itu wujud sebagai **fail**, bukan sebagai **aplikasi**.

🔴 **`DRIFT-018` → enjin RPC Fasa-3 (dimigrasi 2026-09-09) tidak mempunyai SATU pun pemanggil dalam apl.**
`start_match`, `record_match_event`, `end_match`, `finalize_match`, `void_match_event`, `match_observer_scope_for`: **0 kemunculan di seluruh `public/`** (hanya muncul dalam `database/*.sql` legacy). → Isu Match Observer **bukan sekadar** skrip 404: walaupun 404 itu dibaiki, **tiada baris kod apl yang mengarah ke RPC yang baharu dibina**. R2 betul bahawa RPC itu baik "sebagai asas" → dan itulah sebabnya `finalize_match()` **tidak akan** menyelamatkan halaman observer. Yang tiada ialah **lapisan penyambung (wiring)**. Itu kerja reka bentuk fasa skema, bukan tampalan.

🟠 **`DRIFT-019` → penulis perlawanan dalam `MatchRepo` ialah kod mati.**
`saveEvents()`, `savePlayerStats()`, `completeFixture()` mempunyai **0 pemanggil** di luar `public/js/repositories.js`; satu-satunya "rujukan" kepada `runPipeline()` ialah **teks label** di `public/db_readiness_report.html:344` (`<td>MatchRepo.runPipeline()</td>`), bukan panggilan. Rantai penuh yang diukur: `savePlayerStats()` (L1128-1158) mengupsert 7 lajur yang R2 laporkan **tiada di live** (`passes_completed, passes_attempted, tackles_won, tackles_attempted, interceptions, match_rating, is_motm`) + `club_id`; `completeFixture()` (L1166-1172) hanya `update fixtures.status='completed'` dengan harapan trigger yang R2 sahkan **tiada**; `runPipeline()` (L1180-1186) memanggil RPC yang juga **tiada**; dan setiap ralat hanya `console.error` → tiada toast, tiada sekatan. → **Tiada satu pun laluan tulis statistik yang berfungsi hari ini.**

🟠 **`DRIFT-020` → teks SQL yang "hilang" itu sebenarnya ADA di `[GIT]`, dalam lapisan LEGACY.**
`database/playpro_phase6_7_pipeline.sql` (**1,355 baris / 56,574 B**) mendefinisikan `run_post_match_pipeline()` (L896), `PERFORM run_post_match_pipeline(NEW.id, NULL)` (L1133), `DROP/CREATE TRIGGER trg_fixture_status_pipeline ON fixtures` (L1140-1141), `GRANT EXECUTE … TO authenticated` (L1100) dan `RAISE WARNING … SQLERRM` (L1090) yang **menelan ralat**. Setiap satu daripada 7 RPC klien ada definisinya di dalam `database/*.sql`. `connection_test.html:813` malah menulis `"… not found → run phase6_7"`. → **Pipeline tidak hilang; ia tertulis dan TIDAK PERNAH DITERAPKAN ke `playpro2`.** Ini tepat guna kaedah `DEC-039`: lapisan LEGACY menyediakan teks untuk rekonsiliasi. Dan ia melahirkan **pertembungan reka bentuk yang CEO mesti putuskan** (`DECISIONS.md` §J): *arkitektur Fasa-3 (RPC observer ialah penulis tunggal)* lwn *arkitektur Fasa-6/7 (klien tulis jadual → trigger derive)*. Dua-dua ada dalam repo; satu ada di DB; **tiada satu pun bersambung ke UI**.

### 10.5 Bantahan CTO kepada R2 (4) → sopan, tetapi atas rekod

1. **§17 R2 mengkritik ayat yang tidak wujud dalam mana-mana fail repo.** Petikannya: "Semua halangan semantik dan falsafah produk telah diselesaikan sepenuhnya". `grep` ke atas `docs/memory/*.md` + `AGENTS.md` + `README.md` + `docs/*.md` = **0 padanan**. Ayat sebenar: `STATE.md` §1 baris "Halangan semantik fasa A | **Kosong**" → maksudnya tiada halangan *semantik* untuk membuka Fasa A, dan baris yang sama terus menyebut urutan `DEC-030`. Substansi R2 ( *arkitektur semantik diluluskan ≠ sistem semasa dilaksanakan* ) **kami terima dan memang itu yang dokumen kami tulis**; yang silap ialah metodologinya: dia menyemak **prosa chat**, bukan fail → penyakit yang dia sendiri tandai pada pusingan 1. (Dijadikan peraturan: `AGENTS.md` §3(6).)
2. **"LIVE DB FORENSICS 🟢 BASELINE VERIFIED" adalah pramatang** ikut takrif gerbang `DEC-022`. `WO-08` bukan "Reviewer menjawab soalan"; ia **fail output yang disimpan ke repo** (`docs/memory/PRODUCTION_TRUTH_<tarikh>/`) bagi **28 blok** `PRODUCTION_TRUTH_EXPORT.sql`, dijalankan di **dua projek** (`playpro2` **dan** `playpro` legacy). Yang ada selepas R2: jawapan separuh. **Tiada** senarai nama 20 fungsi (dua pusingan, hanya kaunter); **tiada** `q10` (senarai 61 policy); **tiada** `q14` (kiraan row); **tiada** `q20` (DDL penuh setiap jadual); projek legacy `playpro` **belum disentuh** (`WO-25` kekal). **Disahkan ≠ dieksport.** `DEC-022` hanya boleh digerakkan Owner/CEO → dan **R2 sendiri ada akses untuk melaksanakannya malam ini.**
3. **Senarai separuh tidak boleh menutup soalan.** §9 R2 menulis lajur `player_match_stats` "antara lain: `started, minutes_played, goals, assists, shots, shots_on_target, yellow_cards, red_cards, saves, clean_sheet`" → `antara lain` = bukan senarai penutup. Akibatnya: (a) saya **tidak boleh** menyimpulkan 7 lajur klien itu pasti tiada; (b) status `club_id` pada jadual itu belum diketahui; (c) `clean_sheet` pula **tidak ditulis** klien langsung. Mengikut `AGENTS.md` §3(4) yang R2 sendiri cadangkan: **nombor/himpunan tanpa ahli = belum disahkan**. Yang diperlukan = output `q20` penuh.
4. **§8 (perlumbaan `sequence`)** → sependapat itu risiko kekonkurenan, dan terima bahawa dia **tidak** minta pembetulan sekarang. Satu fakta tambahan dari `[GIT]`: kerana RPC itu sendiri **tiada pemanggil** (`DRIFT-018`), laluan perlumbaan belum boleh dicapai dari UI → justeru `FOR UPDATE` / `nextval` ialah **keputusan reka bentuk fasa skema**, bukan kerja keemasan. "Membetulkan sequence" sekarang bermakna **mengunci arkitektur Fasa-3 sebelum CEO memilih**.

### 10.6 Baki permintaan kepada R2 (5 — lebih kecil daripada pusingan 1)

1. **Senaraikan 20 fungsi itu** (`proname` + `prosecdef` + siapa boleh EXECUTE). Kami ada **kaunter** 20 sejak R1 dan **tiada nama** selepas dua pusingan. Tanpa nama, `WO-08` tak boleh ditutup dan senarai klien (7 nama) tak boleh ditanda padan/tidak.
2. **Matriks keistimewaan `q07` untuk jadual yang klien cuba tulis:** `player_match_stats`, `match_results`, `standings`, `disciplinary_records`, `suspensions`, `fixtures`, `match_participants`, `match_playing_time`, `players`, `profiles`, `clubs`, `leagues`, `coaches`, `referees` (SELECT/INSERT/UPDATE/DELETE × `anon`/`authenticated`). Sebab `match_events` selamat **tidak** bermakna `player_match_stats` selamat → kalau yang ini boleh di-INSERT terus, **itulah pintu sebenar**, dan `WO-24` berubah keutamaan.
3. **Badan 3 fungsi** (`q21`): `register_my_player`, `record_match_event`, `finalize_match`. Untuk `register_my_player` soalan penentunya: adakah `profiles.identification_number` dirujuk **secara keras** (maka pendaftaran pemain **selalu gagal** → P0 pengguna) atau melalui SQL dinamik (maka ia gagal tertakluk cabang).
4. **Kiraan row penentu:** `select count(*)` + `max(recorded_at)`/`max(created_at)` bagi `match_events`, `player_match_stats`, `match_results`, `standings`. **Ini mengesahkan atau membunuh `DRIFT-013` TANPA pelayar**: jika `match_events` = 0 baris, tiada seorang pun pernah menyimpan perlawanan melalui laluan mana sekali pun, dan `WO-28` turun taraf daripada "penentuan" kepada "pengesahan".
5. **Salin teks 4 migration** dari `supabase_migrations.schema_migrations` (R2 jumpa ia disimpan di `statements`) → satu SELECT read-only → saya commit ke `supabase/migrations/` sebagai **rekod** (BUKAN untuk dijalankan) → `WO-23` tertutup dan `DEC-040` boleh diluluskan CEO.

### 10.7 Papan status R2 yang saya terima (dengan SATU perubahan)

```
SEMANTIC ARCHITECTURE   🟢 APPROVED (v1.3 §1-64, Owner) - TAPI teksnya masih tiada di Git (WO-01)
MASTER CONTEXT           🟢 READY (PR #5, belum digabung)
LIVE DB FORENSICS        🟡 SEPARUH  <- perubahan saya: review = ya; EKSPORT ke repo = belum (DEC-022)
SCHEMA DESIGN            🔴 NOT STARTED (dilarang sehingga WO-01 + WO-08)
IMPLEMENTATION           🔴 LOCKED
PRODUCTION CHANGE        🔴 LOCKED (7 langkah Fasa 2C)
ARCHITECTURE FREEZE      🔴 BELUM  <- R2 betul, dan sebabnya ialah WO-01: tidak boleh membekukan apa yang tiada dalam git
```

Satu baris daripada R2 yang saya jadikan panduan sepanjang fasa: **"jumpa drift → terus tambah column/table/function" ialah kesilapan lama yang tidak akan kita ulang.**
