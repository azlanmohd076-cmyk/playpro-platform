BEGIN;

CREATE OR REPLACE FUNCTION public.playpro_referee_respond_assignment(p_assignment_id uuid,p_decision text,p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE v_uid uuid:=auth.uid(); v_status text; v_profile uuid; v_role public.fixture_official_role;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  IF p_decision NOT IN ('accepted','declined') THEN RAISE EXCEPTION 'Keputusan assignment tidak sah' USING ERRCODE='22023'; END IF;
  SELECT profile_id,status,role INTO v_profile,v_status,v_role FROM public.referee_assignments WHERE id=p_assignment_id FOR UPDATE;
  IF v_profile IS NULL THEN RAISE EXCEPTION 'Assignment tidak ditemui' USING ERRCODE='P0002'; END IF;
  IF v_profile<>v_uid THEN RAISE EXCEPTION 'Hanya pengadil yang ditugaskan boleh menjawab assignment' USING ERRCODE='42501'; END IF;
  IF v_role<>'referee'::public.fixture_official_role THEN RAISE EXCEPTION 'Workflow ini hanya untuk lead referee' USING ERRCODE='22023'; END IF;
  IF v_status NOT IN ('assigned','accepted') THEN RAISE EXCEPTION 'Assignment tidak lagi boleh diubah: %',v_status USING ERRCODE='55000'; END IF;
  IF p_decision='accepted' THEN
    UPDATE public.referee_assignments SET status='accepted',accepted_at=COALESCE(accepted_at,now()),notes=COALESCE(NULLIF(trim(p_note),''),notes),updated_at=now() WHERE id=p_assignment_id;
  ELSE
    UPDATE public.referee_assignments SET status='declined',notes=COALESCE(NULLIF(trim(p_note),''),notes),updated_at=now() WHERE id=p_assignment_id;
  END IF;
  RETURN jsonb_build_object('success',true,'assignment_id',p_assignment_id,'status',p_decision);
END;
$$;

REVOKE ALL ON FUNCTION public.playpro_referee_respond_assignment(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.playpro_referee_respond_assignment(uuid,text,text) TO authenticated;

COMMIT;
