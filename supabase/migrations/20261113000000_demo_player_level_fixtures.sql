-- Demo fixtures only: keep demo DNA separate from official coach assessment and live player ratings.
ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS demo_level text;
ALTER TABLE public.players DROP CONSTRAINT IF EXISTS players_demo_level_check;
ALTER TABLE public.players ADD CONSTRAINT players_demo_level_check
  CHECK (demo_level IS NULL OR demo_level IN ('beginner','novice','intermediate','advanced','pro'));
ALTER TABLE public.player_attribute_state DROP CONSTRAINT IF EXISTS player_attribute_state_source_chk;
ALTER TABLE public.player_attribute_state ADD CONSTRAINT player_attribute_state_source_chk
  CHECK (source IN ('none','coach_assessment','organic','combined','demo_seed'));

UPDATE public.players p
SET is_demo=true, demo_level=v.demo_level,
    dna_technical=NULL,dna_physical=NULL,dna_mental=NULL,dna_tactical=NULL,
    dna_goalkeeper=NULL,dna_overall=NULL,dna_band=NULL,dna_computed_at=NULL,updated_at=now()
FROM (VALUES
 ('56e4eb06-69c0-4ea1-a318-4f913b6aaa5a'::uuid,'beginner'),
 ('cd4003df-bfcf-497f-8bcd-69a1ae68b33a'::uuid,'novice'),
 ('7da92d4b-79da-4446-8ee4-e0fea867ea71'::uuid,'intermediate'),
 ('95d638ed-c94e-456a-9c6a-2857006921f7'::uuid,'advanced'),
 ('9b6270c4-98af-4466-bee3-549bafbaf1cf'::uuid,'pro')
) v(player_id,demo_level) WHERE p.id=v.player_id;

UPDATE public.player_attribute_state a
SET passing=v.passing,dribbling=v.dribbling,finishing=v.finishing,first_touch=v.first_touch,
    tackling=v.tackling,heading=v.heading,pace=v.pace,stamina=v.stamina,strength=v.strength,
    agility=v.agility,leadership=v.leadership,composure=v.composure,teamwork=v.teamwork,
    work_rate=v.work_rate,positioning=v.positioning,vision=v.vision,
    decision_making=v.decision_making,anticipation=v.anticipation,
    source='demo_seed',confidence=0,updated_at=now()
FROM (VALUES
 ('56e4eb06-69c0-4ea1-a318-4f913b6aaa5a'::uuid,3,2,2,3,3,2,4,3,3,4,2,2,3,4,2,2,2,2),
 ('cd4003df-bfcf-497f-8bcd-69a1ae68b33a'::uuid,7,6,5,7,6,5,8,7,7,8,6,6,7,8,6,6,6,7),
 ('7da92d4b-79da-4446-8ee4-e0fea867ea71'::uuid,12,11,10,12,11,9,12,12,11,12,10,11,12,12,11,12,11,12),
 ('95d638ed-c94e-456a-9c6a-2857006921f7'::uuid,15,14,13,15,16,14,15,16,15,14,14,15,16,15,16,15,15,16),
 ('9b6270c4-98af-4466-bee3-549bafbaf1cf'::uuid,19,18,18,19,17,18,19,19,18,19,18,19,20,19,18,19,19,20)
) v(player_id,passing,dribbling,finishing,first_touch,tackling,heading,pace,stamina,strength,agility,leadership,composure,teamwork,work_rate,positioning,vision,decision_making,anticipation)
WHERE a.player_id=v.player_id;

CREATE OR REPLACE FUNCTION public.get_player_profile(p_player_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_player record; v_is_owner boolean; v_is_follower boolean; v_follow_status text;
  v_attrs jsonb; v_followers bigint; v_display_name text;
BEGIN
  SELECT p.id,p.profile_id,p.full_name,p.preferred_name,p.display_name_mode,p.bio,
    p.date_of_birth,p.position,p.preferred_foot,p.photo_url,p.club_id,p.jersey_number,
    p.nationality,p.height_cm,p.weight_kg,p.football_passport_no,p.profile_visibility,
    p.verification_status,p.verified_at,p.dna_technical,p.dna_physical,p.dna_mental,
    p.dna_tactical,p.dna_overall,p.dna_band,p.is_demo,p.demo_level,
    c.name AS club_name,c.logo_url AS club_logo
  INTO v_player FROM public.players p LEFT JOIN public.clubs c ON c.id=p.club_id
  WHERE p.id=p_player_id AND p.is_active=true;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND'); END IF;
  v_is_owner := v_player.profile_id=(SELECT auth.uid());
  SELECT pf.status INTO v_follow_status FROM public.player_follows pf
    WHERE pf.player_id=p_player_id AND pf.follower_profile_id=(SELECT auth.uid());
  v_is_follower := v_follow_status='approved';
  SELECT count(*) INTO v_followers FROM public.player_follows
    WHERE player_id=p_player_id AND status='approved';
  v_display_name := CASE WHEN v_player.display_name_mode='legal'
    THEN v_player.full_name ELSE coalesce(v_player.preferred_name,v_player.full_name) END;
  IF NOT (v_is_owner OR v_player.profile_visibility='public' OR v_is_follower) THEN
    RETURN jsonb_build_object('ok',true,'restricted',true,'player',jsonb_build_object(
      'id',v_player.id,'profile_id',v_player.profile_id,'preferred_name',v_display_name,
      'photo_url',v_player.photo_url,'position',v_player.position,
      'verification_status',v_player.verification_status,
      'profile_visibility',v_player.profile_visibility,'follower_count',v_followers),
      'follow_status',coalesce(v_follow_status,'none'));
  END IF;
  SELECT to_jsonb(a)-'player_id'-'updated_at' INTO v_attrs
    FROM public.player_attribute_state a WHERE a.player_id=p_player_id;
  RETURN jsonb_build_object('ok',true,'restricted',false,
    'player',jsonb_build_object(
      'id',v_player.id,'profile_id',v_player.profile_id,'full_name',v_player.full_name,
      'preferred_name',v_display_name,'raw_preferred_name',v_player.preferred_name,
      'display_name_mode',v_player.display_name_mode,'bio',v_player.bio,
      'age',extract(year from age(current_date,v_player.date_of_birth))::integer,
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
      'dna_overall',v_player.dna_overall,'dna_band',v_player.dna_band,
      'is_demo',v_player.is_demo,'demo_level',v_player.demo_level),
    'attributes',coalesce(v_attrs,'{}'::jsonb),
    'follow_status',coalesce(v_follow_status,'none'));
END;
$function$;
