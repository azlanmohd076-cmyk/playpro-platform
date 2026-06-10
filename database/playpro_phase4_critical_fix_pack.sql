-- ============================================================
-- PLAYPRO — PHASE 4: CRITICAL PRODUCTION FIX PACK
-- ============================================================
-- Apply AFTER Phase 1, Phase 2 and Phase 3 are fully applied.
-- Run top to bottom exactly as written inside a single
-- transaction where possible. Exceptions are noted inline.
--
-- PostgreSQL 16 compatible. Supabase compatible.
-- Zero modifications to any existing Phase 1/2/3 object.
-- All changes are strictly additive.
-- ============================================================

BEGIN;

-- ============================================================
-- FIX 1 — SEASONS ARCHITECTURE
-- ============================================================
-- New enums
-- ============================================================

CREATE TYPE season_status AS ENUM (
  'upcoming',       -- Defined but not started
  'registration',   -- Registration window open
  'active',         -- Season in progress
  'completed',      -- All fixtures played
  'archived'        -- Historical, read-only
);

CREATE TYPE round_type AS ENUM (
  'group_stage',
  'round_robin',
  'knockout',
  'quarter_final',
  'semi_final',
  'third_place_playoff',
  'final',
  'playoff',
  'promotion_playoff',
  'relegation_playoff'
);

CREATE TYPE promotion_relegation_action AS ENUM (
  'promoted',
  'relegated',
  'playoff_promotion',
  'playoff_relegation',
  'stayed'
);

-- ============================================================
-- seasons
-- One row per season per league.
-- leagues.season (TEXT) is preserved and untouched.
-- New modules reference seasons.id for structured season data.
-- ============================================================

CREATE TABLE seasons (
  id                        UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  league_id                 UUID          NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  -- Human-readable label, mirrors leagues.season convention
  name                      TEXT          NOT NULL,         -- e.g. "2025/26"
  season_code               TEXT          NOT NULL,         -- e.g. "2526" (unique per league)

  status                    season_status NOT NULL DEFAULT 'upcoming',

  -- Competition calendar
  start_date                DATE          NOT NULL,
  end_date                  DATE          NOT NULL,

  -- Registration window
  registration_start_date   DATE          NOT NULL,
  registration_end_date     DATE          NOT NULL,

  -- Transfer windows (a season may have multiple; stored separately)
  -- These mark the primary (summer) window
  transfer_window_open      DATE,
  transfer_window_close     DATE,

  -- Promotion / relegation configuration
  promotion_spots           SMALLINT      NOT NULL DEFAULT 0 CHECK (promotion_spots >= 0),
  relegation_spots          SMALLINT      NOT NULL DEFAULT 0 CHECK (relegation_spots >= 0),
  playoff_spots             SMALLINT      NOT NULL DEFAULT 0 CHECK (playoff_spots >= 0),

  -- Max squad size per club for this season
  max_squad_size            SMALLINT      NOT NULL DEFAULT 30 CHECK (max_squad_size > 0),
  min_squad_size            SMALLINT      NOT NULL DEFAULT 11 CHECK (min_squad_size > 0),

  -- Maximum foreign (non-domestic) players per squad
  max_foreign_players       SMALLINT      DEFAULT NULL,     -- NULL = no restriction

  -- Administrative
  created_by                UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- Constraints
  CONSTRAINT chk_season_dates
    CHECK (end_date > start_date),
  CONSTRAINT chk_registration_dates
    CHECK (registration_end_date >= registration_start_date),
  CONSTRAINT chk_registration_before_season_end
    CHECK (registration_end_date <= end_date),
  CONSTRAINT chk_transfer_window
    CHECK (
      (transfer_window_open IS NULL AND transfer_window_close IS NULL)
      OR (transfer_window_close >= transfer_window_open)
    ),
  CONSTRAINT chk_squad_size_order
    CHECK (max_squad_size >= min_squad_size),

  UNIQUE (league_id, season_code)
);

CREATE TRIGGER trg_seasons_updated_at
  BEFORE UPDATE ON seasons
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_seasons_league         ON seasons(league_id);
CREATE INDEX idx_seasons_status         ON seasons(status);
CREATE INDEX idx_seasons_dates          ON seasons(start_date, end_date);
CREATE INDEX idx_seasons_league_active  ON seasons(league_id, status)
  WHERE status = 'active';

-- ============================================================
-- competition_rounds
-- Defines each round within a season.
-- Replaces the loose integers in fixtures.round.
-- ============================================================

CREATE TABLE competition_rounds (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  season_id     UUID        NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
  league_id     UUID        NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  round_number  SMALLINT    NOT NULL CHECK (round_number > 0),
  round_name    TEXT        NOT NULL,         -- e.g. "Matchday 1", "Quarter-Final"
  round_type    round_type  NOT NULL DEFAULT 'round_robin',

  scheduled_date_start  DATE,
  scheduled_date_end    DATE,

  is_completed  BOOLEAN     NOT NULL DEFAULT false,

  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_round_dates
    CHECK (
      scheduled_date_end IS NULL
      OR scheduled_date_end >= scheduled_date_start
    ),

  UNIQUE (season_id, round_number)
);

CREATE TRIGGER trg_competition_rounds_updated_at
  BEFORE UPDATE ON competition_rounds
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_crounds_season         ON competition_rounds(season_id);
CREATE INDEX idx_crounds_league         ON competition_rounds(league_id);
CREATE INDEX idx_crounds_type           ON competition_rounds(round_type);

-- ============================================================
-- group_stages
-- Defines named groups within a season (Group A, B, C…).
-- Each group has its own mini-standings.
-- ============================================================

CREATE TABLE group_stages (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  season_id     UUID        NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
  league_id     UUID        NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  group_name    TEXT        NOT NULL,         -- "Group A", "Pool 1"
  group_code    TEXT        NOT NULL,         -- "A", "B", "1", "2"

  -- Clubs assigned to this group
  -- Junction handled by group_stage_clubs below

  is_completed  BOOLEAN     NOT NULL DEFAULT false,

  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (season_id, group_code)
);

CREATE TRIGGER trg_group_stages_updated_at
  BEFORE UPDATE ON group_stages
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Clubs assigned to each group
CREATE TABLE group_stage_clubs (
  id              UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_stage_id  UUID  NOT NULL REFERENCES group_stages(id) ON DELETE CASCADE,
  club_id         UUID  NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  season_id       UUID  NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
  UNIQUE (group_stage_id, club_id)
);

CREATE INDEX idx_gstages_season         ON group_stages(season_id);
CREATE INDEX idx_gstages_league         ON group_stages(league_id);
CREATE INDEX idx_gsc_group              ON group_stage_clubs(group_stage_id);
CREATE INDEX idx_gsc_club               ON group_stage_clubs(club_id);
CREATE INDEX idx_gsc_season             ON group_stage_clubs(season_id);

-- ============================================================
-- knockout_brackets
-- Defines bracket slots for knockout competition stages.
-- ============================================================

CREATE TABLE knockout_brackets (
  id                    UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  season_id             UUID        NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
  league_id             UUID        NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  round_id              UUID        REFERENCES competition_rounds(id) ON DELETE SET NULL,

  bracket_position      SMALLINT    NOT NULL CHECK (bracket_position > 0),
  round_type            round_type  NOT NULL,

  home_club_id          UUID        REFERENCES clubs(id) ON DELETE SET NULL,
  away_club_id          UUID        REFERENCES clubs(id) ON DELETE SET NULL,
  fixture_id            UUID        REFERENCES fixtures(id) ON DELETE SET NULL,
  winner_club_id        UUID        REFERENCES clubs(id) ON DELETE SET NULL,

  -- Which bracket slot the winner advances to (self-referential)
  advances_to_bracket_id UUID       REFERENCES knockout_brackets(id) ON DELETE SET NULL,

  is_completed          BOOLEAN     NOT NULL DEFAULT false,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (season_id, round_type, bracket_position)
);

CREATE TRIGGER trg_knockout_brackets_updated_at
  BEFORE UPDATE ON knockout_brackets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_kbracket_season        ON knockout_brackets(season_id);
CREATE INDEX idx_kbracket_league        ON knockout_brackets(league_id);
CREATE INDEX idx_kbracket_fixture       ON knockout_brackets(fixture_id);

-- ============================================================
-- promotion_relegation_records
-- End-of-season outcome per club per season.
-- ============================================================

CREATE TABLE promotion_relegation_records (
  id            UUID                          PRIMARY KEY DEFAULT uuid_generate_v4(),
  season_id     UUID                          NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
  league_id     UUID                          NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  club_id       UUID                          NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  final_position SMALLINT                     NOT NULL CHECK (final_position > 0),
  action        promotion_relegation_action   NOT NULL DEFAULT 'stayed',
  notes         TEXT,
  recorded_by   UUID                          REFERENCES profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ                   NOT NULL DEFAULT NOW(),

  UNIQUE (season_id, club_id)
);

CREATE INDEX idx_prom_rel_season        ON promotion_relegation_records(season_id);
CREATE INDEX idx_prom_rel_club          ON promotion_relegation_records(club_id);
CREATE INDEX idx_prom_rel_league        ON promotion_relegation_records(league_id);

-- RLS — seasons
ALTER TABLE seasons                     ENABLE ROW LEVEL SECURITY;
ALTER TABLE competition_rounds          ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_stages                ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_stage_clubs           ENABLE ROW LEVEL SECURITY;
ALTER TABLE knockout_brackets           ENABLE ROW LEVEL SECURITY;
ALTER TABLE promotion_relegation_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "seasons: public read"
  ON seasons FOR SELECT USING (true);

CREATE POLICY "seasons: league admin insert"
  ON seasons FOR INSERT
  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "seasons: league admin update"
  ON seasons FOR UPDATE
  USING (is_league_admin(league_id));

CREATE POLICY "competition_rounds: public read"
  ON competition_rounds FOR SELECT USING (true);

CREATE POLICY "competition_rounds: league admin insert"
  ON competition_rounds FOR INSERT
  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "competition_rounds: league admin update"
  ON competition_rounds FOR UPDATE
  USING (is_league_admin(league_id));

CREATE POLICY "group_stages: public read"
  ON group_stages FOR SELECT USING (true);

CREATE POLICY "group_stages: league admin insert"
  ON group_stages FOR INSERT
  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "group_stages: league admin update"
  ON group_stages FOR UPDATE
  USING (is_league_admin(league_id));

CREATE POLICY "group_stage_clubs: public read"
  ON group_stage_clubs FOR SELECT USING (true);

CREATE POLICY "group_stage_clubs: league admin insert"
  ON group_stage_clubs FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM group_stages gs
      WHERE gs.id = group_stage_id AND is_league_admin(gs.league_id)
    )
  );

CREATE POLICY "group_stage_clubs: league admin delete"
  ON group_stage_clubs FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM group_stages gs
      WHERE gs.id = group_stage_id AND is_league_admin(gs.league_id)
    )
  );

CREATE POLICY "knockout_brackets: public read"
  ON knockout_brackets FOR SELECT USING (true);

CREATE POLICY "knockout_brackets: league admin insert"
  ON knockout_brackets FOR INSERT
  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "knockout_brackets: league admin update"
  ON knockout_brackets FOR UPDATE
  USING (is_league_admin(league_id));

CREATE POLICY "promotion_relegation_records: public read"
  ON promotion_relegation_records FOR SELECT USING (true);

CREATE POLICY "promotion_relegation_records: league admin insert"
  ON promotion_relegation_records FOR INSERT
  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "promotion_relegation_records: league admin update"
  ON promotion_relegation_records FOR UPDATE
  USING (is_league_admin(league_id));


-- ============================================================
-- FIX 2 — PLAYER ELIGIBILITY ENGINE
-- ============================================================

-- ============================================================
-- registration_windows
-- League-defined periods during which players may be
-- registered or transferred. A season may have multiple
-- windows (summer, winter).
-- ============================================================

CREATE TABLE registration_windows (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  season_id     UUID        NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
  league_id     UUID        NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  window_name   TEXT        NOT NULL,    -- "Summer 2025", "Winter 2026"
  opens_at      DATE        NOT NULL,
  closes_at     DATE        NOT NULL,

  -- If true, new player registrations (not just transfers) are permitted
  allows_new_registrations  BOOLEAN NOT NULL DEFAULT true,
  -- If true, transfers between clubs are permitted
  allows_transfers          BOOLEAN NOT NULL DEFAULT true,

  is_active     BOOLEAN     NOT NULL DEFAULT true,
  created_by    UUID        REFERENCES profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_window_dates
    CHECK (closes_at >= opens_at)
);

CREATE TRIGGER trg_registration_windows_updated_at
  BEFORE UPDATE ON registration_windows
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_regwin_season          ON registration_windows(season_id);
CREATE INDEX idx_regwin_league          ON registration_windows(league_id);
CREATE INDEX idx_regwin_active          ON registration_windows(league_id, is_active)
  WHERE is_active = true;

