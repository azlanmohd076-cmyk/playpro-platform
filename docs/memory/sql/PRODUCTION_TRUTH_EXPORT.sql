-- ============================================================================
--  PLAYPRO — PRODUCTION TRUTH EXPORT (WO-08 / DEC-022)
--  READ-ONLY: HANYA SELECT. Tiada INSERT/UPDATE/DELETE/DDL. Selamat ditempel
--  dan dijalankan di Supabase -> SQL Editor.
--
--  CARA GUNA (Owner, ±12 minit):
--   1. Supabase -> projek `playpro2` (produksi) -> SQL Editor -> New query.
--   2. Jalankan **satu blok satu masa** (blok berlabel `-- qNN`). Untuk setiap
--      hasil: butang "Download results" -> CSV.
--   3. Namakan fail ikut nombor blok (q01.csv, q02.csv, ... q22.csv) dan
--      letakkan dalam folder:  docs/memory/PRODUCTION_TRUTH_<tarikh>/
--   4. Yang paling penting untuk baseline: **q20** (DDL jadual) dan **q21**
--      (DDL fungsi). Kalau CSV menyusahkan, tampal terus output dua blok itu
--      ke Owner dan saya (CTO) yang susun.
--   5. ULANGI untuk projek `playpro` (legacy) supaya keputusan "beku / padam /
--      RLS disabled" dibuat atas bukti, bukan ingatan.
--   6. Maklumkan CTO. CTO rekonsiliasi menjadi supabase/migrations/
--      0001_baseline.sql **DI BRANCH** — CTO TIDAK menjalankan apa-apa DDL.
--
--  Kenapa fail ini wujud: satu-satunya cara menukar angka "DILAPORKAN" dalam
--  docs/memory/STATE.md menjadi "DISAHKAN". Skema produksi TIDAK tercermin
--  dalam database/*.sql (legacy) mahupun docs/ARCHITECTURE.md (rekaan) —
--  lihat docs/memory/EVIDENCE.md §E.
-- ============================================================================

-- q00 — identiti sambungan (bukti export ini dari projek yang mana)
select current_database()                     as db,
       current_setting('server_version')       as pg_version,
       now() at time zone 'utc'                as utc_now,
       current_user                            as run_as;

-- q01 — bilangan objek ikut skema
select table_schema, table_type, count(*) as n
from information_schema.tables
where table_schema in ('public','auth','storage','realtime','extensions')
group by 1, 2
order by 1, 2;

-- q02 — senarai jadual public + status RLS
select c.relname                as table_name,
       c.relrowsecurity         as rls_on,
       c.relforcerowsecurity    as rls_forced,
       c.reloptions::text       as reloptions,
       pg_get_userbyid(c.relowner) as owner
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','p')
order by c.relname;

-- q02b — JELAS: jadual yang RLS-nya MATI (calon pendedahan langsung)
select c.relname as table_rls_mati
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','p') and not c.relrowsecurity
order by 1;

-- q03 — lajur setiap jadual (nama, jenis, nullability, default)
select table_schema, table_name, ordinal_position, column_name, data_type,
       coalesce(character_maximum_length::text, numeric_precision::text, '') as len_or_prec,
       is_nullable,
       coalesce(column_default, '') as column_default
from information_schema.columns
where table_schema in ('public','auth')
order by table_schema, table_name, ordinal_position;

-- q03b — PENTING UNTUK WO-09: adakah `profiles.identification_number` wujud?
--         (inilah punca pendaftaran pemain rosak — bukti, bukan andaian)
select table_name, ordinal_position, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('profiles','players','verification_cases')
order by table_name, ordinal_position;

-- q04 — kekangan (PK / FK / UNIQUE / CHECK)
select c.relname as table_name,
       con.conname as constraint_name,
       con.contype as kind,
       pg_get_constraintdef(con.oid) as definition
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
order by c.relname, con.contype, con.conname;

-- q05 — semua index + definisinya
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
order by tablename, indexname;

-- q05b — lajur kiri setiap foreign key. (CTO akan mengira "FK tanpa index"
--         secara luaran daripada senarai index di atas; itu lebih selamat
--         daripada query pintar yang mungkin ralat pada versi Postgres Supabase.)
select cl.relname as table_name,
       con.conname as fk_name,
       (select string_agg(a.attname::text, ',' order by t.ord)
          from unnest(con.conkey) with ordinality as t(attnum, ord)
          join pg_attribute a on a.attrelid = con.conrelid and a.attnum = t.attnum) as fk_columns,
       (select c2.relname from pg_class c2 where c2.oid = con.confrelid) as refs_table
from pg_constraint con
join pg_class cl on cl.oid = con.conrelid
join pg_namespace n on n.oid = cl.relnamespace
where n.nspname = 'public' and con.contype = 'f'
order by 1, 2;

-- q05c — lajur setiap index (ikut tertib, untuk padankan dengan q05b)
select i.relname as table_name,
       ix.indexrelid::regclass as index_name,
       string_agg(att.attname::text, ',' order by g.n) as index_columns
from pg_index ix
join pg_class i on i.oid = ix.indrelid
join pg_namespace n on n.oid = i.relnamespace
cross join lateral generate_series(1, ix.indnatts) as g(n)
join pg_attribute att on att.attrelid = ix.indrelid and att.attnum = ix.indkey[g.n - 1]
where n.nspname = 'public'
group by 1, 2
order by 1, 2;

-- q06 — VIEWS + status security_invoker + definisi (Fasa-3 kata 5 view sudah
--         ditukar security_invoker=true -> reloptions akan membuktikannya)
select c.relname as view_name,
       c.reloptions::text as reloptions,
       pg_get_viewdef(c.oid, true) as view_definition
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'v'
order by 1;

-- q07 — SIAPA BOLEH MEMANGGIL APA (audit: ~13 SECURITY DEFINER boleh
--         dipanggil authenticated; dan adakah search_path di-pin?)
select p.proname as function_name,
       pg_get_userbyid(p.proowner) as owner,
       p.prosecdef as security_definer,
       p.provolatile as volatility,
       coalesce(array_to_string(p.proconfig, ','), '(tiada search_path pinned)') as config,
       has_function_privilege('anonymous', p.oid, 'execute') as anon_execute,
       has_function_privilege('authenticated', p.oid, 'execute') as auth_execute,
       has_function_privilege('service_role', p.oid, 'execute') as service_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.prosecdef desc, p.proname;

-- q08 — HAK TULIS pada jadual (anon boleh INSERT/UPDATE/DELETE?)
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon','authenticated','service_role','postgres')
order by table_name, grantee, privilege_type;

-- q09 — TRIGGER
select cl.relname as table_name,
       tg.tgname as trigger_name,
       case when tg.tginsert  then 'I' else '' end ||
       case when tg.tgupdate  then 'U' else '' end ||
       case when tg.tgdelete  then 'D' else '' end ||
       case when tg.tgtruncate then 'T' else '' end as events,
       pg_get_triggerdef(tg.oid) as definition
from pg_trigger tg
join pg_class cl on cl.oid = tg.tgrelid
join pg_namespace n on n.oid = cl.relnamespace
where n.nspname = 'public' and not tg.tgisinternal
order by cl.relname, tg.tgname;

-- q10 — RLS POLICIES (57 dilaporkan) + ungkapan penuh
select tablename, policyname, permissive, cmd,
       roles::text as roles,
       coalesce(qual, '(tiada)') as using_expr,
       coalesce(with_check, '(tiada)') as check_expr
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- q10b — jadual yang RLS-on TETAPI 0 policy (contoh audit: `referees`)
select c.relname as table_name,
       c.relrowsecurity as rls_on,
       (select count(*) from pg_policies p
         where p.schemaname = 'public' and p.tablename = c.relname) as n_policies
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','p')
  and (c.relrowsecurity
       or not exists (select 1 from pg_policies p
                       where p.schemaname = 'public' and p.tablename = c.relname))
order by n_policies, c.relname;

-- q11 — ENUM (termasuk `match_state` yang Fasa-3 kata ditambah)
select t.typname as enum_name,
       string_agg(e.enumlabel, ' -> ' order by e.enumsortorder) as labels
from pg_type t
join pg_enum e on e.enumtypid = t.oid
join pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'public'
group by t.typname
order by t.typname;

-- q12 — OBJEK FASA-3: WUJUD ATAU TIDAK? (semua ini 0 rujukan dalam Git)
select table_name, 'table' as kind
from information_schema.tables
where table_schema = 'public'
  and table_name in ('match_events','match_participants','match_playing_time',
                     'match_admin_assignments','fixtures','player_assessments',
                     'competition_player_registrations','capabilities')
union all
select table_name || '.' || column_name, 'column'
from information_schema.columns
where table_schema = 'public'
  and column_name in ('match_state','identification_number','sequence')
order by 2, 1;

-- q13 — anggaran bilangan row (SELAMAT: tak pernah ralat walau jadual tiada)
select relname as table_name, n_live_tup as approx_rows, last_vacuum, last_analyze
from pg_stat_user_tables
order by relname;

-- q13b — kiraan EKSAK untuk dua jadual teras sahaja (jika jadual lain tiada,
--          query panjang akan ralat — sebab itu kita hanya uji dua ini)
select 'profiles' as table_name, count(*) as n from public.profiles
union all
select 'players', count(*) from public.players
order by 1;

-- q14 — KIRAAN OBJEK (checksum kelengkapan). Bandingkan dengan
--         docs/PLAYPRO_SYSTEM_CONTRACT.md: 17→~21 jadual, 5 view, 14 fungsi,
--         16 trigger, 57 policy.
select 'tables'      as kind, count(*) as n from information_schema.tables
  where table_schema = 'public' and table_type = 'BASE TABLE'
union all select 'views', count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'v'
union all select 'functions', count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
union all select 'triggers', count(*) from pg_trigger tg join pg_class c on c.oid = tg.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and not tg.tgisinternal
union all select 'policies', count(*) from pg_policies where schemaname = 'public'
union all select 'indexes', count(*) from pg_indexes where schemaname = 'public'
union all select 'constraints', count(*) from pg_constraint con join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'
order by 1;

-- q15 — MIGRATION YANG TERPAKAI. Jika ralat "relation schema_migrations does
--         not exist" -> ITULAH JAWAPANNYA: projek ini tiada tracking migration.
select version, name, inserted_at
from public.schema_migrations
order by version;

-- q16 — SAIZ AUTENTIKASI (tanpa PII; JANGAN sesekali select email/meta data)
select count(*) as total_auth_users,
       count(*) filter (where email_confirmed_at is not null) as confirmed
from auth.users;

-- q17 — polisi PERMISSIVE berganda pada jadual+command sama (18 dilaporkan)
select tablename, cmd, count(*) as n_policies,
       string_agg(policyname, ', ') as policies
from pg_policies
where schemaname = 'public' and permissive = 'PERMISSIVE'
group by tablename, cmd
having count(*) > 1
order by count(*) desc, tablename;

-- q18 — index yang nampak tidak digunakan (statistik boleh jadi sifar lepas restart)
select schemaname, relname as table_name, indexrelname as index_name, idx_scan
from pg_stat_user_indexes
where schemaname = 'public'
order by idx_scan nulls last, relname
limit 80;

-- ============================================================================
-- q20 — BLOK TERPENTING: jana semula DDL jadual. Output inilah yang CTO pakai
--         untuk membina supabase/migrations/0001_baseline.sql
-- ============================================================================
select c.relname as table_name,
       'create table public.' || c.relname || E' (\n'
       || string_agg(
            '  ' || quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod)
            || case when a.attnotnull then ' not null' else '' end
            || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), ''),
            E',\n' order by a.attnum)
       || E'\n);' as ddl
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
where c.relkind in ('r','p')
group by c.relname
order by c.relname;

-- q21 — DDL penuh setiap fungsi public (termasuk body + signature)
select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.prosecdef as security_definer,
       pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.proname;

-- q22 — LOMPATAN KHAS: fungsi yang terlibat defect yang direkod (WO-09, WO-10,
--         Fasa-3). Kalau mana-mana tiada -> itu juga jawapan, catatkan.
select p.proname as function_name, pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('auto_suspend_on_red_card','register_my_player',
                    'ensure_profile_after_signup','start_match','end_match',
                    'record_match_event','void_match_event','finalize_match')
order by p.proname;

-- ============================================================================
--  SELESAI. Simpan CSV dalam docs/memory/PRODUCTION_TRUTH_<tarikh>/ dan
--  maklumkan CTO. JANGAN commit apa-apa yang mengandungi emel/token/nombor
--  dokumen orang sebenar.
-- ============================================================================
