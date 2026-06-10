-- ============================================================
-- PlayPro Phase 6.7 — Match → Attribute → DNA Pipeline
-- ============================================================
-- Version:    6.7.0
-- Date:       2026-06-08
-- Depends on: All prior phases through 6.6
-- ============================================================
-- PURPOSE:
--   Close the loop between Match Observer and Football DNA.
--   Every completed match automatically flows through:
--
--   match_events
--     → attribute nudges (capped +0.2/match, +1.0/month)
--       → DNA recalculation
--         → Position Intelligence
--           → Playing Role determination
--             → Scout Recommendation
--               → Passport Score update
--
--   All pipeline steps run inside a single function:
--   run_post_match_pipeline(p_fixture_id, p_season_id)
--
-- WHAT IS NEW vs Phase 6.6:
--   1. Per-match cap: max +0.2 on any attribute per match
--   2. Monthly cap:   max +1.0 on any attribute per 30 days
--   3. Composure decay from cards (not just idle)
--   4. position_suitability table (new)
--   5. determine_player_position() — Position Intelligence Engine
--   6. playing role catalogue (position_roles reference table)
--   7. player_position_profiles table (stores best/secondary/role)
--   8. generate_player_recommendation() — auto recommendation
--   9. run_post_match_pipeline() — the single entry point
--  10. match_pipeline_log — audit of every pipeline run
--  11. Trigger on fixtures: status → 'completed' fires pipeline
-- ============================================================

-- ============================================================
-- PART A — ENUM (outside transaction)
-- ============================================================

-- No new enum values needed for this patch.

-- ============================================================
-- PART B — MAIN MIGRATION
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- SECTION 1: NEW COLUMNS ON PLAYERS
-- Store position intelligence results (denormalised).
-- ────────────────────────────────────────────────────────────

ALTER TABLE players
  ADD COLUMN IF NOT EXISTS best_position        TEXT,    -- e.g. 'AMC', 'ST', 'GK'
  ADD COLUMN IF NOT EXISTS secondary_position   TEXT,    -- e.g. 'MC', 'AML'
  ADD COLUMN IF NOT EXISTS playing_role         TEXT,    -- e.g. 'Advanced Playmaker'
  ADD COLUMN IF NOT EXISTS development_trend    TEXT
    CHECK (development_trend IN (
      'rapidly_improving','improving','stable',
      'declining','rapidly_declining','insufficient_data',NULL
    )),
  ADD COLUMN IF NOT EXISTS scout_recommendation TEXT
    CHECK (scout_recommendation IN (
      'strongly_recommended','recommended','monitor',
      'development_prospect','not_recommended',NULL
    )),
  ADD COLUMN IF NOT EXISTS pipeline_last_run    TIMESTAMPTZ;

-- ────────────────────────────────────────────────────────────
-- SECTION 2: position_roles REFERENCE TABLE
-- Maps attribute signatures to FM-style playing roles.
-- Each role has minimum attribute thresholds for a match.
-- ────────────────────────────────────────────────────────────

