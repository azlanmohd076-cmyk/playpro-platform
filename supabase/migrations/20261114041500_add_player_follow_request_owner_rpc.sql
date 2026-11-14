CREATE OR REPLACE FUNCTION public.get_my_player_follow_requests()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_player_id uuid;
  v_requests jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';
  END IF;

  SELECT p.id INTO v_player_id
  FROM public.players p
  WHERE p.profile_id=v_uid AND p.is_active=true
  LIMIT 1;

  IF v_player_id IS NULL THEN
    RETURN jsonb_build_object('ok',true,'requests','[]'::jsonb);
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id',pf.id,
        'follower_profile_id',pf.follower_profile_id,
        'follower_name',COALESCE(
          NULLIF(BTRIM(fp.preferred_name),''),
          NULLIF(BTRIM(fp.full_name),''),
          pr.full_name,
          'Pengguna PlayPro'
        ),
        'requested_at',pf.requested_at
      )
      ORDER BY pf.requested_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_requests
  FROM public.player_follows pf
  JOIN public.profiles pr ON pr.id=pf.follower_profile_id
  LEFT JOIN public.players fp ON fp.profile_id=pr.id AND fp.is_active=true
  WHERE pf.player_id=v_player_id AND pf.status='pending';

  RETURN jsonb_build_object('ok',true,'requests',v_requests);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_my_player_follow_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_player_follow_requests() TO authenticated;
