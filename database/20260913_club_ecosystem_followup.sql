-- PLAYPRO CLUB FOLLOW-UP
-- Completes tactical-template persistence and final dashboard payload.
BEGIN;

CREATE TABLE IF NOT EXISTS public.club_team_tactics(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id uuid NOT NULL UNIQUE REFERENCES public.club_teams(id) ON DELETE CASCADE,
  formation text NOT NULL DEFAULT '4-3-3',
  lineup jsonb NOT NULL DEFAULT '[]'::jsonb,
  bench jsonb NOT NULL DEFAULT '[]'::jsonb,
  notes text,
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT club_team_tactics_formation_chk CHECK(formation IN('3-4-3','4-3-3','3-5-2','3-4-2-1','4-2-3-1','4-4-2','4-1-4-1','5-3-2','5-4-1'))
);
ALTER TABLE public.club_team_tactics ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE ON public.club_team_tactics TO authenticated;
DROP POLICY IF EXISTS club_team_tactics_read ON public.club_team_tactics;
CREATE POLICY club_team_tactics_read ON public.club_team_tactics FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t JOIN public.clubs c ON c.id=t.club_id WHERE t.id=team_id AND(c.verification_status='verified' OR public.playpro_is_club_manager(c.id))));
DROP POLICY IF EXISTS club_team_tactics_manage ON public.club_team_tactics;
CREATE POLICY club_team_tactics_manage ON public.club_team_tactics FOR INSERT TO authenticated WITH CHECK(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id)));
DROP POLICY IF EXISTS club_team_tactics_update ON public.club_team_tactics;
CREATE POLICY club_team_tactics_update ON public.club_team_tactics FOR UPDATE TO authenticated USING(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id))) WITH CHECK(EXISTS(SELECT 1 FROM public.club_teams t WHERE t.id=team_id AND public.playpro_is_club_manager(t.club_id)));

CREATE OR REPLACE FUNCTION public.save_team_tactics(p_team_id uuid,p_formation text,p_lineup jsonb,p_bench jsonb DEFAULT '[]'::jsonb,p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_uid uuid:=(SELECT auth.uid());v_club_id uuid;
BEGIN
SELECT club_id INTO v_club_id FROM public.club_teams WHERE id=p_team_id;
IF v_uid IS NULL OR v_club_id IS NULL OR NOT public.playpro_is_club_manager(v_club_id) THEN RAISE EXCEPTION 'Akses taktikal tidak dibenarkan.' USING ERRCODE='42501';END IF;
IF p_formation NOT IN('3-4-3','4-3-3','3-5-2','3-4-2-1','4-2-3-1','4-4-2','4-1-4-1','5-3-2','5-4-1') THEN RAISE EXCEPTION 'Formation tidak sah.' USING ERRCODE='22023';END IF;
INSERT INTO public.club_team_tactics(team_id,formation,lineup,bench,notes,updated_by) VALUES(p_team_id,p_formation,coalesce(p_lineup,'[]'::jsonb),coalesce(p_bench,'[]'::jsonb),p_notes,v_uid) ON CONFLICT(team_id) DO UPDATE SET formation=excluded.formation,lineup=excluded.lineup,bench=excluded.bench,notes=excluded.notes,updated_by=excluded.updated_by,updated_at=now();
UPDATE public.club_teams SET formation=p_formation,updated_at=now() WHERE id=p_team_id;
RETURN jsonb_build_object('success',true,'team_id',p_team_id,'formation',p_formation);
END;$$;
REVOKE ALL ON FUNCTION public.save_team_tactics(uuid,text,jsonb,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_team_tactics(uuid,text,jsonb,jsonb,text) TO authenticated;

DROP FUNCTION IF EXISTS public.get_my_club_dashboard();
CREATE FUNCTION public.get_my_club_dashboard()
RETURNS TABLE(club_id uuid,club_name text,club_code text,club_type text,club_logo_url text,verification_status text,city text,state text,description text,year_founded integer,ros_registration_no text,contact_phone text,whatsapp_phone text,visibility text,team_count bigint,member_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
SELECT c.id,c.name,c.club_code,c.club_type,c.logo_url,c.verification_status,c.city,c.state,c.description,c.year_founded,c.ros_registration_no,c.contact_phone,c.whatsapp_phone,c.visibility,(SELECT count(*) FROM public.club_teams t WHERE t.club_id=c.id AND t.status='active'),(SELECT count(*) FROM public.club_memberships m WHERE m.club_id=c.id AND m.status='active') FROM public.clubs c WHERE public.playpro_is_club_manager(c.id) ORDER BY c.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_my_club_dashboard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_club_dashboard() TO authenticated;

COMMIT;