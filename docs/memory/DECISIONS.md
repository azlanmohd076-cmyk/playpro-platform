# DECISIONS.md — Daftar Keputusan Beku (append-only)

Cara guna: **tiada AI dibenarkan membahaskan semula entri yang statusnya APPROVED/FROZEN.** Kalau sesuatu keputusan nampak salah, tulis cadangan di `BACKLOG.md` sebagai work order + sebab + bukti; Owner/CEO yang putuskan. Entri **tidak pernah dipadam**, hanya digantikan dengan rujukan entri baharu (`SUPERSEDED BY DEC-nnn`).

Provenance: `DEC-001`–`DEC-017` + `MA-01`–`MA-03` + `R-01`–`R-07` adalah **ringkasan faithfully-dipetik** dari **PLAYPRO DOMAIN ARCHITECTURE BLUEPRINT v1.3 — CEO FINAL** (§1–64) seperti yang dihantar Owner dalam perbualan 8–9 Sept 2026. **Teks penuh §1–64 belum tersimpan dalam Git** → WO-01. Jika ringkasan di sini bercanggah dengan teks penuh v1.3 yang anda (Owner/Gemini) ada → **teks penuh menang**, dan fail ini wajib dibetulkan.

---

## A. Status bekuan

| Artifak | Status | Siapa | Tarikh |
|---|---|---|---|
| Blueprint v1.3 (semantik domain) | **FROZEN / APPROVED** | Owner + CEO (ChatGPT pada masa itu) | 2026-09-09 |
| Penerimaan CTO | **ACKNOWLEDGED — "menunggu arahan"** | CTO (Arena) | 2026-09-09 |
| Langkah seterusnya | **MASTER CONTEXT** (bukan reka bentuk skema) — pembetulan akhir oleh CEO | CEO | 2026-09-09 |
| Struktur peranan (Gemini CEO / Arena CTO / ChatGPT reviewer) | **APPROVED** | Owner | 2026-09-10 |

> Catatan integriti: dalam perbualan asal, CEO pernah melompat ke "Schema Design" pada satu mesej, kemudian **membetulkan sendiri** kepada MASTER CONTEXT. Entri di bawah mengikut pembetulan akhir itu. Jangan petik mesej yang ditarik balik sebagai arahan.

---

## B. Keputusan teras (beku)

**DEC-001 — Organizer adalah kelas warganegara pertama.** Organizer = **capability/identity** yang boleh ada pada individu atau entiti. `Organization` ≠ Organizer; kakitangan pertandingan ≠ Organizer. Seorang boleh jadi Organizer bagi satu pertandingan tanpa menjadi Organization.

**DEC-002 — `Competition` adalah payung kanonik.** Liga / kejohanan ialah **format** di bawah `Competition`, bukan entiti bertanding dua arah. Jangan cipta dua pokok entiti berasingan untuk liga dan kejohanan.

**DEC-003 — Rantai penyertaan.** `Competition → Category → Participation → Team → Squad → Player`. `Participation` **bukan** pengganti `Team`; ia hubungan Team↔Competition+Category (dokumen pendaftaran), manakala `Team` ialah entiti kekal.

**DEC-004 — Pengesahan (verification) berasaskan risiko, berperingkat.** `organizer.status = ACTIVE` **tidak sekali-kali** menjadi sempadan keselamatan. Keselamatan = keputusan gabungan (DEC-009).

**DEC-005 — "Dianjurkan" ≠ "Diiktiraf rasmi".** `hosted` dan `officially recognized` ialah dua fakta berasingan; UI, policy, dan laporan mesti membezakannya.

**DEC-006 — Wallet / escrow / custody DITANGGUH.** Reka bentuk mestilah **provider-agnostic**; tiada lajur/enum yang memihak kepada mana-mana penyedia pembayaran. Jangan cipta jadual dompet sekarang.

**DEC-007 — Tiga tingkat autoriti pertikaian.** (i) dalam pertandingan oleh Organizer, (ii) merentas pertandingan oleh badan yang lebih tinggi, (iii) rayuan bebas. Tiada satu pun boleh ditulis sebagai "admin boleh buat apa-apa".

**DEC-008 — Lima kitaran hayat BERASINGAN, tiada yang jadi proksi untuk yang lain.** (lihat `BOUNDARIES.md` §1 untuk keadaan penuh).

