-- Owner-scoped read API for the multi-role registry.
-- Direct table access remains governed by RLS; this RPC exposes only the caller's own role links.

create or replace function public.get_my_role_profiles()
returns table (
  role_code text,
  subject_id uuid,
  is_active boolean
)
language sql
stable
security definer
set search_path = ''
as $function$
  select r.role_code, r.subject_id, r.is_active
  from public.profile_role_profiles r
  where r.profile_id = auth.uid()
  order by r.created_at asc, r.role_code asc;
$function$;

revoke all on function public.get_my_role_profiles() from public, anon;
grant execute on function public.get_my_role_profiles() to authenticated;
