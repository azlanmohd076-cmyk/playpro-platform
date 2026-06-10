-- ============================================================

-- PLAYPRO — PHASE 1 DATABASE SCHEMA

-- Paste this entire file into Supabase SQL Editor and run it.

-- Order matters — run top to bottom exactly as written.

-- ============================================================

-- ============================================================

-- SECTION 1: EXTENSIONS

-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================

-- SECTION 2: ENUMS

-- ============================================================

CREATE TYPE user_role AS ENUM (

  'developer',

  'league_founder',

  'league_admin',

  'club_admin',

  'coach',

  'technical_assessor'

);

CREATE TYPE league_status AS ENUM (

  'draft',

  'active',

  'completed',

  'archived'

);

CREATE TYPE fixture_status AS ENUM (

  'scheduled',

  'postponed',

  'cancelled',

  'in_progress',

  'completed',

  'official'

);

CREATE TYPE preferred_foot AS ENUM (

  'left',

  'right',

  'both'

);

CREATE TYPE player_position AS ENUM (

  'goalkeeper',

  'defender',

  'midfielder',

  'forward'

);

CREATE TYPE card_type AS ENUM (

  'yellow',

  'red',

  'second_yellow'

);

CREATE TYPE suspension_reason AS ENUM (

  'automatic_red_card',

  'yellow_card_accumulation',

  'serious_misconduct',

  'manual_admin'

);

CREATE TYPE league_staff_role AS ENUM (

  'league_admin',

  'referee'

);

-- ============================================================

-- SECTION 3: CORE TABLES

-- ============================================================

-- -----------------------------------------------------------

-- profiles

-- Extends Supabase auth.users. One row per authenticated user.

-- -----------------------------------------------------------

CREATE TABLE profiles (

  id            UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  full_name     TEXT        NOT NULL,

  email         TEXT        NOT NULL UNIQUE,

  role          user_role   NOT NULL DEFAULT 'club_admin',

  avatar_url    TEXT,

  phone         TEXT,

  is_active     BOOLEAN     NOT NULL DEFAULT true,

  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()

);

-- -----------------------------------------------------------

-- leagues

-- A competition. Created by developer, owned by league_founder.

-- -----------------------------------------------------------

CREATE TABLE leagues (

  id                      UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),

  name                    TEXT          NOT NULL,

  logo_url                TEXT,

  description             TEXT,

  season                  TEXT          NOT NULL,

  status                  league_status NOT NULL DEFAULT 'draft',

  founder_id              UUID          REFERENCES profiles(id) ON DELETE SET NULL,

  -- Disciplinary rule: how many yellows trigger a suspension

  yellow_card_threshold   INTEGER       NOT NULL DEFAULT 5,

  -- Disciplinary rule: how many matches for an automatic red card ban

  red_card_ban_matches    INTEGER       NOT NULL DEFAULT 1,

  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW()

);

-- -----------------------------------------------------------

-- league_staff

-- Maps profiles to leagues with a specific operational role.

-- League founders appoint these users.

-- -----------------------------------------------------------

CREATE TABLE league_staff (

  id            UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),

  league_id     UUID              NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  profile_id    UUID              NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  role          league_staff_role NOT NULL,

  appointed_by  UUID              REFERENCES profiles(id) ON DELETE SET NULL,

  created_at    TIMESTAMPTZ       NOT NULL DEFAULT NOW(),

  UNIQUE (league_id, profile_id, role)

);

-- -----------------------------------------------------------

-- clubs

-- A football club. Managed by its club_admin.

-- -----------------------------------------------------------

CREATE TABLE clubs (

  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  name          TEXT        NOT NULL,

  logo_url      TEXT,

  year_founded  INTEGER,

  home_venue    TEXT,

  colours       TEXT,

  admin_id      UUID        REFERENCES profiles(id) ON DELETE SET NULL,

  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()

);

-- -----------------------------------------------------------

-- league_clubs

-- Junction: which clubs are in which league, and are they approved.

-- -----------------------------------------------------------

CREATE TABLE league_clubs (

  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  league_id     UUID        NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  club_id       UUID        NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  approved      BOOLEAN     NOT NULL DEFAULT false,

  approved_by   UUID        REFERENCES profiles(id) ON DELETE SET NULL,

  approved_at   TIMESTAMPTZ,

  joined_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (league_id, club_id)

);

-- -----------------------------------------------------------

-- players

-- Registered football players. Belongs to one club.

-- Assessment fields are in a separate table.

-- -----------------------------------------------------------

CREATE TABLE players (

  id              UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),

  full_name       TEXT            NOT NULL,

  date_of_birth   DATE            NOT NULL,

  preferred_foot  preferred_foot,

  position        player_position NOT NULL,

  photo_url       TEXT,

  club_id         UUID            REFERENCES clubs(id) ON DELETE SET NULL,

  jersey_number   INTEGER,

  nationality     TEXT,

  is_active       BOOLEAN         NOT NULL DEFAULT true,

  created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

  updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()

);

-- -----------------------------------------------------------

-- coaches

-- Football coaches. Belongs to one club.

-- -----------------------------------------------------------

CREATE TABLE coaches (

  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  full_name     TEXT        NOT NULL,

  license       TEXT,

  club_id       UUID        REFERENCES clubs(id) ON DELETE SET NULL,

  photo_url     TEXT,

  profile_id    UUID        REFERENCES profiles(id) ON DELETE SET NULL,

  is_active     BOOLEAN     NOT NULL DEFAULT true,

  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()

);

-- -----------------------------------------------------------

-- fixtures

-- A scheduled match between two clubs in a league.

-- -----------------------------------------------------------

CREATE TABLE fixtures (

  id              UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),

  league_id       UUID            NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  home_club_id    UUID            NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  away_club_id    UUID            NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  match_date      TIMESTAMPTZ,

  venue           TEXT,

  round           INTEGER,

  round_name      TEXT,

  status          fixture_status  NOT NULL DEFAULT 'scheduled',

  referee_id      UUID            REFERENCES profiles(id) ON DELETE SET NULL,

  created_by      UUID            REFERENCES profiles(id) ON DELETE SET NULL,

  created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

  updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_different_clubs CHECK (home_club_id <> away_club_id)

);

