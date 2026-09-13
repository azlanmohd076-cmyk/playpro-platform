-- PLAYPRO CLUB ECOSYSTEM FOUNDATION
-- Live-applied on playpro2. Source of truth for Club -> Team/Squad -> Venue -> Training -> Match Room.
-- This migration is additive. No player/coach legacy tables are replaced.

BEGIN;

ALTER TABLE public.clubs
  ADD COLUMN IF NOT EXISTS owner_profile_id uuid,
  ADD COLUMN IF NOT EXISTS club_code text,
  ADD COLUMN IF NOT EXISTS slug text,
  ADD COLUMN IF NOT EXISTS club_type text,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS ros_registration_no text,
  ADD COLUMN IF NOT EXISTS contact_phone text,
  ADD COLUMN IF NOT EXISTS whatsapp_phone text,
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS state text,
  ADD COLUMN IF NOT EXISTS country text DEFAULT 'Malaysia',
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS verified_by uuid,
  ADD COLUMN IF NOT EXISTS verification_note text,
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public',
  ADD COLUMN IF NOT EXISTS primary_training_venue_id uuid;

CREATE SEQUENCE IF NOT EXISTS public.club_code_seq START WITH 1 INCREMENT BY 1;
UPDATE public.clubs SET club_code='PP-CLB-'||lpad(nextval('public.club_code_seq')::text,6,'0') WHERE club_code IS NULL;
UPDATE public.clubs SET owner_profile_id=admin_id WHERE owner_profile_id IS NULL AND admin_id IS NOT NULL;
UPDATE public.clubs SET club_type='grassroots_academy' WHERE club_type IS NULL;
UPDATE public.clubs SET slug=lower(regexp_replace(name,'[^a-zA-Z0-9]+','-','g'))||'-'||substring(id::text,1,8) WHERE slug IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS clubs_club_code_uq ON public.clubs(club_code);
CREATE UNIQUE INDEX IF NOT EXISTS clubs_slug_uq ON public.clubs(slug) WHERE slug IS NOT NULL;
CREATE INDEX IF NOT EXISTS clubs_owner_profile_idx ON public.clubs(owner_profile_id);
CREATE INDEX IF NOT EXISTS clubs_verification_idx ON public.clubs(verification_status);