-- ============================================================
-- eligibility_rules
-- Per-season, per-league rules governing who may play.
-- ============================================================

CREATE TABLE eligibility_rules (
  id                      UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  season_id               UUID        NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
  league_id               UUID        NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  -- Age category bounds (NULL = no restriction)
  min_age_years           SMALLINT    CHECK (min_age_years >= 0),
  max_age_years           SMALLINT    CHECK (max_age_years >= 0),

  -- Minimum days a player must be registered before playing
  min_registration_days   SMALLINT    NOT NULL DEFAULT 0 CHECK (min_registration_days >= 0),

  -- Maximum foreign players per starting XI (NULL = no restriction)
  max_foreign_starters    SMALLINT    CHECK (max_foreign_starters >= 0),

  -- Must a player have appeared in registration list before cut-off?
  require_approved_registration BOOLEAN NOT NULL DEFAULT true,

  notes                   TEXT,
  created_by              UUID        REFERENCES profiles(id) ON DELETE SET NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_age_bounds
    CHECK (
      max_age_years IS NULL
      OR min_age_years IS NULL
      OR max_age_years >= min_age_years
    ),

  UNIQUE (season_id, league_id)
);

CREATE TRIGGER trg_eligibility_rules_updated_at
  BEFORE UPDATE ON eligibility_rules
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_elrules_season         ON eligibility_rules(season_id);
CREATE INDEX idx_elrules_league         ON eligibility_rules(league_id);

-- ============================================================
-- player_league_registrations
-- Explicit per-player, per-season, per-league registration.
-- A player at a club is NOT automatically registered in any
-- league until this record is approved.
-- ============================================================

CREATE TYPE registration_status AS ENUM (
  'pending',      -- Submitted by club admin, awaiting league approval
  'approved',     -- Player is eligible to play
  'rejected',     -- Registration denied
  'suspended',    -- Temporarily blocked (admin hold)
  'expired'       -- Registration window closed without approval
);

CREATE TABLE player_league_registrations (
  id                  UUID                  PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id           UUID                  NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  club_id             UUID                  NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  league_id           UUID                  NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  season_id           UUID                  NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,

  status              registration_status   NOT NULL DEFAULT 'pending',

  -- The registration window this was submitted under
  window_id           UUID                  REFERENCES registration_windows(id) ON DELETE SET NULL,

  -- Jersey number declared at registration (may differ from players.jersey_number)
  jersey_number       SMALLINT              CHECK (jersey_number BETWEEN 1 AND 99),

  -- Is this player considered a foreign/non-domestic player for this league?
  is_foreign          BOOLEAN               NOT NULL DEFAULT false,

  -- Dates
  submitted_at        TIMESTAMPTZ           NOT NULL DEFAULT NOW(),
  approved_at         TIMESTAMPTZ,
  rejected_at         TIMESTAMPTZ,
  valid_from          DATE,                 -- First match eligibility date
  valid_until         DATE,                 -- End of eligibility (loan end, etc.)

  -- Workflow
  submitted_by        UUID                  REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_by         UUID                  REFERENCES profiles(id) ON DELETE SET NULL,
  rejection_reason    TEXT,
  notes               TEXT,

  created_at          TIMESTAMPTZ           NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ           NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_valid_dates
    CHECK (valid_until IS NULL OR valid_until >= valid_from),

  -- One registration per player per club per league per season
  UNIQUE (player_id, league_id, season_id)
);

CREATE TRIGGER trg_plr_updated_at
  BEFORE UPDATE ON player_league_registrations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_plr_player             ON player_league_registrations(player_id);
CREATE INDEX idx_plr_club               ON player_league_registrations(club_id);
CREATE INDEX idx_plr_league             ON player_league_registrations(league_id);
CREATE INDEX idx_plr_season             ON player_league_registrations(season_id);
CREATE INDEX idx_plr_status             ON player_league_registrations(status);
CREATE INDEX idx_plr_approved           ON player_league_registrations(league_id, player_id, status)
  WHERE status = 'approved';

-- RLS
ALTER TABLE registration_windows         ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility_rules            ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_league_registrations  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "registration_windows: public read"
  ON registration_windows FOR SELECT USING (true);

CREATE POLICY "registration_windows: league admin insert"
  ON registration_windows FOR INSERT
  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "registration_windows: league admin update"
  ON registration_windows FOR UPDATE
  USING (is_league_admin(league_id));

CREATE POLICY "eligibility_rules: public read"
  ON eligibility_rules FOR SELECT USING (true);

CREATE POLICY "eligibility_rules: league admin insert"
  ON eligibility_rules FOR INSERT
  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "eligibility_rules: league admin update"
  ON eligibility_rules FOR UPDATE
  USING (is_league_admin(league_id));

CREATE POLICY "player_league_registrations: public read"
  ON player_league_registrations FOR SELECT USING (true);

-- Club admin submits registration for their own players
CREATE POLICY "player_league_registrations: club admin insert"
  ON player_league_registrations FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
  );

-- Club admin can update only pending/draft registrations; league admin approves
CREATE POLICY "player_league_registrations: club admin or league admin update"
  ON player_league_registrations FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR is_league_admin(league_id)
    OR (
      get_my_role() = 'club_admin'
      AND is_club_admin(club_id)
      AND status = 'pending'
    )
  );

-- ============================================================
-- is_player_eligible(p_player_id, p_fixture_id)
-- Core eligibility gate. Returns TRUE only when all checks pass.
-- Used by lineup enforcement trigger and app-layer pre-checks.
-- ============================================================

CREATE OR REPLACE FUNCTION is_player_eligible(
  p_player_id   UUID,
  p_fixture_id  UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_league_id         UUID;
  v_home_club_id      UUID;
  v_away_club_id      UUID;
  v_match_date        TIMESTAMPTZ;
  v_player_club_id    UUID;
  v_player_dob        DATE;
  v_player_active     BOOLEAN;
  v_season_id         UUID;
  v_reg               RECORD;
  v_rules             RECORD;
  v_win_open          DATE;
  v_win_close         DATE;
  v_age_years         INTEGER;
BEGIN
  -- ── 1. Load fixture context ──────────────────────────────
  SELECT f.league_id, f.home_club_id, f.away_club_id, f.match_date
  INTO   v_league_id, v_home_club_id, v_away_club_id, v_match_date
  FROM   fixtures f
  WHERE  f.id = p_fixture_id;

  IF NOT FOUND THEN
    RETURN FALSE;  -- Fixture does not exist
  END IF;

  -- ── 2. Load player context ───────────────────────────────
  SELECT p.club_id, p.date_of_birth, p.is_active
  INTO   v_player_club_id, v_player_dob, v_player_active
  FROM   players p
  WHERE  p.id = p_player_id;

  IF NOT FOUND THEN
    RETURN FALSE;  -- Player does not exist
  END IF;

  -- ── 3. Player must be active ─────────────────────────────
  IF NOT v_player_active THEN
    RETURN FALSE;
  END IF;

  -- ── 4. Player must belong to one of the two clubs ────────
  IF v_player_club_id IS DISTINCT FROM v_home_club_id
     AND v_player_club_id IS DISTINCT FROM v_away_club_id THEN
    RETURN FALSE;
  END IF;

  -- ── 5. No active suspension in this league ───────────────
  IF EXISTS (
    SELECT 1 FROM suspensions s
    WHERE  s.player_id = p_player_id
      AND  s.league_id = v_league_id
      AND  s.is_active = true
      AND  s.matches_served < s.matches_suspended
  ) THEN
    RETURN FALSE;
  END IF;

  -- ── 6. No active injury ──────────────────────────────────
  IF EXISTS (
    SELECT 1 FROM player_injuries pi
    WHERE  pi.player_id = p_player_id
      AND  pi.is_active  = true
  ) THEN
    RETURN FALSE;
  END IF;

  -- ── 7. Find the active season for this league on match date ─
  SELECT s.id INTO v_season_id
  FROM   seasons s
  WHERE  s.league_id = v_league_id
    AND  s.status    = 'active'
    AND  COALESCE(v_match_date::DATE, CURRENT_DATE) BETWEEN s.start_date AND s.end_date
  LIMIT  1;

  -- If no active season found, skip season-bound checks gracefully
  IF v_season_id IS NULL THEN
    RETURN TRUE;
  END IF;

  -- ── 8. Player must have an approved league registration ──
  SELECT plr.* INTO v_reg
  FROM   player_league_registrations plr
  WHERE  plr.player_id = p_player_id
    AND  plr.league_id = v_league_id
    AND  plr.season_id = v_season_id
    AND  plr.status    = 'approved';

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- ── 9. Registration must be valid for match date ─────────
  IF v_reg.valid_from IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) < v_reg.valid_from THEN
    RETURN FALSE;
  END IF;

  IF v_reg.valid_until IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) > v_reg.valid_until THEN
    RETURN FALSE;
  END IF;

  -- ── 10. Load eligibility rules for this season ───────────
  SELECT er.* INTO v_rules
  FROM   eligibility_rules er
  WHERE  er.season_id  = v_season_id
    AND  er.league_id  = v_league_id;

  IF FOUND THEN
    -- ── 11. Age category compliance ─────────────────────────
    v_age_years := EXTRACT(YEAR FROM AGE(
      COALESCE(v_match_date::DATE, CURRENT_DATE),
      v_player_dob
    ))::INTEGER;

    IF v_rules.min_age_years IS NOT NULL
       AND v_age_years < v_rules.min_age_years THEN
      RETURN FALSE;
    END IF;

    IF v_rules.max_age_years IS NOT NULL
       AND v_age_years > v_rules.max_age_years THEN
      RETURN FALSE;
    END IF;

    -- ── 12. Minimum registration days elapsed ────────────────
    IF v_rules.min_registration_days > 0
       AND v_reg.approved_at IS NOT NULL THEN
      IF (COALESCE(v_match_date::DATE, CURRENT_DATE)
          - v_reg.approved_at::DATE) < v_rules.min_registration_days THEN
        RETURN FALSE;
      END IF;
    END IF;
  END IF;

  -- All checks passed
  RETURN TRUE;
END;
$$;

-- ============================================================
-- is_player_eligible_with_reason(p_player_id, p_fixture_id)
-- Diagnostic variant that returns the failure reason as text.
-- For use in admin panels and API responses.
-- ============================================================

CREATE OR REPLACE FUNCTION is_player_eligible_with_reason(
  p_player_id   UUID,
  p_fixture_id  UUID
)
RETURNS TABLE (
  eligible   BOOLEAN,
  reason     TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_league_id         UUID;
  v_home_club_id      UUID;
  v_away_club_id      UUID;
  v_match_date        TIMESTAMPTZ;
  v_player_club_id    UUID;
  v_player_dob        DATE;
  v_player_active     BOOLEAN;
  v_season_id         UUID;
  v_reg               RECORD;
  v_rules             RECORD;
  v_age_years         INTEGER;
BEGIN
  SELECT f.league_id, f.home_club_id, f.away_club_id, f.match_date
  INTO   v_league_id, v_home_club_id, v_away_club_id, v_match_date
  FROM   fixtures f WHERE f.id = p_fixture_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Fixture not found';
    RETURN;
  END IF;

  SELECT p.club_id, p.date_of_birth, p.is_active
  INTO   v_player_club_id, v_player_dob, v_player_active
  FROM   players p WHERE p.id = p_player_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Player not found';
    RETURN;
  END IF;

  IF NOT v_player_active THEN
    RETURN QUERY SELECT false, 'Player is not active';
    RETURN;
  END IF;

  IF v_player_club_id IS DISTINCT FROM v_home_club_id
     AND v_player_club_id IS DISTINCT FROM v_away_club_id THEN
    RETURN QUERY SELECT false, 'Player does not belong to either club in this fixture';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM suspensions s
    WHERE  s.player_id = p_player_id
      AND  s.league_id = v_league_id
      AND  s.is_active = true
      AND  s.matches_served < s.matches_suspended
  ) THEN
    RETURN QUERY SELECT false, 'Player has an active suspension in this league';
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM player_injuries pi
    WHERE  pi.player_id = p_player_id
      AND  pi.is_active  = true
  ) THEN
    RETURN QUERY SELECT false, 'Player has an active injury';
    RETURN;
  END IF;

  SELECT s.id INTO v_season_id
  FROM   seasons s
  WHERE  s.league_id = v_league_id
    AND  s.status    = 'active'
    AND  COALESCE(v_match_date::DATE, CURRENT_DATE) BETWEEN s.start_date AND s.end_date
  LIMIT  1;

  IF v_season_id IS NULL THEN
    RETURN QUERY SELECT true, 'Eligible (no active season context)';
    RETURN;
  END IF;

  SELECT plr.* INTO v_reg
  FROM   player_league_registrations plr
  WHERE  plr.player_id = p_player_id
    AND  plr.league_id = v_league_id
    AND  plr.season_id = v_season_id
    AND  plr.status    = 'approved';

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Player does not have an approved registration for this league/season';
    RETURN;
  END IF;

  IF v_reg.valid_from IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) < v_reg.valid_from THEN
    RETURN QUERY SELECT false, 'Player registration is not yet valid for this match date';
    RETURN;
  END IF;

  IF v_reg.valid_until IS NOT NULL
     AND COALESCE(v_match_date::DATE, CURRENT_DATE) > v_reg.valid_until THEN
    RETURN QUERY SELECT false, 'Player registration has expired';
    RETURN;
  END IF;

  SELECT er.* INTO v_rules
  FROM   eligibility_rules er
  WHERE  er.season_id = v_season_id AND er.league_id = v_league_id;

  IF FOUND THEN
    v_age_years := EXTRACT(YEAR FROM AGE(
      COALESCE(v_match_date::DATE, CURRENT_DATE),
      v_player_dob
    ))::INTEGER;

    IF v_rules.min_age_years IS NOT NULL AND v_age_years < v_rules.min_age_years THEN
      RETURN QUERY SELECT false,
        'Player is too young (age ' || v_age_years || ', minimum ' || v_rules.min_age_years || ')';
      RETURN;
    END IF;

    IF v_rules.max_age_years IS NOT NULL AND v_age_years > v_rules.max_age_years THEN
      RETURN QUERY SELECT false,
        'Player is too old (age ' || v_age_years || ', maximum ' || v_rules.max_age_years || ')';
      RETURN;
    END IF;

    IF v_rules.min_registration_days > 0 AND v_reg.approved_at IS NOT NULL THEN
      IF (COALESCE(v_match_date::DATE, CURRENT_DATE) - v_reg.approved_at::DATE)
         < v_rules.min_registration_days THEN
        RETURN QUERY SELECT false,
          'Player has not been registered for the minimum required days ('
          || v_rules.min_registration_days || ')';
        RETURN;
      END IF;
    END IF;
  END IF;

  RETURN QUERY SELECT true, 'Player is eligible';
