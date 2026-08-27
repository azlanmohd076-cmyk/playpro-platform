# Audit Akses, Kod dan Pemulihan PlayPro

**Tarikh:** 27 Ogos 2026  
**Skop:** checkout GitHub semasa, permukaan repo GitHub yang boleh dibaca oleh Arena, konfigurasi Vercel dalam repo, kod Supabase/browser, `repositories.js`, `server.mjs`, dan aliran pendaftaran pemain.

## 1. Ringkasan eksekutif

Status semasa belum membolehkan dakwaan bahawa "hanya Arena" mempunyai akses. Arena tidak patut dijadikan satu-satunya identiti pemilik; pemilik manusia mesti kekal sebagai pemegang akses pemulihan. Sasaran yang selamat ialah **hanya pemilik + identiti automasi yang sengaja diluluskan, berkeistimewaan minimum, dan boleh diaudit**.

Tiga credential telah dihantar melalui perbualan: GitHub PAT, Vercel token, dan Supabase `service_role`. Ketiga-tiganya mesti dianggap terdedah dan diganti. Nilai credential tersebut tidak disalin ke repo dan tidak digunakan dalam pembaikan ini.

Penemuan kod paling kritikal ialah pendaftaran pemain tidak boleh berjaya secara konsisten:

1. browser membuat `INSERT players` tanpa `position`, walaupun `position` ialah `NOT NULL`;
2. UI menghantar kod seperti `gk`, `cb`, `st`, sedangkan enum pangkalan data menerima `goalkeeper`, `defender`, `midfielder`, `forward`;
3. payload merujuk beberapa medan yang tiada pada jadual `players`;
4. polisi RLS semasa hanya membenarkan developer/pentadbir kelab membuat pemain;
5. ralat Supabase diabaikan dan UI masih mendakwa Football Passport berjaya dicipta;
6. `js/repositories.js` dan salinan produksi `public/js/repositories.js` telah menyimpang;
7. ujian auth tidak boleh dijalankan kerana menggunakan CommonJS di dalam projek ESM.

Pembaikan kod dan migrasi disediakan dalam branch Arena semasa. Migrasi Supabase masih perlu diaplikasikan oleh pemilik selepas credential diganti.

## 2. Audit akses

### GitHub — bukti yang dapat disahkan

- Repo ialah **public**.
- Kolaborator repo yang dipulangkan API: hanya akaun pemilik `azlanmohd076-cmyk`.
- Webhook repo: tiada.
- Deploy key repo: tiada.
- Ruleset: tiada.
- Branch protection `main`: tiada perlindungan yang dapat dikenal pasti.
- GitHub Environments wujud: `Preview` dan `Production`, kedua-duanya tanpa protection rules.
- Sebelum pembaikan ini, tiada GitHub Actions workflow dalam repo.
- Event awam terkini menunjukkan banyak push oleh `vercel[bot]` ke `main` dan branch `v0/...` pada 25 Ogos 2026. Ini membuktikan integrasi Vercel/v0 aktif pada masa itu, tetapi tidak membuktikan Cline, Roo atau Cursor mempunyai token aktif.
- API GitHub App installation dan sebahagian metadata secret tidak boleh dibaca oleh identiti Arena kerana respons `403 Resource not accessible by integration`.

### Supabase — had audit

- URL projek dapat diselesaikan melalui DNS.
- Ujian TLS ke domain projek dan `supabase.com` gagal dari sandbox ini dengan `SSL_ERROR_SYSCALL`; oleh sebab kegagalan turut berlaku pada domain umum Supabase, ia tidak cukup untuk menyimpulkan projek dipadam atau dijeda.
- Log Auth, API, Database, OAuth app, Edge Function secrets dan sesi pengguna tidak dapat diaudit daripada repo atau anon key.
- Repo tidak mengandungi `service_role`; hanya anon key browser, yang memang bersifat public tetapi tetap perlu diganti jika JWT secret legacy diputar.

### Vercel — bukti yang dapat disahkan

