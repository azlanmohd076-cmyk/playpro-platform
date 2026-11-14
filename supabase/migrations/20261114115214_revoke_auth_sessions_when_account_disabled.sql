create or replace function public.playpro_handle_account_status_change()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_roles text[] := '{}';
  v_revoked_refresh_tokens bigint := 0;
  v_revoked_sessions bigint := 0;
begin
  if old.is_active is true and new.is_active is false then
    select coalesce(array_agg(rp.role_code order by rp.role_code),'{}'::text[])
      into v_roles from public.profile_role_profiles rp
      where rp.profile_id=new.id and rp.is_active is true;

    update public.profile_role_profiles set is_active=false,updated_at=now()
      where profile_id=new.id and is_active is true;

    update auth.refresh_tokens set revoked=true,updated_at=now()
      where user_id=new.id::text and coalesce(revoked,false)=false;
    get diagnostics v_revoked_refresh_tokens = row_count;

    delete from auth.sessions where user_id=new.id;
    get diagnostics v_revoked_sessions = row_count;

    insert into private.account_security_audit(
      actor_profile_id,subject_profile_id,event_type,role_codes,details
    ) values (
      auth.uid(),new.id,'account_deactivated',v_roles,
      jsonb_build_object('account_is_active',false,
        'role_capabilities_revoked',cardinality(v_roles),
        'refresh_tokens_revoked',v_revoked_refresh_tokens,
        'auth_sessions_deleted',v_revoked_sessions,
        'access_jwt_note','Existing signed access JWTs remain valid until expiry; database active-account guards deny protected operations.')
    );
  elsif old.is_active is false and new.is_active is true then
    insert into private.account_security_audit(
      actor_profile_id,subject_profile_id,event_type,details
    ) values (
      auth.uid(),new.id,'account_reactivated',
      jsonb_build_object('account_is_active',true,'role_restore_required',true,'new_login_required',true)
    );
  end if;
  return new;
end;
$function$;

revoke execute on function public.playpro_handle_account_status_change()
from public,anon,authenticated;
