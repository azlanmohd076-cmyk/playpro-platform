# Standard Onboarding PlayPro

Versi: 1.0 · 14 November 2026 · Selaras dengan DEC-043

Dokumen ini menetapkan satu perjalanan pengguna (user journey) dan satu bahasa UI untuk semua modul PlayPro. Ia melengkapkan docs/PLAYPRO_PRINCIPLES.md.

## 1. Perjalanan pengguna kanonik

1. **Daftar / log masuk** — satu akaun PlayPro sahaja.
2. **Profil asas** — nama dan maklumat asas disimpan sekali; modul tidak meminta maklumat yang sudah tersedia tanpa sebab.
3. **Pusat Peranan** — pengguna menambah atau membuka Player, Coach, Club Owner, Organizer atau Referee menggunakan akaun yang sama.
4. **KYC pusat apabila tindakan memerlukannya**:
   - Jika sah: teruskan serta-merta.
   - Jika sedang diproses / menunggu semakan: jangan minta dokumen lagi; pengguna boleh meneruskan aktiviti yang tidak memerlukan KYC.
   - Jika belum dihantar / luput / ditolak: satu halaman KYC pusat menerangkan tindakan seterusnya.
5. **Profil khusus peranan** — minta hanya data yang benar-benar diperlukan oleh peranan tersebut.
6. **Kelayakan profesional / entiti** — lesen, akreditasi, pengiktirafan kelab dan syarat pertandingan diproses berasingan daripada KYC.
7. **Dashboard peranan** — pengguna masuk terus ke ruang kerja yang dipilih.

## 2. Peraturan KYC

- Satu rekod identity_verifications dengan subject_type='individual' untuk satu profile_id.
- Tempoh sah lima tahun dari masa kelulusan.
- Penambahan role tidak mencipta rekod KYC baharu.
- Permohonan pending/processing dikekalkan dan digunakan semula.
- OCR hanya diproses sekali bagi set dokumen yang sama. OCR bukan kelulusan.
- Dokumen dimuat naik ke bucket private dan hanya boleh dibaca oleh pemilik aktif atau Developer yang diberi kuasa.
- Pembaharuan selepas luput menggunakan rekod kanonik yang sama; tiada borang role-specific.
- Lesen, akreditasi dan pengiktirafan entiti bukan KYC kedua.

## 3. Keperluan mengikut modul

| Modul | Profil boleh diwujudkan | KYC pusat | Semakan lain |
|---|---|---|---|
| Player | Ya, percuma | Sebelum tindakan yang mensyaratkannya seperti keahlian/penyertaan rasmi | Umur, kategori, roster dan eligibility |
| Coach | Ya | Hanya apabila tindakan memerlukannya; guna rekod sama | Lesen, kursus dan akreditasi Coach |
| Club Owner | Ya; kelab dan skuad boleh dibina awal | Guna rekod individu sama | Pengiktirafan kelab untuk pertandingan rasmi |
| Organizer | Ya | Guna rekod individu sama jika tindakan memerlukan | Pengiktirafan / kelayakan penganjur |
| Referee | Ya | Guna rekod individu sama jika tindakan memerlukan | Lesen dan akreditasi pengadil |

## 4. Standard UI

Semua halaman onboarding menggunakan /css/playpro-onboarding.css dan body.pp-onboarding untuk:
- warna PlayPro hijau gelap / hitam / emas;
- tipografi, label, input, butang dan panel yang konsisten;
- responsif mudah alih;
- status kejayaan, menunggu dan ralat yang jelas;
- pautan kembali ke Pusat Peranan.

Halaman KYC tunggal ialah /player_kyc.html. Parameter next hanya menentukan halaman sambungan selepas status dipaparkan; ia tidak menentukan jenis KYC.

Pusat pengurusan peranan tunggal ialah /role_center.html. Halaman profil Player tidak membina senarai pengurusan peranan kedua.

## 5. Copywriting wajib

Gunakan istilah **Pengesahan Identiti PlayPro (KYC)**. Elakkan label seperti "Player KYC", "Coach KYC" atau "Organizer KYC" sebagai proses berasingan.

Ayat standard:
- "KYC individu dibuat sekali dan dikongsi semua peranan PlayPro."
- "Jika identiti anda sudah disahkan dan masih sah, anda tidak perlu menghantar dokumen semula."
- "Lesen dan akreditasi ialah pengesahan profesional yang berasingan."
- "Profil boleh diwujudkan dahulu; KYC hanya diperlukan apabila tindakan itu memerlukannya."

## 6. Syarat penerimaan

- Akaun yang KYC-nya sah boleh menambah kelima-lima peranan tanpa muat naik dokumen kedua.
- Semua modul memaparkan status dan tarikh luput daripada RPC pusat yang sama.
- Permohonan pending/processing tidak menghasilkan permohonan kedua atau OCR berulang.
- Akaun belum KYC masih boleh mencipta profil asas dan melakukan aktiviti yang tidak memerlukan pengesahan.
- Player membership / roster / pertandingan rasmi tetap mengesahkan KYC pusat, umur, keahlian dan peraturan di backend.
- Lesen Coach/Referee dan pengiktirafan kelab kekal berasingan.
- Dokumen KYC tidak terdedah pada profil awam, carian awam atau kad pemain.
- Tiada ujian menggunakan dokumen palsu atau data identiti rekaan pada akaun sebenar.

## 7. Status pelaksanaan 14 November 2026

- Migration kanonik KYC dan pembetulan adapter/passport telah diterapkan ke Supabase playpro2.
- Edge Function OCR kyc-verify-coach dan alias keserasian kyc-verify-player menggunakan kod identiti individu yang sama; kedua-duanya mewajibkan JWT.
- Komponen UI bersama telah disambungkan ke Player onboarding, KYC, Developer KYC review, Coach, Club, Organizer, Referee, Role Center dan Player signup.
- PR #60 kekal terbuka. Vercel tidak dideploy.
- Ujian browser hujung ke hujung (upload dokumen sebenar, OCR Google, semakan Developer, dan role onboarding semua modul) masih memerlukan sesi pengguna sebenar; jangan lapor lulus sebelum diuji.