-- -----------------------------------------------------------

-- match_results

-- Full team-level statistics for a completed fixture.

-- One row per fixture. is_official = true means standings update.

-- -----------------------------------------------------------

CREATE TABLE match_results (

  id                      UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  fixture_id              UUID        NOT NULL UNIQUE REFERENCES fixtures(id) ON DELETE CASCADE,

  -- Scoreline

  home_goals              INTEGER     NOT NULL DEFAULT 0 CHECK (home_goals >= 0),

  away_goals              INTEGER     NOT NULL DEFAULT 0 CHECK (away_goals >= 0),

  -- Possession (must sum to 100)

  home_possession         INTEGER     CHECK (home_possession BETWEEN 0 AND 100),

  away_possession         INTEGER     CHECK (away_possession BETWEEN 0 AND 100),

  -- Shots

  home_shots              INTEGER     NOT NULL DEFAULT 0 CHECK (home_shots >= 0),

  away_shots              INTEGER     NOT NULL DEFAULT 0 CHECK (away_shots >= 0),

  home_shots_on_target    INTEGER     NOT NULL DEFAULT 0 CHECK (home_shots_on_target >= 0),

  away_shots_on_target    INTEGER     NOT NULL DEFAULT 0 CHECK (away_shots_on_target >= 0),

  -- Set pieces

  home_corners            INTEGER     NOT NULL DEFAULT 0 CHECK (home_corners >= 0),

  away_corners            INTEGER     NOT NULL DEFAULT 0 CHECK (away_corners >= 0),

  home_free_kicks         INTEGER     NOT NULL DEFAULT 0 CHECK (home_free_kicks >= 0),

  away_free_kicks         INTEGER     NOT NULL DEFAULT 0 CHECK (away_free_kicks >= 0),

  home_offsides           INTEGER     NOT NULL DEFAULT 0 CHECK (home_offsides >= 0),

  away_offsides           INTEGER     NOT NULL DEFAULT 0 CHECK (away_offsides >= 0),

  -- Discipline (team totals)

  home_fouls              INTEGER     NOT NULL DEFAULT 0 CHECK (home_fouls >= 0),

  away_fouls              INTEGER     NOT NULL DEFAULT 0 CHECK (away_fouls >= 0),

  home_yellow_cards       INTEGER     NOT NULL DEFAULT 0 CHECK (home_yellow_cards >= 0),

  away_yellow_cards       INTEGER     NOT NULL DEFAULT 0 CHECK (away_yellow_cards >= 0),

  home_red_cards          INTEGER     NOT NULL DEFAULT 0 CHECK (home_red_cards >= 0),

  away_red_cards          INTEGER     NOT NULL DEFAULT 0 CHECK (away_red_cards >= 0),

  -- Goalkeeping

  home_saves              INTEGER     NOT NULL DEFAULT 0 CHECK (home_saves >= 0),

  away_saves              INTEGER     NOT NULL DEFAULT 0 CHECK (away_saves >= 0),

  -- Penalties

  home_penalties_scored   INTEGER     NOT NULL DEFAULT 0 CHECK (home_penalties_scored >= 0),

  away_penalties_scored   INTEGER     NOT NULL DEFAULT 0 CHECK (away_penalties_scored >= 0),

  home_penalties_taken    INTEGER     NOT NULL DEFAULT 0 CHECK (home_penalties_taken >= 0),

  away_penalties_taken    INTEGER     NOT NULL DEFAULT 0 CHECK (away_penalties_taken >= 0),

  -- Extra time

  extra_time              BOOLEAN     NOT NULL DEFAULT false,

  home_et_goals           INTEGER     NOT NULL DEFAULT 0 CHECK (home_et_goals >= 0),

  away_et_goals           INTEGER     NOT NULL DEFAULT 0 CHECK (away_et_goals >= 0),

  -- Ratification

  is_official             BOOLEAN     NOT NULL DEFAULT false,

  ratified_by             UUID        REFERENCES profiles(id) ON DELETE SET NULL,

  ratified_at             TIMESTAMPTZ,

  entered_by              UUID        REFERENCES profiles(id) ON DELETE SET NULL,

  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()

);

-- -----------------------------------------------------------

-- player_match_stats

-- Individual player statistics per match.

-- One row per player per fixture.

-- -----------------------------------------------------------

CREATE TABLE player_match_stats (

  id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  fixture_id          UUID        NOT NULL REFERENCES fixtures(id) ON DELETE CASCADE,

  player_id           UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,

  club_id             UUID        NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  started             BOOLEAN     NOT NULL DEFAULT false,

  minutes_played      INTEGER     NOT NULL DEFAULT 0 CHECK (minutes_played >= 0 AND minutes_played <= 120),

  goals               INTEGER     NOT NULL DEFAULT 0 CHECK (goals >= 0),

  assists             INTEGER     NOT NULL DEFAULT 0 CHECK (assists >= 0),

  shots               INTEGER     NOT NULL DEFAULT 0 CHECK (shots >= 0),

  shots_on_target     INTEGER     NOT NULL DEFAULT 0 CHECK (shots_on_target >= 0),

  yellow_cards        INTEGER     NOT NULL DEFAULT 0 CHECK (yellow_cards BETWEEN 0 AND 2),

  red_cards           INTEGER     NOT NULL DEFAULT 0 CHECK (red_cards BETWEEN 0 AND 1),

  saves               INTEGER     NOT NULL DEFAULT 0 CHECK (saves >= 0),

  clean_sheet         BOOLEAN     NOT NULL DEFAULT false,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (fixture_id, player_id)

);

-- -----------------------------------------------------------

-- disciplinary_records

-- Every card issued to every player is recorded here.

-- This is the audit trail. Suspensions are derived from this.

-- -----------------------------------------------------------

