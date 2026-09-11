-- PlayPro migration: correct team-context lookup in red-card suspension trigger.
-- Applied in Supabase as migration 20260911183122.

CREATE OR REPLACE FUNCTION public.auto_suspend_on_red_card()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE
  v_matches INTEGER;
  v_rule_config_id UUID;
  v_club_id UUID;
  v_home_club UUID;
  v_away_club UUID;
  v_player_club UUID;
  v_match_date TIMESTAMPTZ;
BEGIN
  IF NEW.card_type IN ('red', 'second_yellow') THEN
    SELECT f.home_club_id, f.away_club_id, f.match_date
      INTO v_home_club, v_away_club, v_match_date
    FROM public.fixtures f
    WHERE f.id = NEW.fixture_id AND f.league_id = NEW.league_id;

    IF v_home_club IS NULL OR v_away_club IS NULL THEN
      RAISE EXCEPTION 'Cannot create suspension: fixture % is missing valid team context', NEW.fixture_id;
    END IF;

    SELECT c.id,
           CASE WHEN NEW.card_type = 'red'
                THEN c.red_card_suspension_matches
                ELSE c.second_yellow_suspension_matches END
      INTO v_rule_config_id, v_matches
    FROM public.competition_rule_config c
    WHERE c.league_id = NEW.league_id
      AND c.effective_from <= COALESCE(v_match_date, now())
      AND (c.effective_to IS NULL OR c.effective_to > COALESCE(v_match_date, now()))
    ORDER BY c.version DESC, c.effective_from DESC
    LIMIT 1;

    IF v_rule_config_id IS NULL OR v_matches IS NULL THEN
      RAISE EXCEPTION 'No competition suspension rule configuration exists for league %', NEW.league_id;
    END IF;

    SELECT mp.club_id INTO v_club_id
    FROM public.match_participants mp
    WHERE mp.fixture_id = NEW.fixture_id
      AND mp.player_id = NEW.player_id
      AND mp.club_id IN (v_home_club, v_away_club)
    ORDER BY mp.created_at DESC LIMIT 1;

    IF v_club_id IS NULL THEN
      SELECT p.club_id INTO v_player_club FROM public.players p WHERE p.id = NEW.player_id;
      IF v_player_club IN (v_home_club, v_away_club) THEN
        v_club_id := v_player_club;
      END IF;
    END IF;

    IF v_club_id IS NULL THEN
      RAISE EXCEPTION 'Cannot create suspension: player % has no valid team context for fixture %', NEW.player_id, NEW.fixture_id;
    END IF;

    INSERT INTO public.suspensions (
      player_id, league_id, club_id, rule_config_id, suspension_reason,
      matches_suspended, matches_served, matches_remaining, served_fixture_ids,
      start_fixture_id, reason_notes, is_active, imposed_by
    ) VALUES (
      NEW.player_id, NEW.league_id, v_club_id, v_rule_config_id, 'automatic_red_card',
      v_matches, 0, v_matches, '{}'::uuid[], NEW.fixture_id,
      CASE WHEN NEW.card_type = 'second_yellow'
        THEN 'Automatic suspension for second-yellow dismissal on ' || NEW.match_date::TEXT
        ELSE 'Automatic suspension for red card on ' || NEW.match_date::TEXT END,
      true, NEW.created_by
    )
    ON CONFLICT (player_id, league_id, start_fixture_id, suspension_reason)
    WHERE start_fixture_id IS NOT NULL DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;
