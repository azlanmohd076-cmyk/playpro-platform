BEGIN;
UPDATE public.players SET football_passport_no=NULL WHERE verification_status<>'verified' AND football_passport_no IS NOT NULL;
COMMIT;