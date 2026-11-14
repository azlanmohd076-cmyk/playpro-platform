begin;
alter table public.coach_certification_courses drop constraint if exists coach_certification_courses_coach_id_course_no_key;
alter table public.coach_certification_courses add constraint coach_certification_courses_coach_course_track_key unique (coach_id,course_no,certification_track);
alter table public.coach_certification_requests drop constraint if exists coach_certification_requests_status_check;
alter table public.coach_certification_requests add constraint coach_certification_requests_status_check check (status = any (array['requested','scheduled','in_progress','passed','failed','cancelled','rejected']));
create unique index if not exists coach_certification_requests_one_open_per_track_level on public.coach_certification_requests(coach_id,certification_track,requested_course_no) where status in ('requested','scheduled','in_progress');
create or replace function public.playpro_request_coach_certification(p_track text,p_level integer,p_note text default null) returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_uid uuid := (select auth.uid()); v_coach_id uuid; v_request_id uuid;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if p_track not in ('player_assessment_authority','coach_attribute_certification') then raise exception 'INVALID_TRACK' using errcode='22023'; end if;
 if p_level is null or p_level<1 or p_level>5 then raise exception 'INVALID_LEVEL' using errcode='22023'; end if;
 select c.id into v_coach_id from public.coaches c where c.profile_id=v_uid and c.is_active=true for update;
 if v_coach_id is null then raise exception 'COACH_PROFILE_REQUIRED' using errcode='P0002'; end if;
 if not exists(select 1 from public.coaches c where c.id=v_coach_id and c.verification_status='verified' and c.kyc_verified_at is not null) then raise exception 'KYC_REQUIRED' using errcode='42501'; end if;
 if exists(select 1 from public.coach_certification_courses cc where cc.coach_id=v_coach_id and cc.course_no=p_level and cc.certification_track=case when p_track='player_assessment_authority' then 'player_assessment' else 'coach_attribute' end and cc.status='passed') then raise exception 'LEVEL_ALREADY_PASSED'; end if;
 select r.id into v_request_id from public.coach_certification_requests r where r.coach_id=v_coach_id and r.certification_track=case when p_track='player_assessment_authority' then 'player_assessment' else 'coach_attribute' end and r.requested_course_no=p_level and r.status in ('requested','scheduled','in_progress') order by r.created_at desc limit 1;
 if v_request_id is null then
  insert into public.coach_certification_requests(coach_id,requested_course_no,certification_track,status,requested_at,notes,created_at,updated_at)
  values(v_coach_id,p_level,case when p_track='player_assessment_authority' then 'player_assessment' else 'coach_attribute' end,'requested',now(),nullif(btrim(p_note),''),now(),now()) returning id into v_request_id;
 end if;
 return jsonb_build_object('ok',true,'request_id',v_request_id,'coach_id',v_coach_id,'track',p_track,'level',p_level,'status','requested');
end;$function$;
create or replace function public.playpro_review_coach_certification(p_request_id uuid,p_decision text,p_note text default null) returns uuid language plpgsql security definer set search_path='' as $function$
declare v_uid uuid := (select auth.uid()); v_req public.coach_certification_requests%rowtype; v_band text; v_max smallint;
begin
 if v_uid is null or (select public.get_my_role()) is distinct from 'developer'::public.user_role then raise exception 'REVIEWER_REQUIRED: Developer PlayPro only' using errcode='42501'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'INVALID_DECISION' using errcode='22023'; end if;
 select * into v_req from public.coach_certification_requests where id=p_request_id for update;
 if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
 if v_req.status<>'requested' then raise exception 'REQUEST_NOT_PENDING' using errcode='55000'; end if;
 v_band:=case v_req.requested_course_no when 1 then '1-5' when 2 then '5-10' when 3 then '10-15' when 4 then '15-20' else 'specialist' end;
 v_max:=case v_req.requested_course_no when 1 then 5 when 2 then 10 when 3 then 15 else 20 end;
 if p_decision='approved' then
  update public.coach_certification_requests set status='scheduled',reviewed_by=v_uid,reviewed_at=now(),notes=coalesce(nullif(btrim(p_note),''),notes),updated_at=now() where id=p_request_id;
  insert into public.coach_certification_courses(coach_id,course_no,attribute_band,max_attribute_score,status,requested_at,scheduled_at,completed_at,reviewed_by,notes,created_at,updated_at,certification_track)
  values(v_req.coach_id,v_req.requested_course_no,v_band,v_max,'scheduled',v_req.requested_at,null,null,v_uid,nullif(btrim(p_note),''),now(),now(),v_req.certification_track)
  on conflict(coach_id,course_no,certification_track) do update set status=case when public.coach_certification_courses.status='passed' then 'passed' else 'scheduled' end,reviewed_by=excluded.reviewed_by,notes=coalesce(excluded.notes,public.coach_certification_courses.notes),updated_at=now();
 else
  update public.coach_certification_requests set status='rejected',reviewed_by=v_uid,reviewed_at=now(),notes=coalesce(nullif(btrim(p_note),''),notes),updated_at=now() where id=p_request_id;
 end if;
 return p_request_id;
end;$function$;
revoke all on function public.playpro_request_coach_certification(text,integer,text) from public;
grant execute on function public.playpro_request_coach_certification(text,integer,text) to authenticated;
revoke all on function public.playpro_review_coach_certification(uuid,text,text) from public;
grant execute on function public.playpro_review_coach_certification(uuid,text,text) to authenticated;
commit;