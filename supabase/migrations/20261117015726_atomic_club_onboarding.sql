CREATE OR REPLACE FUNCTION public.save_my_club_onboarding(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_club jsonb;
  v_venue jsonb;
  v_club_id uuid;
BEGIN
  PERFORM public.playpro_require_active_account();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;

  v_club := public.create_playpro_club(p_payload);
  v_club_id := (v_club->>'club_id')::uuid;

  IF nullif(trim(p_payload->>'ground_name'),'') IS NOT NULL THEN
    v_venue := public.save_club_training_venue(
      v_club_id,
      jsonb_build_object(
        'name',p_payload->>'ground_name',
        'address',p_payload->>'ground_address',
        'city',p_payload->>'district',
        'state',p_payload->>'state',
        'country',coalesce(nullif(trim(p_payload->>'country'),''),'Malaysia'),
        'google_maps_url',p_payload->>'map_url',
        'is_primary',true,
        'notes','Padang latihan utama yang dihantar melalui onboarding kelab'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'success',true,
    'club_id',v_club_id,
    'club_code',v_club->>'club_code',
    'slug',v_club->>'slug',
    'verification_status',v_club->>'verification_status',
    'venue',v_venue
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.save_my_club_onboarding(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_my_club_onboarding(jsonb) TO authenticated;

COMMENT ON FUNCTION public.save_my_club_onboarding(jsonb) IS
  'Atomic authenticated club and primary training venue onboarding. Club recognition remains pending until reviewed.';