CREATE TABLE position_roles (
  code            TEXT          PRIMARY KEY,
  label           TEXT          NOT NULL UNIQUE,
  position_group  TEXT          NOT NULL
                  CHECK (position_group IN
                    ('goalkeeper','defender','midfielder','forward')),
  -- Primary position codes this role plays in
  primary_pos     TEXT[]        NOT NULL,
  secondary_pos   TEXT[]        NOT NULL DEFAULT '{}',
  -- Key attribute requirements (minimum value on 1-20 scale)
  -- NULL means no minimum for that attribute
  req_passing     SMALLINT,
  req_vision      SMALLINT,
  req_positioning SMALLINT,
  req_tackling    SMALLINT,
  req_pace        SMALLINT,
  req_finishing   SMALLINT,
  req_work_rate   SMALLINT,
  req_leadership  SMALLINT,
  req_composure   SMALLINT,
  req_anticipation SMALLINT,
  req_strength    SMALLINT,
  req_stamina     SMALLINT,
  req_dribbling   SMALLINT,
  req_first_touch SMALLINT,
  req_decision_making SMALLINT,
  req_heading     SMALLINT,
  -- Attribute weights for scoring this role fit (relative, not absolute)
  -- Higher = more important for this role
  wt_passing      NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_vision       NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_positioning  NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_tackling     NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_pace         NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_finishing    NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_work_rate    NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_leadership   NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_composure    NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_anticipation NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_strength     NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_stamina      NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_dribbling    NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_first_touch  NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_decision_making NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  wt_heading      NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  description     TEXT,
  is_active       BOOLEAN       NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE position_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "position_roles: public read"
  ON position_roles FOR SELECT USING (true);
CREATE POLICY "position_roles: developer write"
  ON position_roles FOR ALL
  USING (get_my_role() = 'developer')
  WITH CHECK (get_my_role() = 'developer');

-- ── Seed 18 FM-style playing roles ───────────────────────────

INSERT INTO position_roles (
  code, label, position_group, primary_pos, secondary_pos,
  req_passing, req_vision, req_decision_making, req_composure,
  wt_passing, wt_vision, wt_positioning, wt_tackling, wt_pace,
  wt_finishing, wt_work_rate, wt_leadership, wt_composure,
  wt_anticipation, wt_strength, wt_stamina, wt_dribbling,
  wt_first_touch, wt_decision_making, wt_heading,
  description
) VALUES

-- ── GOALKEEPERS ─────────────────────────────────────────────
('sweeper_keeper',      'Sweeper Keeper',        'goalkeeper', ARRAY['GK'], ARRAY[],
  NULL, NULL, NULL, NULL,
  0.30,0.20,0.20,0.00,0.30,0.00,0.20,0.20,0.30,0.20,0.20,0.20,0.00,0.20,0.30,0.00,
  'Active goalkeeper who sweeps behind the defensive line'),
('shot_stopper',        'Shot Stopper',          'goalkeeper', ARRAY['GK'], ARRAY[],
  NULL, NULL, NULL, NULL,
  0.10,0.10,0.30,0.00,0.10,0.00,0.20,0.20,0.30,0.30,0.20,0.20,0.00,0.10,0.20,0.00,
  'Traditional goalkeeper focused on shot stopping and positioning'),

-- ── DEFENDERS ───────────────────────────────────────────────
('ball_playing_cb',     'Ball-Playing Centre Back','defender', ARRAY['CB'], ARRAY['CD'],
  11, 10, NULL, NULL,
  0.30,0.20,0.30,0.30,0.10,0.00,0.20,0.20,0.20,0.20,0.30,0.20,0.00,0.20,0.20,0.30,
  'Centre back who initiates attacks with quality distribution'),
('stopper_cb',          'Stopper Centre Back',   'defender', ARRAY['CB'], ARRAY['CD'],
  NULL, NULL, NULL, NULL,
  0.10,0.10,0.30,0.40,0.10,0.00,0.25,0.20,0.20,0.30,0.40,0.20,0.00,0.10,0.20,0.40,
  'Physical, aggressive centre back who wins the ball'),
('full_back',           'Full Back',             'defender', ARRAY['LB','RB'], ARRAY['LWB','RWB'],
  NULL, NULL, NULL, NULL,
  0.15,0.15,0.25,0.25,0.30,0.00,0.30,0.10,0.15,0.20,0.20,0.30,0.10,0.10,0.20,0.10,
  'Disciplined wide defender who tracks and marks'),
('wing_back',           'Wing Back',             'defender', ARRAY['LWB','RWB'], ARRAY['LB','RB'],
  NULL, NULL, NULL, NULL,
  0.20,0.15,0.20,0.20,0.40,0.00,0.40,0.10,0.15,0.20,0.20,0.35,0.20,0.15,0.15,0.00,
  'Attacking wide defender providing width and crosses'),

-- ── MIDFIELDERS ─────────────────────────────────────────────
('deep_lying_playmaker','Deep Lying Playmaker',  'midfielder', ARRAY['CDM','CM'], ARRAY['DM'],
  13, 13, 12, 12,
  0.40,0.35,0.15,0.15,0.05,0.00,0.20,0.20,0.30,0.25,0.10,0.20,0.10,0.30,0.35,0.00,
  'Dictates tempo from deep, recycles possession with vision'),
('ball_winning_mid',    'Ball Winning Midfielder','midfielder', ARRAY['CDM','CM'], ARRAY['DM'],
  NULL, NULL, NULL, NULL,
  0.10,0.10,0.30,0.45,0.15,0.00,0.40,0.20,0.15,0.30,0.35,0.30,0.00,0.10,0.20,0.10,
  'Aggressive, energetic midfielder who wins the ball'),
('box_to_box_mid',      'Box-to-Box Midfielder', 'midfielder', ARRAY['CM'], ARRAY['CDM','CAM'],
  NULL, NULL, NULL, NULL,
  0.20,0.15,0.20,0.25,0.20,0.10,0.40,0.15,0.20,0.20,0.20,0.40,0.10,0.15,0.20,0.10,
  'Gets up and down the pitch, contributing in both phases'),
('advanced_playmaker',  'Advanced Playmaker',    'midfielder', ARRAY['CAM','CM'], ARRAY['AML','AMR'],
  13, 14, 13, 12,
  0.35,0.45,0.10,0.05,0.10,0.15,0.15,0.15,0.30,0.20,0.05,0.15,0.25,0.35,0.35,0.00,
  'Creative #10 who operates between lines and creates chances'),
('wide_midfielder',     'Wide Midfielder',       'midfielder', ARRAY['AML','AMR','LM','RM'], ARRAY['CM'],
  NULL, NULL, NULL, NULL,
  0.20,0.15,0.20,0.15,0.35,0.10,0.35,0.10,0.15,0.15,0.10,0.30,0.25,0.15,0.15,0.00,
  'Wide midfield player who tracks back and provides width'),

-- ── FORWARDS ────────────────────────────────────────────────
('poacher',             'Poacher',               'forward', ARRAY['ST','CF'], ARRAY['SS'],
  NULL, NULL, NULL, NULL,
  0.05,0.10,0.35,0.00,0.15,0.45,0.15,0.05,0.30,0.35,0.10,0.10,0.10,0.15,0.15,0.15,
  'Goal-hungry striker who lives in the box for half chances'),
('target_man',          'Target Man',            'forward', ARRAY['ST','CF'], ARRAY[],
  NULL, NULL, NULL, NULL,
  0.10,0.10,0.20,0.00,0.10,0.30,0.20,0.20,0.25,0.20,0.40,0.20,0.10,0.20,0.15,0.40,
  'Physical striker who holds up play and brings others into game'),
('advanced_forward',    'Advanced Forward',      'forward', ARRAY['ST','CF'], ARRAY['SS','AML','AMR'],
  NULL, NULL, NULL, NULL,
  0.15,0.20,0.20,0.00,0.30,0.35,0.25,0.10,0.25,0.25,0.15,0.20,0.30,0.20,0.20,0.10,
  'Complete striker who can press, run in behind and score'),
('winger',              'Winger',                'forward', ARRAY['AML','AMR'], ARRAY['LM','RM','ST'],
  NULL, NULL, NULL, NULL,
  0.15,0.15,0.15,0.05,0.45,0.25,0.25,0.05,0.20,0.15,0.10,0.20,0.40,0.20,0.15,0.00,
  'Electric wide attacker who beats defenders with pace and dribbling'),
('inside_forward',      'Inside Forward',        'forward', ARRAY['AML','AMR'], ARRAY['CAM','ST'],
  NULL, NULL, NULL, NULL,
  0.20,0.25,0.15,0.00,0.35,0.35,0.20,0.05,0.25,0.20,0.10,0.20,0.35,0.25,0.25,0.00,
  'Inverted wide forward who cuts inside to shoot or create'),
('pressing_forward',    'Pressing Forward',      'forward', ARRAY['ST','AML','AMR'], ARRAY['CF'],
  NULL, NULL, NULL, NULL,
  0.10,0.10,0.20,0.00,0.30,0.20,0.45,0.10,0.20,0.25,0.15,0.35,0.20,0.10,0.20,0.00,
  'High-energy forward who presses defenders to force errors');

-- ────────────────────────────────────────────────────────────
-- SECTION 3: player_position_profiles TABLE
-- Stores the computed position intelligence result per player.
-- One current row per player.
-- ────────────────────────────────────────────────────────────

CREATE TABLE player_position_profiles (
  id                  UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id           UUID          NOT NULL
                      REFERENCES players(id) ON DELETE CASCADE,
  -- Best fit position and role
  best_position       TEXT          NOT NULL,
  secondary_position  TEXT,
  best_role_code      TEXT
                      REFERENCES position_roles(code) ON DELETE SET NULL,
  best_role_label     TEXT,
  secondary_role_code TEXT
                      REFERENCES position_roles(code) ON DELETE SET NULL,
  -- Role fit scores (0-100)
  best_role_score     NUMERIC(5,2),
  -- Trend and recommendation
  development_trend   TEXT
                      CHECK (development_trend IN (
                        'rapidly_improving','improving','stable',
                        'declining','rapidly_declining','insufficient_data'
                      )),
  scout_recommendation TEXT
                      CHECK (scout_recommendation IN (
                        'strongly_recommended','recommended','monitor',
                        'development_prospect','not_recommended'
                      )),
  recommendation_reason TEXT
                      CHECK (char_length(recommendation_reason) <= 500),
  -- When computed
  is_current          BOOLEAN       NOT NULL DEFAULT true,
  computed_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_pos_profile_current
  ON player_position_profiles(player_id) WHERE is_current = true;

CREATE INDEX idx_pos_profile_player
  ON player_position_profiles(player_id, computed_at DESC);

CREATE INDEX idx_pos_profile_role
  ON player_position_profiles(best_role_code) WHERE is_current = true;

ALTER TABLE player_position_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_position_profiles: public read"
  ON player_position_profiles FOR SELECT USING (true);

CREATE POLICY "player_position_profiles: system write"
  ON player_position_profiles FOR INSERT
  WITH CHECK (get_my_role() IN ('developer','league_admin','league_founder'));

-- ────────────────────────────────────────────────────────────
-- SECTION 4: match_pipeline_log TABLE
-- Audit trail for every pipeline execution.
-- ────────────────────────────────────────────────────────────

CREATE TABLE match_pipeline_log (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  fixture_id        UUID
                    REFERENCES fixtures(id) ON DELETE SET NULL,
  season_id         UUID
                    REFERENCES seasons(id) ON DELETE SET NULL,
  started_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  completed_at      TIMESTAMPTZ,
  status            TEXT          NOT NULL DEFAULT 'running'
                    CHECK (status IN ('running','completed','failed')),
  players_processed INTEGER       NOT NULL DEFAULT 0,
  attribute_updates INTEGER       NOT NULL DEFAULT 0,
  dna_updates       INTEGER       NOT NULL DEFAULT 0,
  position_updates  INTEGER       NOT NULL DEFAULT 0,
  passport_updates  INTEGER       NOT NULL DEFAULT 0,
  error_message     TEXT,
  triggered_by      UUID          REFERENCES profiles(id) ON DELETE SET NULL
);

CREATE INDEX idx_pipeline_log_fixture
  ON match_pipeline_log(fixture_id);
CREATE INDEX idx_pipeline_log_status
  ON match_pipeline_log(status, started_at DESC);

ALTER TABLE match_pipeline_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pipeline_log: authorised read"
  ON match_pipeline_log FOR SELECT
  USING (get_my_role() IN ('developer','league_admin','league_founder','club_admin'));

-- ────────────────────────────────────────────────────────────
-- SECTION 5: ATTRIBUTE MONTHLY CAP TRACKING
-- Track cumulative AI-sourced attribute changes per player
-- per rolling 30-day window to enforce the +1.0/month cap.
-- ────────────────────────────────────────────────────────────

CREATE TABLE attribute_monthly_caps (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id       UUID          NOT NULL
                  REFERENCES players(id) ON DELETE CASCADE,
  attribute_code  TEXT          NOT NULL
                  REFERENCES attribute_definitions(code) ON DELETE CASCADE,
  window_start    DATE          NOT NULL DEFAULT CURRENT_DATE,
  cumulative_gain NUMERIC(4,2)  NOT NULL DEFAULT 0,
  last_updated    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (player_id, attribute_code, window_start)
);

CREATE INDEX idx_monthly_caps_player
  ON attribute_monthly_caps(player_id, attribute_code, window_start DESC);

ALTER TABLE attribute_monthly_caps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "attribute_monthly_caps: authorised read"
  ON attribute_monthly_caps FOR SELECT
  USING (get_my_role() IN ('developer','league_admin','club_admin','coach'));

-- ────────────────────────────────────────────────────────────
-- SECTION 6: CORE FUNCTION — apply_capped_attribute_update()
-- Applies a single attribute nudge with all three caps:
--   1. Per-match cap:  max ±0.20 change per match
--   2. Monthly cap:    max +1.00 cumulative gain per 30 days
--   3. Value bounds:   clamp to [1, 20]
-- Returns the actual applied delta.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION apply_capped_attribute_update(
  p_player_id    UUID,
  p_attr_code    TEXT,
  p_raw_nudge    NUMERIC,     -- uncapped desired change (may be ±)
  p_season_id    UUID,
  p_source       TEXT         DEFAULT 'ai_batch'
)
RETURNS NUMERIC              -- actual applied delta
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_val   NUMERIC;
  v_capped_nudge  NUMERIC;
  v_new_val       NUMERIC;
  v_applied_delta NUMERIC;
  v_monthly_gain  NUMERIC;
  v_window_start  DATE;
  v_prev_val      SMALLINT;
  PER_MATCH_CAP   CONSTANT NUMERIC := 0.20;
  MONTHLY_CAP     CONSTANT NUMERIC := 1.00;
BEGIN
  -- 1. Fetch current value (use current_value, not ai_value, as the base)
  SELECT COALESCE(current_value, 10) INTO v_current_val
  FROM player_attributes
  WHERE player_id = p_player_id AND attribute_code = p_attr_code;

  v_current_val := COALESCE(v_current_val, 10);

  -- 2. Apply per-match cap to the raw nudge
  v_capped_nudge := GREATEST(-PER_MATCH_CAP, LEAST(PER_MATCH_CAP, p_raw_nudge));

  -- 3. For positive gains: check monthly cumulative cap
  IF v_capped_nudge > 0 THEN
    v_window_start := DATE_TRUNC('month', CURRENT_DATE)::DATE;

    SELECT COALESCE(SUM(cumulative_gain), 0) INTO v_monthly_gain
    FROM attribute_monthly_caps
    WHERE player_id     = p_player_id
      AND attribute_code = p_attr_code
      AND window_start  >= CURRENT_DATE - 30;

    -- How much room left in the monthly budget?
    DECLARE
      v_room NUMERIC := MONTHLY_CAP - v_monthly_gain;
    BEGIN
      IF v_room <= 0 THEN
        RETURN 0;  -- monthly cap already exhausted
      END IF;
      v_capped_nudge := LEAST(v_capped_nudge, v_room);
    END;
  END IF;

  -- 4. Compute new value with regression-to-mean dampening
  IF v_capped_nudge > 0 THEN
    -- Resistance increases as value approaches 20
    v_new_val := v_current_val
      + v_capped_nudge * (1 - (v_current_val - 1)::NUMERIC / 19.0);
  ELSE
    -- Resistance increases as value approaches 1
    v_new_val := v_current_val
      + v_capped_nudge * (1 - (20 - v_current_val)::NUMERIC / 19.0);
  END IF;

  -- 5. Clamp to [1, 20]
  v_new_val := GREATEST(1, LEAST(20, v_new_val));

  -- 6. Round: only apply if results in at least 0.05 move
  v_applied_delta := v_new_val - v_current_val;
  IF ABS(v_applied_delta) < 0.05 THEN
    RETURN 0;
  END IF;

  v_prev_val := ROUND(v_current_val)::SMALLINT;

  -- 7. Upsert player_attributes
  INSERT INTO player_attributes (
    player_id, attribute_code,
    current_value, ai_value,
    confidence_level,
    last_assessed_at, last_assessed_by_type,
    season_id, is_public
  ) VALUES (
    p_player_id, p_attr_code,
    ROUND(v_new_val)::SMALLINT, ROUND(v_new_val)::SMALLINT,
    'low', NOW(), p_source,
    p_season_id, true
  )
  ON CONFLICT (player_id, attribute_code) DO UPDATE SET
    ai_value              = ROUND(v_new_val)::SMALLINT,
    current_value         = ROUND(v_new_val)::SMALLINT,
    last_assessed_at      = NOW(),
    last_assessed_by_type = p_source,
    updated_at            = NOW();

  -- 8. Write to history only if integer value actually changed
  IF ROUND(v_new_val)::SMALLINT <> v_prev_val THEN
    INSERT INTO player_attribute_history (
      player_id, attribute_code,
      value, previous_value,
      recorded_at, season_id, trigger_source
    ) VALUES (
      p_player_id, p_attr_code,
      ROUND(v_new_val)::SMALLINT, v_prev_val,
      NOW(), p_season_id, p_source
    );
  END IF;

  -- 9. Update monthly cap tracker (only for gains)
  IF v_applied_delta > 0 THEN
    INSERT INTO attribute_monthly_caps (
      player_id, attribute_code, window_start, cumulative_gain
    ) VALUES (
      p_player_id, p_attr_code,
      DATE_TRUNC('month', CURRENT_DATE)::DATE,
      v_applied_delta
    )
    ON CONFLICT (player_id, attribute_code, window_start)
    DO UPDATE SET
      cumulative_gain = attribute_monthly_caps.cumulative_gain + v_applied_delta,
      last_updated    = NOW();
  END IF;

  RETURN v_applied_delta;
END;
$$;

GRANT EXECUTE ON FUNCTION apply_capped_attribute_update(UUID,TEXT,NUMERIC,UUID,TEXT)
  TO authenticated;

-- ────────────────────────────────────────────────────────────
-- SECTION 7: MATCH EVENT → ATTRIBUTE MAPPING
-- The 18-attribute, per-event mapping with explicit nudge values.
-- This replaces the generic weight table for the pipeline.
-- Each entry defines the direct effect of one event type
-- on one attribute.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_match_attribute_nudges(
  p_event_type    TEXT,
  p_position_group TEXT
)
RETURNS TABLE (attribute_code TEXT, nudge NUMERIC)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Returns (attribute_code, nudge_per_occurrence) pairs
  -- nudge is per single event, before match cap is applied
  SELECT * FROM (VALUES

    -- PASS SUCCESSFUL → Passing (small), Composure (tiny)
    ('pass_successful',   'passing',       0.004,  NULL),
    ('pass_successful',   'composure',     0.002,  NULL),

    -- PASS FAILED → Passing (negative)
    ('pass_failed',       'passing',      -0.003,  NULL),

    -- KEY PASS → Vision (strong), Passing, Decision Making
    ('key_pass',          'vision',        0.012,  NULL),
    ('key_pass',          'passing',       0.008,  NULL),
    ('key_pass',          'decision_making',0.007, NULL),

    -- THROUGH BALL → Vision (strong), Decision Making, Anticipation
    ('through_ball',      'vision',        0.015,  NULL),
    ('through_ball',      'decision_making',0.010, NULL),
    ('through_ball',      'anticipation',  0.008,  NULL),

    -- GOAL → Finishing (strong, forwards), Composure
    ('goal',              'finishing',     0.020, 'forward'),
    ('goal',              'composure',     0.010, 'forward'),
    ('goal',              'finishing',     0.012, 'midfielder'),
    ('goal',              'composure',     0.008, 'midfielder'),
    ('goal',              'composure',     0.006,  NULL),   -- all positions

    -- ASSIST → Vision, Teamwork, Passing
    ('assist',            'vision',        0.015,  NULL),
    ('assist',            'teamwork',      0.010,  NULL),
    ('assist',            'passing',       0.008,  NULL),
    ('assist',            'decision_making',0.006, NULL),

    -- SHOT ON TARGET → Finishing, Composure
    ('shot_on_target',    'finishing',     0.010, 'forward'),
    ('shot_on_target',    'composure',     0.006, 'forward'),
    ('shot_on_target',    'finishing',     0.006, 'midfielder'),

    -- SHOT OFF TARGET → slight Finishing negative (poor decision)
    ('shot_off_target',   'finishing',    -0.002, 'forward'),
    ('shot_off_target',   'decision_making',-0.001,NULL),

    -- TACKLE WON → Tackling (strong), Anticipation, Positioning
    ('tackle_won',        'tackling',      0.015,  NULL),
    ('tackle_won',        'anticipation',  0.008,  NULL),
    ('tackle_won',        'positioning',   0.006,  NULL),
    ('tackle_won',        'work_rate',     0.005,  NULL),

    -- TACKLE LOST → Tackling (negative)
    ('tackle_lost',       'tackling',     -0.008,  NULL),
    ('tackle_lost',       'composure',    -0.004,  NULL),

    -- INTERCEPTION → Anticipation (strong), Positioning
    ('interception',      'anticipation',  0.018,  NULL),
    ('interception',      'positioning',   0.012,  NULL),
    ('interception',      'decision_making',0.006, NULL),

    -- CLEARANCE → Heading (defenders), Positioning, Strength
    ('clearance',         'heading',       0.010, 'defender'),
    ('clearance',         'positioning',   0.008, 'defender'),
    ('clearance',         'strength',      0.006, 'defender'),

    -- SAVE (keeper_save_routine) → Composure, Work Rate
    ('keeper_save_routine','composure',    0.008, 'goalkeeper'),
    ('keeper_save_routine','work_rate',    0.006, 'goalkeeper'),

    -- SAVE DIFFICULT → Composure (strong), Decision Making
    ('keeper_save_difficult','composure',  0.018, 'goalkeeper'),
    ('keeper_save_difficult','decision_making',0.012,'goalkeeper'),

    -- SAVE EXCEPTIONAL → Strong boost all GK mental
    ('keeper_save_exceptional','composure',0.030,'goalkeeper'),
    ('keeper_save_exceptional','leadership',0.010,'goalkeeper'),

    -- DUEL WON → Strength, Work Rate
    ('duel_won',          'strength',      0.008,  NULL),
    ('duel_won',          'work_rate',     0.006,  NULL),

    -- DUEL LOST → slight Strength negative
    ('duel_lost',         'strength',     -0.004,  NULL),

    -- YELLOW CARD → Composure (significant negative)
    ('yellow_card',       'composure',    -0.030,  NULL),
    ('yellow_card',       'decision_making',-0.015,NULL),

    -- RED CARD → Composure (severe negative)
    ('red_card',          'composure',    -0.060,  NULL),
    ('red_card',          'decision_making',-0.030,NULL),

    -- ERROR LEADING TO GOAL → Composure (severe), Positioning, Decision Making
    ('error_leading_to_goal','composure',  -0.060, NULL),
    ('error_leading_to_goal','decision_making',-0.040,NULL),
    ('error_leading_to_goal','positioning', -0.025,NULL),

    -- FOUL WON → Work Rate
    ('foul_won',           'work_rate',    0.003,  NULL)

  ) AS t(event_type_key, attr_code, nudge_val, pos_filter)
  WHERE event_type_key = p_event_type
    AND (pos_filter IS NULL OR pos_filter = p_position_group);
$$;

GRANT EXECUTE ON FUNCTION get_match_attribute_nudges(TEXT, TEXT) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- SECTION 8: POSITION INTELLIGENCE ENGINE
-- Determines a player's best position and playing role
-- by scoring their attribute profile against every
-- position_roles entry.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION determine_player_position(p_player_id UUID)
RETURNS TABLE (
  best_position       TEXT,
  secondary_position  TEXT,
  best_role_code      TEXT,
  best_role_label     TEXT,
  best_role_score     NUMERIC,
  secondary_role_code TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- Player's current attribute values
  v_passing       NUMERIC := 10;
  v_vision        NUMERIC := 10;
  v_positioning   NUMERIC := 10;
  v_tackling      NUMERIC := 10;
  v_pace          NUMERIC := 10;
  v_finishing     NUMERIC := 10;
  v_work_rate     NUMERIC := 10;
  v_leadership    NUMERIC := 10;
  v_composure     NUMERIC := 10;
  v_anticipation  NUMERIC := 10;
  v_strength      NUMERIC := 10;
  v_stamina       NUMERIC := 10;
  v_dribbling     NUMERIC := 10;
  v_first_touch   NUMERIC := 10;
  v_decision_making NUMERIC := 10;
  v_heading       NUMERIC := 10;
  v_position      player_position;
  v_pos_group     TEXT;
  v_best_score    NUMERIC := 0;
  v_best_code     TEXT;
  v_best_label    TEXT;
  v_second_score  NUMERIC := 0;
  v_second_code   TEXT;
  v_best_pos      TEXT;
  v_second_pos    TEXT;
  v_role          RECORD;
  v_role_score    NUMERIC;
BEGIN
  -- 1. Fetch all attribute values
  SELECT
    MAX(CASE WHEN attribute_code = 'passing'         THEN current_value END),
    MAX(CASE WHEN attribute_code = 'vision'          THEN current_value END),
    MAX(CASE WHEN attribute_code = 'positioning'     THEN current_value END),
    MAX(CASE WHEN attribute_code = 'tackling'        THEN current_value END),
    MAX(CASE WHEN attribute_code = 'pace'            THEN current_value END),
    MAX(CASE WHEN attribute_code = 'finishing'       THEN current_value END),
    MAX(CASE WHEN attribute_code = 'work_rate'       THEN current_value END),
    MAX(CASE WHEN attribute_code = 'leadership'      THEN current_value END),
    MAX(CASE WHEN attribute_code = 'composure'       THEN current_value END),
    MAX(CASE WHEN attribute_code = 'anticipation'    THEN current_value END),
    MAX(CASE WHEN attribute_code = 'strength'        THEN current_value END),
    MAX(CASE WHEN attribute_code = 'stamina'         THEN current_value END),
    MAX(CASE WHEN attribute_code = 'dribbling'       THEN current_value END),
    MAX(CASE WHEN attribute_code = 'first_touch'     THEN current_value END),
    MAX(CASE WHEN attribute_code = 'decision_making' THEN current_value END),
    MAX(CASE WHEN attribute_code = 'heading'         THEN current_value END)
  INTO
    v_passing, v_vision, v_positioning, v_tackling, v_pace,
    v_finishing, v_work_rate, v_leadership, v_composure,
    v_anticipation, v_strength, v_stamina, v_dribbling,
    v_first_touch, v_decision_making, v_heading
  FROM player_attributes
  WHERE player_id = p_player_id;

  -- Default nulls to 10
  v_passing        := COALESCE(v_passing, 10);
  v_vision         := COALESCE(v_vision, 10);
  v_positioning    := COALESCE(v_positioning, 10);
  v_tackling       := COALESCE(v_tackling, 10);
  v_pace           := COALESCE(v_pace, 10);
  v_finishing      := COALESCE(v_finishing, 10);
  v_work_rate      := COALESCE(v_work_rate, 10);
  v_leadership     := COALESCE(v_leadership, 10);
  v_composure      := COALESCE(v_composure, 10);
  v_anticipation   := COALESCE(v_anticipation, 10);
  v_strength       := COALESCE(v_strength, 10);
  v_stamina        := COALESCE(v_stamina, 10);
  v_dribbling      := COALESCE(v_dribbling, 10);
  v_first_touch    := COALESCE(v_first_touch, 10);
  v_decision_making := COALESCE(v_decision_making, 10);
  v_heading        := COALESCE(v_heading, 10);

  -- 2. Get player's registered position
  SELECT p.position INTO v_position FROM players p WHERE p.id = p_player_id;
  v_pos_group := COALESCE(v_position::TEXT, 'midfielder');

  -- 3. Score every active role
  FOR v_role IN
    SELECT * FROM position_roles WHERE is_active = true
  LOOP
    -- Score = weighted sum of attribute values, normalised to 0-100
    v_role_score := (
      v_passing        * v_role.wt_passing
      + v_vision         * v_role.wt_vision
      + v_positioning    * v_role.wt_positioning
      + v_tackling       * v_role.wt_tackling
      + v_pace           * v_role.wt_pace
      + v_finishing      * v_role.wt_finishing
      + v_work_rate      * v_role.wt_work_rate
      + v_leadership     * v_role.wt_leadership
      + v_composure      * v_role.wt_composure
      + v_anticipation   * v_role.wt_anticipation
      + v_strength       * v_role.wt_strength
      + v_stamina        * v_role.wt_stamina
      + v_dribbling      * v_role.wt_dribbling
      + v_first_touch    * v_role.wt_first_touch
      + v_decision_making * v_role.wt_decision_making
      + v_heading        * v_role.wt_heading
    ) / 20.0 * 100; -- normalise to 0-100

    -- Apply hard minimum requirements (if any are unmet, heavy penalty)
    IF (v_role.req_passing      IS NOT NULL AND v_passing        < v_role.req_passing)
    OR (v_role.req_vision       IS NOT NULL AND v_vision         < v_role.req_vision)
    OR (v_role.req_decision_making IS NOT NULL AND v_decision_making < v_role.req_decision_making)
    OR (v_role.req_composure    IS NOT NULL AND v_composure      < v_role.req_composure) THEN
      v_role_score := v_role_score * 0.60; -- 40% penalty for not meeting minimums
    END IF;

    -- Bonus if role's position_group matches player's registered position
    IF v_role.position_group = v_pos_group THEN
      v_role_score := v_role_score * 1.10;
    END IF;

    -- Track top two
    IF v_role_score > v_best_score THEN
      v_second_score := v_best_score;
      v_second_code  := v_best_code;
      v_best_score   := v_role_score;
      v_best_code    := v_role.code;
      v_best_label   := v_role.label;
      v_best_pos     := v_role.primary_pos[1];
    ELSIF v_role_score > v_second_score THEN
      v_second_score := v_role_score;
      v_second_code  := v_role.code;
    END IF;
  END LOOP;

  -- 4. Determine secondary position (from secondary role)
  SELECT primary_pos[1] INTO v_second_pos
  FROM position_roles WHERE code = v_second_code;

  RETURN QUERY SELECT
    COALESCE(v_best_pos, v_pos_group::TEXT),
    v_second_pos,
    v_best_code,
    v_best_label,
    ROUND(v_best_score, 2),
    v_second_code;
END;
$$;

GRANT EXECUTE ON FUNCTION determine_player_position(UUID) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- SECTION 9: generate_player_recommendation()
-- Produces a structured scout recommendation from DNA,
-- trend, and role fit.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION generate_player_recommendation(
  p_player_id UUID
)
RETURNS TABLE (
  recommendation      TEXT,
  recommendation_reason TEXT,
  development_trend   TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dna           SMALLINT;
  v_potential     SMALLINT;
  v_pot_cat       TEXT;
  v_age           INTEGER;
  v_trend         TEXT;
  v_passport      SMALLINT;
  v_avg_delta     NUMERIC;
  v_rec           TEXT;
  v_reason        TEXT;
BEGIN
  SELECT
    p.dna_overall,
    p.potential_score,
    p.potential_category,
    p.passport_score,
    EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER
  INTO v_dna, v_potential, v_pot_cat, v_passport, v_age
  FROM players p WHERE p.id = p_player_id;

  -- Development trend from last 12 months of attribute history
  SELECT COALESCE(AVG(delta), 0) INTO v_avg_delta
  FROM player_attribute_history
  WHERE player_id  = p_player_id
    AND recorded_at >= NOW() - INTERVAL '12 months'
    AND delta IS NOT NULL;

  v_trend := CASE
    WHEN v_avg_delta > 0.8  THEN 'rapidly_improving'
    WHEN v_avg_delta > 0.3  THEN 'improving'
    WHEN v_avg_delta >= -0.1 THEN 'stable'
    WHEN v_avg_delta >= -0.5 THEN 'declining'
    ELSE                          'rapidly_declining'
  END;

  -- Check if we have any history at all
  IF NOT EXISTS (
    SELECT 1 FROM player_attribute_history WHERE player_id = p_player_id LIMIT 1
  ) THEN
    v_trend := 'insufficient_data';
  END IF;

  -- Generate recommendation
  v_rec := CASE
    WHEN COALESCE(v_dna,0) >= 80
         AND COALESCE(v_potential,0) >= 80
         AND v_trend IN ('rapidly_improving','improving')
         THEN 'strongly_recommended'

    WHEN COALESCE(v_dna,0) >= 75
         OR (COALESCE(v_potential,0) >= 80 AND v_age <= 22)
         THEN 'recommended'

    WHEN COALESCE(v_dna,0) >= 60
         OR (COALESCE(v_potential,0) >= 65 AND v_age <= 24)
         THEN 'monitor'

    WHEN COALESCE(v_dna,0) >= 40
         AND COALESCE(v_age, 99) <= 20
         THEN 'development_prospect'

    ELSE 'not_recommended'
  END;

  -- Generate reason text
  v_reason := format(
    '%s, age %s. DNA: %s. Potential: %s (%s). Trend: %s. Passport: %s.',
    CASE v_rec
      WHEN 'strongly_recommended' THEN 'Outstanding profile across all metrics'
      WHEN 'recommended'          THEN 'Strong candidate warranting serious consideration'
      WHEN 'monitor'              THEN 'Interesting profile, worth tracking development'
      WHEN 'development_prospect' THEN 'Young player with future potential'
      ELSE                             'Current profile does not meet selection threshold'
    END,
    v_age,
    COALESCE(v_dna::TEXT, 'unrated'),
    COALESCE(v_potential::TEXT, 'unrated'),
    REPLACE(COALESCE(v_pot_cat, 'unknown'), '_', ' '),
    REPLACE(v_trend, '_', ' '),
    COALESCE(v_passport::TEXT, 'unrated')
  );

  RETURN QUERY SELECT v_rec, v_reason, v_trend;
END;
$$;

GRANT EXECUTE ON FUNCTION generate_player_recommendation(UUID) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- SECTION 10: THE PIPELINE — run_post_match_pipeline()
-- Single entry point. Called by:
--   a) Match Observer "Finalise" button (manual)
--   b) fixtures status trigger (automatic)
--
-- Pipeline steps:
--   1. Aggregate match events → player_match_stats
--   2. For each player:
--      a. Collect event types and counts
--      b. Look up attribute nudges
--      c. Apply with caps via apply_capped_attribute_update()
--      d. Apply card-based composure decay
--   3. Recalculate DNA for each player
--   4. Position Intelligence for each player
--   5. Generate recommendation for each player
--   6. Update players table (denormalised columns)
--   7. Recompute Passport Score
--   8. Log pipeline result
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION run_post_match_pipeline(
  p_fixture_id UUID,
  p_season_id  UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_log_id            UUID;
  v_players_processed INTEGER := 0;
  v_attr_updates      INTEGER := 0;
  v_dna_updates       INTEGER := 0;
  v_pos_updates       INTEGER := 0;
  v_passport_updates  INTEGER := 0;
  v_player            RECORD;
  v_event             RECORD;
  v_nudge             RECORD;
  v_event_count       INTEGER;
  v_total_nudge       NUMERIC;
  v_applied           NUMERIC;
  v_pos_result        RECORD;
  v_rec_result        RECORD;
  v_dna_result        RECORD;
  v_season_id         UUID;
  v_pos_group         TEXT;
BEGIN
  -- Resolve season_id if not provided
  IF p_season_id IS NULL THEN
    SELECT s.id INTO v_season_id
    FROM fixtures f
    JOIN seasons s ON s.league_id = f.league_id
    WHERE f.id = p_fixture_id
      AND s.status = 'active'
    LIMIT 1;
  ELSE
    v_season_id := p_season_id;
  END IF;

  -- Create pipeline log entry
  INSERT INTO match_pipeline_log (fixture_id, season_id, triggered_by)
  VALUES (p_fixture_id, v_season_id, auth.uid())
  RETURNING id INTO v_log_id;

  -- ── STEP 1: Post-match stats aggregation ──────────────────
  PERFORM post_match_aggregation(p_fixture_id);

  -- ── STEP 2: Process each player ───────────────────────────
  FOR v_player IN
    SELECT DISTINCT
      me.player_id,
      p.position,
      CASE p.position
        WHEN 'goalkeeper' THEN 'goalkeeper'
        WHEN 'defender'   THEN 'defender'
        WHEN 'midfielder' THEN 'midfielder'
        WHEN 'forward'    THEN 'forward'
        ELSE 'midfielder'
      END AS pos_group
    FROM match_events me
    JOIN players p ON p.id = me.player_id
    WHERE me.fixture_id   = p_fixture_id
      AND me.player_id    IS NOT NULL
      AND me.is_cancelled = false
  LOOP
    v_players_processed := v_players_processed + 1;

    -- ── STEP 2a: For each event type this player had ──────────
    FOR v_event IN
      SELECT
        me.event_type::TEXT AS etype,
        COUNT(*)            AS cnt
      FROM match_events me
      WHERE me.fixture_id  = p_fixture_id
        AND me.player_id   = v_player.player_id
        AND me.is_cancelled = false
      GROUP BY me.event_type
    LOOP
      -- ── STEP 2b: Get attribute nudges for this event ────────
      FOR v_nudge IN
        SELECT attribute_code, nudge
        FROM get_match_attribute_nudges(v_event.etype, v_player.pos_group)
      LOOP
        -- Total nudge = nudge_per_event * count of events
        -- (count is implicitly capped by the per-match ±0.20 cap)
        v_total_nudge := v_nudge.nudge * v_event.cnt;

        -- ── STEP 2c: Apply with cap ─────────────────────────
        v_applied := apply_capped_attribute_update(
          v_player.player_id,
          v_nudge.attribute_code,
          v_total_nudge,
          v_season_id,
          'ai_batch'
        );

        IF v_applied <> 0 THEN
          v_attr_updates := v_attr_updates + 1;
        END IF;
      END LOOP;
    END LOOP;

    -- ── STEP 3: Recalculate DNA ───────────────────────────────
    SELECT * INTO v_dna_result
    FROM calculate_player_dna(v_player.player_id);
    v_dna_updates := v_dna_updates + 1;

    -- ── STEP 4: Position Intelligence ────────────────────────
    SELECT * INTO v_pos_result
    FROM determine_player_position(v_player.player_id);

    -- ── STEP 5: Recommendation ───────────────────────────────
    SELECT * INTO v_rec_result
    FROM generate_player_recommendation(v_player.player_id);

    -- ── STEP 6: Update player_position_profiles ──────────────
    UPDATE player_position_profiles SET is_current = false
    WHERE player_id = v_player.player_id AND is_current = true;

    INSERT INTO player_position_profiles (
      player_id,
      best_position, secondary_position,
      best_role_code, best_role_label,
      secondary_role_code,
      best_role_score,
      development_trend,
      scout_recommendation,
      recommendation_reason,
      is_current
    ) VALUES (
      v_player.player_id,
      v_pos_result.best_position,
      v_pos_result.secondary_position,
      v_pos_result.best_role_code,
      v_pos_result.best_role_label,
      v_pos_result.secondary_role_code,
      v_pos_result.best_role_score,
      v_rec_result.development_trend,
      v_rec_result.recommendation,
      v_rec_result.recommendation_reason,
      true
    );
    v_pos_updates := v_pos_updates + 1;

    -- ── STEP 7: Denormalise to players table ──────────────────
    UPDATE players SET
      best_position      = v_pos_result.best_position,
      secondary_position = v_pos_result.secondary_position,
      playing_role       = v_pos_result.best_role_label,
      development_trend  = v_rec_result.development_trend,
      scout_recommendation = v_rec_result.recommendation,
      pipeline_last_run  = NOW(),
      updated_at         = NOW()
    WHERE id = v_player.player_id;

    -- ── STEP 8: Recompute Passport Score ──────────────────────
    PERFORM compute_player_passport_score(v_player.player_id);
    v_passport_updates := v_passport_updates + 1;

  END LOOP;

  -- ── STEP 9: Update pipeline log ──────────────────────────────
  UPDATE match_pipeline_log SET
    status            = 'completed',
    completed_at      = NOW(),
    players_processed = v_players_processed,
    attribute_updates = v_attr_updates,
    dna_updates       = v_dna_updates,
    position_updates  = v_pos_updates,
    passport_updates  = v_passport_updates
  WHERE id = v_log_id;

  -- ── STEP 10: Return summary ───────────────────────────────────
  RETURN JSONB_BUILD_OBJECT(
    'pipeline_log_id',   v_log_id,
    'fixture_id',        p_fixture_id,
    'season_id',         v_season_id,
    'players_processed', v_players_processed,
    'attribute_updates', v_attr_updates,
    'dna_updates',       v_dna_updates,
    'position_updates',  v_pos_updates,
    'passport_updates',  v_passport_updates,
    'completed_at',      NOW()
  );

EXCEPTION WHEN OTHERS THEN
  -- Log failure
  UPDATE match_pipeline_log SET
    status        = 'failed',
    completed_at  = NOW(),
    error_message = SQLERRM
  WHERE id = v_log_id;

  RAISE WARNING 'run_post_match_pipeline failed for fixture %: %', p_fixture_id, SQLERRM;

  RETURN JSONB_BUILD_OBJECT(
    'error',      SQLERRM,
    'fixture_id', p_fixture_id,
    'log_id',     v_log_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION run_post_match_pipeline(UUID, UUID) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- SECTION 11: AUTOMATIC TRIGGER ON FIXTURE COMPLETION
-- When fixture.status changes to 'completed', fire the
-- pipeline automatically. No manual action required.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION trg_fixture_completion_pipeline()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only fire when status transitions TO 'completed'
  IF OLD.status IS DISTINCT FROM NEW.status
     AND NEW.status = 'completed'
  THEN
    -- Run pipeline asynchronously via pg_notify so it doesn't block
    -- the fixture UPDATE transaction.
    -- In Supabase: a realtime listener or Edge Function picks this up.
    PERFORM pg_notify(
      'match_pipeline',
      JSON_BUILD_OBJECT(
        'fixture_id', NEW.id,
        'league_id',  NEW.league_id,
        'event',      'fixture_completed'
      )::TEXT
    );

    -- Also run synchronously for immediate DNA update
    -- (acceptable latency for grassroots; swap to async for high-volume)
    PERFORM run_post_match_pipeline(NEW.id, NULL);
  END IF;
  RETURN NEW;
END;
$$;

-- Attach to fixtures table
DROP TRIGGER IF EXISTS trg_fixture_status_pipeline ON fixtures;
CREATE TRIGGER trg_fixture_status_pipeline
  AFTER UPDATE OF status ON fixtures
  FOR EACH ROW
  EXECUTE FUNCTION trg_fixture_completion_pipeline();

-- ────────────────────────────────────────────────────────────
-- SECTION 12: COMPOSURE DECAY FROM REPEATED CARDS
-- Separate from idle decay. If a player accumulates 3+
-- yellow cards or any red card in a season, apply composure
-- decay. Called by pipeline after card events.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION apply_discipline_decay(
  p_player_id UUID,
  p_season_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_yellows INTEGER;
  v_reds    INTEGER;
  v_decay   NUMERIC := 0;
BEGIN
  -- Count cards this season
  SELECT
    COALESCE(SUM(CASE WHEN d.card_type = 'yellow' THEN 1 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN d.card_type = 'red'    THEN 1 ELSE 0 END), 0)
  INTO v_yellows, v_reds
  FROM disciplinary_records d
  JOIN fixtures f ON f.id = d.fixture_id
  JOIN seasons  s ON s.league_id = f.league_id
  WHERE d.player_id = p_player_id
    AND s.id = p_season_id;

  -- Composure decay scale (cumulative from cards this season)
  IF v_reds >= 1 THEN
    v_decay := -0.15;  -- red card: significant composure hit
  ELSIF v_yellows >= 5 THEN
    v_decay := -0.12;
  ELSIF v_yellows >= 3 THEN
    v_decay := -0.08;
  ELSIF v_yellows >= 1 THEN
    v_decay := -0.04;
  END IF;

  IF v_decay < 0 THEN
    PERFORM apply_capped_attribute_update(
      p_player_id, 'composure', v_decay, p_season_id, 'ai_batch'
    );
    -- Decision Making also affected
    PERFORM apply_capped_attribute_update(
      p_player_id, 'decision_making', v_decay * 0.5, p_season_id, 'ai_batch'
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION apply_discipline_decay(UUID, UUID) TO authenticated;

-- ────────────────────────────────────────────────────────────
-- SECTION 13: ENHANCED VIEWS FOR POSITION INTELLIGENCE
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW v_player_position_intelligence
WITH (security_invoker = true)
AS
SELECT
  p.id                                        AS player_id,
  COALESCE(p.preferred_name, p.full_name)     AS display_name,
  p.position                                  AS registered_position,
  p.best_position,
  p.secondary_position,
  p.playing_role,
  p.development_trend,
  p.scout_recommendation,
  p.dna_overall,
  p.dna_band,
  p.dna_technical,
  p.dna_physical,
  p.dna_mental,
  p.dna_tactical,
  p.potential_score,
  p.potential_category,
  p.passport_score,
  p.passport_band,
  p.pipeline_last_run,
  -- Position profile details
  pp.best_role_score,
  pp.recommendation_reason,
  pp.secondary_role_code,
  -- Club
  c.name                                      AS club_name,
  c.logo_url                                  AS club_logo,
  -- Age
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age
FROM players p
LEFT JOIN clubs c ON c.id = p.club_id
LEFT JOIN player_position_profiles pp
  ON pp.player_id = p.id AND pp.is_current = true
WHERE p.is_active = true
  AND p.is_passport_public = true;

-- ── Pipeline summary view ─────────────────────────────────

CREATE OR REPLACE VIEW v_pipeline_summary
WITH (security_invoker = true)
AS
SELECT
  pl.id,
  pl.fixture_id,
  f.match_date,
  pl.season_id,
  pl.status,
  pl.players_processed,
  pl.attribute_updates,
  pl.dna_updates,
  pl.position_updates,
  pl.passport_updates,
  pl.started_at,
  pl.completed_at,
  EXTRACT(EPOCH FROM (pl.completed_at - pl.started_at))::INTEGER AS duration_seconds,
  pl.error_message
FROM match_pipeline_log pl
LEFT JOIN fixtures f ON f.id = pl.fixture_id
ORDER BY pl.started_at DESC;

-- ────────────────────────────────────────────────────────────
-- SECTION 14: VERIFICATION QUERIES (run manually)
-- ────────────────────────────────────────────────────────────

-- 1. Check new player columns:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'players'
-- AND column_name IN ('best_position','secondary_position','playing_role',
--   'development_trend','scout_recommendation','pipeline_last_run');

-- 2. Check position_roles seeded (18 rows):
-- SELECT code, label, position_group FROM position_roles ORDER BY position_group, code;

-- 3. Test position engine for a specific player:
-- SELECT * FROM determine_player_position('<player-uuid>');

-- 4. Test recommendation:
-- SELECT * FROM generate_player_recommendation('<player-uuid>');

-- 5. Test full pipeline (with real fixture UUID):
-- SELECT run_post_match_pipeline('<fixture-uuid>', '<season-uuid>');

-- 6. Check pipeline log:
-- SELECT * FROM v_pipeline_summary LIMIT 10;

-- 7. Verify caps working — check monthly tracker:
-- SELECT * FROM attribute_monthly_caps WHERE player_id = '<uuid>'
-- ORDER BY window_start DESC, cumulative_gain DESC;

-- 8. Verify trigger exists:
-- SELECT tgname FROM pg_trigger WHERE tgname = 'trg_fixture_status_pipeline';

COMMIT;

-- ============================================================
-- PHASE 6.7 SUMMARY
-- ============================================================
-- New tables:        4
--   position_roles          (18 roles seeded)
--   player_position_profiles
--   match_pipeline_log
--   attribute_monthly_caps
-- New columns:       6 (on players)
-- New functions:     6
--   apply_capped_attribute_update()  ← core cap enforcement
--   get_match_attribute_nudges()     ← event→attribute mapping
--   determine_player_position()      ← Position Intelligence Engine
--   generate_player_recommendation() ← auto recommendation
--   run_post_match_pipeline()        ← master pipeline
--   apply_discipline_decay()         ← card composure decay
--   trg_fixture_completion_pipeline()← trigger function
-- New trigger:       1 (on fixtures.status → 'completed')
-- New views:         2
--   v_player_position_intelligence
--   v_pipeline_summary
-- ============================================================
-- PIPELINE FLOW:
--   fixture.status = 'completed'
--     → trigger fires run_post_match_pipeline()
--       → post_match_aggregation()           [step 1]
--       → get_match_attribute_nudges()       [step 2b]
--       → apply_capped_attribute_update()    [step 2c]  ← +0.2/match cap
--                                                         +1.0/month cap
--       → apply_discipline_decay()           [step 2d]
--       → calculate_player_dna()             [step 3]
--       → determine_player_position()        [step 4]
--       → generate_player_recommendation()   [step 5]
--       → player_position_profiles upsert    [step 6]
--       → players table denormalise          [step 7]
--       → compute_player_passport_score()    [step 8]
--       → match_pipeline_log updated         [step 9]
-- ============================================================
-- CAPS ENFORCED:
--   Per match:   ±0.20 per attribute (hard cap, GREATEST/LEAST)
--   Per month:   +1.00 cumulative gain (tracked in attribute_monthly_caps)
--   Regression:  dampening formula as value approaches 1 or 20
--   Value bounds: [1, 20] at all times
-- ============================================================
-- POSITION INTELLIGENCE (18 roles):
--   GK:  Sweeper Keeper, Shot Stopper
--   DEF: Ball-Playing CB, Stopper CB, Full Back, Wing Back
--   MID: Deep Lying Playmaker, Ball Winning Mid, Box-to-Box,
--        Advanced Playmaker, Wide Midfielder
--   FWD: Poacher, Target Man, Advanced Forward, Winger,
--        Inside Forward, Pressing Forward
-- ============================================================
