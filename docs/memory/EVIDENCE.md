# EVIDENCE.md — Nombor Yang Boleh Dihasilkan Semula

Prinsip: **tiada nombor tanpa arahan reproduce.** AI yang menulis statistik tanpa ini dianggap mengarang. Semua diukur pada 2026-09-10 di HEAD `23569ac`.

---

## A. Repo & GitHub (DISAHKAN — jalankan arahan ini untuk sama angka)

| # | Metrik | Nilai | Arahan |
|---|---|---|---|
| 1 | Baita `public/index.html` | **1,204,835** | `wc -c < public/index.html` |
| 2 | Baris `public/index.html` | **6,127** | `wc -l < public/index.html` |
| 3 | Kemunculan `function` | **199** | `grep -o 'function' public/index.html \| wc -l` |
| 4 | Rujukan DOM (`getElementById`+`querySelector`) | **314** | `grep -o 'getElementById\|querySelector' public/index.html \| wc -l` |
| 5 | Baris `localStorage` | **25** | `grep -c localStorage public/index.html` |
| 6 | Panggilan `supabase.` | **5** | `grep -o 'supabase\.' public/index.html \| wc -l` |
| 7 | `.from('table')` unik | **8** | `grep -o "\.from('[a-z_]*')" public/index.html \| sort -u \| wc -l` |
| 8 | Fail `.sql` (semuanya di `database/`) | **29** | `git ls-files '*.sql' \| wc -l` |
| 9 | Fail HTML tracked | **18** (17 di `public/`, 1 bersarang) | `git ls-files '*.html'` |
| 10 | Fail dikesan git | **127** | `git ls-files \| wc -l` |
| 11 | Sebutan `Azlan` dalam `index.html` | **21** | `grep -c Azlan public/index.html` |
| 12 | Commit di `main` | **235** | `gh api "repos/azlanmohd076-cmyk/playpro-platform/commits?per_page=100" --paginate` |
| 13 | Ruleset `main` | **0** | `gh api repos/…/rulesets --jq length` |
| 14 | Jumlah PR (semua status) | **4, keempatnya MERGED**; `phase-1`/`phase-2` **tiada PR** | `gh pr list --state all` |
| 15 | `phase-1/system-contract` | ahead **1**, behind **5** | `gh api repos/…/compare/main...phase-1/system-contract --jq .ahead_by` |
| 16 | `phase-2/canonical-model` | ahead **10**, behind **5** | sama, tukar branch |
| 17 | Fail di `supabase/migrations` | **main: 404 (tiada)** · `phase-2`: **1 fail** | `gh api repos/…/contents/supabase/migrations?ref=<branch>` |
| 18 | Sintaks JS | **0 ralat** semua `.js`/`.mjs` | `for f in $(git ls-files '*.js' '*.mjs'); do node --check "$f" \|\| echo "FAIL $f"; done` |
| 19 | Salinan kembar | `js/repositories.js` ≡ `public/js/repositories.js`; `js/supabase.js` ≡ `public/js/supabase.js`; `src/` ≠ `public/src/` (drift) | `md5sum js/*.js public/js/*.js` |
| 20 | `npm test` | auth 52/52 ✅ · obcomplete 34/34 ✅ · server 3/3 ✅ · **repository-sync 1/5 ❌** | `npm test` |

> Angka 1–11 membatalkan dakwaan "index.html kosong/placeholder". Angka 12–16 & 20 membatalkan dakwaan "sejarah git dah squash jadi 1 commit" (itu artifak **shallow clone** sandbox: `.git/shallow` ada, 1 baris).

---

## B. Empat artefak legacy yang HIDUP di produksi (DISAHKAN — petikan tepat)

