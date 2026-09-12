-- PLAYPRO — Close legacy KYC paths
-- The document-backed request is the only player KYC submission path.

BEGIN;

DROP FUNCTION IF EXISTS public.approve_player_kyc(UUID,TEXT);

CREATE OR REPLACE FUNCTION public.request_player_kyc(
  p_id_type TEXT,
  p_legal_name TEXT,
  p_birth_state_code TEXT DEFAULT NULL,
  p_masked_identifier TEXT DEFAULT NULL,
  p_provider_reference TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Gunakan laluan Player KYC dengan muat naik dokumen. Buka player_kyc.html.' USING ERRCODE = '22023';
END;
$$;

REVOKE ALL ON FUNCTION public.request_player_kyc(TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_player_kyc(TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;

COMMIT;
