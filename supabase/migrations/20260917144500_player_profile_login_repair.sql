BEGIN;

INSERT INTO public.player_attribute_state (player_id)
SELECT p.id
FROM public.players p
WHERE p.is_active = true
ON CONFLICT (player_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_player_profile(p_player_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_player record;
  v_is_owner boolean;
  v_is_follower boolean;
  v_follow_status text;
  v_attrs jsonb;
  v_followers bigint;
  v_display_name text;
BEGIN
  SELECT p.id,p.profile_id,p.full_name,p.preferred_name,p.display_name_mode,p.bio,p.date_of_birth,
         p.position,p.preferred_foot,p.photo_url,p.club_id,p.jersey_number,p.nationality,p.height_cm,
         p.weight_kg,p.football_passport_no,p.profile_visibility,p.verification_status,p.verified_at,
         c.name AS club_name,c.logo_url AS club_logo
  INTO v_player
  FROM public.players p
  LEFT JOIN public.clubs c ON c.id=p.club_id
  WHERE p.id=p_player_id AND p.is_active=true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND');
  END IF;

  v_is_owner:=v_player.profile_id=(SELECT auth.uid());

  SELECT pf.status INTO v_follow_status
  FROM public.player_follows pf
  WHERE pf.player_id=p_player_id
    AND pf.follower_profile_id=(SELECT auth.uid());

  v_is_follower:=v_follow_status='approved';

  SELECT count(*) INTO v_followers
  FROM public.player_follows
  WHERE player_id=p_player_id AND status='approved';

  v_display_name:=CASE WHEN v_player.display_name_mode='legal'
    THEN v_player.full_name ELSE coalesce(v_player.preferred_name,v_player.full_name) END;

  IF NOT (v_is_owner OR v_player.profile_visibility='public' OR v_is_follower) THEN
    RETURN jsonb_build_object(
      'ok',true,'restricted',true,
      'player',jsonb_build_object(
        'id',v_player.id,'profile_id',v_player.profile_id,
        'preferred_name',v_display_name,'photo_url',v_player.photo_url,
        'position',v_player.position,'verification_status',v_player.verification_status,
        'profile_visibility',v_player.profile_visibility,'follower_count',v_followers),
      'follow_status',coalesce(v_follow_status,'none'));
  END IF;

  SELECT to_jsonb(a)-'player_id'-'updated_at'
  INTO v_attrs
  FROM public.player_attribute_state a
  WHERE a.player_id=p_player_id;

  RETURN jsonb_build_object(
    'ok',true,'restricted',false,
    'player',jsonb_build_object(
      'id',v_player.id,'profile_id',v_player.profile_id,'full_name',v_player.full_name,
      'preferred_name',v_display_name,'raw_preferred_name',v_player.preferred_name,
      'display_name_mode',v_player.display_name_mode,'bio',v_player.bio,
      'age',extract(year from age(current_date,v_player.date_of_birth))::integer,
      'position',v_player.position,'preferred_foot',v_player.preferred_foot,
      'photo_url',v_player.photo_url,'club_id',v_player.club_id,
      'club_name',v_player.club_name,'club_logo',v_player.club_logo,
      'jersey_number',v_player.jersey_number,'nationality',v_player.nationality,
      'height_cm',v_player.height_cm,'weight_kg',v_player.weight_kg,
      'football_passport_no',v_player.football_passport_no,
      'verification_status',v_player.verification_status,'verified_at',v_player.verified_at,
      'profile_visibility',v_player.profile_visibility,'follower_count',v_followers),
    'attributes',coalesce(v_attrs,'{}'::jsonb),
    'follow_status',coalesce(v_follow_status,'none'));
END;
$$;

REVOKE ALL ON FUNCTION public.get_player_profile(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_player_profile(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_player_profile()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_player_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';
  END IF;

  SELECT p.id INTO v_player_id
  FROM public.players p
  WHERE p.profile_id=v_uid AND p.is_active=true
  LIMIT 1;

  IF v_player_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND');
  END IF;

  RETURN public.get_player_profile(v_player_id);
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_player_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_player_profile() TO authenticated;

COMMIT;
