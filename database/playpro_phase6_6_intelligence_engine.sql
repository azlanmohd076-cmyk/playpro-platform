-- ============================================================
-- PlayPro Phase 6.6 — Football Intelligence Engine
-- ============================================================
-- Version:    6.6.0
-- Date:       2026-06-08
-- Depends on: All Phase 1–4.2 patches + Phase 6.5 migration
-- ============================================================
-- MODULES:
--   1. Advanced Match Event Engine
--      - Extended match_event_type enum (13 new types)
--      - match_event_details (extended data per event)
--      - player_match_stats extended columns
--      - post_match_aggregation() trigger function
--
--   2. AI Attribute Engine
--      - attribute_ai_weights (per-event attribute impact map)
--      - apply_match_events_to_attributes()
--      - attribute decay mechanism
--      - confidence scoring update
--
--   3. Scout Engine
--      - scout_reports (FM-style structured report)
--      - scout_report_items (per-attribute notes)
--      - player_similarities (similar player pairs)
--      - scout_recommendations
--
--   4. Football Search Engine
--      - v_player_search (full parameterised view)
--      - search_players() function
--      - mv_player_search_index (materialised for performance)
--
--   5. Transfer Market Engine
--      - player_market_values (computed + manual)
--      - market_value_history
--      - compute_player_market_value()
--
--   6. Reputation Engine
--      - reputation_scores (player/coach/club/league)
--      - reputation_history
--      - compute_reputation()
-- ============================================================
-- CONSTRAINTS:
--   ✓ No existing Phase 1–4 objects modified except
--     ALTER TYPE ADD VALUE (outside transaction) and
--     ALTER TABLE ... ADD COLUMN IF NOT EXISTS
--   ✓ All SQL is PostgreSQL 16 + Supabase compatible
--   ✓ ENUM ADD VALUE outside transaction (Part A)
--   ✓ All other DDL inside single BEGIN...COMMIT (Part B)
-- ============================================================

-- ============================================================
-- PART A — ENUM EXTENSIONS (must run outside transaction)
-- ============================================================

-- Extend match_event_type with intelligence-grade event types
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'pass_successful';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'pass_failed';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'key_pass';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'cross_attempted';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'cross_successful';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'through_ball';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'tackle_won';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'tackle_lost';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'duel_won';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'duel_lost';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'clearance';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'interception';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'error_leading_to_goal';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'shot_on_target';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'shot_off_target';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'shot_blocked';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'foul_committed';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'foul_won';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'keeper_save_routine';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'keeper_save_difficult';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'keeper_save_exceptional';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'keeper_claim_cross';
ALTER TYPE match_event_type ADD VALUE IF NOT EXISTS 'keeper_error';

-- ============================================================
-- PART B — MAIN MIGRATION (single transaction)
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- MODULE 1: ADVANCED MATCH EVENT ENGINE
-- ════════════════════════════════════════════════════════════

-- ── 1a. Extended player_match_stats columns ──────────────────
-- Phase 1 has: goals, assists, shots, shots_on_target, yellow_cards,
-- red_cards, saves, clean_sheet, minutes_played, started
-- We add the intelligence-grade columns.

ALTER TABLE player_match_stats
  ADD COLUMN IF NOT EXISTS passes_attempted    SMALLINT NOT NULL DEFAULT 0
    CHECK (passes_attempted >= 0),
  ADD COLUMN IF NOT EXISTS passes_completed    SMALLINT NOT NULL DEFAULT 0
    CHECK (passes_completed >= 0),
  ADD COLUMN IF NOT EXISTS key_passes          SMALLINT NOT NULL DEFAULT 0
    CHECK (key_passes >= 0),
  ADD COLUMN IF NOT EXISTS crosses_attempted   SMALLINT NOT NULL DEFAULT 0
    CHECK (crosses_attempted >= 0),
  ADD COLUMN IF NOT EXISTS crosses_completed   SMALLINT NOT NULL DEFAULT 0
    CHECK (crosses_completed >= 0),
  ADD COLUMN IF NOT EXISTS through_balls       SMALLINT NOT NULL DEFAULT 0
    CHECK (through_balls >= 0),
  ADD COLUMN IF NOT EXISTS tackles_attempted   SMALLINT NOT NULL DEFAULT 0
    CHECK (tackles_attempted >= 0),
  ADD COLUMN IF NOT EXISTS tackles_won         SMALLINT NOT NULL DEFAULT 0
    CHECK (tackles_won >= 0),
  ADD COLUMN IF NOT EXISTS duels_attempted     SMALLINT NOT NULL DEFAULT 0
    CHECK (duels_attempted >= 0),
  ADD COLUMN IF NOT EXISTS duels_won           SMALLINT NOT NULL DEFAULT 0
    CHECK (duels_won >= 0),
  ADD COLUMN IF NOT EXISTS clearances          SMALLINT NOT NULL DEFAULT 0
    CHECK (clearances >= 0),
  ADD COLUMN IF NOT EXISTS interceptions       SMALLINT NOT NULL DEFAULT 0
    CHECK (interceptions >= 0),
  ADD COLUMN IF NOT EXISTS errors_leading_to_goal SMALLINT NOT NULL DEFAULT 0
    CHECK (errors_leading_to_goal >= 0),
  ADD COLUMN IF NOT EXISTS fouls_committed     SMALLINT NOT NULL DEFAULT 0
    CHECK (fouls_committed >= 0),
  ADD COLUMN IF NOT EXISTS fouls_won           SMALLINT NOT NULL DEFAULT 0
    CHECK (fouls_won >= 0),
  -- Goalkeeper extended
  ADD COLUMN IF NOT EXISTS saves_routine       SMALLINT NOT NULL DEFAULT 0
    CHECK (saves_routine >= 0),
  ADD COLUMN IF NOT EXISTS saves_difficult     SMALLINT NOT NULL DEFAULT 0
    CHECK (saves_difficult >= 0),
  ADD COLUMN IF NOT EXISTS saves_exceptional   SMALLINT NOT NULL DEFAULT 0
    CHECK (saves_exceptional >= 0),
  ADD COLUMN IF NOT EXISTS crosses_claimed     SMALLINT NOT NULL DEFAULT 0
    CHECK (crosses_claimed >= 0),
  ADD COLUMN IF NOT EXISTS goalkeeper_errors   SMALLINT NOT NULL DEFAULT 0
    CHECK (goalkeeper_errors >= 0),
  -- Computed rates (populated by aggregation function)
  ADD COLUMN IF NOT EXISTS pass_accuracy       NUMERIC(5,2), -- 0.00–100.00
  ADD COLUMN IF NOT EXISTS tackle_success_rate NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS duel_success_rate   NUMERIC(5,2),
  ADD COLUMN IF NOT EXISTS cross_accuracy      NUMERIC(5,2),
  -- Match rating (1.0–10.0, computed by AI engine)
  ADD COLUMN IF NOT EXISTS match_rating        NUMERIC(3,1)
    CHECK (match_rating IS NULL OR match_rating BETWEEN 1.0 AND 10.0),
  -- Position played in this match (may differ from registered position)
  ADD COLUMN IF NOT EXISTS position_played     TEXT,
  -- Distance covered in km (if GPS available)
  ADD COLUMN IF NOT EXISTS distance_km         NUMERIC(4,1)
    CHECK (distance_km IS NULL OR distance_km BETWEEN 0 AND 20),
  -- Man of the Match flag
  ADD COLUMN IF NOT EXISTS is_motm             BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_pms_motm
  ON player_match_stats(fixture_id) WHERE is_motm = true;

CREATE INDEX IF NOT EXISTS idx_pms_rating
  ON player_match_stats(player_id, match_rating DESC NULLS LAST);

-- ── 1b. match_event_details ───────────────────────────────────
-- Extended metadata per match event. Keeps match_events clean
-- while storing the intelligence payload separately.

