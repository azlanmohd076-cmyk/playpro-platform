-- Multi-role account model: profile creation is allowed before professional recognition.
-- Professional actions must separately check role-specific verification/accreditation.
create or replace function public.playpro_safe_signup_role(p_role text)
returns public.user_role language plpgsql immutable set search_path=public,pg_temp as $$
declare v_role text:=lower(trim(coalesce(p_role,'')));
begin
 v_role:=case v_role when 'pengguna' then 'user' when 'user_biasa' then 'user'
 when 'pemain' then 'player' when 'jurulatih' then 'coach'
 when 'pengurus_kelab' then 'club_admin' when 'club_manager' then 'club_admin'
 when 'manager' then 'club_admin' when 'club_admin' then 'club_admin'
 when 'club_owner' then 'club_admin' when 'penganjur_liga' then 'organizer'
 when 'league_admin' then 'organizer' when 'pengadil' then 'referee' else v_role end;
 if v_role in ('user','player','coach','club_admin','organizer','referee') then return v_role::public.user_role; end if;
 return 'player'::public.user_role;
end $$;

create or replace function public.playpro_add_role(p_role_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_role text:=lower(btrim(coalesce(p_role_code,''))); v_subject uuid;
begin
 if v_uid is null then raise exception 'Log masuk diperlukan.' using errcode='42501'; end if;
 v_role:=case v_role when 'club_admin' then 'club_owner' when 'club_manager' then 'club_owner'
 when 'pengurus_kelab' then 'club_owner' when 'pemain' then 'player'
 when 'jurulatih' then 'coach' when 'penganjur' then 'organizer' when 'pengadil' then 'referee' else v_role end;
 if v_role not in ('player','coach','club_owner','organizer','referee') then raise exception 'Peranan PlayPro tidak sah.' using errcode='22023'; end if;
 if v_role='player' then select id into v_subject from public.players where profile_id=v_uid and is_active=true order by created_at asc limit 1;
 elsif v_role='coach' then select id into v_subject from public.coaches where profile_id=v_uid and is_active=true order by created_at asc limit 1;
 elsif v_role='club_owner' then select id into v_subject from public.clubs where owner_profile_id=v_uid order by created_at asc limit 1;
 elsif v_role='organizer' then select id into v_subject from public.organizers where profile_id=v_uid order by created_at asc limit 1;
 elsif v_role='referee' then select id into v_subject from public.referees where user_id=v_uid order by created_at asc limit 1;
 end if;
 insert into public.profile_role_profiles(profile_id,role_code,subject_id,is_active) values(v_uid,v_role,v_subject,true)
 on conflict(profile_id,role_code) do update set subject_id=coalesce(public.profile_role_profiles.subject_id,excluded.subject_id),is_active=true,updated_at=now();
 return jsonb_build_object('ok',true,'role_code',v_role,'subject_id',v_subject);
end $$;
grant execute on function public.playpro_add_role(text) to authenticated;

create or replace function public.create_organizer_profile(p_organizer_type text,p_display_name text,p_description text default null,p_phone text default null,p_whatsapp text default null,p_email text default null,p_city text default null,p_state text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_profile uuid:=auth.uid();v_id uuid;v_code text;
begin
 if v_profile is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_display_name is null or btrim(p_display_name)='' then raise exception 'Organizer display name is required'; end if;
 if exists(select 1 from public.organizers where profile_id=v_profile) then raise exception 'Organizer profile already exists'; end if;
 v_code:='ORG-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 insert into public.organizers(profile_id,organizer_code,organizer_type,display_name,description,phone,whatsapp,email,city,state,verification_status,profile_completed_at)
 values(v_profile,v_code,p_organizer_type,btrim(p_display_name),p_description,p_phone,p_whatsapp,p_email,p_city,p_state,'pending',now()) returning id into v_id;
 insert into public.profile_role_profiles(profile_id,role_code,subject_id) values(v_profile,'organizer',v_id)
 on conflict(profile_id,role_code) do update set subject_id=excluded.subject_id,is_active=true,updated_at=now();
 return v_id;
end $$;

create or replace function public.create_referee_profile(p_pitch_nickname text default null,p_license_type text default null,p_coverage_area text default null,p_phone text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_uid uuid:=auth.uid();v_id uuid;v_name text;v_dob date;v_nationality text;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if exists(select 1 from public.referees where user_id=v_uid) then select id into v_id from public.referees where user_id=v_uid limit 1;return v_id;end if;
 select coalesce(p.full_name,'PlayPro Referee'),p.date_of_birth,coalesce(p.nationality,'Malaysian') into v_name,v_dob,v_nationality from public.profiles p where p.id=v_uid;
 insert into public.referees(user_id,full_name,pitch_nickname,license_type,coverage_area,nationality,date_of_birth,phone,verification_status,profile_completed_at)
 values(v_uid,v_name,p_pitch_nickname,p_license_type,p_coverage_area,v_nationality,v_dob,p_phone,'pending',now()) returning id into v_id;
 insert into public.profile_role_profiles(profile_id,role_code,subject_id,is_active) values(v_uid,'referee',v_id,true)
 on conflict(profile_id,role_code) do update set subject_id=excluded.subject_id,is_active=true,updated_at=now();
 return v_id;
end $$;

create or replace function public.create_playpro_club(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_club_id uuid;v_name text:=nullif(trim(p_payload->>'name'),'');v_type text:=nullif(trim(p_payload->>'club_type'),'');v_slug text;v_code text;
begin
 if v_uid is null then raise exception 'Log masuk diperlukan.' using errcode='42501'; end if;
 if v_name is null then raise exception 'Nama kelab wajib diisi.' using errcode='22023'; end if;
 if v_type is null or not exists(select 1 from public.club_type_catalog where code=v_type and active) then raise exception 'Jenis kelab tidak sah.' using errcode='22023'; end if;
 v_club_id:=gen_random_uuid();v_code:='PP-CLB-'||lpad(nextval('public.club_code_seq')::text,6,'0');
 v_slug:=lower(regexp_replace(v_name,'[^a-zA-Z0-9]+','-','g'))||'-'||substring(v_club_id::text,1,8);
 insert into public.clubs(id,name,logo_url,year_founded,home_venue,colours,admin_id,owner_profile_id,club_code,slug,club_type,description,ros_registration_no,contact_phone,whatsapp_phone,city,state,country,verification_status,visibility,created_at,updated_at)
 values(v_club_id,v_name,null,null,null,null,v_uid,v_uid,v_code,v_slug,v_type,nullif(trim(p_payload->>'description'),''),nullif(trim(p_payload->>'ros_registration_no'),''),nullif(trim(p_payload->>'contact_phone'),''),nullif(trim(p_payload->>'whatsapp_phone'),''),nullif(trim(p_payload->>'city'),''),nullif(trim(p_payload->>'state'),''),coalesce(nullif(trim(p_payload->>'country'),''),'Malaysia'),'pending',case when p_payload->>'visibility'='private' then 'private' else 'public' end,now(),now());
 insert into public.club_memberships(club_id,profile_id,role_code,status,created_by) values(v_club_id,v_uid,'owner','active',v_uid);
 insert into public.profile_role_profiles(profile_id,role_code,subject_id,is_active,created_at,updated_at) values(v_uid,'club_owner',v_club_id,true,now(),now())
 on conflict(profile_id,role_code) do update set subject_id=excluded.subject_id,is_active=true,updated_at=now();
 return jsonb_build_object('success',true,'club_id',v_club_id,'club_code',v_code,'slug',v_slug,'verification_status','pending');
end $$;