```
baris 16    window.PLAYPRO_SUPABASE_REDIRECT_URL='https://v0.app/chat/api/supabase/redirect/sWOYxw7xZPa';
baris 3601  var loggedInUser = "Azlan"; var altUser = "L.Rom";
            → diikuti: isOwnProfileBio = (nama papar == "azlan" || == "l.rom" || …)
            → keputusannya: sorok/tunjuk butang Edit Biodata (kawalan privasi = padanan string di pelayar)
baris 4227  const DATABASE_PEMAIN_PLAYPRO = [ { id:'550e…0001', full_name:"Azlan Mohd", …
              passport_number:"27091976-05-AZLN", date_of_birth:"1976-09-27", kyc_status:"verified", …
baris 4228–4232  Cikyut "15011970-05-CYUT" · Fadzrul Ezzaq/Loko M "15061979-10-FDZL" ·
                 Ebob "20041983-05-EBOB" · Otai "22031981-01-OTAI" · Haji Boss "01051956-02-HJBS"
baris 4302  if (!localStorage.getItem('PLAYPRO_REGISTRY_V3') || !JSON.parse(…PLAYPRO_REGISTRY_V3)["Azlan"]) {
            → auto-seed / "auto-heal" registry palsu ini masih berjalan
```
Sahkan: `sed -n '16p;3601p;4227,4232p;4302p' public/index.html`
Pemilikan nilai: data rakan = ujian → buang; `Azlan` = persona rujukan sahaja → `DEC-019`. Kerja: `BACKLOG.md` WO-02, WO-03.

---

## C. Keadaan produksi Supabase

### ⚠️ DIBETULKAN 2026-09-10 (malam 5) — angka di bawah ini **LAPUK**

Angka lama (14 fungsi / 57 policy / 0 migration) dibawa dari `docs/PLAYPRO_SYSTEM_CONTRACT.md` (audit 27-28 Ogos) dan dibiarkan dalam jadual ini walaupun sudah ditanda `DILAPORKAN`. Semakan **live oleh Reviewer (ChatGPT)** pada 2026-09-10 memberi keadaan sebenar:

```
[DB] playpro2  ACTIVE_HEALTHY  — disahkan live oleh Reviewer (bukan CTO; sandbox tiada TLS)
       jadual 21 · view 5 · fungsi 20 · trigger 16 · policy 61 · migration tracked 4
       20260908175624  phase3_security_boundary_hardening
       20260908182106  phase3_match_stat_reconciliation_contract
       20260908184858  phase3_match_event_engine_foundation
       20260909003126  phase3_match_observer_rpc_engine_v1
[GIT] main     — 0 fail migrasi (404). Berbeza daripada [DB]; dua-dua betul.
```

**Kesimpulan yang wajib dibawa ke fasa skema:** Supabase **mempunyai** sejarah migrasi (4 versi), tetapi **teks SQL-nya tiada di mana-mana dalam Git**. Maka `0001_baseline.sql` mesti dijana daripada **introspeksi** (§D), **lalu** direkonsiliasi dengan 4 versi itu — bukan disalin daripadanya. Ini **mengukuh** `DEC-022`, tidak melemahkannya. Butiran penuh + 6 temuan DRIFT: `PEER_REVIEW_2026-09-10.md`.

**Sumber angka lama (jejak audit sahaja — jangan kutip):**

Sumber: `docs/PLAYPRO_SYSTEM_CONTRACT.md` (branch `phase-1/system-contract`, angka hasil audit 27–28 Ogos) + laporan Fasa 2/2B/2C/3 di branch `phase-2/canonical-model` + perbualan CEO 8–9 Sept.

| Objekt | Angka dilaporkan |
|---|---|
| Jadual | 17 → **~21** (+ `match_events`, `match_participants`, `match_admin_assignments`, `match_playing_time`; + `fixtures.match_state`) |
| Views / Functions / Triggers / Policies | 5 / 14 / 16 / **57** |
| Migration tracked | **0** |
| Row: `profiles` 4 · `players` 3 (Adam, ds, lokmn — kes ujian Owner sendiri) · lain-lain 0 |
| Fasa-3 keselamatan (dilaporkan dilaksanakan) | REVOKE EXECUTE anon pada fungsi trigger (12→0), `search_path` pinned, 5 views `security_invoker=true`, buang hak tulis anon pada jadual, betulkan double-count standings |
| Baki defect (audit CTO) | `referees` RLS-on/0 policy · `player_assessments` `authenticated INSERT WITH CHECK true` · leaked-password protection DISABLED · ~13 `SECURITY DEFINER` boleh dipanggil `authenticated` · 24 FK tanpa index · 35 index tidak digunakan · 16 kumpulan policy permissive berganda · `auto_suspend_on_red_card()` → **1** perlawanan, sepatutnya **2** (DEC §E) |
| DRIFT-005 | `register_my_player()` masih tulis `profiles.identification_number` (lajur tiada) → pendaftaran pemain rosak |

**Status CTO:** semua baris di atas = `TAK SEMAK` dari sandbox. Gerak hanya selepas §D dijalankan.

---

## D. Skrip read-only untuk mengesahkan §C (Owner jalankan di SQL Editor `playpro2`)

