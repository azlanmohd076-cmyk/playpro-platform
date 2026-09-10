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
| R-01 | Bentuk skema untuk organizer **fizikal** (venue/kompleks) — perlu entiti berasingan atau atribut? | ✅ **DIJAWAB CEO 2026-09-10 → DEC-032** (entiti berasingan; skop direkod sebagai `WO-19`, Fasa C) |
| R-02 | Penamaan legacy `leagues` / `tournaments` — peta kepada `Competition.format` atau kekal + view? | ✅ **DIJAWAB CEO 2026-09-10 → DEC-023** |
| R-03 | Tahap KYC/verification & bukti yang diterima bagi setiap tahap risiko | ✅ **DIJAWAB CEO 2026-09-10 → DEC-029** (butiran dasar tertunggak: `R-03a`) |
| R-04 | Model custody dana (selepas DEC-006 dibuka semula) | CEO |
| R-05 | **Formula OVR** & pemberat attribute (DEC-016) | ✅ **DISELESAIKAN SEBAGAI ALIH TANGGUH BERTAMAT → DEC-027/DEC-028** (konfigurasi berversi; nilai ditentukan dalam fasa SKEMA) |
| R-06 | Kebergantungan akhir antara fasa A–J (urutan sebenar pelaksanaan) | ✅ **DIJAWAB CEO 2026-09-10 → DEC-030** (A→J disahkan) |
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

---

## G. Keputusan CEO pusingan 2 (Gemini) 2026-09-10, petang — jawapan G1…G4

Petikan **VERBATIM** seperti Owner tampal dari chat CEO; tafsiran CTO sentiasa dilabel.

> **G1.** "Serahkan ke fasa skema sebagai fail konfigurasi berversi; nilai akan ditentukan kemudian."
> **G2.** "Berversi."
> **G3.** "Tahap KYC merangkumi pengesahan asas MyKad dan nombor telefon untuk pemain amatur, serta dokumen pengesahan tambahan bagi kategori pertandingan kompetitif."
> **G4.** "Sahkan; urutan pelaksanaan A->J kekal seperti dicadangkan bermula dengan Identity & Trust."

**DEC-027 — R-05a dialih-tangguh secara bertamad (G1).** Pemberat OVR **tidak** ditetapkan sekarang, dan **tidak** ditempel tetap (hardcode) dalam kod pelayar mahupun dalam dokumen. Ia menjadi **konfigurasi berversi dalam pangkalan data** yang nilainya diisi pada fasa REKA BENTUK SKEMA.
*Nota CTO:* keputusan ini **membuka** fasa skema (tiada lagi halangan semantik pada OVR) tetapi **tidak** membuka pintu SQL — `DEC-022` (eksport produksi dahulu) masih mengikat. Bentuk yang diperlukan: satu rekod pemberat **per versi**, dengan `effective_from`/status, supaya unjuran OVR yang pernah dipaparkan boleh dijejak semula (selari `DEC-016` dan `DEC-015`: unjuran tidak boleh ditulis-balik).

**DEC-028 — pemberat OVR adalah BERVERSI (G2).** Nilai boleh berubah ikut musim/peraturan/kompetisi. Implikasi yang wajib ada dalam fasa skema (keperluan, bukan reka bentuk): setiap penilaian/unjuran OVR mesti menyimpan **rujukan versi pemberat** yang digunakannya, supaya laporan lama tidak berubah maksud apabila pemberat baharu diguna. Nota CTO: **jangan** buat satu lajur `weight` pada jadual atribut — itu akan memusnahkan ciri berversi ini.