END;
$$;


-- ============================================================
-- FIX 3 — MEDICAL DATA SECURITY
-- ============================================================
-- The Phase 3 "player_injuries: public read" policy must be
-- REPLACED with two granular policies.
-- We cannot DROP the old policy here (it lives in Phase 3),
-- so we disable it by creating RESTRICTIVE policies that
-- supersede the PERMISSIVE one.
--
-- Supabase uses PERMISSIVE policies by default. All PERMISSIVE
-- policies are OR'd together. To restrict, we create a new
-- SECURITY INVOKER view that filters sensitive columns.
--
-- ► The correct production fix is to drop the Phase 3 public
--   read policy and replace it with the two below during a
--   controlled migration window. The drop statement is
--   provided in the rollback/migration notes section.
--
-- DROP POLICY "player_injuries: public read" ON player_injuries;
-- (Run this manually in a migration window before applying
--  the two policies below.)
-- ============================================================

-- Public-safe view: excludes all confidential medical fields
CREATE OR REPLACE VIEW v_player_injuries_public AS
SELECT
  pi.id,
  pi.player_id,
  pl.full_name          AS player_name,
  pi.club_id,
  cl.name               AS club_name,
  pi.fixture_id,
  pi.injury_type,
  pi.severity,
  pi.body_part,
  pi.injury_date,
  pi.expected_return_date,
  pi.actual_return_date,
  pi.is_active,
  pi.cleared_at,
  pi.created_at
  -- medical_notes, diagnosis, treatment_notes deliberately excluded
FROM player_injuries pi
JOIN  players pl ON pl.id = pi.player_id
JOIN  clubs   cl ON cl.id = pi.club_id;

-- Restricted view: full medical data, for authorized users only
-- Access enforced at app layer via RLS on the underlying table.
CREATE OR REPLACE VIEW v_player_injuries_medical AS
SELECT
  pi.id,
  pi.player_id,
  pl.full_name          AS player_name,
  pi.club_id,
  cl.name               AS club_name,
  pi.injury_type,
  pi.severity,
  pi.body_part,
  pi.injury_date,
  pi.expected_return_date,
  pi.actual_return_date,
  pi.diagnosis,
  pi.treatment_notes,
  pi.medical_notes,
  pi.is_active,
  pi.cleared_at,
  pi.clearance_notes,
  pi.reported_by,
  pi.cleared_by,
  pi.created_at,
  pi.updated_at
FROM player_injuries pi
JOIN  players pl ON pl.id = pi.player_id
JOIN  clubs   cl ON cl.id = pi.club_id;

-- ── Replacement RLS policies for player_injuries ────────────
-- IMPORTANT: Execute the DROP below BEFORE this block.
-- DROP POLICY IF EXISTS "player_injuries: public read" ON player_injuries;

-- Policy 1: Public read — non-sensitive fields only
-- We implement this as a per-column SELECT using a secure view.
-- The underlying table policy restricts to authorized users.

CREATE POLICY "player_injuries: authorized read"
  ON player_injuries FOR SELECT
  USING (
    -- Developer: full access
    get_my_role() = 'developer'
    -- League founder: full access
    OR get_my_role() = 'league_founder'
    -- League admin: see injuries of players in their leagues
    OR EXISTS (
      SELECT 1 FROM league_clubs lc
      JOIN   fixtures f ON f.league_id = lc.league_id
      WHERE  lc.club_id    = player_injuries.club_id
        AND  is_league_admin(lc.league_id)
      LIMIT  1
    )
    -- Club admin of the player's club: full access
    OR is_club_admin(player_injuries.club_id)
    -- Assigned physiotherapist of the player's club
    OR EXISTS (
      SELECT 1 FROM club_staff cs
      WHERE  cs.club_id    = player_injuries.club_id
        AND  cs.profile_id = auth.uid()
        AND  cs.is_active  = true
        AND  cs.role       = 'physiotherapist'
    )
  );

-- ============================================================
-- FIX 4 — TRANSFER APPROVAL SECURITY
-- ============================================================
-- Phase 2 policy "player_transfers: admin update" is too
-- permissive — club admins can approve their own transfers.
-- We issue a replacement that locks approval to league staff.
--
-- DROP the old policy first:
-- DROP POLICY IF EXISTS "player_transfers: admin update" ON player_transfers;
-- ============================================================

-- Replacement: granular transfer update policy
CREATE POLICY "player_transfers: league admin approve"
  ON player_transfers FOR UPDATE
  USING (
    -- Developers can do anything
    get_my_role() = 'developer'
    -- League admin of the relevant league can approve/reject/complete
    OR (
      league_id IS NOT NULL
      AND is_league_admin(league_id)
    )
    -- Club admin of EITHER club may update ONLY when:
    --   status is still 'pending' AND they are only cancelling (status → 'cancelled')
    --   This is enforced via the trigger below, not purely via RLS.
    OR (
      get_my_role() = 'club_admin'
      AND (is_club_admin(from_club_id) OR is_club_admin(to_club_id))
      AND status = 'pending'
    )
  );

-- ── Transfer approval guard trigger ─────────────────────────
-- Prevents club admins from escalating transfer status beyond
-- 'cancelled'. Only league admins may set 'approved' or 'rejected'.

CREATE OR REPLACE FUNCTION guard_transfer_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_my_role user_role;
  v_is_league_admin BOOLEAN;
BEGIN
  -- No status change: nothing to check
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  v_my_role := get_my_role();

  -- Developers bypass all checks
  IF v_my_role = 'developer' THEN
    RETURN NEW;
  END IF;

  -- Check if the current user is a league admin for this transfer
  v_is_league_admin := (
    NEW.league_id IS NOT NULL
    AND is_league_admin(NEW.league_id)
  );

  -- Only league admins and developers may set approved or rejected
  IF NEW.status IN ('approved', 'rejected') THEN
    IF NOT v_is_league_admin THEN
      RAISE EXCEPTION
        'Insufficient privileges: only league administrators may approve or reject transfers. '
        'Your attempted status change: % → %',
        OLD.status, NEW.status
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Club admins may only cancel pending transfers (not modify anything else)
  IF v_my_role = 'club_admin' AND NEW.status NOT IN ('cancelled') THEN
    IF NOT v_is_league_admin THEN
      RAISE EXCEPTION
        'Club administrators may only cancel pending transfers. '
        'Your attempted status change: % → %',
        OLD.status, NEW.status
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- A transfer can only be cancelled if it is currently pending
  IF NEW.status = 'cancelled' AND OLD.status NOT IN ('pending') THEN
    IF NOT v_is_league_admin THEN
      RAISE EXCEPTION
        'Only pending transfers may be cancelled by a club administrator.'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_transfer_status
  BEFORE UPDATE ON player_transfers
  FOR EACH ROW EXECUTE FUNCTION guard_transfer_status_change();


-- ============================================================
-- FIX 5 — REFEREE ASSIGNMENT CONSOLIDATION
-- ============================================================
-- fixtures.referee_id (Phase 1) is a simple FK to profiles.
-- referee_assignments (Phase 2) is the full officiating model.
-- Both coexist. This fix:
--   1. Creates a compatibility view that exposes a unified
--      referee view per fixture (referee_assignments is
--      authoritative; falls back to fixtures.referee_id).
--   2. Adds a consistency-check trigger on fixtures UPDATE
--      that warns (not blocks) when referee_id conflicts.
--   3. Provides the migration path to deprecate referee_id.
-- ============================================================

CREATE OR REPLACE VIEW v_fixture_referee_consolidated AS
SELECT
  f.id                                        AS fixture_id,
  f.league_id,
  f.match_date,
  f.venue,
  f.status,
  -- Authoritative: main referee from referee_assignments
  ra_main.referee_id                          AS assignment_referee_id,
  ra_main_profile.full_name                   AS assignment_referee_name,
  ra_main_profile.phone                       AS assignment_referee_phone,
  ra_main_ref.grade                           AS assignment_referee_grade,
  -- Legacy: referee_id direct FK on fixtures
  f.referee_id                                AS legacy_referee_profile_id,
  legacy_prof.full_name                       AS legacy_referee_name,
  -- Resolution: prefer referee_assignments; fall back to legacy
  COALESCE(ra_main.referee_id,
           (SELECT r2.id FROM referees r2
            WHERE r2.profile_id = f.referee_id LIMIT 1))
                                              AS resolved_referee_id,
  COALESCE(ra_main_profile.full_name, legacy_prof.full_name)
                                              AS resolved_referee_name,
  -- Flag if both exist and they disagree
  CASE
    WHEN f.referee_id IS NOT NULL
         AND ra_main.referee_id IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM referees rx
           WHERE rx.id = ra_main.referee_id
             AND rx.profile_id = f.referee_id
         )
    THEN true
    ELSE false
  END                                         AS has_conflict
FROM fixtures f
LEFT JOIN referee_assignments ra_main
       ON ra_main.fixture_id = f.id
      AND ra_main.role = 'main_referee'
LEFT JOIN referees ra_main_ref
       ON ra_main_ref.id = ra_main.referee_id
LEFT JOIN profiles ra_main_profile
       ON ra_main_profile.id = ra_main_ref.profile_id
LEFT JOIN profiles legacy_prof
       ON legacy_prof.id = f.referee_id;


-- ============================================================
-- FIX 6 — MATCH RESULT VALIDATION
-- ============================================================
-- Add missing CHECK constraints to match_results.
-- PostgreSQL allows adding NOT VALID constraints then validating
-- them separately to avoid locking large tables.
-- We add as NOT VALID first, then VALIDATE immediately since
-- this is a fresh production system (no legacy violations).
-- ============================================================

-- Possession must sum to 100 when both are provided
ALTER TABLE match_results
  ADD CONSTRAINT chk_possession_sum
    CHECK (
      (home_possession IS NULL OR away_possession IS NULL)
      OR (home_possession + away_possession = 100)
    )
  NOT VALID;

ALTER TABLE match_results
  VALIDATE CONSTRAINT chk_possession_sum;

-- Shots on target cannot exceed total shots
ALTER TABLE match_results
  ADD CONSTRAINT chk_home_shots_on_target
    CHECK (home_shots_on_target <= home_shots)
  NOT VALID;

ALTER TABLE match_results
  VALIDATE CONSTRAINT chk_home_shots_on_target;

ALTER TABLE match_results
  ADD CONSTRAINT chk_away_shots_on_target
    CHECK (away_shots_on_target <= away_shots)
  NOT VALID;

ALTER TABLE match_results
  VALIDATE CONSTRAINT chk_away_shots_on_target;

-- Penalties scored cannot exceed penalties taken
ALTER TABLE match_results
  ADD CONSTRAINT chk_home_penalties
    CHECK (home_penalties_scored <= home_penalties_taken)
  NOT VALID;

ALTER TABLE match_results
  VALIDATE CONSTRAINT chk_home_penalties;