CREATE TABLE disciplinary_records (

  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  player_id     UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,

  fixture_id    UUID        REFERENCES fixtures(id) ON DELETE SET NULL,

  league_id     UUID        NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  card_type     card_type   NOT NULL,

  match_date    DATE        NOT NULL,

  minute        INTEGER     CHECK (minute BETWEEN 1 AND 120),

  notes         TEXT,

  created_by    UUID        REFERENCES profiles(id) ON DELETE SET NULL,

  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()

);

-- -----------------------------------------------------------

-- suspensions

-- Active or past bans for players.

-- Auto-created by triggers. Can also be created manually.

-- -----------------------------------------------------------

CREATE TABLE suspensions (

  id                  UUID                PRIMARY KEY DEFAULT uuid_generate_v4(),

  player_id           UUID                NOT NULL REFERENCES players(id) ON DELETE CASCADE,

  league_id           UUID                NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  suspension_reason   suspension_reason   NOT NULL,

  matches_suspended   INTEGER             NOT NULL DEFAULT 1 CHECK (matches_suspended > 0),

  matches_served      INTEGER             NOT NULL DEFAULT 0 CHECK (matches_served >= 0),

  start_fixture_id    UUID                REFERENCES fixtures(id) ON DELETE SET NULL,

  reason_notes        TEXT,

  is_active           BOOLEAN             NOT NULL DEFAULT true,

  imposed_by          UUID                REFERENCES profiles(id) ON DELETE SET NULL,

  created_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW(),

  updated_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW()

);

-- -----------------------------------------------------------

-- standings

-- League table. One row per club per league.

-- Updated automatically when a result is ratified (is_official=true).

-- -----------------------------------------------------------

CREATE TABLE standings (

  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  league_id       UUID        NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  club_id         UUID        NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  played          INTEGER     NOT NULL DEFAULT 0 CHECK (played >= 0),

  wins            INTEGER     NOT NULL DEFAULT 0 CHECK (wins >= 0),

  draws           INTEGER     NOT NULL DEFAULT 0 CHECK (draws >= 0),

  losses          INTEGER     NOT NULL DEFAULT 0 CHECK (losses >= 0),

  goals_for       INTEGER     NOT NULL DEFAULT 0 CHECK (goals_for >= 0),

  goals_against   INTEGER     NOT NULL DEFAULT 0 CHECK (goals_against >= 0),

  -- goal_difference and points are computed columns

  goal_difference INTEGER     GENERATED ALWAYS AS (goals_for - goals_against) STORED,

  points          INTEGER     GENERATED ALWAYS AS ((wins * 3) + draws) STORED,

  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (league_id, club_id)

);

-- -----------------------------------------------------------

-- player_assessments

-- Technical scouting data. All fields nullable (empty until assessed).

-- One row per player per assessor (assessors can re-assess).

-- -----------------------------------------------------------

CREATE TABLE player_assessments (

  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  player_id       UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,

  assessor_id     UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  -- Technical attributes (1–100)

  passing         SMALLINT    CHECK (passing BETWEEN 1 AND 100),

  crossing        SMALLINT    CHECK (crossing BETWEEN 1 AND 100),

  tackling        SMALLINT    CHECK (tackling BETWEEN 1 AND 100),

  finishing       SMALLINT    CHECK (finishing BETWEEN 1 AND 100),

  dribbling       SMALLINT    CHECK (dribbling BETWEEN 1 AND 100),

  first_touch     SMALLINT    CHECK (first_touch BETWEEN 1 AND 100),

  -- Mental attributes (1–100)

  leadership      SMALLINT    CHECK (leadership BETWEEN 1 AND 100),

  teamwork        SMALLINT    CHECK (teamwork BETWEEN 1 AND 100),

  determination   SMALLINT    CHECK (determination BETWEEN 1 AND 100),

  decisions       SMALLINT    CHECK (decisions BETWEEN 1 AND 100),

  positioning     SMALLINT    CHECK (positioning BETWEEN 1 AND 100),

  -- Physical attributes (1–100)

  pace            SMALLINT    CHECK (pace BETWEEN 1 AND 100),

  strength        SMALLINT    CHECK (strength BETWEEN 1 AND 100),

  agility         SMALLINT    CHECK (agility BETWEEN 1 AND 100),

  balance         SMALLINT    CHECK (balance BETWEEN 1 AND 100),

  stamina         SMALLINT    CHECK (stamina BETWEEN 1 AND 100),

  -- Goalkeeper attributes (1–100, only relevant for GKs)

  gk_handling     SMALLINT    CHECK (gk_handling BETWEEN 1 AND 100),

  gk_reflexes     SMALLINT    CHECK (gk_reflexes BETWEEN 1 AND 100),

  gk_positioning  SMALLINT    CHECK (gk_positioning BETWEEN 1 AND 100),

  -- Assessor notes

  notes           TEXT,

  assessed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (player_id, assessor_id)

);

-- -----------------------------------------------------------

-- coach_assessments

-- One row per coach per assessor.

-- -----------------------------------------------------------

CREATE TABLE coach_assessments (

  id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  coach_id            UUID        NOT NULL REFERENCES coaches(id) ON DELETE CASCADE,

  assessor_id         UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  tactical_knowledge  SMALLINT    CHECK (tactical_knowledge BETWEEN 1 AND 100),

  motivation          SMALLINT    CHECK (motivation BETWEEN 1 AND 100),

  discipline          SMALLINT    CHECK (discipline BETWEEN 1 AND 100),

  youth_development   SMALLINT    CHECK (youth_development BETWEEN 1 AND 100),

  man_management      SMALLINT    CHECK (man_management BETWEEN 1 AND 100),

  notes               TEXT,

  assessed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (coach_id, assessor_id)

);

-- -----------------------------------------------------------

-- club_assessments

-- One row per club per assessor.

-- -----------------------------------------------------------

