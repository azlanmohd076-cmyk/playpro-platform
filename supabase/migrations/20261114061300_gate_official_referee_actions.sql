create or replace function public.create_referee_profile(p_pitch_nickname text default null,p_license_type text default null,p_coverage_area text default null,p_phone text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid();v_id uuid;v_name text;v_dob date;v_nationality text;v_code text;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select id into v_id from public.referees where user_id=v_uid limit 1;
 if v_id is null then
  select coalesce(p.full_name,'PlayPro Referee'),p.date_of_birth,coalesce(p.nationality,'Malaysian') into v_name,v_dob,v_nationality from public.profiles p where p.id=v_uid;
  v_code:='PP-REF-'||lpad(nextval('public.referee_code_seq')::text,6,'0');
  insert into public.referees(user_id,full_name,pitch_nickname,license_type,coverage_area,nationality,date_of_birth,phone,referee_code,verification_status,profile_completed_at)
  values(v_uid,v_name,p_pitch_nickname,p_license_type,p_coverage_area,v_nationality,v_dob,p_phone,v_code,'pending',now()) returning id into v_id;
 else
  update public.referees set pitch_nickname=coalesce(p_pitch_nickname,pitch_nickname),license_type=coalesce(p_license_type,license_type),coverage_area=coalesce(p_coverage_area,coverage_area),phone=coalesce(p_phone,phone),updated_at=now() where id=v_id;
 end if;
 insert into public.referee_attribute_state(referee_id) values(v_id) on conflict(referee_id) do nothing;
 insert into public.referee_accreditations(referee_id,level_no,course_type,course_title) values(v_id,1,'orientation','PlayPro Referee Orientation'),(v_id,2,'refreshment','PlayPro Referee Refreshment & Match Observer Protocol') on conflict(referee_id,level_no) do nothing;
 insert into public.profile_role_profiles(profile_id,role_code,subject_id,is_active) values(v_uid,'referee',v_id,true) on conflict(profile_id,role_code) do update set subject_id=excluded.subject_id,is_active=true,updated_at=now();
 return v_id;
end $$;

create or replace function public.playpro_referee_respond_assignment(p_assignment_id uuid,p_decision text,p_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_status text;v_profile uuid;v_role public.fixture_official_role;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_decision not in ('accepted','declined') then raise exception 'Keputusan assignment tidak sah' using errcode='22023'; end if;
 select profile_id,status,role into v_profile,v_status,v_role from public.referee_assignments where id=p_assignment_id for update;
 if v_profile is null then raise exception 'Assignment tidak ditemui' using errcode='P0002'; end if;
 if v_profile<>v_uid then raise exception 'Hanya pengadil yang ditugaskan boleh menjawab assignment' using errcode='42501'; end if;
 if v_role<>'referee'::public.fixture_official_role then raise exception 'Workflow ini hanya untuk lead referee' using errcode='22023'; end if;
 if not exists(select 1 from public.profile_role_profiles rp join public.referees r on r.id=rp.subject_id and r.user_id=rp.profile_id where rp.profile_id=v_uid and rp.role_code='referee' and rp.is_active=true and r.verification_status='verified' and exists(select 1 from public.referee_license_documents ld where ld.referee_id=r.id and ld.status='verified') and exists(select 1 from public.referee_accreditations ra where ra.referee_id=r.id and ra.level_no=1 and ra.status='completed')) then
  raise exception 'Pengadil belum mendapat pengiktirafan profesional PlayPro.' using errcode='42501';
 end if;
 if v_status not in ('assigned','accepted') then raise exception 'Assignment tidak lagi boleh diubah: %',v_status using errcode='55000'; end if;
 if p_decision='accepted' then update public.referee_assignments set status='accepted',accepted_at=coalesce(accepted_at,now()),notes=coalesce(nullif(trim(p_note),''),notes),updated_at=now() where id=p_assignment_id;
 else update public.referee_assignments set status='declined',notes=coalesce(nullif(trim(p_note),''),notes),updated_at=now() where id=p_assignment_id; end if;
 return jsonb_build_object('success',true,'assignment_id',p_assignment_id,'status',p_decision);
end $$;

create or replace function public.finalize_match(p_fixture_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_referee_profile_id uuid;v_result_exists boolean;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select ra.profile_id into v_referee_profile_id from public.referee_assignments ra join public.fixtures f on f.id=ra.fixture_id
 where ra.fixture_id=p_fixture_id and ra.role='referee'::public.fixture_official_role and ra.status in ('assigned','accepted','active') and f.match_state='ended'
 order by ra.assigned_at desc limit 1;
 if v_referee_profile_id is null then raise exception 'Match must be ENDED and have an active appointed referee before approval'; end if;
 if v_referee_profile_id<>auth.uid() then raise exception 'Only the appointed referee can approve/finalize this match' using errcode='42501'; end if;
 if not exists(select 1 from public.profile_role_profiles rp join public.referees r on r.id=rp.subject_id and r.user_id=rp.profile_id where rp.profile_id=auth.uid() and rp.role_code='referee' and rp.is_active=true and r.verification_status='verified' and exists(select 1 from public.referee_license_documents ld where ld.referee_id=r.id and ld.status='verified') and exists(select 1 from public.referee_accreditations ra where ra.referee_id=r.id and ra.level_no=1 and ra.status='completed')) then
  raise exception 'Pengadil belum mendapat pengiktirafan profesional PlayPro.' using errcode='42501';
 end if;
 select exists(select 1 from public.match_results mr where mr.fixture_id=p_fixture_id) into v_result_exists;
 if not v_result_exists then raise exception 'MATCH REPORT/result is required before referee approval'; end if;
 update public.match_results set is_official=true,ratified_by=auth.uid(),ratified_at=now(),entered_by=coalesce(entered_by,auth.uid()),updated_at=now() where fixture_id=p_fixture_id and is_official=false;
 if not found and not exists(select 1 from public.match_results where fixture_id=p_fixture_id and is_official=true and ratified_by=auth.uid()) then raise exception 'Match result is already official and was ratified by another authority'; end if;
 update public.fixtures set match_state='finalized',updated_at=now() where id=p_fixture_id and match_state='ended';
 if not found then raise exception 'Match finalization failed because the fixture state changed'; end if;
 return true;
end $$;
