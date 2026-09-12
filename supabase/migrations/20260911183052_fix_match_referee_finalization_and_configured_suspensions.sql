-- PlayPro migration: referee-gated finalization + configurable suspensions
-- Applied in Supabase as migration 20260911183052.
-- Scope: additive schema + function/trigger corrections.

CREATE TABLE IF NOT EXISTS public.competition_rule_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  league_id UUID NOT NULL UNIQUE REFERENCES public.leagues(id) ON DELETE CASCADE,
  red_card_suspension_matches INTEGER NOT NULL,
  second_yellow_suspension_matches INTEGER NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  effective_from TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to TIMESTAMPTZ,
  updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT competition_rule_config_red_card_chk CHECK (red_card_suspension_matches > 0),
  CONSTRAINT competition_rule_config_second_yellow_chk CHECK (second_yellow_suspension_matches > 0),
  CONSTRAINT competition_rule_config_dates_chk CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX IF NOT EXISTS idx_competition_rule_config_league
  ON public.competition_rule_config(league_id);
CREATE INDEX IF NOT EXISTS idx_competition_rule_config_effective
  ON public.competition_rule_config(league_id, effective_from, effective_to);

-- Current PlayPro defaults are configuration data, not function fallbacks.
INSERT INTO public.competition_rule_config (
  league_id, red_card_suspension_matches, second_yellow_suspension_matches
)
SELECT id, 2, 1
FROM public.leagues
ON CONFLICT (league_id) DO NOTHING;

ALTER TABLE public.suspensions
  ADD COLUMN IF NOT EXISTS club_id UUID REFERENCES public.clubs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rule_config_id UUID REFERENCES public.competition_rule_config(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS matches_remaining INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS served_fixture_ids UUID[] NOT NULL DEFAULT '{}'::uuid[],
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

UPDATE public.suspensions
SET matches_remaining = GREATEST(matches_suspended - matches_served, 0),
    is_active = (matches_served < matches_suspended)
WHERE true;

-- Remove the obsolete universal fallback of one match.
ALTER TABLE public.suspensions
  ALTER COLUMN matches_suspended DROP DEFAULT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_suspensions_fixture_reason
  ON public.suspensions(player_id, league_id, start_fixture_id, suspension_reason)
  WHERE start_fixture_id IS NOT NULL;

-- Official finalization is performed by the appointed referee.
-- Referee approval writes the existing match_results ratification gate.
CREATE OR REPLACE FUNCTION public.finalize_match(p_fixture_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE
  v_referee_id UUID;
  v_profile_role public.user_role;
  v_result_exists BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT f.referee_id INTO v_referee_id
  FROM public.fixtures f
  WHERE f.id = p_fixture_id AND f.match_state = 'ended';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Match must be ENDED before referee approval';
  END IF;

  IF v_referee_id IS NULL OR v_referee_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the appointed referee can approve/finalize this match';
  END IF;

  SELECT p.role INTO v_profile_role
  FROM public.profiles p WHERE p.id = auth.uid();

  IF v_profile_role IS DISTINCT FROM 'referee'::public.user_role THEN
    RAISE EXCEPTION 'Authenticated finalizer must have referee role';
  END IF;

  SELECT EXISTS (SELECT 1 FROM public.match_results mr WHERE mr.fixture_id = p_fixture_id)
    INTO v_result_exists;

  IF NOT v_result_exists THEN
    RAISE EXCEPTION 'MATCH REPORT/result is required before referee approval';
  END IF;

  UPDATE public.match_results
  SET is_official = true,
      ratified_by = auth.uid(),
      ratified_at = now(),
      entered_by = COALESCE(entered_by, auth.uid()),
      updated_at = now()
  WHERE fixture_id = p_fixture_id AND is_official = false;

  IF NOT FOUND AND NOT EXISTS (
    SELECT 1 FROM public.match_results
    WHERE fixture_id = p_fixture_id AND is_official = true AND ratified_by = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Match result is already official and was ratified by another authority';
  END IF;

  UPDATE public.fixtures
  SET match_state = 'finalized', updated_at = now()
  WHERE id = p_fixture_id AND match_state = 'ended';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Match finalization failed because the fixture state changed';
  END IF;

  RETURN TRUE;
END;
$$;

-- Suspension length is read from competition_rule_config.
-- There is intentionally no hard-coded one-match fallback.
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
      IF v_player_club IN (v_home_club, v_away_club) THEN v_club_id := v_player_club; END IF;
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

-- An official fixture serves one match of an active suspension for that team.
-- The suspended player does not need to be registered/selected in the serving match.
CREATE OR REPLACE FUNCTION public.advance_suspensions_on_official_result()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, pg_temp
AS $$
DECLARE
  v_home_club UUID;
  v_away_club UUID;
  v_league_id UUID;
BEGIN
  IF (TG_OP = 'INSERT' AND NEW.is_official = true)
     OR (TG_OP = 'UPDATE' AND OLD.is_official = false AND NEW.is_official = true) THEN
    SELECT f.home_club_id, f.away_club_id, f.league_id
      INTO v_home_club, v_away_club, v_league_id
    FROM public.fixtures f WHERE f.id = NEW.fixture_id;

    UPDATE public.suspensions s
    SET matches_served = LEAST(s.matches_suspended, s.matches_served + 1),
        matches_remaining = GREATEST(s.matches_suspended - (s.matches_served + 1), 0),
        served_fixture_ids = array_append(s.served_fixture_ids, NEW.fixture_id),
        is_active = (s.matches_served + 1) < s.matches_suspended,
        completed_at = CASE WHEN (s.matches_served + 1) >= s.matches_suspended THEN now() ELSE s.completed_at END,
        updated_at = now()
    WHERE s.is_active = true
      AND s.league_id = v_league_id
      AND s.club_id IN (v_home_club, v_away_club)
      AND s.start_fixture_id IS DISTINCT FROM NEW.fixture_id
      AND NOT (NEW.fixture_id = ANY(s.served_fixture_ids));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_advance_suspensions_on_official_result ON public.match_results;
CREATE TRIGGER trg_advance_suspensions_on_official_result
AFTER INSERT OR UPDATE ON public.match_results
FOR EACH ROW EXECUTE FUNCTION public.advance_suspensions_on_official_result();
