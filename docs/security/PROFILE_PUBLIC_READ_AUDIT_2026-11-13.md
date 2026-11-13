# PlayPro — Audit Pendedahan Profil Awam
Tarikh pemeriksaan: 2026-11-13
Projek: Supabase `playpro2` (`muirhenvjruvfxenoaxm`)
Status: **P0 disahkan — belum ditutup**

## Ringkasan
Pemeriksaan metadata langsung mengesahkan jadual `public.profiles` mempunyai RLS aktif tetapi tidak dipaksa (FORCE RLS = false), peranan `anon` masih mempunyai hak `SELECT`, dan polisi permissive `profiles: public read` menggunakan `USING (true)`. Oleh sebab polisi permissive digabungkan dengan OR, polisi ini membenarkan bacaan baris profil tanpa pengesahan.

Jadual mengandungi medan peribadi termasuk `email`, `phone`, `ic_number`, `passport_number` dan `date_of_birth`. Tiada rekod pengguna sebenar dibaca semasa audit.

## Bukti yang diperoleh
- `profiles.relrowsecurity = true`; `relforcerowsecurity = false`.
- `has_table_privilege('anon','public.profiles','SELECT') = true`.
- Polisi `profiles: public read` ialah `PERMISSIVE SELECT TO public USING (true)`.
- `public_profiles` belum wujud.
- Polisi lain yang ditemui: developer delete, developer update any, insert own, update own non-role fields. Polisi SELECT own/developer belum wujud dalam snapshot semasa.
- Medan skema yang dikenal pasti: `email`, `phone`, `ic_number`, `passport_number`, `date_of_birth`, `full_name`, `role`, `avatar_url`, `is_active`, dan medan sokongan lain.

## Penilaian RPC yang ditandakan Security Advisor
Security Advisor menandakan tiga fungsi `SECURITY DEFINER` boleh dipanggil oleh `anon`:
1. `get_player_match_history(uuid, integer)`
2. `get_player_profile(uuid)`
3. `get_team_roster(uuid)`

Semakan definisi menunjukkan ketiga-tiganya menetapkan `search_path` kosong dan merujuk jadual dengan skema `public`. Fungsi profil mengehadkan hasil penuh kepada pemilik, follower yang diluluskan atau profil awam; profil private dipulangkan dalam bentuk terhad. Fungsi sejarah memulangkan statistik perlawanan rasmi pemain aktif. Fungsi roster menyemak status kelab disahkan atau pengurus kelab. Ini ialah fungsi awam yang perlu ujian kebenaran khusus, bukan bukti automatik bahawa semuanya patut ditutup. Jangan revoke secara pukal tanpa ujian kerana ia boleh memecahkan profil awam, sejarah dan roster.

## Pelan pembaikan P0 yang dicadangkan
1. Inventori semua pemanggil `profiles` dan asingkan bacaan profil sendiri daripada carian profil awam.
2. Untuk jadual `profiles`: buang polisi `profiles: public read`; tarik hak SELECT terus daripada `anon`; pastikan pengguna `authenticated` hanya boleh membaca rekod sendiri dan peranan developer mengikut fungsi autoriti yang disahkan.
3. Jika carian awam benar-benar diperlukan, sediakan permukaan awam berasingan yang hanya mengeluarkan medan yang dibenarkan. Jangan gunakan semula jadual `profiles` untuk tujuan ini.
4. Uji melalui REST tanpa login, akaun pengguna A, akaun pengguna B dan akaun developer. Pastikan A tidak boleh membaca B; A masih boleh membaca rekod sendiri; aliran login, pendaftaran dan KYC tidak rosak.
5. Semak semula Security Advisor dan jalankan ujian regresi selepas pembaikan.

## Kebergantungan / sekatan pelaksanaan
- Dokumen tadbir urus projek menetapkan tiada DDL produksi sebelum eksport kebenaran produksi WO-08, rekonsiliasi baseline, dan gerbang Fasa 2C.
- Oleh itu, audit ini **belum menjalankan sebarang DDL**, tidak menukar polisi produksi, tidak mengubah data dan tidak mendakwa kebocoran telah ditutup.
- Fail SQL P1 lama dalam `database/` tidak boleh dijalankan terus: ia turut menyentuh jadual dan fungsi lain, dan perlu disemak terhadap skema langsung serta pengguna kod dahulu.
- Tindakan seterusnya: lengkapkan eksport baca-sahaja WO-08 dan semakan Fasa 2C; sediakan hotfix paling kecil dengan ujian dan pelan rollback; kemudian laksanakan hanya melalui work order produksi yang diluluskan Owner.

## Skop landing page
Landing page dibina dalam `public/landing.html`. Root `/` diarahkan ke landing page; `/app` kekal sebagai laluan aplikasi/log masuk. Pengguna yang mempunyai sesi aktif di landing page diarahkan ke `/index.html`. Tiada laluan penjaga bawah umur dipaparkan sebagai fungsi tersedia.