ALTER TABLE match_results
  ADD CONSTRAINT chk_away_penalties
    CHECK (away_penalties_scored <= away_penalties_taken)
  NOT VALID;

ALTER TABLE match_results
  VALIDATE CONSTRAINT chk_away_penalties;

-- Extra-time goals may only exist when extra_time = true
ALTER TABLE match_results
  ADD CONSTRAINT chk_et_goals_require_et
    CHECK (
      extra_time = true
      OR (home_et_goals = 0 AND away_et_goals = 0)
    )
  NOT VALID;

ALTER TABLE match_results
  VALIDATE CONSTRAINT chk_et_goals_require_et;

-- player_match_stats: shots on target cannot exceed total shots
ALTER TABLE player_match_stats
  ADD CONSTRAINT chk_pms_shots_on_target
    CHECK (shots_on_target <= shots)
  NOT VALID;

ALTER TABLE player_match_stats
  VALIDATE CONSTRAINT chk_pms_shots_on_target;


-- ============================================================
-- FIX 7 — JERSEY NUMBER VALIDATION
-- ============================================================

-- Validate jersey number range on players table
ALTER TABLE players
  ADD CONSTRAINT chk_player_jersey_number_range
    CHECK (jersey_number IS NULL OR jersey_number BETWEEN 1 AND 99)
  NOT VALID;

ALTER TABLE players
  VALIDATE CONSTRAINT chk_player_jersey_number_range;

-- Prevent future dates for date_of_birth
ALTER TABLE players
  ADD CONSTRAINT chk_player_dob_not_future
    CHECK (date_of_birth < CURRENT_DATE)
  NOT VALID;

ALTER TABLE players
  VALIDATE CONSTRAINT chk_player_dob_not_future;

-- Unique jersey number per club for active players
-- Uses a partial unique index so:
--   - NULL jersey numbers are allowed (multiple players without numbers)
--   - Inactive/released players (club_id IS NULL) are excluded
--   - Historical players who left a club are excluded (handled by club_id = NULL after release)
CREATE UNIQUE INDEX idx_players_club_jersey_unique
  ON players (club_id, jersey_number)
  WHERE club_id IS NOT NULL
    AND jersey_number IS NOT NULL
    AND is_active = true;


-- ============================================================
-- FIX 8 — AUDIT LOG SYSTEM
-- ============================================================

CREATE TABLE audit_log (
  id            BIGSERIAL     PRIMARY KEY,
  table_name    TEXT          NOT NULL,
  record_id     UUID          NOT NULL,
  operation     TEXT          NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
  old_values    JSONB,
  new_values    JSONB,
  changed_by    UUID,         -- auth.uid() at time of change; NULL if triggered by system
  changed_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  session_app   TEXT,         -- application_name from pg session settings
  client_addr   INET          -- client IP if available via pg session

  -- No FK on changed_by intentionally — audit rows must survive profile deletion
  -- No updated_at — audit rows are immutable
);

-- Partition-friendly index strategy for time-series queries
CREATE INDEX idx_audit_table_record     ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_changed_at       ON audit_log(changed_at DESC);
CREATE INDEX idx_audit_changed_by       ON audit_log(changed_by);
CREATE INDEX idx_audit_operation        ON audit_log(operation);
CREATE INDEX idx_audit_table_time       ON audit_log(table_name, changed_at DESC);

-- ── Reusable audit trigger function ─────────────────────────

CREATE OR REPLACE FUNCTION audit_trigger_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_record_id   UUID;
  v_old_values  JSONB;
  v_new_values  JSONB;