**DEC-029 — tahap pengesahan pemain (G3, menjawab R-03).** Sekurang-kurangnya **dua tahap**:
- **ASAS** — untuk pemain amatur: pengesahan **MyKad** + **nombor telefon** (verifikasi saluran, bukan sekadar simpan nombor).
- **LANJUT** — untuk kategori pertandingan **kompetitif**: dokumen pengesahan **tambahan**.
*Nota CTO (mekanikal):* (i) nama enum/lajur belum dipilih — itu tugas fasa SKEMA; (ii) "dokumen tambahan" memaksa **simpanan fail** → bucket + polisi akses + tempoh simpan; **imej dokumen tidak boleh** muncul dalam mana-mana public view (`PHASE2C P1-9` sudah melarang `verification_cases` terdedah, dan `DEC-019` melarang nilai seperti ini tinggal dalam fail awam); (iii) tahap ASAS/LANJUT ialah **syarat kelayakan per kategori**, jadi ia masuk faktor `verification` dalam rumus autoriti `DEC-009` — bukan faktor `state`.
⚠️ **`R-03a` OPEN (butiran dasar, bukan teknikal):** siapa yang **melulus/menolak** dokumen LANJUT (Organizer sesuatu pertandingan, atau platform?), apa **tempoh sah laku** pengesahan, dan apa yang berlaku apabila **tamat** (perlu `Eligibility` menjadi `INELIGIBLE_EXPIRED`, atau peringatan sahaja?) serta hak **rayuan**. Empat ini ialah keputusan perniagaan → CEO. CTO **tidak** akan menetapkan lalai diam-diam, kecuali untuk satu perkara keselamatan sahaja: **`organizer.status` dan kelulusan dokumen TIDAK BOLEH menjadi sempadan keselamatan** (`DEC-004` kekal).

**DEC-030 — urutan pelaksanaan A→J disahkan (G4).** Fasa **A = Identity & Trust** ialah fasa pelaksanaan pertama; `DEC-011` (dulu "PROPOSED sahaja") kini **DISAHKAN**. Urutan: A Identity & Trust → B Affiliation → C Organizer → D Competition → E Financial foundation → F Match → G Derived records → H Intelligence → I Player experience (Card/Passport) → J Ecosystem.
*Nota CTO:* pengesahan ini **tidak** membatalkan `DEC-022`. Sebelum skema Fasa A ditulis, `WO-08` (eksport kebenaran produksi → baseline) mesti siap, kerana Fasa A menyentuh jadual yang **sudah wujud** di produksi (`profiles`, `capabilities`?, `player_assessments`, `verification_cases` belum wujud) — dan kita sudah lihat apa yang berlaku bila fasa ke-3 dibina atas andaian (`EVIDENCE.md` §E).
Skop Fasa A kini tetap (berdasarkan keputusan yang sudah ada, bukan rekaan CTO): model **capability** menggantikan `profiles.role` (`DECISIONS.md` §B) · **tahap pengesahan** ASAS/LANJUT (DEC-029) · laluan autoriti backend untuk pendaftaran (Fasa 2C `P1-8`) · pembetulan `register_my_player()` (WO-09) · dan `auto_suspend_on_red_card()` 2 perlawanan (WO-10) masuk **Fasa F**, bukan A.

**Default CTO untuk soalan Owner yang belum dijawab (Q3/Q4/Q5) — berkuat kuasa melainkan Owner veto.** Owner diminta 3 kali; saya tidak akan tanya lagi, dan saya pilih default **yang tidak memusnahkan apa-apa**:
1. `WO-02b` = **(A) forward-only** (buang dari `index.html` + notis; **tiada** rewrite sejarah git). Boleh ditukar ke (B) pada bila-bila masa dengan arahan bertulis.
2. Nilai `passport_number` bagi persona Azlan dalam dokumen rujukan dianggap **penjana format `DDMMYYYY-XX-INISIAL`**, bukan dokumen sebenar — jangan dipakai sebagai contoh format nombor rasmi.
3. `WO-03a` dibuka sebagai **PR kod berasingan selepas PR #5 digabung** (saya tidak akan campur suntingan kod ke dalam PR dokumen).

---

---

## H. Keputusan CEO pusingan 3 (Gemini) 2026-09-10 — jawapan H1…H3

Petikan **VERBATIM** seperti Owner tampal dari chat CEO. Nota CTO sentiasa dilabel; **tiada satu pun nota CTO yang mengubah maksud keputusan** — nota hanya menegur percanggahan dengan keputusan yang sudah dibekukan lebih awal.

