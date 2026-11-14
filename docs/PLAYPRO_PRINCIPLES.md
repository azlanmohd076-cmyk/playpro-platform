# Prinsip Produk PlayPro — Rujukan Induk

Versi: 1.0 · Tarikh: 14 November 2026 · Diluluskan Owner

Dokumen ini menetapkan prinsip produk yang mesti diikuti oleh semua modul, aliran onboarding, API, pangkalan data dan UI PlayPro.

## 1. Tujuan produk

PlayPro ialah platform bola sepak akar umbi. Sistem mesti memudahkan orang menyertai bola sepak, membina profil, mengurus pasukan, menganjurkan pertandingan dan merekod aktiviti. Keselamatan ialah perlindungan yang senyap dan berkadar — bukan birokrasi yang menghalang aktiviti bola sepak.

## 2. Satu akaun, banyak peranan

- Satu individu menggunakan satu akaun PlayPro.
- Peranan ialah capability tambahan pada akaun yang sama: User, Player, Coach, Referee, Organizer, Club Owner/Manager dan peranan lain yang diluluskan.
- Menambah atau menukar peranan tidak mencipta akaun identiti baharu dan tidak meminta pengguna mengulang KYC.
- Maklumat profil khusus peranan (contoh: posisi pemain, lesen Coach, rekod pengadilan) kekal berasingan daripada identiti peribadi.

## 3. KYC individu — sekali untuk semua peranan

**Prinsip wajib: One Person, One KYC.**

- KYC mengesahkan identiti individu, bukan peranan.
- Seorang pengguna menghantar MyKad, MyKid atau pasport sekali sahaja. Rekod pengesahan itu dikongsi oleh semua peranan pada akaun yang sama.
- Status KYC tidak boleh dipecahkan kepada player KYC, coach KYC, club_owner KYC, organizer KYC atau referee KYC.
- KYC yang masih sah tidak boleh diminta semula apabila pengguna membuka profil Player, Coach, Referee, Organizer atau Club Owner.
- KYC mempunyai tempoh sah lima (5) tahun dari tarikh pengesahan. Selepas tamat tempoh, pengguna diminta mengemas kini pengesahan. Kemas kini awal hanya apabila dokumen tamat tempoh, identiti berubah, dokumen tidak sah, terdapat percanggahan material atau sebab keselamatan yang boleh dijelaskan.
- Menambah peranan, menyertai kelab, menyertai liga atau memasuki kejohanan bukan sebab untuk mengulang KYC.
- OCR ialah alat bantuan membaca dokumen, bukan proses berasingan yang perlu dilakukan berulang kali dan bukan keputusan kelulusan. Semakan manual hanya apabila bacaan tidak jelas atau terdapat percanggahan material.
- Data dan dokumen KYC disimpan secara peribadi, dienkripsi, diakses mengikut keperluan tugas dan direkodkan aksesnya. Ia tidak boleh muncul pada profil awam, kad pemain awam, carian awam atau respons API awam.
- Rekod pengesahan dan tarikh luput menjadi sumber kebenaran pusat. Semua modul mesti membaca rekod yang sama.

## 4. Bezakan identiti, kelayakan dan pengiktirafan

KYC individu menjawab **siapa orang ini**. Ia bukan pengganti kepada:

- Lesen dan akreditasi Coach/Referee;
- kelayakan atau kompetensi Organizer;
- pengiktirafan entiti kelab;
- keahlian dan keizinan pengurusan kelab;
- syarat umur, kategori, roster dan peraturan pertandingan.

Semakan ini boleh diperlukan apabila aktiviti memerlukannya, tetapi jangan label atau proses sebagai KYC individu kedua. Club Owner menggunakan KYC peribadi yang sama; kelab sebagai entiti boleh mempunyai proses pengiktirafan dokumen organisasinya sendiri.

## 5. Prinsip onboarding dan UI/UX

Semua modul mesti menggunakan corak onboarding yang seragam:

1. Log masuk / cipta satu akaun.
2. Lengkapkan profil asas yang minimum.
3. Pilih atau tambah peranan yang diperlukan.
4. Jika tindakan memerlukan identiti disahkan dan KYC belum sah, bawa pengguna ke satu halaman KYC pusat.
5. Jika KYC sudah sah, teruskan ke borang profil/peranan tanpa meminta dokumen lagi.
6. Minta hanya maklumat yang diperlukan untuk peranan atau tindakan itu.
7. Paparkan status, sebab sekatan dan tindakan seterusnya dengan bahasa mudah.

UI tidak boleh memaksa pengguna melompat antara borang yang mengulang maklumat sama. Butang, label, status, validasi, susun atur, mesej ralat dan navigasi onboarding mesti konsisten merentas Player, Coach, Club, Organizer dan Referee.

## 6. Prinsip data

- Satu rekod identiti KYC kanonik bagi setiap individu; semua peranan merujuk rekod yang sama.
- Jangan salin nombor MyKad/pasport ke jadual profil peranan.
- Simpan dokumen KYC dalam storan private; simpan hanya metadata minimum dan rujukan storan yang diperlukan.
- Simpan sejarah keputusan dan audit tanpa memaksa pengguna menghantar semula dokumen untuk setiap peranan.
- Tempoh sah pengesahan lima tahun tidak bermaksud dokumen boleh didedahkan atau disimpan tanpa kawalan. Jadual penyimpanan/pemadaman dokumen mesti mematuhi undang-undang perlindungan data yang terpakai dan polisi privasi PlayPro.
- Jangan cipta data ujian atau KYC palsu pada akaun sebenar.

## 7. Larangan reka bentuk

- Dilarang meminta KYC baharu hanya kerana pengguna menambah peranan.
- Dilarang menjadikan subject_type peranan sebagai identiti KYC yang berasingan.
- Dilarang menjalankan OCR berulang kali untuk dokumen yang sama tanpa sebab yang boleh dijelaskan.
- Dilarang menyekat fungsi bola sepak yang tidak memerlukan KYC.
- Dilarang mencampur KYC individu dengan lesen, akreditasi, pengiktirafan kelab, membership, registration, payment atau eligibility.
- Dilarang membina langkah onboarding, skrin, status atau borang berlainan tanpa sebab produk yang jelas.

## 8. Syarat penerimaan

Sistem hanya dianggap mematuhi prinsip ini apabila ujian membuktikan bahawa:
- seorang pengguna yang telah disahkan boleh mengaktifkan semua peranan tanpa muat naik KYC kedua;
- semua modul membaca status dan tarikh luput KYC kanonik yang sama;
- akaun tanpa KYC masih boleh menggunakan fungsi yang tidak memerlukan identiti disahkan;
- KYC tamat tempoh mencetuskan satu proses kemas kini pusat, bukan permohonan berasingan setiap peranan;
- data dokumen tidak boleh dibaca oleh pengguna lain atau dipaparkan pada profil awam;
- lesen/akreditasi dan pengiktirafan kelab masih boleh disemak secara berasingan tanpa meminta KYC individu baharu.