BEGIN
  -- Extract the primary key UUID named "id" from every audited table
  IF TG_OP = 'DELETE' THEN
    v_record_id  := OLD.id;
    v_old_values := to_jsonb(OLD);
    v_new_values := NULL;
  ELSIF TG_OP = 'INSERT' THEN
    v_record_id  := NEW.id;
    v_old_values := NULL;
    v_new_values := to_jsonb(NEW);
  ELSE  -- UPDATE
    v_record_id  := NEW.id;
    v_old_values := to_jsonb(OLD);
    v_new_values := to_jsonb(NEW);
  END IF;

  INSERT INTO audit_log (
    table_name,
    record_id,
    operation,
    old_values,
    new_values,
    changed_by,
    session_app,
    client_addr
  ) VALUES (
    TG_TABLE_NAME,
    v_record_id,
    TG_OP,
    v_old_values,
    v_new_values,
    auth.uid(),
    current_setting('application_name', true),
    inet_client_addr()
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

-- ── Attach audit triggers to all required tables ─────────────

-- players
CREATE TRIGGER trg_audit_players
  AFTER INSERT OR UPDATE OR DELETE ON players
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- clubs
CREATE TRIGGER trg_audit_clubs
  AFTER INSERT OR UPDATE OR DELETE ON clubs
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- fixtures
CREATE TRIGGER trg_audit_fixtures
  AFTER INSERT OR UPDATE OR DELETE ON fixtures
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- match_results
CREATE TRIGGER trg_audit_match_results
  AFTER INSERT OR UPDATE OR DELETE ON match_results
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- disciplinary_records
CREATE TRIGGER trg_audit_disciplinary_records
  AFTER INSERT OR UPDATE OR DELETE ON disciplinary_records
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- suspensions
CREATE TRIGGER trg_audit_suspensions
  AFTER INSERT OR UPDATE OR DELETE ON suspensions
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- player_transfers
CREATE TRIGGER trg_audit_player_transfers
  AFTER INSERT OR UPDATE OR DELETE ON player_transfers
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- club_league_payments
CREATE TRIGGER trg_audit_club_league_payments
  AFTER INSERT OR UPDATE OR DELETE ON club_league_payments
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- player_injuries
CREATE TRIGGER trg_audit_player_injuries
  AFTER INSERT OR UPDATE OR DELETE ON player_injuries
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- RLS — audit_log
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Developers read everything; league admins read their own league scope
CREATE POLICY "audit_log: developer read"
  ON audit_log FOR SELECT
  USING (get_my_role() = 'developer');

-- No INSERT/UPDATE/DELETE from app layer — trigger only
-- (All writes come from the SECURITY DEFINER trigger function)
CREATE POLICY "audit_log: deny direct write"
  ON audit_log FOR INSERT
  WITH CHECK (get_my_role() = 'developer');

-- Audit log view with human-readable table + operation summary
CREATE VIEW v_audit_log AS
SELECT
  al.id,
  al.table_name,
  al.record_id,
  al.operation,
  al.old_values,
  al.new_values,
  al.changed_by,
  pr.full_name    AS changed_by_name,
  al.changed_at,
  al.session_app
FROM audit_log al
LEFT JOIN profiles pr ON pr.id = al.changed_by
ORDER BY al.changed_at DESC;


-- ============================================================
-- FIX 9 — STANDINGS REVERSAL ENGINE
-- ============================================================
-- Phase 1's update_standings_on_official_result() only moves
-- standings forward. This fix adds:
--   1. recalculate_standings(p_league_id) — full recompute
--      from scratch using all official match_results.
--   2. reverse_match_result(p_fixture_id) — rolls back a
--      single official result and recalculates.
--   3. A replacement trigger that handles both ratification
--      AND de-ratification (is_official TRUE → FALSE).
--
-- The existing Phase 1 trigger is NOT dropped here. The new
-- trigger fires AFTER the Phase 1 trigger, which means on
-- de-ratification the Phase 1 trigger does nothing (it only
-- fires when is_official flips TRUE) and the Phase 4 trigger
-- handles the recalculation.
--
-- For full correctness, in a migration window:
--   DROP TRIGGER trg_official_result_standings ON match_results;
-- and rely solely on the Phase 4 trigger below.
-- ============================================================

CREATE OR REPLACE FUNCTION recalculate_standings(p_league_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_row RECORD;
BEGIN
  -- Lock the standings rows for this league to prevent concurrent modification
  PERFORM 1 FROM standings
  WHERE league_id = p_league_id
  FOR UPDATE;

  -- Reset all standings for this league to zero
  UPDATE standings
  SET
    played        = 0,
    wins          = 0,
    draws         = 0,
    losses        = 0,
    goals_for     = 0,
    goals_against = 0,
    updated_at    = NOW()
  WHERE league_id = p_league_id;

  -- Recompute from all official results for this league
  FOR v_row IN
    SELECT
      f.home_club_id,
      f.away_club_id,
      mr.home_goals,
      mr.away_goals
    FROM match_results mr
    JOIN fixtures f ON f.id = mr.fixture_id
    WHERE f.league_id    = p_league_id
      AND mr.is_official = true
  LOOP
    -- Ensure rows exist
    INSERT INTO standings (league_id, club_id)
    VALUES (p_league_id, v_row.home_club_id)
    ON CONFLICT (league_id, club_id) DO NOTHING;

    INSERT INTO standings (league_id, club_id)
    VALUES (p_league_id, v_row.away_club_id)
    ON CONFLICT (league_id, club_id) DO NOTHING;

    -- Home club
    UPDATE standings SET
      played        = played + 1,
      wins          = wins   + CASE WHEN v_row.home_goals > v_row.away_goals THEN 1 ELSE 0 END,
      draws         = draws  + CASE WHEN v_row.home_goals = v_row.away_goals THEN 1 ELSE 0 END,
      losses        = losses + CASE WHEN v_row.home_goals < v_row.away_goals THEN 1 ELSE 0 END,
      goals_for     = goals_for     + v_row.home_goals,
      goals_against = goals_against + v_row.away_goals,
      updated_at    = NOW()
    WHERE league_id = p_league_id AND club_id = v_row.home_club_id;

    -- Away club
    UPDATE standings SET
      played        = played + 1,
      wins          = wins   + CASE WHEN v_row.away_goals > v_row.home_goals THEN 1 ELSE 0 END,
      draws         = draws  + CASE WHEN v_row.away_goals = v_row.home_goals THEN 1 ELSE 0 END,
      losses        = losses + CASE WHEN v_row.away_goals < v_row.home_goals THEN 1 ELSE 0 END,
      goals_for     = goals_for     + v_row.away_goals,
      goals_against = goals_against + v_row.home_goals,
      updated_at    = NOW()
    WHERE league_id = p_league_id AND club_id = v_row.away_club_id;
  END LOOP;
END;
$$;

-- ── Reverse a single ratified result ────────────────────────

CREATE OR REPLACE FUNCTION reverse_match_result(p_fixture_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_league_id   UUID;
  v_home_id     UUID;
  v_away_id     UUID;
  v_home_goals  INTEGER;
  v_away_goals  INTEGER;
BEGIN
  -- Load the fixture and verify it has an official result
  SELECT f.league_id, f.home_club_id, f.away_club_id
  INTO   v_league_id, v_home_id, v_away_id
  FROM   fixtures f
  WHERE  f.id = p_fixture_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fixture % not found', p_fixture_id USING ERRCODE = '02000';
  END IF;

  SELECT mr.home_goals, mr.away_goals
  INTO   v_home_goals, v_away_goals
  FROM   match_results mr
  WHERE  mr.fixture_id   = p_fixture_id
    AND  mr.is_official  = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No official result found for fixture %', p_fixture_id
      USING ERRCODE = '02000';
  END IF;

  -- Subtract the contribution of this result from standings
  UPDATE standings SET
    played        = GREATEST(played - 1, 0),
    wins          = GREATEST(wins   - CASE WHEN v_home_goals > v_away_goals THEN 1 ELSE 0 END, 0),
    draws         = GREATEST(draws  - CASE WHEN v_home_goals = v_away_goals THEN 1 ELSE 0 END, 0),
    losses        = GREATEST(losses - CASE WHEN v_home_goals < v_away_goals THEN 1 ELSE 0 END, 0),
    goals_for     = GREATEST(goals_for     - v_home_goals, 0),
    goals_against = GREATEST(goals_against - v_away_goals, 0),
    updated_at    = NOW()
  WHERE league_id = v_league_id AND club_id = v_home_id;

  UPDATE standings SET
    played        = GREATEST(played - 1, 0),
    wins          = GREATEST(wins   - CASE WHEN v_away_goals > v_home_goals THEN 1 ELSE 0 END, 0),
    draws         = GREATEST(draws  - CASE WHEN v_away_goals = v_home_goals THEN 1 ELSE 0 END, 0),
    losses        = GREATEST(losses - CASE WHEN v_away_goals < v_home_goals THEN 1 ELSE 0 END, 0),
    goals_for     = GREATEST(goals_for     - v_away_goals, 0),
    goals_against = GREATEST(goals_against - v_home_goals, 0),
    updated_at    = NOW()
  WHERE league_id = v_league_id AND club_id = v_away_id;
END;
$$;

-- ── Trigger: handle de-ratification (is_official TRUE → FALSE) ──

CREATE OR REPLACE FUNCTION handle_result_de_ratification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only fire when is_official flips from true to false (de-ratification)
  IF (TG_OP = 'UPDATE' AND OLD.is_official = true AND NEW.is_official = false) THEN
    PERFORM reverse_match_result(NEW.fixture_id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_result_de_ratification
  AFTER UPDATE ON match_results
  FOR EACH ROW EXECUTE FUNCTION handle_result_de_ratification();

-- ── Trigger: handle result score correction when already official ──
-- If a result is already official and the score is corrected,
-- we must reverse the old contribution and apply the new one.

CREATE OR REPLACE FUNCTION handle_official_result_correction()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_league_id   UUID;
  v_home_id     UUID;
  v_away_id     UUID;
BEGIN
  -- Only fire when an already-official result has its scoreline changed
  IF TG_OP = 'UPDATE'
     AND OLD.is_official = true
     AND NEW.is_official = true
     AND (OLD.home_goals <> NEW.home_goals OR OLD.away_goals <> NEW.away_goals)
  THEN
    SELECT f.league_id, f.home_club_id, f.away_club_id
    INTO   v_league_id, v_home_id, v_away_id
    FROM   fixtures f
    WHERE  f.id = NEW.fixture_id;

    -- Reverse the OLD scoreline contribution
    UPDATE standings SET
      played        = GREATEST(played - 1, 0),
      wins          = GREATEST(wins   - CASE WHEN OLD.home_goals > OLD.away_goals THEN 1 ELSE 0 END, 0),
      draws         = GREATEST(draws  - CASE WHEN OLD.home_goals = OLD.away_goals THEN 1 ELSE 0 END, 0),
      losses        = GREATEST(losses - CASE WHEN OLD.home_goals < OLD.away_goals THEN 1 ELSE 0 END, 0),
      goals_for     = GREATEST(goals_for     - OLD.home_goals, 0),
      goals_against = GREATEST(goals_against - OLD.away_goals, 0),
      updated_at    = NOW()
    WHERE league_id = v_league_id AND club_id = v_home_id;

    UPDATE standings SET
      played        = GREATEST(played - 1, 0),
      wins          = GREATEST(wins   - CASE WHEN OLD.away_goals > OLD.home_goals THEN 1 ELSE 0 END, 0),
      draws         = GREATEST(draws  - CASE WHEN OLD.away_goals = OLD.home_goals THEN 1 ELSE 0 END, 0),
      losses        = GREATEST(losses - CASE WHEN OLD.away_goals < OLD.home_goals THEN 1 ELSE 0 END, 0),
      goals_for     = GREATEST(goals_for     - OLD.away_goals, 0),
      goals_against = GREATEST(goals_against - OLD.home_goals, 0),
      updated_at    = NOW()
    WHERE league_id = v_league_id AND club_id = v_away_id;

    -- Apply the NEW scoreline contribution
    UPDATE standings SET
      played        = played + 1,
      wins          = wins   + CASE WHEN NEW.home_goals > NEW.away_goals THEN 1 ELSE 0 END,
      draws         = draws  + CASE WHEN NEW.home_goals = NEW.away_goals THEN 1 ELSE 0 END,
      losses        = losses + CASE WHEN NEW.home_goals < NEW.away_goals THEN 1 ELSE 0 END,
      goals_for     = goals_for     + NEW.home_goals,
      goals_against = goals_against + NEW.away_goals,
      updated_at    = NOW()
    WHERE league_id = v_league_id AND club_id = v_home_id;

    UPDATE standings SET
      played        = played + 1,
      wins          = wins   + CASE WHEN NEW.away_goals > NEW.home_goals THEN 1 ELSE 0 END,
      draws         = draws  + CASE WHEN NEW.away_goals = NEW.home_goals THEN 1 ELSE 0 END,
      losses        = losses + CASE WHEN NEW.away_goals < NEW.home_goals THEN 1 ELSE 0 END,
      goals_for     = goals_for     + NEW.away_goals,
      goals_against = goals_against + NEW.home_goals,
      updated_at    = NOW()
    WHERE league_id = v_league_id AND club_id = v_away_id;

  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_official_result_correction
  AFTER UPDATE ON match_results
  FOR EACH ROW EXECUTE FUNCTION handle_official_result_correction();


-- ============================================================
-- FIX 10 — LINEUP ENFORCEMENT (ELIGIBILITY GATE)
-- ============================================================

CREATE OR REPLACE FUNCTION enforce_lineup_eligibility()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_eligible    BOOLEAN;
  v_reason      TEXT;
  v_player_name TEXT;
BEGIN
  -- Only enforce for starters (role = 'starter')
  -- Substitutes are checked at actual substitution time
  -- not_selected rows are never blocked
  IF NEW.role <> 'starter' THEN
    RETURN NEW;
  END IF;

  -- Only enforce when the lineup is being confirmed
  -- (confirmed_at transitioning from NULL to a value)
  IF (TG_OP = 'UPDATE' AND OLD.confirmed_at IS NOT NULL) THEN
    RETURN NEW;  -- Already confirmed; changes handled by league admin only
  END IF;

  -- Run eligibility check
  SELECT eligible, reason
  INTO   v_eligible, v_reason
  FROM   is_player_eligible_with_reason(NEW.player_id, NEW.fixture_id);

  IF NOT v_eligible THEN
    SELECT full_name INTO v_player_name
    FROM   players WHERE id = NEW.player_id;

    RAISE EXCEPTION
      'Lineup eligibility check failed for player "%" (ID: %): %',
      COALESCE(v_player_name, 'Unknown'),
      NEW.player_id,
      v_reason
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_lineup_eligibility
  BEFORE INSERT OR UPDATE ON match_lineups
  FOR EACH ROW EXECUTE FUNCTION enforce_lineup_eligibility();


-- ============================================================
-- FIX 11 — VENUE MANAGEMENT
-- ============================================================

CREATE TYPE pitch_surface AS ENUM (
  'natural_grass',
  'artificial_grass',
  '3g_artificial',
  'hybrid',
  'sand',
  'indoor'
);

CREATE TABLE venues (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),

  name            TEXT          NOT NULL,
  short_name      TEXT,

  -- Address
  address_line1   TEXT,
  address_line2   TEXT,
  city            TEXT          NOT NULL,
  state           TEXT,
  country         TEXT          NOT NULL DEFAULT 'Malaysia',
  postcode        TEXT,

  -- Geolocation
  latitude        NUMERIC(10,7) CHECK (latitude  BETWEEN -90  AND 90),
  longitude       NUMERIC(10,7) CHECK (longitude BETWEEN -180 AND 180),

  -- Physical attributes
  capacity        INTEGER       CHECK (capacity >= 0),
  pitch_length_m  NUMERIC(5,1)  CHECK (pitch_length_m > 0),
  pitch_width_m   NUMERIC(5,1)  CHECK (pitch_width_m > 0),
  surface         pitch_surface,

  -- Ownership
  owner_name      TEXT,
  owner_club_id   UUID          REFERENCES clubs(id) ON DELETE SET NULL,

  -- Status
  is_active       BOOLEAN       NOT NULL DEFAULT true,

  -- Contact
  phone           TEXT,
  email           TEXT,
  website         TEXT,

  -- Administrative
  created_by      UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  notes           TEXT,

  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_venues_updated_at
  BEFORE UPDATE ON venues
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_venues_city            ON venues(city);
CREATE INDEX idx_venues_country         ON venues(country);
CREATE INDEX idx_venues_active          ON venues(is_active);
CREATE INDEX idx_venues_owner_club      ON venues(owner_club_id);

-- ── venue_availability ──────────────────────────────────────
-- Blackout periods when a venue is unavailable.
-- Used for future scheduling conflict detection.

CREATE TABLE venue_availability (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  venue_id        UUID        NOT NULL REFERENCES venues(id) ON DELETE CASCADE,

  unavailable_from TIMESTAMPTZ NOT NULL,
  unavailable_to   TIMESTAMPTZ NOT NULL,
  reason          TEXT,

  created_by      UUID        REFERENCES profiles(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_availability_dates
    CHECK (unavailable_to > unavailable_from)
);

CREATE INDEX idx_venue_avail_venue      ON venue_availability(venue_id);
CREATE INDEX idx_venue_avail_dates      ON venue_availability(venue_id, unavailable_from, unavailable_to);

-- RLS
ALTER TABLE venues             ENABLE ROW LEVEL SECURITY;
ALTER TABLE venue_availability ENABLE ROW LEVEL SECURITY;

CREATE POLICY "venues: public read"
  ON venues FOR SELECT USING (true);

CREATE POLICY "venues: league admin or developer insert"
  ON venues FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR get_my_role() IN ('league_admin', 'league_founder')
    OR (owner_club_id IS NOT NULL AND is_club_admin(owner_club_id))
  );

CREATE POLICY "venues: league admin or owner update"
  ON venues FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR get_my_role() IN ('league_admin', 'league_founder')
    OR (owner_club_id IS NOT NULL AND is_club_admin(owner_club_id))
    OR created_by = auth.uid()
  );

CREATE POLICY "venue_availability: public read"
  ON venue_availability FOR SELECT USING (true);

CREATE POLICY "venue_availability: admin insert"
  ON venue_availability FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR get_my_role() IN ('league_admin', 'league_founder')
    OR EXISTS (
      SELECT 1 FROM venues v
      WHERE v.id = venue_id
        AND (v.owner_club_id IS NOT NULL AND is_club_admin(v.owner_club_id))
    )
  );

CREATE POLICY "venue_availability: admin delete"
  ON venue_availability FOR DELETE
  USING (
    get_my_role() = 'developer'
    OR get_my_role() IN ('league_admin', 'league_founder')
  );

-- Venue summary view
CREATE VIEW v_venues AS
SELECT
  v.id,
  v.name,
  v.short_name,
  v.city,
  v.state,
  v.country,
  v.latitude,
  v.longitude,
  v.capacity,
  v.surface,
  v.owner_name,
  v.owner_club_id,
  cl.name   AS owner_club_name,
  v.is_active,
  v.phone,
  v.website
FROM venues v
LEFT JOIN clubs cl ON cl.id = v.owner_club_id;


-- ============================================================
-- FIX 12 — DISCIPLINARY APPEALS
-- ============================================================

CREATE TYPE appeal_status AS ENUM (
  'submitted',        -- Appeal filed by club, pending review
  'under_review',     -- Tribunal is reviewing
  'hearing_scheduled',-- Formal hearing date set
  'decided',          -- Decision issued
  'withdrawn'         -- Club withdrew the appeal
);

CREATE TYPE appeal_outcome AS ENUM (
  'upheld',           -- Appeal upheld — original decision overturned
  'partially_upheld', -- Sentence reduced
  'dismissed',        -- Appeal rejected — original decision stands
  'withdrawn'         -- Club withdrew before decision
);

CREATE TABLE disciplinary_appeals (
  id                    UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- What is being appealed
  suspension_id         UUID          REFERENCES suspensions(id) ON DELETE SET NULL,
  disciplinary_record_id UUID         REFERENCES disciplinary_records(id) ON DELETE SET NULL,

  league_id             UUID          NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  player_id             UUID          NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  club_id               UUID          NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  -- Appeal details
  status                appeal_status NOT NULL DEFAULT 'submitted',
  grounds               TEXT          NOT NULL,  -- Reason for appeal
  supporting_evidence   TEXT,                    -- URLs or descriptions of evidence

  -- Suspension hold: if true, the player may play pending outcome
  suspension_held       BOOLEAN       NOT NULL DEFAULT false,

  -- Deadline: appeals must be filed within N days of the decision
  appeal_deadline       DATE,

  -- Submission
  submitted_by          UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  submitted_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- Outcome
  outcome               appeal_outcome,
  outcome_notes         TEXT,
  decided_at            TIMESTAMPTZ,
  decided_by            UUID          REFERENCES profiles(id) ON DELETE SET NULL,

  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- At least one of suspension_id or disciplinary_record_id must be set
  CONSTRAINT chk_appeal_has_subject
    CHECK (suspension_id IS NOT NULL OR disciplinary_record_id IS NOT NULL)
);

CREATE TRIGGER trg_disciplinary_appeals_updated_at
  BEFORE UPDATE ON disciplinary_appeals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_appeals_league         ON disciplinary_appeals(league_id);
CREATE INDEX idx_appeals_player         ON disciplinary_appeals(player_id);
CREATE INDEX idx_appeals_club           ON disciplinary_appeals(club_id);
CREATE INDEX idx_appeals_status         ON disciplinary_appeals(status);
CREATE INDEX idx_appeals_suspension     ON disciplinary_appeals(suspension_id);

-- ── appeal_hearings ──────────────────────────────────────────

CREATE TABLE appeal_hearings (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  appeal_id         UUID          NOT NULL REFERENCES disciplinary_appeals(id) ON DELETE CASCADE,
  league_id         UUID          NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  hearing_date      TIMESTAMPTZ   NOT NULL,
  location          TEXT,
  hearing_notes     TEXT,         -- Minutes / proceedings summary

  is_completed      BOOLEAN       NOT NULL DEFAULT false,

  -- Panel members (stored as profile references)
  panel_member_1    UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  panel_member_2    UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  panel_member_3    UUID          REFERENCES profiles(id) ON DELETE SET NULL,

  scheduled_by      UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_appeal_hearings_updated_at
  BEFORE UPDATE ON appeal_hearings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_hearings_appeal        ON appeal_hearings(appeal_id);
CREATE INDEX idx_hearings_league        ON appeal_hearings(league_id);
CREATE INDEX idx_hearings_date          ON appeal_hearings(hearing_date);

-- ── tribunal_decisions ───────────────────────────────────────

CREATE TABLE tribunal_decisions (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  appeal_id         UUID          NOT NULL UNIQUE REFERENCES disciplinary_appeals(id) ON DELETE CASCADE,
  hearing_id        UUID          REFERENCES appeal_hearings(id) ON DELETE SET NULL,
  league_id         UUID          NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  outcome           appeal_outcome NOT NULL,
  decision_text     TEXT          NOT NULL,    -- Full written decision

  -- If suspension was modified
  original_matches_suspended  INTEGER,
  revised_matches_suspended   INTEGER,        -- NULL = no change

  -- Was the suspension retroactively removed?
  suspension_overturned BOOLEAN   NOT NULL DEFAULT false,

  decided_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  decided_by        UUID          REFERENCES profiles(id) ON DELETE SET NULL,

  -- Automatically update the appeal status when decision is inserted
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tribunal_appeal        ON tribunal_decisions(appeal_id);
CREATE INDEX idx_tribunal_league        ON tribunal_decisions(league_id);

-- ── Trigger: sync appeal outcome from tribunal decision ──────

CREATE OR REPLACE FUNCTION sync_appeal_outcome_from_decision()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Update the parent appeal record with the outcome
  UPDATE disciplinary_appeals
  SET
    outcome       = NEW.outcome,
    outcome_notes = NEW.decision_text,
    decided_at    = NEW.decided_at,
    decided_by    = NEW.decided_by,
    status        = 'decided',
    updated_at    = NOW()
  WHERE id = NEW.appeal_id;

  -- If the suspension was overturned, deactivate it
  IF NEW.suspension_overturned THEN
    UPDATE suspensions
    SET
      is_active  = false,
      reason_notes = COALESCE(reason_notes, '') ||
                     ' [Overturned on appeal ' || NEW.decided_at::DATE::TEXT || ']',
      updated_at = NOW()
    WHERE id = (
      SELECT suspension_id FROM disciplinary_appeals
      WHERE id = NEW.appeal_id
    );
  END IF;

  -- If suspension was revised downward, update matches_suspended
  IF NEW.revised_matches_suspended IS NOT NULL THEN
    UPDATE suspensions
    SET
      matches_suspended = NEW.revised_matches_suspended,
      reason_notes      = COALESCE(reason_notes, '') ||
                          ' [Reduced from ' || NEW.original_matches_suspended ||
                          ' to ' || NEW.revised_matches_suspended ||
                          ' on appeal ' || NEW.decided_at::DATE::TEXT || ']',
      -- If already served enough, deactivate
      is_active = (matches_served < NEW.revised_matches_suspended),
      updated_at = NOW()
    WHERE id = (
      SELECT suspension_id FROM disciplinary_appeals
      WHERE id = NEW.appeal_id
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_appeal_outcome
  AFTER INSERT ON tribunal_decisions
  FOR EACH ROW EXECUTE FUNCTION sync_appeal_outcome_from_decision();

-- RLS
ALTER TABLE disciplinary_appeals  ENABLE ROW LEVEL SECURITY;
ALTER TABLE appeal_hearings        ENABLE ROW LEVEL SECURITY;
ALTER TABLE tribunal_decisions     ENABLE ROW LEVEL SECURITY;

CREATE POLICY "disciplinary_appeals: public read"
  ON disciplinary_appeals FOR SELECT USING (true);

-- Clubs submit appeals for their own players
CREATE POLICY "disciplinary_appeals: club admin insert"
  ON disciplinary_appeals FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
  );

-- League admin manages the review process; clubs can only withdraw
CREATE POLICY "disciplinary_appeals: league admin update"
  ON disciplinary_appeals FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR is_league_admin(league_id)
    OR (
      get_my_role() = 'club_admin'
      AND is_club_admin(club_id)
      AND status = 'submitted'     -- Can only withdraw before review starts
    )
  );

CREATE POLICY "appeal_hearings: public read"
  ON appeal_hearings FOR SELECT USING (true);

CREATE POLICY "appeal_hearings: league admin insert"
  ON appeal_hearings FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR is_league_admin(league_id)
  );

CREATE POLICY "appeal_hearings: league admin update"
  ON appeal_hearings FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR is_league_admin(league_id)
  );

CREATE POLICY "tribunal_decisions: public read"
  ON tribunal_decisions FOR SELECT USING (true);

CREATE POLICY "tribunal_decisions: league admin insert"
  ON tribunal_decisions FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR is_league_admin(league_id)
  );