> **H1.** "(a) Kelulusan atau penolakan dokumen dikendalikan oleh Penganjur Pertandingan yang sah; (b) Tempoh sah laku pengesahan ditetapkan selama satu tahun kalendar; (c) Status automatik menjadi `INELEGIBLE_EXPIRED` apabila tamat tempoh dengan notifikasi sistem; (d) Hak rayuan dikendalikan melalui jawatankuasa rayuan penganjur, selaras dengan DEC-004 bahawa kelulusan dokumen bukan satu-satunya sempadan keselamatan."
> **H2.** "Entiti berasingan diperlukan untuk venue/kompleks fizikal kerana ia melibatkan pengurusan aset, jadual fasiliti, dan logistik pelbagai perlawanan yang melangkaui sekadar atribut metadata."
> **H3.** "Skop Fasa A disahkan merangkumi item (i) hingga (v) seperti yang disenaraikan, dengan ketetapan bahawa pembaikan WO-09 dan audit keselamatan RLS dilaksanakan segera manakala logik `auto_suspend` kekal dikhususkan untuk Fasa F."

**DEC-031 — proses pengesahan LANJUT (menutup `WO-16` / `R-03a`).**
(a) **Penganjur Pertandingan yang sah** adalah pelulus/penolak dokumen — konsisten dengan `DEC-012` (kendiri), `DEC-009` (`organizer_context` + `competition_context` + `resource` wajib ada dalam setiap laluan kelulusan), dan `DEC-004`.
(b) **Tempoh sah laku = satu tahun kalendar.**
(c) Status menjadi **`INELIGIBLE_EXPIRED` secara automatik** apabila tamat tempoh, **disertai notifikasi sistem**.
(d) Rayuan melalui **jawatankuasa rayuan penganjur** = tingkat (i) dalam `DEC-007` (dalam pertandingan, oleh Organizer) → **konsisten**, tiada pertindihan dengan tingkat (ii)/(iii).
**Nota CTO — tiga perkara yang mesti diselesaikan sebelum fasa skema, bukan selepas** *(ketiga-tiganya kini selesai: lihat `DEC-034`…`DEC-036`)*:
1. ~~**Ejaan.**~~ → **SELESAI oleh `DEC-035`.** CEO menulis `INELEGIBLE_EXPIRED`. Nilai kanonik yang betul ialah **`INELIGIBLE_EXPIRED`** (satu `E` selepas `IN`). `DECISIONS.md`/`BOUNDARIES.md` sedia ada memakai `INELIGIBLE_PENDING`/`INELIGIBLE_BLOCKED`. CTO **menolak** menanam typo dalam enum produksi — nilai enum yang salah eja tinggal selama-lamanya kerana setiap migrasi selepas itu perlu pertukaran data.
2. ~~**`DEC-031(b)` TAK TAMAT maknanya**~~ → **SELESAI oleh `DEC-034`.** "satu tahun kalendar" ada dua tafsir. (i) **12 bulan dari tarikh kelulusan** (rolling), atau (ii) **tamat pada 31 Disember tahun kelulusan** (tahun kalendar sebenar, pola pentadbiran MY). Bezasnya material: tafsir (ii) membuatkan pengesahan pemain yang dilulus pada November hanya sah ~2 bulan, dan boleh menyingkirkan pemain di tengah musim. CTO **tidak** akan pilih salah satu. Perlu CEO tetapkan (soalan `J1` di `BACKLOG.md`) sebelum fasa skema mengira tarikh luput.
3. ~~**Nama vs senarai sedia ada.**~~ → **SELESAI oleh `DEC-035`.** `BOUNDARIES.md` §1 sudah menyenaraikan keadaan kelayakan sebagai `… / EXPIRED / SUSPENDED_BY_SANCTION`. Arahan CEO melahirkan nama **baharu** (`INELIGIBLE_EXPIRED`) untuk keadaan yang sudah ada nama (`EXPIRED`). Perlu **satu** nama sahaja → pilih `EXPIRED` **atau** `INELIGIBLE_EXPIRED` (keutamaan CTO: `INELIGIBLE_EXPIRED`, kerana ia jelas dalam senarai `ELIGIBILITY` dan selari pola `INELIGIBLE_*` yang sedia ada), kemudian `BOUNDARIES.md` §1 dibetulkan **sebagai pembetulan konsistensi**, bukan keputusan baharu.