**DEC-009 — Rumus autoriti (wajib dipatuhi policy/RLS/RPC).**
```
authorized = identity AND capability AND verification AND organizer_context
             AND competition_context AND resource AND state
```
Semua 7 faktor. Tiada satu boleh dibuang demi kemudahan. Frontend **bukan** faktor.

**DEC-010 — Kitaran hayat pertandingan ⟂ lapisan tadbir urus.** `NORMAL / UNDER_REVIEW / SUSPENDED / CANCELLED` ialah **overlay**; ia **tidak** menggantikan status kitaran hayat pertandingan (contoh: pertandingan boleh `ACTIVE` tetapi `UNDER_REVIEW`).

**DEC-011 — Urutan Fasa A–J = PROPOSED sahaja.** Tiada fasa boleh dilaksanakan sebelum diuruskan sebagai work order yang diluluskan.

**DEC-012 — Aliran organizer kendiri (self-service) adalah wajib.** Jangan reka proses yang bergantung pada "admin masukkan manual" sebagai satu-satunya laluan.

**DEC-013 — Rantai enjin perniagaan.** `Organizer → Competition → Participation → Match → Data → Intelligence → Services → Revenue`. Setiap jadual/RPC mesti boleh dijelaskan dalam rantai ini; kalau tidak → mungkin tidak sepatutnya wujud.

**DEC-014 — Tiada pertindihan makna** antara `Registration`, `Payment`, `Approval`, `Eligibility`, `Participation`, `Membership`. Enam nama ini = enam keadaan berasingan. Satu lajur/tabel **tidak boleh** menjawab dua soalan.

**DEC-015 — Rantai provenance satu arah.** `Event → DisciplinaryRecord → Sanction → Eligibility`. Rekod **tidak boleh** ditulis balik ke `Event`, dan keputusan disiplin mesti boleh dijejak ke event asalnya tanpa ambiguiti.

**DEC-016 — Rantai penilai.** `Coach (certified) → Assessment (append-only, versioned) → Verified Attribute Version → OVR projection → Intelligence`. **Formula OVR masih terbuka (R-05)** — jangan tetapkan formula dalam mana-mana dokumen sekarang.

**DEC-017 — Keadaan membership** = `REQUESTED / INVITED → TRIAL (pilihan) → ACTIVE → SUSPENDED (non-terminal, boleh dipulih) / ENDED`. `SUSPENDED` **bukan** terminal.

**DEC-018 — Struktur tadbir urus projek** (Owner, 2026-09-10): CEO = Gemini · CTO = Arena · Reviewer = ChatGPT · Owner = Azlan (penggantung muktamad). Tiada AI meluluskan kerjanya sendiri.

**DEC-019 — Data rujukan vs data ujian.** Semua rekod pemain dalam `public/index.html` yang berasal daripada kawan Owner = **data ujian → dibuang** dari kod hidup **dan dari salinan awam (CDN)**. **Kecuali** rekod **Azlan** (Owner): dikekalkan sebagai **persona rujukan pembangunan sahaja** — nilai contoh dalam dokumentasi/senario ujian, **bukan** seed, **bukan** `DEFAULT_PLAYER_REGISTRY`, **bukan** localStorage, **bukan** kebenaran. Rujukan nombor baris: `EVIDENCE.md` §B.

**DEC-020 — Aliran kerja GitHub.** Semua perubahan (dokumen mahupun kod) masuk `main` **hanya melalui PR** + CI hijau + kelulusan Owner. Dilarang push terus ke `main`, termasuk oleh bot dan "CEO". Enforcement sebenar masih perlu WO-04/WO-05 (setakat ini `rulesets: 0`).

---

## C. Senario penerimaan wajib (Blueprint v1.3 — tiada fasa dianggap selesai tanpa empat ini lulus)

**MA-01 — Hujung ke hujung organizer kendiri.** Individu mohon jadi Organizer → disahkan pada tahap risiko → mewujudkan `Competition` (format liga) → membuka `Category` → Team menyertai (`Participation`) → daftar skuad → bermain perlawanan → data perlawanan direkod → keputusan & laporan muncul.

**MA-02 — Pengasingan + kelayakan bukan automatik.** Organizer-A **tidak boleh** menulis apa-apa dalam Competition-B (ujian policy/RLS sebenar, bukan andaian). DAN: pemain yang **ACTIVE dalam Participation** **TIDAK** secara automatik **ELIGIBLE** untuk satu perlawanan — kelayakan ialah kitaran hayat berasingan yang mesti dinilai setiap perlawanan.

