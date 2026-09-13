-- PLAYPRO CLUB MEMBERSHIP + REFEREE FOUNDATION + UNIVERSAL RATINGS
-- Applied to playpro2. Additive only.
-- Membership supports: club invite by PlayPro ID/IC, player request, optional PlayPro fee collection.
-- Referee supports official licence evidence, 2-level PlayPro accreditation, organic LTO statistics and referee attributes.
-- No duplicate user accounts: all entities remain tied to profiles/profile_role_profiles.

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS playpro_id text,
  ADD COLUMN IF NOT EXISTS ic_number text,
  ADD COLUMN IF NOT EXISTS passport_number text,
  ADD COLUMN IF NOT EXISTS date_of_birth date,
  ADD COLUMN IF NOT EXISTS nationality text DEFAULT 'Malaysian';

CREATE SEQUENCE IF NOT EXISTS public.playpro_user_id_seq START WITH 1 INCREMENT BY 1;
CREATE UNIQUE INDEX IF NOT EXISTS profiles_playpro_id_uq ON public.profiles(playpro_id) WHERE playpro_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS profiles_ic_number_idx ON public.profiles(ic_number) WHERE ic_number IS NOT NULL;

CREATE OR REPLACE FUNCTION public.playpro_generate_id_prefix(p_legal_name text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
  SELECT CASE WHEN length(regexp_replace(split_part(trim(coalesce(p_legal_name,'')),' ',1),'[^A-Za-z]','','g')) >= 4
    THEN lower(right(regexp_replace(split_part(trim(p_legal_name),' ',1),'[^A-Za-z]','','g'),4))
    ELSE lower(rpad(regexp_replace(split_part(trim(coalesce(p_legal_name,'')),' ',1),'[^A-Za-z]','','g'),4,'x')) END;
$$;

CREATE OR REPLACE FUNCTION public.playpro_assign_id_after_kyc()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_name text; v_state text; v_seq bigint;
BEGIN
  IF NEW.status IN ('verified','approved') AND COALESCE(NEW.match_status,'matched') IN ('matched','verified','approved','match') THEN
    SELECT COALESCE(NEW.extracted_legal_name,p.full_name), COALESCE(NEW.birth_state_code,'00') INTO v_name,v_state FROM public.profiles p WHERE p.id=NEW.profile_id;
    IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=NEW.profile_id AND p.playpro_id IS NOT NULL) THEN
      SELECT nextval('public.playpro_user_id_seq') INTO v_seq;
    END IF;
    UPDATE public.profiles
       SET full_name=COALESCE(v_name,full_name),
           playpro_id=COALESCE(playpro_id,public.playpro_generate_id_prefix(v_name)||'-'||lpad(regexp_replace(coalesce(v_state,'00'),'[^0-9]','','g'),2,'0')||'-'||lpad(coalesce(v_seq,nextval('public.playpro_user_id_seq'))::text,6,'0')),
           updated_at=now()
     WHERE id=NEW.profile_id;
  END IF; RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_playpro_assign_id_after_kyc ON public.identity_verifications;
CREATE TRIGGER trg_playpro_assign_id_after_kyc AFTER INSERT OR UPDATE OF status,match_status ON public.identity_verifications FOR EACH ROW EXECUTE FUNCTION public.playpro_assign_id_after_kyc();

CREATE TABLE IF NOT EXISTS public.club_membership_settings(
  club_id uuid PRIMARY KEY REFERENCES public.clubs(id) ON DELETE CASCADE,
  fee_collection_enabled boolean NOT NULL DEFAULT false,
  player_registration_fee numeric(12,2) NOT NULL DEFAULT 0,
  currency char(3) NOT NULL DEFAULT 'MYR',
  billing_cycle text NOT NULL DEFAULT 'one_time',
  fee_description text,
  platform_fee_percent numeric(5,2) NOT NULL DEFAULT 5.00,
  payment_instructions text,
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_fee_amount_chk CHECK(player_registration_fee>=0),
  CONSTRAINT club_fee_platform_pct_chk CHECK(platform_fee_percent>=0 AND platform_fee_percent<=100),
  CONSTRAINT club_fee_cycle_chk CHECK(billing_cycle IN ('one_time','monthly','quarterly','annual','custom'))
);

