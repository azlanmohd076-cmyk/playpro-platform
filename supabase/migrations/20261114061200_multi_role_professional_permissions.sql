-- Multi-role professional permissions.
-- profiles.role is the account's original signup type; role-specific access must
-- use profile_role_profiles plus the relevant verified/accredited subject record.

create or replace function public.approve_role_kyc(p_kyc_id uuid,p_reviewer_note text default null,p_verified_legal_name text default null,p_verified_birth_date date default null,p_verified_birth_state_code text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_k public.identity_verifications%rowtype;v_name text;v_dob date;v_state text;
begin
 if v_uid is null or not public.is_league_founder_or_developer() then raise exception 'KYC approval requires PlayPro privileged access' using errcode='42501'; end if;
 select * into v_k from public.identity_verifications where id=p_kyc_id and subject_type in ('club_owner','organizer','referee') for update;
 if not found then raise exception 'Role KYC request not found' using errcode='P0002'; end if;
 if v_k.status='verified' then return jsonb_build_object('ok',true,'status','verified','subject_type',v_k.subject_type,'profile_id',v_k.profile_id); end if;
 if v_k.status<>'pending' then raise exception 'Role KYC request is not awaiting approval' using errcode='40901'; end if;
 v_name:=nullif(btrim(coalesce(p_verified_legal_name,v_k.extracted_legal_name)),'');
 if v_name is null then raise exception 'Reviewer mesti mengesahkan nama sah berdasarkan dokumen asal.' using errcode='22023'; end if;
 v_dob:=coalesce(p_verified_birth_date,v_k.extracted_birth_date);
 if v_k.extracted_birth_date is not null and p_verified_birth_date is not null and v_k.extracted_birth_date<>p_verified_birth_date then raise exception 'Tarikh lahir yang disahkan tidak sepadan dengan bacaan dokumen. Semak semula dokumen asal.' using errcode='22023'; end if;
 v_state:=coalesce(nullif(btrim(p_verified_birth_state_code),''),nullif(btrim(v_k.birth_state_code),''));
 if v_state is null or v_state !~ '^[0-9]{2}$' then raise exception 'Kod negeri kelahiran mesti 2 digit.' using errcode='22023'; end if;
 update public.identity_verifications set status='verified',reviewer_profile_id=v_uid,reviewer_note=p_reviewer_note,reviewed_at=now(),extracted_legal_name=v_name,extracted_birth_date=coalesce(v_dob,extracted_birth_date),provider_status=coalesce(provider_status,'reviewed'),updated_at=now() where id=v_k.id;
 if v_k.subject_type='organizer' then
  update public.organizers set verification_status='verified',verified_at=now(),verified_by=v_uid,updated_at=now() where profile_id=v_k.profile_id;
 elsif v_k.subject_type='referee' then
  update public.referees set verification_status='verified',verified_at=now(),verified_by=v_uid,updated_at=now() where user_id=v_k.profile_id;
 elsif v_k.subject_type='club_owner' then
  update public.clubs set verification_status='under_review',updated_at=now() where owner_profile_id=v_k.profile_id and verification_status in ('pending','rejected');
 end if;
 return jsonb_build_object('ok',true,'status','verified','subject_type',v_k.subject_type,'profile_id',v_k.profile_id);
end $$;

create or replace function public.create_playpro_competition(p_name text,p_season text default null,p_description text default null,p_yellow_card_threshold integer default 5,p_red_card_ban_matches integer default 1)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_base_role text;v_organizer_id uuid;v_league uuid;v_rule uuid;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 select role::text into v_base_role from public.profiles where id=v_uid and is_active=true;
 if coalesce(v_base_role,'')<>'developer' then
  select o.id into v_organizer_id from public.profile_role_profiles rp join public.organizers o on o.id=rp.subject_id and o.profile_id=rp.profile_id
  where rp.profile_id=v_uid and rp.role_code='organizer' and rp.is_active=true and o.verification_status='verified';
  if v_organizer_id is null then raise exception 'ORGANIZER_NOT_VERIFIED: Profil Organizer dan pengiktirafan PlayPro diperlukan.' using errcode='42501'; end if;
 end if;
 if nullif(trim(p_name),'') is null then raise exception 'COMPETITION_NAME_REQUIRED' using errcode='22023'; end if;
 insert into public.leagues(name,season,description,status,founder_id,yellow_card_threshold,red_card_ban_matches)
 values(trim(p_name),nullif(trim(p_season),''),nullif(trim(p_description),''),'draft'::public.league_status,v_uid,greatest(coalesce(p_yellow_card_threshold,5),1),greatest(coalesce(p_red_card_ban_matches,1),1)) returning id into v_league;
 insert into public.competition_rule_config(league_id,red_card_suspension_matches,second_yellow_suspension_matches,version,effective_from,updated_by)
 values(v_league,greatest(coalesce(p_red_card_ban_matches,1),1),greatest(coalesce(p_red_card_ban_matches,1),1),1,now(),v_uid) returning id into v_rule;
 return jsonb_build_object('competition_id',v_league,'rule_config_id',v_rule,'status','draft');
end $$;

create or replace function public.get_assessment_workspace()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());v_level smallint;v_players jsonb;
begin
 if v_uid is null or not exists(select 1 from public.profile_role_profiles rp where rp.profile_id=v_uid and rp.role_code='coach' and rp.is_active=true)
  or not exists(select 1 from public.coach_accreditations ca where ca.coach_profile_id=v_uid and ca.status='active' and (ca.expires_at is null or ca.expires_at>now()) and ca.accreditation_level between 1 and 7) then
  raise exception 'FORBIDDEN: hanya Coach dengan akreditasi PlayPro aktif Level 1–7 boleh menilai pemain.' using errcode='42501';
 end if;
 select accreditation_level into v_level from public.coach_accreditations where coach_profile_id=v_uid and status='active' and (expires_at is null or expires_at>now()) order by accreditation_level desc limit 1;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',case when p.display_name_mode='legal' then p.full_name else coalesce(nullif(btrim(p.preferred_name),''),p.full_name) end,'position',p.position::text,'club_name',c.name,'assessment_source',coalesce(s.source,'none'),'assessed_count',(select count(*) from jsonb_each(to_jsonb(s)-'player_id'-'source'-'confidence'-'updated_at') e where e.value<>'null'::jsonb)) order by p.full_name),'[]'::jsonb)
 into v_players from public.players p left join public.clubs c on c.id=p.club_id left join public.player_attribute_state s on s.player_id=p.id where p.is_active=true and coalesce(p.is_demo,false)=false;
 return jsonb_build_object('ok',true,'coach_level',v_level,'players',v_players);