**DEC-032 — R-01 ditutup: venue/fasiliti ialah entiti BERASINGAN.** Venue/kompleks fizikal **tidak** boleh menjadi atribut metadata sahaja, kerana ia membawa pengurusan aset, jadual fasiliti, dan logistik pelbagai perlawanan.
*Nota CTO:* (i) keputusan ini **menambah skop Fasa C** (Organizer) — direkod sebagai `WO-19` supaya tidak hilang; (ii) "jadual fasiliti" akan bersentuhan dengan penjadualan perlawanan (Fasa F) dan dengan rumus autoriti `DEC-009` — `resource` nanti termasuk venue, jadi polisinya perlu dirancang awal; (iii) **tiada** jadual venue dicipta sekarang (fasa skema belum dibuka); (iv) legacy `database/` mungkin sudah ada `matches.venue`/sebagainya — itu akan terbukti daripada `WO-08`, bukan daripada ingatan.

**DEC-033 — Skop Fasa A disahkan (i)–(v), dengan dua ketetapan yang perlu dibaca bersama gerbang.**
Setuju: (i) model capability menggantikan `profiles.role` · (ii) tahap pengesahan ASAS/LANJUT (`DEC-029` + `DEC-031`) · (iii) laluan autoriti backend untuk pendaftaran (Fasa 2C `P1-8`) · (iv) pembetulan `register_my_player()` (`WO-09`) · (v) audit grant/RLS tertunggak. `auto_suspend_on_red_card()` 1→2 kekal **Fasa F** (`WO-10`) ✔.
⚠️ **Percanggahan yang wajib Owner tahu (inilah sebab CTO melaporkan, bukan menyembunyikan):** CEO tulis "pelaksanaan **segera**" untuk (iv) dan (v), manakala `DEC-022` (jawapan K2 CEO sendiri, 1 hari lebih awal) menetapkan **tiada** sebarang reka bentuk skema sebelum `WO-08` eksport + `0001_baseline` siap, dan gerbang Fasa 2C (`BOUNDARIES.md` §7, verbatim) menutup **mana-mana DDL produksi** sehingga langkah 1–6 selesai.
**Penyelesaian yang CTO cadangkan (memenuhi kedua-dua arahan tanpa memecahkan gerbang):**
- **(a) Boleh dan wajar dibuat SEGERA, tanpa satu pun penulisan:** `WO-08` eksport read-only → keluaran yang sama **ialah** audit RLS/policy/grant untuk (v), dan bukti lajur untuk (iv) (`q03b`, `q07`, `q08`, `q10`, `q10b`, `q17`). 12 minit Owner, tiada risiko, dan ia **menyelesaikan** (v) pada tahap audit.
- **(b) Boleh dibuat SEGERA pada kertas:** draf *spesifikasi* pembetulan `WO-09` + senarai grant yang akan di-`REVOKE`, sebagai teks dalam dokumen fasa skema (tiada SQL dijalankan).
- **(c) Yang TIDAK boleh "segera":** `ALTER`/`CREATE OR REPLACE FUNCTION`/perubahan policy di **produksi**. Ia tetap menunggu langkah 1–6 Fasa 2C.
Cuti: jika Owner/CEO mahu (iv) didahulukan **melepasi** `DEC-022`, itu hak mereka — tetapi ia mesti direkod sebagai `DEC-034` yang menjelaskan **`SUPERSEDES DEC-022`**, supaya tiada AI selepas ini menyangka ia penyimpangan. CTO tidak akan menggabungkan (c) tanpa rekod itu.

---

---

## I. Keputusan CEO pusingan 4 (Gemini) 2026-09-10 — jawapan J1…J3

