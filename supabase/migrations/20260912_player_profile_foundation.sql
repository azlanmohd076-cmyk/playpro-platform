-- PlayPro Player Profile Foundation — canonical migration
-- Applies the approved player flow without replacing the legacy assessment model.
-- NOTE: player_assessments remains historical assessment evidence; player_attribute_state is current presentation state.

BEGIN;

ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS preferred_name TEXT,
  ADD COLUMN IF NOT EXISTS bio TEXT,
  ADD COLUMN IF NOT EXISTS profile_visibility TEXT NOT NULL DEFAULT 'public',
  ADD COLUMN IF NOT EXISTS football_passport_no TEXT,
  ADD COLUMN IF NOT EXISTS verification_status TEXT NOT NULL DEFAULT 'unverified',
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS profile_completed_at TIMESTAMPTZ;

UPDATE public.players
SET preferred_name=COALESCE(NULLIF(trim(preferred_name),''),full_name),
    football_passport_no=COALESCE(football_passport_no,'PP-'||to_char(COALESCE(created_at,now()),'YYYY')||'-'||upper(substr(replace(id::text,'-',''),1,8)))
WHERE preferred_name IS NULL OR trim(preferred_name)='' OR football_passport_no IS NULL;

ALTER TABLE public.players
  DROP CONSTRAINT IF EXISTS players_profile_visibility_chk,
  ADD CONSTRAINT players_profile_visibility_chk CHECK(profile_visibility IN ('public','private')),
  DROP CONSTRAINT IF EXISTS players_verification_status_chk,
  ADD CONSTRAINT players_verification_status_chk CHECK(verification_status IN ('unverified','pending','verified','revoked')),
  DROP CONSTRAINT IF EXISTS players_bio_length_chk,
  ADD CONSTRAINT players_bio_length_chk CHECK(bio IS NULL OR char_length(bio)<=500);

CREATE UNIQUE INDEX IF NOT EXISTS uq_players_football_passport_no ON public.players(football_passport_no) WHERE football_passport_no IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_players_preferred_name ON public.players(preferred_name);
CREATE INDEX IF NOT EXISTS idx_players_visibility ON public.players(profile_visibility);
CREATE INDEX IF NOT EXISTS idx_players_verification ON public.players(verification_status);

CREATE TABLE IF NOT EXISTS public.player_follows(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), player_id UUID NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
 follower_profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
 status TEXT NOT NULL DEFAULT 'pending', requested_at TIMESTAMPTZ NOT NULL DEFAULT now(), responded_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT player_follows_status_chk CHECK(status IN('pending','approved','rejected','blocked'))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_player_follows_pair ON public.player_follows(player_id,follower_profile_id);
CREATE INDEX IF NOT EXISTS idx_player_follows_player_status ON public.player_follows(player_id,status);
CREATE INDEX IF NOT EXISTS idx_player_follows_follower ON public.player_follows(follower_profile_id,status);
ALTER TABLE public.player_follows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.player_follows FROM anon,authenticated;
GRANT SELECT ON public.player_follows TO authenticated;
DROP POLICY IF EXISTS "follow graph visible to participant" ON public.player_follows;
CREATE POLICY "follow graph visible to participant" ON public.player_follows FOR SELECT TO authenticated USING(
 follower_profile_id=(SELECT auth.uid()) OR EXISTS(SELECT 1 FROM public.players p WHERE p.id=player_follows.player_id AND p.profile_id=(SELECT auth.uid()))
);