CREATE TABLE club_assessments (

  id                    UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  club_id               UUID        NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  assessor_id           UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  reputation            SMALLINT    CHECK (reputation BETWEEN 1 AND 100),

  youth_development     SMALLINT    CHECK (youth_development BETWEEN 1 AND 100),

  training_facilities   SMALLINT    CHECK (training_facilities BETWEEN 1 AND 100),

  stadium_quality       SMALLINT    CHECK (stadium_quality BETWEEN 1 AND 100),

  community_support     SMALLINT    CHECK (community_support BETWEEN 1 AND 100),

  notes                 TEXT,

  assessed_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (club_id, assessor_id)

);

-- ============================================================

-- SECTION 4: INDEXES

-- ============================================================

-- profiles

CREATE INDEX idx_profiles_role         ON profiles(role);

CREATE INDEX idx_profiles_email        ON profiles(email);

-- leagues

CREATE INDEX idx_leagues_status        ON leagues(status);

CREATE INDEX idx_leagues_founder       ON leagues(founder_id);

-- league_staff

CREATE INDEX idx_lstaff_league         ON league_staff(league_id);

CREATE INDEX idx_lstaff_profile        ON league_staff(profile_id);

-- clubs

CREATE INDEX idx_clubs_admin           ON clubs(admin_id);

-- league_clubs

CREATE INDEX idx_lclubs_league         ON league_clubs(league_id);

CREATE INDEX idx_lclubs_club           ON league_clubs(club_id);

CREATE INDEX idx_lclubs_approved       ON league_clubs(approved);

-- players

CREATE INDEX idx_players_club          ON players(club_id);

CREATE INDEX idx_players_position      ON players(position);

CREATE INDEX idx_players_active        ON players(is_active);

-- coaches

CREATE INDEX idx_coaches_club          ON coaches(club_id);

-- fixtures

CREATE INDEX idx_fixtures_league       ON fixtures(league_id);

CREATE INDEX idx_fixtures_home         ON fixtures(home_club_id);

CREATE INDEX idx_fixtures_away         ON fixtures(away_club_id);

CREATE INDEX idx_fixtures_status       ON fixtures(status);

CREATE INDEX idx_fixtures_date         ON fixtures(match_date);

-- match_results

CREATE INDEX idx_results_fixture       ON match_results(fixture_id);

CREATE INDEX idx_results_official      ON match_results(is_official);

-- player_match_stats

CREATE INDEX idx_pms_fixture           ON player_match_stats(fixture_id);

CREATE INDEX idx_pms_player            ON player_match_stats(player_id);

CREATE INDEX idx_pms_club              ON player_match_stats(club_id);

-- disciplinary_records

CREATE INDEX idx_disc_player           ON disciplinary_records(player_id);

CREATE INDEX idx_disc_league           ON disciplinary_records(league_id);

CREATE INDEX idx_disc_fixture          ON disciplinary_records(fixture_id);

-- suspensions

CREATE INDEX idx_susp_player           ON suspensions(player_id);

CREATE INDEX idx_susp_league           ON suspensions(league_id);

CREATE INDEX idx_susp_active           ON suspensions(is_active);

-- standings

CREATE INDEX idx_standings_league      ON standings(league_id);

CREATE INDEX idx_standings_club        ON standings(club_id);

CREATE INDEX idx_standings_points      ON standings(league_id, points DESC, goal_difference DESC);

-- assessments

CREATE INDEX idx_passmt_player         ON player_assessments(player_id);

CREATE INDEX idx_cassmt_coach          ON coach_assessments(coach_id);

CREATE INDEX idx_clubassmt_club        ON club_assessments(club_id);

-- ============================================================

-- SECTION 5: HELPER FUNCTIONS

-- ============================================================

-- -----------------------------------------------------------

-- update_updated_at()

-- Generic trigger function to keep updated_at current.

-- -----------------------------------------------------------

CREATE OR REPLACE FUNCTION update_updated_at()

RETURNS TRIGGER

LANGUAGE plpgsql

AS $$

BEGIN

  NEW.updated_at = NOW();

  RETURN NEW;

END;

$$;

-- -----------------------------------------------------------

-- get_my_role()

-- Returns the role of the currently authenticated user.

-- Used in RLS policies.

-- -----------------------------------------------------------

CREATE OR REPLACE FUNCTION get_my_role()

RETURNS user_role

LANGUAGE sql

STABLE

SECURITY DEFINER

AS $$

  SELECT role FROM profiles WHERE id = auth.uid();

$$;

-- -----------------------------------------------------------

-- is_league_admin(league_uuid)

-- Returns true if the current user is:

--   - a developer, OR

--   - the league founder, OR

--   - an appointed league_admin for that league

-- -----------------------------------------------------------

CREATE OR REPLACE FUNCTION is_league_admin(league_uuid UUID)

RETURNS BOOLEAN

LANGUAGE sql

STABLE

SECURITY DEFINER

AS $$

  SELECT

    get_my_role() = 'developer'

    OR EXISTS (

      SELECT 1 FROM leagues

      WHERE id = league_uuid AND founder_id = auth.uid()

    )

    OR EXISTS (

      SELECT 1 FROM league_staff

      WHERE league_id = league_uuid

        AND profile_id = auth.uid()

        AND role = 'league_admin'

    );

$$;

-- -----------------------------------------------------------

-- is_club_admin(club_uuid)

-- Returns true if the current user is:

--   - a developer, OR

--   - the club admin for that club

-- -----------------------------------------------------------

CREATE OR REPLACE FUNCTION is_club_admin(club_uuid UUID)

RETURNS BOOLEAN

LANGUAGE sql

STABLE

SECURITY DEFINER

AS $$

  SELECT

    get_my_role() = 'developer'

    OR EXISTS (

      SELECT 1 FROM clubs

      WHERE id = club_uuid AND admin_id = auth.uid()

    );

$$;

-- -----------------------------------------------------------

-- is_league_founder_or_developer()

-- Returns true if the current user can create/manage leagues.

-- -----------------------------------------------------------

CREATE OR REPLACE FUNCTION is_league_founder_or_developer()

RETURNS BOOLEAN

LANGUAGE sql

STABLE

SECURITY DEFINER

AS $$

  SELECT get_my_role() IN ('developer', 'league_founder');

$$;

-- ============================================================