end $$;

create or replace function public.submit_player_assessment(p_player_id uuid,p_attributes jsonb,p_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());v_level smallint;v_keys text[]:=array['passing','dribbling','finishing','first_touch','tackling','heading','pace','stamina','strength','agility','leadership','composure','teamwork','work_rate','positioning','vision','decision_making','anticipation'];v_key text;v_value numeric;
begin
 if v_uid is null or not exists(select 1 from public.profile_role_profiles rp where rp.profile_id=v_uid and rp.role_code='coach' and rp.is_active=true)
  or not exists(select 1 from public.coach_accreditations ca where ca.coach_profile_id=v_uid and ca.status='active' and (ca.expires_at is null or ca.expires_at>now()) and ca.accreditation_level between 1 and 7) then
  raise exception 'FORBIDDEN: hanya Coach bertauliah PlayPro Level 1–7 boleh menghantar penilaian' using errcode='42501';
 end if;
 select accreditation_level into v_level from public.coach_accreditations where coach_profile_id=v_uid and status='active' and (expires_at is null or expires_at>now()) order by accreditation_level desc limit 1;
 if not exists(select 1 from public.players where id=p_player_id and is_active=true and coalesce(is_demo,false)=false) then raise exception 'Pemain tidak ditemui atau profil demo tidak boleh menerima penilaian'; end if;
 if p_attributes is null or jsonb_typeof(p_attributes)<>'object' or (select count(*) from jsonb_object_keys(p_attributes))<>18 then raise exception 'Penilaian mesti mengandungi tepat 18 atribut'; end if;
 foreach v_key in array v_keys loop
  if not (p_attributes?v_key) then raise exception 'Atribut tiada: %',v_key; end if;
  if jsonb_typeof(p_attributes->v_key)<>'number' then raise exception 'Nilai % mesti nombor',v_key; end if;
  v_value:=(p_attributes->>v_key)::numeric;
  if v_value<>trunc(v_value) or v_value<1 or v_value>20 then raise exception 'Nilai % mesti nombor bulat antara 1 hingga 20',v_key; end if;
 end loop;
 insert into public.player_assessment_records(player_id,coach_profile_id,accreditation_level,attributes,notes) values(p_player_id,v_uid,v_level,p_attributes,nullif(btrim(p_notes),''));
 insert into public.player_attribute_state(player_id,passing,dribbling,finishing,first_touch,tackling,heading,pace,stamina,strength,agility,leadership,composure,teamwork,work_rate,positioning,vision,decision_making,anticipation,source,confidence,updated_at)
 values(p_player_id,(p_attributes->>'passing')::smallint,(p_attributes->>'dribbling')::smallint,(p_attributes->>'finishing')::smallint,(p_attributes->>'first_touch')::smallint,(p_attributes->>'tackling')::smallint,(p_attributes->>'heading')::smallint,(p_attributes->>'pace')::smallint,(p_attributes->>'stamina')::smallint,(p_attributes->>'strength')::smallint,(p_attributes->>'agility')::smallint,(p_attributes->>'leadership')::smallint,(p_attributes->>'composure')::smallint,(p_attributes->>'teamwork')::smallint,(p_attributes->>'work_rate')::smallint,(p_attributes->>'positioning')::smallint,(p_attributes->>'vision')::smallint,(p_attributes->>'decision_making')::smallint,(p_attributes->>'anticipation')::smallint,'coach_assessment',100,now())
 on conflict(player_id) do update set passing=excluded.passing,dribbling=excluded.dribbling,finishing=excluded.finishing,first_touch=excluded.first_touch,tackling=excluded.tackling,heading=excluded.heading,pace=excluded.pace,stamina=excluded.stamina,strength=excluded.strength,agility=excluded.agility,leadership=excluded.leadership,composure=excluded.composure,teamwork=excluded.teamwork,work_rate=excluded.work_rate,positioning=excluded.positioning,vision=excluded.vision,decision_making=excluded.decision_making,anticipation=excluded.anticipation,source='coach_assessment',confidence=100,updated_at=now();
 return jsonb_build_object('ok',true,'player_id',p_player_id,'coach_level',v_level,'attributes_count',18,'assessed_at',now());
