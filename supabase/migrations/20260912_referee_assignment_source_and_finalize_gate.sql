-- PlayPro Match Gate Repair — referee assignment is the official approval authority.
-- This migration is the concrete implementation of DEC-072..074.

BEGIN;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typnamespace='public'::regnamespace AND typname='fixture_official_role') THEN
    CREATE TYPE public.fixture_official_role AS ENUM ('referee','assistant_referee_1','assistant_referee_2','observer_team_a','observer_team_b','match_start_operator');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.referee_assignments(
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(), fixture_id UUID NOT NULL REFERENCES public.fixtures(id) ON DELETE CASCADE,
 profile_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT, role public.fixture_official_role NOT NULL,
 slot_no INTEGER NOT NULL DEFAULT 1, scope public.match_observer_scope, is_start_operator BOOLEAN NOT NULL DEFAULT false,
 assigned_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL, assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(), accepted_at TIMESTAMPTZ,
 status TEXT NOT NULL DEFAULT 'assigned', notes TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_referee_assignments_fixture ON public.referee_assignments(fixture_id);
CREATE INDEX IF NOT EXISTS idx_referee_assignments_profile ON public.referee_assignments(profile_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_referee_assignments_fixture_role_slot ON public.referee_assignments(fixture_id,role,slot_no);
CREATE UNIQUE INDEX IF NOT EXISTS uq_referee_assignments_one_referee ON public.referee_assignments(fixture_id) WHERE role='referee';
CREATE UNIQUE INDEX IF NOT EXISTS uq_referee_assignments_one_start_operator ON public.referee_assignments(fixture_id) WHERE is_start_operator=true;

INSERT INTO public.referee_assignments(fixture_id,profile_id,role,slot_no,assigned_at,status,notes)
SELECT f.id,f.referee_id,'referee'::public.fixture_official_role,1,coalesce(f.updated_at,now()),'assigned','Backfilled from legacy fixtures.referee_id'
FROM public.fixtures f WHERE f.referee_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.referee_assignments ra WHERE ra.fixture_id=f.id AND ra.role='referee');

CREATE OR REPLACE FUNCTION public.finalize_match(p_fixture_id UUID) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_referee_profile_id UUID;v_result_exists BOOLEAN;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';END IF;
 SELECT ra.profile_id INTO v_referee_profile_id FROM public.referee_assignments ra JOIN public.fixtures f ON f.id=ra.fixture_id WHERE ra.fixture_id=p_fixture_id AND ra.role='referee'::public.fixture_official_role AND ra.status IN('assigned','accepted','active') AND f.match_state='ended' ORDER BY ra.assigned_at DESC LIMIT 1;
 IF v_referee_profile_id IS NULL THEN RAISE EXCEPTION 'Match must be ENDED and have an appointed referee before approval';END IF;
 IF v_referee_profile_id<>auth.uid() THEN RAISE EXCEPTION 'Only the appointed referee can approve/finalize this match' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role='referee'::public.user_role) THEN RAISE EXCEPTION 'Authenticated approver must have referee role' USING ERRCODE='42501';END IF;
 SELECT EXISTS(SELECT 1 FROM public.match_results mr WHERE mr.fixture_id=p_fixture_id) INTO v_result_exists;
 IF NOT v_result_exists THEN RAISE EXCEPTION 'MATCH REPORT/result is required before referee approval';END IF;
 UPDATE public.match_results SET is_official=true,ratified_by=auth.uid(),ratified_at=now(),entered_by=coalesce(entered_by,auth.uid()),updated_at=now() WHERE fixture_id=p_fixture_id AND is_official=false;
 IF NOT FOUND AND NOT EXISTS(SELECT 1 FROM public.match_results WHERE fixture_id=p_fixture_id AND is_official=true AND ratified_by=auth.uid()) THEN RAISE EXCEPTION 'Match result is already official and was ratified by another authority';END IF;
 UPDATE public.fixtures SET match_state='finalized',updated_at=now() WHERE id=p_fixture_id AND match_state='ended';
 IF NOT FOUND THEN RAISE EXCEPTION 'Match finalization failed because the fixture state changed';END IF;
 RETURN true;
END;$$;
REVOKE ALL ON FUNCTION public.finalize_match(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finalize_match(UUID) TO authenticated;

ALTER TABLE public.referee_assignments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.referee_assignments FROM anon,authenticated;
GRANT SELECT ON public.referee_assignments TO authenticated;
DROP POLICY IF EXISTS "officials can view their assignments" ON public.referee_assignments;
CREATE POLICY "officials can view their assignments" ON public.referee_assignments FOR SELECT TO authenticated USING(profile_id=(SELECT auth.uid()) OR EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=(SELECT auth.uid()) AND p.role IN('developer','league_admin')));

COMMIT;
