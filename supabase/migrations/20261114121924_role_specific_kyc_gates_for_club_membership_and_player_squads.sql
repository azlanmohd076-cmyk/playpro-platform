create or replace function public.playpro_profile_kyc_verified_for(p_profile_id uuid, p_subject_type text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.profiles p
    where p.id = p_profile_id and p.is_active = true
  ) and case lower(btrim(coalesce(p_subject_type,'')))
    when 'player' then (
      exists (
        select 1 from public.identity_verifications iv
        where iv.profile_id=p_profile_id and iv.subject_type='player'
          and lower(btrim(iv.status)) in ('verified','approved')
      ) or exists (
        select 1 from public.players pl
        where pl.profile_id=p_profile_id and pl.is_active=true
          and lower(btrim(coalesce(pl.verification_status,'')))='verified'
      )
    )
    when 'coach' then (
      exists (
        select 1 from public.identity_verifications iv
        where iv.profile_id=p_profile_id and iv.subject_type='coach'
          and lower(btrim(iv.status)) in ('verified','approved')
      ) or exists (
        select 1 from public.coaches c
        where c.profile_id=p_profile_id and c.is_active=true
          and lower(btrim(coalesce(c.verification_status,'')))='verified'
          and c.kyc_verified_at is not null
      )
    )
    when 'club_owner' then exists (
      select 1 from public.identity_verifications iv
      where iv.profile_id=p_profile_id and iv.subject_type='club_owner'
        and lower(btrim(iv.status)) in ('verified','approved')
    )
    else false
  end;
$function$;

