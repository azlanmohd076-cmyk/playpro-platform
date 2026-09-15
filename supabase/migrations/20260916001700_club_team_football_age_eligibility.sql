-- PlayPro: club squad eligibility must use football-age semantics.
-- Football age = competition/current year - birth year; birthday timing is irrelevant.
-- This mirrors the production migration applied to playpro2.

CREATE OR REPLACE FUNCTION public.add_player_to_club_team(p_team_id uuid, p_player_id uuid, p_jersey smallint DEFAULT NULL::smallint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_club_id uuid;
  v_age_category text;
  v_dob date;
  v_football_age integer;
  v_min_age integer;
  v_player_profile uuid;
BEGIN
  SELECT t.club_id, t.age_category
    INTO v_club_id, v_age_category
  FROM public.club_teams t
  WHERE t.id = p_team_id;

  IF v_club_id IS NULL THEN
    RAISE EXCEPTION 'Squad tidak ditemui.' USING ERRCODE='P0002';
  END IF;

  IF v_uid IS NULL OR NOT public.playpro_is_club_manager(v_club_id) THEN
    RAISE EXCEPTION 'Akses squad tidak dibenarkan.' USING ERRCODE='42501';
  END IF;

  SELECT p.date_of_birth, p.profile_id
    INTO v_dob, v_player_profile
  FROM public.players p
  WHERE p.id = p_player_id
    AND p.is_active = true;

  IF v_dob IS NULL THEN
    RAISE EXCEPTION 'Pemain tidak ditemui.' USING ERRCODE='P0002';
  END IF;

  IF v_player_profile IS NULL OR NOT public.playpro_profile_kyc_verified(v_player_profile) THEN
    RAISE EXCEPTION 'Pemain mesti mempunyai KYC PlayPro yang disahkan sebelum masuk kelab.' USING ERRCODE='42501';
  END IF;

  v_football_age := EXTRACT(YEAR FROM current_date)::integer - EXTRACT(YEAR FROM v_dob)::integer;

  IF v_age_category = 'veteran' THEN
    IF v_football_age < 35 THEN
      RAISE EXCEPTION 'Pemain belum mencapai umur Veteran (35+).';
    END IF;
  ELSIF v_age_category <> 'open' THEN
    v_min_age := substring(v_age_category from 2)::integer;
    IF v_football_age < v_min_age THEN
      RAISE EXCEPTION 'Pemain football age % tidak layak untuk squad %.', v_football_age, upper(v_age_category);
    END IF;
  END IF;

  INSERT INTO public.club_memberships(club_id, profile_id, role_code, status, created_by)
  VALUES(v_club_id, v_player_profile, 'player', 'active', v_uid)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.club_team_players(team_id, player_id, jersey_number, created_by)
  VALUES(p_team_id, p_player_id, p_jersey, v_uid)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'team_id', p_team_id,
    'player_id', p_player_id,
    'football_age', v_football_age,
    'age_category', v_age_category
  );
END;
$function$;
