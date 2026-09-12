-- PlayPro Coach Profile v2 — production foundation
-- Safe/idempotent: extends existing coaches model; does not replace legacy data.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SEQUENCE IF NOT EXISTS coach_public_id_seq;

ALTER TABLE public.coaches
  ADD COLUMN IF NOT EXISTS coach_code TEXT,
  ADD COLUMN IF NOT EXISTS preferred_name TEXT,
  ADD COLUMN IF NOT EXISTS bio TEXT,
  ADD COLUMN IF NOT EXISTS display_name_mode TEXT NOT NULL DEFAULT 'preferred',
  ADD COLUMN IF NOT EXISTS profile_visibility TEXT NOT NULL DEFAULT 'public',
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS nationality TEXT DEFAULT 'Malaysian',
  ADD COLUMN IF NOT EXISTS coaching_role TEXT NOT NULL DEFAULT 'head_coach',
  ADD COLUMN IF NOT EXISTS preferred_formation TEXT,
  ADD COLUMN IF NOT EXISTS preferred_style TEXT,
  ADD COLUMN IF NOT EXISTS coaching_specialties JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS license_type TEXT,
  ADD COLUMN IF NOT EXISTS license_number TEXT,
  ADD COLUMN IF NOT EXISTS license_issuing_body TEXT,
  ADD COLUMN IF NOT EXISTS license_issue_date DATE,
  ADD COLUMN IF NOT EXISTS license_expiry_date DATE,
  ADD COLUMN IF NOT EXISTS license_status TEXT NOT NULL DEFAULT 'unverified',
  ADD COLUMN IF NOT EXISTS verification_status TEXT NOT NULL DEFAULT 'unverified',
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS profile_completed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS disciplinary_status TEXT NOT NULL DEFAULT 'clear',
  ADD COLUMN IF NOT EXISTS card_state TEXT NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE public.coaches
SET coach_code = 'COA-' || LPAD(nextval('public.coach_public_id_seq')::TEXT, 6, '0')
WHERE coach_code IS NULL OR BTRIM(coach_code) = '';

CREATE UNIQUE INDEX IF NOT EXISTS coaches_coach_code_uq ON public.coaches(coach_code);
ALTER TABLE public.coaches ALTER COLUMN coach_code SET NOT NULL;

ALTER TABLE public.coaches
  DROP CONSTRAINT IF EXISTS coaches_display_name_mode_chk,
  DROP CONSTRAINT IF EXISTS coaches_profile_visibility_chk,
  DROP CONSTRAINT IF EXISTS coaches_license_status_chk,
  DROP CONSTRAINT IF EXISTS coaches_verification_status_chk,
  DROP CONSTRAINT IF EXISTS coaches_disciplinary_status_chk,
  DROP CONSTRAINT IF EXISTS coaches_card_state_chk,
  DROP CONSTRAINT IF EXISTS coaches_coaching_role_chk,
  DROP CONSTRAINT IF EXISTS coaches_bio_length_chk;

ALTER TABLE public.coaches
  ADD CONSTRAINT coaches_display_name_mode_chk CHECK (display_name_mode IN ('legal','preferred')),
  ADD CONSTRAINT coaches_profile_visibility_chk CHECK (profile_visibility IN ('public','private')),
  ADD CONSTRAINT coaches_license_status_chk CHECK (license_status IN ('unverified','pending','verified','expired','suspended')),
  ADD CONSTRAINT coaches_verification_status_chk CHECK (verification_status IN ('unverified','pending','verified','revoked')),
  ADD CONSTRAINT coaches_disciplinary_status_chk CHECK (disciplinary_status IN ('clear','warning','suspended','banned')),
  ADD CONSTRAINT coaches_card_state_chk CHECK (card_state IN ('active','dimmed','suspended','banned')),
  ADD CONSTRAINT coaches_coaching_role_chk CHECK (coaching_role IN ('head_coach','assistant_head_coach','assistant_coach','goalkeeper_coach','fitness_coach','youth_coach','technical_coach','other')),
  ADD CONSTRAINT coaches_bio_length_chk CHECK (bio IS NULL OR char_length(bio) <= 500);

CREATE INDEX IF NOT EXISTS idx_coaches_profile_id ON public.coaches(profile_id);
CREATE INDEX IF NOT EXISTS idx_coaches_verification_status ON public.coaches(verification_status);
CREATE INDEX IF NOT EXISTS idx_coaches_club_id ON public.coaches(club_id);