DO $$ BEGIN
  ALTER TABLE public.clubs ADD CONSTRAINT clubs_owner_profile_fk FOREIGN KEY(owner_profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.clubs ADD CONSTRAINT clubs_verified_by_fk FOREIGN KEY(verified_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.clubs ADD CONSTRAINT clubs_type_chk CHECK(club_type IS NULL OR club_type IN ('professional','semi_professional','amateur','grassroots_academy','educational_institution','government_agency','corporate','community','womens_club','futsal','development','other'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.clubs ADD CONSTRAINT clubs_verification_status_chk CHECK(verification_status IN ('pending','under_review','verified','rejected','suspended'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.clubs ADD CONSTRAINT clubs_visibility_chk CHECK(visibility IN ('public','private'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.club_type_catalog(
  code text PRIMARY KEY,label text NOT NULL,description text,active boolean NOT NULL DEFAULT true,sort_order smallint NOT NULL DEFAULT 100
);
INSERT INTO public.club_type_catalog(code,label,description,sort_order) VALUES
('professional','Kelab Profesional','Kelab bola sepak profesional.',10),
('semi_professional','Kelab Separuh Profesional','Kelab separuh profesional.',20),
('amateur','Kelab Amatur','Kelab amatur yang menyertai pertandingan/liga.',30),
('grassroots_academy','Akademi Bola Sepak / Akar Umbi','Pembangunan pemain akar umbi.',40),
('educational_institution','Institusi Pendidikan','Sekolah, kolej, universiti atau institusi pendidikan.',50),
('government_agency','Jabatan / Agensi Kerajaan','Pasukan jabatan atau agensi kerajaan.',60),
('corporate','Kelab Korporat','Kelab/pasukan organisasi korporat.',70),
('community','Kelab Komuniti','Kelab berasaskan komuniti.',80),
('womens_club','Kelab Bola Sepak Wanita','Fokus bola sepak wanita.',90),
('futsal','Kelab Futsal','Organisasi futsal.',100),
('development','Kelab Pembangunan','Kelab pembangunan/laluan bakat.',110),
('other','Lain-lain','Kategori tambahan.',120)
ON CONFLICT(code) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.club_training_venues(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  name text NOT NULL,address text,city text,state text,country text NOT NULL DEFAULT 'Malaysia',latitude numeric(9,6),longitude numeric(9,6),
  google_place_id text,google_maps_url text,is_primary boolean NOT NULL DEFAULT false,booking_enabled boolean NOT NULL DEFAULT false,notes text,
  created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT venue_lat_chk CHECK(latitude IS NULL OR latitude BETWEEN -90 AND 90),CONSTRAINT venue_lng_chk CHECK(longitude IS NULL OR longitude BETWEEN -180 AND 180)
);
CREATE INDEX IF NOT EXISTS club_training_venues_club_idx ON public.club_training_venues(club_id);
CREATE INDEX IF NOT EXISTS club_training_venues_coords_idx ON public.club_training_venues(latitude,longitude);
DO $$ BEGIN ALTER TABLE public.clubs ADD CONSTRAINT clubs_primary_training_venue_fk FOREIGN KEY(primary_training_venue_id) REFERENCES public.club_training_venues(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.club_memberships(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  role_code text NOT NULL,status text NOT NULL DEFAULT 'active',title text,joined_at timestamptz NOT NULL DEFAULT now(),left_at timestamptz,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_membership_role_chk CHECK(role_code IN ('owner','admin','coach','staff','player')),
  CONSTRAINT club_membership_status_chk CHECK(status IN ('pending','active','suspended','ended')),
  CONSTRAINT club_membership_dates_chk CHECK(left_at IS NULL OR left_at>=joined_at)
);
CREATE UNIQUE INDEX IF NOT EXISTS club_memberships_active_uq ON public.club_memberships(club_id,profile_id) WHERE status IN ('pending','active','suspended');
CREATE INDEX IF NOT EXISTS club_memberships_profile_idx ON public.club_memberships(profile_id);
CREATE INDEX IF NOT EXISTS club_memberships_club_role_idx ON public.club_memberships(club_id,role_code,status);

CREATE TABLE IF NOT EXISTS public.club_teams(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,name text NOT NULL,age_category text NOT NULL,
  squad_label text NOT NULL DEFAULT 'A',display_name text NOT NULL,season text,status text NOT NULL DEFAULT 'active',
  primary_coach_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,assistant_coach_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  formation text,logo_url text,created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_team_age_chk CHECK(age_category IN ('u6','u7','u8','u9','u10','u11','u12','u13','u14','u15','u16','u17','u18','u19','u20','u21','u22','u23','open','veteran')),
  CONSTRAINT club_team_label_chk CHECK(squad_label~'^[A-Z0-9]+$'),CONSTRAINT club_team_status_chk CHECK(status IN ('active','inactive','archived')),
  CONSTRAINT club_team_unique_name_uq UNIQUE(club_id,age_category,squad_label)
);
CREATE INDEX IF NOT EXISTS club_teams_club_idx ON public.club_teams(club_id);CREATE INDEX IF NOT EXISTS club_teams_age_idx ON public.club_teams(age_category);

CREATE TABLE IF NOT EXISTS public.club_team_staff(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),team_id uuid NOT NULL REFERENCES public.club_teams(id) ON DELETE CASCADE,profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  staff_role text NOT NULL,status text NOT NULL DEFAULT 'active',appointed_at timestamptz NOT NULL DEFAULT now(),ended_at timestamptz,appointed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT team_staff_role_chk CHECK(staff_role IN ('head_coach','assistant_coach','goalkeeper_coach','fitness_coach','team_manager','staff')),CONSTRAINT team_staff_status_chk CHECK(status IN ('active','ended'))
);
CREATE UNIQUE INDEX IF NOT EXISTS club_team_staff_active_uq ON public.club_team_staff(team_id,profile_id,staff_role) WHERE status='active';CREATE INDEX IF NOT EXISTS club_team_staff_profile_idx ON public.club_team_staff(profile_id);

CREATE TABLE IF NOT EXISTS public.club_team_players(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),team_id uuid NOT NULL REFERENCES public.club_teams(id) ON DELETE CASCADE,player_id uuid NOT NULL REFERENCES public.players(id) ON DELETE RESTRICT,
  jersey_number smallint,squad_status text NOT NULL DEFAULT 'active',joined_at timestamptz NOT NULL DEFAULT now(),left_at timestamptz,created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT team_player_jersey_chk CHECK(jersey_number IS NULL OR jersey_number BETWEEN 0 AND 99),CONSTRAINT team_player_status_chk CHECK(squad_status IN ('active','reserve','trial','inactive','released'))
);
CREATE UNIQUE INDEX IF NOT EXISTS club_team_players_active_uq ON public.club_team_players(team_id,player_id) WHERE squad_status IN ('active','reserve','trial');CREATE INDEX IF NOT EXISTS club_team_players_player_idx ON public.club_team_players(player_id);CREATE INDEX IF NOT EXISTS club_team_players_team_idx ON public.club_team_players(team_id,squad_status);

CREATE TABLE IF NOT EXISTS public.team_training_sessions(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),team_id uuid NOT NULL REFERENCES public.club_teams(id) ON DELETE CASCADE,coach_profile_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  venue_id uuid REFERENCES public.club_training_venues(id) ON DELETE SET NULL,title text NOT NULL,session_type text NOT NULL DEFAULT 'training',starts_at timestamptz NOT NULL,ends_at timestamptz,notes text,status text NOT NULL DEFAULT 'scheduled',created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT training_session_status_chk CHECK(status IN ('scheduled','completed','cancelled')),CONSTRAINT training_session_type_chk CHECK(session_type IN ('training','fitness','tactical','technical','recovery','assessment','friendly_prep','other')),CONSTRAINT training_session_time_chk CHECK(ends_at IS NULL OR ends_at>starts_at)
);
CREATE INDEX IF NOT EXISTS training_sessions_team_time_idx ON public.team_training_sessions(team_id,starts_at DESC);

CREATE TABLE IF NOT EXISTS public.club_history_records(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,record_type text NOT NULL,title text NOT NULL,competition_name text,season text,result_text text,achievement text,event_date date,notes text,source_fixture_id uuid REFERENCES public.fixtures(id) ON DELETE SET NULL,created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_history_type_chk CHECK(record_type IN ('achievement','competition','milestone','founding','award','other'))
);
CREATE INDEX IF NOT EXISTS club_history_club_date_idx ON public.club_history_records(club_id,event_date DESC,created_at DESC);

CREATE TABLE IF NOT EXISTS public.team_match_rooms(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),team_id uuid NOT NULL REFERENCES public.club_teams(id) ON DELETE CASCADE,fixture_id uuid NOT NULL REFERENCES public.fixtures(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pre_match',formation text,lineup jsonb NOT NULL DEFAULT '[]'::jsonb,bench jsonb NOT NULL DEFAULT '[]'::jsonb,tactical_notes text,coach_notes text,snapshot_image_url text,
  opened_at timestamptz,started_at timestamptz,finalized_at timestamptz,finalized_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT team_match_room_status_chk CHECK(status IN ('pre_match','live','half_time','full_time','finalized','voided')),CONSTRAINT team_match_room_unique_uq UNIQUE(team_id,fixture_id)
);
CREATE INDEX IF NOT EXISTS team_match_rooms_fixture_idx ON public.team_match_rooms(fixture_id,status);CREATE INDEX IF NOT EXISTS team_match_rooms_team_idx ON public.team_match_rooms(team_id,created_at DESC);

CREATE TABLE IF NOT EXISTS public.club_team_tactics(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),team_id uuid NOT NULL UNIQUE REFERENCES public.club_teams(id) ON DELETE CASCADE,formation text NOT NULL DEFAULT '4-3-3',lineup jsonb NOT NULL DEFAULT '[]'::jsonb,bench jsonb NOT NULL DEFAULT '[]'::jsonb,notes text,updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_team_tactics_formation_chk CHECK(formation IN ('3-4-3','4-3-3','3-5-2','3-4-2-1','4-2-3-1','4-4-2','4-1-4-1','5-3-2','5-4-1'))
);

CREATE OR REPLACE FUNCTION public.playpro_is_club_manager(p_club_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
SELECT EXISTS(SELECT 1 FROM public.clubs c WHERE c.id=p_club_id AND (c.owner_profile_id=(SELECT auth.uid()) OR c.admin_id=(SELECT auth.uid()) OR EXISTS(SELECT 1 FROM public.club_memberships m WHERE m.club_id=c.id AND m.profile_id=(SELECT auth.uid()) AND m.role_code IN ('owner','admin') AND m.status='active')));
$$;
REVOKE ALL ON FUNCTION public.playpro_is_club_manager(uuid) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.playpro_is_club_manager(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.playpro_profile_kyc_verified(p_profile_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
SELECT EXISTS(SELECT 1 FROM public.identity_verifications iv WHERE iv.profile_id=p_profile_id AND iv.status IN ('verified','approved') AND COALESCE(iv.match_status,'matched') IN ('matched','verified','approved','match'));
$$;
REVOKE ALL ON FUNCTION public.playpro_profile_kyc_verified(uuid) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.playpro_profile_kyc_verified(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_playpro_club(p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid:=(SELECT auth.uid());v_club_id uuid:=gen_random_uuid();v_name text:=NULLIF(trim(p_payload->>'name'),'');v_type text:=NULLIF(trim(p_payload->>'club_type'),'');v_code text;v_slug text;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan.' USING ERRCODE='42501';END IF;
IF NOT public.playpro_profile_kyc_verified(v_uid) THEN RAISE EXCEPTION 'KYC pemilik belum disahkan.' USING ERRCODE='42501';END IF;
IF v_name IS NULL THEN RAISE EXCEPTION 'Nama kelab wajib diisi.' USING ERRCODE='22023';END IF;
IF v_type IS NULL OR NOT EXISTS(SELECT 1 FROM public.club_type_catalog WHERE code=v_type AND active) THEN RAISE EXCEPTION 'Jenis kelab tidak sah.' USING ERRCODE='22023';END IF;
v_code:='PP-CLB-'||lpad(nextval('public.club_code_seq')::text,6,'0');v_slug:=lower(regexp_replace(v_name,'[^a-zA-Z0-9]+','-','g'))||'-'||substring(v_club_id::text,1,8);
INSERT INTO public.clubs(id,name,admin_id,owner_profile_id,club_code,slug,club_type,description,ros_registration_no,contact_phone,whatsapp_phone,city,state,country,verification_status,visibility,created_at,updated_at) VALUES(v_club_id,v_name,v_uid,v_uid,v_code,v_slug,v_type,NULLIF(trim(p_payload->>'description'),''),NULLIF(trim(p_payload->>'ros_registration_no'),''),NULLIF(trim(p_payload->>'contact_phone'),''),NULLIF(trim(p_payload->>'whatsapp_phone'),''),NULLIF(trim(p_payload->>'city'),''),NULLIF(trim(p_payload->>'state'),''),COALESCE(NULLIF(trim(p_payload->>'country'),''),'Malaysia'),'pending',CASE WHEN p_payload->>'visibility'='private' THEN 'private' ELSE 'public' END,now(),now());
INSERT INTO public.club_memberships(club_id,profile_id,role_code,status,created_by) VALUES(v_club_id,v_uid,'owner','active',v_uid);
INSERT INTO public.profile_role_profiles(profile_id,role_code,subject_id,is_active,created_at,updated_at) VALUES(v_uid,'club_owner',v_club_id,true,now(),now()) ON CONFLICT(profile_id,role_code) DO UPDATE SET subject_id=EXCLUDED.subject_id,is_active=true,updated_at=now();
RETURN jsonb_build_object('success',true,'club_id',v_club_id,'club_code',v_code,'slug',v_slug,'verification_status','pending');
END;$$;
REVOKE ALL ON FUNCTION public.create_playpro_club(jsonb) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.create_playpro_club(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_club_team(p_club_id uuid,p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid:=(SELECT auth.uid());v_age text:=lower(trim(coalesce(p_payload->>'age_category','')));v_label text:=upper(trim(coalesce(p_payload->>'squad_label','A')));v_name text:=NULLIF(trim(p_payload->>'name'),'');v_team_id uuid;v_display text;
BEGIN
IF v_uid IS NULL OR NOT public.playpro_is_club_manager(p_club_id) THEN RAISE EXCEPTION 'Hanya owner/admin kelab boleh mencipta squad.' USING ERRCODE='42501';END IF;
IF v_age NOT IN('u6','u7','u8','u9','u10','u11','u12','u13','u14','u15','u16','u17','u18','u19','u20','u21','u22','u23','open','veteran') THEN RAISE EXCEPTION 'Kategori umur tidak sah.' USING ERRCODE='22023';END IF;
IF v_label!~'^[A-Z0-9]+$' THEN RAISE EXCEPTION 'Label squad tidak sah.' USING ERRCODE='22023';END IF;
v_display:=coalesce(v_name,upper(v_age)||v_label);
INSERT INTO public.club_teams(club_id,name,age_category,squad_label,display_name,created_by) VALUES(p_club_id,v_display,v_age,v_label,v_display,v_uid) RETURNING id INTO v_team_id;
INSERT INTO public.club_team_tactics(team_id,formation,updated_by) VALUES(v_team_id,'4-3-3',v_uid);
RETURN jsonb_build_object('success',true,'team_id',v_team_id,'display_name',v_display);
END;$$;
REVOKE ALL ON FUNCTION public.create_club_team(uuid,jsonb) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.create_club_team(uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.add_player_to_club_team(p_team_id uuid,p_player_id uuid,p_jersey smallint DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid:=(SELECT auth.uid());v_club_id uuid;v_age_category text;v_dob date;v_age int;v_min_age int;v_player_profile uuid;
BEGIN
SELECT t.club_id,t.age_category INTO v_club_id,v_age_category FROM public.club_teams t WHERE t.id=p_team_id;
IF v_club_id IS NULL THEN RAISE EXCEPTION 'Squad tidak ditemui.' USING ERRCODE='P0002';END IF;
IF v_uid IS NULL OR NOT public.playpro_is_club_manager(v_club_id) THEN RAISE EXCEPTION 'Akses squad tidak dibenarkan.' USING ERRCODE='42501';END IF;
SELECT p.date_of_birth,p.profile_id INTO v_dob,v_player_profile FROM public.players p WHERE p.id=p_player_id AND p.is_active=true;
IF v_dob IS NULL THEN RAISE EXCEPTION 'Pemain tidak ditemui.' USING ERRCODE='P0002';END IF;
IF v_player_profile IS NULL OR NOT public.playpro_profile_kyc_verified(v_player_profile) THEN RAISE EXCEPTION 'Pemain mesti mempunyai KYC PlayPro yang disahkan.' USING ERRCODE='42501';END IF;
v_age:=extract(year from age(current_date,v_dob));
IF v_age_category='veteran' THEN IF v_age<35 THEN RAISE EXCEPTION 'Pemain belum mencapai umur Veteran (35+).';END IF;
ELSIF v_age_category<>'open' THEN v_min_age:=substring(v_age_category from 2)::int;IF v_age<v_min_age THEN RAISE EXCEPTION 'Pemain umur % tidak layak untuk squad %.',v_age,upper(v_age_category);END IF;END IF;
INSERT INTO public.club_memberships(club_id,profile_id,role_code,status,created_by) VALUES(v_club_id,v_player_profile,'player','active',v_uid) ON CONFLICT DO NOTHING;
INSERT INTO public.club_team_players(team_id,player_id,jersey_number,created_by) VALUES(p_team_id,p_player_id,p_jersey,v_uid) ON CONFLICT DO NOTHING;
UPDATE public.players SET club_id=coalesce(club_id,v_club_id),updated_at=now() WHERE id=p_player_id;
RETURN jsonb_build_object('success',true,'team_id',p_team_id,'player_id',p_player_id,'age',v_age,'age_category',v_age_category);
END;$$;
REVOKE ALL ON FUNCTION public.add_player_to_club_team(uuid,uuid,smallint) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.add_player_to_club_team(uuid,uuid,smallint) TO authenticated;

CREATE OR REPLACE FUNCTION public.appoint_team_staff(p_team_id uuid,p_profile_id uuid,p_staff_role text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid:=(SELECT auth.uid());v_club_id uuid;v_coach_id uuid;
BEGIN
SELECT club_id INTO v_club_id FROM public.club_teams WHERE id=p_team_id;IF v_club_id IS NULL THEN RAISE EXCEPTION 'Squad tidak ditemui.' USING ERRCODE='P0002';END IF;
IF v_uid IS NULL OR NOT public.playpro_is_club_manager(v_club_id) THEN RAISE EXCEPTION 'Akses tidak dibenarkan.' USING ERRCODE='42501';END IF;
IF p_staff_role NOT IN('head_coach','assistant_coach','goalkeeper_coach','fitness_coach','team_manager','staff') THEN RAISE EXCEPTION 'Jawatan staff tidak sah.' USING ERRCODE='22023';END IF;
IF p_staff_role IN('head_coach','assistant_coach','goalkeeper_coach','fitness_coach') THEN SELECT id INTO v_coach_id FROM public.coaches WHERE profile_id=p_profile_id AND is_active=true AND verification_status='verified';IF v_coach_id IS NULL THEN RAISE EXCEPTION 'Coach mestilah Coach Profile yang verified.' USING ERRCODE='42501';END IF;END IF;
IF NOT EXISTS(SELECT 1 FROM public.club_memberships WHERE club_id=v_club_id AND profile_id=p_profile_id AND status='active') THEN RAISE EXCEPTION 'User mesti menjadi ahli kelab terlebih dahulu.' USING ERRCODE='42501';END IF;
INSERT INTO public.club_team_staff(team_id,profile_id,staff_role,status,appointed_by) VALUES(p_team_id,p_profile_id,p_staff_role,'active',v_uid) ON CONFLICT DO NOTHING;
IF p_staff_role='head_coach' THEN UPDATE public.club_teams SET primary_coach_profile_id=p_profile_id,updated_at=now() WHERE id=p_team_id;END IF;
IF p_staff_role='assistant_coach' THEN UPDATE public.club_teams SET assistant_coach_profile_id=p_profile_id,updated_at=now() WHERE id=p_team_id;END IF;
RETURN jsonb_build_object('success',true,'team_id',p_team_id,'profile_id',p_profile_id,'staff_role',p_staff_role);
END;$$;
REVOKE ALL ON FUNCTION public.appoint_team_staff(uuid,uuid,text) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.appoint_team_staff(uuid,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_club_player_directory(p_club_id uuid) RETURNS TABLE(player_id uuid,profile_id uuid,display_name text,photo_url text,player_position text,date_of_birth date,verification_status text,football_passport_no text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
SELECT p.id,p.profile_id,CASE WHEN p.display_name_mode='preferred' AND NULLIF(trim(p.preferred_name),'') IS NOT NULL THEN p.preferred_name ELSE p.full_name END,p.photo_url,p.position::text,p.date_of_birth,p.verification_status,p.football_passport_no FROM public.club_memberships m JOIN public.players p ON p.profile_id=m.profile_id JOIN public.clubs c ON c.id=m.club_id WHERE m.club_id=p_club_id AND m.role_code='player' AND m.status='active' AND p.is_active=true AND(c.verification_status='verified' OR public.playpro_is_club_manager(c.id));
$$;
REVOKE ALL ON FUNCTION public.get_club_player_directory(uuid) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.get_club_player_directory(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_team_roster(p_team_id uuid) RETURNS TABLE(player_id uuid,display_name text,photo_url text,player_position text,jersey_number smallint,squad_status text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
SELECT p.id,CASE WHEN p.display_name_mode='preferred' AND NULLIF(trim(p.preferred_name),'') IS NOT NULL THEN p.preferred_name ELSE p.full_name END,p.photo_url,p.position::text,tp.jersey_number,tp.squad_status FROM public.club_team_players tp JOIN public.players p ON p.id=tp.player_id JOIN public.club_teams t ON t.id=tp.team_id JOIN public.clubs c ON c.id=t.club_id WHERE tp.team_id=p_team_id AND tp.squad_status IN('active','reserve','trial') AND p.is_active=true AND(c.verification_status='verified' OR public.playpro_is_club_manager(c.id));
$$;
REVOKE ALL ON FUNCTION public.get_team_roster(uuid) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.get_team_roster(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_club_dashboard() RETURNS TABLE(club_id uuid,club_name text,club_code text,club_type text,club_logo_url text,verification_status text,city text,state text,team_count bigint,member_count bigint) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
SELECT c.id,c.name,c.club_code,c.club_type,c.logo_url,c.verification_status,c.city,c.state,(SELECT count(*) FROM public.club_teams t WHERE t.club_id=c.id AND t.status='active'),(SELECT count(*) FROM public.club_memberships m WHERE m.club_id=c.id AND m.status='active') FROM public.clubs c WHERE public.playpro_is_club_manager(c.id) ORDER BY c.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_my_club_dashboard() FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.get_my_club_dashboard() TO authenticated;

CREATE OR REPLACE FUNCTION public.update_playpro_club(p_club_id uuid,p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid:=(SELECT auth.uid());v_type text:=NULLIF(trim(p_payload->>'club_type'),'');
BEGIN
IF v_uid IS NULL OR NOT public.playpro_is_club_manager(p_club_id) THEN RAISE EXCEPTION 'Akses club tidak dibenarkan.' USING ERRCODE='42501';END IF;
IF v_type IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.club_type_catalog WHERE code=v_type AND active) THEN RAISE EXCEPTION 'Jenis kelab tidak sah.' USING ERRCODE='22023';END IF;
UPDATE public.clubs SET name=coalesce(NULLIF(trim(p_payload->>'name'),''),name),logo_url=coalesce(NULLIF(trim(p_payload->>'logo_url'),''),logo_url),year_founded=coalesce(NULLIF(p_payload->>'year_founded','')::int,year_founded),club_type=coalesce(v_type,club_type),description=coalesce(NULLIF(trim(p_payload->>'description'),''),description),ros_registration_no=coalesce(NULLIF(trim(p_payload->>'ros_registration_no'),''),ros_registration_no),contact_phone=coalesce(NULLIF(trim(p_payload->>'contact_phone'),''),contact_phone),whatsapp_phone=coalesce(NULLIF(trim(p_payload->>'whatsapp_phone'),''),whatsapp_phone),city=coalesce(NULLIF(trim(p_payload->>'city'),''),city),state=coalesce(NULLIF(trim(p_payload->>'state'),''),state),country=coalesce(NULLIF(trim(p_payload->>'country'),''),country),visibility=CASE WHEN p_payload->>'visibility'='private' THEN 'private' ELSE 'public' END,updated_at=now() WHERE id=p_club_id;
RETURN jsonb_build_object('success',true,'club_id',p_club_id);
END;$$;
REVOKE ALL ON FUNCTION public.update_playpro_club(uuid,jsonb) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.update_playpro_club(uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_club_training_venue(p_club_id uuid,p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid:=(SELECT auth.uid());v_id uuid;
BEGIN
IF v_uid IS NULL OR NOT public.playpro_is_club_manager(p_club_id) THEN RAISE EXCEPTION 'Akses club tidak dibenarkan.' USING ERRCODE='42501';END IF;
IF NULLIF(trim(p_payload->>'name'),'') IS NULL THEN RAISE EXCEPTION 'Nama padang latihan wajib diisi.' USING ERRCODE='22023';END IF;
INSERT INTO public.club_training_venues(club_id,name,address,city,state,country,latitude,longitude,google_place_id,google_maps_url,is_primary,notes) VALUES(p_club_id,trim(p_payload->>'name'),NULLIF(trim(p_payload->>'address'),''),NULLIF(trim(p_payload->>'city'),''),NULLIF(trim(p_payload->>'state'),''),COALESCE(NULLIF(trim(p_payload->>'country'),''),'Malaysia'),NULLIF(p_payload->>'latitude','')::numeric,NULLIF(p_payload->>'longitude','')::numeric,NULLIF(trim(p_payload->>'google_place_id'),''),NULLIF(trim(p_payload->>'google_maps_url'),''),COALESCE((p_payload->>'is_primary')::boolean,false),NULLIF(trim(p_payload->>'notes'),'')) RETURNING id INTO v_id;
IF COALESCE((p_payload->>'is_primary')::boolean,false) THEN UPDATE public.club_training_venues SET is_primary=false WHERE club_id=p_club_id AND id<>v_id;UPDATE public.clubs SET primary_training_venue_id=v_id,updated_at=now() WHERE id=p_club_id;END IF;
RETURN jsonb_build_object('success',true,'venue_id',v_id);
END;$$;
REVOKE ALL ON FUNCTION public.save_club_training_venue(uuid,jsonb) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.save_club_training_venue(uuid,jsonb) TO authenticated;

ALTER TABLE public.club_type_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_training_venues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_team_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_team_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_training_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_history_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_match_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_team_tactics ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.club_type_catalog TO anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.club_training_venues,public.club_memberships,public.club_teams,public.club_team_staff,public.club_team_players,public.team_training_sessions,public.club_history_records,public.team_match_rooms,public.club_team_tactics TO authenticated;

DROP POLICY IF EXISTS club_type_catalog_public_read ON public.club_type_catalog;
CREATE POLICY club_type_catalog_public_read ON public.club_type_catalog FOR SELECT TO anon,authenticated USING(active=true);
DROP POLICY IF EXISTS club_training_venues_read ON public.club_training_venues;
CREATE POLICY club_training_venues_read ON public.club_training_venues FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.clubs c WHERE c.id=club_id AND(c.verification_status='verified' OR public.playpro_is_club_manager(c.id))));
DROP POLICY IF EXISTS club_training_venues_manage ON public.club_training_venues;
CREATE POLICY club_training_venues_manage ON public.club_training_venues FOR ALL TO authenticated USING(public.playpro_is_club_manager(club_id)) WITH CHECK(public.playpro_is_club_manager(club_id));
DROP POLICY IF EXISTS club_memberships_read ON public.club_memberships;
CREATE POLICY club_memberships_read ON public.club_memberships FOR SELECT TO authenticated USING(public.playpro_is_club_manager(club_id) OR profile_id=(SELECT auth.uid()) OR EXISTS(SELECT 1 FROM public.clubs c WHERE c.id=club_id AND c.verification_status='verified'));
DROP POLICY IF EXISTS club_memberships_manage ON public.club_memberships;
CREATE POLICY club_memberships_manage ON public.club_memberships FOR ALL TO authenticated USING(public.playpro_is_club_manager(club_id)) WITH CHECK(public.playpro_is_club_manager(club_id));
DROP POLICY IF EXISTS club_teams_read ON public.club_teams;
CREATE POLICY club_teams_read ON public.club_teams FOR SELECT TO authenticated USING(public.playpro_is_club_manager(club_id) OR EXISTS(SELECT 1 FROM public.clubs c WHERE c.id=club_id AND c.verification_status='verified'));
DROP POLICY IF EXISTS club_teams_manage ON public.club_teams;
CREATE POLICY club_teams_manage ON public.club_teams FOR ALL TO authenticated USING(public.playpro_is_club_manager(club_id)) WITH CHECK(public.playpro_is_club_manager(club_id));
DROP POLICY IF EXISTS club_team_staff_read ON public.club_team_staff;
CREATE POLICY club_team_staff_read ON public.club_team_staff FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND(public.playpro_is_club_manager(t.club_id) OR EXISTS(SELECT 1 FROM public.clubs c WHERE c.id=t.club_id AND c.verification_status='verified'))));
DROP POLICY IF EXISTS club_team_staff_manage ON public.club_team_staff;
CREATE POLICY club_team_staff_manage ON public.club_team_staff FOR ALL TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id))) WITH CHECK(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id)));
DROP POLICY IF EXISTS club_team_players_read ON public.club_team_players;
CREATE POLICY club_team_players_read ON public.club_team_players FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND(public.playpro_is_club_manager(t.club_id) OR EXISTS(SELECT 1 FROM public.clubs c WHERE c.id=t.club_id AND c.verification_status='verified'))));
DROP POLICY IF EXISTS club_team_players_manage ON public.club_team_players;
CREATE POLICY club_team_players_manage ON public.club_team_players FOR ALL TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id))) WITH CHECK(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id)));
DROP POLICY IF EXISTS team_training_sessions_read ON public.team_training_sessions;
CREATE POLICY team_training_sessions_read ON public.team_training_sessions FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND(public.playpro_is_club_manager(t.club_id) OR EXISTS(SELECT 1 FROM public.clubs c WHERE c.id=t.club_id AND c.verification_status='verified'))));
DROP POLICY IF EXISTS team_training_sessions_manage ON public.team_training_sessions;
CREATE POLICY team_training_sessions_manage ON public.team_training_sessions FOR ALL TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id))) WITH CHECK(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id)));
DROP POLICY IF EXISTS club_history_records_read ON public.club_history_records;
CREATE POLICY club_history_records_read ON public.club_history_records FOR SELECT TO authenticated USING(public.playpro_is_club_manager(club_id) OR EXISTS(SELECT 1 FROM public.clubs c WHERE c.id=club_id AND c.verification_status='verified'));
DROP POLICY IF EXISTS club_history_records_manage ON public.club_history_records;
CREATE POLICY club_history_records_manage ON public.club_history_records FOR ALL TO authenticated USING(public.playpro_is_club_manager(club_id)) WITH CHECK(public.playpro_is_club_manager(club_id));
DROP POLICY IF EXISTS team_match_rooms_read ON public.team_match_rooms;
CREATE POLICY team_match_rooms_read ON public.team_match_rooms FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND(public.playpro_is_club_manager(t.club_id) OR EXISTS(SELECT 1 FROM public.clubs c WHERE c.id=t.club_id AND c.verification_status='verified'))));
DROP POLICY IF EXISTS team_match_rooms_manage ON public.team_match_rooms;
CREATE POLICY team_match_rooms_manage ON public.team_match_rooms FOR INSERT TO authenticated WITH CHECK(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id)));
DROP POLICY IF EXISTS team_match_rooms_update ON public.team_match_rooms;
CREATE POLICY team_match_rooms_update ON public.team_match_rooms FOR UPDATE TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id)) AND status<>'finalized') WITH CHECK(status<>'finalized');
DROP POLICY IF EXISTS club_team_tactics_read ON public.club_team_tactics;
CREATE POLICY club_team_tactics_read ON public.club_team_tactics FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t JOIN public.clubs c ON c.id=t.club_id WHERE t.id=team_id AND(c.verification_status='verified' OR public.playpro_is_club_manager(c.id))));
DROP POLICY IF EXISTS club_team_tactics_manage ON public.club_team_tactics;
CREATE POLICY club_team_tactics_manage ON public.club_team_tactics FOR INSERT TO authenticated WITH CHECK(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id)));
DROP POLICY IF EXISTS club_team_tactics_update ON public.club_team_tactics;
CREATE POLICY club_team_tactics_update ON public.club_team_tactics FOR UPDATE TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id))) WITH CHECK(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id)));

COMMIT;