> **J1.** "12 bulan dari tarikh kelulusan (A), bagi memastikan pemain mendapat tempoh sah laku penuh tanpa terjejas oleh kalendar tahun semasa."
> **J2.** "Ya, sahkan `INELIGIBLE_EXPIRED` sebagai ejaan kanonik yang menggantikan `EXPIRED` Sepenuhnya dalam senarai keadaan kelayakan."
> **J3.** "Simpan dokumen dengan cap \"expired\" untuk keperluan audit sejarah dan pematuhan arkib jangka panjang."

**DEC-034 — tempoh sah laku = 12 bulan ROLLING dari tarikh kelulusan (J1).** Bukan tamat 31 Disember. `DEC-031(b)` kini lengkap: `luput_pada = approved_at + interval '1 year'`.
*Nota CTO:* (i) **pembaharuan (renewal) menetapkan semula jam** dari tarikh kelulusan baharu — ini lanjutan logik arahan CEO, bukan keputusan baharu; (ii) setiap rekod pengesahan **wajib simpan kedua-dua** `approved_at` dan `expires_at` yang telah dikira, supaya sejarah boleh dibina semula walaupun peraturan pembundaran tarikh berubah; (iii) **jam bermula pada kelulusan ASAS juga** (bukan hanya LANJUT) — kalau CEO maksudkan LANJUT sahaja, itu perlu `DEC-038`, kerana amatur dengan telefon + MyKad yang "sah selamanya" ialah polisi berbeza.

**DEC-035 — nama kanonik keadaan: `INELIGIBLE_EXPIRED`.** Menggantikan `EXPIRED` **sepenuhnya** dalam senarai keadaan `ELIGIBILITY` (J2). `BOUNDARIES.md` §1 telah dibetulkan sebagai **pembetulan konsistensi** atas kebenaran bertulis ini — bukan keputusan baharu, dan tiada entri `DEC-008`/`DEC-017` yang diubah.

**DEC-036 — dokumen yang luput DKEKALkan, bukan dipadam (J3).** Fail pengesahan LANJUT disimpan dengan **cap `expired`** untuk audit sejarah + pematuhan arkib jangka panjang.
⚠️ **Nota CTO — ini menambah beban, bukan mengurangnya (dan Owner perlu tahu sebelum ia jadi kod):**
1. **Tiada `DELETE`.** Dasar hayat bucket **mesti** melarang pemadaman automatik; sekali kita letak lifecycle "auto-expire objects", arahan CEO tercicir diam-diam.
2. **Akses mesti mengecil, bukan membesar.** Dokumen yang sudah `expired` **kehilang tujuan** untuk Organizer → policy aksesnya patut **lebih ketat** daripada yang masih sah (contoh: hanya pemilik + platform audit + perintah rayuan), supaya "arkib jangka panjang" tidak menjadi arkib kekal yang menjadi punca pendedahan PII.
3. **Ia bercanggah dengan minimum-retention PDPA 2010 (pindaan 2024)** melainkan ada asas undang-undang yang dinyatakan. CTO tidak memberi nasihat undang-undang; yang boleh saya rekam ialah: **`WO-22`** — Owner sahkan *asas + tempoh* arkib (contoh: 7 tahun untuk rekod kewangan/disiplin, atau "selagi akaun wujud") supaya `DEC-036` ada had bertulis. Tanpa `WO-22`, "jangka panjang" = **selamanya**, dan itu bukan sesuatu yang patut dibina tanpa tarikh.
4. **Padam atas permintaan (hak pemain) belum ada laluan.** Perlu keputusan CEO/Owner: adakah cap `expired` + pemadaman mengikut permintaan wujud? Direkod sebagai `WO-22`.