CREATE TABLE IF NOT EXISTS public.profile_role_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role_code TEXT NOT NULL CHECK (role_code IN ('player','coach','club_owner','organizer','referee')),
  subject_id UUID,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(profile_id, role_code),
  UNIQUE(role_code, subject_id)
);

CREATE INDEX IF NOT EXISTS idx_profile_role_profiles_profile ON public.profile_role_profiles(profile_id);
CREATE INDEX IF NOT EXISTS idx_profile_role_profiles_subject ON public.profile_role_profiles(role_code, subject_id);

ALTER TABLE public.profile_role_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS profile_role_profiles_owner_read ON public.profile_role_profiles;
CREATE POLICY profile_role_profiles_owner_read ON public.profile_role_profiles FOR SELECT TO authenticated USING (profile_id = (SELECT auth.uid()));
DROP POLICY IF EXISTS profile_role_profiles_owner_insert ON public.profile_role_profiles;
CREATE POLICY profile_role_profiles_owner_insert ON public.profile_role_profiles FOR INSERT TO authenticated WITH CHECK (profile_id = (SELECT auth.uid()));
DROP POLICY IF EXISTS profile_role_profiles_owner_update ON public.profile_role_profiles;
CREATE POLICY profile_role_profiles_owner_update ON public.profile_role_profiles FOR UPDATE TO authenticated USING (profile_id = (SELECT auth.uid())) WITH CHECK (profile_id = (SELECT auth.uid()));

CREATE TABLE IF NOT EXISTS public.coach_attribute_state (
  coach_id UUID PRIMARY KEY REFERENCES public.coaches(id) ON DELETE CASCADE,
  adaptability SMALLINT NOT NULL DEFAULT 0 CHECK (adaptability BETWEEN 0 AND 20),
  coaching_goalkeepers SMALLINT NOT NULL DEFAULT 0 CHECK (coaching_goalkeepers BETWEEN 0 AND 20),
  coaching_outfield SMALLINT NOT NULL DEFAULT 0 CHECK (coaching_outfield BETWEEN 0 AND 20),
  coaching_youth SMALLINT NOT NULL DEFAULT 0 CHECK (coaching_youth BETWEEN 0 AND 20),
  determination SMALLINT NOT NULL DEFAULT 0 CHECK (determination BETWEEN 0 AND 20),
  discipline SMALLINT NOT NULL DEFAULT 0 CHECK (discipline BETWEEN 0 AND 20),
  judging_player_ability SMALLINT NOT NULL DEFAULT 0 CHECK (judging_player_ability BETWEEN 0 AND 20),
  judging_player_potential SMALLINT NOT NULL DEFAULT 0 CHECK (judging_player_potential BETWEEN 0 AND 20),
  man_management SMALLINT NOT NULL DEFAULT 0 CHECK (man_management BETWEEN 0 AND 20),
  motivating SMALLINT NOT NULL DEFAULT 0 CHECK (motivating BETWEEN 0 AND 20),
  physiotherapy SMALLINT NOT NULL DEFAULT 0 CHECK (physiotherapy BETWEEN 0 AND 20),
  tactical_knowledge SMALLINT NOT NULL DEFAULT 0 CHECK (tactical_knowledge BETWEEN 0 AND 20),
  source TEXT NOT NULL DEFAULT 'none' CHECK (source IN ('none','coach_assessment','derived','combined')),
  confidence SMALLINT NOT NULL DEFAULT 0 CHECK (confidence BETWEEN 0 AND 100),
  assessed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.coach_attribute_state ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS coach_attribute_state_public_read ON public.coach_attribute_state;
CREATE POLICY coach_attribute_state_public_read ON public.coach_attribute_state FOR SELECT TO anon, authenticated USING (TRUE);
DROP POLICY IF EXISTS coach_attribute_state_owner_read ON public.coach_attribute_state;
CREATE POLICY coach_attribute_state_owner_read ON public.coach_attribute_state FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.coaches c WHERE c.id = coach_id AND c.profile_id = (SELECT auth.uid())));