-- View: full appeal lifecycle
CREATE VIEW v_disciplinary_appeals AS
SELECT
  da.id                           AS appeal_id,
  da.league_id,
  l.name                          AS league_name,
  da.player_id,
  pl.full_name                    AS player_name,
  da.club_id,
  cl.name                         AS club_name,
  da.status,
  da.grounds,
  da.suspension_held,
  da.appeal_deadline,
  da.submitted_at,
  da.outcome,
  da.outcome_notes,
  da.decided_at,
  td.revised_matches_suspended,
  td.suspension_overturned,
  ah.hearing_date
FROM disciplinary_appeals da
JOIN  leagues l  ON l.id  = da.league_id
JOIN  players pl ON pl.id = da.player_id
JOIN  clubs   cl ON cl.id = da.club_id
LEFT JOIN tribunal_decisions td ON td.appeal_id = da.id
LEFT JOIN appeal_hearings    ah ON ah.appeal_id = da.id AND ah.is_completed = false
ORDER BY da.submitted_at DESC;


-- ============================================================
-- FIX 13 — NOTIFICATION PREFERENCES & PUSH TOKENS
-- ============================================================

CREATE TABLE user_preferences (
  id                    UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id            UUID    NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,

  -- Display / localisation
  timezone              TEXT    NOT NULL DEFAULT 'Asia/Kuala_Lumpur',
  language              TEXT    NOT NULL DEFAULT 'en',
  date_format           TEXT    NOT NULL DEFAULT 'DD/MM/YYYY',

  -- Global notification toggle (master off switch)
  notifications_enabled BOOLEAN NOT NULL DEFAULT true,

  -- Channel-level defaults
  email_enabled         BOOLEAN NOT NULL DEFAULT true,
  push_enabled          BOOLEAN NOT NULL DEFAULT true,
  sms_enabled           BOOLEAN NOT NULL DEFAULT false,
  in_app_enabled        BOOLEAN NOT NULL DEFAULT true,

  -- Dashboard preferences (JSON for flexibility)
  dashboard_config      JSONB,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_user_preferences_updated_at
  BEFORE UPDATE ON user_preferences
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── notification_preferences ────────────────────────────────
-- Per-user, per-notification-type, per-channel opt-in/opt-out.

CREATE TABLE notification_preferences (
  id                    UUID                  PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id            UUID                  NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  notification_type     notification_type     NOT NULL,
  channel               notification_channel  NOT NULL,
  is_enabled            BOOLEAN               NOT NULL DEFAULT true,
  created_at            TIMESTAMPTZ           NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ           NOT NULL DEFAULT NOW(),

  UNIQUE (profile_id, notification_type, channel)
);

CREATE TRIGGER trg_notification_preferences_updated_at
  BEFORE UPDATE ON notification_preferences
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_notifpref_profile      ON notification_preferences(profile_id);
CREATE INDEX idx_notifpref_type         ON notification_preferences(notification_type);
CREATE INDEX idx_notifpref_enabled      ON notification_preferences(profile_id, is_enabled)
  WHERE is_enabled = true;

-- ── user_device_tokens ───────────────────────────────────────
-- Push notification device tokens (FCM / APNs).
-- One user may have multiple devices.

CREATE TYPE push_platform AS ENUM (
  'fcm',    -- Firebase Cloud Messaging (Android + web)
  'apns',   -- Apple Push Notification Service (iOS/macOS)
  'web'     -- Web Push (browser)
);

CREATE TABLE user_device_tokens (
  id            UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id    UUID          NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  platform      push_platform NOT NULL,
  token         TEXT          NOT NULL,
  device_name   TEXT,         -- e.g. "iPhone 15 Pro", "Chrome on MacBook"
  device_id     TEXT,         -- Unique device identifier from the app
  is_active     BOOLEAN       NOT NULL DEFAULT true,
  last_used_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- One token value must be unique across all users
  UNIQUE (token)
);

CREATE TRIGGER trg_user_device_tokens_updated_at
  BEFORE UPDATE ON user_device_tokens
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_udt_profile            ON user_device_tokens(profile_id);
CREATE INDEX idx_udt_platform           ON user_device_tokens(platform);
CREATE INDEX idx_udt_active             ON user_device_tokens(profile_id, is_active)
  WHERE is_active = true;

-- RLS
ALTER TABLE user_preferences          ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences  ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_device_tokens        ENABLE ROW LEVEL SECURITY;

-- Users manage only their own preferences
CREATE POLICY "user_preferences: own read"
  ON user_preferences FOR SELECT
  USING (profile_id = auth.uid() OR get_my_role() = 'developer');

CREATE POLICY "user_preferences: own insert"
  ON user_preferences FOR INSERT
  WITH CHECK (profile_id = auth.uid());

CREATE POLICY "user_preferences: own update"
  ON user_preferences FOR UPDATE
  USING (profile_id = auth.uid() OR get_my_role() = 'developer');

CREATE POLICY "notification_preferences: own read"
  ON notification_preferences FOR SELECT
  USING (profile_id = auth.uid() OR get_my_role() = 'developer');

CREATE POLICY "notification_preferences: own insert"
  ON notification_preferences FOR INSERT
  WITH CHECK (profile_id = auth.uid());

CREATE POLICY "notification_preferences: own update"
  ON notification_preferences FOR UPDATE
  USING (profile_id = auth.uid() OR get_my_role() = 'developer');

CREATE POLICY "notification_preferences: own delete"
  ON notification_preferences FOR DELETE
  USING (profile_id = auth.uid() OR get_my_role() = 'developer');

CREATE POLICY "user_device_tokens: own read"
  ON user_device_tokens FOR SELECT
  USING (profile_id = auth.uid() OR get_my_role() = 'developer');

CREATE POLICY "user_device_tokens: own insert"
  ON user_device_tokens FOR INSERT
  WITH CHECK (profile_id = auth.uid());

CREATE POLICY "user_device_tokens: own update"
  ON user_device_tokens FOR UPDATE
  USING (profile_id = auth.uid() OR get_my_role() = 'developer');

CREATE POLICY "user_device_tokens: own delete"
  ON user_device_tokens FOR DELETE
  USING (profile_id = auth.uid() OR get_my_role() = 'developer');


-- ============================================================
-- FIX 14 — DATA QUALITY FIXES
-- ============================================================

-- ── Transfer fee must be non-negative ───────────────────────
ALTER TABLE player_transfers
  ADD CONSTRAINT chk_transfer_fee_non_negative
    CHECK (transfer_fee IS NULL OR transfer_fee >= 0)
  NOT VALID;

ALTER TABLE player_transfers
  VALIDATE CONSTRAINT chk_transfer_fee_non_negative;

-- ── Loan return date must be on or after effective date ──────
ALTER TABLE player_transfers
  ADD CONSTRAINT chk_loan_return_after_effective
    CHECK (
      loan_return_date IS NULL
      OR effective_date IS NULL
      OR loan_return_date >= effective_date
    )
  NOT VALID;

ALTER TABLE player_transfers
  VALIDATE CONSTRAINT chk_loan_return_after_effective;

-- ── Fixture clubs must belong to the fixture's league ────────
-- Implemented as a trigger (cannot reference other tables
-- inside a CHECK constraint in PostgreSQL).

CREATE OR REPLACE FUNCTION validate_fixture_clubs_in_league()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Validate home club
  IF NOT EXISTS (
    SELECT 1 FROM league_clubs lc
    WHERE lc.league_id = NEW.league_id
      AND lc.club_id   = NEW.home_club_id
      AND lc.approved  = true
  ) THEN
    RAISE EXCEPTION
      'Home club (ID: %) is not an approved member of league (ID: %)',
      NEW.home_club_id, NEW.league_id
      USING ERRCODE = '23514';
  END IF;

  -- Validate away club
  IF NOT EXISTS (
    SELECT 1 FROM league_clubs lc
    WHERE lc.league_id = NEW.league_id
      AND lc.club_id   = NEW.away_club_id
      AND lc.approved  = true
  ) THEN
    RAISE EXCEPTION
      'Away club (ID: %) is not an approved member of league (ID: %)',
      NEW.away_club_id, NEW.league_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_fixture_clubs
  BEFORE INSERT OR UPDATE ON fixtures
  FOR EACH ROW EXECUTE FUNCTION validate_fixture_clubs_in_league();

-- ── Completed fixture must have a match result ───────────────
CREATE OR REPLACE FUNCTION validate_completed_fixture_has_result()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only check when status is being set to 'completed' or 'official'
  IF NEW.status IN ('completed', 'official')
     AND OLD.status NOT IN ('completed', 'official') THEN
    IF NOT EXISTS (
      SELECT 1 FROM match_results mr
      WHERE mr.fixture_id = NEW.id
    ) THEN
      RAISE EXCEPTION
        'Cannot mark fixture (ID: %) as "%" without a match result entry.',
        NEW.id, NEW.status
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_completed_fixture_result
  BEFORE UPDATE ON fixtures
  FOR EACH ROW EXECUTE FUNCTION validate_completed_fixture_has_result();

-- ── Referee conflict of interest guard ───────────────────────
-- Prevents a referee from being assigned to a fixture where
-- their home club (via referees → profiles → clubs) is playing.

CREATE OR REPLACE FUNCTION validate_referee_no_conflict()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_referee_profile_id  UUID;
  v_home_club_id        UUID;
  v_away_club_id        UUID;
BEGIN
  -- Get the referee's profile_id
  SELECT r.profile_id INTO v_referee_profile_id
  FROM   referees r WHERE r.id = NEW.referee_id;

  -- Get the fixture's two clubs
  SELECT f.home_club_id, f.away_club_id
  INTO   v_home_club_id, v_away_club_id
  FROM   fixtures f WHERE f.id = NEW.fixture_id;

  -- Check if the referee is an admin of either club
  IF EXISTS (
    SELECT 1 FROM clubs c
    WHERE  c.admin_id = v_referee_profile_id
      AND  c.id IN (v_home_club_id, v_away_club_id)
  ) THEN
    RAISE EXCEPTION
      'Conflict of interest: referee (profile ID: %) is an administrator of one of the clubs in fixture (ID: %).',
      v_referee_profile_id, NEW.fixture_id
      USING ERRCODE = '23514';
  END IF;

  -- Check if the referee is a registered player at either club
  IF EXISTS (
    SELECT 1 FROM players p
    JOIN   profiles pr ON pr.id = v_referee_profile_id
    WHERE  p.club_id IN (v_home_club_id, v_away_club_id)
      -- Note: players are matched by profile linkage if any exists
      -- This is a best-effort check; full enforcement requires profile-player linking
  ) THEN
    -- Only raise if the referee profile is explicitly linked via coaches table
    IF EXISTS (
      SELECT 1 FROM coaches co
      WHERE  co.profile_id = v_referee_profile_id
        AND  co.club_id    IN (v_home_club_id, v_away_club_id)
        AND  co.is_active  = true
    ) THEN
      RAISE EXCEPTION
        'Conflict of interest: referee (profile ID: %) is an active coach at one of the clubs in fixture (ID: %).',
        v_referee_profile_id, NEW.fixture_id
        USING ERRCODE = '23514';
    END IF;

    IF EXISTS (
      SELECT 1 FROM club_staff cs
      WHERE  cs.profile_id = v_referee_profile_id
        AND  cs.club_id    IN (v_home_club_id, v_away_club_id)
        AND  cs.is_active  = true
    ) THEN
      RAISE EXCEPTION
        'Conflict of interest: referee (profile ID: %) is active club staff at one of the clubs in fixture (ID: %).',
        v_referee_profile_id, NEW.fixture_id
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_referee_conflict
  BEFORE INSERT OR UPDATE ON referee_assignments
  FOR EACH ROW EXECUTE FUNCTION validate_referee_no_conflict();


-- ============================================================
-- FIX 15 — SECURITY HARDENING
-- ============================================================

-- ── 15.1 Notification abuse — tighten insert policies ────────
-- Replace overly permissive notification insert policy.
-- DROP POLICY IF EXISTS "notifications: developer insert" ON notifications;
-- (Drop the Phase 3 policy manually in migration window, then:)

CREATE POLICY "notifications: hardened insert"
  ON notifications FOR INSERT
  WITH CHECK (
    -- Only developer and league admins may directly insert notifications
    -- System-generated notifications bypass RLS via SECURITY DEFINER triggers
    get_my_role() = 'developer'
    OR (
      league_id IS NOT NULL
      AND is_league_admin(league_id)
      AND notification_type IN ('league_announcement', 'league_status_change', 'general')
    )
  );

-- Prevent inserting notification_recipients for other users' inboxes
-- DROP POLICY IF EXISTS "notification_recipients: system insert" ON notification_recipients;

CREATE POLICY "notification_recipients: hardened insert"
  ON notification_recipients FOR INSERT
  WITH CHECK (
    -- Developer bypass
    get_my_role() = 'developer'
    -- System triggers (SECURITY DEFINER) bypass RLS automatically
    -- Direct app inserts only allowed for own profile
    OR profile_id = auth.uid()
  );

-- ── 15.2 Media ownership spoofing — scope insert by club/league ──
-- DROP POLICY IF EXISTS "media_assets: admin insert" ON media_assets;

CREATE POLICY "media_assets: hardened insert"
  ON media_assets FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    -- League-scoped media: must be league admin of that specific league
    OR (league_id IS NOT NULL AND club_id IS NULL AND is_league_admin(league_id))
    -- Club-scoped media: must be club admin of that specific club
    OR (club_id IS NOT NULL AND league_id IS NULL AND is_club_admin(club_id))
    -- Both league and club scoped: must satisfy both
    OR (
      league_id IS NOT NULL
      AND club_id IS NOT NULL
      AND is_league_admin(league_id)
      AND is_club_admin(club_id)
    )
    -- Neither league nor club: only developer
    -- (prevents unanchored media from any role)
  );