**DEC-038 — jam luput HANYA pada tahap LANJUT (jawapan K1, 2026-09-10).** Tahap **ASAS** (MyKad + nombor telefon) sah **selagi akaun hidup**; tempoh **12 bulan** terpakai **hanya** untuk tahap **LANJUT** (kategori kompetitif). Niat CEO direkod: elak beban pentadbiran + pembaharuan tahunan di peringkat akar umbi.
*Nota CTO — empat akibat yang wajib ikut serta (lanjutan logik arahan ini, bukan keputusan baharu):*
1. **`DEC-031(b)`/`DEC-034` tersekat skopnya:** `expires_at` **null** untuk ASAS, **dikira** untuk LANJUT. Mekanisme luput automatik + `INELIGIBLE_EXPIRED` (`DEC-031(c)`, `DEC-035`) berjalan **hanya** pada LANJUT; notifikasi (`WO-21`) pun LANJUT sahaja.
2. **"Tiada tarikh luput" ≠ "umur tak perlu disemak."** Kelayakan umur/kategori mesti sentiasa dikira daripada `date_of_birth` **setiap perlawanan**, bukan daripada kesegaran pengesahan. Kalau tidak: seorang yang disahkan ASAS pada umur 15 kekal "sah" dan boleh tersalah letak dalam kategori B18 pada umur 17. CTO menetapkan ini sebagai **syarat penerimaan** (pengukuhan `MA-02`), dan ia mesti ada ujian tertulis.
3. **Perlu satu tempat menyimpan "tahap mana yang diwajibkan":** kelayakan kini bergantung pada **tahap yang disyaratkan kategori pertandingan** → fasa skema mesti boleh nyatakan *kategori → tahap pengesahan diwajibkan*. **Nama objek/lajur belum dipilih** dan tidak akan dipilih di luar fasa SKEMA.
4. **Laluan pembaharuan LANJUT diperlukan:** hantar dokumen → kelulusan penganjur → `approved_at`/`expires_at` sebagai **rekod baharu** (append, bukan tulis-ganti), supaya `DEC-015` (provenance satu arah) dan audit `DEC-036` kekal utuh.
✅ Yang diselesaikan oleh K1: kebimbangan operasi besar — **tiada** penyingkiran pemain amatur beramai-ramai setiap tahun, dan **tiada** pemain jatuh tidak layak di tengah musim sebab kalendar.

**Nota penomboran (penting, supaya nombor tidak bercanggah):** CEO menjawab tiga soalan yang **beliau** namakan J1/J2/J3 (tahun kalendar · ejaan status · retensi). Jadual soalan dalam `BACKLOG.md` ada **J3 yang berbeza** (landasan dev untuk uji DDL). Jawapan retensi CEO = **`DEC-036`**; soalan landasan dev **masih terbuka** dan kini berlabel **`J3-TIDAK-KENA` / `WO-20`** supaya tiada AI menyangka ia sudah dijawab.

**`DEC-037` — DIKOSONGKAN (reserved).** Nombor ini dikosongkan untuk kes *"Owner/CEO melangkau gerbang `DEC-022`"* (lihat `DEC-033` bahagian (c)). Jangan guna `DEC-037` untuk isu lain; kalau ia dipakai, dokumen ini jadi bercanggah nombor — dan nombor yang bercanggah itulah yang menyebabkan "semalam kau cakap lain".

---

## J. Dapatan semakan bebas 2026-09-10 (bukan keputusan beku)

Sumber: `PEER_REVIEW_2026-09-10.md` (Reviewer = ChatGPT; akses live Supabase yang CTO semasa tidak punya).

**DEC-039 — kaedah rekonsiliasi baseline (`PROPOSED` oleh CTO, belum diluluskan CEO).** `0001_baseline.sql` mesti dijana dengan turutan 12 lapis, **bukan** `merge` buta:
```
[DB] live: tables -> columns -> constraints -> indexes -> views -> functions
     -> triggers -> policies -> grants -> enums -> extensions -> migration history
-> [GIT] yang sedia ada -> LEGACY database/*.sql -> TARGET v1.3
```
Setiap lapis memulangkan **perbezaan**, bukan pengesahan; tiga lapisan terakhir ialah tempat `DRIFT-007`…`DRIFT-012` diselesaikan. Status `PROPOSED` → CEO sahkan (ya/tukar) **sebelum** `WO-08` dianggap selesai.

Yang **tidak** berubah: v1.3 kekal beku; tiada `DEC-xxx` digantikan; tiada objek DB disentuh. Semakan ini menyentuh **fakta mekanikal**, bukan semantik domain.

---