CREATE TABLE match_event_details (
  id                  UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id            UUID          NOT NULL UNIQUE
                      REFERENCES match_events(id) ON DELETE CASCADE,
  -- Spatial context (pitch zone 1-18, Opta-style grid)
  zone_from           SMALLINT      CHECK (zone_from BETWEEN 1 AND 18),
  zone_to             SMALLINT      CHECK (zone_to BETWEEN 1 AND 18),
  -- Pass metadata
  pass_length_m       SMALLINT      CHECK (pass_length_m BETWEEN 0 AND 120),
  pass_direction      TEXT          CHECK (pass_direction IN
                        ('forward','backward','lateral','diagonal')),
  pass_technique      TEXT          CHECK (pass_technique IN
                        ('short','long','driven','lofted','through')),
  -- Shot metadata
  shot_technique      TEXT          CHECK (shot_technique IN
                        ('foot_right','foot_left','header','volley','chip')),
  shot_placement      TEXT          CHECK (shot_placement IN
                        ('top_left','top_right','bottom_left','bottom_right',
                         'centre','blocked','post','bar')),
  shot_xg             NUMERIC(4,3)  CHECK (shot_xg BETWEEN 0 AND 1),
  -- Duel metadata
  duel_type           TEXT          CHECK (duel_type IN
                        ('aerial','ground','tackle')),
  -- Body part
  body_part           TEXT          CHECK (body_part IN
                        ('right_foot','left_foot','head','chest','other')),
  -- Was this under pressure?
  under_pressure      BOOLEAN       NOT NULL DEFAULT false,
  -- Outcome quality (for AI engine)
  outcome_quality     TEXT          CHECK (outcome_quality IN
                        ('exceptional','good','average','poor','error')),
  -- Raw coordinates (optional; if tracking data available)
  x_coord             NUMERIC(5,2),
  y_coord             NUMERIC(5,2),
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_evtdet_event
  ON match_event_details(event_id);

CREATE INDEX idx_evtdet_zone
  ON match_event_details(zone_from, zone_to)
  WHERE zone_from IS NOT NULL;

ALTER TABLE match_event_details ENABLE ROW LEVEL SECURITY;

CREATE POLICY "match_event_details: public read"
  ON match_event_details FOR SELECT USING (true);

CREATE POLICY "match_event_details: authorised write"
  ON match_event_details FOR INSERT
  WITH CHECK (
    get_my_role() IN ('developer','league_admin','league_founder',
                      'club_admin','referee')
  );

-- ── 1c. post_match_aggregation() ────────────────────────────
-- Called after match events are entered. Aggregates raw events
-- into player_match_stats columns. SECURITY DEFINER.

CREATE OR REPLACE FUNCTION post_match_aggregation(p_fixture_id UUID)
RETURNS INTEGER  -- returns count of player rows updated
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  -- For each player who appears in match_events for this fixture,
  -- aggregate event counts into player_match_stats
  WITH event_counts AS (
    SELECT
      me.player_id,
      me.club_id,
      COUNT(CASE WHEN me.event_type = 'pass_successful'          THEN 1 END) AS passes_completed,
      COUNT(CASE WHEN me.event_type IN ('pass_successful','pass_failed') THEN 1 END) AS passes_attempted,
      COUNT(CASE WHEN me.event_type = 'key_pass'                 THEN 1 END) AS key_passes,
      COUNT(CASE WHEN me.event_type IN ('cross_attempted','cross_successful') THEN 1 END) AS crosses_attempted,
      COUNT(CASE WHEN me.event_type = 'cross_successful'         THEN 1 END) AS crosses_completed,
      COUNT(CASE WHEN me.event_type = 'through_ball'             THEN 1 END) AS through_balls,
      COUNT(CASE WHEN me.event_type IN ('tackle_won','tackle_lost') THEN 1 END) AS tackles_attempted,
      COUNT(CASE WHEN me.event_type = 'tackle_won'               THEN 1 END) AS tackles_won,
      COUNT(CASE WHEN me.event_type IN ('duel_won','duel_lost')   THEN 1 END) AS duels_attempted,
      COUNT(CASE WHEN me.event_type = 'duel_won'                 THEN 1 END) AS duels_won,
      COUNT(CASE WHEN me.event_type = 'clearance'                THEN 1 END) AS clearances,
      COUNT(CASE WHEN me.event_type = 'interception'             THEN 1 END) AS interceptions,
      COUNT(CASE WHEN me.event_type = 'error_leading_to_goal'    THEN 1 END) AS errors_leading_to_goal,
      COUNT(CASE WHEN me.event_type = 'foul_committed'           THEN 1 END) AS fouls_committed,
      COUNT(CASE WHEN me.event_type = 'foul_won'                 THEN 1 END) AS fouls_won,
      COUNT(CASE WHEN me.event_type IN
                   ('keeper_save_routine','keeper_save_difficult','keeper_save_exceptional')
                                                                 THEN 1 END) AS saves_total,
      COUNT(CASE WHEN me.event_type = 'keeper_save_routine'      THEN 1 END) AS saves_routine,
      COUNT(CASE WHEN me.event_type = 'keeper_save_difficult'    THEN 1 END) AS saves_difficult,
      COUNT(CASE WHEN me.event_type = 'keeper_save_exceptional'  THEN 1 END) AS saves_exceptional,
      COUNT(CASE WHEN me.event_type = 'keeper_claim_cross'       THEN 1 END) AS crosses_claimed,
      COUNT(CASE WHEN me.event_type = 'keeper_error'             THEN 1 END) AS goalkeeper_errors,
      COUNT(CASE WHEN me.event_type IN ('shot_on_target','shot_off_target','shot_blocked',
                                         'goal','penalty_scored')
                                                                 THEN 1 END) AS shots_total,
      COUNT(CASE WHEN me.event_type IN ('shot_on_target','goal','penalty_scored')
                                                                 THEN 1 END) AS shots_on_target_total,
      COUNT(CASE WHEN me.event_type = 'goal'                     THEN 1 END) AS goals_total,
      COUNT(CASE WHEN me.event_type = 'assist'                   THEN 1 END) AS assists_total
    FROM match_events me
    WHERE me.fixture_id  = p_fixture_id
      AND me.player_id   IS NOT NULL
      AND me.is_cancelled = false
    GROUP BY me.player_id, me.club_id
  )
  INSERT INTO player_match_stats (
    fixture_id, player_id, club_id,
    passes_completed, passes_attempted, key_passes,
    crosses_attempted, crosses_completed, through_balls,
    tackles_attempted, tackles_won,
    duels_attempted, duels_won,
    clearances, interceptions,
    errors_leading_to_goal, fouls_committed, fouls_won,
    saves_routine, saves_difficult, saves_exceptional,
    crosses_claimed, goalkeeper_errors,
    shots, shots_on_target, goals, assists,
    pass_accuracy, tackle_success_rate, duel_success_rate, cross_accuracy
  )
  SELECT
    p_fixture_id,
    ec.player_id,
    ec.club_id,
    ec.passes_completed,
    ec.passes_attempted,
    ec.key_passes,
    ec.crosses_attempted,
    ec.crosses_completed,
    ec.through_balls,
    ec.tackles_attempted,
    ec.tackles_won,
    ec.duels_attempted,
    ec.duels_won,
    ec.clearances,
    ec.interceptions,
    ec.errors_leading_to_goal,
    ec.fouls_committed,
    ec.fouls_won,
    ec.saves_routine,
    ec.saves_difficult,
    ec.saves_exceptional,
    ec.crosses_claimed,
    ec.goalkeeper_errors,
    ec.shots_total,
    ec.shots_on_target_total,
    ec.goals_total,
    ec.assists_total,
    -- computed rates
    CASE WHEN ec.passes_attempted  > 0
         THEN ROUND(ec.passes_completed::NUMERIC  / ec.passes_attempted  * 100, 2) END,
    CASE WHEN ec.tackles_attempted > 0
         THEN ROUND(ec.tackles_won::NUMERIC       / ec.tackles_attempted * 100, 2) END,
    CASE WHEN ec.duels_attempted   > 0
         THEN ROUND(ec.duels_won::NUMERIC         / ec.duels_attempted   * 100, 2) END,
    CASE WHEN ec.crosses_attempted > 0
         THEN ROUND(ec.crosses_completed::NUMERIC / ec.crosses_attempted * 100, 2) END
  FROM event_counts ec
  ON CONFLICT (fixture_id, player_id) DO UPDATE SET
    passes_completed     = EXCLUDED.passes_completed,
    passes_attempted     = EXCLUDED.passes_attempted,
    key_passes           = EXCLUDED.key_passes,
    crosses_attempted    = EXCLUDED.crosses_attempted,
    crosses_completed    = EXCLUDED.crosses_completed,
    through_balls        = EXCLUDED.through_balls,
    tackles_attempted    = EXCLUDED.tackles_attempted,
    tackles_won          = EXCLUDED.tackles_won,
    duels_attempted      = EXCLUDED.duels_attempted,
    duels_won            = EXCLUDED.duels_won,
    clearances           = EXCLUDED.clearances,
    interceptions        = EXCLUDED.interceptions,
    errors_leading_to_goal = EXCLUDED.errors_leading_to_goal,
    fouls_committed      = EXCLUDED.fouls_committed,
    fouls_won            = EXCLUDED.fouls_won,
    saves_routine        = EXCLUDED.saves_routine,
    saves_difficult      = EXCLUDED.saves_difficult,
    saves_exceptional    = EXCLUDED.saves_exceptional,
    crosses_claimed      = EXCLUDED.crosses_claimed,
    goalkeeper_errors    = EXCLUDED.goalkeeper_errors,
    shots                = EXCLUDED.shots,
    shots_on_target      = EXCLUDED.shots_on_target,
    goals                = EXCLUDED.goals,
    assists              = EXCLUDED.assists,
    pass_accuracy        = EXCLUDED.pass_accuracy,
    tackle_success_rate  = EXCLUDED.tackle_success_rate,
    duel_success_rate    = EXCLUDED.duel_success_rate,
    cross_accuracy       = EXCLUDED.cross_accuracy,
    updated_at           = NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- Compute match rating for each player based on aggregated stats
  UPDATE player_match_stats pms SET
    match_rating = compute_match_rating(
      pms.goals, pms.assists, pms.shots_on_target, pms.shots,
      pms.pass_accuracy, pms.tackle_success_rate, pms.duel_success_rate,
      pms.errors_leading_to_goal, pms.yellow_cards, pms.red_cards,
      pms.key_passes, pms.clearances, pms.interceptions,
      pms.saves_routine, pms.saves_difficult, pms.saves_exceptional,
      pms.goalkeeper_errors
    )
  WHERE pms.fixture_id = p_fixture_id;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION post_match_aggregation(UUID) TO authenticated;

-- ── 1d. compute_match_rating() helper ───────────────────────

CREATE OR REPLACE FUNCTION compute_match_rating(
  p_goals          INTEGER, p_assists         INTEGER,
  p_sot            INTEGER, p_shots           INTEGER,
  p_pass_acc       NUMERIC, p_tackle_sr       NUMERIC,
  p_duel_sr        NUMERIC, p_errors          INTEGER,
  p_yellows        INTEGER, p_reds            INTEGER,
  p_key_passes     INTEGER, p_clearances      INTEGER,
  p_interceptions  INTEGER,
  p_saves_r        INTEGER, p_saves_d         INTEGER,
  p_saves_e        INTEGER, p_gk_errors       INTEGER
)
RETURNS NUMERIC(3,1)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_rating NUMERIC := 6.0;  -- baseline
BEGIN
  -- Attacking contributions
  v_rating := v_rating + COALESCE(p_goals,    0) * 0.8;
  v_rating := v_rating + COALESCE(p_assists,  0) * 0.5;
  v_rating := v_rating + COALESCE(p_key_passes, 0) * 0.15;

  -- Shot efficiency
  IF COALESCE(p_shots, 0) > 0 THEN
    v_rating := v_rating
      + (COALESCE(p_sot, 0)::NUMERIC / p_shots - 0.35) * 0.5;
  END IF;

  -- Passing
  IF COALESCE(p_pass_acc, 0) > 0 THEN
    v_rating := v_rating + (p_pass_acc - 70) / 100.0;
  END IF;

  -- Defensive
  v_rating := v_rating + COALESCE(p_clearances,    0) * 0.05;
  v_rating := v_rating + COALESCE(p_interceptions, 0) * 0.10;

  IF COALESCE(p_tackle_sr, 0) > 0 THEN
    v_rating := v_rating + (p_tackle_sr - 50) / 200.0;
  END IF;

  IF COALESCE(p_duel_sr, 0) > 0 THEN
    v_rating := v_rating + (p_duel_sr - 50) / 200.0;
  END IF;

  -- Goalkeeper saves
  v_rating := v_rating + COALESCE(p_saves_r, 0) * 0.1;
  v_rating := v_rating + COALESCE(p_saves_d, 0) * 0.25;
  v_rating := v_rating + COALESCE(p_saves_e, 0) * 0.50;

  -- Negatives
  v_rating := v_rating - COALESCE(p_errors,    0) * 1.5;
  v_rating := v_rating - COALESCE(p_yellows,   0) * 0.3;
  v_rating := v_rating - COALESCE(p_reds,      0) * 1.5;
  v_rating := v_rating - COALESCE(p_gk_errors, 0) * 1.2;

  -- Clamp 1.0–10.0, round to 1dp
  RETURN GREATEST(1.0, LEAST(10.0, ROUND(v_rating, 1)));
END;
$$;

-- ════════════════════════════════════════════════════════════
-- MODULE 2: AI ATTRIBUTE ENGINE
-- ════════════════════════════════════════════════════════════

-- ── 2a. attribute_ai_weights ─────────────────────────────────
-- Maps each match_event_type to attribute impact weights.
-- Positive = attribute raised; Negative = attribute reduced.
-- Values are per-event nudge on the 1-20 scale (accumulated
-- over a season then averaged).

CREATE TABLE attribute_ai_weights (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_type      TEXT          NOT NULL,  -- matches match_event_type
  attribute_code  TEXT          NOT NULL
                  REFERENCES attribute_definitions(code) ON DELETE CASCADE,
  -- Impact per event occurrence (can be negative for errors)
  impact_weight   NUMERIC(5,4)  NOT NULL,  -- e.g. 0.0100 = +0.01 per event
  -- Minimum events needed before this weight is applied
  min_events      SMALLINT      NOT NULL DEFAULT 1,
  -- Position restriction (NULL = all positions)
  position_group  TEXT          CHECK (position_group IN
                    ('goalkeeper','defender','midfielder','forward',NULL)),
  is_active       BOOLEAN       NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (event_type, attribute_code, COALESCE(position_group, ''))
);

CREATE INDEX idx_ai_weights_event
  ON attribute_ai_weights(event_type) WHERE is_active = true;

ALTER TABLE attribute_ai_weights ENABLE ROW LEVEL SECURITY;

CREATE POLICY "attribute_ai_weights: public read"
  ON attribute_ai_weights FOR SELECT USING (true);

CREATE POLICY "attribute_ai_weights: developer write"
  ON attribute_ai_weights FOR ALL
  USING (get_my_role() = 'developer')
  WITH CHECK (get_my_role() = 'developer');

-- Seed the AI weight map
-- Impact scale: 0.02 = moderate signal per event; 0.05 = strong signal
INSERT INTO attribute_ai_weights (event_type, attribute_code, impact_weight, min_events, position_group)
VALUES
  -- PASSING → passing, vision, first_touch
  ('pass_successful',   'passing',       0.0080, 5,  NULL),
  ('pass_successful',   'vision',        0.0040, 10, NULL),
  ('pass_successful',   'decision_making',0.0030,10, NULL),
  ('pass_failed',       'passing',      -0.0060, 5,  NULL),
  ('key_pass',          'passing',       0.0200, 3,  NULL),
  ('key_pass',          'vision',        0.0250, 3,  NULL),
  ('key_pass',          'anticipation',  0.0150, 3,  NULL),
  ('through_ball',      'vision',        0.0300, 2,  NULL),
  ('through_ball',      'passing',       0.0200, 2,  NULL),
  ('through_ball',      'anticipation',  0.0200, 2,  NULL),

  -- CROSSING → crossing (we don't have crossing in v1 18-attr; use passing proxy)
  ('cross_successful',  'passing',       0.0150, 3,  NULL),
  ('cross_successful',  'vision',        0.0100, 3,  NULL),
  ('cross_attempted',   'passing',       0.0020, 5,  NULL),

  -- TACKLING → tackling, strength, anticipation
  ('tackle_won',        'tackling',      0.0200, 3,  NULL),
  ('tackle_won',        'strength',      0.0100, 5,  NULL),
  ('tackle_won',        'anticipation',  0.0100, 5,  NULL),
  ('tackle_won',        'positioning',   0.0080, 5,  NULL),
  ('tackle_lost',       'tackling',     -0.0150, 3,  NULL),

  -- DUELS → strength, agility, work_rate, composure
  ('duel_won',          'strength',      0.0150, 5,  NULL),
  ('duel_won',          'agility',       0.0100, 5,  NULL),
  ('duel_won',          'work_rate',     0.0080, 5,  NULL),
  ('duel_won',          'composure',     0.0060, 5,  NULL),
  ('duel_lost',         'strength',     -0.0080, 5,  NULL),

  -- CLEARANCES / INTERCEPTIONS → positioning, heading, anticipation
  ('clearance',         'positioning',   0.0120, 5,  'defender'),
  ('clearance',         'anticipation',  0.0100, 5,  'defender'),
  ('interception',      'positioning',   0.0150, 3,  NULL),
  ('interception',      'anticipation',  0.0200, 3,  NULL),
  ('interception',      'vision',        0.0100, 5,  NULL),

  -- ERRORS → composure penalty, decision_making penalty
  ('error_leading_to_goal', 'composure',         -0.0500, 1, NULL),
  ('error_leading_to_goal', 'decision_making',   -0.0400, 1, NULL),
  ('error_leading_to_goal', 'concentration',     -0.0300, 1, NULL),

  -- SHOTS → finishing, composure
  ('shot_on_target',    'finishing',     0.0150, 3,  'forward'),
  ('shot_on_target',    'composure',     0.0100, 3,  'forward'),
  ('shot_on_target',    'finishing',     0.0080, 5,  'midfielder'),

  -- GOALKEEPER SAVES → composure, work_rate
  ('keeper_save_routine',    'composure',   0.0060, 5, 'goalkeeper'),
  ('keeper_save_routine',    'work_rate',   0.0040, 5, 'goalkeeper'),
  ('keeper_save_difficult',  'composure',   0.0200, 2, 'goalkeeper'),
  ('keeper_save_difficult',  'decision_making',0.0150,2,'goalkeeper'),
  ('keeper_save_exceptional','composure',   0.0500, 1, 'goalkeeper'),
  ('keeper_save_exceptional','decision_making',0.0300,1,'goalkeeper'),
  ('keeper_claim_cross',     'leadership',  0.0100, 3, 'goalkeeper'),
  ('keeper_error',           'composure',  -0.0600, 1, 'goalkeeper'),
  ('keeper_error',           'decision_making',-0.0400,1,'goalkeeper'),

  -- DISCIPLINARY → work_rate boost (won duels), composure penalty
  ('foul_won',          'work_rate',     0.0050, 5,  NULL),
  ('foul_committed',    'composure',    -0.0030, 5,  NULL);

-- ── 2b. apply_match_events_to_attributes() ──────────────────
-- Core AI engine: reads match events for a completed fixture,
-- maps them to attribute weights, accumulates season deltas,
-- and applies weighted nudges to player_attributes.
-- Called after post_match_aggregation().

CREATE OR REPLACE FUNCTION apply_match_events_to_attributes(
  p_fixture_id UUID,
  p_season_id  UUID
)
RETURNS INTEGER  -- count of attribute updates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player          RECORD;
  v_attr_code       TEXT;
  v_raw_nudge       NUMERIC;
  v_new_ai_value    NUMERIC;
  v_current_val     SMALLINT;
  v_prev_val        SMALLINT;
  v_count           INTEGER := 0;
  v_position_group  TEXT;
BEGIN
  -- Iterate each player who had events in this fixture
  FOR v_player IN
    SELECT DISTINCT me.player_id, p.position
    FROM match_events me
    JOIN players p ON p.id = me.player_id
    WHERE me.fixture_id  = p_fixture_id
      AND me.player_id   IS NOT NULL
      AND me.is_cancelled = false
  LOOP
    -- Map position to group
    v_position_group := CASE v_player.position
      WHEN 'goalkeeper' THEN 'goalkeeper'
      WHEN 'defender'   THEN 'defender'
      WHEN 'midfielder' THEN 'midfielder'
      WHEN 'forward'    THEN 'forward'
      ELSE NULL
    END;

    -- For each attribute that has weights for this player's events
    FOR v_attr_code IN
      SELECT DISTINCT w.attribute_code
      FROM attribute_ai_weights w
      WHERE w.is_active = true
        AND (w.position_group IS NULL OR w.position_group = v_position_group)
    LOOP
      -- Sum nudge from all matching events
      SELECT COALESCE(SUM(w.impact_weight), 0)
      INTO v_raw_nudge
      FROM match_events me
      JOIN attribute_ai_weights w
        ON w.event_type     = me.event_type::TEXT
        AND w.attribute_code = v_attr_code
        AND w.is_active      = true
        AND (w.position_group IS NULL OR w.position_group = v_position_group)
      WHERE me.fixture_id  = p_fixture_id
        AND me.player_id   = v_player.player_id
        AND me.is_cancelled = false;

      -- Skip if no signal
      CONTINUE WHEN v_raw_nudge = 0;

      -- Fetch current AI value
      SELECT ai_value INTO v_current_val
      FROM player_attributes
      WHERE player_id = v_player.player_id AND attribute_code = v_attr_code;

      -- Default to 10 (midpoint) if no prior AI value
      v_current_val := COALESCE(v_current_val, 10);

      -- Apply nudge with regression-to-mean dampening:
      -- Large values resist upward nudges; small values resist downward nudges
      v_new_ai_value := v_current_val + (v_raw_nudge * 20);  -- scale to 1-20 range

      -- Apply regression: nudge is dampened as value approaches extremes
      IF v_raw_nudge > 0 THEN
        v_new_ai_value := v_current_val
          + (v_raw_nudge * 20) * (1 - (v_current_val - 1)::NUMERIC / 19);
      ELSE
        v_new_ai_value := v_current_val
          + (v_raw_nudge * 20) * (1 - (20 - v_current_val)::NUMERIC / 19);
      END IF;

      -- Clamp to [1, 20]
      v_new_ai_value := GREATEST(1, LEAST(20, ROUND(v_new_ai_value)));

      -- Skip if no effective change
      CONTINUE WHEN v_new_ai_value::SMALLINT = v_current_val;

      v_prev_val := v_current_val;

      -- Upsert into player_attributes (ai_value column only)
      INSERT INTO player_attributes (
        player_id, attribute_code, current_value,
        ai_value, confidence_level,
        last_assessed_at, last_assessed_by_type,
        season_id, is_public, created_by
      ) VALUES (
        v_player.player_id, v_attr_code,
        v_new_ai_value::SMALLINT,  -- AI is sole source if no assessments yet
        v_new_ai_value::SMALLINT,
        'low',  -- AI-only confidence until coach/LTO validates
        NOW(), 'ai', p_season_id, true, NULL
      )
      ON CONFLICT (player_id, attribute_code) DO UPDATE SET
        ai_value              = v_new_ai_value::SMALLINT,
        last_assessed_at      = NOW(),
        last_assessed_by_type = 'ai',
        -- Recompute current_value with renormalised weights
        current_value = (
          SELECT GREATEST(1, LEAST(20, ROUND(
            COALESCE(pa2.coach_value,   v_new_ai_value::SMALLINT)
              * CASE WHEN pa2.coach_value IS NOT NULL THEN 0.500 / (
                  CASE WHEN pa2.coach_value IS NOT NULL THEN 0.500 ELSE 0 END
                + CASE WHEN pa2.officer_value IS NOT NULL THEN 0.300 ELSE 0 END
                + 0.200) ELSE 0 END
            + COALESCE(pa2.officer_value, 0)
              * CASE WHEN pa2.officer_value IS NOT NULL THEN 0.300 / (
                  CASE WHEN pa2.coach_value IS NOT NULL THEN 0.500 ELSE 0 END
                + CASE WHEN pa2.officer_value IS NOT NULL THEN 0.300 ELSE 0 END
                + 0.200) ELSE 0 END
            + v_new_ai_value::SMALLINT * 0.200 / (
                  CASE WHEN pa2.coach_value IS NOT NULL THEN 0.500 ELSE 0 END
                + CASE WHEN pa2.officer_value IS NOT NULL THEN 0.300 ELSE 0 END
                + 0.200)
          )::NUMERIC))
          FROM player_attributes pa2
          WHERE pa2.player_id = v_player.player_id
            AND pa2.attribute_code = v_attr_code
          LIMIT 1
        ),
        updated_at = NOW();

      -- Write to history
      INSERT INTO player_attribute_history (
        player_id, attribute_code, value, previous_value,
        recorded_at, season_id, trigger_source, assessment_id
      ) VALUES (
        v_player.player_id, v_attr_code,
        v_new_ai_value::SMALLINT, v_prev_val,
        NOW(), p_season_id, 'ai_batch', NULL
      );

      v_count := v_count + 1;
    END LOOP;

    -- After all attributes updated, recompute DNA
    PERFORM calculate_player_dna(v_player.player_id);

  END LOOP;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION apply_match_events_to_attributes(UUID, UUID) TO authenticated;

-- ── 2c. attribute_decay() ────────────────────────────────────
-- Applies time-based decay to AI-sourced attribute values
-- for players who have not played in N days.
-- Called by nightly cron. Decay is slow (0.05 per week idle).

CREATE OR REPLACE FUNCTION apply_attribute_decay(
  p_idle_threshold_days INTEGER DEFAULT 60
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id   UUID;
  v_last_match  DATE;
  v_idle_weeks  INTEGER;
  v_decay       NUMERIC;
  v_count       INTEGER := 0;
BEGIN
  FOR v_player_id IN
    SELECT DISTINCT p.id
    FROM players p
    WHERE p.is_active = true
      AND NOT EXISTS (
        SELECT 1 FROM match_lineups ml
        JOIN fixtures f ON f.id = ml.fixture_id
        WHERE ml.player_id = p.id
          AND f.match_date >= CURRENT_DATE - p_idle_threshold_days
          AND f.status = 'completed'
      )
  LOOP
    -- Get weeks idle
    SELECT MAX(f.match_date) INTO v_last_match
    FROM match_lineups ml
    JOIN fixtures f ON f.id = ml.fixture_id
    WHERE ml.player_id = v_player_id AND f.status = 'completed';

    v_idle_weeks := GREATEST(0,
      EXTRACT(DAYS FROM CURRENT_DATE - COALESCE(v_last_match, CURRENT_DATE - p_idle_threshold_days))::INTEGER / 7
    );

    -- Decay: 0.05 per week idle on physical attributes only
    -- (mental/tactical attributes decay slower, handled by coach assessment cadence)
    v_decay := LEAST(v_idle_weeks * 0.05, 2.0);  -- cap at 2 points decay

    IF v_decay <= 0 THEN CONTINUE; END IF;

    -- Apply decay to physical AI values
    UPDATE player_attributes SET
      ai_value   = GREATEST(1, ai_value - ROUND(v_decay)::SMALLINT),
      current_value = GREATEST(1,
        ROUND(current_value - (v_decay * 0.20))::SMALLINT), -- AI is 20% of current
      updated_at = NOW()
    WHERE player_id = v_player_id
      AND attribute_code IN ('pace','acceleration','stamina','strength','agility')
      AND ai_value IS NOT NULL
      AND ai_value > 1;

    IF FOUND THEN
      v_count := v_count + 1;
      -- Write decay history
      INSERT INTO player_attribute_history (
        player_id, attribute_code, value, previous_value,
        recorded_at, trigger_source, notes
      )
      SELECT
        v_player_id, attribute_code, ai_value,
        ai_value + ROUND(v_decay)::SMALLINT,
        NOW(), 'ai_batch',
        format('Decay: %s weeks idle', v_idle_weeks)
      FROM player_attributes
      WHERE player_id = v_player_id
        AND attribute_code IN ('pace','acceleration','stamina','strength','agility')
        AND ai_value IS NOT NULL;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION apply_attribute_decay(INTEGER) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- MODULE 3: SCOUT ENGINE
-- ════════════════════════════════════════════════════════════

-- ── 3a. scout_reports ────────────────────────────────────────

CREATE TABLE scout_reports (
  id                  UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id           UUID          NOT NULL
                      REFERENCES players(id) ON DELETE CASCADE,
  scout_profile_id    UUID
                      REFERENCES profiles(id) ON DELETE SET NULL,
  -- Whether this is AI-generated or human-written
  report_source       TEXT          NOT NULL DEFAULT 'human'
                      CHECK (report_source IN ('human','ai','hybrid')),
  season_id           UUID
                      REFERENCES seasons(id) ON DELETE SET NULL,
  -- Match watched (optional — scout may report without a specific game)
  fixture_id          UUID
                      REFERENCES fixtures(id) ON DELETE SET NULL,
  -- Core FM-style report fields
  recommended_role    TEXT,         -- e.g. 'Central Midfielder', 'Ball-Playing Defender'
  playing_style       TEXT,         -- e.g. 'Press-resistant passer', 'Box-to-box'
  -- Narrative sections (human-written or AI-generated)
  overview            TEXT          CHECK (char_length(overview) <= 2000),
  strengths           TEXT          CHECK (char_length(strengths) <= 1000),
  weaknesses          TEXT          CHECK (char_length(weaknesses) <= 1000),
  development_trend   TEXT          CHECK (development_trend IN
                        ('rapidly_improving','improving','stable',
                         'declining','rapidly_declining','insufficient_data')),
  development_notes   TEXT          CHECK (char_length(development_notes) <= 500),
  -- Scout verdict
  recommendation      TEXT          CHECK (recommendation IN
                        ('sign_immediately','sign_if_available','monitor',
                         'release','not_suitable','insufficient_data')),
  recommendation_notes TEXT         CHECK (char_length(recommendation_notes) <= 500),
  -- Predicted values
  predicted_dna_12m   SMALLINT      CHECK (predicted_dna_12m BETWEEN 1 AND 100),
  predicted_dna_36m   SMALLINT      CHECK (predicted_dna_36m BETWEEN 1 AND 100),
  -- Visibility
  is_public           BOOLEAN       NOT NULL DEFAULT false,
  -- Report metadata
  watched_matches     SMALLINT      DEFAULT 1,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by          UUID          REFERENCES profiles(id) ON DELETE SET NULL
);

CREATE TRIGGER trg_scout_reports_updated_at
  BEFORE UPDATE ON scout_reports
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_scout_reports_player
  ON scout_reports(player_id, created_at DESC);

CREATE INDEX idx_scout_reports_scout
  ON scout_reports(scout_profile_id, created_at DESC)
  WHERE scout_profile_id IS NOT NULL;

CREATE INDEX idx_scout_reports_recommendation
  ON scout_reports(recommendation) WHERE recommendation IS NOT NULL;

ALTER TABLE scout_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "scout_reports: scout own read"
  ON scout_reports FOR SELECT
  USING (
    is_public = true
    OR scout_profile_id = auth.uid()
    OR get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
  );

CREATE POLICY "scout_reports: scout insert"
  ON scout_reports FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND scout_profile_id = auth.uid()
  );

CREATE POLICY "scout_reports: scout update own"
  ON scout_reports FOR UPDATE
  USING (
    scout_profile_id = auth.uid()
    OR get_my_role() = 'developer'
  );

-- ── 3b. scout_report_items ───────────────────────────────────
-- Per-attribute notes within a scout report.

CREATE TABLE scout_report_items (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  report_id       UUID          NOT NULL
                  REFERENCES scout_reports(id) ON DELETE CASCADE,
  attribute_code  TEXT          NOT NULL
                  REFERENCES attribute_definitions(code) ON DELETE RESTRICT,
  observed_value  SMALLINT      CHECK (observed_value BETWEEN 1 AND 20),
  scout_note      TEXT          CHECK (char_length(scout_note) <= 300),
  is_strength     BOOLEAN,
  is_weakness     BOOLEAN,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (report_id, attribute_code)
);

CREATE INDEX idx_report_items_report
  ON scout_report_items(report_id);

ALTER TABLE scout_report_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "scout_report_items: inherit from report"
  ON scout_report_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM scout_reports sr
      WHERE sr.id = report_id
        AND (
          sr.is_public = true
          OR sr.scout_profile_id = auth.uid()
          OR get_my_role() IN ('developer','league_admin','league_founder')
        )
    )
  );

