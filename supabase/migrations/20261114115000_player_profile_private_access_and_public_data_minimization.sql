create or replace function public.get_player_profile(p_player_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_player record;
  v_is_owner boolean := false;
  v_is_follower boolean := false;
  v_follow_status text;
  v_attrs jsonb;
  v_followers bigint;
  v_display_name text;
  v_public_player jsonb;
  v_owner_player jsonb;
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
  into v_player
  from public.players p left join public.clubs c on c.id=p.club_id
  where p.id=p_player_id and p.is_active=true;

  if not found then return jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND'); end if;

  -- Explicit FALSE defaults prevent SQL NULL from bypassing private-profile checks.
  v_is_owner := coalesce(v_player.profile_id=(select auth.uid()),false);

  select pf.status into v_follow_status from public.player_follows pf
  where pf.player_id=p_player_id and pf.follower_profile_id=(select auth.uid());
  v_is_follower := coalesce(v_follow_status='approved',false);

  select count(*) into v_followers from public.player_follows
  where player_id=p_player_id and status='approved';

  v_display_name := case when v_player.display_name_mode='legal' then v_player.full_name
    else coalesce(nullif(btrim(v_player.preferred_name),''),v_player.full_name) end;

  if not (v_is_owner or v_player.profile_visibility='public' or v_is_follower) then
    return jsonb_build_object('ok',true,'restricted',true,
      'player',jsonb_build_object('id',v_player.id,'preferred_name',v_display_name,
        'photo_url',v_player.photo_url,'position',v_player.position,'follower_count',v_followers),
      'follow_status',coalesce(v_follow_status,'none'));
  end if;

  select to_jsonb(a)-'player_id'-'updated_at' into v_attrs
  from public.player_attribute_state a where a.player_id=p_player_id;

  -- Public and approved-follower responses contain no DOB, passport number,
  -- internal profile UUID, club UUID, or demo flags.
  v_public_player := jsonb_build_object(
    'id',v_player.id,'full_name',v_display_name,'preferred_name',v_display_name,
    'bio',v_player.bio,
    'age',case when v_player.date_of_birth is not null
      then extract(year from age(current_date,v_player.date_of_birth))::integer else null end,
    'position',v_player.position,'preferred_foot',v_player.preferred_foot,
    'photo_url',v_player.photo_url,'club_name',v_player.club_name,'club_logo',v_player.club_logo,
    'jersey_number',v_player.jersey_number,'nationality',v_player.nationality,
    'height_cm',v_player.height_cm,'weight_kg',v_player.weight_kg,
    'verification_status',v_player.verification_status,'verified_at',v_player.verified_at,
    'profile_visibility',v_player.profile_visibility,'follower_count',v_followers,
    'dna_technical',v_player.dna_technical,'dna_physical',v_player.dna_physical,
    'dna_mental',v_player.dna_mental,'dna_tactical',v_player.dna_tactical,
    'dna_overall',v_player.dna_overall,'dna_band',v_player.dna_band
  );

  if v_is_owner then
    v_owner_player := v_public_player || jsonb_build_object(
      'profile_id',v_player.profile_id,'raw_preferred_name',v_player.preferred_name,
      'display_name_mode',v_player.display_name_mode,'date_of_birth',v_player.date_of_birth,
      'football_passport_no',v_player.football_passport_no,'is_demo',v_player.is_demo,
      'demo_level',v_player.demo_level,'club_id',v_player.club_id
    );
    return jsonb_build_object('ok',true,'restricted',false,'player',v_owner_player,
      'attributes',coalesce(v_attrs,'{}'::jsonb),'follow_status',coalesce(v_follow_status,'none'));
  end if;

  return jsonb_build_object('ok',true,'restricted',false,'player',v_public_player,
    'attributes',coalesce(v_attrs,'{}'::jsonb),'follow_status',coalesce(v_follow_status,'none'));
end;
$function$;