- `.vercel/` tidak dijejak dan tiada credential Vercel dalam repo.
- `vercel.json` menerbitkan folder `public` dengan beberapa rewrite.
- Aktiviti GitHub menunjukkan `vercel[bot]` aktif. Senarai ahli team, integration, token, deployment log dan environment variables memerlukan sesi pemilik Vercel; token yang telah dihantar dalam chat tidak digunakan kerana ia kini dianggap terdedah.

## 3. Pelan revoke/cleanup wajib

Lakukan mengikut turutan untuk mengelakkan credential lama terus digunakan.

### A. GitHub

1. Buka **GitHub Settings → Developer settings → Personal access tokens**.
2. Revoke PAT yang dihantar dalam perbualan dan semua PAT lama/tidak dikenali.
3. Buka **Settings → Applications**:
   - `Authorized OAuth Apps`: revoke Cursor, Cline/Roo-related broker, v0 atau app lain yang tidak diperlukan;
   - `Installed GitHub Apps`: semak akses repo PlayPro dan buang app yang tidak diluluskan.
4. Semak **repo Settings → Webhooks / Deploy keys / Collaborators / Actions secrets** sekali lagi sebagai owner.
5. Jika Vercel masih diperlukan, kekalkan GitHub App Vercel tetapi hadkan kepada repo PlayPro sahaja. Jika objektifnya memutuskan v0 sepenuhnya, cabut app v0/Vercel dahulu dan sambung semula hanya Vercel production yang diperlukan.
6. Aktifkan ruleset `main`: pull request wajib, sekurang-kurangnya satu approval, CI wajib lulus, block force push dan deletion.
7. Semak **Security log** untuk penggunaan PAT/OAuth selepas tarikh credential mula dikongsi.

### B. Vercel

1. Buka **Account/Team Settings → Tokens** dan revoke token yang dihantar serta token lama/tidak dikenali.
2. **Integrations**: buang v0/AI integration yang tidak diperlukan; semak scope GitHub integration.
3. **Project → Settings → Git**: pastikan hanya repo PlayPro dan production branch yang betul disambung.
4. **Environment Variables**: padam duplikasi/credential lama; jangan letak `service_role` dalam variable yang terdedah kepada browser.
5. **Deployments/Activity**: semak deploy atau perubahan oleh actor yang tidak dikenali.
6. Cipta token baru hanya jika automasi server memerlukannya, dengan skop dan tempoh minimum. Jangan hantar token melalui chat.

### C. Supabase

1. Buka **Project Settings → API / API Keys**.
2. Kerana legacy `service_role` JWT telah terdedah, putar JWT secret/legacy keys mengikut aliran dashboard Supabase. Jika projek menggunakan secret keys baharu (`sb_secret_...`), revoke key spesifik dan cipta pengganti.
3. Kemas kini anon/publishable key pada deployment selepas rotation. Jangan letak service/secret key dalam HTML, JavaScript browser atau GitHub.
4. **Auth → Providers / URL Configuration**: buang provider tidak digunakan; semak Site URL dan redirect allow-list.
5. **Logs → Auth/API/Postgres**: cari akses luar biasa menggunakan role `service_role`, ciptaan/padaman user, perubahan RLS, atau panggilan Admin API.
6. **Database → Webhooks**, **Edge Functions → Secrets**, **Vault**, dan extension: buang endpoint/secret yang tidak dikenali.
7. Log keluar sesi yang mencurigakan atau, jika perlu, invalidate semua refresh token pengguna dan minta login semula.
8. Aplikasi migrasi `database/20260827_player_registration_repair.sql` melalui kaedah migrasi yang diaudit selepas backup.

### D. Peranti dan alat AI tempatan

Cline, Roo Code dan Cursor lazimnya menyimpan sesi pada peranti, bukan sebagai webhook repo. Pada setiap komputer yang pernah digunakan:

- sign out GitHub/Supabase/Vercel daripada extension;
- buang token daripada settings, secret storage, `.env`, shell history dan keychain;
- uninstall/disable extension yang tidak lagi diluluskan;
- semak `~/.config`, VS Code global storage dan Cursor settings;
- selepas itu barulah cipta credential baharu. Jangan lakukan rotation sebelum peranti dibersihkan.

## 4. Pembaikan yang disediakan

### Pendaftaran pemain