### §J.2 Semakan kedua (R2, 2026-09-10 malam) — diterima, dan dua `PROPOSED` baharu

R2 mengesahkan angka hidup kami (21/5/20/16/61 + 4 versi migrasi + 0 fail di `[GIT]`), mengesahkan ref `muirhenvjruvfxenoaxm` = **`playpro2`**, dan menandai tiga hal yang CTO salah tafsir dari sisi kod sahaja: pipeline `run_post_match_pipeline()` **tiada live**, `trg_fixture_status_pipeline` **tiada**, dan `authenticated` **tiada INSERT** pada `match_events`. Butiran penuh + bantahan CTO (4): `PEER_REVIEW_2026-09-10.md` §10.

**`DEC-040 (PROPOSED)` — Teks migrasi diimport sebagai REKOD, bukan untuk dijalankan.** Supabase menyimpan teks 4 migrasi dalam `supabase_migrations.schema_migrations.statements` (ditemui R2). Cadangan: satu SELECT read-only → fail disimpan di `supabase/migrations/` di branch kerja → direkonsiliasi dalam `0001_baseline.sql` ikut `DEC-022`. **LARANGAN:** fail itu **tidak boleh** dianggap "sudah diterapkan", dan tidak boleh dijalankan; `0001_baseline.sql` tetap lahir daripada **introspeksi**, bukan daripada salinan sejarah. Pelulus: **CEO (Gemini) + Owner**; CTO tidak meluluskan reka bentuknya sendiri.

**`DEC-041 (PROPOSED)` — Satu arkitektur derivation statistik mesti dipilih SEBELUM skema direka.** (A) Fasa-3: RPC observer penulis tunggal · (B) Fasa-6/7 legacy: klien tulis jadual + trigger derive (teks penuh `database/playpro_phase6_7_pipeline.sql`). Bukti: **dua-dua wujud di `[GIT]`**, hanya (A) sebahagian di `[DB]`, dan **tiada satu pun bersambung ke UI** (`DRIFT-017`…`DRIFT-020`). Pelulus: **CEO + Owner** → `WO-35`. Keputusan ini menentukan samada 7 lajur ditambah (B) atau `MatchRepo` match-writer dibuang (A); maka ia **mendahului** apa-apa kerja reka bentuk jadual statistik.

Yang **TIDAK** berubah: `DEC-001`…`DEC-038` (beku) · skop terkunci (`leagues` tidak dibuang/direname pada migrasi pertama; `match_events` calon satu-satunya kebenaran perlawanan) · `DEC-022` sebagai gerbang #1 · larangan DDL produksi · status `DEC-039` sebagai `PROPOSED`. Verdict R2 ("forensic baseline accepted / not production ready") ialah **semakan** — dan diterima sebagai demikian, bukan sebagai kelulusan.
## K. Log append-only