**MA-03 — Provenance disiplin yang tidak boleh dipadam.** "Player X digantung kerana Event Y dalam Match Z di bawah Rule vN." Override/ampun hanya boleh dilakukan di tempat yang peraturan + polisi + autoriti membenarkan, dan **tidak sekali-kali memadam atau menulis balik** rekod event/sanction asal.

**MA-04 — hosted ≠ recognized.** Satu pertandingan yang dianjurkan tetapi tidak diiktiraf mesti dipaparkan dan dilapor berbeza di semua permukaan (kad, laporan, pengesahan penyertaan).

---

## D. Item terbuka (OPEN — jangan ditutup oleh AI eksekusi; CEO yang jawab)

| ID | Soalan terbuka | Siapa |
|---|---|---|
| R-01 | Bentuk skema untuk organizer **fizikal** (venue/kompleks) — perlu entiti berasingan atau atribut? | CEO |
| R-02 | Penamaan legacy `leagues` / `tournaments` — peta kepada `Competition.format` atau kekal + view? | ✅ **DIJAWAB CEO 2026-09-10 → DEC-023** |
| R-03 | Tahap KYC/verification & bukti yang diterima bagi setiap tahap risiko | CEO + Owner |
| R-04 | Model custody dana (selepas DEC-006 dibuka semula) | CEO |
| R-05 | **Formula OVR** & pemberat attribute (DEC-016) | 🟡 **SEPARUH DIJAWAB → DEC-024. Pemberat (nombor) masih OPEN sebagai R-05a** |
| R-06 | Kebergantungan akhir antara fasa A–J (urutan sebenar pelaksanaan) | CEO + CTO |
| R-07 | Skop `KEDAI`/marketplace pada rilis pertama | Owner + CEO |

---

## E. Skop terkunci tambahan (bukan keputusan domain, tapi arahan kerja)

- UI shell seperti `AGENTS.md` §7 (header `LIVE · CARI · MYTEAM · KEDAI`; footer `CARI · MYTEAM · INBOX · PASSPORT`; tiada header kedua; Match Observer bukan nav global).
- Model perlawanan: `shot` = tepat sasaran + tersasar + penalti; jaringan sendiri dikira sebagai shot penendang (assist kepada penendang); masa tambahan 2×15 minit **dijangka berasingan**; penalti = bilangan **sepakan diambil** sahaja; clean sheet automatik; possession daripada pertukaran jam antara dua team observer; foul/corners/offside/free-kick pada tahap pemain **dan** pasukan (fair-play + KPI jurulatih); kad kuning kedua = merah automatik = penggantungan **2 perlawanan** automatik (fungsi `auto_suspend_on_red_card()` sekarang jatuh ke **1** → percanggahan, WO-08); input observer adalah autoritatif, **tiada suntingan statistik selepas perlawanan**.

---

## F. Keputusan CEO (Gemini) 2026-09-10 — jawapan K1…K5 yang disampaikan Owner

Provenans: jawapan ditulis **VERBATIM** seperti Owner tampal dari chat CEO. Tiada tafsiran CTO dalam petikan; tafsiran hanya dalam nota CTO yang dilabel jelas.

> **K1.** "Tiada percanggahan ketara antara DECISIONS.md dengan Blueprint v1.3; kesemuanya sejajar sebagai penjelas kepada pelaksanaan teknikal."
> **K2.** "YA; setuju WO-08 diutamakan untuk eksport kebenaran produksi ke fail migrasi asas sebelum sebarang reka bentuk skema baharu dimulakan."
> **K3.** "R-02: Legacy leagues/tournaments dipetakan terus ke entiti Competition.format berserta jadual view keserasian; R-05: Formula OVR dikira secara dinamik melalui purata wajaran atribut fizikal dan teknikal yang disahkan oleh jurulatih bertauliah."
> **K4.** "verification_cases dibuka sekarang bagi menyelesaikan segera isu pendaftaran pemain di produksi yang masih rosak di bawah WO-09."
> **K5.** "YA; setuju CTO mula memecahkan fail monolitik index.html (WO-03) sekarang kerana ia tidak membawa sebarang implikasi terus kepada pangkalan data."

**DEC-021 — keselarasan pengesahan (K1).** `DECISIONS.md` diiktiraf CEO sebagai sejajar dengan v1.3 dan berfungsi sebagai *penjelas pelaksanaan teknikal*, bukan penggantinya. Nota CTO: pengesahan ini dibuat **terhadap ringkasan**, kerana teks penuh §1–64 **masih belum dalam Git** → `WO-01` belum selesai dan tetap wajib.

