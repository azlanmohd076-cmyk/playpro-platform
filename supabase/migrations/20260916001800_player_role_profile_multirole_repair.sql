-- PlayPro: Player profile creation must register the player role in the
-- canonical multi-role table. A user's legacy profiles.role is not a
-- single-role gate; one user may hold Player + Coach + Club Owner +
-- Organiser + Referee simultaneously.

CREATE OR REPLACE FUNCTION public.register_my_player(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_profile public.profiles%ROWTYPE;
  v_player public.players%ROWTYPE;
  v_dob date;
  v_position_code text := lower(trim(coalesce(p_payload->>'position','')));
  v_position public.player_position;
  v_foot public.preferred_foot;
  v_jersey integer;
  v_height integer;
  v_weight numeric;
  v_name text;
  v_preferred text;
  v_display text;
  v_visibility text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_profile FROM public.profiles WHERE id=v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002'; END IF;

  v_dob=NULLIF(p_payload->>'date_of_birth','')::date;
  v_jersey=NULLIF(p_payload->>'jersey_number','')::integer;
  v_height=NULLIF(p_payload->>'height_cm','')::integer;
  v_weight=NULLIF(p_payload->>'weight_kg','')::numeric;
  v_foot=NULLIF(lower(trim(p_payload->>'preferred_foot')),'')::public.preferred_foot;

  IF v_dob IS NULL OR v_dob>CURRENT_DATE THEN RAISE EXCEPTION 'Tarikh lahir yang sah diperlukan' USING ERRCODE='22023'; END IF;
  v_position=CASE
    WHEN v_position_code IN('gk','goalkeeper') THEN 'goalkeeper'::public.player_position
    WHEN v_position_code IN('cb','lb','rb','lwb','rwb','defender') THEN 'defender'::public.player_position
    WHEN v_position_code IN('dm','cm','am','lm','rm','midfielder') THEN 'midfielder'::public.player_position
    WHEN v_position_code IN('cf','st','ss','forward') THEN 'forward'::public.player_position
    ELSE NULL
  END;
  IF v_position IS NULL THEN RAISE EXCEPTION 'Posisi pemain diperlukan' USING ERRCODE='22023'; END IF;

  v_name=coalesce(nullif(trim(p_payload->>'full_name'),''),nullif(trim(v_profile.full_name),''),'Pemain Baru');
  v_preferred=nullif(trim(p_payload->>'preferred_name'),'');
  v_display=lower(trim(coalesce(p_payload->>'display_name_mode','preferred')));
  v_visibility=case when p_payload->>'profile_visibility'='private' then 'private' else 'public' end;
  IF v_display NOT IN ('legal','preferred') THEN v_display='preferred'; END IF;

  UPDATE public.profiles SET full_name=v_name, phone=coalesce(nullif(trim(p_payload->>'phone'),''),phone), updated_at=now() WHERE id=v_uid;

  INSERT INTO public.players(profile_id,full_name,preferred_name,date_of_birth,position,preferred_foot,jersey_number,height_cm,weight_kg,nationality,is_active,profile_visibility,verification_status,profile_completed_at,football_passport_no,display_name_mode)
  VALUES(v_uid,v_name,v_preferred,v_dob,v_position,v_foot,v_jersey,v_height,v_weight,coalesce(nullif(trim(p_payload->>'nationality'),''),'Malaysian'),true,v_visibility,'unverified',now(),NULL,v_display)
  ON CONFLICT(profile_id) DO UPDATE SET
    full_name=CASE WHEN public.players.verification_status='verified' THEN public.players.full_name ELSE excluded.full_name END,
    preferred_name=excluded.preferred_name,date_of_birth=excluded.date_of_birth,position=excluded.position,
    preferred_foot=coalesce(excluded.preferred_foot,public.players.preferred_foot),jersey_number=coalesce(excluded.jersey_number,public.players.jersey_number),
    height_cm=coalesce(excluded.height_cm,public.players.height_cm),weight_kg=coalesce(excluded.weight_kg,public.players.weight_kg),
    nationality=coalesce(excluded.nationality,public.players.nationality),profile_visibility=excluded.profile_visibility,
    display_name_mode=excluded.display_name_mode,profile_completed_at=now(),updated_at=now()
  RETURNING * INTO v_player;

  INSERT INTO public.profile_role_profiles(profile_id,role_code,subject_id,is_active)
  VALUES(v_uid,'player',v_player.id,true)
  ON CONFLICT(profile_id,role_code) DO UPDATE SET subject_id=EXCLUDED.subject_id,is_active=true,updated_at=now();

  INSERT INTO public.player_attribute_state(player_id) VALUES(v_player.id) ON CONFLICT(player_id) DO NOTHING;
  RETURN jsonb_build_object('ok',true,'player_id',v_player.id,'football_passport_no',v_player.football_passport_no,'verification_status',v_player.verification_status);
END;
$function$;