Tiada `INSERT/UPDATE/DELETE/DDL`. Outputnya yang akan menjadikan §C `DISAHKAN` dan disimpan sebagai `docs/memory/PRODUCTION_TRUTH_YYYY-MM-DD.md` (WO-08).

```sql
-- 1. objek & kuantiti
select table_schema, table_type, count(*)
from information_schema.tables
where table_schema in ('public','auth') group by 1,2 order by 1,2;

-- 2. senarai jadual public + bilangan row anggaran
select c.relname as table_name, c.reloptions::text, c.relrowsecurity as rls_on,
       c.relforcerowsecurity as rls_forced,
       (select count(*) from pg_stat_user_tables s where s.relname = c.relname) AS approx_stat_rows
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind in ('r','p') order by 1;

-- 3. policy tanpa liputan / pelik
select tablename, policyname, cmd, qual::text, with_check::text
from pg_policies where schemaname='public' order by tablename, policyname;

-- 4. fungsi: siapa boleh panggil, security definer, search_path
select p.proname, pg_get_userbyid(p.proowner) owner, p.prosecdef as security_defer,
       coalesce(array_to_string(p.proconfig,','),'(none)') as search_path_cfg,
       has_function_privilege('anonymous', p.oid, 'execute') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'execute') as auth_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' order by 1;

-- 5. trigger
select tg.tgname, cl.relname, pg_get_triggerdef(tg.oid) from pg_trigger tg
join pg_class cl on cl.oid=tg.tgrelid join pg_namespace n on n.oid=cl.relnamespace
where n.nspname='public' and not tg.tgisinternal order by 2,1;

-- 6. enum & domain (penting: match_state dsb.)
select t.typname, string_agg(e.enumlabel, ' -> ' order by e.enumsortorder) labels
from pg_type t join pg_enum e on e.enumtypid=t.oid group by 1 order by 1;

-- 7. indexes: yang tiada pada FK + yang mungkin tak guna
select relname, indexrelname, idx_scan from pg_stat_user_indexes order by idx_scan nulls last, relname;
```
Untuk Fasa-3 (bukti objek itu benar-benar ada): `select table_name from information_schema.columns where column_name in ('match_state') or table_name in ('match_events','match_participants','match_playing_time','match_admin_assignments') group by 1;`

---

## E. Dokumen di `main` yang MENYESATKAN AI (jangan jadikan rujukan skema)

| Fail | Kenapa salah | Bukti |
|---|---|---|
| `docs/ARCHITECTURE.md` | 85 jadual / 86 fungsi / ~99 trigger — tiada asas | production dilaporkan 21/14/16; repo 0 migrasi |
| `docs/DEPLOYMENT.md` | urutan migrasi menyebut nama `14/15` yang **tidak wujud**; merujuk `src/supabase.js` (bukan laluan hidang) | `git ls-files supabase/migrations` → 404 di main |
| `docs/DATABASE.md`, `docs/TROUBLESHOOTING.md` | sebahagian besar Pra-P0; skema lama | — |
| `README.md` | tarikh 2026-06-09; "8 HTML" | actual: 18 fail `.html` tracked |
| `database/*.sql` (29 fail) | skema legacy **plus** `playpro_phase2_additions.sql:431` mencipta `match_events` → **langgar nama** dengan jadual Fasa-3 di produksi. Jika dipakai → clash/keliru | `grep -n "CREATE TABLE match_events" database/*.sql` |
| `docs/AUDIT_ACCESS_CODE_2026-08-27_BM.md`, `PLAYPRO_P0_DIAGNOSIS_2026-07-26.md`, `PANDUAN_PEMULIHAN_P0_BM.md`, `LANGKAH_RUN_PATCH_SEKARANG_BM.md`, `ARAHAN_GIT_PUSH_BM.md`, `PADAM_AKAUN_UJIAN_BM.md`, `PLAYPRO_BRIEF_UPDATE_CTO_2026-07-26.md`, `PLAYPRO_KAJIAN_TRIGGER_RLS_CACHE_BM.md` | **Bernilai sebagai sejarah** & punca keputusan; tetapi arahan patch/revertnya **sudah lapuk** | hash-nya ada di `main` (235 commit), tapi konteks `index.html` sudah berubah (PR #3/#4, bot shell) |

Tanda `SUPERSEDED` pada fail-fail ini = WO-07 (belum dilakukan; PR ini tidak menyentuh fail sedia ada).
