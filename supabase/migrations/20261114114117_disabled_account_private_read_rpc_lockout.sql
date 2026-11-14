create or replace function public.get_my_coach_profile()
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_uid uuid := (select auth.uid()); v_profile jsonb;
begin
  perform public.playpro_require_active_account();
  if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  select to_jsonb(c) into v_profile from public.coaches c where c.profile_id=v_uid limit 1;
  return v_profile;
end;
$function$;

create or replace function public.get_my_player_follow_requests()
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_uid uuid := (select auth.uid()); v_player_id uuid; v_requests jsonb;
begin
  perform public.playpro_require_active_account();
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select p.id into v_player_id from public.players p where p.profile_id=v_uid and p.is_active=true limit 1;
  if v_player_id is null then return jsonb_build_object('ok',true,'requests','[]'::jsonb); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',pf.id,'follower_profile_id',pf.follower_profile_id,
    'follower_name',coalesce(nullif(btrim(fp.preferred_name),''),nullif(btrim(fp.full_name),''),pr.full_name,'Pengguna PlayPro'),
    'requested_at',pf.requested_at
  ) order by pf.requested_at desc),'[]'::jsonb)
  into v_requests
  from public.player_follows pf
  join public.profiles pr on pr.id=pf.follower_profile_id
  left join public.players fp on fp.profile_id=pr.id and fp.is_active=true
  where pf.player_id=v_player_id and pf.status='pending';
  return jsonb_build_object('ok',true,'requests',v_requests);
end;
$function$;

create or replace function public.get_my_player_kyc_status()
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_uid uuid := (select auth.uid()); v_k public.identity_verifications%rowtype; v_p public.players%rowtype;
begin
  perform public.playpro_require_active_account();
  if v_uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into v_p from public.players where profile_id=v_uid and is_active=true limit 1;
  if not found then return jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND'); end if;
  select * into v_k from public.identity_verifications where profile_id=v_uid and subject_type='player' order by created_at desc limit 1;
  return jsonb_build_object(
    'ok',true,'verification_status',v_p.verification_status,'football_passport_no',v_p.football_passport_no,
    'kyc_status',coalesce(v_k.status,'not_submitted'),'kyc_id',v_k.id,'id_type',v_k.id_type,
    'provider',v_k.provider,'provider_status',v_k.provider_status,'match_status',v_k.match_status,
    'match_score',v_k.match_score,'submitted_at',v_k.submitted_at,'processed_at',v_k.processed_at,
    'reviewed_at',v_k.reviewed_at,'reviewer_note',v_k.reviewer_note
  );
end;
$function$;

create or replace function public.get_my_role_profiles()
returns table(role_code text,subject_id uuid,is_active boolean)
language plpgsql stable security definer set search_path = ''
as $function$
begin
  perform public.playpro_require_active_account();
  return query select r.role_code,r.subject_id,r.is_active
    from public.profile_role_profiles r
    where r.profile_id=(select auth.uid())
    order by r.created_at asc,r.role_code asc;
end;
$function$;