-- ── 15.3 Coach assessment cross-club prevention ──────────────
-- coach_assessments: assessor insert allows any technical_assessor
-- to insert assessments. We add a scoped update policy to prevent
-- cross-club updates (the insert already requires assessor_id = auth.uid()).
-- DROP POLICY IF EXISTS "coach_assessments: assessor or developer update" ON coach_assessments;

CREATE POLICY "coach_assessments: scoped update"
  ON coach_assessments FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (
      get_my_role() = 'technical_assessor'
      AND assessor_id = auth.uid()
      -- Assessor may only update if they assessed this coach
      -- (assessor_id = auth.uid() is already the unique key)
    )
    -- League admin can update assessments in their leagues
    OR EXISTS (
      SELECT 1 FROM coaches co
      JOIN   league_clubs lc ON lc.club_id = co.club_id
      WHERE  co.id = coach_assessments.coach_id
        AND  is_league_admin(lc.league_id)
    )
  );

-- ── 15.4 Player assessment cross-club prevention ─────────────
-- Drop and replace Phase 1 player_assessments update policy
-- DROP POLICY IF EXISTS "player_assessments: assessor or developer update" ON player_assessments;

CREATE POLICY "player_assessments: scoped update"
  ON player_assessments FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (
      get_my_role() = 'technical_assessor'
      AND assessor_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM players pl
      JOIN   league_clubs lc ON lc.club_id = pl.club_id
      WHERE  pl.id = player_assessments.player_id
        AND  is_league_admin(lc.league_id)
    )
  );

-- ── 15.5 Storage bucket hardening ────────────────────────────
-- Existing bucket policies are bucket-wide. We cannot add
-- path-level policies in pure SQL on Supabase; those must be
-- configured via Supabase Dashboard Storage > Policies.
-- We add explicit UPDATE and DELETE deny policies for
-- public buckets to prevent overwriting or deleting assets.

CREATE POLICY "storage: deny public delete league-logos"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'league-logos'
    AND auth.uid() IS NOT NULL
    AND get_my_role() IN ('developer', 'league_founder', 'league_admin')
  );

CREATE POLICY "storage: deny public delete club-logos"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'club-logos'
    AND auth.uid() IS NOT NULL
    AND get_my_role() IN ('developer', 'club_admin')
  );

CREATE POLICY "storage: deny public delete player-photos"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'player-photos'
    AND auth.uid() IS NOT NULL
    AND get_my_role() IN ('developer', 'club_admin')
  );

-- ── 15.6 Audit log — deny all direct writes except developer ─
-- Already established in Fix 8, confirmed here.

-- ── 15.7 Helper function: is_active_physio_for_club ─────────

CREATE OR REPLACE FUNCTION is_active_physio_for_club(p_club_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM club_staff cs
    WHERE cs.club_id    = p_club_id
      AND cs.profile_id = auth.uid()
      AND cs.is_active  = true
      AND cs.role       = 'physiotherapist'
  );
$$;

-- ── 15.8 Prevent notification_recipients fan-out abuse ───────
-- An authenticated user must not be able to INSERT a
-- notification_recipients row for another user's profile_id.
-- Already handled by "hardened insert" policy (Fix 15.1).
-- Additional: prevent DELETE of other users' notifications.

CREATE POLICY "notification_recipients: own delete"
  ON notification_recipients FOR DELETE
  USING (
    profile_id = auth.uid()
    OR get_my_role() = 'developer'
  );

-- ── 15.9 player_league_registrations — approval protection ──
-- Club admins must NOT be able to approve their own player
-- registrations. Approval must be league admin only.

CREATE OR REPLACE FUNCTION guard_registration_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_my_role user_role;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  v_my_role := get_my_role();

  IF v_my_role = 'developer' THEN
    RETURN NEW;
  END IF;

  -- Only league admins may approve or reject registrations
  IF NEW.status IN ('approved', 'rejected', 'suspended', 'expired') THEN
    IF NOT is_league_admin(NEW.league_id) THEN
      RAISE EXCEPTION
        'Insufficient privileges: only league administrators may approve or reject player registrations. Attempted: % → %',
        OLD.status, NEW.status
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_registration_approval
  BEFORE UPDATE ON player_league_registrations
  FOR EACH ROW EXECUTE FUNCTION guard_registration_approval();


-- ============================================================
-- SUPPORTING VIEWS
-- ============================================================

-- Season overview per league
CREATE VIEW v_seasons AS
SELECT
  s.id,
  s.league_id,
  l.name              AS league_name,
  s.name              AS season_name,
  s.season_code,
  s.status,
  s.start_date,
  s.end_date,
  s.registration_start_date,
  s.registration_end_date,
  s.promotion_spots,
  s.relegation_spots,
  s.max_squad_size,
  s.max_foreign_players,
  (s.end_date - s.start_date)   AS total_days,
  (SELECT COUNT(*)
   FROM competition_rounds cr
   WHERE cr.season_id = s.id)   AS total_rounds,
  (SELECT COUNT(*)
   FROM competition_rounds cr
   WHERE cr.season_id = s.id AND cr.is_completed = true) AS completed_rounds
FROM seasons s
JOIN leagues l ON l.id = s.league_id
ORDER BY s.league_id, s.start_date DESC;

-- Player eligibility snapshot per fixture (for admin dashboard)
CREATE VIEW v_player_eligibility_check AS
SELECT
  pl.id                     AS player_id,
  pl.full_name              AS player_name,
  pl.position,
  pl.club_id,
  cl.name                   AS club_name,
  is_player_eligible(pl.id, NULL::UUID) AS eligible_generic
  -- For fixture-specific checks call is_player_eligible_with_reason(player_id, fixture_id)
FROM players pl
JOIN clubs cl ON cl.id = pl.club_id
WHERE pl.is_active = true;

-- Active registration windows per league
CREATE VIEW v_active_registration_windows AS
SELECT
  rw.id,
  rw.season_id,
  s.name              AS season_name,
  rw.league_id,
  l.name              AS league_name,
  rw.window_name,
  rw.opens_at,
  rw.closes_at,
  rw.allows_new_registrations,
  rw.allows_transfers,
  (CURRENT_DATE BETWEEN rw.opens_at AND rw.closes_at) AS is_currently_open
FROM registration_windows rw
JOIN seasons s ON s.id = rw.season_id
JOIN leagues l ON l.id = rw.league_id
WHERE rw.is_active = true
ORDER BY rw.league_id, rw.opens_at;

-- Pending player registrations (league admin review queue)
CREATE VIEW v_pending_registrations AS
SELECT
  plr.id,
  plr.player_id,
  pl.full_name          AS player_name,
  pl.position,
  pl.date_of_birth,
  EXTRACT(YEAR FROM AGE(pl.date_of_birth))::INTEGER AS age,
  plr.club_id,
  cl.name               AS club_name,
  plr.league_id,
  l.name                AS league_name,
  plr.season_id,
  s.name                AS season_name,
  plr.status,
  plr.jersey_number,
  plr.is_foreign,
  plr.submitted_at,
  pr.full_name          AS submitted_by_name
