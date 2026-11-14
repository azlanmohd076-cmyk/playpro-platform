begin;
drop policy if exists "coaches: public read" on public.coaches;
drop policy if exists coaches_owner_or_club_admin_read on public.coaches;
create policy coaches_owner_or_club_admin_read on public.coaches for select to authenticated
using(profile_id=(select auth.uid()) or (select public.get_my_role())='developer'::public.user_role or (club_id is not null and public.is_club_admin(club_id)));
revoke all on public.coaches from anon,authenticated;
grant select(id,full_name,license,club_id,photo_url,profile_id,is_active,coach_code,preferred_name,display_name_mode,profile_visibility,coaching_role,preferred_formation,preferred_style,coaching_specialties,license_type,license_status,verification_status,disciplinary_status,card_state,playpro_license_level) on public.coaches to authenticated;
grant update(is_active) on public.coaches to authenticated;
drop policy if exists "coaches: club admin insert" on public.coaches;
create or replace function public.get_my_coach_profile() returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare v_uid uuid := (select auth.uid()); v_profile jsonb;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 select to_jsonb(c) into v_profile from public.coaches c where c.profile_id=v_uid limit 1;
 return v_profile;
end;$function$;
create or replace function public.add_club_roster_coach(p_club_id uuid,p_full_name text,p_license text default null) returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_uid uuid := (select auth.uid()); v_coach public.coaches%rowtype;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if p_club_id is null or not ((select public.is_club_admin(p_club_id)) or (select public.get_my_role())='developer'::public.user_role) then raise exception 'CLUB_ADMIN_REQUIRED' using errcode='42501'; end if;
 if p_full_name is null or length(btrim(p_full_name))<2 then raise exception 'COACH_NAME_REQUIRED' using errcode='22023'; end if;
 insert into public.coaches(full_name,license,club_id,coach_code,is_active)
 values(btrim(p_full_name),nullif(btrim(p_license),''),p_club_id,'COA-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),true)
 returning * into v_coach;
 return jsonb_build_object('id',v_coach.id,'full_name',v_coach.full_name,'license',v_coach.license,'profile_id',v_coach.profile_id,'is_active',v_coach.is_active,'photo_url',v_coach.photo_url,'verification_status',v_coach.verification_status,'coach_code',v_coach.coach_code);
end;$function$;
revoke all on function public.get_my_coach_profile() from public;
grant execute on function public.get_my_coach_profile() to authenticated;
revoke all on function public.add_club_roster_coach(uuid,text,text) from public;
grant execute on function public.add_club_roster_coach(uuid,text,text) to authenticated;
drop policy if exists "coach_assessments: public read" on public.coach_assessments;
drop policy if exists "coach_assessments: assessor insert" on public.coach_assessments;
drop policy if exists "coach_assessments: assessor or developer update" on public.coach_assessments;
create policy coach_assessments_owner_assessor_developer_read on public.coach_assessments for select to authenticated
using(assessor_id=(select auth.uid()) or (select public.get_my_role())='developer'::public.user_role or exists(select 1 from public.coaches c where c.id=coach_id and c.profile_id=(select auth.uid())));
revoke all on public.coach_assessments from anon,authenticated;
grant select on public.coach_assessments to authenticated;
drop policy if exists coach_disciplinary_public_read on public.coach_disciplinary_records;
drop policy if exists coach_disciplinary_owner_developer_read on public.coach_disciplinary_records;
create policy coach_disciplinary_owner_developer_read on public.coach_disciplinary_records for select to authenticated
using((select public.get_my_role())='developer'::public.user_role or exists(select 1 from public.coaches c where c.id=coach_id and c.profile_id=(select auth.uid())));
revoke all on public.coach_disciplinary_records from anon,authenticated;
grant select on public.coach_disciplinary_records to authenticated;
commit;