CREATE TABLE IF NOT EXISTS public.player_posts(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), player_id UUID NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
 author_profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
 body TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT player_posts_body_chk CHECK(char_length(trim(body)) BETWEEN 1 AND 500)
);
CREATE INDEX IF NOT EXISTS idx_player_posts_player_created ON public.player_posts(player_id,created_at DESC);
ALTER TABLE public.player_posts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.player_posts FROM anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.player_posts TO authenticated;
DROP POLICY IF EXISTS "player wall read" ON public.player_posts;
CREATE POLICY "player wall read" ON public.player_posts FOR SELECT TO authenticated USING(
 author_profile_id=(SELECT auth.uid()) OR EXISTS(
  SELECT 1 FROM public.players p LEFT JOIN public.player_follows pf ON pf.player_id=p.id AND pf.follower_profile_id=(SELECT auth.uid()) AND pf.status='approved'
  WHERE p.id=player_posts.player_id AND(p.profile_visibility='public' OR p.profile_id=(SELECT auth.uid()) OR pf.id IS NOT NULL)
 )
);
DROP POLICY IF EXISTS "player can create wall post" ON public.player_posts;
CREATE POLICY "player can create wall post" ON public.player_posts FOR INSERT TO authenticated WITH CHECK(
 author_profile_id=(SELECT auth.uid()) AND EXISTS(SELECT 1 FROM public.players p WHERE p.id=player_posts.player_id AND p.profile_id=(SELECT auth.uid()))
);
DROP POLICY IF EXISTS "player can edit own wall post" ON public.player_posts;
CREATE POLICY "player can edit own wall post" ON public.player_posts FOR UPDATE TO authenticated USING(author_profile_id=(SELECT auth.uid())) WITH CHECK(author_profile_id=(SELECT auth.uid()));
DROP POLICY IF EXISTS "player can delete own wall post" ON public.player_posts;
CREATE POLICY "player can delete own wall post" ON public.player_posts FOR DELETE TO authenticated USING(author_profile_id=(SELECT auth.uid()));

CREATE TABLE IF NOT EXISTS public.player_attribute_state(
 player_id UUID PRIMARY KEY REFERENCES public.players(id) ON DELETE CASCADE,
 passing SMALLINT DEFAULT 0,dribbling SMALLINT DEFAULT 0,finishing SMALLINT DEFAULT 0,first_touch SMALLINT DEFAULT 0,tackling SMALLINT DEFAULT 0,heading SMALLINT DEFAULT 0,
 pace SMALLINT DEFAULT 0,stamina SMALLINT DEFAULT 0,strength SMALLINT DEFAULT 0,agility SMALLINT DEFAULT 0,leadership SMALLINT DEFAULT 0,composure SMALLINT DEFAULT 0,
 teamwork SMALLINT DEFAULT 0,work_rate SMALLINT DEFAULT 0,positioning SMALLINT DEFAULT 0,vision SMALLINT DEFAULT 0,decision_making SMALLINT DEFAULT 0,anticipation SMALLINT DEFAULT 0,
 source TEXT NOT NULL DEFAULT 'none',confidence SMALLINT NOT NULL DEFAULT 0,updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT player_attribute_state_range_chk CHECK(passing BETWEEN 0 AND 20 AND dribbling BETWEEN 0 AND 20 AND finishing BETWEEN 0 AND 20 AND first_touch BETWEEN 0 AND 20 AND tackling BETWEEN 0 AND 20 AND heading BETWEEN 0 AND 20 AND pace BETWEEN 0 AND 20 AND stamina BETWEEN 0 AND 20 AND strength BETWEEN 0 AND 20 AND agility BETWEEN 0 AND 20 AND leadership BETWEEN 0 AND 20 AND composure BETWEEN 0 AND 20 AND teamwork BETWEEN 0 AND 20 AND work_rate BETWEEN 0 AND 20 AND positioning BETWEEN 0 AND 20 AND vision BETWEEN 0 AND 20 AND decision_making BETWEEN 0 AND 20 AND anticipation BETWEEN 0 AND 20),
 CONSTRAINT player_attribute_state_source_chk CHECK(source IN('none','coach_assessment','organic','combined')),
 CONSTRAINT player_attribute_state_confidence_chk CHECK(confidence BETWEEN 0 AND 100)
);
ALTER TABLE public.player_attribute_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.player_attribute_state FROM anon,authenticated;
GRANT SELECT ON public.player_attribute_state TO authenticated;
DROP POLICY IF EXISTS "player attribute owner read" ON public.player_attribute_state;
CREATE POLICY "player attribute owner read" ON public.player_attribute_state FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.players p WHERE p.id=player_attribute_state.player_id AND p.profile_id=(SELECT auth.uid())));

