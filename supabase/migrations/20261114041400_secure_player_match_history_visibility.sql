CREATE OR REPLACE FUNCTION public.get_player_match_history(
  p_player_id uuid,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_owner uuid;
  v_visibility text;
BEGIN
  SELECT p.profile_id, p.profile_visibility
    INTO v_owner, v_visibility
  FROM public.players p
  WHERE p.id = p_player_id
    AND p.is_active = true;

  IF NOT FOUND THEN
    RETURN '[]'::jsonb;
  END IF;

  IF COALESCE(v_visibility, 'private') = 'private'
     AND (
       v_uid IS NULL
       OR (v_uid <> v_owner AND NOT EXISTS (
         SELECT 1
         FROM public.player_follows pf
         WHERE pf.player_id = p_player_id
           AND pf.follower_profile_id = v_uid
           AND pf.status = 'approved'
       ))
     )
  THEN
    RAISE EXCEPTION 'Profile private'
      USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.match_date DESC), '[]'::jsonb)
    FROM (
      SELECT
        f.id AS fixture_id,
        f.match_date,
        f.round_name,
        f.home_club_id,
        f.away_club_id,
        hc.name AS home_club,
        ac.name AS away_club,
        mr.home_goals,
        mr.away_goals,
        pms.minutes_played,
        pms.goals,
        pms.assists,
        pms.yellow_cards,
        pms.red_cards,
        pms.started
      FROM public.player_match_stats pms
      JOIN public.fixtures f ON f.id = pms.fixture_id
      JOIN public.match_results mr ON mr.fixture_id = f.id AND mr.is_official = true
      LEFT JOIN public.clubs hc ON hc.id = f.home_club_id
      LEFT JOIN public.clubs ac ON ac.id = f.away_club_id
      WHERE pms.player_id = p_player_id
      ORDER BY f.match_date DESC NULLS LAST
      LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
    ) x
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_player_match_history(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_player_match_history(uuid, integer) TO anon, authenticated;
