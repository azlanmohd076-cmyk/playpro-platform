-- Keep the privacy-aware profile RPC aligned with the canonical player data model.
-- Includes DNA aggregate fields and the canonical player_attribute_state JSON payload.
-- It still returns only the limited player summary for private profiles viewed by non-owners.

create or replace function public.get_player_profile(p_player_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_player record;
  v_is_owner boolean;
  v_is_follower boolean;
  v_follow_status text;
  v_attrs jsonb;
  v_followers bigint;
  v_display_name text;
begin
  select
    p.id,p.profile_id,p.full_name,p.preferred_name,p.display_name_mode,p.bio,
    p.date_of_birth,p.position,p.preferred_foot,p.photo_url,p.club_id,p.jersey_number,
    p.nationality,p.height_cm,p.weight_kg,p.football_passport_no,p.profile_visibility,
    p.verification_status,p.verified_at,
    p.dna_technical,p.dna_physical,p.dna_mental,p.dna_tactical,p.dna_overall,p.dna_band,
    c.name as club_name,c.logo_url as club_logo
  into v_player
  from public.players p
  left join public.clubs c on c.id=p.club_id
  where p.id=p_player_id and p.is_active=true;

  if not found then
    return jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND');
  end if;

  v_is_owner := v_player.profile_id=(select auth.uid());
  select pf.status into v_follow_status
  from public.player_follows pf
  where pf.player_id=p_player_id and pf.follower_profile_id=(select auth.uid());
  v_is_follower := v_follow_status='approved';
  select count(*) into v_followers from public.player_follows
  where player_id=p_player_id and status='approved';

  v_display_name := case when v_player.display_name_mode='legal'
    then v_player.full_name else coalesce(v_player.preferred_name,v_player.full_name) end;

  if not (v_is_owner or v_player.profile_visibility='public' or v_is_follower) then
    return jsonb_build_object(
      'ok',true,'restricted',true,
      'player',jsonb_build_object(
        'id',v_player.id,'profile_id',v_player.profile_id,
        'preferred_name',v_display_name,'photo_url',v_player.photo_url,
        'position',v_player.position,'verification_status',v_player.verification_status,
        'profile_visibility',v_player.profile_visibility,'follower_count',v_followers
      ),
      'follow_status',coalesce(v_follow_status,'none')
    );
  end if;

  select to_jsonb(a)-'player_id'-'updated_at' into v_attrs
  from public.player_attribute_state a where a.player_id=p_player_id;

  return jsonb_build_object(
    'ok',true,'restricted',false,
    'player',jsonb_build_object(
      'id',v_player.id,'profile_id',v_player.profile_id,
      'full_name',v_player.full_name,'preferred_name',v_display_name,
      'raw_preferred_name',v_player.preferred_name,'display_name_mode',v_player.display_name_mode,
      'bio',v_player.bio,'age',extract(year from age(current_date,v_player.date_of_birth))::integer,
      'date_of_birth',v_player.date_of_birth,'position',v_player.position,
      'preferred_foot',v_player.preferred_foot,'photo_url',v_player.photo_url,
      'club_id',v_player.club_id,'club_name',v_player.club_name,'club_logo',v_player.club_logo,
      'jersey_number',v_player.jersey_number,'nationality',v_player.nationality,
      'height_cm',v_player.height_cm,'weight_kg',v_player.weight_kg,
      'football_passport_no',v_player.football_passport_no,
      'verification_status',v_player.verification_status,'verified_at',v_player.verified_at,
      'profile_visibility',v_player.profile_visibility,'follower_count',v_followers,
      'dna_technical',v_player.dna_technical,'dna_physical',v_player.dna_physical,
      'dna_mental',v_player.dna_mental,'dna_tactical',v_player.dna_tactical,
      'dna_overall',v_player.dna_overall,'dna_band',v_player.dna_band
    ),
    'attributes',coalesce(v_attrs,'{}'::jsonb),
    'follow_status',coalesce(v_follow_status,'none')
  );
end;
$function$;
