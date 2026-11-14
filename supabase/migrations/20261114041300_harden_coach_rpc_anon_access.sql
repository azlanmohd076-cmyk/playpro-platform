-- Keep Coach RPC entry points authenticated; internal role/ownership checks remain authoritative.
REVOKE ALL ON FUNCTION public.add_club_roster_coach(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_club_roster_coach(uuid,text,text) TO authenticated;

REVOKE ALL ON FUNCTION public.attach_coach_kyc_documents(uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_coach_kyc_documents(uuid,jsonb) TO authenticated;

REVOKE ALL ON FUNCTION public.get_coach_kyc_admin_list() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_coach_kyc_admin_list() TO authenticated;

REVOKE ALL ON FUNCTION public.get_my_coach_profile() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_coach_profile() TO authenticated;