**DEC-022 — turutan kerja (K2).** `WO-08` = keutamaan **#1**. Tiada satu pun reka bentuk jadual/RPC baharu dibenarkan bermula sebelum kebenaran produksi dieksport menjadi `supabase/migrations/0001_baseline.sql`. Ini menutup punca utama Fasa 2C "PASS WITH CHANGES" (reka bentuk atas andaian).

**DEC-023 — R-02 diselesaikan (K3a).** Legacy `leagues` / `tournaments` **dipetakan terus** ke `Competition.format`, disertai **view keserasian**.
*Nota CTO (mekanikal, bukan semantik):* (i) tiada penamaan semula/buang pada migrasi pertama — selari `BOUNDARIES.md` §6(2); (ii) *view keserasian* ialah **objek skema** → hanya dicipta pada fasa REKA BENTUK SKEMA, kini hanya sebagai keperluan bertulis; (iii) view itu mesti **read-only** untuk kod legacy (jangan jadi medium penulisan kedua, kalau tidak kita cipta balik sumber-kebenaran-ganda yang DEC-014/015 larang).

**DEC-024 — R-05 dijawab sebahagian (K3b).** OVR = **purata wajaran** atribut fizikal + teknikal, dan hanya atribut yang **disahkan jurulatih bertauliah** (selari DEC-016: `Verified Attribute Version`, bukan nilai dari pelayar).
⚠️ **R-05a masih OPEN:** nilai pemberat (berat setiap atribut, dan pembahagian fizikal vs teknikal) **belum diberikan**. CTO **menolak** meneka nombor. Ia mesti datang sebagai jawapan CEO/Owner yang direkod sebagai DEC baharu, dan disimpan sebagai **konfigurasi berversi di DB** (bukan hardcoded dalam `index.html`) supaya sejarah unjuran OVR boleh dijejak.

**DEC-025 — `verification_cases` dibuka (K4).** Entiti verification/`verification_cases` dimasukkan ke fasa Identity & Trust, dan isu `register_my_player()` (WO-09, DRIFT-005) dianggap **perlu diselesaikan segera**.
⚠️ **Kos yang CTO wajib catat supaya Owner tak terkejut:** sebarang pembetulan `register_my_player()` = **DDL ke produksi** (sama ada tambah lajur ke `profiles`, atau `CREATE OR REPLACE FUNCTION`). Gerbang Fasa 2C (7 langkah, `BOUNDARIES.md` §7) masih menghalang DDL. Maka, secara jujur: **pendaftaran pemain di production akan TETAP rosak** sehingga `WO-08` → baseline → langkah 1–6 Fasa 2C selesai. Laluan terpantas yang sah = siapkan `WO-08` (hari ini, read-only) + `WO-15`/`WO-05`/`WO-06`, baru DDL. **Tiada jalan pintas yang selamat**, dan CTO tidak akan mencadangkan "edit laju di Dashboard" kerana itulah yang menghasilkan 0 tracked migration yang kita warisi sekarang.

**DEC-026 — monolith `index.html` (K5 + penemuan CTO).** `WO-03` diluluskan. Selepas pemetaan, keputusan teknikal diubah: punca "AI buta" **bukan** jumlah kod — ia **4 keping gambar base64 (873,460 B = 72.5% fail)**, dengan logo yang sama ditampal **3 kali**. `WO-03` dipecah kepada `WO-03a` (luaran aset) → `WO-03b` (modularisasi JS) → `WO-03c` (optimum gambar). Butiran + bukti dry-run: `INDEX_HTML_MAP.md`.

---

## G. Log append-only

| Tarikh | Peristiwa |
|---|---|
| 2026-09-09 | Blueprint v1.3 FROZEN (Owner + CEO); CTO acknowledge |
| 2026-09-10 | Owner tetapkan peranan: Gemini=CEO, Arena=CTO, ChatGPT=reviewer (DEC-018) |
| 2026-09-10 | MASTER CONTEXT ditulis sebagai **PR #5** (7 fail, +671) · `main` tidak disentuh |
| 2026-09-10 | CEO jawab K1–K5 → DEC-021…DEC-026 direkod. R-02 selesai; R-05 separuh (**R-05a OPEN**); `WO-08` jadi keutamaan #1 |