end $$;

create or replace function public.playpro_create_referee_profile(p_full_name text,p_phone text default null,p_nationality text default 'Malaysian')
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_id uuid;v_code text;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select id into v_id from public.referees where user_id=v_uid limit 1;
 if v_id is null then
  v_code:='PP-REF-'||lpad(nextval('public.referee_code_seq')::text,6,'0');
  insert into public.referees(user_id,full_name,phone,nationality,referee_code,verification_status) values(v_uid,coalesce(nullif(trim(p_full_name),''),(select full_name from public.profiles where id=v_uid)),p_phone,coalesce(nullif(trim(p_nationality),''),'Malaysian'),v_code,'pending') returning id into v_id;
 else
  update public.referees set full_name=coalesce(nullif(trim(p_full_name),''),full_name),phone=coalesce(p_phone,phone),nationality=coalesce(nullif(trim(p_nationality),''),nationality),updated_at=now() where id=v_id;
 end if;
 insert into public.referee_attribute_state(referee_id) values(v_id) on conflict(referee_id) do nothing;
 insert into public.referee_accreditations(referee_id,level_no,course_type,course_title) values(v_id,1,'orientation','PlayPro Referee Orientation'),(v_id,2,'refreshment','PlayPro Referee Refreshment & Match Observer Protocol') on conflict(referee_id,level_no) do nothing;
 insert into public.profile_role_profiles(profile_id,role_code,subject_id,is_active) values(v_uid,'referee',v_id,true) on conflict(profile_id,role_code) do update set subject_id=excluded.subject_id,is_active=true,updated_at=now();
 return jsonb_build_object('success',true,'referee_id',v_id,'referee_code',(select referee_code from public.referees where id=v_id),'verification_status','pending');
end $$;

create or replace function public.save_club_manager_onboarding_profile(p_profile_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid());v_club_id uuid;v_type text:=coalesce(nullif(trim(p_payload->>'club_type'),''),'grassroots_academy');
begin
 if v_uid is null or v_uid<>p_profile_id then raise exception 'Akses tidak dibenarkan.' using errcode='42501'; end if;
 if not exists(select 1 from public.club_type_catalog where code=v_type and active) then raise exception 'Jenis kelab tidak sah.' using errcode='22023'; end if;
 select id into v_club_id from public.clubs where owner_profile_id=v_uid or admin_id=v_uid order by created_at limit 1;
 if v_club_id is null then return public.create_playpro_club(p_payload||jsonb_build_object('club_type',v_type)); end if;
 update public.clubs set name=coalesce(nullif(trim(p_payload->>'club_name'),''),name),year_founded=coalesce(nullif(p_payload->>'year_founded','')::int,year_founded),home_venue=coalesce(nullif(trim(p_payload->>'training_ground'),''),home_venue),colours=coalesce(nullif(trim(p_payload->>'club_colours'),''),colours),contact_phone=coalesce(nullif(trim(p_payload->>'phone'),''),contact_phone),club_type=v_type,updated_at=now() where id=v_club_id;
 insert into public.profile_role_profiles(profile_id,role_code,subject_id,is_active,created_at,updated_at) values(v_uid,'club_owner',v_club_id,true,now(),now()) on conflict(profile_id,role_code) do update set subject_id=excluded.subject_id,is_active=true,updated_at=now();
 return jsonb_build_object('success',true,'reason','CLUB_PROFILE_UPDATED','club_id',v_club_id);
end $$;
