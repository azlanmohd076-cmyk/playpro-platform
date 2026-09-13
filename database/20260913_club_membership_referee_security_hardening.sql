-- PLAYPRO SECURITY HARDENING
-- Exact identity lookup restricted to self or club owner/admin.
-- RLS enabled for new membership, payment, referee and rating tables.
BEGIN;

CREATE OR REPLACE FUNCTION public.playpro_membership_lookup(p_lookup_type text,p_lookup_value text)
RETURNS TABLE(profile_id uuid,playpro_id text,display_name text,role_code text,kyc_verified boolean,has_player boolean,has_coach boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid:=auth.uid(); v_manager boolean;
BEGIN
 IF v_uid IS NULL THEN RETURN; END IF;
 SELECT EXISTS(SELECT 1 FROM public.clubs c WHERE public.playpro_is_club_manager(c.id)) INTO v_manager;
 IF NOT v_manager AND NOT ((lower(p_lookup_type)='playpro_id' AND EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=v_uid AND p.playpro_id=trim(p_lookup_value))) OR (lower(p_lookup_type)='ic' AND EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=v_uid AND p.ic_number=regexp_replace(trim(p_lookup_value),'[^0-9A-Za-z]','','g')))) THEN
   RAISE EXCEPTION 'Carian identiti hanya untuk pemilik/admin kelab atau pemilik identiti.' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT p.id,p.playpro_id,p.full_name,p.role::text,public.playpro_profile_kyc_verified(p.id),EXISTS(SELECT 1 FROM public.players pl WHERE pl.profile_id=p.id),EXISTS(SELECT 1 FROM public.coaches co WHERE co.profile_id=p.id)
 FROM public.profiles p WHERE (lower(p_lookup_type)='playpro_id' AND p.playpro_id=trim(p_lookup_value)) OR (lower(p_lookup_type)='ic' AND p.ic_number=regexp_replace(trim(p_lookup_value),'[^0-9A-Za-z]','','g')) LIMIT 1;
END; $$;
REVOKE ALL ON FUNCTION public.playpro_membership_lookup(text,text) FROM PUBLIC;GRANT EXECUTE ON FUNCTION public.playpro_membership_lookup(text,text) TO authenticated;

ALTER TABLE public.club_membership_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_membership_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_membership_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referee_license_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referee_accreditations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referee_attribute_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_ratings ENABLE ROW LEVEL SECURITY;

GRANT SELECT,INSERT,UPDATE ON public.club_membership_settings TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.club_membership_requests TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.club_membership_payments TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.referee_license_documents TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.referee_accreditations TO authenticated;
GRANT SELECT ON public.referee_attribute_state TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.profile_ratings TO authenticated;

DROP POLICY IF EXISTS cms_select ON public.club_membership_settings;
CREATE POLICY cms_select ON public.club_membership_settings FOR SELECT TO authenticated USING(public.playpro_is_club_manager(club_id) OR EXISTS(SELECT 1 FROM public.clubs c WHERE c.id=club_id AND c.verification_status='verified'));
DROP POLICY IF EXISTS cms_manage ON public.club_membership_settings;
CREATE POLICY cms_manage ON public.club_membership_settings FOR INSERT TO authenticated WITH CHECK(public.playpro_is_club_manager(club_id));
DROP POLICY IF EXISTS cms_update ON public.club_membership_settings;
CREATE POLICY cms_update ON public.club_membership_settings FOR UPDATE TO authenticated USING(public.playpro_is_club_manager(club_id)) WITH CHECK(public.playpro_is_club_manager(club_id));

DROP POLICY IF EXISTS cmr_select ON public.club_membership_requests;
CREATE POLICY cmr_select ON public.club_membership_requests FOR SELECT TO authenticated USING(profile_id=auth.uid() OR public.playpro_is_club_manager(club_id) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer'));
DROP POLICY IF EXISTS cmr_insert ON public.club_membership_requests;
CREATE POLICY cmr_insert ON public.club_membership_requests FOR INSERT TO authenticated WITH CHECK(profile_id=auth.uid() OR public.playpro_is_club_manager(club_id));
DROP POLICY IF EXISTS cmr_update ON public.club_membership_requests;
CREATE POLICY cmr_update ON public.club_membership_requests FOR UPDATE TO authenticated USING(profile_id=auth.uid() OR public.playpro_is_club_manager(club_id) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer')) WITH CHECK(profile_id=auth.uid() OR public.playpro_is_club_manager(club_id) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer'));