-- SECTION 6: UPDATED_AT TRIGGERS

-- ============================================================

CREATE TRIGGER trg_profiles_updated_at

  BEFORE UPDATE ON profiles

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_leagues_updated_at

  BEFORE UPDATE ON leagues

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_clubs_updated_at

  BEFORE UPDATE ON clubs

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_players_updated_at

  BEFORE UPDATE ON players

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_coaches_updated_at

  BEFORE UPDATE ON coaches

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_fixtures_updated_at

  BEFORE UPDATE ON fixtures

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_match_results_updated_at

  BEFORE UPDATE ON match_results

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_player_match_stats_updated_at

  BEFORE UPDATE ON player_match_stats

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_suspensions_updated_at

  BEFORE UPDATE ON suspensions

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_player_assessments_updated_at

  BEFORE UPDATE ON player_assessments

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_coach_assessments_updated_at

  BEFORE UPDATE ON coach_assessments

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_club_assessments_updated_at

  BEFORE UPDATE ON club_assessments

  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================

-- SECTION 7: AUTO-CREATE PROFILE ON SIGNUP

-- ============================================================

-- When a new user registers via Supabase Auth, this trigger

-- automatically inserts their profile row.

CREATE OR REPLACE FUNCTION handle_new_user()

RETURNS TRIGGER

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

BEGIN

  INSERT INTO profiles (id, full_name, email, role)

  VALUES (

    NEW.id,

    COALESCE(NEW.raw_user_meta_data->>'full_name', 'New User'),

    NEW.email,

    COALESCE(

      (NEW.raw_user_meta_data->>'role')::user_role,

      'club_admin'

    )

  )

  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;

END;

$$;

CREATE TRIGGER on_auth_user_created

  AFTER INSERT ON auth.users

  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================

-- SECTION 8: STANDINGS AUTO-UPDATE TRIGGER

-- ============================================================

-- When a match_result is marked is_official = true,

-- automatically recalculate standings for both clubs.

CREATE OR REPLACE FUNCTION update_standings_on_official_result()

RETURNS TRIGGER

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

  -- Only fire when is_official flips from false to true

  IF (TG_OP = 'UPDATE' AND OLD.is_official = false AND NEW.is_official = true)

    OR (TG_OP = 'INSERT' AND NEW.is_official = true) THEN

    -- Get fixture info

    SELECT league_id, home_club_id, away_club_id

    INTO v_league_id, v_home_id, v_away_id

    FROM fixtures

    WHERE id = NEW.fixture_id;

    v_home_goals := NEW.home_goals;

    v_away_goals := NEW.away_goals;

    -- Ensure standings rows exist for both clubs

    INSERT INTO standings (league_id, club_id)

    VALUES (v_league_id, v_home_id)

    ON CONFLICT (league_id, club_id) DO NOTHING;

    INSERT INTO standings (league_id, club_id)

    VALUES (v_league_id, v_away_id)

    ON CONFLICT (league_id, club_id) DO NOTHING;

    -- Home club update

    UPDATE standings

    SET

      played        = played + 1,

      wins          = wins   + CASE WHEN v_home_goals > v_away_goals  THEN 1 ELSE 0 END,

      draws         = draws  + CASE WHEN v_home_goals = v_away_goals  THEN 1 ELSE 0 END,

      losses        = losses + CASE WHEN v_home_goals < v_away_goals  THEN 1 ELSE 0 END,

      goals_for     = goals_for     + v_home_goals,

      goals_against = goals_against + v_away_goals,

      updated_at    = NOW()

    WHERE league_id = v_league_id AND club_id = v_home_id;

    -- Away club update

    UPDATE standings

    SET

      played        = played + 1,

      wins          = wins   + CASE WHEN v_away_goals > v_home_goals  THEN 1 ELSE 0 END,

      draws         = draws  + CASE WHEN v_away_goals = v_home_goals  THEN 1 ELSE 0 END,

      losses        = losses + CASE WHEN v_away_goals < v_home_goals  THEN 1 ELSE 0 END,

      goals_for     = goals_for     + v_away_goals,

      goals_against = goals_against + v_home_goals,

      updated_at    = NOW()

    WHERE league_id = v_league_id AND club_id = v_away_id;

  END IF;

  RETURN NEW;

END;

$$;

CREATE TRIGGER trg_official_result_standings

  AFTER INSERT OR UPDATE ON match_results

  FOR EACH ROW EXECUTE FUNCTION update_standings_on_official_result();

-- ============================================================

-- SECTION 9: AUTO-SUSPENSION TRIGGER (RED CARDS)

-- ============================================================

-- When a red card disciplinary record is inserted,

-- automatically create a suspension for that player.

CREATE OR REPLACE FUNCTION auto_suspend_on_red_card()

RETURNS TRIGGER

LANGUAGE plpgsql

SECURITY DEFINER

AS $$

DECLARE

  v_ban_matches INTEGER;

BEGIN

  IF NEW.card_type IN ('red', 'second_yellow') THEN

    -- Get the ban length configured for this league

    SELECT red_card_ban_matches INTO v_ban_matches

    FROM leagues WHERE id = NEW.league_id;

    INSERT INTO suspensions (

      player_id,

      league_id,

      suspension_reason,

      matches_suspended,

      matches_served,

      start_fixture_id,

      reason_notes,

      is_active

    ) VALUES (

      NEW.player_id,

      NEW.league_id,

      'automatic_red_card',

      COALESCE(v_ban_matches, 1),

      0,

      NEW.fixture_id,

      'Automatic suspension for red card on ' || NEW.match_date::TEXT,

      true

    );

  END IF;

  RETURN NEW;

END;

$$;

CREATE TRIGGER trg_auto_suspend_red_card

  AFTER INSERT ON disciplinary_records

  FOR EACH ROW EXECUTE FUNCTION auto_suspend_on_red_card();

-- ============================================================

-- SECTION 10: YELLOW CARD ACCUMULATION TRIGGER

-- ============================================================

-- When a yellow card is inserted, check if the player has now

-- reached the league's yellow card threshold. If so, create a