CREATE POLICY "scout_report_items: insert via report"
  ON scout_report_items FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM scout_reports sr
      WHERE sr.id = report_id
        AND sr.scout_profile_id = auth.uid()
    )
  );

-- ── 3c. player_similarities ──────────────────────────────────
-- Pre-computed similar player pairs (like FM's "similar player" feature).
-- Populated by nightly AI batch.

CREATE TABLE player_similarities (
  id                  UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id           UUID          NOT NULL
                      REFERENCES players(id) ON DELETE CASCADE,
  similar_player_id   UUID          NOT NULL
                      REFERENCES players(id) ON DELETE CASCADE,
  similarity_score    NUMERIC(5,3)  NOT NULL
                      CHECK (similarity_score BETWEEN 0 AND 1),
  -- What drives the similarity
  similarity_basis    TEXT[]        NOT NULL DEFAULT ARRAY['dna'],
  -- e.g. ARRAY['dna','position','age','style']
  computed_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (player_id, similar_player_id),
  CONSTRAINT chk_not_self CHECK (player_id <> similar_player_id)
);

CREATE INDEX idx_similarities_player
  ON player_similarities(player_id, similarity_score DESC);

ALTER TABLE player_similarities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_similarities: public read"
  ON player_similarities FOR SELECT USING (true);

-- ── 3d. compute_player_similarities() ───────────────────────
-- Computes top-5 similar players for a given player
-- using Euclidean distance on normalised DNA scores.

CREATE OR REPLACE FUNCTION compute_player_similarities(p_player_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tech    SMALLINT; v_phys SMALLINT; v_ment SMALLINT; v_tact SMALLINT;
  v_pos     player_position;
  v_age     INTEGER;
  v_count   INTEGER := 0;
BEGIN
  -- Fetch target player DNA
  SELECT dna_technical, dna_physical, dna_mental, dna_tactical,
         position,
         EXTRACT(YEAR FROM AGE(date_of_birth))::INTEGER
  INTO v_tech, v_phys, v_ment, v_tact, v_pos, v_age
  FROM players WHERE id = p_player_id;

  IF NOT FOUND THEN RETURN 0; END IF;

  -- Delete existing similarities for this player
  DELETE FROM player_similarities WHERE player_id = p_player_id;

  -- Insert top 5 most similar players (same position, within 5 years age)
  INSERT INTO player_similarities (
    player_id, similar_player_id, similarity_score, similarity_basis
  )
  SELECT
    p_player_id,
    p.id,
    -- Similarity: 1 - normalised Euclidean distance across 4 DNA dimensions
    ROUND(1.0 - SQRT(
      POWER(COALESCE(p.dna_technical, 50) - COALESCE(v_tech, 50), 2) +
      POWER(COALESCE(p.dna_physical,  50) - COALESCE(v_phys, 50), 2) +
      POWER(COALESCE(p.dna_mental,    50) - COALESCE(v_ment, 50), 2) +
      POWER(COALESCE(p.dna_tactical,  50) - COALESCE(v_tact, 50), 2)
    ) / 200.0, 3),
    ARRAY['dna','position']
  FROM players p
  WHERE p.id          <> p_player_id
    AND p.is_active    = true
    AND p.is_passport_public = true
    AND p.position     = v_pos
    AND ABS(EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER - v_age) <= 5
    AND (p.dna_overall IS NOT NULL)
  ORDER BY 3 DESC
  LIMIT 5;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION compute_player_similarities(UUID) TO authenticated;

-- ── 3e. generate_ai_scout_report() ──────────────────────────
-- Generates an AI-authored scout report for a player
-- based on their current attributes, stats, and passport data.
-- Returns the new report UUID.

CREATE OR REPLACE FUNCTION generate_ai_scout_report(p_player_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_report_id         UUID;
  v_player            RECORD;
  v_overview          TEXT;
  v_strengths         TEXT;
  v_weaknesses        TEXT;
  v_trend             TEXT;
  v_recommendation    TEXT;
  v_role              TEXT;
  v_style             TEXT;
  v_top_attrs         TEXT[];
  v_low_attrs         TEXT[];
  v_attr              RECORD;
BEGIN
  -- Fetch player summary
  SELECT
    p.full_name,
    COALESCE(p.preferred_name, p.full_name) AS display_name,
    p.position,
    EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
    p.dna_overall,
    p.dna_technical,
    p.dna_physical,
    p.dna_mental,
    p.dna_tactical,
    p.dna_band,
    p.potential_score,
    p.potential_category,
    p.passport_score
  INTO v_player
  FROM players p
  WHERE p.id = p_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player % not found', p_player_id;
  END IF;

  -- Find top 3 highest attributes
  SELECT ARRAY_AGG(attribute_code ORDER BY current_value DESC)
  INTO v_top_attrs
  FROM (
    SELECT attribute_code, current_value
    FROM player_attributes
    WHERE player_id = p_player_id
    ORDER BY current_value DESC
    LIMIT 3
  ) t;

  -- Find bottom 3 lowest attributes
  SELECT ARRAY_AGG(attribute_code ORDER BY current_value ASC)
  INTO v_low_attrs
  FROM (
    SELECT attribute_code, current_value
    FROM player_attributes
    WHERE player_id = p_player_id
    ORDER BY current_value ASC
    LIMIT 3
  ) t;

  -- Determine recommended role from position + top attributes
  v_role := CASE v_player.position
    WHEN 'midfielder' THEN
      CASE
        WHEN 'vision' = ANY(v_top_attrs)    THEN 'Playmaker (CM/CAM)'
        WHEN 'tackling' = ANY(v_top_attrs)  THEN 'Defensive Midfielder'
        WHEN 'work_rate' = ANY(v_top_attrs) THEN 'Box-to-Box Midfielder'
        ELSE 'Central Midfielder'
      END
    WHEN 'forward' THEN
      CASE
        WHEN 'finishing' = ANY(v_top_attrs) THEN 'Striker (Goal Poacher)'
        WHEN 'pace' = ANY(v_top_attrs)      THEN 'Wide Forward'
        ELSE 'Complete Forward'
      END
    WHEN 'defender' THEN
      CASE
        WHEN 'pace' = ANY(v_top_attrs)      THEN 'Attacking Fullback'
        WHEN 'leadership' = ANY(v_top_attrs) THEN 'Ball-Playing Centre Back'
        ELSE 'Centre Back'
      END
    WHEN 'goalkeeper' THEN 'Goalkeeper'
    ELSE 'Unknown'
  END;

  -- Generate overview text
  v_overview := format(
    '%s is a %s-year-old %s with a DNA rating of %s (%s). '
    'Their Football Passport score stands at %s, with particular strength in '
    'the %s category (score: %s/100). '
    'Potential assessment: %s, indicating %s.',
    v_player.display_name,
    v_player.age,
    REPLACE(v_player.position::TEXT, '_', ' '),
    COALESCE(v_player.dna_overall::TEXT, 'unrated'),
    COALESCE(v_player.dna_band, 'unclassified'),
    COALESCE(v_player.passport_score::TEXT, 'unrated'),
    CASE
      WHEN GREATEST(COALESCE(v_player.dna_technical,0),
                    COALESCE(v_player.dna_physical,0),
                    COALESCE(v_player.dna_mental,0),
                    COALESCE(v_player.dna_tactical,0))
           = COALESCE(v_player.dna_mental,0) THEN 'Mental'
      WHEN GREATEST(COALESCE(v_player.dna_technical,0),
                    COALESCE(v_player.dna_physical,0),
                    COALESCE(v_player.dna_mental,0),
                    COALESCE(v_player.dna_tactical,0))
           = COALESCE(v_player.dna_tactical,0) THEN 'Tactical'
      WHEN GREATEST(COALESCE(v_player.dna_technical,0),
                    COALESCE(v_player.dna_physical,0),
                    COALESCE(v_player.dna_mental,0),
                    COALESCE(v_player.dna_tactical,0))
           = COALESCE(v_player.dna_physical,0) THEN 'Physical'
      ELSE 'Technical'
    END,
    GREATEST(
      COALESCE(v_player.dna_technical, 0),
      COALESCE(v_player.dna_physical, 0),
      COALESCE(v_player.dna_mental, 0),
      COALESCE(v_player.dna_tactical, 0)
    ),
    COALESCE(v_player.potential_category, 'unassessed'),
    CASE v_player.potential_category
      WHEN 'elite_prospect'       THEN 'professional or national team pathway'
      WHEN 'national_prospect'    THEN 'top-tier semi-professional potential'
      WHEN 'regional_prospect'    THEN 'state representative potential'
      WHEN 'development_prospect' THEN 'solid competitive amateur ceiling'
      ELSE 'recreational participation level'
    END
  );

  -- Strengths text
  v_strengths := COALESCE(
    (SELECT STRING_AGG(
       format('%s (%s/20)', ad.label, pa.current_value), '; '
       ORDER BY pa.current_value DESC
     )
     FROM player_attributes pa
     JOIN attribute_definitions ad ON ad.code = pa.attribute_code
     WHERE pa.player_id = p_player_id
       AND pa.current_value >= 14
    ), 'No attributes currently rated 14 or above.'
  );

  -- Weaknesses text
  v_weaknesses := COALESCE(
    (SELECT STRING_AGG(
       format('%s (%s/20)', ad.label, pa.current_value), '; '
       ORDER BY pa.current_value ASC
     )
     FROM player_attributes pa
     JOIN attribute_definitions ad ON ad.code = pa.attribute_code
     WHERE pa.player_id = p_player_id
       AND pa.current_value <= 9
    ), 'No significant attribute weaknesses identified.'
  );

  -- Development trend from history
  SELECT CASE
    WHEN AVG(delta) > 0.5  THEN 'improving'
    WHEN AVG(delta) > 0    THEN 'stable'
    WHEN AVG(delta) = 0    THEN 'stable'
    ELSE                        'declining'
  END
  INTO v_trend
  FROM player_attribute_history
  WHERE player_id = p_player_id
    AND recorded_at >= NOW() - INTERVAL '12 months'
    AND delta IS NOT NULL;

  v_trend := COALESCE(v_trend, 'insufficient_data');

  -- Recommendation
  v_recommendation := CASE
    WHEN COALESCE(v_player.dna_overall, 0) >= 80
         AND COALESCE(v_player.potential_score, 0) >= 80 THEN 'sign_immediately'
    WHEN COALESCE(v_player.dna_overall, 0) >= 70
         OR  COALESCE(v_player.potential_score, 0) >= 75 THEN 'sign_if_available'
    WHEN COALESCE(v_player.dna_overall, 0) >= 55
         OR  COALESCE(v_player.potential_score, 0) >= 60 THEN 'monitor'
    WHEN COALESCE(v_player.dna_overall, 0) < 40          THEN 'not_suitable'
    ELSE 'insufficient_data'
  END;

  -- Insert report
  INSERT INTO scout_reports (
    player_id, scout_profile_id, report_source,
    recommended_role, overview, strengths, weaknesses,
    development_trend, recommendation,
    predicted_dna_12m, predicted_dna_36m,
    is_public, watched_matches, created_by
  ) VALUES (
    p_player_id, NULL, 'ai',
    v_role, v_overview, v_strengths, v_weaknesses,
    v_trend, v_recommendation,
    -- 12-month prediction: current + 10% of gap to 100 (improving) or -5% (stable)
    LEAST(100, COALESCE(v_player.dna_overall, 50) +
      CASE v_trend
        WHEN 'rapidly_improving' THEN 8
        WHEN 'improving'         THEN 4
        WHEN 'stable'            THEN 1
        ELSE                          -2
      END),
    LEAST(100, COALESCE(v_player.dna_overall, 50) +
      CASE v_trend
        WHEN 'rapidly_improving' THEN 15
        WHEN 'improving'         THEN 10
        WHEN 'stable'            THEN 3
        ELSE                          -5
      END),
    true,  -- AI reports are public by default
    NULL, NULL
  )
  RETURNING id INTO v_report_id;

  -- Insert per-attribute items
  INSERT INTO scout_report_items (
    report_id, attribute_code, observed_value, is_strength, is_weakness
  )
  SELECT
    v_report_id,
    pa.attribute_code,
    pa.current_value,
    pa.current_value >= 14,
    pa.current_value <= 9
  FROM player_attributes pa
  WHERE pa.player_id = p_player_id
    AND pa.current_value IS NOT NULL;

  RETURN v_report_id;
END;
$$;

GRANT EXECUTE ON FUNCTION generate_ai_scout_report(UUID) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- MODULE 4: FOOTBALL SEARCH ENGINE
-- ════════════════════════════════════════════════════════════

-- ── 4a. Materialized search index ───────────────────────────
-- Denormalised, pre-joined player record for sub-100ms searches.

CREATE MATERIALIZED VIEW mv_player_search_index AS
SELECT
  p.id                                        AS player_id,
  COALESCE(p.preferred_name, p.full_name)     AS display_name,
  p.full_name,
  p.position,
  p.nationality,
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
  p.date_of_birth,
  p.height_cm,
  p.photo_url,
  p.share_url_slug,
  p.is_passport_public,
  p.is_active,
  -- Club context
  c.id                                        AS club_id,
  c.name                                      AS club_name,
  -- League context (current active registration)
  l.id                                        AS league_id,
  l.name                                      AS league_name,
  lqt.scalar                                  AS league_scalar,
  lqt.code                                    AS league_tier,
  -- DNA scores
  p.dna_overall,
  p.dna_band,
  p.dna_technical,
  p.dna_physical,
  p.dna_mental,
  p.dna_tactical,
  p.dna_computed_at,
  -- Potential
  p.potential_score,
  p.potential_category,
  -- Passport
  p.passport_score,
  p.passport_band,
  -- Key individual attributes (for attribute filtering)
  pa_passing.current_value        AS attr_passing,
  pa_dribbling.current_value      AS attr_dribbling,
  pa_finishing.current_value      AS attr_finishing,
  pa_first_touch.current_value    AS attr_first_touch,
  pa_tackling.current_value       AS attr_tackling,
  pa_heading.current_value        AS attr_heading,
  pa_pace.current_value           AS attr_pace,
  pa_stamina.current_value        AS attr_stamina,
  pa_strength.current_value       AS attr_strength,
  pa_agility.current_value        AS attr_agility,
  pa_leadership.current_value     AS attr_leadership,
  pa_composure.current_value      AS attr_composure,
  pa_teamwork.current_value       AS attr_teamwork,
  pa_work_rate.current_value      AS attr_work_rate,
  pa_positioning.current_value    AS attr_positioning,
  pa_vision.current_value         AS attr_vision,
  pa_decision_making.current_value AS attr_decision_making,
  pa_anticipation.current_value   AS attr_anticipation,
  -- Reputation
  rep.score                       AS reputation_score,
  -- Market value
  mv.value_myr                    AS market_value_myr,
  -- Full-text search vector
  TO_TSVECTOR('english',
    COALESCE(p.full_name, '') || ' ' ||
    COALESCE(p.preferred_name, '') || ' ' ||
    COALESCE(c.name, '') || ' ' ||
    COALESCE(l.name, '') || ' ' ||
    COALESCE(p.nationality, '') || ' ' ||
    COALESCE(p.position::TEXT, '')
  )                                           AS search_vector
FROM players p
LEFT JOIN clubs c ON c.id = p.club_id
LEFT JOIN (
  SELECT DISTINCT ON (plr.player_id)
    plr.player_id, s.league_id
  FROM player_league_registrations plr
  JOIN seasons s ON s.id = plr.season_id
  WHERE plr.status = 'approved' AND plr.is_current = true
  ORDER BY plr.player_id, plr.created_at DESC
) cur_reg ON cur_reg.player_id = p.id
LEFT JOIN leagues l ON l.id = cur_reg.league_id
LEFT JOIN league_quality_tiers lqt ON lqt.id = l.quality_tier_id
-- Attribute joins
LEFT JOIN player_attributes pa_passing       ON pa_passing.player_id = p.id
  AND pa_passing.attribute_code = 'passing'
LEFT JOIN player_attributes pa_dribbling     ON pa_dribbling.player_id = p.id
  AND pa_dribbling.attribute_code = 'dribbling'
LEFT JOIN player_attributes pa_finishing     ON pa_finishing.player_id = p.id
  AND pa_finishing.attribute_code = 'finishing'
LEFT JOIN player_attributes pa_first_touch   ON pa_first_touch.player_id = p.id
  AND pa_first_touch.attribute_code = 'first_touch'
LEFT JOIN player_attributes pa_tackling      ON pa_tackling.player_id = p.id
  AND pa_tackling.attribute_code = 'tackling'
LEFT JOIN player_attributes pa_heading       ON pa_heading.player_id = p.id
  AND pa_heading.attribute_code = 'heading'
LEFT JOIN player_attributes pa_pace          ON pa_pace.player_id = p.id
  AND pa_pace.attribute_code = 'pace'
LEFT JOIN player_attributes pa_stamina       ON pa_stamina.player_id = p.id
  AND pa_stamina.attribute_code = 'stamina'
LEFT JOIN player_attributes pa_strength      ON pa_strength.player_id = p.id
  AND pa_strength.attribute_code = 'strength'
LEFT JOIN player_attributes pa_agility       ON pa_agility.player_id = p.id
  AND pa_agility.attribute_code = 'agility'
LEFT JOIN player_attributes pa_leadership    ON pa_leadership.player_id = p.id
  AND pa_leadership.attribute_code = 'leadership'
LEFT JOIN player_attributes pa_composure     ON pa_composure.player_id = p.id
  AND pa_composure.attribute_code = 'composure'
LEFT JOIN player_attributes pa_teamwork      ON pa_teamwork.player_id = p.id
  AND pa_teamwork.attribute_code = 'teamwork'
LEFT JOIN player_attributes pa_work_rate     ON pa_work_rate.player_id = p.id
  AND pa_work_rate.attribute_code = 'work_rate'
LEFT JOIN player_attributes pa_positioning   ON pa_positioning.player_id = p.id
  AND pa_positioning.attribute_code = 'positioning'
LEFT JOIN player_attributes pa_vision        ON pa_vision.player_id = p.id
  AND pa_vision.attribute_code = 'vision'
LEFT JOIN player_attributes pa_decision_making ON pa_decision_making.player_id = p.id
  AND pa_decision_making.attribute_code = 'decision_making'
LEFT JOIN player_attributes pa_anticipation  ON pa_anticipation.player_id = p.id
  AND pa_anticipation.attribute_code = 'anticipation'
-- Reputation join (added below in Module 6)
LEFT JOIN LATERAL (
  SELECT score FROM reputation_scores
  WHERE entity_type = 'player' AND entity_id = p.id AND is_current = true
  LIMIT 1
) rep ON true
-- Market value join (added below in Module 5)
LEFT JOIN LATERAL (
  SELECT value_myr FROM player_market_values
  WHERE player_id = p.id AND is_current = true
  LIMIT 1
) mv ON true
WHERE p.is_active = true
WITH NO DATA;  -- populate after reputation_scores and player_market_values created

CREATE UNIQUE INDEX mv_search_player_id
  ON mv_player_search_index(player_id);

CREATE INDEX mv_search_dna
  ON mv_player_search_index(dna_overall DESC NULLS LAST)
  WHERE is_active = true;

CREATE INDEX mv_search_position
  ON mv_player_search_index(position, dna_overall DESC NULLS LAST);

CREATE INDEX mv_search_age
  ON mv_player_search_index(age, dna_overall DESC NULLS LAST);

CREATE INDEX mv_search_league
  ON mv_player_search_index(league_id, dna_overall DESC NULLS LAST)
  WHERE league_id IS NOT NULL;

CREATE INDEX mv_search_potential
  ON mv_player_search_index(potential_score DESC NULLS LAST)
  WHERE potential_score IS NOT NULL;

CREATE INDEX mv_search_fts
  ON mv_player_search_index USING GIN(search_vector);

-- ── 4b. search_players() function ───────────────────────────
-- Parameterised search across the materialised view.
-- Returns up to 50 results. All parameters are optional.

CREATE OR REPLACE FUNCTION search_players(
  p_query           TEXT     DEFAULT NULL,   -- free text search
  p_position        TEXT     DEFAULT NULL,   -- 'goalkeeper'|'defender'|'midfielder'|'forward'
  p_age_min         INTEGER  DEFAULT NULL,
  p_age_max         INTEGER  DEFAULT NULL,
  p_dna_min         SMALLINT DEFAULT NULL,
  p_dna_max         SMALLINT DEFAULT NULL,
  p_potential_min   SMALLINT DEFAULT NULL,
  p_league_id       UUID     DEFAULT NULL,
  p_club_id         UUID     DEFAULT NULL,
  p_league_tier     TEXT     DEFAULT NULL,   -- 'liga_super'|'liga_premier'|etc.
  p_nationality     TEXT     DEFAULT NULL,
  p_passport_min    SMALLINT DEFAULT NULL,
  -- Attribute filters (minimum value required)
  p_attr_passing    SMALLINT DEFAULT NULL,
  p_attr_pace       SMALLINT DEFAULT NULL,
  p_attr_finishing  SMALLINT DEFAULT NULL,
  p_attr_vision     SMALLINT DEFAULT NULL,
  p_attr_tackling   SMALLINT DEFAULT NULL,
  p_attr_strength   SMALLINT DEFAULT NULL,
  p_attr_composure  SMALLINT DEFAULT NULL,
  p_attr_work_rate  SMALLINT DEFAULT NULL,
  -- Sort
  p_sort_by         TEXT     DEFAULT 'dna_overall',  -- field name
  p_sort_dir        TEXT     DEFAULT 'DESC',
  p_limit           INTEGER  DEFAULT 50,
  p_offset          INTEGER  DEFAULT 0
)
RETURNS TABLE (
  player_id         UUID,
  display_name      TEXT,
  position          player_position,
  age               INTEGER,
  club_name         TEXT,
  league_name       TEXT,
  league_tier       TEXT,
  dna_overall       SMALLINT,
  dna_band          TEXT,
  dna_technical     SMALLINT,
  dna_physical      SMALLINT,
  dna_mental        SMALLINT,
  dna_tactical      SMALLINT,
  potential_score   SMALLINT,
  potential_category TEXT,
  passport_score    SMALLINT,
  reputation_score  SMALLINT,
  market_value_myr  NUMERIC,
  photo_url         TEXT,
  share_url_slug    TEXT,
  total_count       BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total BIGINT;
BEGIN
  -- Get total count for pagination
  SELECT COUNT(*) INTO v_total
  FROM mv_player_search_index si
  WHERE si.is_active = true
    AND si.is_passport_public = true
    AND (p_query      IS NULL OR si.search_vector @@ PLAINTO_TSQUERY('english', p_query))
    AND (p_position   IS NULL OR si.position::TEXT = p_position)
    AND (p_age_min    IS NULL OR si.age >= p_age_min)
    AND (p_age_max    IS NULL OR si.age <= p_age_max)
    AND (p_dna_min    IS NULL OR si.dna_overall >= p_dna_min)
    AND (p_dna_max    IS NULL OR si.dna_overall <= p_dna_max)
    AND (p_potential_min IS NULL OR si.potential_score >= p_potential_min)
    AND (p_league_id  IS NULL OR si.league_id = p_league_id)
    AND (p_club_id    IS NULL OR si.club_id   = p_club_id)
    AND (p_league_tier IS NULL OR si.league_tier = p_league_tier)
    AND (p_nationality IS NULL OR si.nationality ILIKE '%' || p_nationality || '%')
    AND (p_passport_min IS NULL OR si.passport_score >= p_passport_min)
    AND (p_attr_passing   IS NULL OR si.attr_passing   >= p_attr_passing)
    AND (p_attr_pace      IS NULL OR si.attr_pace      >= p_attr_pace)
    AND (p_attr_finishing IS NULL OR si.attr_finishing >= p_attr_finishing)
    AND (p_attr_vision    IS NULL OR si.attr_vision    >= p_attr_vision)
    AND (p_attr_tackling  IS NULL OR si.attr_tackling  >= p_attr_tackling)
    AND (p_attr_strength  IS NULL OR si.attr_strength  >= p_attr_strength)
    AND (p_attr_composure IS NULL OR si.attr_composure >= p_attr_composure)
    AND (p_attr_work_rate IS NULL OR si.attr_work_rate >= p_attr_work_rate);

  RETURN QUERY
  SELECT
    si.player_id,
    si.display_name,
    si.position,
    si.age,
    si.club_name,
    si.league_name,
    si.league_tier,
    si.dna_overall,
    si.dna_band,
    si.dna_technical,
    si.dna_physical,
    si.dna_mental,
    si.dna_tactical,
    si.potential_score,
    si.potential_category,
    si.passport_score,
    si.reputation_score,
    si.market_value_myr,
    si.photo_url,
    si.share_url_slug,
    v_total
  FROM mv_player_search_index si
  WHERE si.is_active = true
    AND si.is_passport_public = true
    AND (p_query      IS NULL OR si.search_vector @@ PLAINTO_TSQUERY('english', p_query))
    AND (p_position   IS NULL OR si.position::TEXT = p_position)
    AND (p_age_min    IS NULL OR si.age >= p_age_min)
    AND (p_age_max    IS NULL OR si.age <= p_age_max)
    AND (p_dna_min    IS NULL OR si.dna_overall >= p_dna_min)
    AND (p_dna_max    IS NULL OR si.dna_overall <= p_dna_max)
    AND (p_potential_min IS NULL OR si.potential_score >= p_potential_min)
    AND (p_league_id  IS NULL OR si.league_id = p_league_id)
    AND (p_club_id    IS NULL OR si.club_id   = p_club_id)
    AND (p_league_tier IS NULL OR si.league_tier = p_league_tier)
    AND (p_nationality IS NULL OR si.nationality ILIKE '%' || p_nationality || '%')
    AND (p_passport_min IS NULL OR si.passport_score >= p_passport_min)
    AND (p_attr_passing   IS NULL OR si.attr_passing   >= p_attr_passing)
    AND (p_attr_pace      IS NULL OR si.attr_pace      >= p_attr_pace)
    AND (p_attr_finishing IS NULL OR si.attr_finishing >= p_attr_finishing)
    AND (p_attr_vision    IS NULL OR si.attr_vision    >= p_attr_vision)
    AND (p_attr_tackling  IS NULL OR si.attr_tackling  >= p_attr_tackling)
    AND (p_attr_strength  IS NULL OR si.attr_strength  >= p_attr_strength)
    AND (p_attr_composure IS NULL OR si.attr_composure >= p_attr_composure)
    AND (p_attr_work_rate IS NULL OR si.attr_work_rate >= p_attr_work_rate)
  ORDER BY
    CASE WHEN p_sort_by = 'dna_overall'     AND p_sort_dir = 'DESC' THEN si.dna_overall     END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'dna_overall'     AND p_sort_dir = 'ASC'  THEN si.dna_overall     END ASC  NULLS LAST,
    CASE WHEN p_sort_by = 'potential_score' AND p_sort_dir = 'DESC' THEN si.potential_score END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'potential_score' AND p_sort_dir = 'ASC'  THEN si.potential_score END ASC  NULLS LAST,
    CASE WHEN p_sort_by = 'passport_score'  AND p_sort_dir = 'DESC' THEN si.passport_score  END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'age'             AND p_sort_dir = 'ASC'  THEN si.age             END ASC  NULLS LAST,
    CASE WHEN p_sort_by = 'age'             AND p_sort_dir = 'DESC' THEN si.age             END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'market_value'    AND p_sort_dir = 'DESC' THEN si.market_value_myr END DESC NULLS LAST,
    si.dna_overall DESC NULLS LAST
  LIMIT LEAST(p_limit, 100)
  OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION search_players(
  TEXT,TEXT,INTEGER,INTEGER,SMALLINT,SMALLINT,SMALLINT,
  UUID,UUID,TEXT,TEXT,SMALLINT,
  SMALLINT,SMALLINT,SMALLINT,SMALLINT,SMALLINT,SMALLINT,SMALLINT,SMALLINT,
  TEXT,TEXT,INTEGER,INTEGER
) TO authenticated, anon;

-- ════════════════════════════════════════════════════════════
-- MODULE 5: TRANSFER MARKET ENGINE
-- ════════════════════════════════════════════════════════════

-- ── 5a. player_market_values ─────────────────────────────────

CREATE TABLE player_market_values (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id       UUID          NOT NULL
                  REFERENCES players(id) ON DELETE CASCADE,
  value_myr       NUMERIC(14,2) NOT NULL CHECK (value_myr >= 0),
  -- Component inputs (for transparency)
  base_score      NUMERIC(6,2),   -- 0-100, pre-multiplier
  age_multiplier  NUMERIC(4,3),   -- e.g. 1.20 for peak age
  league_multiplier NUMERIC(4,3), -- league tier scalar
  potential_premium NUMERIC(4,3), -- extra for high-potential young players
  -- Valuation method
  method          TEXT          NOT NULL DEFAULT 'computed'
                  CHECK (method IN ('computed','manual','transfer_fee')),
  -- For transfer_fee method: the actual fee paid
  source_transfer_id UUID
                  REFERENCES player_transfers(id) ON DELETE SET NULL,
  is_current      BOOLEAN       NOT NULL DEFAULT true,
  computed_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by      UUID          REFERENCES profiles(id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX idx_market_value_current
  ON player_market_values(player_id) WHERE is_current = true;

CREATE INDEX idx_market_value_player
  ON player_market_values(player_id, computed_at DESC);

CREATE INDEX idx_market_value_top
  ON player_market_values(value_myr DESC) WHERE is_current = true;

ALTER TABLE player_market_values ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_market_values: public read"
  ON player_market_values FOR SELECT USING (true);

CREATE POLICY "player_market_values: system write"
  ON player_market_values FOR INSERT
  WITH CHECK (get_my_role() IN ('developer','league_admin','league_founder'));

-- ── 5b. market_value_history ─────────────────────────────────

CREATE TABLE market_value_history (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id       UUID          NOT NULL
                  REFERENCES players(id) ON DELETE CASCADE,
  value_myr       NUMERIC(14,2) NOT NULL,
  recorded_date   DATE          NOT NULL DEFAULT CURRENT_DATE,
  method          TEXT          NOT NULL DEFAULT 'computed',
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (player_id, recorded_date)
);

CREATE INDEX idx_mvhist_player_date
  ON market_value_history(player_id, recorded_date DESC);

ALTER TABLE market_value_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "market_value_history: public read"
  ON market_value_history FOR SELECT USING (true);

-- ── 5c. compute_player_market_value() ───────────────────────
-- Market value formula:
--   Base = DNA_overall * 500 MYR (scale: 0=0, 100=50,000 MYR)
--   × Age multiplier (peak 22-26 = 1.30)
--   × League multiplier (Liga Super = 1.50)
--   × Potential premium (elite prospect under 21 = +40%)
-- Result is a grassroots-realistic Malaysian market value.

CREATE OR REPLACE FUNCTION compute_player_market_value(p_player_id UUID)
RETURNS NUMERIC(14,2)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dna_overall     SMALLINT;
  v_passport_score  SMALLINT;
  v_potential       SMALLINT;
  v_pot_cat         TEXT;
  v_age             INTEGER;
  v_league_scalar   NUMERIC;
  v_base            NUMERIC;
  v_age_mult        NUMERIC;
  v_league_mult     NUMERIC;
  v_pot_premium     NUMERIC;
  v_final_value     NUMERIC;
  v_prev_current    UUID;
BEGIN
  SELECT
    p.dna_overall,
    p.passport_score,
    p.potential_score,
    p.potential_category,
    EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER,
    COALESCE(lqt.scalar, 0.65)
  INTO
    v_dna_overall, v_passport_score, v_potential, v_pot_cat,
    v_age, v_league_scalar
  FROM players p
  LEFT JOIN (
    SELECT DISTINCT ON (plr.player_id) plr.player_id, lqt2.scalar
    FROM player_league_registrations plr
    JOIN seasons s ON s.id = plr.season_id
    JOIN leagues l ON l.id = s.league_id
    JOIN league_quality_tiers lqt2 ON lqt2.id = l.quality_tier_id
    WHERE plr.status = 'approved' AND plr.is_current = true
    ORDER BY plr.player_id, plr.created_at DESC
  ) cur_league ON cur_league.player_id = p.id
  LEFT JOIN league_quality_tiers lqt ON lqt.scalar = cur_league.scalar
  WHERE p.id = p_player_id;

  IF NOT FOUND THEN RETURN 0; END IF;

  -- Base value: DNA * 500 MYR
  v_base := COALESCE(v_dna_overall, 0) * 500.0;

  -- Age multiplier (peak at 22-26)
  v_age_mult := CASE
    WHEN v_age < 16 THEN 0.40
    WHEN v_age < 18 THEN 0.60
    WHEN v_age < 20 THEN 0.85
    WHEN v_age < 22 THEN 1.10
    WHEN v_age < 24 THEN 1.30
    WHEN v_age < 26 THEN 1.30
    WHEN v_age < 28 THEN 1.20
    WHEN v_age < 30 THEN 1.00
    WHEN v_age < 32 THEN 0.80
    WHEN v_age < 35 THEN 0.55
    ELSE                 0.35
  END;

  -- League multiplier (Liga Super players are worth more than amateur)
  v_league_mult := CASE COALESCE(v_league_scalar, 0.65)
    WHEN 1.00 THEN 1.80
    WHEN 0.90 THEN 1.40
    WHEN 0.80 THEN 1.10
    WHEN 0.72 THEN 0.90
    WHEN 0.65 THEN 0.75
    WHEN 0.60 THEN 0.60
    ELSE            0.60
  END;

  -- Potential premium (young players with high potential are worth more)
  v_pot_premium := CASE
    WHEN v_age <= 21 AND v_pot_cat = 'elite_prospect'       THEN 1.40
    WHEN v_age <= 21 AND v_pot_cat = 'national_prospect'    THEN 1.25
    WHEN v_age <= 23 AND v_pot_cat IN ('elite_prospect','national_prospect') THEN 1.15
    WHEN v_age <= 25 AND v_pot_cat = 'elite_prospect'       THEN 1.10
    ELSE 1.00
  END;

  v_final_value := ROUND(v_base * v_age_mult * v_league_mult * v_pot_premium, 2);

  -- Archive previous current value
  UPDATE player_market_values SET is_current = false
  WHERE player_id = p_player_id AND is_current = true;

  -- Insert new current value
  INSERT INTO player_market_values (
    player_id, value_myr, base_score, age_multiplier,
    league_multiplier, potential_premium, method, is_current
  ) VALUES (
    p_player_id, v_final_value,
    v_dna_overall, v_age_mult, v_league_mult, v_pot_premium,
    'computed', true
  );

  -- Insert history record
  INSERT INTO market_value_history (player_id, value_myr, method)
  VALUES (p_player_id, v_final_value, 'computed')
  ON CONFLICT (player_id, recorded_date)
  DO UPDATE SET value_myr = EXCLUDED.value_myr, method = EXCLUDED.method;

  -- Update denormalised column on players
  UPDATE players SET
    updated_at = NOW()
  WHERE id = p_player_id;

  RETURN v_final_value;
END;
$$;

GRANT EXECUTE ON FUNCTION compute_player_market_value(UUID) TO authenticated;

-- ── 5d. Extend player_transfers with intelligence columns ────

ALTER TABLE player_transfers
  ADD COLUMN IF NOT EXISTS market_value_at_transfer NUMERIC(14,2),
  ADD COLUMN IF NOT EXISTS value_trend TEXT
    CHECK (value_trend IN ('rising','stable','falling',NULL));

-- ════════════════════════════════════════════════════════════
-- MODULE 6: REPUTATION ENGINE
-- ════════════════════════════════════════════════════════════

-- ── 6a. reputation_scores ────────────────────────────────────

CREATE TABLE reputation_scores (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  entity_type     TEXT          NOT NULL
                  CHECK (entity_type IN ('player','coach','club','league')),
  entity_id       UUID          NOT NULL,
  score           SMALLINT      NOT NULL CHECK (score BETWEEN 1 AND 100),
  -- Component breakdown
  performance_score   SMALLINT  CHECK (performance_score BETWEEN 1 AND 100),
  consistency_score   SMALLINT  CHECK (consistency_score BETWEEN 1 AND 100),
  longevity_score     SMALLINT  CHECK (longevity_score BETWEEN 1 AND 100),
  social_score        SMALLINT  CHECK (social_score BETWEEN 1 AND 100),
  -- Reputation band
  band            TEXT          NOT NULL
                  CHECK (band IN (
                    'legendary','elite','prominent','known',
                    'emerging','unknown'
                  )),
  is_current      BOOLEAN       NOT NULL DEFAULT true,
  computed_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_reputation_current
  ON reputation_scores(entity_type, entity_id) WHERE is_current = true;

CREATE INDEX idx_reputation_type_score
  ON reputation_scores(entity_type, score DESC) WHERE is_current = true;

ALTER TABLE reputation_scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "reputation_scores: public read"
  ON reputation_scores FOR SELECT USING (true);

CREATE POLICY "reputation_scores: system write"
  ON reputation_scores FOR INSERT
  WITH CHECK (get_my_role() IN ('developer','league_admin','league_founder'));

-- ── 6b. reputation_history ───────────────────────────────────

CREATE TABLE reputation_history (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  entity_type     TEXT          NOT NULL,
  entity_id       UUID          NOT NULL,
  score           SMALLINT      NOT NULL,
  recorded_date   DATE          NOT NULL DEFAULT CURRENT_DATE,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (entity_type, entity_id, recorded_date)
);

CREATE INDEX idx_rephist_entity_date
  ON reputation_history(entity_type, entity_id, recorded_date DESC);

ALTER TABLE reputation_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "reputation_history: public read"
  ON reputation_history FOR SELECT USING (true);

-- ── 6c. compute_player_reputation() ─────────────────────────

CREATE OR REPLACE FUNCTION compute_player_reputation(p_player_id UUID)
RETURNS SMALLINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_perf      SMALLINT;
  v_consist   SMALLINT;
  v_longevity SMALLINT;
  v_social    SMALLINT;
  v_score     SMALLINT;
  v_band      TEXT;
  v_apps      INTEGER;
  v_goals     INTEGER;
  v_assists   INTEGER;
  v_followers INTEGER;
  v_dna       SMALLINT;
  v_passport  SMALLINT;
  v_seasons   INTEGER;
BEGIN
  -- Performance: based on passport score + DNA
  SELECT
    COALESCE(p.passport_score, 0),
    COALESCE(p.dna_overall, 0),
    COALESCE(p.follower_count, 0)
  INTO v_passport, v_dna, v_followers
  FROM players p WHERE p.id = p_player_id;

  -- Career stats
  SELECT
    COALESCE(SUM(pms.goals), 0),
    COALESCE(SUM(pms.assists), 0),
    COUNT(DISTINCT pms.fixture_id)
  INTO v_goals, v_assists, v_apps
  FROM player_match_stats pms
  WHERE pms.player_id = p_player_id;

  -- Seasons active
  SELECT COUNT(DISTINCT plr.season_id) INTO v_seasons
  FROM player_league_registrations plr
  WHERE plr.player_id = p_player_id AND plr.status = 'approved';

  -- Performance score (40%)
  v_perf := LEAST(100, GREATEST(0,
    COALESCE(v_passport, 0) * 0.60
    + COALESCE(v_dna, 0) * 0.40
  ))::SMALLINT;

  -- Consistency score (30%): based on appearances
  v_consist := LEAST(100, GREATEST(0, ROUND(
    CASE
      WHEN v_apps >= 100 THEN 95
      WHEN v_apps >= 50  THEN 80
      WHEN v_apps >= 25  THEN 65
      WHEN v_apps >= 10  THEN 50
      WHEN v_apps >= 5   THEN 35
      ELSE                    20
    END
    + (v_goals + v_assists) * 0.3
  )))::SMALLINT;

  -- Longevity score (20%): seasons active
  v_longevity := LEAST(100, GREATEST(0,
    CASE
      WHEN v_seasons >= 5 THEN 90
      WHEN v_seasons >= 3 THEN 70
      WHEN v_seasons >= 2 THEN 50
      WHEN v_seasons >= 1 THEN 30
      ELSE                     10
    END
  ))::SMALLINT;

  -- Social score (10%): followers
  v_social := LEAST(100, GREATEST(0,
    CASE
      WHEN v_followers >= 1000 THEN 90
      WHEN v_followers >= 500  THEN 70
      WHEN v_followers >= 100  THEN 50
      WHEN v_followers >= 10   THEN 30
      ELSE                          10
    END
  ))::SMALLINT;

  -- Final weighted score
  v_score := ROUND(
    v_perf * 0.40 + v_consist * 0.30 + v_longevity * 0.20 + v_social * 0.10
  )::SMALLINT;

  -- Band
  v_band := CASE
    WHEN v_score >= 90 THEN 'legendary'
    WHEN v_score >= 75 THEN 'elite'
    WHEN v_score >= 60 THEN 'prominent'
    WHEN v_score >= 45 THEN 'known'
    WHEN v_score >= 25 THEN 'emerging'
    ELSE                    'unknown'
  END;

  -- Archive existing
  UPDATE reputation_scores SET is_current = false
  WHERE entity_type = 'player' AND entity_id = p_player_id AND is_current = true;

  -- Insert new
  INSERT INTO reputation_scores (
    entity_type, entity_id, score,
    performance_score, consistency_score, longevity_score, social_score,
    band, is_current
  ) VALUES (
    'player', p_player_id, v_score,
    v_perf, v_consist, v_longevity, v_social,
    v_band, true
  );

  -- History
  INSERT INTO reputation_history (entity_type, entity_id, score)
  VALUES ('player', p_player_id, v_score)
  ON CONFLICT (entity_type, entity_id, recorded_date)
  DO UPDATE SET score = EXCLUDED.score;

  RETURN v_score;
END;
$$;

-- ── 6d. compute_club_reputation() ───────────────────────────

CREATE OR REPLACE FUNCTION compute_club_reputation(p_club_id UUID)
RETURNS SMALLINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_score     SMALLINT;
  v_band      TEXT;
  v_avg_dna   NUMERIC;
  v_players   INTEGER;
  v_followers INTEGER;
  v_seasons   INTEGER;
BEGIN
  SELECT
    COALESCE(AVG(p.dna_overall), 0),
    COUNT(p.id),
    COALESCE(MAX(c.follower_count), 0)
  INTO v_avg_dna, v_players, v_followers
  FROM players p
  JOIN clubs c ON c.id = p.club_id
  WHERE p.club_id = p_club_id AND p.is_active = true;

  SELECT COUNT(DISTINCT plr.season_id) INTO v_seasons
  FROM player_league_registrations plr
  JOIN players p2 ON p2.id = plr.player_id
  WHERE p2.club_id = p_club_id AND plr.status = 'approved';

  v_score := LEAST(100, GREATEST(1, ROUND(
    v_avg_dna * 0.50
    + LEAST(v_players, 30) / 30.0 * 20
    + LEAST(v_seasons, 5)  / 5.0  * 15
    + LEAST(v_followers, 1000) / 1000.0 * 15
  )))::SMALLINT;

  v_band := CASE
    WHEN v_score >= 90 THEN 'legendary'
    WHEN v_score >= 75 THEN 'elite'
    WHEN v_score >= 60 THEN 'prominent'
    WHEN v_score >= 45 THEN 'known'
    WHEN v_score >= 25 THEN 'emerging'
    ELSE                    'unknown'
  END;

  UPDATE reputation_scores SET is_current = false
  WHERE entity_type = 'club' AND entity_id = p_club_id AND is_current = true;

  INSERT INTO reputation_scores (
    entity_type, entity_id, score, band, is_current
  ) VALUES ('club', p_club_id, v_score, v_band, true);

  INSERT INTO reputation_history (entity_type, entity_id, score)
  VALUES ('club', p_club_id, v_score)
  ON CONFLICT (entity_type, entity_id, recorded_date)
  DO UPDATE SET score = EXCLUDED.score;

  RETURN v_score;
END;
$$;

-- ── 6e. compute_league_reputation() ─────────────────────────

CREATE OR REPLACE FUNCTION compute_league_reputation(p_league_id UUID)
RETURNS SMALLINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_score     SMALLINT;
  v_band      TEXT;
  v_clubs     INTEGER;
  v_scalar    NUMERIC;
  v_followers INTEGER;
  v_seasons   INTEGER;
BEGIN
  SELECT
    COUNT(DISTINCT lc.club_id),
    COALESCE(lqt.scalar, 0.65),
    COALESCE(l.follower_count, 0)
  INTO v_clubs, v_scalar, v_followers
  FROM leagues l
  LEFT JOIN league_clubs lc ON lc.league_id = l.id AND lc.approved = true
  LEFT JOIN league_quality_tiers lqt ON lqt.id = l.quality_tier_id
  WHERE l.id = p_league_id
  GROUP BY lqt.scalar, l.follower_count;

  SELECT COUNT(DISTINCT s.id) INTO v_seasons
  FROM seasons s WHERE s.league_id = p_league_id;

  v_score := LEAST(100, GREATEST(1, ROUND(
    v_scalar * 50                              -- tier is primary driver
    + LEAST(v_clubs, 16) / 16.0 * 25          -- more clubs = more prominent
    + LEAST(v_seasons, 5) / 5.0 * 15          -- longevity
    + LEAST(v_followers, 500) / 500.0 * 10    -- community size
  )))::SMALLINT;

  v_band := CASE
    WHEN v_score >= 90 THEN 'legendary'
    WHEN v_score >= 75 THEN 'elite'
    WHEN v_score >= 60 THEN 'prominent'
    WHEN v_score >= 45 THEN 'known'
    WHEN v_score >= 25 THEN 'emerging'
    ELSE                    'unknown'
  END;

  UPDATE reputation_scores SET is_current = false
  WHERE entity_type = 'league' AND entity_id = p_league_id AND is_current = true;

  INSERT INTO reputation_scores (
    entity_type, entity_id, score, band, is_current
  ) VALUES ('league', p_league_id, v_score, v_band, true);

  INSERT INTO reputation_history (entity_type, entity_id, score)
  VALUES ('league', p_league_id, v_score)
  ON CONFLICT (entity_type, entity_id, recorded_date)
  DO UPDATE SET score = EXCLUDED.score;

  RETURN v_score;
END;
$$;

GRANT EXECUTE ON FUNCTION compute_player_reputation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION compute_club_reputation(UUID)  TO authenticated;
GRANT EXECUTE ON FUNCTION compute_league_reputation(UUID) TO authenticated;

-- ── 6f. Add reputation columns to players/clubs/leagues ──────

ALTER TABLE players
  ADD COLUMN IF NOT EXISTS reputation_score SMALLINT
    CHECK (reputation_score IS NULL OR reputation_score BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS reputation_band  TEXT,
  ADD COLUMN IF NOT EXISTS market_value_myr NUMERIC(14,2);

ALTER TABLE clubs
  ADD COLUMN IF NOT EXISTS reputation_score SMALLINT
    CHECK (reputation_score IS NULL OR reputation_score BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS reputation_band  TEXT;

ALTER TABLE leagues
  ADD COLUMN IF NOT EXISTS reputation_score SMALLINT
    CHECK (reputation_score IS NULL OR reputation_score BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS reputation_band  TEXT;

-- ════════════════════════════════════════════════════════════
-- MODULE 7: MASTER INTELLIGENCE REFRESH
-- Single function to run the full intelligence pipeline
-- for one player. Called by nightly cron per active player.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION run_player_intelligence(p_player_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dna_result    RECORD;
  v_passport      SMALLINT;
  v_market_value  NUMERIC;
  v_reputation    SMALLINT;
  v_similarities  INTEGER;
  v_scout_report  UUID;
BEGIN
  -- 1. Recompute DNA
  SELECT * INTO v_dna_result FROM calculate_player_dna(p_player_id);

  -- 2. Recompute Passport Score
  v_passport := compute_player_passport_score(p_player_id);

  -- 3. Recompute Market Value
  v_market_value := compute_player_market_value(p_player_id);

  -- 4. Recompute Reputation
  v_reputation := compute_player_reputation(p_player_id);

  -- 5. Update denormalised reputation + market value on players
  UPDATE players SET
    reputation_score = v_reputation,
    reputation_band  = (SELECT band FROM reputation_scores
                        WHERE entity_type = 'player' AND entity_id = p_player_id
                          AND is_current = true LIMIT 1),
    market_value_myr = v_market_value,
    updated_at       = NOW()
  WHERE id = p_player_id;

  -- 6. Recompute similar players
  v_similarities := compute_player_similarities(p_player_id);

  -- 7. Generate AI scout report if none exists for current period
  IF NOT EXISTS (
    SELECT 1 FROM scout_reports
    WHERE player_id = p_player_id
      AND report_source = 'ai'
      AND created_at >= NOW() - INTERVAL '30 days'
  ) THEN
    v_scout_report := generate_ai_scout_report(p_player_id);
  END IF;

  RETURN JSONB_BUILD_OBJECT(
    'player_id',     p_player_id,
    'dna_overall',   v_dna_result.overall_dna,
    'passport_score', v_passport,
    'market_value',  v_market_value,
    'reputation',    v_reputation,
    'similarities',  v_similarities,
    'scout_report',  v_scout_report,
    'run_at',        NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION run_player_intelligence(UUID) TO authenticated;

-- ── Nightly batch: all active players ───────────────────────

CREATE OR REPLACE FUNCTION run_intelligence_batch()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id UUID;
  v_count     INTEGER := 0;
BEGIN
  FOR v_player_id IN
    SELECT id FROM players WHERE is_active = true
    ORDER BY passport_computed_at ASC NULLS FIRST  -- process stale players first
    LIMIT 500  -- process up to 500 per batch run
  LOOP
    BEGIN
      PERFORM run_player_intelligence(v_player_id);
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      -- Log error but continue batch
      RAISE WARNING 'Intelligence batch failed for player %: %', v_player_id, SQLERRM;
    END;
  END LOOP;

  -- Refresh all materialized views
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_player_passport_scores;
  -- mv_player_search_index needs non-concurrent refresh if first time
  -- (handled separately; use CONCURRENTLY once data exists)

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION run_intelligence_batch() TO authenticated;

-- ════════════════════════════════════════════════════════════
-- MODULE 8: PUBLIC VIEWS FOR INTELLIGENCE DATA
-- ════════════════════════════════════════════════════════════

-- ── Scout report public view (redacts scout identity) ────────

CREATE OR REPLACE VIEW v_scout_reports_public
WITH (security_invoker = true)
AS
SELECT
  sr.id,
  sr.player_id,
  COALESCE(p.preferred_name, p.full_name) AS player_name,
  p.position,
  sr.report_source,
  sr.recommended_role,
  sr.playing_style,
  sr.overview,
  sr.strengths,
  sr.weaknesses,
  sr.development_trend,
  sr.recommendation,
  sr.predicted_dna_12m,
  sr.predicted_dna_36m,
  sr.watched_matches,
  -- Redact scout identity on public view
  CASE WHEN sr.is_public THEN 'PlayPro Scout Network'
       ELSE 'Private'
  END AS scout_name,
  sr.created_at,
  sr.season_id
FROM scout_reports sr
JOIN players p ON p.id = sr.player_id
WHERE sr.is_public = true;

-- ── Market value public view ─────────────────────────────────

CREATE OR REPLACE VIEW v_player_market_values_public
WITH (security_invoker = true)
AS
SELECT
  mv.player_id,
  COALESCE(p.preferred_name, p.full_name) AS player_name,
  p.position,
  p.share_url_slug,
  c.name AS club_name,
  mv.value_myr,
  mv.computed_at,
  p.reputation_score,
  p.reputation_band,
  p.dna_overall,
  p.potential_score,
  p.potential_category
FROM player_market_values mv
JOIN players p ON p.id = mv.player_id
LEFT JOIN clubs c ON c.id = p.club_id
WHERE mv.is_current = true
  AND p.is_active = true
  AND p.is_passport_public = true;

-- ── Reputation leaderboard view ──────────────────────────────

CREATE OR REPLACE VIEW v_reputation_leaderboard
WITH (security_invoker = true)
AS
SELECT
  rs.entity_type,
  rs.entity_id,
  rs.score,
  rs.band,
  rs.computed_at,
  CASE rs.entity_type
    WHEN 'player' THEN (SELECT COALESCE(preferred_name, full_name) FROM players WHERE id = rs.entity_id)
    WHEN 'club'   THEN (SELECT name FROM clubs  WHERE id = rs.entity_id)
    WHEN 'league' THEN (SELECT name FROM leagues WHERE id = rs.entity_id)
    ELSE NULL
  END AS entity_name,
  CASE rs.entity_type
    WHEN 'player' THEN (SELECT photo_url FROM players WHERE id = rs.entity_id)
    WHEN 'club'   THEN (SELECT logo_url  FROM clubs   WHERE id = rs.entity_id)
    ELSE NULL
  END AS entity_image
FROM reputation_scores rs
WHERE rs.is_current = true
ORDER BY rs.score DESC;

-- ════════════════════════════════════════════════════════════
-- DEFERRED: Populate mv_player_search_index
-- (reputation_scores and player_market_values now exist)
-- ════════════════════════════════════════════════════════════

REFRESH MATERIALIZED VIEW mv_player_search_index;

-- ════════════════════════════════════════════════════════════
-- GRANT EXECUTE on all new functions
-- ════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION compute_match_rating(
  INTEGER,INTEGER,INTEGER,INTEGER,NUMERIC,NUMERIC,NUMERIC,
  INTEGER,INTEGER,INTEGER,INTEGER,INTEGER,INTEGER,
  INTEGER,INTEGER,INTEGER,INTEGER
) TO authenticated;

GRANT EXECUTE ON FUNCTION apply_attribute_decay(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION run_intelligence_batch()        TO authenticated;

-- ════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (run manually after migration)
-- ════════════════════════════════════════════════════════════

-- 1. Confirm new event types in enum:
-- SELECT enumlabel FROM pg_enum
-- WHERE enumtypid = 'match_event_type'::regtype
-- ORDER BY enumsortorder;

-- 2. Confirm player_match_stats new columns:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'player_match_stats'
-- AND column_name IN ('passes_attempted','tackles_won','match_rating','is_motm');

-- 3. Confirm AI weight seed (should be 40 rows):
-- SELECT COUNT(*) FROM attribute_ai_weights;

-- 4. Confirm scout_reports table:
-- SELECT tablename FROM pg_tables WHERE schemaname = 'public'
-- AND tablename IN ('scout_reports','scout_report_items','player_similarities',
--   'player_market_values','market_value_history','reputation_scores','reputation_history',
--   'match_event_details','attribute_ai_weights');

-- 5. Confirm search function:
-- SELECT * FROM search_players(p_position := 'midfielder', p_dna_min := 70);

-- 6. Confirm materialised view populated:
-- SELECT COUNT(*) FROM mv_player_search_index;

COMMIT;

-- ============================================================
-- PHASE 6.6 SUMMARY
-- ============================================================
-- Part A (outside tx): 23 new match_event_type enum values
-- Part B (transaction):
--   Tables created:       8 new tables
--   Columns added:       25 new columns across 3 tables
--   Functions created:   14 SECURITY DEFINER functions
--   Views created:        3 public views
--   Matviews created:     1 (mv_player_search_index)
--   Matviews refreshed:   1 (sprint1 + passport scores)
--   Indexes created:     20+
--   Policies created:    14
--   AI weights seeded:   40 rows
-- ============================================================