DROP POLICY IF EXISTS cmp_select ON public.club_membership_payments;
CREATE POLICY cmp_select ON public.club_membership_payments FOR SELECT TO authenticated USING(payer_profile_id=auth.uid() OR public.playpro_is_club_manager(club_id) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer'));
DROP POLICY IF EXISTS cmp_insert ON public.club_membership_payments;
CREATE POLICY cmp_insert ON public.club_membership_payments FOR INSERT TO authenticated WITH CHECK(payer_profile_id=auth.uid() OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer'));
DROP POLICY IF EXISTS cmp_update ON public.club_membership_payments;
CREATE POLICY cmp_update ON public.club_membership_payments FOR UPDATE TO authenticated USING(payer_profile_id=auth.uid() OR public.playpro_is_club_manager(club_id) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer')) WITH CHECK(payer_profile_id=auth.uid() OR public.playpro_is_club_manager(club_id) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer'));

DROP POLICY IF EXISTS rld_select ON public.referee_license_documents;
CREATE POLICY rld_select ON public.referee_license_documents FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.referees r WHERE r.id=referee_id AND (r.user_id=auth.uid() OR r.verification_status='verified')) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer'));
DROP POLICY IF EXISTS rld_insert ON public.referee_license_documents;
CREATE POLICY rld_insert ON public.referee_license_documents FOR INSERT TO authenticated WITH CHECK(EXISTS(SELECT 1 FROM public.referees r WHERE r.id=referee_id AND r.user_id=auth.uid()));
DROP POLICY IF EXISTS rld_update ON public.referee_license_documents;
CREATE POLICY rld_update ON public.referee_license_documents FOR UPDATE TO authenticated USING(EXISTS(SELECT 1 FROM public.referees r WHERE r.id=referee_id AND r.user_id=auth.uid()) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer')) WITH CHECK(EXISTS(SELECT 1 FROM public.referees r WHERE r.id=referee_id AND r.user_id=auth.uid()) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer'));

DROP POLICY IF EXISTS rac_select ON public.referee_accreditations;
CREATE POLICY rac_select ON public.referee_accreditations FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.referees r WHERE r.id=referee_id AND (r.user_id=auth.uid() OR r.verification_status='verified')) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer'));
DROP POLICY IF EXISTS rac_update ON public.referee_accreditations;
CREATE POLICY rac_update ON public.referee_accreditations FOR UPDATE TO authenticated USING(EXISTS(SELECT 1 FROM public.referees r WHERE r.id=referee_id AND r.user_id=auth.uid()) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer')) WITH CHECK(EXISTS(SELECT 1 FROM public.referees r WHERE r.id=referee_id AND r.user_id=auth.uid()) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer'));

DROP POLICY IF EXISTS ras_select ON public.referee_attribute_state;
CREATE POLICY ras_select ON public.referee_attribute_state FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.referees r WHERE r.id=referee_id AND (r.user_id=auth.uid() OR r.verification_status='verified')) OR EXISTS(SELECT 1 FROM public.profiles WHERE id=auth.uid() AND role::text='developer'));

DROP POLICY IF EXISTS pr_select ON public.profile_ratings;
CREATE POLICY pr_select ON public.profile_ratings FOR SELECT TO authenticated USING(true);
DROP POLICY IF EXISTS pr_insert ON public.profile_ratings;
CREATE POLICY pr_insert ON public.profile_ratings FOR INSERT TO authenticated WITH CHECK(rater_profile_id=auth.uid());
DROP POLICY IF EXISTS pr_update ON public.profile_ratings;
CREATE POLICY pr_update ON public.profile_ratings FOR UPDATE TO authenticated USING(rater_profile_id=auth.uid()) WITH CHECK(rater_profile_id=auth.uid());

COMMIT;
