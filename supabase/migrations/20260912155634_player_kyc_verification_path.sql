-- PLAYPRO — Player KYC verification path
-- Live migration version: 20260912155634

BEGIN;

ALTER TABLE public.players ADD COLUMN IF NOT EXISTS legal_name_locked_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_players_verification_status ON public.players(verification_status);

CREATE OR REPLACE FUNCTION public.prevent_verified_player_identity_edit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF OLD.verification_status = 'verified' THEN
    IF NEW.full_name IS DISTINCT FROM OLD.full_name AND COALESCE(current_setting('playpro.kyc_approval', true), '') <> 'true' THEN
      RAISE EXCEPTION 'Nama sah pemain telah dikunci selepas KYC. Hanya nama samaran boleh diubah.' USING ERRCODE = '42501';
    END IF;
    IF NEW.date_of_birth IS DISTINCT FROM OLD.date_of_birth AND COALESCE(current_setting('playpro.kyc_approval', true), '') <> 'true' THEN
      RAISE EXCEPTION 'Tarikh lahir pemain telah dikunci selepas KYC.' USING ERRCODE = '42501';
    END IF;
    IF NEW.profile_id IS DISTINCT FROM OLD.profile_id AND COALESCE(current_setting('playpro.kyc_approval', true), '') <> 'true' THEN
      RAISE EXCEPTION 'Identiti akaun pemain telah dikunci selepas KYC.' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lock_verified_player_identity ON public.players;
CREATE TRIGGER trg_lock_verified_player_identity BEFORE UPDATE ON public.players FOR EACH ROW EXECUTE FUNCTION public.prevent_verified_player_identity_edit();

CREATE OR REPLACE FUNCTION public.approve_player_kyc(
  p_kyc_id UUID, p_reviewer_note TEXT DEFAULT NULL, p_verified_legal_name TEXT DEFAULT NULL,
  p_verified_birth_date DATE DEFAULT NULL, p_verified_birth_state_code TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid UUID := (SELECT auth.uid()); v_k public.identity_verifications%ROWTYPE; v_player public.players%ROWTYPE;
  v_verified_name TEXT; v_verified_dob DATE; v_state TEXT; v_no BIGINT; v_prefix TEXT; v_passport TEXT;
BEGIN
  IF v_uid IS NULL OR NOT public.is_league_founder_or_developer() THEN RAISE EXCEPTION 'KYC approval requires PlayPro privileged access' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_k FROM public.identity_verifications WHERE id=p_kyc_id AND subject_type='player' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'KYC request not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_player FROM public.players WHERE profile_id=v_k.profile_id AND is_active=true LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Player profile not found' USING ERRCODE='P0002'; END IF;
  IF v_k.status='verified' THEN RETURN jsonb_build_object('ok',true,'status','verified','player_id',v_player.id,'football_passport_no',v_player.football_passport_no); END IF;
  IF v_k.status<>'pending' THEN RAISE EXCEPTION 'KYC request is not awaiting approval' USING ERRCODE='40901'; END IF;
  v_verified_name := NULLIF(BTRIM(COALESCE(p_verified_legal_name,v_k.extracted_legal_name)),'');
  IF v_verified_name IS NULL THEN RAISE EXCEPTION 'Nama sah daripada dokumen belum tersedia. Reviewer mesti memasukkan nama sah yang disahkan.' USING ERRCODE='22023'; END IF;
  v_verified_dob := COALESCE(v_k.extracted_birth_date,p_verified_birth_date,v_player.date_of_birth);
  IF p_verified_birth_date IS NOT NULL AND p_verified_birth_date<>v_player.date_of_birth THEN RAISE EXCEPTION 'Tarikh lahir yang disahkan tidak sepadan dengan profil pemain.' USING ERRCODE='22023'; END IF;
  IF v_k.extracted_birth_date IS NOT NULL AND v_k.extracted_birth_date<>v_player.date_of_birth AND p_verified_birth_date IS NULL THEN RAISE EXCEPTION 'Tarikh lahir dokumen tidak sepadan. Reviewer mesti mengesahkan semula.' USING ERRCODE='22023'; END IF;
  v_state := COALESCE(NULLIF(BTRIM(p_verified_birth_state_code),''),NULLIF(BTRIM(v_k.birth_state_code),''));
  IF v_state IS NULL OR v_state !~ '^[0-9]{2}$' THEN RAISE EXCEPTION 'Kod negeri kelahiran mesti 2 digit.' USING ERRCODE='22023'; END IF;
  v_no := nextval('public.playpro_passport_user_no_seq');
  v_prefix := upper(right(regexp_replace(split_part(trim(v_verified_name),' ',1),'[^A-Za-z]','','g'),4));
  IF length(v_prefix)<4 THEN v_prefix:=upper(rpad(v_prefix,4,'X')); END IF;
  v_passport := v_prefix||'-'||v_state||'-'||lpad(v_no::text,4,'0');
  PERFORM set_config('playpro.kyc_approval','true',true);
  UPDATE public.players SET full_name=v_verified_name,date_of_birth=v_verified_dob,verification_status='verified',legal_name_locked_at=now(),verified_at=now(),verified_by=v_uid,football_passport_no=v_passport,updated_at=now() WHERE id=v_player.id;
  UPDATE public.profiles SET full_name=v_verified_name,updated_at=now() WHERE id=v_player.profile_id;
  UPDATE public.identity_verifications SET status='verified',reviewer_profile_id=v_uid,reviewer_note=p_reviewer_note,reviewed_at=now(),provider_status=COALESCE(provider_status,'processed'),updated_at=now() WHERE id=v_k.id;
  RETURN jsonb_build_object('ok',true,'status','verified','player_id',v_player.id,'football_passport_no',v_passport,'playpro_user_no',v_no,'legal_name_locked',true);
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_player_kyc(p_kyc_id UUID,p_reviewer_note TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_uid UUID := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL OR NOT public.is_league_founder_or_developer() THEN RAISE EXCEPTION 'KYC rejection requires PlayPro privileged access' USING ERRCODE='42501'; END IF;
  IF NULLIF(BTRIM(COALESCE(p_reviewer_note,'')),'') IS NULL THEN RAISE EXCEPTION 'Sebab penolakan KYC wajib diisi.' USING ERRCODE='22023'; END IF;
  UPDATE public.identity_verifications SET status='rejected',reviewer_profile_id=v_uid,reviewer_note=p_reviewer_note,reviewed_at=now(),updated_at=now() WHERE id=p_kyc_id AND subject_type='player' AND status IN ('pending','rejected');
  IF NOT FOUND THEN RAISE EXCEPTION 'KYC request not found or already finalised' USING ERRCODE='P0002'; END IF;
  RETURN jsonb_build_object('ok',true,'status','rejected','kyc_id',p_kyc_id);
END;
$$;

REVOKE ALL ON FUNCTION public.approve_player_kyc(UUID,TEXT,TEXT,DATE,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_player_kyc(UUID,TEXT,TEXT,DATE,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.reject_player_kyc(UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_player_kyc(UUID,TEXT) TO authenticated;
COMMENT ON COLUMN public.players.legal_name_locked_at IS 'Masa nama sah/tarikh lahir pemain dikunci selepas KYC disahkan. preferred_name kekal boleh diubah.';

COMMIT;