CREATE OR REPLACE FUNCTION public.register_my_player(p_payload JSONB) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid UUID=(SELECT auth.uid());v_profile public.profiles%ROWTYPE;v_player public.players%ROWTYPE;v_dob DATE;v_position_code TEXT=lower(trim(coalesce(p_payload->>'position','')));v_position public.player_position;v_foot public.preferred_foot;v_jersey INTEGER;v_height INTEGER;v_weight NUMERIC;v_name TEXT;v_preferred TEXT;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='42501';END IF;
 SELECT * INTO v_profile FROM public.profiles WHERE id=v_uid;
 IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found' USING ERRCODE='P0002';END IF;
 IF v_profile.role<>'player'::public.user_role THEN RAISE EXCEPTION 'Only player accounts can create a player profile' USING ERRCODE='42501';END IF;
 v_dob=NULLIF(p_payload->>'date_of_birth','')::DATE;v_jersey=NULLIF(p_payload->>'jersey_number','')::INTEGER;v_height=NULLIF(p_payload->>'height_cm','')::INTEGER;v_weight=NULLIF(p_payload->>'weight_kg','')::NUMERIC;v_foot=NULLIF(lower(trim(p_payload->>'preferred_foot')),'')::public.preferred_foot;
 IF v_dob IS NULL OR v_dob>CURRENT_DATE THEN RAISE EXCEPTION 'Tarikh lahir yang sah diperlukan' USING ERRCODE='22023';END IF;
 v_position=CASE WHEN v_position_code IN('gk','goalkeeper') THEN 'goalkeeper'::public.player_position WHEN v_position_code IN('cb','lb','rb','lwb','rwb','defender') THEN 'defender'::public.player_position WHEN v_position_code IN('dm','cm','am','lm','rm','midfielder') THEN 'midfielder'::public.player_position WHEN v_position_code IN('cf','st','ss','forward') THEN 'forward'::public.player_position ELSE NULL END;
 IF v_position IS NULL THEN RAISE EXCEPTION 'Posisi pemain diperlukan' USING ERRCODE='22023';END IF;
 v_name=coalesce(nullif(trim(v_profile.full_name),''),'Pemain Baru');v_preferred=coalesce(nullif(trim(p_payload->>'preferred_name'),''),v_name);
 UPDATE public.profiles SET phone=coalesce(nullif(trim(p_payload->>'phone'),''),phone),updated_at=now() WHERE id=v_uid;
 INSERT INTO public.players(profile_id,full_name,preferred_name,date_of_birth,position,preferred_foot,jersey_number,height_cm,weight_kg,nationality,is_active,profile_visibility,verification_status,profile_completed_at,football_passport_no)
 VALUES(v_uid,v_name,v_preferred,v_dob,v_position,v_foot,v_jersey,v_height,v_weight,coalesce(nullif(trim(p_payload->>'nationality'),''),'Malaysian'),true,case when p_payload->>'profile_visibility'='private' then 'private' else 'public' end,'unverified',now(),'PP-'||to_char(now(),'YYYY')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)))
 ON CONFLICT(profile_id) DO UPDATE SET full_name=excluded.full_name,preferred_name=excluded.preferred_name,date_of_birth=excluded.date_of_birth,position=excluded.position,preferred_foot=coalesce(excluded.preferred_foot,public.players.preferred_foot),jersey_number=coalesce(excluded.jersey_number,public.players.jersey_number),height_cm=coalesce(excluded.height_cm,public.players.height_cm),weight_kg=coalesce(excluded.weight_kg,public.players.weight_kg),nationality=coalesce(excluded.nationality,public.players.nationality),profile_visibility=excluded.profile_visibility,profile_completed_at=now(),updated_at=now()
 RETURNING * INTO v_player;
 INSERT INTO public.player_attribute_state(player_id) VALUES(v_player.id) ON CONFLICT(player_id) DO NOTHING;
 RETURN jsonb_build_object('ok',true,'player_id',v_player.id,'football_passport_no',v_player.football_passport_no,'verification_status',v_player.verification_status);