CREATE TABLE IF NOT EXISTS public.coach_certification_courses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coaches(id) ON DELETE CASCADE,
  course_no SMALLINT NOT NULL CHECK (course_no BETWEEN 1 AND 5),
  attribute_band TEXT NOT NULL,
  max_attribute_score SMALLINT NOT NULL CHECK (max_attribute_score BETWEEN 1 AND 20),
  status TEXT NOT NULL DEFAULT 'not_started' CHECK (status IN ('not_started','requested','scheduled','in_progress','passed','failed','expired')),
  requested_at TIMESTAMPTZ,
  scheduled_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  certificate_no TEXT,
  reviewed_by UUID REFERENCES public.profiles(id),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(coach_id, course_no)
);

INSERT INTO public.coach_certification_courses (coach_id, course_no, attribute_band, max_attribute_score)
SELECT c.id, x.course_no, x.attribute_band, x.max_attribute_score
FROM public.coaches c
CROSS JOIN (VALUES
  (1::smallint,'1–5',5::smallint),
  (2::smallint,'5–10',10::smallint),
  (3::smallint,'10–15',15::smallint),
  (4::smallint,'15–20',20::smallint),
  (5::smallint,'15–20 · practical certification',20::smallint)
) x(course_no,attribute_band,max_attribute_score)
ON CONFLICT (coach_id, course_no) DO NOTHING;

ALTER TABLE public.coach_certification_courses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS coach_certification_courses_owner_read ON public.coach_certification_courses;
CREATE POLICY coach_certification_courses_owner_read ON public.coach_certification_courses FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.coaches c WHERE c.id = coach_id AND c.profile_id = (SELECT auth.uid())));

CREATE TABLE IF NOT EXISTS public.coach_certification_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coaches(id) ON DELETE CASCADE,
  requested_course_no SMALLINT NOT NULL CHECK (requested_course_no BETWEEN 1 AND 5),
  status TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','scheduled','in_progress','passed','failed','cancelled')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  scheduled_at TIMESTAMPTZ,
  reviewed_by UUID REFERENCES public.profiles(id),
  reviewed_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_coach_cert_requests_coach ON public.coach_certification_requests(coach_id, status);
ALTER TABLE public.coach_certification_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS coach_certification_requests_owner_read ON public.coach_certification_requests;
CREATE POLICY coach_certification_requests_owner_read ON public.coach_certification_requests FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.coaches c WHERE c.id = coach_id AND c.profile_id = (SELECT auth.uid())));
DROP POLICY IF EXISTS coach_certification_requests_owner_insert ON public.coach_certification_requests;
CREATE POLICY coach_certification_requests_owner_insert ON public.coach_certification_requests FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM public.coaches c WHERE c.id = coach_id AND c.profile_id = (SELECT auth.uid())));

