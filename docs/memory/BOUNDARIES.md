# BOUNDARIES.md — Sempadan Makna, Sumber Kebenaran, dan Senarai Larangan

Dokumen ini **tidak menetapkan reka bentuk**. Ia hanya menetapkan (a) makna yang tidak boleh dipertikaikan, (b) di mana kebenaran tinggal, (c) apa yang dilarang.

---

## 1. Lima kitaran hayat BERASINGAN (DEC-008 / DEC-017)

| # | Kitaran | Keadaan | Peraturan penting |
|---|---|---|---|
| 1 | **MEMBERSHIP** (orang ↔ Organization/Team) | `REQUESTED` / `INVITED` → `TRIAL` (pilihan) → `ACTIVE` → `SUSPENDED` → `ENDED` | `SUSPENDED` **non-terminal**, boleh dipulih. Tamat membership **tidak** memadam sejarah sumbangan. |
| 2 | **REGISTRATION** (Team/Squad ↔ Competition+Category) | `DRAFT` → `SUBMITTED` → `APPROVED` / `REJECTED` / `WITHDRAWN` | Lulus pendaftaran ≠ layak bermain. |
| 3 | **PAYMENT** | `NONE_DUE` / `PENDING` / `PAID` / `PARTIALLY_REFUNDED` / `REFUNDED` / `FAILED` | Tiada auto-cascade ke registration/eligibility; `CANCELLED` sahaja laluan terminal yang dibenarkan merantai. |
| 4 | **ELIGIBILITY** (pemain ↔ perlawanan) | `ELIGIBLE` / `INELIGIBLE_PENDING` / `INELIGIBLE_BLOCKED` / **`INELIGIBLE_EXPIRED`** / `SUSPENDED_BY_SANCTION` | Dikira semula setiap perlawanan daripada sumber, bukan disalin sekali. *Nama ini disahkan CEO 2026-09-10 (`DEC-035`) dan menggantikan `EXPIRED` sepenuhnya* |
| 5 | **PARTICIPATION** (penampilan dalam sesuatu perlawanan) | `SCHEDULED` → `IN_SQUAD` → `ON_PITCH` → `SUBBED_OFF`/`RECALLED`(ikut peraturan) → `COMPLETED` | ACTIVE dalam Participation **≠** ELIGIBLE (MA-02). |

**Larangan langsung:** menjadikan satu kitaran sebagai proksi kitaran lain (contoh yang pernah berlaku: `profiles.role` sebagai proksi capability; `participation=ACTIVE` sebagai proksi eligibility; `organizer.status=ACTIVE` sebagai proksi kebenaran keselamatan).

---

## 2. Matriks sumber kebenaran (source of truth)

| Soalan | Di mana jawabannya | Yang TIDAK boleh jadi jawapan |
|---|---|---|
| Siapa saya (identiti) | `auth.users` + `profiles` (identiti sahaja) | `localStorage`, `var loggedInUser = "Azlan"` |
| Apa yang saya **boleh buat** (capability) | jadual capability + policy (menggantikan `profiles.role`) | nama papar, peranan dalam teks, butang yang disorok |
| Saya disahkan pada tahap apa | rekod verification (R-03) | `kyc_status` hardcoded dalam fail awam |
| Keputusan perlawanan (gol, kad, possession, masa) | `match_events` (event-sourced) + `match_playing_time` | jadual ringkasan, UI, suntingan selepas perlawanan |
| Disiplin & penggantungan | `DisciplinaryRecord` → `Sanction` → `Eligibility` (provenance satu arah, DEC-015) | lajur boolean pada `players` |
| Kedudukan liga / statistik terkumpul | **view terkira** daripada event | jadual yang disuai tanpa kira semula (double-count pernah berlaku di Fasa-3) |
| Penilaian pemain | `Assessment` append-only, versioned → Verified Attribute Version | skor OVR disimpan sebagai kebenaran asal (ia unjuran) |
| Keadaan projek hari ini | `docs/memory/STATE.md` + `git log` + API GitHub | ingatan sesi chat |
| Keadaan skema produksi | **introspeksi DB Supabase** (skrip `EVIDENCE.md` §D) | `database/*.sql` (legacy), `docs/ARCHITECTURE.md` (rekaan), `docs/DEPLOYMENT.md` (nama migrasi palsu) |

---

## 3. Rumus autoriti yang wajib ada dalam setiap policy/RPC (DEC-009)

```
authorized = identity AND capability AND verification AND organizer_context
             AND competition_context AND resource AND state
```

- 7 faktor; **tiada yang boleh dibuang** demi "senang dulu".
- `organizer.status`, flag boolean UI, dan "dia nampak butang" **bukan** faktor.
- Client-side hiding = **kosmetik**, bukan kawalan. (Ini cacat yang ada hari ini pada baris 3601 `index.html`.)
- Setiap RPC yang mengubah keadaan wajib: `security_invoker` atau `search_path` pinned, semakan `state`, dan audit trail; jangan `SECURITY DEFINER` yang boleh dipanggil `authenticated` secara umum (baki audit: ~13 fungsi).

---

## 4. Enam perkataan yang tidak boleh bertindih (DEC-014)

