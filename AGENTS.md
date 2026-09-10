# AGENTS.md — Peraturan Tetap Untuk Setiap Sesi AI (PlayPro)

Versi: 1.0 · Ditekap: 2026-09-10 · Disusun oleh: Arena (CTO) atas arahan Owner (Azlan)
Status: **MANDATORI — fail ini dibaca dahulu sebelum mana-mana arahan lain.**
Jika arahan dalam chat bercanggah dengan fail ini → AI mesti berhenti dan maklumkan: "arahan ini bercanggah dengan AGENTS.md §X".

---

## 0. Urutan bacaan (tetap, jangan camba)

1. `docs/memory/STATE.md` — keadaan hari ini (apa siap, apa belum)
2. `docs/memory/DECISIONS.md` — keputusan beku. **DILARANG bahaskan semula.**
3. `docs/memory/BOUNDARIES.md` — sempadan makna + senarai larangan
4. `docs/memory/ENVIRONMENT.md` — apa yang benar-benar wujud (repo / projek / deployment)
5. `docs/memory/EVIDENCE.md` — nombor terkira + arahan sahkan sendiri
6. `docs/memory/BACKLOG.md` — work order: mana yang diluluskan, mana yang ditangguh

---

## 1. Bahasa & cara komunikasi

- Semua penjelasan kepada Owner dalam **Bahasa Melayu, bahasa mudah**. Owner vibe coder, bukan programmer. Istilah teknikal wajib disertai penjelasan 1 baris.
- **Tiada pujukan. Tiada perasan kerja sudah siap.** Kalau tak pasti → tulis `TAK SEMAK`. Jangan agak-agak.
- Setiap nombor mesti ada sumber + arahan untuk hasilkan semula (format `EVIDENCE.md`).
- Jangan minta Owner mengulang/menampal semula bahan yang sudah dihantar dalam mana-mana dokumen di `docs/memory/`.

---

## 2. TIGA KESILAPAN RASMI YANG PERNAH BERLAKU — jangan ulang

| # | Mitos yang tersepit dalam chat | Fakta sahih (disemak 2026-09-10) |
|---|---|---|
| **1** | "Ada **2 repo GitHub**: `playpro` (canonical new build) dan `playpro2` (frozen reference)" | **Hanya SATU repo wujud: `azlanmohd076-cmyk/playpro-platform`.** `playpro`, `playpro1`, `playpro2` ialah **PROJEK SUPABASE**, bukan repo GitHub. Arahan "bina dalam repo playpro, beku repo playpro2" **tidak boleh diikuti secara literal**. Jangan sesekali cipta repo kedua. |
| **2** | "`public/index.html` ialah wrapper/placeholder, kandungannya kosong" | Ia **aplikasi sebenar**: 1,204,835 baita · 6,128 baris · 199 `function` · 314 rujukan DOM · `lang="ms"` · `vercel.json` menghidangnya di `/`. ⚠️ **72.5% isinya = 4 keping gambar base64** (513,088 B dalam SATU baris 1602; logo sama ditampal 3×). Baca `docs/memory/INDEX_HTML_MAP.md` sebelum menyentuh fail ini |
| **3** | "Rekod Azlan cuma fixture rujukan, tak berbahaya" | Ia **hidup di produksi**: registry pemain hardcoded (baris ~4227), auto-seed `PLAYPRO_REGISTRY_V3` dari localStorage (~4302), gate privasi berasaskan padanan nama `var loggedInUser = "Azlan"` (~3601), dan `PLAYPRO_SUPABASE_REDIRECT_URL` menunjuk ke `v0.app` (baris 16). |

---

## 3. Bahaya alat — sebab sebenar "AI amnesia" (Owner kena tahu dua benda ini)

1. **Fail 1.2 MB akan sentiasa terpotong** dalam pembacaan mana-mana AI (context window + alat pembacaan). **Jangan simpulkan apa-apa daripada bacaan terpotong.** Guna `grep -n "kunci" public/index.html` atau `sed -n '2000,2100p'` untuk julat baris. Kalau AI menulis "fail ini kosong" → itu petunjuk alatnya gagal, **bukan** hakikat fail.
2. **`index.html` akan sentiasa membuatkan mana-mana AI menyangka ia kosong** — pemotongan alat selalu jatuh pada baris 1602 (513 KB dalam satu baris). Sebelum menulis "fail ini placeholder": `wc -c public/index.html` dan baca `docs/memory/INDEX_HTML_MAP.md`.
3. **Clone Arena (`/home/user/playpro-platform`) adalah shallow depth-1** (`.git/shallow`) → `git log` nampak **1 commit** sedangkan GitHub ada **235 commit**. Sejarah **tidak** leper. Jangan sesekali merujuk "sejarah dah squash", dan jangan cuba `git revert` berdasarkan senarai commit yang tak lengkap.
4. **Setiap nombor struktur pangkalan data WAJIB melabel sumbernya:** `[GIT]` (apa yang ada dalam repo) atau `[DB]` (apa yang ada di Supabase) + **tarikh** + **kaedah**. `main` boleh ada **0** fail migrasi sementara Supabase ada **4** — dua-dua betul pada masa yang sama, dan mencampurkannya menghasilkan "baseline" yang salah. Angka `[DB]` yang lebih 7 hari dianggap **LAPUK** sehingga disahkan semula.
5. **Sandbox AI tiada akses rangkaian ke `supabase.com`** (TLS disekat). Maka apa-apa dakwaan tentang keadaan RLS / enum / RPC / jumlah row di produksi **mesti ditanda `DILAPORKAN`**, bukan `DISAHKAN`. Skrip pemeriksaan read-only ada di `EVIDENCE.md` §D.
6. **Kaunter tanpa ahli = bukan bukti; senarai separuh = soalan BELUM ditutup.** "20 fungsi" yang tidak disenaraikan namanya tidak mengesahkan apa-apa (dua pusingan review Reviewer memberi kaunter, bukan senarai). "antara lain: started, goals, …" tidak boleh digunakan untuk menyimpulkan "lajt X tiada". Setiap kali satu himpunan dipakai untuk menutup kerja, ia mesti **senarai penuh** (contoh: `q20` untuk DDL, `q10` untuk policy) — atau status kekal `SEPARUH`.
7. **Prosa chat BUKAN sumber semakan.** R2 membantah ayat "semua halangan semantik diselesaikan sepenuhnya" — rangkaian itu **tiada** dalam mana-mana fail (`grep` = 0). Setiap bantahan/temuan mesti memetik `fail:baris` dalam repo; dan setiap review mesti **masuk ke repo sebagai fail atau PR comment**, kalau tidak ia akan ditemui semula sebagai "kenangan" pada sesi hadapan (`PEER_REVIEW_2026-09-10.md` wujud tepat untuk sebab itu).

