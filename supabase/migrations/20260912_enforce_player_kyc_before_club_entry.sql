-- PLAYPRO — KYC gate before club entry

BEGIN;

CREATE OR REPLACE FUNCTION public.prevent_unverified_player_club_entry()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.club_id IS NOT NULL AND NEW.verification_status <> 'verified' THEN
    RAISE EXCEPTION 'Player KYC diperlukan sebelum pemain boleh dimasukkan ke kelab.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_require_player_kyc_for_club ON public.players;
CREATE TRIGGER trg_require_player_kyc_for_club
BEFORE INSERT OR UPDATE OF club_id, verification_status ON public.players
FOR EACH ROW
EXECUTE FUNCTION public.prevent_unverified_player_club_entry();

CREATE OR REPLACE FUNCTION public.player_is_kyc_verified(p_player_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.players
    WHERE id = p_player_id AND is_active = true AND verification_status = 'verified'
  );
$$;

REVOKE ALL ON FUNCTION public.player_is_kyc_verified(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.player_is_kyc_verified(UUID) TO anon, authenticated;

COMMIT;
