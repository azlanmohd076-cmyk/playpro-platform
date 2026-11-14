create or replace function public.mcp_set_admin_access(p_profile_id uuid,p_enabled boolean)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role text; v_old public.user_role;
begin
 select role::text into v_role from public.profiles where id=auth.uid() and is_active=true;
 if auth.uid() is null or v_role<>'developer' then raise exception 'Developer access required' using errcode='42501'; end if;
 if p_profile_id is null or p_profile_id=auth.uid() then raise exception 'Cannot change own access'; end if;
 select role into v_old from public.profiles where id=p_profile_id for update;
 if not found then raise exception 'User not found'; end if;
 if v_old='developer' then raise exception 'Developer role cannot be changed through Admin Access'; end if;
 if p_enabled then
  insert into private.mcp_admin_role_assignments(profile_id,previous_role,assigned_by,assigned_at,revoked_by,revoked_at)
  values(p_profile_id,v_old,auth.uid(),now(),null,null)
  on conflict(profile_id) do update set previous_role=excluded.previous_role,assigned_by=excluded.assigned_by,assigned_at=now(),revoked_by=null,revoked_at=null;
 else
  update private.mcp_admin_role_assignments set revoked_by=auth.uid(),revoked_at=now()
  where profile_id=p_profile_id and revoked_at is null;
 end if;
 insert into private.developer_editor_audit(actor_profile_id,entity,record_id,action,before_data,after_data)
 values(auth.uid(),'profiles',p_profile_id,'update',
  jsonb_build_object('role',v_old::text,'mcp_access',not p_enabled),
  jsonb_build_object('role',v_old::text,'mcp_access',p_enabled));
 return jsonb_build_object('ok',true,'role',v_old::text,'mcp_access',p_enabled);
end $$;