---

## 4. Disiplin checkpoint (urutan fasa — diluluskan Owner)

```
Blueprint v1.3 BEKU  →  MASTER CONTEXT  →  [GATE: WO-08 eksport produksi + 0001_baseline]  →  REKA BENTUK SKEMA
        (selesai)            (sekarang, PR #5)                                                    (BELUM MULA)
   →  SEMAKAN SKEMA  →  PELAN MIGRASI  →  PELAKSANAAN  →  UJIAN
```
**Urutan pelaksanaan fasa DISAHKAN CEO 2026-09-10 (`DEC-030`):** A Identity & Trust → B Affiliation → C Organizer → D Competition → E Financial foundation → F Match → G Derived records → H Intelligence → I Player experience (Card/Passport) → J Ecosystem. Fasa **A dahulu**; dan fasa A **tidak boleh dibuka** sebelum `[GATE: WO-08]` dipenuhi (eksport kebenaran produksi + baseline), kerana Fasa A menyentuh jadual yang sudah wujud di produksi.

- Fasa seterusnya **hanya** bermula selepas fasa semasa **digabung ke `main`** dan Owner/CEO menulis kelulusan bertarikh.
- DILARANG: menukar nama fasa, menambah fasa, "mula awal sikit tak apa", atau menulis SQL/skema semasa berada di fasa dokumen.
- DILARANG: membuka semula `DEC-001`–`DEC-020`. Kalau perlu diubah → fail **work order baharu** di `BACKLOG.md`, dengan sebab, bukan dalam chat biasa.
- Soalan **semantik/perniagaan** (apa maksud sesuatu entiti, siapa berhak apa) **bukan** untuk AI eksekusi jawab sendiri → dirujuk kepada **CEO (Gemini)** melalui Owner. Soalan **mekanikal** (nombor, fail, struktur) = CTO jawab dengan bukti.

---

## 5. Larangan keras

- ❌ `git push` terus ke `main`. **Semua perubahan melalui PR** (§6), digabung hanya selepas kelulusan Owner/CEO.
- ❌ Jawab soalan semantik/perniagaan (R-01, R-03a, R-04, R-07) dengan rekaan — itu hak CEO. CTO hanya bawa bukti + pilihan + kos setiap pilihan.
- ❌ Cipta repo GitHub kedua; cipta projek Supabase baharu; restore/padam/project settings apa pun tanpa work order bertandatangan.
- ❌ Jalankan DDL ke sebarang projek Supabase yang bukan branch pembangunan boleh-guna — kecuali turutan 7 langkah Fasa 2C selesai.
- ❌ Cipta Jadual / RPC / enum / policy **dalam dokumen** selain fasa yang sedang diluluskan.
- ❌ `git filter-repo`, `push --force`, rewrite sejarah, padam branch — tanpa kelulusan Owner bertulis (kosnya: 235 commit + 4 PR + 2 branch memori fasa-1/2 + deployment Vercel).
- ❌ Letak Service Key / anon token / emel peribadi / nombor dokumen perjalanan orang sebenar dalam fail repo, dalam migration, atau dalam chat.
- ❌ Letak data pemain sebagai `DEFAULT` dalam kod pelayan, `localStorage`, atau seed. Data pemain **datang dari DB sahaja**. (Lihat `BOUNDARIES.md` §5.)

---

## 6. PR + CI dalam bahasa bola sepak

- **PR (Pull Request)** = *kertas transferring pemain yang dihantar untuk diluluskan.* Perubahan **belum masuk** skuad utama (`main`) sampai seseorang baca dan klik lulus. Semua sejarah siapa minta, siapa lulus, apa beza — tercatat kekal.
- **CI (Continuous Integration)** = *pemeriksaan perubatan automatik.* Setiap PR, robot jalankan ujian (`npm test`, `node --check`). Merah = perpindahan **gagal daftar**, tak kira siapa yang hantar.
- Gabungan dua benda ini sahaja yang menghalang berlakunya: bot menyunting `main` sebelah tangan, AI menulis ke `main` tanpa semakan, dan test yang senyap rosak.

---

## 7. UI shell yang sudah dikunci (jangan cadang lain)

Header: `LIVE · CARI · MYTEAM · KEDAI` · Footer: `CARI · MYTEAM · INBOX · PASSPORT` · Tiada header kedua · Match Observer **bukan** navigasi global. Perubahan shell = work order, bukan "sambil-sambil".