create or replace function public.get_player_profile(p_player_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_player record; v_is_owner boolean; v_is_follower boolean; v_follow_status text;
  v_attrs jsonb; v_followers bigint; v_display_name text;
begin
  if (select auth.uid()) is not null and not public.playpro_account_is_active() then
    raise exception 'ACCOUNT_DISABLED_OR_INACTIVE' using errcode='42501';
  end if;
  select p.id,p.profile_id,p.full_name,p.preferred_name,p.display_name_mode,p.bio,
    p.date_of_birth,p.position,p.preferred_foot,p.photo_url,p.club_id,p.jersey_number,
    p.nationality,p.height_cm,p.weight_kg,p.football_passport_no,p.profile_visibility,
    p.verification_status,p.verified_at,p.dna_technical,p.dna_physical,p.dna_mental,
    p.dna_tactical,p.dna_overall,p.dna_band,p.is_demo,p.demo_level,
    c.name as club_name,c.logo_url as club_logo
  into v_player from public.players p left join public.clubs c on c.id=p.club_id
  where p.id=p_player_id and p.is_active=true;
  if not found then return jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND'); end if;
  v_is_owner := v_player.profile_id=(select auth.uid());
  select pf.status into v_follow_status from public.player_follows pf
    where pf.player_id=p_player_id and pf.follower_profile_id=(select auth.uid());
  v_is_follower := v_follow_status='approved';
  select count(*) into v_followers from public.player_follows where player_id=p_player_id and status='approved';
  v_display_name := case when v_player.display_name_mode='legal' then v_player.full_name else coalesce(v_player.preferred_name,v_player.full_name) end;
  if not (v_is_owner or v_player.profile_visibility='public' or v_is_follower) then
    return jsonb_build_object('ok',true,'restricted',true,'player',jsonb_build_object(
      'id',v_player.id,'profile_id',v_player.profile_id,'preferred_name',v_display_name,
      'photo_url',v_player.photo_url,'position',v_player.position,'verification_status',v_player.verification_status,
      'profile_visibility',v_player.profile_visibility,'follower_count',v_followers
    ),'follow_status',coalesce(v_follow_status,'none'));
  end if;
  select to_jsonb(a)-'player_id'-'updated_at' into v_attrs from public.player_attribute_state a where a.player_id=p_player_id;
  return jsonb_build_object('ok',true,'restricted',false,'player',jsonb_build_object(
    'id',v_player.id,'profile_id',v_player.profile_id,'full_name',v_player.full_name,
    'preferred_name',v_display_name,'raw_preferred_name',v_player.preferred_name,
    'display_name_mode',v_player.display_name_mode,'bio',v_player.bio,
    'age',extract(year from age(current_date,v_player.date_of_birth))::integer,
    'date_of_birth',v_player.date_of_birth,'position',v_player.position,'preferred_foot',v_player.preferred_foot,
    'photo_url',v_player.photo_url,'club_id',v_player.club_id,'club_name',v_player.club_name,'club_logo',v_player.club_logo,
    'jersey_number',v_player.jersey_number,'nationality',v_player.nationality,'height_cm',v_player.height_cm,
    'weight_kg',v_player.weight_kg,'football_passport_no',v_player.football_passport_no,
    'verification_status',v_player.verification_status,'verified_at',v_player.verified_at,
    'profile_visibility',v_player.profile_visibility,'follower_count',v_followers,
    'dna_technical',v_player.dna_technical,'dna_physical',v_player.dna_physical,
    'dna_mental',v_player.dna_mental,'dna_tactical',v_player.dna_tactical,
    'dna_overall',v_player.dna_overall,'dna_band',v_player.dna_band,
    'is_demo',v_player.is_demo,'demo_level',v_player.demo_level
  ),'attributes',coalesce(v_attrs,'{}'::jsonb),'follow_status',coalesce(v_follow_status,'none'));
end;
$function$;

create or replace function public.get_player_match_history(p_player_id uuid,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_uid uuid := (select auth.uid()); v_owner uuid; v_visibility text;
begin
  if v_uid is not null and not public.playpro_account_is_active() then
    raise exception 'ACCOUNT_DISABLED_OR_INACTIVE' using errcode='42501';
  end if;
  select p.profile_id,p.profile_visibility into v_owner,v_visibility
  from public.players p where p.id=p_player_id and p.is_active=true;
  if not found then return '[]'::jsonb; end if;
  if coalesce(v_visibility,'private')='private' and (
    v_uid is null or (v_uid<>v_owner and not exists (
      select 1 from public.player_follows pf where pf.player_id=p_player_id
      and pf.follower_profile_id=v_uid and pf.status='approved'
    ))
  ) then raise exception 'Profile private' using errcode='42501'; end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.match_date desc),'[]'::jsonb)
    from (
      select f.id as fixture_id,f.match_date,f.round_name,f.home_club_id,f.away_club_id,
        hc.name as home_club,ac.name as away_club,mr.home_goals,mr.away_goals,
        pms.minutes_played,pms.goals,pms.assists,pms.yellow_cards,pms.red_cards,pms.started
      from public.player_match_stats pms
      join public.fixtures f on f.id=pms.fixture_id
      join public.match_results mr on mr.fixture_id=f.id and mr.is_official=true
      left join public.clubs hc on hc.id=f.home_club_id
      left join public.clubs ac on ac.id=f.away_club_id
      where pms.player_id=p_player_id
      order by f.match_date desc nulls last
      limit least(greatest(coalesce(p_limit,50),1),200)
    ) x
  );
end;
$function$;
