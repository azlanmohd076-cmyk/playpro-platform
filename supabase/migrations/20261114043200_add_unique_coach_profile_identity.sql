-- One authenticated identity may own at most one Coach profile.
-- PostgreSQL unique indexes allow multiple NULL values, preserving unlinked demo rows.
create unique index if not exists coaches_profile_id_uq
  on public.coaches (profile_id);