`Registration` · `Payment` · `Approval` · `Eligibility` · `Participation` · `Membership`
Satu lajur / satu status **tidak boleh** menjawab dua daripada soalan ini. Kalau nampak perlu → itu tanda skema salah, bukan tanda jimat ruang.

---

## 5. Azlan = persona rujukan pembangunan (DEC-019), bukan seed

Nilai rujukan yang boleh dipakai dalam **dokumen/senario ujian/contoh API** sahaja:

```
Azlan Mohd · DOB 1976-09-27 · Negeri Sembilan, MY · 170 cm / 68 kg · kaki kanan · #8 · CM
OVR 91 (Elite) · PAC 92 SHO 89 PAS 96 DRI 95 DEF 78 PHY 88 · status: verified
DNA 1–20: Acc 18 · Pace 19 · Agi 19 · Bal 18 · Sta 18 · Str 16 · Jump 15 ·
          Pass 20 · Drib 19 · Fin 18 · Tech 19 · Tack 15 · Head 16 · Cross 19
```

**Dilarang:** meletakkannya sebagai data lalai dalam kod, `DEFAULT_PLAYER_REGISTRY`, seed migrasi, atau nilai auto-heal. Dibenarkan: sebagai contoh dalam dokumen dan fixture ujian (dicipta dalam projek Supabase **boleh-guna** sahaja, bukan di produksi).

Data rakan Owner yang berada dalam `index.html` = data ujian → **dibuang** (WO-02), termasuk `passport_number` gaya-malaysia + `date_of_birth` + `kyc_status` yang kini terserlah dalam fail awam.

---

## 6. Enam larangan reka bentuk (ringkas)

1. Jangan cipta jadual hanya kerana `database/*.sql` atau kod legacy menyebutnya.
2. Jangan tukar nama / buang `leagues` dalam migrasi pertama (R-02 belum dijawab).
3. Jangan buat kolum yang menyimpan hasil kiraan sebagai kebenaran (standings, OVR, jumlah kad) tanpa definisi kiraan semula.
4. Jangan buat cascade automatik untuk bayaran balik / tamat tempoh; `CANCELLED` satu-satunya terminal yang merantai.
5. Jangan buat "mode admin" yang melangkau semakan state + context.
6. Jangan tambah objek baharu (termasuk view, index, trigger) pada Fasa yang belum membuka pintu objek itu.

---

## 7. Definition of Gate — apa bermakna "fasa selesai"

| Fasa | Keluaran | Gerbang |
|---|---|---|
| **v1.3 beku** | teks penuh §1–64 dalam `docs/memory/BLUEPRINT_V1.3.md` | Owner sahkan vs sumber; ringkasan di `DECISIONS.md` menjadi seiras |
| **MASTER CONTEXT** | 9 fail (`AGENTS.md` + 6 dokumen + `INDEX_HTML_MAP.md` + `sql/PRODUCTION_TRUTH_EXPORT.sql`; **7 fail pada commit pertama `a7288b9`**, 9 sekarang selepas pemetaan + kit eksport + `PEER_REVIEW`) | PR digabung selepas CI hijau + kelulusan Owner (bukan selepas "nampak cantik") |
| **REKA BENTUK SKEMA** | DDL *cadangan* sahaja (teks .sql dalam dokumen, **tidak** dijalankan) | Lulus semakan CEO (semantik) + Reviewer (pertentangan dengan DEC-xxx) |
| **SEMAKAN SKEMA** | laporan audit (bentuk P1-x seperti Fasa 2C) | semua P1 selesai atau ditulis sebagai penerimaan bersyarat Owner |
| **PELAN MIGRASI** | turutan fail bernombor + pelan balik | sahaja selepas 7 langkah Fasa 2C dipenuhi |
| **PELAKSANAAN** | PR kod, test hijau | **tiada** DDL produksi tanpa work order bertandatangan Owner |
| **UJIAN** | MA-01…MA-04 lulus, dilaporkan dengan nombor | laporan + bukti SQL, bukan prosa |

**7 langkah Fasa 2C — gerbang wajib sebelum mana-mana DDL produksi.** Sumber: `docs/PLAYPRO_PHASE2C_STATIC_AUDIT_v1.md` §"Required next sequence" (baris 84–94) pada branch `phase-2/canonical-model`. Petikan **VERBATIM** — jangan tafsir semula:

```
1. Correct capability lifecycle uniqueness.
2. Define server-authoritative live-event write contract.
3. Define playing-time and match-start/end invariants.
4. Define updated_at ownership.
5. Complete Phase 3 security policy matrix.
6. Produce a revised development baseline.
7. Only then consider a disposable Supabase development branch for migration execution testing.

Production migration remains unauthorized.
```