CREATE TABLE IF NOT EXISTS public.coach_disciplinary_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id UUID NOT NULL REFERENCES public.coaches(id) ON DELETE RESTRICT,
  incident_type TEXT NOT NULL,
  reason TEXT NOT NULL,
  fixture_id UUID REFERENCES public.fixtures(id),
  sanction_status TEXT NOT NULL DEFAULT 'active' CHECK (sanction_status IN ('active','completed','appealed','revoked')),
  suspension_matches INTEGER CHECK (suspension_matches IS NULL OR suspension_matches > 0),
  ban_until TIMESTAMPTZ,
  evidence JSONB NOT NULL DEFAULT '[]'::jsonb,
  imposed_by UUID REFERENCES public.profiles(id),
  imposed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  appeal_status TEXT NOT NULL DEFAULT 'none' CHECK (appeal_status IN ('none','pending','upheld','modified','revoked')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_coach_discipline_coach ON public.coach_disciplinary_records(coach_id, imposed_at DESC);
ALTER TABLE public.coach_disciplinary_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS coach_disciplinary_public_read ON public.coach_disciplinary_records;
CREATE POLICY coach_disciplinary_public_read ON public.coach_disciplinary_records FOR SELECT TO anon, authenticated USING (TRUE);

INSERT INTO public.coach_attribute_state (coach_id)
SELECT id FROM public.coaches
ON CONFLICT (coach_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.save_coach_onboarding_profile(p_profile_id UUID, p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_coach_id UUID;
  v_name TEXT;
  v_preferred TEXT;
  v_phone TEXT;
  v_dob DATE;
  v_license TEXT;
  v_license_no TEXT;
  v_role TEXT;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR (SELECT auth.uid()) <> p_profile_id THEN
    RETURN jsonb_build_object('success',false,'reason','UNAUTHORIZED');
  END IF;

  v_name := NULLIF(BTRIM(p_payload->>'full_name'),'');
  v_preferred := NULLIF(BTRIM(p_payload->>'preferred_name'),'');
  v_phone := NULLIF(BTRIM(p_payload->>'phone'),'');
  v_license := NULLIF(BTRIM(p_payload->>'license_type'),'');
  v_license_no := NULLIF(BTRIM(p_payload->>'license_number'),'');
  v_role := COALESCE(NULLIF(BTRIM(p_payload->>'coaching_role'),''),'head_coach');

  IF v_name IS NULL OR v_phone IS NULL OR v_license IS NULL THEN
    RETURN jsonb_build_object('success',false,'reason','REQUIRED_FIELDS_MISSING','message','Nama, nombor telefon dan lesen diperlukan.');
  END IF;

  IF NULLIF(p_payload->>'date_of_birth','') IS NOT NULL THEN
    v_dob := (p_payload->>'date_of_birth')::DATE;
  END IF;

  UPDATE public.profiles
  SET full_name = v_name,
      phone = v_phone,
      date_of_birth = COALESCE(v_dob,date_of_birth),
      updated_at = NOW()
  WHERE id = p_profile_id;

  INSERT INTO public.coaches (
    profile_id, full_name, preferred_name, phone, date_of_birth, license,
    license_type, license_number, license_issuing_body, coaching_role,
    preferred_formation, preferred_style, coaching_specialties, photo_url,
    profile_completed_at, verification_status, updated_at
  ) VALUES (
    p_profile_id, v_name, v_preferred, v_phone, v_dob, v_license,
    v_license, v_license_no, NULLIF(BTRIM(p_payload->>'license_issuing_body'),''), v_role,
    NULLIF(BTRIM(p_payload->>'preferred_formation'),''),
    NULLIF(BTRIM(p_payload->>'preferred_style'),''),
    COALESCE(p_payload->'coaching_specialties','[]'::jsonb),
    NULLIF(BTRIM(p_payload->>'photo_url'),''), NOW(), 'unverified', NOW()
  )
  ON CONFLICT (profile_id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    preferred_name = EXCLUDED.preferred_name,
    phone = EXCLUDED.phone,
    date_of_birth = COALESCE(EXCLUDED.date_of_birth, public.coaches.date_of_birth),
    license = EXCLUDED.license,
    license_type = EXCLUDED.license_type,
    license_number = EXCLUDED.license_number,
    license_issuing_body = EXCLUDED.license_issuing_body,
    coaching_role = EXCLUDED.coaching_role,
    preferred_formation = EXCLUDED.preferred_formation,
    preferred_style = EXCLUDED.preferred_style,
    coaching_specialties = EXCLUDED.coaching_specialties,
    photo_url = EXCLUDED.photo_url,
    profile_completed_at = NOW(),
    updated_at = NOW()
  RETURNING id INTO v_coach_id;

  INSERT INTO public.profile_role_profiles(profile_id,role_code,subject_id)
  VALUES (p_profile_id,'coach',v_coach_id)
  ON CONFLICT (profile_id,role_code) DO UPDATE SET subject_id=EXCLUDED.subject_id,is_active=TRUE,updated_at=NOW();

  INSERT INTO public.coach_attribute_state(coach_id)
  VALUES (v_coach_id) ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object('success',true,'reason','COACH_PROFILE_SAVED','coach_id',v_coach_id);
END;
$$;

REVOKE ALL ON FUNCTION public.save_coach_onboarding_profile(UUID,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_coach_onboarding_profile(UUID,JSONB) TO authenticated;

COMMENT ON TABLE public.profile_role_profiles IS 'Additive multi-role identity map: one PlayPro account can own player, coach, club-owner, organiser and referee identities. profiles.role remains legacy/primary until router migration.';
COMMENT ON TABLE public.coach_attribute_state IS 'CM-style coach attributes. 0 means not yet assessed; PlayPro display scale is 1–20.';
COMMENT ON TABLE public.coach_certification_courses IS 'Five-course PlayPro coach accreditation pathway controlling maximum player-attribute assessment authority.';