CREATE TABLE IF NOT EXISTS public.club_membership_requests(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  requested_role text NOT NULL,
  initiated_by text NOT NULL,
  requested_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'requested',
  club_note text,
  response_note text,
  approved_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_at timestamptz,
  payment_required boolean NOT NULL DEFAULT false,
  payment_status text NOT NULL DEFAULT 'not_required',
  payment_due_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cmr_role_chk CHECK(requested_role IN ('player','coach','staff','admin')),
  CONSTRAINT cmr_initiated_chk CHECK(initiated_by IN ('club_invite','user_request')),
  CONSTRAINT cmr_status_chk CHECK(status IN ('requested','approved','rejected','cancelled','payment_pending','pending_playpro_verification','active')),
  CONSTRAINT cmr_payment_status_chk CHECK(payment_status IN ('not_required','pending','paid','verified','failed','refunded'))
);
CREATE INDEX IF NOT EXISTS club_membership_requests_club_idx ON public.club_membership_requests(club_id,status,created_at DESC);
CREATE INDEX IF NOT EXISTS club_membership_requests_profile_idx ON public.club_membership_requests(profile_id,status,created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS club_membership_requests_open_uq ON public.club_membership_requests(club_id,profile_id,requested_role) WHERE status IN ('requested','approved','payment_pending','pending_playpro_verification');

CREATE TABLE IF NOT EXISTS public.club_membership_payments(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE REFERENCES public.club_membership_requests(id) ON DELETE RESTRICT,
  club_id uuid NOT NULL REFERENCES public.clubs(id) ON DELETE RESTRICT,
  payer_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  gross_amount numeric(12,2) NOT NULL,
  platform_fee_amount numeric(12,2) NOT NULL,
  club_net_amount numeric(12,2) NOT NULL,
  currency char(3) NOT NULL DEFAULT 'MYR',
  payment_provider text,
  provider_reference text,
  status text NOT NULL DEFAULT 'pending',
  paid_at timestamptz,
  playpro_verified_at timestamptz,
  verified_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cmp_amount_chk CHECK(gross_amount>=0 AND platform_fee_amount>=0 AND club_net_amount>=0),
  CONSTRAINT cmp_status_chk CHECK(status IN ('pending','paid','verified','failed','refunded'))
);
CREATE INDEX IF NOT EXISTS club_membership_payments_club_idx ON public.club_membership_payments(club_id,status,created_at DESC);

CREATE OR REPLACE FUNCTION public.playpro_membership_lookup(p_lookup_type text,p_lookup_value text)
RETURNS TABLE(profile_id uuid,playpro_id text,display_name text,role_code text,kyc_verified boolean,has_player boolean,has_coach boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
SELECT p.id,p.playpro_id,p.full_name,p.role::text,public.playpro_profile_kyc_verified(p.id),
       EXISTS(SELECT 1 FROM public.players pl WHERE pl.profile_id=p.id),
       EXISTS(SELECT 1 FROM public.coaches co WHERE co.profile_id=p.id)
FROM public.profiles p
WHERE (lower(p_lookup_type)='playpro_id' AND p.playpro_id=trim(p_lookup_value))
   OR (lower(p_lookup_type)='ic' AND p.ic_number=regexp_replace(trim(p_lookup_value),'[^0-9A-Za-z]','','g'))
LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.playpro_membership_lookup(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.playpro_membership_lookup(text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.playpro_create_membership_request(p_club_id uuid,p_profile_id uuid,p_role text,p_mode text,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid:=auth.uid(); v_fee_enabled boolean:=false; v_fee numeric(12,2):=0; v_req uuid; v_payment_required boolean:=false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Log masuk diperlukan.' USING ERRCODE='42501'; END IF;
  IF p_role NOT IN ('player','coach','staff','admin') THEN RAISE EXCEPTION 'Role kelab tidak sah.' USING ERRCODE='22023'; END IF;
  IF p_mode NOT IN ('club_invite','user_request') THEN RAISE EXCEPTION 'Mode permintaan tidak sah.' USING ERRCODE='22023'; END IF;
  IF p_mode='club_invite' AND NOT public.playpro_is_club_manager(p_club_id) THEN RAISE EXCEPTION 'Hanya owner/admin kelab boleh menjemput.' USING ERRCODE='42501'; END IF;
  IF p_mode='user_request' AND v_uid<>p_profile_id THEN RAISE EXCEPTION 'Permintaan mesti datang daripada user tersebut.' USING ERRCODE='42501'; END IF;
  IF p_role IN ('player','coach') AND NOT public.playpro_profile_kyc_verified(p_profile_id) THEN RAISE EXCEPTION 'User mesti KYC verified sebelum menyertai kelab.' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM public.club_memberships m WHERE m.club_id=p_club_id AND m.profile_id=p_profile_id AND m.status IN ('active','suspended')) THEN RAISE EXCEPTION 'User sudah menjadi ahli kelab.' USING ERRCODE='23505'; END IF;
  SELECT fee_collection_enabled,player_registration_fee INTO v_fee_enabled,v_fee FROM public.club_membership_settings WHERE club_id=p_club_id;
  v_payment_required:=p_role='player' AND coalesce(v_fee_enabled,false) AND coalesce(v_fee,0)>0;
  INSERT INTO public.club_membership_requests(club_id,profile_id,requested_role,initiated_by,requested_by,status,payment_required,payment_status,club_note)
  VALUES(p_club_id,p_profile_id,p_role,p_mode,v_uid,'requested',v_payment_required,CASE WHEN v_payment_required THEN 'pending' ELSE 'not_required' END,p_note)
  RETURNING id INTO v_req;
  RETURN jsonb_build_object('success',true,'request_id',v_req,'payment_required',v_payment_required,'fee',v_fee,'platform_fee_percent',5.00);
END; $$;
REVOKE ALL ON FUNCTION public.playpro_create_membership_request(uuid,uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.playpro_create_membership_request(uuid,uuid,text,text,text) TO authenticated;

ALTER TABLE public.referees
  ADD COLUMN IF NOT EXISTS referee_code text,
  ADD COLUMN IF NOT EXISTS nationality text DEFAULT 'Malaysian',
  ADD COLUMN IF NOT EXISTS date_of_birth date,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS profile_visibility text NOT NULL DEFAULT 'public',
  ADD COLUMN IF NOT EXISTS verification_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS verified_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS disciplinary_status text NOT NULL DEFAULT 'clear',
  ADD COLUMN IF NOT EXISTS card_state text NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS playpro_accreditation_level smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS profile_completed_at timestamptz;
CREATE SEQUENCE IF NOT EXISTS public.referee_code_seq START WITH 1 INCREMENT BY 1;
UPDATE public.referees SET referee_code='PP-REF-'||lpad(nextval('public.referee_code_seq')::text,6,'0') WHERE referee_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS referees_referee_code_uq ON public.referees(referee_code) WHERE referee_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.referee_license_documents(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),referee_id uuid NOT NULL REFERENCES public.referees(id) ON DELETE CASCADE,
 issuing_body text NOT NULL,license_type text NOT NULL,license_number text,document_path text NOT NULL,issue_date date,expiry_date date,status text NOT NULL DEFAULT 'pending',review_note text,
 submitted_at timestamptz NOT NULL DEFAULT now(),reviewed_at timestamptz,reviewed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT referee_license_body_chk CHECK(issuing_body IN ('FAM','AFC','FIFA','other')),CONSTRAINT referee_license_status_chk CHECK(status IN ('pending','verified','rejected','expired')));
CREATE INDEX IF NOT EXISTS referee_license_docs_referee_idx ON public.referee_license_documents(referee_id,status);

CREATE TABLE IF NOT EXISTS public.referee_accreditations(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),referee_id uuid NOT NULL REFERENCES public.referees(id) ON DELETE CASCADE,
 level_no smallint NOT NULL,course_type text NOT NULL,course_title text NOT NULL,status text NOT NULL DEFAULT 'not_started',requested_at timestamptz,scheduled_at timestamptz,completed_at timestamptz,certificate_no text,reviewed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,notes text,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT referee_acc_level_chk CHECK(level_no IN (1,2)),CONSTRAINT referee_acc_course_chk CHECK(course_type IN ('orientation','refreshment')),CONSTRAINT referee_acc_status_chk CHECK(status IN ('not_started','requested','scheduled','completed','failed','suspended')),CONSTRAINT referee_acc_unique_uq UNIQUE(referee_id,level_no));
INSERT INTO public.referee_accreditations(referee_id,level_no,course_type,course_title) SELECT r.id,1,'orientation','PlayPro Referee Orientation' FROM public.referees r ON CONFLICT(referee_id,level_no) DO NOTHING;
INSERT INTO public.referee_accreditations(referee_id,level_no,course_type,course_title) SELECT r.id,2,'refreshment','PlayPro Referee Refreshment & Match Observer Protocol' FROM public.referees r ON CONFLICT(referee_id,level_no) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.referee_attribute_state(
 referee_id uuid PRIMARY KEY REFERENCES public.referees(id) ON DELETE CASCADE,
 law_application smallint NOT NULL DEFAULT 0,decision_making smallint NOT NULL DEFAULT 0,positioning smallint NOT NULL DEFAULT 0,disciplinary_control smallint NOT NULL DEFAULT 0,communication smallint NOT NULL DEFAULT 0,teamwork smallint NOT NULL DEFAULT 0,fitness smallint NOT NULL DEFAULT 0,consistency smallint NOT NULL DEFAULT 0,
 source text NOT NULL DEFAULT 'none',confidence smallint NOT NULL DEFAULT 0,assessed_at timestamptz,updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT referee_attr_range_chk CHECK(law_application BETWEEN 0 AND 20 AND decision_making BETWEEN 0 AND 20 AND positioning BETWEEN 0 AND 20 AND disciplinary_control BETWEEN 0 AND 20 AND communication BETWEEN 0 AND 20 AND teamwork BETWEEN 0 AND 20 AND fitness BETWEEN 0 AND 20 AND consistency BETWEEN 0 AND 20),
 CONSTRAINT referee_attr_source_chk CHECK(source IN ('none','playpro_assessment','organic_lto','hybrid')));

CREATE OR REPLACE VIEW public.v_referee_match_stats AS
SELECT r.id referee_id,r.referee_code,r.full_name,
 count(DISTINCT f.id) FILTER(WHERE f.status::text IN ('completed','finalized')) matches_officiated,
 count(me.id) FILTER(WHERE me.event_type::text='foul' AND me.voided_at IS NULL) fouls_recorded,
 count(me.id) FILTER(WHERE me.event_type::text='yellow_card' AND me.voided_at IS NULL) yellow_cards,
 count(me.id) FILTER(WHERE me.event_type::text IN ('red_card','second_yellow') AND me.voided_at IS NULL) red_cards,
 count(me.id) FILTER(WHERE me.event_type::text IN ('penalty_kick','penalty_scored','penalty_missed','penalty_saved') AND me.voided_at IS NULL) penalty_events
FROM public.referees r
LEFT JOIN public.referee_assignments ra ON ra.profile_id=r.user_id AND ra.status IN ('assigned','accepted','completed')
LEFT JOIN public.fixtures f ON f.id=ra.fixture_id
LEFT JOIN public.match_events me ON me.fixture_id=f.id AND me.recorded_by=r.user_id
GROUP BY r.id,r.referee_code,r.full_name;

CREATE TABLE IF NOT EXISTS public.profile_ratings(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),target_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,rater_profile_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
 target_role text NOT NULL,rating_value smallint NOT NULL,reason_code text NOT NULL,comment text,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT profile_rating_value_chk CHECK(rating_value BETWEEN 1 AND 4),
 CONSTRAINT profile_rating_role_chk CHECK(target_role IN ('player','coach','referee','club_owner','organizer','club','staff')),
 CONSTRAINT profile_rating_reason_chk CHECK(reason_code IN ('integrity','professionalism','discipline','reliability','communication','respect','performance','other')),
 CONSTRAINT profile_rating_self_chk CHECK(target_profile_id<>rater_profile_id));
CREATE UNIQUE INDEX IF NOT EXISTS profile_ratings_one_vote_uq ON public.profile_ratings(target_profile_id,rater_profile_id,target_role);
CREATE INDEX IF NOT EXISTS profile_ratings_target_idx ON public.profile_ratings(target_profile_id,target_role,created_at DESC);

COMMIT;