END;$$;
REVOKE ALL ON FUNCTION public.register_my_player(JSONB) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.register_my_player(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_my_player_profile(p_payload JSONB) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid UUID=(SELECT auth.uid());v_player_id UUID;v_position_code TEXT;v_position public.player_position;v_foot public.preferred_foot;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';END IF;SELECT id INTO v_player_id FROM public.players WHERE profile_id=v_uid LIMIT 1;IF v_player_id IS NULL THEN RAISE EXCEPTION 'Player profile not found';END IF;
 v_position_code=lower(trim(coalesce(p_payload->>'position','')));IF v_position_code<>'' THEN v_position=CASE WHEN v_position_code IN('gk','goalkeeper') THEN 'goalkeeper'::public.player_position WHEN v_position_code IN('cb','lb','rb','lwb','rwb','defender') THEN 'defender'::public.player_position WHEN v_position_code IN('dm','cm','am','lm','rm','midfielder') THEN 'midfielder'::public.player_position WHEN v_position_code IN('cf','st','ss','forward') THEN 'forward'::public.player_position ELSE NULL END;IF v_position IS NULL THEN RAISE EXCEPTION 'Invalid position' USING ERRCODE='22023';END IF;END IF;
 UPDATE public.players SET preferred_name=coalesce(nullif(trim(p_payload->>'preferred_name'),''),preferred_name),bio=case when p_payload ? 'bio' then nullif(trim(p_payload->>'bio'),'') else bio end,nationality=coalesce(nullif(trim(p_payload->>'nationality'),''),nationality),position=coalesce(v_position,position),preferred_foot=coalesce(case when nullif(p_payload->>'preferred_foot','') is not null then lower(trim(p_payload->>'preferred_foot'))::public.preferred_foot end,preferred_foot),jersey_number=case when p_payload ? 'jersey_number' then nullif(p_payload->>'jersey_number','')::integer else jersey_number end,height_cm=case when p_payload ? 'height_cm' then nullif(p_payload->>'height_cm','')::numeric else height_cm end,weight_kg=case when p_payload ? 'weight_kg' then nullif(p_payload->>'weight_kg','')::numeric else weight_kg end,photo_url=case when p_payload ? 'photo_url' then nullif(trim(p_payload->>'photo_url'),'') else photo_url end,profile_visibility=case when p_payload->>'profile_visibility' in('public','private') then p_payload->>'profile_visibility' else profile_visibility end,updated_at=now() WHERE id=v_player_id;
 RETURN public.get_player_profile(v_player_id);
END;$$;
REVOKE ALL ON FUNCTION public.update_my_player_profile(JSONB) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.update_my_player_profile(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_player_profile(p_player_id UUID) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_player RECORD;v_follow_status TEXT;v_followers BIGINT;v_attrs JSONB;v_owner BOOLEAN;v_follower BOOLEAN;
BEGIN
 SELECT p.id,p.profile_id,p.full_name,p.preferred_name,p.bio,p.date_of_birth,p.position,p.preferred_foot,p.photo_url,p.club_id,p.jersey_number,p.nationality,p.height_cm,p.weight_kg,p.football_passport_no,p.profile_visibility,p.verification_status,p.verified_at,c.name club_name,c.logo_url club_logo INTO v_player FROM public.players p LEFT JOIN public.clubs c ON c.id=p.club_id WHERE p.id=p_player_id AND p.is_active=true;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND');END IF;
 v_owner=v_player.profile_id=(SELECT auth.uid());SELECT pf.status INTO v_follow_status FROM public.player_follows pf WHERE pf.player_id=p_player_id AND pf.follower_profile_id=(SELECT auth.uid());v_follower=v_follow_status='approved';SELECT count(*) INTO v_followers FROM public.player_follows WHERE player_id=p_player_id AND status='approved';
 IF NOT(v_owner OR v_player.profile_visibility='public' OR v_follower) THEN RETURN jsonb_build_object('ok',true,'restricted',true,'player',jsonb_build_object('id',v_player.id,'preferred_name',coalesce(v_player.preferred_name,v_player.full_name),'photo_url',v_player.photo_url,'position',v_player.position,'verification_status',v_player.verification_status,'profile_visibility',v_player.profile_visibility,'follower_count',v_followers),'follow_status',coalesce(v_follow_status,'none'));END IF;
 SELECT to_jsonb(a)-'player_id'-'updated_at' INTO v_attrs FROM public.player_attribute_state a WHERE a.player_id=p_player_id;
 RETURN jsonb_build_object('ok',true,'restricted',false,'player',jsonb_build_object('id',v_player.id,'full_name',v_player.full_name,'preferred_name',coalesce(v_player.preferred_name,v_player.full_name),'bio',v_player.bio,'age',extract(year from age(current_date,v_player.date_of_birth))::integer,'position',v_player.position,'preferred_foot',v_player.preferred_foot,'photo_url',v_player.photo_url,'club_id',v_player.club_id,'club_name',v_player.club_name,'club_logo',v_player.club_logo,'jersey_number',v_player.jersey_number,'nationality',v_player.nationality,'height_cm',v_player.height_cm,'weight_kg',v_player.weight_kg,'football_passport_no',v_player.football_passport_no,'verification_status',v_player.verification_status,'verified_at',v_player.verified_at,'profile_visibility',v_player.profile_visibility,'follower_count',v_followers),'attributes',coalesce(v_attrs,'{}'::jsonb),'follow_status',coalesce(v_follow_status,'none'));
END;$$;
REVOKE ALL ON FUNCTION public.get_player_profile(UUID) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.get_player_profile(UUID) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.follow_player(p_player_id UUID) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid UUID=(SELECT auth.uid());v_owner UUID;v_visibility TEXT;v_status TEXT;
BEGIN IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';END IF;SELECT profile_id,profile_visibility INTO v_owner,v_visibility FROM public.players WHERE id=p_player_id AND is_active=true;IF v_owner IS NULL THEN RAISE EXCEPTION 'Player not found';END IF;IF v_owner=v_uid THEN RAISE EXCEPTION 'You cannot follow yourself';END IF;v_status=case when v_visibility='private' then 'pending' else 'approved' end;INSERT INTO public.player_follows(player_id,follower_profile_id,status,responded_at) VALUES(p_player_id,v_uid,v_status,case when v_status='approved' then now() else null end) ON CONFLICT(player_id,follower_profile_id) DO UPDATE SET status=excluded.status,requested_at=now(),responded_at=excluded.responded_at,updated_at=now();RETURN jsonb_build_object('ok',true,'status',v_status);END;$$;
REVOKE ALL ON FUNCTION public.follow_player(UUID) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.follow_player(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.unfollow_player(p_player_id UUID) RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ DELETE FROM public.player_follows WHERE player_id=$1 AND follower_profile_id=(SELECT auth.uid()); SELECT true; $$;
REVOKE ALL ON FUNCTION public.unfollow_player(UUID) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.unfollow_player(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.respond_player_follow(p_follow_id UUID,p_decision TEXT) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid UUID=(SELECT auth.uid());v_player UUID;
BEGIN IF p_decision NOT IN('approved','rejected','blocked') THEN RAISE EXCEPTION 'Invalid follow decision';END IF;SELECT pf.player_id INTO v_player FROM public.player_follows pf JOIN public.players p ON p.id=pf.player_id WHERE pf.id=p_follow_id AND p.profile_id=v_uid;IF v_player IS NULL THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE='42501';END IF;UPDATE public.player_follows SET status=p_decision,responded_at=now(),updated_at=now() WHERE id=p_follow_id;RETURN jsonb_build_object('ok',true,'status',p_decision);END;$$;
REVOKE ALL ON FUNCTION public.respond_player_follow(UUID,TEXT) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.respond_player_follow(UUID,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_player_profile_settings(p_visibility TEXT) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_player UUID;BEGIN IF p_visibility NOT IN('public','private') THEN RAISE EXCEPTION 'Invalid visibility';END IF;SELECT id INTO v_player FROM public.players WHERE profile_id=(SELECT auth.uid()) LIMIT 1;IF v_player IS NULL THEN RAISE EXCEPTION 'Player profile not found';END IF;UPDATE public.players SET profile_visibility=p_visibility,updated_at=now() WHERE id=v_player;RETURN jsonb_build_object('ok',true,'visibility',p_visibility);END;$$;
REVOKE ALL ON FUNCTION public.set_player_profile_settings(TEXT) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.set_player_profile_settings(TEXT) TO authenticated;

COMMIT;