-- suspension automatically.

CREATE OR REPLACE FUNCTION auto_suspend_on_yellow_accumulation()

RETURNS TRIGGER

LANGUAGE plpgsql

SECURITY DEFINER

AS $$

DECLARE

  v_threshold     INTEGER;

  v_yellow_count  INTEGER;

  v_already_susp  BOOLEAN;

BEGIN

  IF NEW.card_type = 'yellow' THEN

    -- Get threshold for this league

    SELECT yellow_card_threshold INTO v_threshold

    FROM leagues WHERE id = NEW.league_id;

    -- Count all yellow cards this player has in this league

    SELECT COUNT(*) INTO v_yellow_count

    FROM disciplinary_records

    WHERE player_id   = NEW.player_id

      AND league_id   = NEW.league_id

      AND card_type   = 'yellow';

    -- Check threshold and that we haven't already auto-suspended for this batch

    -- (We use modulo so suspensions fire at 5, 10, 15, etc.)

    IF v_yellow_count > 0 AND (v_yellow_count % v_threshold) = 0 THEN

      INSERT INTO suspensions (

        player_id,

        league_id,

        suspension_reason,

        matches_suspended,

        matches_served,

        start_fixture_id,

        reason_notes,

        is_active

      ) VALUES (

        NEW.player_id,

        NEW.league_id,

        'yellow_card_accumulation',

        1,

        0,

        NEW.fixture_id,

        'Automatic suspension: reached ' || v_yellow_count || ' yellow cards',

        true

      );

    END IF;

  END IF;

  RETURN NEW;

END;

$$;

CREATE TRIGGER trg_auto_suspend_yellows

  AFTER INSERT ON disciplinary_records

  FOR EACH ROW EXECUTE FUNCTION auto_suspend_on_yellow_accumulation();

-- ============================================================

-- SECTION 11: ROW LEVEL SECURITY — ENABLE

-- ============================================================

ALTER TABLE profiles             ENABLE ROW LEVEL SECURITY;

ALTER TABLE leagues               ENABLE ROW LEVEL SECURITY;

ALTER TABLE league_staff          ENABLE ROW LEVEL SECURITY;

ALTER TABLE clubs                 ENABLE ROW LEVEL SECURITY;

ALTER TABLE league_clubs          ENABLE ROW LEVEL SECURITY;

ALTER TABLE players               ENABLE ROW LEVEL SECURITY;

ALTER TABLE coaches               ENABLE ROW LEVEL SECURITY;

ALTER TABLE fixtures              ENABLE ROW LEVEL SECURITY;

ALTER TABLE match_results         ENABLE ROW LEVEL SECURITY;

ALTER TABLE player_match_stats    ENABLE ROW LEVEL SECURITY;

ALTER TABLE disciplinary_records  ENABLE ROW LEVEL SECURITY;

ALTER TABLE suspensions           ENABLE ROW LEVEL SECURITY;

ALTER TABLE standings             ENABLE ROW LEVEL SECURITY;

ALTER TABLE player_assessments    ENABLE ROW LEVEL SECURITY;

ALTER TABLE coach_assessments     ENABLE ROW LEVEL SECURITY;

ALTER TABLE club_assessments      ENABLE ROW LEVEL SECURITY;

-- ============================================================

-- SECTION 12: RLS POLICIES

-- ============================================================

-- ==========================

-- profiles

-- ==========================

-- Anyone can read (public portal needs coach/player profiles)

CREATE POLICY "profiles: public read"

  ON profiles FOR SELECT

  USING (true);

-- Each user can insert their own profile (used by auth trigger)

CREATE POLICY "profiles: insert own"

  ON profiles FOR INSERT

  WITH CHECK (id = auth.uid());

-- Users update their own profile; developers update any

CREATE POLICY "profiles: update own or developer"

  ON profiles FOR UPDATE

  USING (id = auth.uid() OR get_my_role() = 'developer');

-- Only developers can delete profiles

CREATE POLICY "profiles: developer delete"

  ON profiles FOR DELETE

  USING (get_my_role() = 'developer');

-- ==========================

-- leagues

-- ==========================

CREATE POLICY "leagues: public read"

  ON leagues FOR SELECT

  USING (true);

-- Only developers create leagues

CREATE POLICY "leagues: developer insert"

  ON leagues FOR INSERT

  WITH CHECK (get_my_role() = 'developer');

-- Developers and the league founder can update

CREATE POLICY "leagues: founder or developer update"

  ON leagues FOR UPDATE

  USING (get_my_role() = 'developer' OR founder_id = auth.uid());

-- ==========================

-- league_staff

-- ==========================

CREATE POLICY "league_staff: public read"

  ON league_staff FOR SELECT

  USING (true);

-- Founders appoint staff for their league; developers appoint for any

CREATE POLICY "league_staff: founder or developer insert"

  ON league_staff FOR INSERT

  WITH CHECK (

    get_my_role() = 'developer'

    OR EXISTS (

      SELECT 1 FROM leagues

      WHERE id = league_id AND founder_id = auth.uid()

    )

  );

CREATE POLICY "league_staff: founder or developer delete"

  ON league_staff FOR DELETE

  USING (

    get_my_role() = 'developer'

    OR EXISTS (

      SELECT 1 FROM leagues

      WHERE id = league_id AND founder_id = auth.uid()

    )

  );

-- ==========================

-- clubs

-- ==========================

CREATE POLICY "clubs: public read"

  ON clubs FOR SELECT

  USING (true);

-- Authenticated users can create a club (then assign admin to themselves)

CREATE POLICY "clubs: authenticated insert"

  ON clubs FOR INSERT

  WITH CHECK (auth.uid() IS NOT NULL);

-- Club admin updates their own club; developers update any

CREATE POLICY "clubs: admin or developer update"

  ON clubs FOR UPDATE

  USING (is_club_admin(id));

-- ==========================

-- league_clubs

-- ==========================

CREATE POLICY "league_clubs: public read"

  ON league_clubs FOR SELECT

  USING (true);

