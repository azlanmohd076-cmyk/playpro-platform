BEGIN;

-- PlayPro KYC documents are private. The browser may upload and read back its own
-- object metadata, while the verification Edge Function accesses the object server-side.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'kyc-documents',
  'kyc-documents',
  false,
  10485760,
  ARRAY['image/jpeg','image/png','application/pdf']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public=false,
    file_size_limit=10485760,
    allowed_mime_types=ARRAY['image/jpeg','image/png','application/pdf']::text[];

ALTER TABLE public.identity_verifications
  ADD COLUMN IF NOT EXISTS document_storage_paths jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS provider text NOT NULL DEFAULT 'google_document_ai',
  ADD COLUMN IF NOT EXISTS provider_status text,
  ADD COLUMN IF NOT EXISTS extracted_legal_name text,
  ADD COLUMN IF NOT EXISTS extracted_birth_date date,
  ADD COLUMN IF NOT EXISTS extracted_id_type text,
  ADD COLUMN IF NOT EXISTS extracted_identifier_masked text,
  ADD COLUMN IF NOT EXISTS match_status text NOT NULL DEFAULT 'not_processed',
  ADD COLUMN IF NOT EXISTS match_score numeric(5,2),
  ADD COLUMN IF NOT EXISTS processed_at timestamptz;

ALTER TABLE public.identity_verifications
  DROP CONSTRAINT IF EXISTS identity_verifications_document_paths_check;
ALTER TABLE public.identity_verifications
  ADD CONSTRAINT identity_verifications_document_paths_check
  CHECK (jsonb_typeof(document_storage_paths) = 'array' AND jsonb_array_length(document_storage_paths) BETWEEN 0 AND 2);

ALTER TABLE public.identity_verifications
  DROP CONSTRAINT IF EXISTS identity_verifications_match_status_check;
ALTER TABLE public.identity_verifications
  ADD CONSTRAINT identity_verifications_match_status_check
  CHECK (match_status IN ('not_processed','match','mismatch','inconclusive','provider_error'));

CREATE INDEX IF NOT EXISTS idx_identity_verifications_provider_status
  ON public.identity_verifications(provider, provider_status, status);

DROP POLICY IF EXISTS "player kyc upload own document" ON storage.objects;
CREATE POLICY "player kyc upload own document"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'kyc-documents'
  AND (storage.foldername(name))[1] = (select auth.uid()::text)
);

DROP POLICY IF EXISTS "player kyc read own document" ON storage.objects;
CREATE POLICY "player kyc read own document"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'kyc-documents'
  AND owner_id = (select auth.uid()::text)
);

CREATE OR REPLACE FUNCTION public.request_player_kyc_document(
  p_id_type text,
  p_legal_name text,
  p_birth_state_code text,
  p_document_storage_paths jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_uid uuid=(SELECT auth.uid());
  v_player public.players%ROWTYPE;
  v_kyc_id uuid;
  v_paths text[];
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_player FROM public.players
    WHERE profile_id=v_uid AND is_active=true LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player profile not found' USING ERRCODE='P0002';
  END IF;
  IF v_player.verification_status='verified' THEN
    RETURN jsonb_build_object('ok',true,'status','verified','player_id',v_player.id,'football_passport_no',v_player.football_passport_no);
  END IF;
  IF lower(trim(coalesce(p_id_type,''))) NOT IN ('mykad','mykid','passport') THEN
    RAISE EXCEPTION 'KYC mesti menggunakan MyKad, MyKid atau Passport' USING ERRCODE='22023';
  END IF;
  IF nullif(trim(coalesce(p_legal_name,'')),'') IS NULL THEN
    RAISE EXCEPTION 'Nama sah diperlukan untuk KYC' USING ERRCODE='22023';
  END IF;
  IF p_document_storage_paths IS NULL OR jsonb_typeof(p_document_storage_paths)<>'array'
     OR jsonb_array_length(p_document_storage_paths) NOT BETWEEN 1 AND 2 THEN
    RAISE EXCEPTION 'Sila muat naik 1 atau 2 dokumen' USING ERRCODE='22023';
  END IF;
  SELECT array_agg(value::text) INTO v_paths FROM jsonb_array_elements_text(p_document_storage_paths);
  IF EXISTS (
    SELECT 1 FROM unnest(v_paths) path
    WHERE path !~ ('^'||v_uid::text||'/[A-Za-z0-9._-]+$')
  ) THEN
    RAISE EXCEPTION 'Lokasi dokumen KYC tidak sah' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.identity_verifications(
    profile_id,subject_type,id_type,legal_name_claimed,birth_state_code,
    document_storage_paths,provider,provider_status,status,match_status
  ) VALUES (
    v_uid,'player',lower(trim(p_id_type)),trim(p_legal_name),nullif(trim(p_birth_state_code),''),
    p_document_storage_paths,'google_document_ai','queued','pending','not_processed'
  )
  ON CONFLICT (profile_id,subject_type) WHERE status='pending'
  DO UPDATE SET
    id_type=EXCLUDED.id_type,
    legal_name_claimed=EXCLUDED.legal_name_claimed,
    birth_state_code=EXCLUDED.birth_state_code,
    document_storage_paths=EXCLUDED.document_storage_paths,
    provider=EXCLUDED.provider,
    provider_status='queued',
    match_status='not_processed',
    match_score=NULL,
    processed_at=NULL,
    updated_at=now()
  RETURNING id INTO v_kyc_id;
  RETURN jsonb_build_object('ok',true,'status','pending','kyc_id',v_kyc_id,'player_id',v_player.id,'provider','google_document_ai');
END;
$$;

REVOKE ALL ON FUNCTION public.request_player_kyc_document(text,text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_player_kyc_document(text,text,text,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_player_kyc_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_uid uuid=(SELECT auth.uid());
  v_k public.identity_verifications%ROWTYPE;
  v_p public.players%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_p FROM public.players WHERE profile_id=v_uid AND is_active=true LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','PLAYER_NOT_FOUND'); END IF;
  SELECT * INTO v_k FROM public.identity_verifications
    WHERE profile_id=v_uid AND subject_type='player'
    ORDER BY created_at DESC LIMIT 1;
  RETURN jsonb_build_object(
    'ok',true,
    'verification_status',v_p.verification_status,
    'football_passport_no',v_p.football_passport_no,
    'kyc_status',coalesce(v_k.status,'not_submitted'),
    'kyc_id',v_k.id,
    'id_type',v_k.id_type,
    'provider',v_k.provider,
    'provider_status',v_k.provider_status,
    'match_status',v_k.match_status,
    'match_score',v_k.match_score,
    'submitted_at',v_k.submitted_at,
    'processed_at',v_k.processed_at,
    'reviewed_at',v_k.reviewed_at,
    'reviewer_note',v_k.reviewer_note
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_player_kyc_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_player_kyc_status() TO authenticated;

COMMIT;
