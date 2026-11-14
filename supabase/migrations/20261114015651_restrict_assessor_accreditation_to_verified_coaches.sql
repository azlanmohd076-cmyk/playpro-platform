create or replace function public.set_coach_accreditation(
 p_coach_profile_id uuid,p_level smallint,p_status text default 'active',
 p_expires_at timestamptz default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_admin uuid := (select auth.uid());
begin
 if v_admin is null or (select public.get_my_role()) is distinct from 'developer'::public.user_role then
  raise exception 'FORBIDDEN: hanya Developer PlayPro boleh mengurus akreditasi coach' using errcode='42501';
 end if;
 if p_coach_profile_id is null then raise exception 'COACH_PROFILE_REQUIRED' using errcode='22023'; end if;
 if p_status is null or p_status not in ('active','suspended','revoked') then
  raise exception 'Status akreditasi tidak sah' using errcode='22023';
 end if;
 if p_status='active' and (p_level is null or p_level not between 1 and 7) then
  raise exception 'Tahap akreditasi mesti antara Level 1 hingga 7' using errcode='22023';
 end if;
 if not exists (
  select 1 from public.profiles p join public.coaches c on c.profile_id=p.id
  where p.id=p_coach_profile_id and p.is_active=true and c.is_active=true
    and c.verification_status='verified' and c.kyc_verified_at is not null
 ) then
  raise exception 'COACH_KYC_REQUIRED: hanya profil Coach aktif yang telah disahkan KYC boleh ditauliahkan' using errcode='42501';
 end if;
 update public.profiles set role='technical_assessor'::public.user_role,updated_at=now() where id=p_coach_profile_id;
 insert into public.coach_accreditations(coach_profile_id,accreditation_level,status,accredited_at,expires_at,accredited_by,notes,updated_at)
 values(p_coach_profile_id,coalesce(p_level,1),p_status,now(),p_expires_at,v_admin,nullif(btrim(p_notes),''),now())
 on conflict(coach_profile_id) do update set accreditation_level=excluded.accreditation_level,status=excluded.status,
 accredited_at=case when excluded.status='active' then now() else public.coach_accreditations.accredited_at end,
 expires_at=excluded.expires_at,accredited_by=excluded.accredited_by,notes=excluded.notes,updated_at=now();
 return jsonb_build_object('ok',true,'coach_profile_id',p_coach_profile_id,'level',p_level,'status',p_status);
end;$function$;

create or replace function public.get_coach_accreditation_admin_list()
returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_uid uuid := (select auth.uid()); v_rows jsonb;
begin
 if v_uid is null or (select public.get_my_role()) is distinct from 'developer'::public.user_role then
  raise exception 'FORBIDDEN: Developer PlayPro only' using errcode='42501';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'profile_id',p.id,
  'full_name',case when c.preferred_name is not null and btrim(c.preferred_name)<>'' then c.preferred_name else c.full_name end,
  'email',p.email,'role',p.role::text,'is_active',p.is_active,'coach_id',c.id,
  'coach_code',c.coach_code,'coaching_role',c.coaching_role,'license_type',c.license_type,
  'accreditation_level',ca.accreditation_level,'accreditation_status',ca.status,'expires_at',ca.expires_at
 ) order by c.full_name),'[]'::jsonb) into v_rows
 from public.profiles p join public.coaches c on c.profile_id=p.id
 left join public.coach_accreditations ca on ca.coach_profile_id=p.id
 where p.is_active=true and c.is_active=true
  and c.verification_status='verified' and c.kyc_verified_at is not null;
 return jsonb_build_object('ok',true,'profiles',v_rows);
end;$function$;

revoke all on function public.set_coach_accreditation(uuid,smallint,text,timestamptz,text) from public;
grant execute on function public.set_coach_accreditation(uuid,smallint,text,timestamptz,text) to authenticated;
revoke all on function public.get_coach_accreditation_admin_list() from public;
grant execute on function public.get_coach_accreditation_admin_list() to authenticated;