**Pengecualian kecemasan Owner — 14 Nov 2026 (skop terhad):** Owner meluluskan pelaksanaan pembaikan keselamatan akaun dinyahaktifkan pada projek Supabase aktif `playpro2` sahaja, walaupun gerbang 7 langkah belum selesai. Pengecualian ini hanya meliputi pengawal akaun aktif, penguncian RPC/RLS, dan ujian pengesahan yang berkaitan. Ia **bukan** kebenaran umum untuk DDL lain, pembangunan ciri, perubahan rasmi kemasukan pertandingan, reka bentuk sejarah/rating, atau kerja pada projek `playpro` / `playpro1`. Tiada deployment Vercel dibenarkan melalui pengecualian ini. Migrasi yang diluluskan: `20261114105719`, `20261114105826`, `20261114105934`, `20261114110516`, `20261114110725`, `20261114114015`, `20261114114117`.

**Pelanjutan kebenaran Owner — 14 Nov 2026 (arahan eksplisit dalam chat):** Owner membenarkan kerja pembaikan yang boleh disiapkan tanpa deployment Vercel, termasuk hardening RPC bacaan peribadi dan kawalan kemasukan kelab ke liga pada projek Supabase aktif `playpro2`, serta penyelarasan migrasi ke branch PR #60. Skop ini tidak membenarkan deployment Vercel, merge PR, perubahan pada projek `playpro` / `playpro1`, atau perubahan data pengguna sebenar; ujian fixture mesti di-rollback. Migrasi tambahan dalam skop ini: `20261114114015`, `20261114114117`, `20261114114231`, `20261114114925`, `20261114115214`, `20261114115556`, `20261114120920`. Semakan kelayakan roster pemain (KYC, umur/kategori dan keahlian pasukan) kekal berasingan dan tidak dianggap selesai oleh polisi `league_clubs` ini. Pelanjutan arahan Owner seterusnya meliputi minimisasi data profil pemain awam/peribadi dan pembatalan refresh token/sesi Auth apabila akaun dinyahaktifkan, bersama ujian rollback dan penyelarasan ke PR #60; token akses JWT yang telah ditandatangani kekal sah sehingga tamat tempoh, tetapi operasi DB terlindung terus ditolak oleh active-account guards. Profil peribadi kini mengembalikan respons terhad kepada tetamu/pengikut tanpa akses yang diluluskan, dan respons awam/pengikut yang dibenarkan tidak memulangkan tarikh lahir, nombor Passport, UUID profil/kelab atau penanda demo; pemilik masih boleh membaca butiran sendiri. Aliran Coach turut diperketatkan: profil baharu bermula `unverified`, permohonan KYC mengemas kini permohonan pending sedia ada dan tidak boleh menurunkan status Coach yang sudah verified, kelulusan memerlukan dokumen dilampirkan, keputusan OCR bukan `match` memerlukan nota semakan, tarikh lahir yang disahkan reviewer mengatasi OCR, dan polisi bacaan/muat naik KYC Coach menyemak akaun aktif. Edge Function `kyc-verify-coach` versi 3 turut menyemak `profiles.is_active` sebelum memproses dokumen; deployment ini hanya ke Supabase Edge Functions, bukan Vercel.  Semasa dinyahaktifkan, semua pautan role tambahan dinyahaktifkan tetapi rekod dikekalkan; selepas pengaktifan semula, role tidak dipulihkan secara automatik dan hanya Developer aktif boleh memulihkan pautan role sedia ada melalui RPC `playpro_restore_profile_role`, dengan jejak audit.

⚠️ Nota CTO: dokumen yang mengandungi 7 langkah ini **belum masuk `main`** — ia tersangkut di branch tanpa PR (`BACKLOG.md` WO-15). AI yang hanya membaca `main` tidak akan menemuinya.

P1 wajib yang direkod dalam dokumen yang sama (P1-4…P1-9), sebagai peringatan supaya tidak diulang: `unique(profile_id, capability)` **salah** untuk sejarah revoke→regrant (perlu active-row uniqueness / status) · `match_events.sequence` **dibekalkan klien** (race-prone; agihan mesti berlaku di pelayan) · lebih dari satu selang playing-time aktif boleh wujud untuk pemain yang sama · `MATCH_START`/`MATCH_END` tiada unik · `competition_player_registrations` perlu laluan autoriti backend + semakan kelayakan · `verification_cases` (KYC) **mesti kekal di luar** public view pemain/kelab.


## 8. KYC individu pusat (DEC-043 — arahan Owner 2026-11-14)

- Sumber kebenaran KYC ialah satu rekod identiti individu per akaun, bukan rekod berasingan per role.
- Semua role menggunakan pengesahan identiti pusat yang sama; status sah selama lima tahun dari tarikh pengesahan.
- Role-specific verification hanya untuk lesen, akreditasi, kelayakan atau kuasa profesional — bukan untuk mengesahkan semula identiti.
- Pengiktirafan kelab ialah semakan entiti organisasi dan kekal berasingan daripada KYC Club Owner.
- KYC tidak menjadi syarat untuk aktiviti yang tidak memerlukannya. Apabila diperlukan, sistem menyemak status pusat; ia tidak meminta dokumen kedua.
- Dokumen identiti dan metadata KYC kekal private. Tempoh sah lima tahun ialah tempoh sah pengesahan, bukan kebenaran akses tanpa had atau pengecualian daripada undang-undang perlindungan data.
- Semua modul mesti menggunakan satu aliran KYC pusat dan komponen onboarding yang seragam.