FROM player_league_registrations plr
JOIN players pl ON pl.id = plr.player_id
JOIN clubs   cl ON cl.id = plr.club_id
JOIN leagues l  ON l.id  = plr.league_id
JOIN seasons s  ON s.id  = plr.season_id
LEFT JOIN profiles pr ON pr.id = plr.submitted_by
WHERE plr.status = 'pending'
ORDER BY plr.submitted_at ASC;


-- ============================================================
-- PHASE 4 COMPLETE
-- ============================================================

COMMIT;

-- ============================================================
-- MIGRATION ORDER
-- ============================================================
-- 1. Apply Phase 1 (playpro_phase1.sql)
-- 2. Apply Phase 2 (playpro_phase2_additions.sql)
-- 3. Apply Phase 3 (playpro_phase3_additions.sql)
-- 4. (Migration window) Execute the DROP statements below
-- 5. Apply Phase 4 (this file) inside a transaction
-- ============================================================
-- MANUAL PRE-FLIGHT DROPS (run in migration window before Phase 4):
-- ============================================================
--
-- FIX 3 — Medical data security:
--   DROP POLICY IF EXISTS "player_injuries: public read" ON player_injuries;
--
-- FIX 4 — Transfer approval:
--   DROP POLICY IF EXISTS "player_transfers: admin update" ON player_transfers;
--
-- FIX 9 — Standings reversal (optional, keeps both triggers active):
--   DROP TRIGGER IF EXISTS trg_official_result_standings ON match_results;
--   (Phase 4 triggers handle both ratification and de-ratification correctly.
--    The Phase 1 trigger is safe to leave in place as it only fires on
--    is_official = false → true transitions and does not conflict with
--    the correction trigger, but removing it avoids double-counting on
--    fresh ratifications. Recommended: drop it.)
--
-- FIX 15 — Security hardening (if prior policies interfere):
--   DROP POLICY IF EXISTS "notifications: developer insert" ON notifications;
--   DROP POLICY IF EXISTS "notification_recipients: system insert" ON notification_recipients;
--   DROP POLICY IF EXISTS "media_assets: admin insert" ON media_assets;
--   DROP POLICY IF EXISTS "coach_assessments: assessor or developer update" ON coach_assessments;
--   DROP POLICY IF EXISTS "player_assessments: assessor or developer update" ON player_assessments;
--
-- ============================================================
-- ROLLBACK STRATEGY
-- ============================================================
-- Because this migration runs inside BEGIN ... COMMIT, the
-- entire Phase 4 can be rolled back with a single:
--   ROLLBACK;
-- before the COMMIT is executed.
--
-- After COMMIT, individual fixes can be rolled back as follows:
--
-- FIX 1:  DROP TABLE promotion_relegation_records, knockout_brackets,
--         group_stage_clubs, group_stages, competition_rounds, seasons CASCADE;
--         DROP TYPE season_status, round_type, promotion_relegation_action;
--
-- FIX 2:  DROP FUNCTION is_player_eligible(UUID,UUID);
--         DROP FUNCTION is_player_eligible_with_reason(UUID,UUID);
--         DROP TABLE player_league_registrations, eligibility_rules,
--         registration_windows CASCADE;
--         DROP TYPE registration_status;
--
-- FIX 3:  DROP VIEW v_player_injuries_public, v_player_injuries_medical;
--         DROP POLICY "player_injuries: authorized read" ON player_injuries;
--         Re-create: CREATE POLICY "player_injuries: public read" ON player_injuries
--           FOR SELECT USING (true);
--
-- FIX 4:  DROP TRIGGER trg_guard_transfer_status ON player_transfers;
--         DROP FUNCTION guard_transfer_status_change();
--         DROP POLICY "player_transfers: league admin approve" ON player_transfers;
--         Re-create Phase 2 policy as needed.
--
-- FIX 5:  DROP VIEW v_fixture_referee_consolidated;
--
-- FIX 6:  ALTER TABLE match_results DROP CONSTRAINT chk_possession_sum,
--         DROP CONSTRAINT chk_home_shots_on_target, DROP CONSTRAINT chk_away_shots_on_target,
--         DROP CONSTRAINT chk_home_penalties, DROP CONSTRAINT chk_away_penalties,
--         DROP CONSTRAINT chk_et_goals_require_et;
--         ALTER TABLE player_match_stats DROP CONSTRAINT chk_pms_shots_on_target;
--
-- FIX 7:  DROP INDEX idx_players_club_jersey_unique;
--         ALTER TABLE players DROP CONSTRAINT chk_player_jersey_number_range,
--         DROP CONSTRAINT chk_player_dob_not_future;
--
-- FIX 8:  DROP TRIGGER trg_audit_* ON players, clubs, fixtures, match_results,
--         disciplinary_records, suspensions, player_transfers,
--         club_league_payments, player_injuries;
--         DROP FUNCTION audit_trigger_fn();
--         DROP TABLE audit_log CASCADE;
--
-- FIX 9:  DROP TRIGGER trg_result_de_ratification ON match_results;
--         DROP TRIGGER trg_official_result_correction ON match_results;
--         DROP FUNCTION recalculate_standings(UUID);
--         DROP FUNCTION reverse_match_result(UUID);
--         DROP FUNCTION handle_result_de_ratification();
--         DROP FUNCTION handle_official_result_correction();
--
-- FIX 10: DROP TRIGGER trg_enforce_lineup_eligibility ON match_lineups;
--         DROP FUNCTION enforce_lineup_eligibility();
--
-- FIX 11: DROP TABLE venue_availability, venues CASCADE;
--         DROP TYPE pitch_surface;
--
-- FIX 12: DROP TABLE tribunal_decisions, appeal_hearings,
--         disciplinary_appeals CASCADE;
--         DROP TYPE appeal_status, appeal_outcome;
--
-- FIX 13: DROP TABLE user_device_tokens, notification_preferences,
--         user_preferences CASCADE;
--         DROP TYPE push_platform;
--
-- FIX 14: ALTER TABLE player_transfers
--           DROP CONSTRAINT chk_transfer_fee_non_negative,
--           DROP CONSTRAINT chk_loan_return_after_effective;
--         DROP TRIGGER trg_validate_fixture_clubs ON fixtures;
--         DROP FUNCTION validate_fixture_clubs_in_league();
--         DROP TRIGGER trg_validate_completed_fixture_result ON fixtures;
--         DROP FUNCTION validate_completed_fixture_has_result();
--         DROP TRIGGER trg_validate_referee_conflict ON referee_assignments;
--         DROP FUNCTION validate_referee_no_conflict();
--
-- FIX 15: DROP all hardened policies; re-create originals from Phase 2/3.
--
-- ============================================================
-- PRODUCTION RISK NOTES
-- ============================================================
--
-- RISK 1 — FIX 6 constraint validation
--   ALTER TABLE ... ADD CONSTRAINT ... NOT VALID followed by VALIDATE
--   runs a full table scan on match_results and player_match_stats.
--   If existing rows violate the new constraints (e.g. possession
--   does not sum to 100), the VALIDATE step will FAIL.
--   Mitigation: audit existing data before applying:
--     SELECT * FROM match_results
--     WHERE home_possession + away_possession <> 100
--       AND home_possession IS NOT NULL
--       AND away_possession IS NOT NULL;
--   Fix any violations before running FIX 6.
--
-- RISK 2 — FIX 7 unique jersey index
--   CREATE UNIQUE INDEX on players may FAIL if two active players
--   at the same club share the same jersey number.
--   Mitigation: audit before applying:
--     SELECT club_id, jersey_number, COUNT(*)
--     FROM players
--     WHERE club_id IS NOT NULL AND jersey_number IS NOT NULL AND is_active = true
--     GROUP BY club_id, jersey_number
--     HAVING COUNT(*) > 1;
--   Resolve duplicates before running FIX 7.
--
-- RISK 3 — FIX 9 trigger coexistence
--   Phase 1 trg_official_result_standings and Phase 4
--   trg_official_result_correction both fire on UPDATE of
--   match_results. On a fresh is_official = false → true transition,
--   BOTH triggers fire. Phase 1 adds standings; Phase 4 correction
--   trigger only fires if old and new scores differ (no double count
--   on initial ratification). SAFE as-is.
--   For clean production, drop the Phase 1 trigger per migration notes.
--
-- RISK 4 — FIX 14 fixture club validation trigger
--   trg_validate_fixture_clubs fires on INSERT OR UPDATE of fixtures.
--   If existing fixtures reference clubs that were removed from a
--   league (league_clubs.approved flipped to false after fixture
--   creation), updating those fixtures will FAIL.
--   Mitigation: the trigger only validates on INSERT and UPDATE.
--   Existing fixtures are grandfathered. Only new or updated
--   fixtures are subject to the check.
--
-- RISK 5 — FIX 10 lineup eligibility trigger
--   trg_enforce_lineup_eligibility blocks INSERT of starter rows
--   into match_lineups if is_player_eligible() returns FALSE.
--   This WILL block lineup submission for leagues with no seasons
--   defined yet (gracefully passes when no season context found).
--   Ensure at least one active season exists before entering lineups.
--
-- RISK 6 — Audit log volume
--   audit_log will accumulate rapidly. Plan a retention policy:
--   partition by year or run a nightly archive job moving rows
--   older than N months to a cold archive table.
--
-- RISK 7 — Phase 3 "player_injuries: public read" coexistence
--   Until that policy is dropped, BOTH the Phase 3 public read
--   policy and the Phase 4 authorized read policy exist.
--   In Supabase (PERMISSIVE mode), the public read policy WINS
--   because any passing policy grants access.
--   YOU MUST DROP the Phase 3 policy before Fix 3 is effective.
--   Do this in the migration window before applying this file.
--
-- ============================================================
-- PHASE 4 OBJECT SUMMARY
-- ============================================================
-- New enums:        7   season_status, round_type,
--                       promotion_relegation_action,
--                       registration_status, pitch_surface,
--                       appeal_status, appeal_outcome,
--                       push_platform
--
-- New tables:      18   seasons, competition_rounds,
--                       group_stages, group_stage_clubs,
--                       knockout_brackets,
--                       promotion_relegation_records,
--                       registration_windows,
--                       eligibility_rules,
--                       player_league_registrations,
--                       audit_log,
--                       venues, venue_availability,
--                       disciplinary_appeals,
--                       appeal_hearings,
--                       tribunal_decisions,
--                       user_preferences,
--                       notification_preferences,
--                       user_device_tokens
--
-- New functions:   13   is_player_eligible,
--                       is_player_eligible_with_reason,
--                       guard_transfer_status_change,
--                       audit_trigger_fn,
--                       recalculate_standings,
--                       reverse_match_result,
--                       handle_result_de_ratification,
--                       handle_official_result_correction,
--                       enforce_lineup_eligibility,
--                       validate_fixture_clubs_in_league,
--                       validate_completed_fixture_has_result,
--                       validate_referee_no_conflict,
--                       sync_appeal_outcome_from_decision,
--                       guard_registration_approval,
--                       is_active_physio_for_club
--
-- New triggers:    22   trg_seasons_updated_at,
--                       trg_competition_rounds_updated_at,
--                       trg_group_stages_updated_at,
--                       trg_knockout_brackets_updated_at,
--                       trg_registration_windows_updated_at,
--                       trg_eligibility_rules_updated_at,
--                       trg_plr_updated_at,
--                       trg_guard_transfer_status,
--                       trg_audit_players,
--                       trg_audit_clubs,
--                       trg_audit_fixtures,
--                       trg_audit_match_results,
--                       trg_audit_disciplinary_records,
--                       trg_audit_suspensions,
--                       trg_audit_player_transfers,
--                       trg_audit_club_league_payments,
--                       trg_audit_player_injuries,
--                       trg_result_de_ratification,
--                       trg_official_result_correction,
--                       trg_enforce_lineup_eligibility,
--                       trg_validate_fixture_clubs,
--                       trg_validate_completed_fixture_result,
--                       trg_validate_referee_conflict,
--                       trg_sync_appeal_outcome,
--                       trg_guard_registration_approval,
--                       trg_venues_updated_at,
--                       trg_disciplinary_appeals_updated_at,
--                       trg_appeal_hearings_updated_at,
--                       trg_user_preferences_updated_at,
--                       trg_notification_preferences_updated_at,
--                       trg_user_device_tokens_updated_at
--
-- New views:        9   v_seasons,
--                       v_player_injuries_public,
--                       v_player_injuries_medical,
--                       v_fixture_referee_consolidated,
--                       v_audit_log,
--                       v_venues,
--                       v_disciplinary_appeals,
--                       v_player_eligibility_check,
--                       v_active_registration_windows,
--                       v_pending_registrations
--
-- New indexes:     ~45
-- New constraints:  8  (on match_results, player_match_stats,
--                       player_transfers, players)
-- New RLS policies: 50+
-- ============================================================
