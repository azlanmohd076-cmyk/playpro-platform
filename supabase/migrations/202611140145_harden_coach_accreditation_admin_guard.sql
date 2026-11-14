-- Ensure a missing/null role never passes the Developer authorization guard.
create or replace function public.set_coach_accreditation(
 p_coach_profile_id uuid,p_level smallint,p_status text default 'active',
 p_expires_at timestamptz default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_admin uuid := (select auth.uid());
begin
 if v_admin is null or (select public.get_my_role()) is distinct from 'developer'::public.user_role then
  raise exception 'FORBIDDEN: only PlayPro Developer can manage coach accreditation';
 end if;
 if p_status not in ('active','suspended','revoked') then raise exception 'Invalid accreditation status'; end if;
 if p_status='active' and (p_level is null or p_level not between 1 and 7) then raise exception 'Accreditation level must be 1–7'; end if;
 if not exists(select 1 from public.profiles where id=p_coach_profile_id and is_active=true) then raise exception 'Coach profile not found or inactive'; end if;
 update public.profiles set role='technical_assessor'::public.user_role,updated_at=now() where id=p_coach_profile_id;
 insert into public.coach_accreditations(coach_profile_id,accreditation_level,status,accredited_at,expires_at,accredited_by,notes,updated_at)
 values(p_coach_profile_id,coalesce(p_level,1),p_status,now(),p_expires_at,v_admin,nullif(btrim(p_notes),''),now())
 on conflict(coach_profile_id) do update set accreditation_level=excluded.accreditation_level,status=excluded.status,
  accredited_at=case when excluded.status='active' then now() else public.coach_accreditations.accredited_at end,
  expires_at=excluded.expires_at,accredited_by=excluded.accredited_by,notes=excluded.notes,updated_at=now();
 return jsonb_build_object('ok',true,'coach_profile_id',p_coach_profile_id,'level',p_level,'status',p_status);
end $$;
revoke all on function public.set_coach_accreditation(uuid,smallint,text,timestamptz,text) from public,anon,authenticated;
grant execute on function public.set_coach_accreditation(uuid,smallint,text,timestamptz,text) to authenticated;