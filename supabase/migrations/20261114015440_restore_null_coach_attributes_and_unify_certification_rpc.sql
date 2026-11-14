begin;
alter table public.coach_attribute_state
 alter column adaptability drop default, alter column adaptability drop not null,
 alter column coaching_goalkeepers drop default, alter column coaching_goalkeepers drop not null,
 alter column coaching_outfield drop default, alter column coaching_outfield drop not null,
 alter column coaching_youth drop default, alter column coaching_youth drop not null,
 alter column determination drop default, alter column determination drop not null,
 alter column discipline drop default, alter column discipline drop not null,
 alter column judging_player_ability drop default, alter column judging_player_ability drop not null,
 alter column judging_player_potential drop default, alter column judging_player_potential drop not null,
 alter column man_management drop default, alter column man_management drop not null,
 alter column motivating drop default, alter column motivating drop not null,
 alter column physiotherapy drop default, alter column physiotherapy drop not null,
 alter column tactical_knowledge drop default, alter column tactical_knowledge drop not null;
create or replace function public.playpro_request_coach_certification(p_track text,p_level integer,p_note text default null) returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_uid uuid := (select auth.uid()); v_coach_id uuid; v_request_id uuid; v_db_track text;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if p_track is null or p_track not in ('player_assessment_authority','coach_attribute_certification') then raise exception 'INVALID_TRACK' using errcode='22023'; end if;
 if p_level is null or p_level<1 or p_level>5 then raise exception 'INVALID_LEVEL' using errcode='22023'; end if;
 v_db_track:=case when p_track='player_assessment_authority' then 'player_assessment' else 'coach_attribute' end;
 select c.id into v_coach_id from public.coaches c where c.profile_id=v_uid and c.is_active=true for update;
 if v_coach_id is null then raise exception 'COACH_PROFILE_REQUIRED' using errcode='P0002'; end if;
 if not exists(select 1 from public.coaches c where c.id=v_coach_id and c.verification_status='verified' and c.kyc_verified_at is not null) then raise exception 'KYC_REQUIRED' using errcode='42501'; end if;
 if exists(select 1 from public.coach_certification_courses cc where cc.coach_id=v_coach_id and cc.course_no=p_level and cc.certification_track=v_db_track and cc.status='passed') then raise exception 'LEVEL_ALREADY_PASSED'; end if;
 select r.id into v_request_id from public.coach_certification_requests r where r.coach_id=v_coach_id and r.certification_track=v_db_track and r.requested_course_no=p_level and r.status in ('requested','scheduled','in_progress') order by r.created_at desc limit 1;
 if v_request_id is null then insert into public.coach_certification_requests(coach_id,requested_course_no,certification_track,status,requested_at,notes,created_at,updated_at) values(v_coach_id,p_level,v_db_track,'requested',now(),nullif(btrim(p_note),''),now(),now()) returning id into v_request_id; end if;
 return jsonb_build_object('ok',true,'request_id',v_request_id,'coach_id',v_coach_id,'track',p_track,'level',p_level,'status','requested');
end;$function$;
create or replace function public.playpro_review_coach_certification(p_request_id uuid,p_decision text,p_note text default null) returns uuid language plpgsql security definer set search_path='' as $function$
declare v_uid uuid := (select auth.uid()); v_req public.coach_certification_requests%rowtype; v_band text; v_max smallint;
begin
 if v_uid is null or (select public.get_my_role()) is distinct from 'developer'::public.user_role then raise exception 'REVIEWER_REQUIRED: Developer PlayPro only' using errcode='42501'; end if;
 if p_decision is null or p_decision not in ('approved','rejected') then raise exception 'INVALID_DECISION' using errcode='22023'; end if;
 select * into v_req from public.coach_certification_requests where id=p_request_id for update;
 if not found then raise exception 'REQUEST_NOT_FOUND' using errcode='P0002'; end if;
 if v_req.status<>'requested' then raise exception 'REQUEST_NOT_PENDING' using errcode='55000'; end if;
 v_band:=case v_req.requested_course_no when 1 then '1-5' when 2 then '5-10' when 3 then '10-15' when 4 then '15-20' else 'specialist' end;
 v_max:=case v_req.requested_course_no when 1 then 5 when 2 then 10 when 3 then 15 when 4 then 20 else 20 end;
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
create or replace function public.request_playpro_coach_certification(p_course_no smallint,p_track text default 'player_assessment'::text) returns jsonb language plpgsql security definer set search_path='' as $function$
begin
 if p_track is null or p_track not in ('player_assessment','coach_attribute') then raise exception 'INVALID_TRACK' using errcode='22023'; end if;
 return public.playpro_request_coach_certification(case when p_track='player_assessment' then 'player_assessment_authority' else 'coach_attribute_certification' end,p_course_no::integer,null);
end;$function$;
revoke all on function public.playpro_request_coach_certification(text,integer,text) from public;
grant execute on function public.playpro_request_coach_certification(text,integer,text) to authenticated;
revoke all on function public.playpro_review_coach_certification(uuid,text,text) from public;
grant execute on function public.playpro_review_coach_certification(uuid,text,text) to authenticated;
revoke all on function public.request_playpro_coach_certification(smallint,text) from public;
grant execute on function public.request_playpro_coach_certification(smallint,text) to authenticated;
commit;