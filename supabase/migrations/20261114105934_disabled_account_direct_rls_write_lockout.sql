do $block$
declare
  r record;
  v_using text;
  v_check text;
  v_sql text;
  v_changed integer := 0;
begin
  for r in
    select schemaname, tablename, policyname, cmd, roles, qual, with_check
    from pg_policies
    where schemaname='public'
      and cmd in ('INSERT','UPDATE','DELETE','ALL')
      and (roles::text like '%authenticated%' or roles::text like '%public%')
      and coalesce(qual,'') not ilike '%playpro_account_is_active%'
      and coalesce(with_check,'') not ilike '%playpro_account_is_active%'
      and coalesce(qual,'') not ilike '%playpro_is_club_manager%'
      and coalesce(with_check,'') not ilike '%playpro_is_club_manager%'
      and not (tablename='profiles' and policyname='profiles: insert own')
  loop
    v_using := coalesce(r.qual,'true');
    v_check := coalesce(r.with_check,r.qual,'true');
    if r.cmd='INSERT' then
      v_sql := format(
        'alter policy %I on %I.%I with check ((%s) and public.playpro_account_is_active())',
        r.policyname,r.schemaname,r.tablename,v_check
      );
    elsif r.cmd='DELETE' then
      v_sql := format(
        'alter policy %I on %I.%I using ((%s) and public.playpro_account_is_active())',
        r.policyname,r.schemaname,r.tablename,v_using
      );
    else
      v_sql := format(
        'alter policy %I on %I.%I using ((%s) and public.playpro_account_is_active()) with check ((%s) and public.playpro_account_is_active())',
        r.policyname,r.schemaname,r.tablename,v_using,v_check
      );
    end if;
    execute v_sql;
    v_changed := v_changed + 1;
  end loop;
  raise notice 'Added active-account RLS guard to % public mutation policies',v_changed;
end;
$block$;

revoke execute on function public.playpro_add_role(text) from anon, public;
grant execute on function public.playpro_add_role(text) to authenticated, service_role;
