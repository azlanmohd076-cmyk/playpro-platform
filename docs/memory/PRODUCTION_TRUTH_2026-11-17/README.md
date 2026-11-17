# WO-08 Production Truth Export — 2026-11-17

Read-only export captured from both Supabase projects and committed on branch `chore/wo08-production-truth-export-20261117`.

## Source projects

| Project | Ref | PostgreSQL | Public tables | Views | Functions | Triggers | Policies | Auth users |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| playpro2 (target) | `muirhenvjruvfxenoaxm` | 17.6 | 53 | 7 | 125 | 24 | 113 | 9 |
| playpro (legacy) | `vzuuespavlsqtdhudxzu` | 17.4 | 15 | 0 | 2 | 0 | 7 | 0 |

## Export files

- `playpro2-ddl.json`: q20 table DDL and q21 full public function definitions.
- `playpro-legacy-ddl.json`: q20 and q21 for the legacy project.
- `playpro2-security-structure.json`: q04 constraints, q05 indexes, q06 views, q07 function execute/security metadata, q09 triggers, q10 complete RLS policy definitions, q11 enums.
- `playpro-legacy-security-structure.json`: same export for legacy.
- `playpro2-catalog-audit.json` and `playpro-legacy-catalog-audit.json`: q00, q08 grants, q12 object checks, q13 row estimates, q14 object counts, q16 auth counts, q17 permissive-policy overlap, q18 index statistics.
- `playpro2-remaining-catalog.json` and `playpro-legacy-remaining-catalog.json`: q01 object counts, q02b RLS-disabled tables, q03 columns, q03b relevant identity/player columns, q05b/q05c FK/index mapping, q10b RLS/policy coverage, q13b exact profile/player counts where available, q15 migration-table query result.
- `playpro2-migration-source-records.json`: read-only copy of the four original Phase-3 migration statements from `supabase_migrations.schema_migrations`.

## Notes

- No INSERT, UPDATE, DELETE, DDL, or migration was executed against either database.
- The legacy project is not structurally compatible with the target: it has no `public.profiles`, no auth users, only 15 public tables, and a legacy `users` model. It is evidence for historical reconciliation only; it is not a schema source to merge into playpro2.
- The `public.schema_migrations` query in q15 is not authoritative for migration history; Supabase's migration listing and `supabase_migrations.schema_migrations` are the authoritative sources. The four original Phase-3 SQL statements are preserved separately.
- The exact q13b profiles/players count is available for playpro2; it cannot run on legacy because `public.profiles` does not exist.
- This completes the read-only evidence collection needed for WO-08. It does **not** itself create or apply `0001_baseline.sql`, satisfy the seven Phase-2C implementation gates, or authorize production DDL.