| Tarikh | Peristiwa |
|---|---|
| 2026-09-09 | Blueprint v1.3 FROZEN (Owner + CEO); CTO acknowledge |
| 2026-09-10 | Owner tetapkan peranan: Gemini=CEO, Arena=CTO, ChatGPT=reviewer (DEC-018) |
| 2026-09-10 | MASTER CONTEXT ditulis sebagai **PR #5** (7 fail, +671) · `main` tidak disentuh |
| 2026-09-10 | CEO jawab K1–K5 → DEC-021…DEC-026 direkod. R-02 selesai; R-05 separuh (**R-05a OPEN**); `WO-08` jadi keutamaan #1 |
| 2026-09-10 (petang 2) | CEO jawab G1–G4 → `DEC-027`…`DEC-030`. **R-05a diselesaikan sebagai alih-tangguh bertamad**, R-06 disahkan (A→J), R-03 dijawab (2 tahap KYC) → `R-03a` OPEN. Default `Q3/Q4/Q5` ditetapkan (A / jangan petik nombor / PR kod berasingan) |
| 2026-09-10 (malam) | CEO jawab H1–H3 → `DEC-031`…`DEC-033`. **R-01 ditutup** (venue = entiti berasingan). Tiga teguran CTO direkod: typo `INELEGIBLE_EXPIRED` → `INELIGIBLE_EXPIRED`; pertindihan nama dengan `EXPIRED` sedia ada; dan **percanggahan `DEC-033` vs `DEC-022`** (segera vs gerbang) dengan jalan keluar 3 bahagian (a/b/c) |
| 2026-09-10 (malam 7) | Soalan Owner ("mana file ni?") menghasilkan **3 fakta yang mengubah cara `WO-28` dijalankan, bukan mengubah keputusan**: (i) `match_observer.html` ada di `main` tetapi **yatim** — 0 pautan dari `index.html`, hanya 2 butang di `coach_command_center.html` L218/L324 → itu penjelasan paling munasabah mengapa kiyasan ✅ `DRIFT-013` kekal tak perasan: mangsanya sukar ditemui; (ii) anon key L15 = key SEBENAR (bukan placeholder), `ref=muirhenvjruvfxenoaxm` → apl memang mengarah ke projek itu; `WO-30` tinggal **nama projek** dan itu semak 10 saat di baris alamat dashboard; (iii) angka `DRIFT-016` saya betulkan daripada ukuran — sebelum ini tertulis "6 daripada 12 halaman" (ingatan), sebenar **16 rujukan / 3 skrip / 17 halaman** (`shared_dashboard_components` hanya 4 halaman). Tiada `DEC-xxx` berubah; `DEC-039` kekal `PROPOSED` |
| 2026-09-10 (malam 8) | **R2 Reviewer diterima sebagai SEMANT, bukan kelulusan.** 15 fakta `[DB]` direkod; 2 kesimpulan CTO dibetulkan (`DRIFT-014` turun taraf; senarai RPC klien dirinci 7+6); 4 temuan CTO baharu (`DRIFT-017`…`DRIFT-020`). `DEC-040` + `DEC-041` dibuka **`PROPOSED`** (pelulus: CEO+Owner; CTO tidak meluluskan reka bentuk sendiri). Bantahan CTO: "BASELINE VERIFIED" pramatang ikut `DEC-022` (disahkan ≠ dieksport); "antara lain" bukan senarai penutup; petikan §17 R2 tiada dalam mana-mana fail. Tiada `DEC-001`…`DEC-039` berubah; tiada DDL; `main` tidak berubah |
| 2026-09-10 (malam 6) | Addendum CTO daripada semakan Reviewer: 4 temuan **`[GIT]`** direkod di `PEER_REVIEW_2026-09-10.md` §9 — `DRIFT-013` (observer mungkin tak menyimpan + ✅ palsu) · `DRIFT-014` (penulis 404 itu menunjuk ke skema lain: 6 lajur tiada, `sequence`/`recorded_by`/`voided_*` ditinggalkan) · `DRIFT-015` (`savePlayerStats` upsert terus + `trg_fixture_status_pipeline` = dua arkitektur bersaing) · `DRIFT-016` (3 skrip 404 pada 6 halaman, termasuk `playpro_audit_fixes.js`). Diletak larangan `WO-29`: jangan "baiki 404" dengan menyalin fail. **Tiada keputusan beku diubah** |
| 2026-09-10 (malam 5) | **Semakan bebas Reviewer (ChatGPT) diterima + disimpan** (`PEER_REVIEW_2026-09-10.md`). 3 angka `[DB]` kami **lapuk** (14→**20** fungsi, 57→**61** policy, 0→**4** migration) dan dibetulkan di `EVIDENCE.md`/`ENVIRONMENT.md`; `DEC-039 (PROPOSED)` ditambah. **Tiada keputusan beku diubah** |
| 2026-09-10 (malam 4) | CEO jawab K1 → **`DEC-038`**: ASAS sah selagi akaun hidup; 12 bulan hanya LANJUT. 4 akibat direkod (`expires_at` null untuk ASAS · umur wajib dikira dari `date_of_birth` setiap perlawanan · kategori perlu simpan "tahap diwajibkan" · renewal LANJUT = rekod baharu, append). **Halangan semantik untuk fasa SKEMA = NOL.** R-04/R-07 kekal ditangguh seperti diarah |
