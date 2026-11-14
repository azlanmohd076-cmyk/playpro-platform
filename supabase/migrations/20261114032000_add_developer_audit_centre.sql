create or replace function public.developer_editor_audit_list(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_rows jsonb;
  v_limit integer := least(greatest(coalesce(p_limit,50),1),100);
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'developer'::public.user_role
      and p.is_active = true
  ) then
    raise exception 'Developer access required';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.changed_at desc), '[]'::jsonb)
    into v_rows
  from (
    select
      a.id,
      a.entity,
      a.record_id,
      a.action,
      a.changed_at,
      a.actor_profile_id,
      coalesce(nullif(p.full_name,''), p.email, 'Developer') as actor_name,
      case
        when a.action = 'insert' then coalesce(
          (select jsonb_agg(k) from jsonb_object_keys(coalesce(a.after_data,'{}'::jsonb)) as k),
          '[]'::jsonb
        )
        else coalesce(
          (select jsonb_agg(k)
           from jsonb_object_keys(coalesce(a.after_data,'{}'::jsonb)) as k
           where a.before_data -> k is distinct from a.after_data -> k),
          '[]'::jsonb
        )
      end as changed_fields,
      a.before_data,
      a.after_data
    from private.developer_editor_audit a
    left join public.profiles p on p.id = a.actor_profile_id
    order by a.changed_at desc
    limit v_limit
  ) x;

  return v_rows;
end;
$function$;

revoke all on function public.developer_editor_audit_list(integer) from public;
revoke all on function public.developer_editor_audit_list(integer) from anon;
grant execute on function public.developer_editor_audit_list(integer) to authenticated;
