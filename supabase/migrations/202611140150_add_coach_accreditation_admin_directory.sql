create or replace function public.get_coach_accreditation_admin_list()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid := (select auth.uid()); v_rows jsonb;
begin
 if v_uid is null or (select public.get_my_role()) is distinct from 'developer'::public.user_role then
  raise exception 'FORBIDDEN: Developer PlayPro only';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'profile_id',p.id,'full_name',p.full_name,'email',p.email,'role',p.role::text,'is_active',p.is_active,
  'accreditation_level',ca.accreditation_level,'accreditation_status',ca.status,'expires_at',ca.expires_at
 ) order by p.full_name),'[]'::jsonb) into v_rows
 from public.profiles p left join public.coach_accreditations ca on ca.coach_profile_id=p.id
 where p.is_active=true;
 return jsonb_build_object('ok',true,'profiles',v_rows);
end $$;
revoke all on function public.get_coach_accreditation_admin_list() from public,anon,authenticated;
grant execute on function public.get_coach_accreditation_admin_list() to authenticated;