-- Any authenticated user can request to join a league

CREATE POLICY "league_clubs: authenticated insert"

  ON league_clubs FOR INSERT

  WITH CHECK (auth.uid() IS NOT NULL);

-- Only league founders and developers can approve memberships

CREATE POLICY "league_clubs: founder or developer update"

  ON league_clubs FOR UPDATE

  USING (

    get_my_role() = 'developer'

    OR EXISTS (

      SELECT 1 FROM leagues

      WHERE id = league_id AND founder_id = auth.uid()

    )

  );

-- ==========================

-- players

-- ==========================

CREATE POLICY "players: public read"

  ON players FOR SELECT

  USING (true);

-- Club admins register players for their own club

CREATE POLICY "players: club admin insert"

  ON players FOR INSERT

  WITH CHECK (

    get_my_role() IN ('developer', 'club_admin')

    AND (club_id IS NULL OR is_club_admin(club_id))

  );

-- Club admins update their own club's players; developers update any

CREATE POLICY "players: club admin or developer update"

  ON players FOR UPDATE

  USING (

    get_my_role() = 'developer'

    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))

  );

-- ==========================

-- coaches

-- ==========================

CREATE POLICY "coaches: public read"

  ON coaches FOR SELECT

  USING (true);

CREATE POLICY "coaches: club admin insert"

  ON coaches FOR INSERT

  WITH CHECK (

    get_my_role() IN ('developer', 'club_admin')

    AND (club_id IS NULL OR is_club_admin(club_id))

  );

CREATE POLICY "coaches: club admin or developer update"

  ON coaches FOR UPDATE

  USING (

    get_my_role() = 'developer'

    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))

  );

-- ==========================

-- fixtures

-- ==========================

CREATE POLICY "fixtures: public read"

  ON fixtures FOR SELECT

  USING (true);

CREATE POLICY "fixtures: league admin insert"

  ON fixtures FOR INSERT

  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "fixtures: league admin update"

  ON fixtures FOR UPDATE

  USING (is_league_admin(league_id));

-- ==========================

-- match_results

-- ==========================

CREATE POLICY "match_results: public read"

  ON match_results FOR SELECT

  USING (true);

CREATE POLICY "match_results: league admin insert"

  ON match_results FOR INSERT

  WITH CHECK (

    EXISTS (

      SELECT 1 FROM fixtures f

      WHERE f.id = fixture_id AND is_league_admin(f.league_id)

    )

  );

CREATE POLICY "match_results: league admin update"

  ON match_results FOR UPDATE

  USING (

    EXISTS (

      SELECT 1 FROM fixtures f

      WHERE f.id = fixture_id AND is_league_admin(f.league_id)

    )

  );

-- ==========================

-- player_match_stats

-- ==========================

CREATE POLICY "player_match_stats: public read"

  ON player_match_stats FOR SELECT

  USING (true);

CREATE POLICY "player_match_stats: league admin insert"

  ON player_match_stats FOR INSERT

  WITH CHECK (

    EXISTS (

      SELECT 1 FROM fixtures f

      WHERE f.id = fixture_id AND is_league_admin(f.league_id)

    )

  );

CREATE POLICY "player_match_stats: league admin update"

  ON player_match_stats FOR UPDATE

  USING (

    EXISTS (

      SELECT 1 FROM fixtures f

      WHERE f.id = fixture_id AND is_league_admin(f.league_id)

    )

  );

-- ==========================

-- disciplinary_records

-- ==========================

CREATE POLICY "disciplinary_records: public read"

  ON disciplinary_records FOR SELECT

  USING (true);

CREATE POLICY "disciplinary_records: league admin insert"

  ON disciplinary_records FOR INSERT

  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "disciplinary_records: league admin update"

  ON disciplinary_records FOR UPDATE

  USING (is_league_admin(league_id));

-- ==========================

-- suspensions

-- ==========================

CREATE POLICY "suspensions: public read"

  ON suspensions FOR SELECT

  USING (true);

CREATE POLICY "suspensions: league admin insert"

  ON suspensions FOR INSERT

  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "suspensions: league admin update"

  ON suspensions FOR UPDATE

  USING (is_league_admin(league_id));

-- ==========================

-- standings

-- ==========================

CREATE POLICY "standings: public read"

  ON standings FOR SELECT

  USING (true);

-- The trigger function runs as SECURITY DEFINER so it bypasses RLS.

-- These policies cover manual inserts/updates from the app layer.

CREATE POLICY "standings: league admin insert"

  ON standings FOR INSERT

  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "standings: league admin update"

  ON standings FOR UPDATE

  USING (is_league_admin(league_id));

-- ==========================

-- player_assessments

-- ==========================

CREATE POLICY "player_assessments: public read"

  ON player_assessments FOR SELECT

  USING (true);

CREATE POLICY "player_assessments: assessor insert"

  ON player_assessments FOR INSERT

  WITH CHECK (

    get_my_role() IN ('technical_assessor', 'developer')

    AND assessor_id = auth.uid()

  );

-- Assessors can only update their own assessments; developers update any

CREATE POLICY "player_assessments: assessor or developer update"

  ON player_assessments FOR UPDATE

  USING (

    get_my_role() = 'developer'

    OR (get_my_role() = 'technical_assessor' AND assessor_id = auth.uid())

  );

-- ==========================

-- coach_assessments

-- ==========================

CREATE POLICY "coach_assessments: public read"

  ON coach_assessments FOR SELECT

  USING (true);

CREATE POLICY "coach_assessments: assessor insert"

  ON coach_assessments FOR INSERT

  WITH CHECK (

    get_my_role() IN ('technical_assessor', 'developer')

    AND assessor_id = auth.uid()

  );

CREATE POLICY "coach_assessments: assessor or developer update"

  ON coach_assessments FOR UPDATE

  USING (

    get_my_role() = 'developer'

    OR (get_my_role() = 'technical_assessor' AND assessor_id = auth.uid())

  );

-- ==========================

-- club_assessments

-- ==========================

CREATE POLICY "club_assessments: public read"

  ON club_assessments FOR SELECT

  USING (true);