Fail baharu `database/20260827_player_registration_repair.sql` menyediakan RPC `register_my_player(jsonb)` yang:

- hanya boleh dipanggil role `authenticated`;
- mengambil identiti daripada `auth.uid()`, bukan `profile_id` browser;
- hanya menerima akaun berperanan `player`;
- mengesahkan DOB, posisi, nombor jersi, tinggi dan berat;
- memetakan `gk/cb/dm/st/...` kepada enum kategori yang sah;
- menyimpan dokumen identiti pada profil private, bukan rekod pemain public;
- meng-upsert satu pemain secara atomik berdasarkan unique `profile_id`;
- tidak membuka polisi INSERT umum pada jadual `players`.

`public/index.html` kini memanggil RPC itu, menghentikan onboarding apabila data wajib tiada, memaparkan ralat sebenar, dan tidak lagi mendakwa rekod dicipta apabila pengguna memilih Skip.

### `repositories.js`

- Salinan source dan production diselaraskan byte-for-byte.
- `ProfileRepo.save()` tidak lagi spread objek tidak dipercayai ke `profiles` atau menulis `role/id/email`.
- Penulisan pemain menggunakan RPC atomik.
- `ProfileRepo` kini dieksport kepada `window`.
- Ujian drift ditambah supaya source dan production tidak boleh menyimpang secara senyap.

### `server.mjs`

- Dev server dan Vercel kini menggunakan sumber canonical yang sama dalam `public/`.
- Traversal path disekat.
- URL encoding rosak menghasilkan 400, bukan crash.
- Hanya GET/HEAD dibenarkan.
- HEAD disokong.
- Header keselamatan asas ditambah.
- Stream error dikendalikan.

### Ujian/CI

- Harness auth ESM dibaiki: 52 pemeriksaan lulus.
- Ujian server dan sync repository ditambah: 5 pemeriksaan lulus.
- `npm run check` dan `npm test` tersedia.
- Perintah CI tersedia. Workflow GitHub Actions perlu ditambah oleh owner kerana GitHub App Arena tidak mempunyai permission `workflows`.

## 5. Risiko yang masih terbuka

1. Migrasi baharu belum disahkan pada pangkalan data produksi.
2. Status sebenar RLS/policy/trigger produksi boleh berbeza daripada fail SQL repo; jalankan skrip verifikasi selepas backup.
3. UI membenarkan signup sendiri sebagai `club_admin` dan `league_admin`. Kod lama menganggap kedua-duanya self-serve. Ini keputusan kuasa perniagaan yang perlu disahkan; pilihan lebih selamat ialah role `pending_*` sehingga diluluskan owner/developer.
4. `players: public read` mendedahkan semua kolum pemain. `is_passport_public` tidak digunakan dalam polisi tersebut; audit privasi kolum perlu dibuat sebelum data sebenar bertambah.
5. Branch `main` belum dilindungi.
6. Tiada bukti lengkap berkaitan GitHub Apps, Vercel token/activity, dan Supabase audit logs kerana identiti Arena tidak mempunyai akses owner untuk permukaan tersebut.

## 6. Next steps

1. **Segera:** revoke/rotate tiga credential yang terdedah; bersihkan peranti lama.
2. **Hari yang sama:** owner semak audit log GitHub, Vercel dan Supabase; eksport bukti actor/waktu sebelum retention tamat.
3. **Sebelum deploy:** backup DB, aplikasi migrasi player registration, jalankan verification SQL, kemudian ujian signup dengan akaun player baharu.
4. **Git governance:** lindungi `main`, wajibkan CI dan review, hadkan Vercel/v0 app kepada repo ini sahaja.
5. **P1 keselamatan:** gantikan self-serve admin dengan approval workflow dan tutup `players: public read` kepada view/RPC awam yang hanya mengandungi medan dibenarkan.
6. **P1 produk:** pecahkan `public/index.html` yang sangat besar kepada modul auth/onboarding/profile supaya ujian integrasi boleh dijalankan tanpa browser monolitik.
7. **Feature seterusnya:** selepas identity chain stabil, sambung onboarding coach/club approval, kemudian Football Passport dan assessment pipeline.