create or replace function public.playpro_profile_kyc_verified(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select public.playpro_profile_kyc_verified_for(p_profile_id,'player')
      or public.playpro_profile_kyc_verified_for(p_profile_id,'club_owner');
$function$;

create or replace function public.add_player_to_club_team(p_team_id uuid, p_player_id uuid, p_jersey smallint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_club_id uuid;
  v_age_category text;
  v_dob date;
  v_football_age integer;
  v_min_age integer;
  v_player_profile uuid;
begin
  perform public.playpro_require_active_account();
  select t.club_id,t.age_category into v_club_id,v_age_category
  from public.club_teams t where t.id=p_team_id;
  if v_club_id is null then raise exception 'Squad tidak ditemui.' using errcode='P0002'; end if;
  if v_uid is null or not public.playpro_is_club_manager(v_club_id) then
    raise exception 'Akses squad tidak dibenarkan.' using errcode='42501';
  end if;
  select p.date_of_birth,p.profile_id into v_dob,v_player_profile
  from public.players p where p.id=p_player_id and p.is_active=true;
  if v_dob is null or v_player_profile is null then raise exception 'Pemain tidak ditemui.' using errcode='P0002'; end if;
  if not public.playpro_profile_kyc_verified_for(v_player_profile,'player') then
    raise exception 'Pemain mesti mempunyai KYC pemain PlayPro yang disahkan sebelum masuk kelab.' using errcode='42501';
  end if;
  v_football_age := extract(year from current_date)::integer-extract(year from v_dob)::integer;
  if v_age_category='veteran' then
    if v_football_age<35 then raise exception 'Pemain belum mencapai umur Veteran (35+).'; end if;
  elsif v_age_category<>'open' then
    v_min_age:=substring(v_age_category from 2)::integer;
    if v_football_age<v_min_age then
      raise exception 'Pemain football age % tidak layak untuk squad %.',v_football_age,upper(v_age_category);
    end if;
  end if;
  insert into public.club_memberships(club_id,profile_id,role_code,status,created_by)
  values(v_club_id,v_player_profile,'player','active',v_uid) on conflict do nothing;
  insert into public.club_team_players(team_id,player_id,jersey_number,created_by)
  values(p_team_id,p_player_id,p_jersey,v_uid) on conflict do nothing;
  return jsonb_build_object('success',true,'team_id',p_team_id,'player_id',p_player_id,
    'football_age',v_football_age,'age_category',v_age_category);
end;
$function$;

create or replace function public.playpro_create_membership_request(
 p_club_id uuid,p_profile_id uuid,p_role text,p_mode text,p_note text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
 v_uid uuid:=auth.uid(); v_fee_enabled boolean:=false; v_fee numeric(12,2):=0;
 v_req uuid; v_payment_required boolean:=false; v_kyc_ok boolean:=false;
begin
 perform public.playpro_require_active_account();
 if v_uid is null then raise exception 'Log masuk diperlukan.' using errcode='42501'; end if;
 if p_role not in ('player','coach','staff','admin') then raise exception 'Role kelab tidak sah.' using errcode='22023'; end if;
 if p_mode not in ('club_invite','user_request') then raise exception 'Mode permintaan tidak sah.' using errcode='22023'; end if;
 if p_mode='club_invite' and not public.playpro_is_club_manager(p_club_id) then raise exception 'Hanya owner/admin kelab boleh menjemput.' using errcode='42501'; end if;
 if p_mode='user_request' and v_uid<>p_profile_id then raise exception 'Permintaan mesti datang daripada user tersebut.' using errcode='42501'; end if;
 if p_role='player' then v_kyc_ok:=public.playpro_profile_kyc_verified_for(p_profile_id,'player');
 elsif p_role='coach' then v_kyc_ok:=public.playpro_profile_kyc_verified_for(p_profile_id,'coach');
 else v_kyc_ok:=public.playpro_profile_kyc_verified(p_profile_id);
 end if;
 if not v_kyc_ok then raise exception 'KYC untuk peranan ini belum disahkan.' using errcode='23514'; end if;
 if exists(select 1 from public.club_memberships m where m.club_id=p_club_id and m.profile_id=p_profile_id and m.status in ('active','suspended')) then
   raise exception 'User sudah menjadi ahli kelab.' using errcode='23505';
 end if;
 select fee_collection_enabled,player_registration_fee into v_fee_enabled,v_fee
 from public.club_membership_settings where club_id=p_club_id;
 v_payment_required:=p_role='player' and coalesce(v_fee_enabled,false) and coalesce(v_fee,0)>0;
 insert into public.club_membership_requests(club_id,profile_id,requested_role,initiated_by,requested_by,status,payment_required,payment_status,club_note)
 values(p_club_id,p_profile_id,p_role,p_mode,v_uid,'requested',v_payment_required,
   case when v_payment_required then 'pending' else 'not_required' end,p_note)
 returning id into v_req;
 return jsonb_build_object('success',true,'request_id',v_req,'payment_required',v_payment_required,'fee',v_fee,'platform_fee_percent',5.00);
end;
$function$;

create or replace function public.playpro_approve_membership_request(p_request_id uuid,p_note text default null)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
 r public.club_membership_requests; v_uid uuid:=auth.uid();
 v_payment_id uuid; v_fee numeric(12,2); v_pct numeric(5,2); v_net numeric(12,2);
 v_kyc_ok boolean:=false;
begin
 perform public.playpro_require_active_account();
 select * into r from public.club_membership_requests where id=p_request_id for update;
 if not found or not public.playpro_is_club_manager(r.club_id) then
   raise exception 'Permintaan tidak ditemui atau akses tidak dibenarkan.' using errcode='42501';
 end if;
 if r.status<>'requested' then raise exception 'Permintaan bukan dalam status requested.' using errcode='22023'; end if;
 if r.requested_role='player' then v_kyc_ok:=public.playpro_profile_kyc_verified_for(r.profile_id,'player');
 elsif r.requested_role='coach' then v_kyc_ok:=public.playpro_profile_kyc_verified_for(r.profile_id,'coach');
 elsif r.requested_role in ('staff','admin') then v_kyc_ok:=public.playpro_profile_kyc_verified(r.profile_id);
 else v_kyc_ok:=false;
 end if;
 if not v_kyc_ok then raise exception 'KYC untuk peranan ini belum disahkan.' using errcode='23514'; end if;
 select player_registration_fee,platform_fee_percent into v_fee,v_pct
 from public.club_membership_settings where club_id=r.club_id;
 v_fee:=coalesce(v_fee,0); v_pct:=coalesce(v_pct,5);
 if r.requested_role='player' and r.payment_required and v_fee>0 then
   update public.club_membership_requests set status='payment_pending',approved_by=v_uid,approved_at=now(),response_note=p_note,updated_at=now() where id=p_request_id;
   v_net:=round(v_fee-(v_fee*v_pct/100),2);
   insert into public.club_membership_payments(request_id,club_id,payer_profile_id,gross_amount,platform_fee_amount,club_net_amount,currency,status)
   select r.id,r.club_id,r.profile_id,v_fee,round(v_fee*v_pct/100,2),v_net,
     coalesce((select currency from public.club_membership_settings where club_id=r.club_id),'MYR'),'pending'
   on conflict(request_id) do nothing returning id into v_payment_id;
   return jsonb_build_object('success',true,'status','payment_pending','payment_id',v_payment_id,
     'gross_amount',v_fee,'platform_fee',round(v_fee*v_pct/100,2),'club_net',v_net);
 end if;
 update public.club_membership_requests set status='active',payment_status='not_required',
   approved_by=v_uid,approved_at=now(),response_note=p_note,updated_at=now() where id=p_request_id;
 insert into public.club_memberships(club_id,profile_id,role_code,status,created_by)
 values(r.club_id,r.profile_id,r.requested_role,'active',v_uid) on conflict do nothing;
 return jsonb_build_object('success',true,'status','active','payment_required',false);
end;
$function$;

create or replace function public.add_club_member(p_club_id uuid,p_profile_id uuid,p_role_code text,p_title text default null)
returns jsonb
language plpgsql security definer set search_path=''
as $function$
declare
 v_uid uuid:=(select auth.uid()); v_role text:=lower(trim(p_role_code)); v_subject uuid; v_kyc_ok boolean:=false;
begin
 perform public.playpro_require_active_account();
 if v_uid is null or not public.playpro_is_club_manager(p_club_id) then
   raise exception 'Hanya owner/admin kelab dibenarkan.' using errcode='42501';
 end if;
 if v_role not in ('owner','admin','coach','staff','player') then raise exception 'Role kelab tidak sah.' using errcode='22023'; end if;
 if not exists(select 1 from public.profiles where id=p_profile_id and is_active=true) then
   raise exception 'User PlayPro tidak ditemui.' using errcode='P0002';
 end if;
 if v_role='player' then v_kyc_ok:=public.playpro_profile_kyc_verified_for(p_profile_id,'player');
 elsif v_role='coach' then v_kyc_ok:=public.playpro_profile_kyc_verified_for(p_profile_id,'coach');
 elsif v_role in ('owner','admin') then v_kyc_ok:=public.playpro_profile_kyc_verified_for(p_profile_id,'club_owner');
 else v_kyc_ok:=public.playpro_profile_kyc_verified(p_profile_id);
 end if;
 if not v_kyc_ok then raise exception 'KYC untuk peranan ini belum disahkan.' using errcode='42501'; end if;
 if v_role='player' then
   select id into v_subject from public.players where profile_id=p_profile_id and is_active=true;
   if v_subject is null then raise exception 'User belum mempunyai Player Profile.' using errcode='P0002'; end if;
 elsif v_role='coach' then
   select id into v_subject from public.coaches where profile_id=p_profile_id and is_active=true;
   if v_subject is null then raise exception 'User belum mempunyai Coach Profile.' using errcode='P0002'; end if;
 end if;
 insert into public.club_memberships(club_id,profile_id,role_code,status,title,created_by)
 values(p_club_id,p_profile_id,v_role,'active',nullif(trim(p_title),''),v_uid) on conflict do nothing;
 return jsonb_build_object('success',true,'club_id',p_club_id,'profile_id',p_profile_id,'role_code',v_role,'subject_id',v_subject);
end;
$function$;

grant execute on function public.playpro_profile_kyc_verified_for(uuid,text) to authenticated,service_role;