CREATE POLICY "club_assessments: assessor insert"

  ON club_assessments FOR INSERT

  WITH CHECK (

    get_my_role() IN ('technical_assessor', 'developer')

    AND assessor_id = auth.uid()

  );

CREATE POLICY "club_assessments: assessor or developer update"

  ON club_assessments FOR UPDATE

  USING (

    get_my_role() = 'developer'

    OR (get_my_role() = 'technical_assessor' AND assessor_id = auth.uid())

  );

-- ============================================================

-- SECTION 13: VIEWS (read-only, public safe)

-- ============================================================

-- Player profile with calculated age

CREATE VIEW v_player_profiles AS

SELECT

  p.id,

  p.full_name,

  p.date_of_birth,

  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,

  p.preferred_foot,

  p.position,

  p.photo_url,

  p.jersey_number,

  p.nationality,

  p.is_active,

  p.club_id,

  c.name  AS club_name,

  c.logo_url AS club_logo

FROM players p

LEFT JOIN clubs c ON c.id = p.club_id;

-- Active suspensions (still serving ban)

CREATE VIEW v_active_suspensions AS

SELECT

  s.id,

  s.player_id,

  p.full_name         AS player_name,

  p.position          AS player_position,

  cl.name             AS club_name,

  s.league_id,

  l.name              AS league_name,

  s.suspension_reason,

  s.matches_suspended,

  s.matches_served,

  (s.matches_suspended - s.matches_served) AS matches_remaining,

  s.reason_notes,

  s.created_at

FROM suspensions s

JOIN players  p  ON p.id  = s.player_id

LEFT JOIN clubs  cl ON cl.id = p.club_id

JOIN leagues  l  ON l.id  = s.league_id

WHERE s.is_active = true

  AND s.matches_served < s.matches_suspended;

-- League standings ordered correctly

CREATE VIEW v_standings AS

SELECT

  s.id,

  s.league_id,

  l.name              AS league_name,

  s.club_id,

  c.name              AS club_name,

  c.logo_url          AS club_logo,

  s.played,

  s.wins,

  s.draws,

  s.losses,

  s.goals_for,

  s.goals_against,

  s.goal_difference,

  s.points,

  ROW_NUMBER() OVER (

    PARTITION BY s.league_id

    ORDER BY s.points DESC, s.goal_difference DESC, s.goals_for DESC

  ) AS position

FROM standings s

JOIN clubs   c ON c.id = s.club_id

JOIN leagues l ON l.id = s.league_id;

-- Top scorers (official matches only)

CREATE VIEW v_top_scorers AS

SELECT

  p.id                AS player_id,

  p.full_name,

  p.position,

  p.photo_url,

  c.name              AS club_name,

  f.league_id,

  SUM(pms.goals)      AS total_goals,

  SUM(pms.assists)    AS total_assists,

  COUNT(pms.id)       AS matches_played

FROM player_match_stats pms

JOIN players  p   ON p.id  = pms.player_id

LEFT JOIN clubs  c   ON c.id  = p.club_id

JOIN fixtures f   ON f.id  = pms.fixture_id

JOIN match_results mr ON mr.fixture_id = f.id AND mr.is_official = true

GROUP BY p.id, p.full_name, p.position, p.photo_url, c.name, f.league_id;

-- Discipline leaderboard (yellow cards per player per league)

CREATE VIEW v_discipline_summary AS

SELECT

  dr.player_id,

  p.full_name,

  c.name              AS club_name,

  dr.league_id,

  COUNT(*) FILTER (WHERE dr.card_type = 'yellow')       AS yellow_cards,

  COUNT(*) FILTER (WHERE dr.card_type IN ('red', 'second_yellow')) AS red_cards

FROM disciplinary_records dr

JOIN players p  ON p.id  = dr.player_id

LEFT JOIN clubs  c  ON c.id  = p.club_id

GROUP BY dr.player_id, p.full_name, c.name, dr.league_id;

-- ============================================================

-- SECTION 14: STORAGE BUCKETS

-- ============================================================

-- Run these in Supabase Dashboard > Storage, OR via SQL if

-- using the storage schema. These create public read buckets

-- for images uploaded through the app.

INSERT INTO storage.buckets (id, name, public)

VALUES

  ('league-logos',   'league-logos',   true),

  ('club-logos',     'club-logos',     true),

  ('player-photos',  'player-photos',  true),

  ('coach-photos',   'coach-photos',   true)

ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload to buckets

CREATE POLICY "storage: auth upload league-logos"

  ON storage.objects FOR INSERT

  WITH CHECK (bucket_id = 'league-logos' AND auth.uid() IS NOT NULL);

CREATE POLICY "storage: public read league-logos"

  ON storage.objects FOR SELECT

  USING (bucket_id = 'league-logos');

CREATE POLICY "storage: auth upload club-logos"

  ON storage.objects FOR INSERT

  WITH CHECK (bucket_id = 'club-logos' AND auth.uid() IS NOT NULL);

CREATE POLICY "storage: public read club-logos"

  ON storage.objects FOR SELECT

  USING (bucket_id = 'club-logos');

CREATE POLICY "storage: auth upload player-photos"

  ON storage.objects FOR INSERT

  WITH CHECK (bucket_id = 'player-photos' AND auth.uid() IS NOT NULL);

CREATE POLICY "storage: public read player-photos"

  ON storage.objects FOR SELECT

  USING (bucket_id = 'player-photos');

CREATE POLICY "storage: auth upload coach-photos"

  ON storage.objects FOR INSERT

  WITH CHECK (bucket_id = 'coach-photos' AND auth.uid() IS NOT NULL);

CREATE POLICY "storage: public read coach-photos"

  ON storage.objects FOR SELECT

  USING (bucket_id = 'coach-photos');

-- ============================================================

-- PHASE 1 COMPLETE

-- Tables: 16

-- Enums: 7

-- Functions: 6

-- Triggers: 15

-- Views: 5

-- Storage buckets: 4

-- RLS policies: 45+

-- ============================================================