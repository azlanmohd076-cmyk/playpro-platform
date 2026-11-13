-- PlayPro: public player directory RPC
-- Applied to production project playpro2 on 2026-11-13.
-- Exposes only active profiles explicitly marked public, and only non-sensitive
-- directory fields. Authenticated users only; direct SELECT on players remains
-- owner-scoped under the existing RLS policy.

create or replace function public.get_public_player_directory(
  p_search text default null,
  p_limit integer default 50
)
returns table (
  player_id uuid,
  display_name text,
  photo_url text,
  player_position text,
  club_name text,
  verification_status text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    p.id,
    case
      when p.display_name_mode = 'legal' then p.full_name
      else coalesce(nullif(btrim(p.preferred_name), ''), p.full_name)
    end,
    p.photo_url,
    p.position::text,
    c.name,
    p.verification_status
  from public.players p
  left join public.clubs c on c.id = p.club_id
  where (select auth.uid()) is not null
    and p.is_active is true
    and p.profile_visibility = 'public'
    and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or coalesce(p.preferred_name, '') ilike '%' || btrim(p_search) || '%'
      or coalesce(p.full_name, '') ilike '%' || btrim(p_search) || '%'
    )
  order by
    case when p.display_name_mode = 'legal'
      then p.full_name else coalesce(nullif(btrim(p.preferred_name), ''), p.full_name) end asc,
    p.created_at asc
  limit least(greatest(coalesce(p_limit, 50), 1), 50);
$function$;

revoke all on function public.get_public_player_directory(text, integer) from public;
revoke all on function public.get_public_player_directory(text, integer) from anon;
grant execute on function public.get_public_player_directory(text, integer) to authenticated;
