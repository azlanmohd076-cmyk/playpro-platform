-- ============================================================
-- PlayPro Phase 6.8 — Player Development Engine
-- ============================================================
-- Version    : 6.8.0
-- Date       : 2026-06-08
-- Depends on : Phases 1–6.7 (all prior migrations)
-- Author     : PlayPro Principal DB Architect
-- ============================================================
-- DELIVERS:
--   1.  Training Engine
--         training_programmes, training_sessions,
--         player_training_attendance, player_training_performance
--         compute_weekly_training_score()
--
--   2.  Development Engine (hidden attributes)
--         player_hidden_attributes
--         (professionalism, ambition, loyalty, temperament,
--          consistency, injury_proneness)
--         update_hidden_attributes()
--
--   3.  Growth Engine
--         player_development_curves  (age-based growth table)
--         compute_attribute_growth() (coach+attendance+match influence)
--
--   4.  Fitness Engine
--         player_fitness_snapshots
--         (match_sharpness, fatigue, condition, training_load)
--         update_fitness_after_match(), update_fitness_after_training()
--
--   5.  Morale Engine
--         player_morale_snapshots
--         (morale, happiness, playing_time_satisfaction,
--          training_satisfaction)
--         compute_player_morale()
--
--   6.  Injury Engine
--         player_injury_risk_profiles
--         player_development_injuries  (phase 6.8 lightweight extension)
--         assess_injury_risk()
--
--   7.  Position Retraining Engine
--         player_position_familiarity
--         (natural, accomplished, learning, familiarity_pct)
--         apply_position_training()
--
--   8.  Development Projection Engine
--         player_development_projections
--         compute_development_projection()
--
--   9.  Denormalised columns on players
--         fitness_condition, morale_score, match_sharpness,
--         training_load, projected_peak_dna, development_phase
--
--  10.  Club dashboard views
--         v_squad_development_report
--         v_development_leaderboard
--         v_wonderkid_radar
--
--  11.  Passport integration view
--         v_player_development_passport
--
--  12.  Nightly development batch
--         run_development_nightly()
--         called by Supabase Cron at 03:00 MYT
-- ============================================================
-- RULES CONFIRMED:
--   ✓ trigger function name : update_updated_at()
--   ✓ audit function name   : audit_trigger_fn()
--   ✓ player_injuries already exists (Phase 3) — not recreated
--   ✓ injury_type, injury_severity enums already exist
--   ✓ is_coach_for_club(), get_my_player_id(), is_guardian_of() exist
--   ✓ notification_type enum: ADD VALUE outside transaction
--   ✓ attribute_definitions 18-attribute V1 schema is live
--   ✓ player_position enum values: goalkeeper/defender/midfielder/forward
-- ============================================================

-- ============================================================
-- PART A — ENUM ADDITIONS (outside transaction)
-- ============================================================

ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'training_missed';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'training_excellent';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'fitness_low';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'morale_low';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'injury_risk_high';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'development_milestone';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'projection_updated';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'wonderkid_identified';

-- ============================================================
-- PART B — MAIN MIGRATION
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- SECTION 1: PLAYER DENORMALISED DEVELOPMENT COLUMNS
-- ════════════════════════════════════════════════════════════

ALTER TABLE players
  ADD COLUMN IF NOT EXISTS fitness_condition     SMALLINT
    CHECK (fitness_condition IS NULL OR fitness_condition BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS match_sharpness       SMALLINT
    CHECK (match_sharpness IS NULL OR match_sharpness BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS fatigue_level         SMALLINT
    CHECK (fatigue_level IS NULL OR fatigue_level BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS training_load         TEXT
    CHECK (training_load IN ('rest','light','normal','heavy','intense',NULL)),
  ADD COLUMN IF NOT EXISTS morale_score          SMALLINT
    CHECK (morale_score IS NULL OR morale_score BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS morale_band           TEXT
    CHECK (morale_band IN ('ecstatic','happy','content','unsettled','unhappy','miserable',NULL)),
  ADD COLUMN IF NOT EXISTS projected_peak_dna    SMALLINT
    CHECK (projected_peak_dna IS NULL OR projected_peak_dna BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS projected_peak_age    SMALLINT
    CHECK (projected_peak_age IS NULL OR projected_peak_age BETWEEN 14 AND 45),
  ADD COLUMN IF NOT EXISTS development_phase     TEXT
    CHECK (development_phase IN ('emerging','developing','peak','declining','veteran',NULL)),
  ADD COLUMN IF NOT EXISTS injury_risk_level     TEXT
    CHECK (injury_risk_level IN ('low','medium','high','very_high',NULL)),
  ADD COLUMN IF NOT EXISTS last_training_date    DATE,
  ADD COLUMN IF NOT EXISTS days_since_match      SMALLINT;

CREATE INDEX IF NOT EXISTS idx_players_fitness
  ON players(fitness_condition DESC NULLS LAST) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_players_morale
  ON players(morale_score DESC NULLS LAST) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_players_dev_phase
  ON players(development_phase) WHERE is_active = true;

-- ════════════════════════════════════════════════════════════
-- SECTION 2: TRAINING ENGINE
-- ════════════════════════════════════════════════════════════

-- ── 2a. training_programmes ──────────────────────────────────
-- A reusable training programme template defined by a coach.
-- Can be assigned to a club's squad for a period of time.

CREATE TABLE training_programmes (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  club_id           UUID          NOT NULL
                    REFERENCES clubs(id) ON DELETE CASCADE,
  created_by        UUID
                    REFERENCES profiles(id) ON DELETE SET NULL,
  name              TEXT          NOT NULL
                    CHECK (char_length(name) <= 100),
  description       TEXT
                    CHECK (description IS NULL OR char_length(description) <= 500),
  focus_category    TEXT          NOT NULL
                    CHECK (focus_category IN (
                      'technical','physical','mental','tactical',
                      'fitness','recovery','mixed'
                    )),
  -- Intensity affects fatigue accumulation and growth rate
  intensity         TEXT          NOT NULL DEFAULT 'normal'
                    CHECK (intensity IN ('light','normal','heavy','intense')),
  -- Sessions per week (1–7)
  sessions_per_week SMALLINT      NOT NULL DEFAULT 3
                    CHECK (sessions_per_week BETWEEN 1 AND 7),
  -- Which attributes this programme primarily develops (up to 4)
  target_attributes TEXT[]        NOT NULL DEFAULT '{}',
  -- Attribute growth bonus per week (decimal, added to base growth)
  growth_bonus      NUMERIC(4,3)  NOT NULL DEFAULT 0.050
                    CHECK (growth_bonus BETWEEN 0 AND 0.500),
  is_active         BOOLEAN       NOT NULL DEFAULT true,
  season_id         UUID          REFERENCES seasons(id) ON DELETE SET NULL,
  valid_from        DATE,
  valid_until       DATE,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_training_programmes_updated_at
  BEFORE UPDATE ON training_programmes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_training_programmes_audit
  AFTER INSERT OR UPDATE OR DELETE ON training_programmes
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE INDEX idx_tp_club       ON training_programmes(club_id, is_active);
CREATE INDEX idx_tp_season     ON training_programmes(season_id) WHERE season_id IS NOT NULL;

ALTER TABLE training_programmes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "training_programmes: club read"
  ON training_programmes FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
  );

CREATE POLICY "training_programmes: coach write"
  ON training_programmes FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
  );

CREATE POLICY "training_programmes: coach update"
  ON training_programmes FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
  );

-- ── 2b. training_sessions ────────────────────────────────────
-- A single scheduled training session for a club.

CREATE TABLE training_sessions (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  club_id           UUID          NOT NULL
                    REFERENCES clubs(id) ON DELETE CASCADE,
  programme_id      UUID
                    REFERENCES training_programmes(id) ON DELETE SET NULL,
  coach_id          UUID
                    REFERENCES coaches(id) ON DELETE SET NULL,
  session_date      DATE          NOT NULL,
  session_time      TIME,
  duration_minutes  SMALLINT      NOT NULL DEFAULT 90
                    CHECK (duration_minutes BETWEEN 15 AND 300),
  focus_category    TEXT          NOT NULL DEFAULT 'mixed'
                    CHECK (focus_category IN (
                      'technical','physical','mental','tactical',
                      'fitness','recovery','mixed'
                    )),
  intensity         TEXT          NOT NULL DEFAULT 'normal'
                    CHECK (intensity IN ('light','normal','heavy','intense')),
  target_attributes TEXT[]        NOT NULL DEFAULT '{}',
  -- Session notes by coach
  coach_notes       TEXT
                    CHECK (coach_notes IS NULL OR char_length(coach_notes) <= 1000),
  -- Computed after session: average performance of attendees
  avg_performance   NUMERIC(4,2),
  -- Status
  status            TEXT          NOT NULL DEFAULT 'scheduled'
                    CHECK (status IN ('scheduled','in_progress','completed','cancelled')),
  completed_at      TIMESTAMPTZ,
  season_id         UUID          REFERENCES seasons(id) ON DELETE SET NULL,
  created_by        UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_training_sessions_updated_at
  BEFORE UPDATE ON training_sessions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_training_sessions_audit
  AFTER INSERT OR UPDATE OR DELETE ON training_sessions
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE INDEX idx_ts_club_date   ON training_sessions(club_id, session_date DESC);
CREATE INDEX idx_ts_programme   ON training_sessions(programme_id) WHERE programme_id IS NOT NULL;
CREATE INDEX idx_ts_status      ON training_sessions(status, session_date DESC);
CREATE INDEX idx_ts_season      ON training_sessions(season_id, session_date DESC) WHERE season_id IS NOT NULL;

ALTER TABLE training_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "training_sessions: club read"
  ON training_sessions FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
    OR get_my_player_id() IN (
         SELECT player_id FROM player_training_attendance
         WHERE session_id = id
       )
  );

CREATE POLICY "training_sessions: coach write"
  ON training_sessions FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
  );

CREATE POLICY "training_sessions: coach update"
  ON training_sessions FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
  );

-- ── 2c. player_training_attendance ───────────────────────────
-- Records whether each player attended a training session.

CREATE TABLE player_training_attendance (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id      UUID          NOT NULL
                  REFERENCES training_sessions(id) ON DELETE CASCADE,
  player_id       UUID          NOT NULL
                  REFERENCES players(id) ON DELETE CASCADE,
  club_id         UUID          NOT NULL
                  REFERENCES clubs(id) ON DELETE CASCADE,
  status          TEXT          NOT NULL DEFAULT 'present'
                  CHECK (status IN (
                    'present','absent_excused','absent_unexcused',
                    'injured','late','partial'
                  )),
  -- Minutes actually trained (may be less than session duration)
  minutes_trained SMALLINT      NOT NULL DEFAULT 90
                  CHECK (minutes_trained BETWEEN 0 AND 300),
  absence_reason  TEXT
                  CHECK (absence_reason IS NULL OR char_length(absence_reason) <= 200),
  recorded_by     UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (session_id, player_id)
);

CREATE TRIGGER trg_pta_audit
  AFTER INSERT OR UPDATE OR DELETE ON player_training_attendance
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE INDEX idx_pta_session    ON player_training_attendance(session_id);
CREATE INDEX idx_pta_player     ON player_training_attendance(player_id, created_at DESC);
CREATE INDEX idx_pta_status     ON player_training_attendance(player_id, status);

ALTER TABLE player_training_attendance ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_training_attendance: authorised read"
  ON player_training_attendance FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
    OR player_id = get_my_player_id()
    OR is_guardian_of(player_id)
  );

CREATE POLICY "player_training_attendance: coach record"
  ON player_training_attendance FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
  );

CREATE POLICY "player_training_attendance: coach update"
  ON player_training_attendance FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(
          (SELECT club_id FROM training_sessions WHERE id = session_id LIMIT 1)))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(
          (SELECT club_id FROM training_sessions WHERE id = session_id LIMIT 1)))
  );

-- ── 2d. player_training_performance ──────────────────────────
-- Coach rates each player's performance in a training session.
-- Scale 1–10. Drives growth engine and morale.

CREATE TABLE player_training_performance (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id        UUID          NOT NULL
                    REFERENCES training_sessions(id) ON DELETE CASCADE,
  player_id         UUID          NOT NULL
                    REFERENCES players(id) ON DELETE CASCADE,
  club_id           UUID          NOT NULL
                    REFERENCES clubs(id) ON DELETE CASCADE,
  -- Performance rating 1–10 for this session
  rating            NUMERIC(3,1)  NOT NULL
                    CHECK (rating BETWEEN 1.0 AND 10.0),
  -- Effort rating 1–10
  effort_rating     NUMERIC(3,1)
                    CHECK (effort_rating IS NULL OR effort_rating BETWEEN 1.0 AND 10.0),
  -- Technical quality observed
  technical_quality NUMERIC(3,1)
                    CHECK (technical_quality IS NULL OR technical_quality BETWEEN 1.0 AND 10.0),
  -- Coach observations (free text)
  coach_notes       TEXT
                    CHECK (coach_notes IS NULL OR char_length(coach_notes) <= 500),
  -- Whether player showed exceptional or concerning behaviour
  standout_positive BOOLEAN       NOT NULL DEFAULT false,
  standout_negative BOOLEAN       NOT NULL DEFAULT false,
  rated_by          UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (session_id, player_id)
);

CREATE TRIGGER trg_ptp_updated_at
  BEFORE UPDATE ON player_training_performance
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_ptp_audit
  AFTER INSERT OR UPDATE OR DELETE ON player_training_performance
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE INDEX idx_ptp_session    ON player_training_performance(session_id);
CREATE INDEX idx_ptp_player     ON player_training_performance(player_id, created_at DESC);
CREATE INDEX idx_ptp_rating     ON player_training_performance(player_id, rating DESC);

ALTER TABLE player_training_performance ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_training_performance: authorised read"
  ON player_training_performance FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
    OR player_id = get_my_player_id()
    OR is_guardian_of(player_id)
  );

CREATE POLICY "player_training_performance: coach write"
  ON player_training_performance FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
  );

CREATE POLICY "player_training_performance: coach update"
  ON player_training_performance FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'     AND is_coach_for_club(club_id))
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 3: HIDDEN ATTRIBUTES
-- ════════════════════════════════════════════════════════════
-- FM-style personality attributes that influence development
-- but are never shown directly to the public.
-- Range 1–20. Assessed only by coaches and the AI engine.
-- Visibility: coach, club_admin, developer only.

CREATE TABLE player_hidden_attributes (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id         UUID          NOT NULL UNIQUE
                    REFERENCES players(id) ON DELETE CASCADE,
  -- Core personality traits (1–20)
  professionalism   SMALLINT      NOT NULL DEFAULT 10
                    CHECK (professionalism BETWEEN 1 AND 20),
  ambition          SMALLINT      NOT NULL DEFAULT 10
                    CHECK (ambition BETWEEN 1 AND 20),
  loyalty           SMALLINT      NOT NULL DEFAULT 10
                    CHECK (loyalty BETWEEN 1 AND 20),
  temperament       SMALLINT      NOT NULL DEFAULT 10
                    CHECK (temperament BETWEEN 1 AND 20),
  -- Consistency: how reliably player performs at their attribute level
  consistency       SMALLINT      NOT NULL DEFAULT 10
                    CHECK (consistency BETWEEN 1 AND 20),
  -- Injury proneness: higher = more likely to get injured
  injury_proneness  SMALLINT      NOT NULL DEFAULT 10
                    CHECK (injury_proneness BETWEEN 1 AND 20),
  -- Pressure handling (how attributes hold up in big matches)
  pressure_handling SMALLINT      NOT NULL DEFAULT 10
                    CHECK (pressure_handling BETWEEN 1 AND 20),
  -- Confidence (self-belief, bounces back from poor form)
  confidence        SMALLINT      NOT NULL DEFAULT 10
                    CHECK (confidence BETWEEN 1 AND 20),
  -- Source: how were these values determined
  assessed_by_type  TEXT          NOT NULL DEFAULT 'coach'
                    CHECK (assessed_by_type IN ('coach','ai','manual')),
  assessed_by       UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  assessed_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by        UUID          REFERENCES profiles(id) ON DELETE SET NULL
);

CREATE TRIGGER trg_pha_updated_at
  BEFORE UPDATE ON player_hidden_attributes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_pha_audit
  AFTER INSERT OR UPDATE OR DELETE ON player_hidden_attributes
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE INDEX idx_pha_professionalism ON player_hidden_attributes(professionalism DESC);
CREATE INDEX idx_pha_ambition        ON player_hidden_attributes(ambition DESC);
CREATE INDEX idx_pha_injury          ON player_hidden_attributes(injury_proneness DESC);

ALTER TABLE player_hidden_attributes ENABLE ROW LEVEL SECURITY;

-- Hidden attributes are NEVER publicly visible
CREATE POLICY "player_hidden_attributes: restricted read"
  ON player_hidden_attributes FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM coaches WHERE profile_id = auth.uid()
              AND is_active = true
          )
        ))
  );

CREATE POLICY "player_hidden_attributes: coach write"
  ON player_hidden_attributes FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
          )
        ))
  );

CREATE POLICY "player_hidden_attributes: coach update"
  ON player_hidden_attributes FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
          )
        ))
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 4: GROWTH ENGINE — DEVELOPMENT CURVES
-- ════════════════════════════════════════════════════════════
-- Stores per-age growth multipliers for each attribute category.
-- Used by compute_attribute_growth() to scale training gains.
-- Technical attributes develop fastest at 16-21.
-- Physical peaks at 22-26 then declines.
-- Mental and Tactical keep developing into late 20s.

CREATE TABLE player_development_curves (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  age             SMALLINT      NOT NULL CHECK (age BETWEEN 14 AND 45),
  category        TEXT          NOT NULL
                  CHECK (category IN ('technical','physical','mental','tactical')),
  -- Growth multiplier (1.0 = normal, 1.5 = fast, 0.5 = slow, <0 = decline)
  growth_multiplier NUMERIC(4,2) NOT NULL,
  -- Decline multiplier (applied when attributes decay without training)
  decay_multiplier  NUMERIC(4,2) NOT NULL DEFAULT 0.00,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (age, category)
);

ALTER TABLE player_development_curves ENABLE ROW LEVEL SECURITY;
CREATE POLICY "player_development_curves: public read"
  ON player_development_curves FOR SELECT USING (true);
CREATE POLICY "player_development_curves: developer write"
  ON player_development_curves FOR ALL
  USING (get_my_role() = 'developer')
  WITH CHECK (get_my_role() = 'developer');

-- ── Seed development curves for all ages 14-45 ───────────────

INSERT INTO player_development_curves (age, category, growth_multiplier, decay_multiplier)
SELECT age, category, growth_mult, decay_mult
FROM (VALUES
  -- Technical: peaks 17-22, slow decline after 30
  (14,'technical',1.30,0.00),(15,'technical',1.45,0.00),(16,'technical',1.60,0.00),
  (17,'technical',1.70,0.00),(18,'technical',1.75,0.00),(19,'technical',1.70,0.00),
  (20,'technical',1.60,0.00),(21,'technical',1.50,0.00),(22,'technical',1.35,0.00),
  (23,'technical',1.20,0.00),(24,'technical',1.10,0.00),(25,'technical',1.00,0.00),
  (26,'technical',0.90,0.00),(27,'technical',0.80,0.00),(28,'technical',0.70,0.00),
  (29,'technical',0.60,0.00),(30,'technical',0.50,0.02),(31,'technical',0.40,0.04),
  (32,'technical',0.30,0.06),(33,'technical',0.20,0.08),(34,'technical',0.10,0.10),
  (35,'technical',0.00,0.12),(36,'technical',0.00,0.14),(37,'technical',0.00,0.16),
  (38,'technical',0.00,0.18),(39,'technical',0.00,0.20),(40,'technical',0.00,0.22),
  (41,'technical',0.00,0.24),(42,'technical',0.00,0.26),(43,'technical',0.00,0.28),
  (44,'technical',0.00,0.30),(45,'technical',0.00,0.32),

  -- Physical: fast growth 14-22, peak 22-26, decline after 28
  (14,'physical',1.40,0.00),(15,'physical',1.55,0.00),(16,'physical',1.65,0.00),
  (17,'physical',1.70,0.00),(18,'physical',1.75,0.00),(19,'physical',1.80,0.00),
  (20,'physical',1.85,0.00),(21,'physical',1.85,0.00),(22,'physical',1.80,0.00),
  (23,'physical',1.70,0.00),(24,'physical',1.55,0.00),(25,'physical',1.35,0.00),
  (26,'physical',1.10,0.00),(27,'physical',0.85,0.00),(28,'physical',0.60,0.05),
  (29,'physical',0.35,0.08),(30,'physical',0.15,0.12),(31,'physical',0.00,0.16),
  (32,'physical',0.00,0.20),(33,'physical',0.00,0.25),(34,'physical',0.00,0.30),
  (35,'physical',0.00,0.35),(36,'physical',0.00,0.40),(37,'physical',0.00,0.44),
  (38,'physical',0.00,0.48),(39,'physical',0.00,0.52),(40,'physical',0.00,0.56),
  (41,'physical',0.00,0.60),(42,'physical',0.00,0.64),(43,'physical',0.00,0.68),
  (44,'physical',0.00,0.72),(45,'physical',0.00,0.76),

  -- Mental: grows throughout career, peaks 26-32
  (14,'mental',0.90,0.00),(15,'mental',1.00,0.00),(16,'mental',1.10,0.00),
  (17,'mental',1.15,0.00),(18,'mental',1.20,0.00),(19,'mental',1.25,0.00),
  (20,'mental',1.30,0.00),(21,'mental',1.35,0.00),(22,'mental',1.40,0.00),
  (23,'mental',1.45,0.00),(24,'mental',1.50,0.00),(25,'mental',1.55,0.00),
  (26,'mental',1.55,0.00),(27,'mental',1.50,0.00),(28,'mental',1.45,0.00),
  (29,'mental',1.35,0.00),(30,'mental',1.25,0.00),(31,'mental',1.10,0.00),
  (32,'mental',0.95,0.00),(33,'mental',0.80,0.00),(34,'mental',0.65,0.00),
  (35,'mental',0.50,0.02),(36,'mental',0.35,0.04),(37,'mental',0.20,0.06),
  (38,'mental',0.10,0.08),(39,'mental',0.05,0.10),(40,'mental',0.00,0.12),
  (41,'mental',0.00,0.14),(42,'mental',0.00,0.16),(43,'mental',0.00,0.18),
  (44,'mental',0.00,0.20),(45,'mental',0.00,0.22),

  -- Tactical: slow growth, peaks 24-30 (experience-dependent)
  (14,'tactical',0.80,0.00),(15,'tactical',0.90,0.00),(16,'tactical',1.00,0.00),
  (17,'tactical',1.05,0.00),(18,'tactical',1.10,0.00),(19,'tactical',1.15,0.00),
  (20,'tactical',1.20,0.00),(21,'tactical',1.25,0.00),(22,'tactical',1.30,0.00),
  (23,'tactical',1.35,0.00),(24,'tactical',1.40,0.00),(25,'tactical',1.45,0.00),
  (26,'tactical',1.45,0.00),(27,'tactical',1.40,0.00),(28,'tactical',1.35,0.00),
  (29,'tactical',1.25,0.00),(30,'tactical',1.15,0.00),(31,'tactical',1.00,0.00),
  (32,'tactical',0.85,0.00),(33,'tactical',0.70,0.00),(34,'tactical',0.55,0.00),
  (35,'tactical',0.40,0.02),(36,'tactical',0.25,0.04),(37,'tactical',0.15,0.06),
  (38,'tactical',0.08,0.08),(39,'tactical',0.04,0.10),(40,'tactical',0.00,0.12),
  (41,'tactical',0.00,0.14),(42,'tactical',0.00,0.16),(43,'tactical',0.00,0.18),
  (44,'tactical',0.00,0.20),(45,'tactical',0.00,0.22)
) AS t(age, category, growth_mult, decay_mult);

-- ════════════════════════════════════════════════════════════
-- SECTION 5: FITNESS ENGINE
-- ════════════════════════════════════════════════════════════

CREATE TABLE player_fitness_snapshots (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id         UUID          NOT NULL
                    REFERENCES players(id) ON DELETE CASCADE,
  snapshot_date     DATE          NOT NULL DEFAULT CURRENT_DATE,
  -- Fitness components (0–100)
  match_sharpness   SMALLINT      NOT NULL DEFAULT 70
                    CHECK (match_sharpness BETWEEN 0 AND 100),
  fatigue_level     SMALLINT      NOT NULL DEFAULT 0
                    CHECK (fatigue_level BETWEEN 0 AND 100),
  -- Overall condition (inverse of fatigue, weighted by sharpness)
  condition         SMALLINT      NOT NULL DEFAULT 80
                    CHECK (condition BETWEEN 0 AND 100),
  -- Training load category
  training_load     TEXT          NOT NULL DEFAULT 'normal'
                    CHECK (training_load IN ('rest','light','normal','heavy','intense')),
  -- Days since last competitive match
  days_since_match  SMALLINT      NOT NULL DEFAULT 7
                    CHECK (days_since_match BETWEEN 0 AND 365),
  -- Days since last training session
  days_since_training SMALLINT    NOT NULL DEFAULT 1
                    CHECK (days_since_training BETWEEN 0 AND 365),
  -- Number of matches played in last 14 days (congestion indicator)
  matches_last_14d  SMALLINT      NOT NULL DEFAULT 0
                    CHECK (matches_last_14d BETWEEN 0 AND 14),
  -- Total minutes played in last 7 days
  minutes_last_7d   SMALLINT      NOT NULL DEFAULT 0
                    CHECK (minutes_last_7d BETWEEN 0 AND 630),
  trigger_source    TEXT          NOT NULL DEFAULT 'nightly'
                    CHECK (trigger_source IN ('match','training','nightly','manual')),
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (player_id, snapshot_date)
);

CREATE INDEX idx_fitness_player_date
  ON player_fitness_snapshots(player_id, snapshot_date DESC);
CREATE INDEX idx_fitness_condition
  ON player_fitness_snapshots(condition) WHERE snapshot_date = CURRENT_DATE;

ALTER TABLE player_fitness_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_fitness_snapshots: authorised read"
  ON player_fitness_snapshots FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
          )
        ))
    OR player_id = get_my_player_id()
    OR is_guardian_of(player_id)
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 6: MORALE ENGINE
-- ════════════════════════════════════════════════════════════

CREATE TABLE player_morale_snapshots (
  id                        UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id                 UUID          NOT NULL
                            REFERENCES players(id) ON DELETE CASCADE,
  snapshot_date             DATE          NOT NULL DEFAULT CURRENT_DATE,
  -- Overall morale (0–100)
  morale_score              SMALLINT      NOT NULL DEFAULT 70
                            CHECK (morale_score BETWEEN 0 AND 100),
  morale_band               TEXT          NOT NULL DEFAULT 'content'
                            CHECK (morale_band IN (
                              'ecstatic','happy','content','unsettled','unhappy','miserable'
                            )),
  -- Component scores (0–100 each)
  playing_time_satisfaction SMALLINT      NOT NULL DEFAULT 70
                            CHECK (playing_time_satisfaction BETWEEN 0 AND 100),
  training_satisfaction     SMALLINT      NOT NULL DEFAULT 70
                            CHECK (training_satisfaction BETWEEN 0 AND 100),
  form_satisfaction         SMALLINT      NOT NULL DEFAULT 70
                            CHECK (form_satisfaction BETWEEN 0 AND 100),
  team_harmony              SMALLINT      NOT NULL DEFAULT 70
                            CHECK (team_harmony BETWEEN 0 AND 100),
  -- Minutes played in last 5 matches (playing time proxy)
  minutes_last_5_matches    SMALLINT      NOT NULL DEFAULT 450
                            CHECK (minutes_last_5_matches BETWEEN 0 AND 450),
  -- Matches started in last 5
  starts_last_5             SMALLINT      NOT NULL DEFAULT 5
                            CHECK (starts_last_5 BETWEEN 0 AND 5),
  -- Recent form rating (average match rating last 3 matches, × 10)
  recent_form               SMALLINT,
  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (player_id, snapshot_date)
);

CREATE INDEX idx_morale_player_date
  ON player_morale_snapshots(player_id, snapshot_date DESC);
CREATE INDEX idx_morale_score
  ON player_morale_snapshots(morale_score) WHERE snapshot_date = CURRENT_DATE;

ALTER TABLE player_morale_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_morale_snapshots: authorised read"
  ON player_morale_snapshots FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
          )
        ))
    OR player_id = get_my_player_id()
    OR is_guardian_of(player_id)
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 7: INJURY ENGINE (extension)
-- player_injuries already exists from Phase 3.
-- We add a risk profile table and a lightweight injury log
-- specifically for development-engine-triggered injuries
-- (e.g. from overtraining, high fatigue).
-- ════════════════════════════════════════════════════════════

CREATE TABLE player_injury_risk_profiles (
  id                    UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id             UUID          NOT NULL UNIQUE
                        REFERENCES players(id) ON DELETE CASCADE,
  -- Overall risk level
  risk_level            TEXT          NOT NULL DEFAULT 'medium'
                        CHECK (risk_level IN ('low','medium','high','very_high')),
  risk_score            SMALLINT      NOT NULL DEFAULT 50
                        CHECK (risk_score BETWEEN 0 AND 100),
  -- Contributing factors (all 0–100)
  fatigue_contribution  SMALLINT      NOT NULL DEFAULT 0
                        CHECK (fatigue_contribution BETWEEN 0 AND 100),
  workload_contribution SMALLINT      NOT NULL DEFAULT 0
                        CHECK (workload_contribution BETWEEN 0 AND 100),
  history_contribution  SMALLINT      NOT NULL DEFAULT 0
                        CHECK (history_contribution BETWEEN 0 AND 100),
  age_contribution      SMALLINT      NOT NULL DEFAULT 0
                        CHECK (age_contribution BETWEEN 0 AND 100),
  -- Body part most at risk (based on injury history)
  vulnerable_body_part  TEXT,
  -- Number of injuries in last 12 months
  injuries_last_12m     SMALLINT      NOT NULL DEFAULT 0
                        CHECK (injuries_last_12m BETWEEN 0 AND 52),
  -- Total days injured in last 12 months
  days_injured_last_12m SMALLINT      NOT NULL DEFAULT 0
                        CHECK (days_injured_last_12m BETWEEN 0 AND 365),
  computed_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_injury_risk_updated_at
  BEFORE UPDATE ON player_injury_risk_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_injury_risk_level
  ON player_injury_risk_profiles(risk_level, risk_score DESC);

ALTER TABLE player_injury_risk_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_injury_risk_profiles: authorised read"
  ON player_injury_risk_profiles FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
          )
        ))
    OR player_id = get_my_player_id()
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 8: POSITION RETRAINING ENGINE
-- ════════════════════════════════════════════════════════════

CREATE TABLE player_position_familiarity (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id       UUID          NOT NULL
                  REFERENCES players(id) ON DELETE CASCADE,
  -- Position code: matches position_roles.primary_pos values
  position_code   TEXT          NOT NULL,
  position_label  TEXT          NOT NULL,
  -- Familiarity level
  familiarity     TEXT          NOT NULL DEFAULT 'learning'
                  CHECK (familiarity IN ('natural','accomplished','competent','learning','unfamiliar')),
  -- Percentage mastery (0–100)
  familiarity_pct SMALLINT      NOT NULL DEFAULT 0
                  CHECK (familiarity_pct BETWEEN 0 AND 100),
  -- How many matches played in this position
  matches_in_pos  SMALLINT      NOT NULL DEFAULT 0
                  CHECK (matches_in_pos BETWEEN 0 AND 9999),
  -- How many training sessions specifically for this position
  training_in_pos SMALLINT      NOT NULL DEFAULT 0
                  CHECK (training_in_pos BETWEEN 0 AND 9999),
  -- Whether this is the player's natural (registered) position
  is_natural      BOOLEAN       NOT NULL DEFAULT false,
  last_played     DATE,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (player_id, position_code)
);

CREATE TRIGGER trg_ppf_updated_at
  BEFORE UPDATE ON player_position_familiarity
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_ppf_audit
  AFTER INSERT OR UPDATE OR DELETE ON player_position_familiarity
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE INDEX idx_ppf_player    ON player_position_familiarity(player_id);
CREATE INDEX idx_ppf_natural   ON player_position_familiarity(player_id, is_natural)
  WHERE is_natural = true;
CREATE INDEX idx_ppf_familiarity ON player_position_familiarity(familiarity, familiarity_pct DESC);

ALTER TABLE player_position_familiarity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_position_familiarity: public read"
  ON player_position_familiarity FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder','technical_assessor')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
          )
        ))
    OR player_id = get_my_player_id()
    OR is_guardian_of(player_id)
  );

CREATE POLICY "player_position_familiarity: system write"
  ON player_position_familiarity FOR INSERT
  WITH CHECK (
    get_my_role() IN ('developer','league_admin')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
          )
        ))
  );

CREATE POLICY "player_position_familiarity: system update"
  ON player_position_familiarity FOR UPDATE
  USING (
    get_my_role() IN ('developer','league_admin')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
          )
        ))
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 9: DEVELOPMENT PROJECTION ENGINE
-- ════════════════════════════════════════════════════════════

CREATE TABLE player_development_projections (
  id                    UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id             UUID          NOT NULL
                        REFERENCES players(id) ON DELETE CASCADE,
  computed_date         DATE          NOT NULL DEFAULT CURRENT_DATE,
  -- Current state snapshot
  current_dna           SMALLINT,
  current_age           SMALLINT,
  -- Projections
  projected_dna_18      SMALLINT      CHECK (projected_dna_18  IS NULL OR projected_dna_18  BETWEEN 1 AND 100),
  projected_dna_21      SMALLINT      CHECK (projected_dna_21  IS NULL OR projected_dna_21  BETWEEN 1 AND 100),
  projected_dna_peak    SMALLINT      CHECK (projected_dna_peak IS NULL OR projected_dna_peak BETWEEN 1 AND 100),
  projected_peak_age    SMALLINT      CHECK (projected_peak_age IS NULL OR projected_peak_age BETWEEN 14 AND 40),
  -- Confidence in projection (0–100, low if insufficient data)
  projection_confidence SMALLINT      NOT NULL DEFAULT 50
                        CHECK (projection_confidence BETWEEN 0 AND 100),
  -- Development phase
  development_phase     TEXT          NOT NULL DEFAULT 'developing'
                        CHECK (development_phase IN (
                          'emerging','developing','peak','declining','veteran'
                        )),
  -- Key factors driving the projection
  limiting_factor       TEXT,         -- e.g. 'physical_ceiling','consistency','injury_history'
  accelerating_factor   TEXT,         -- e.g. 'high_ambition','excellent_training'
  -- Wonderkid flag (high potential under 21)
  is_wonderkid          BOOLEAN       NOT NULL DEFAULT false,
  wonderkid_score       SMALLINT      CHECK (wonderkid_score IS NULL OR wonderkid_score BETWEEN 0 AND 100),
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (player_id, computed_date)
);

CREATE INDEX idx_dp_player_date
  ON player_development_projections(player_id, computed_date DESC);
CREATE INDEX idx_dp_wonderkid
  ON player_development_projections(is_wonderkid, wonderkid_score DESC)
  WHERE is_wonderkid = true;
CREATE INDEX idx_dp_peak_dna
  ON player_development_projections(projected_dna_peak DESC NULLS LAST);

ALTER TABLE player_development_projections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_development_projections: authorised read"
  ON player_development_projections FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder','technical_assessor')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
          )
        ))
    OR player_id = get_my_player_id()
    OR is_guardian_of(player_id)
    -- Public: only current DNA and wonderkid flag visible (via view filtering)
    OR EXISTS (
        SELECT 1 FROM players p WHERE p.id = player_id AND p.is_passport_public = true
      )
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 10: CORE FUNCTIONS
-- ════════════════════════════════════════════════════════════

-- ── 10a. compute_weekly_training_score() ─────────────────────

CREATE OR REPLACE FUNCTION compute_weekly_training_score(
  p_player_id UUID,
  p_week_start DATE DEFAULT DATE_TRUNC('week', CURRENT_DATE)::DATE
)
RETURNS NUMERIC(4,2)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_end    DATE := p_week_start + 7;
  v_attended    INTEGER;
  v_sessions    INTEGER;
  v_avg_perf    NUMERIC;
  v_avg_effort  NUMERIC;
  v_score       NUMERIC;
BEGIN
  -- Count sessions scheduled for this club this week
  SELECT
    COUNT(DISTINCT ts.id),
    COUNT(DISTINCT CASE WHEN pta.status = 'present' THEN ts.id END)
  INTO v_sessions, v_attended
  FROM training_sessions ts
  JOIN players p ON p.club_id = ts.club_id
  LEFT JOIN player_training_attendance pta
    ON pta.session_id = ts.id AND pta.player_id = p_player_id
  WHERE p.id = p_player_id
    AND ts.session_date >= p_week_start
    AND ts.session_date <  v_week_end
    AND ts.status = 'completed';

  -- Average performance and effort ratings for the week
  SELECT
    COALESCE(AVG(ptp.rating),       5.0),
    COALESCE(AVG(ptp.effort_rating),5.0)
  INTO v_avg_perf, v_avg_effort
  FROM player_training_performance ptp
  JOIN training_sessions ts ON ts.id = ptp.session_id
  WHERE ptp.player_id = p_player_id
    AND ts.session_date >= p_week_start
    AND ts.session_date <  v_week_end;

  IF v_sessions = 0 THEN RETURN 0; END IF;

  -- Score: attendance (50%) + performance (30%) + effort (20%)
  v_score :=
    (v_attended::NUMERIC / v_sessions * 100 * 0.50)
    + (v_avg_perf  / 10.0 * 100 * 0.30)
    + (v_avg_effort / 10.0 * 100 * 0.20);

  RETURN ROUND(GREATEST(0, LEAST(100, v_score)), 2);
END;
$$;

GRANT EXECUTE ON FUNCTION compute_weekly_training_score(UUID, DATE) TO authenticated;

-- ── 10b. compute_attribute_growth() ──────────────────────────
-- Calculates how much each attribute should grow this week
-- based on training, age curve, coach influence, and professionalism.

CREATE OR REPLACE FUNCTION compute_attribute_growth(
  p_player_id  UUID,
  p_attr_code  TEXT,
  p_week_start DATE DEFAULT DATE_TRUNC('week', CURRENT_DATE)::DATE
)
RETURNS NUMERIC(5,4)  -- weekly growth delta (may be negative = decay)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_age               INTEGER;
  v_category          TEXT;
  v_growth_mult       NUMERIC;
  v_decay_mult        NUMERIC;
  v_training_score    NUMERIC;
  v_professionalism   NUMERIC := 10;
  v_ambition          NUMERIC := 10;
  v_current_val       NUMERIC := 10;
  v_base_growth       NUMERIC := 0.050;  -- base weekly growth rate
  v_total_growth      NUMERIC;
  v_coach_bonus       NUMERIC := 0;
  v_match_bonus       NUMERIC := 0;
  v_matches_this_week INTEGER;
BEGIN
  -- Player age
  SELECT EXTRACT(YEAR FROM AGE(date_of_birth))::INTEGER INTO v_age
  FROM players WHERE id = p_player_id;

  v_age := COALESCE(GREATEST(14, LEAST(45, v_age)), 20);

  -- Attribute category
  SELECT category INTO v_category
  FROM attribute_definitions WHERE code = p_attr_code;

  IF v_category IS NULL THEN RETURN 0; END IF;

  -- Age-based growth and decay multipliers
  SELECT growth_multiplier, decay_multiplier
  INTO v_growth_mult, v_decay_mult
  FROM player_development_curves
  WHERE age = v_age AND category = v_category;

  v_growth_mult := COALESCE(v_growth_mult, 0.5);
  v_decay_mult  := COALESCE(v_decay_mult,  0.0);

  -- Current attribute value
  SELECT COALESCE(current_value, 10) INTO v_current_val
  FROM player_attributes WHERE player_id = p_player_id AND attribute_code = p_attr_code;

  -- Hidden attributes influence
  SELECT
    COALESCE(professionalism, 10),
    COALESCE(ambition, 10)
  INTO v_professionalism, v_ambition
  FROM player_hidden_attributes WHERE player_id = p_player_id;

  -- Weekly training score
  v_training_score := compute_weekly_training_score(p_player_id, p_week_start);

  -- Training score scales base growth (full attendance + excellent perf = 1.5x)
  v_base_growth := v_base_growth * (v_training_score / 100.0 * 1.5 + 0.25);

  -- Professionalism multiplier (1–20 maps to 0.70–1.30)
  v_base_growth := v_base_growth * (0.70 + (v_professionalism::NUMERIC / 20.0) * 0.60);

  -- Ambition multiplier for young players (<23)
  IF v_age < 23 THEN
    v_base_growth := v_base_growth * (0.80 + (v_ambition::NUMERIC / 20.0) * 0.40);
  END IF;

  -- Apply age curve multiplier
  v_total_growth := v_base_growth * v_growth_mult;

  -- Match experience bonus (matches played this week boost tactical+mental)
  SELECT COUNT(*) INTO v_matches_this_week
  FROM match_lineups ml
  JOIN fixtures f ON f.id = ml.fixture_id
  WHERE ml.player_id  = p_player_id
    AND f.match_date  >= p_week_start
    AND f.match_date  <  p_week_start + 7
    AND f.status      = 'completed';

  IF v_matches_this_week > 0 AND v_category IN ('mental','tactical') THEN
    v_match_bonus := 0.015 * v_matches_this_week;
    v_total_growth := v_total_growth + v_match_bonus;
  END IF;

  -- Regression-to-mean: harder to grow high values
  v_total_growth := v_total_growth * (1 - (v_current_val - 1)::NUMERIC / 38.0);

  -- Decay: if no training this week and attribute declines naturally
  IF v_training_score < 20 AND v_decay_mult > 0 THEN
    v_total_growth := v_total_growth - (v_decay_mult * 0.1);
  END IF;

  -- Cap: max ±1.0 per week
  v_total_growth := GREATEST(-1.0, LEAST(1.0, v_total_growth));

  RETURN ROUND(v_total_growth, 4);
END;
$$;

GRANT EXECUTE ON FUNCTION compute_attribute_growth(UUID, TEXT, DATE) TO authenticated;

-- ── 10c. update_fitness_after_match() ────────────────────────

CREATE OR REPLACE FUNCTION update_fitness_after_match(
  p_player_id    UUID,
  p_minutes      INTEGER,
  p_match_date   DATE DEFAULT CURRENT_DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prev            RECORD;
  v_fatigue_gain    SMALLINT;
  v_sharpness_gain  SMALLINT;
  v_new_fatigue     SMALLINT;
  v_new_sharpness   SMALLINT;
  v_new_condition   SMALLINT;
  v_matches_14d     SMALLINT;
BEGIN
  -- Fetch previous fitness state
  SELECT match_sharpness, fatigue_level, condition, matches_last_14d
  INTO v_prev
  FROM player_fitness_snapshots
  WHERE player_id = p_player_id
  ORDER BY snapshot_date DESC LIMIT 1;

  v_prev.match_sharpness  := COALESCE(v_prev.match_sharpness, 60);
  v_prev.fatigue_level    := COALESCE(v_prev.fatigue_level,   10);
  v_prev.matches_last_14d := COALESCE(v_prev.matches_last_14d, 0);

  -- Fatigue from match: scales with minutes played
  v_fatigue_gain   := LEAST(35, ROUND(p_minutes::NUMERIC / 90.0 * 30))::SMALLINT;

  -- Sharpness from match: playing improves sharpness
  v_sharpness_gain := LEAST(15, ROUND(p_minutes::NUMERIC / 90.0 * 12))::SMALLINT;

  -- Congestion penalty: more matches in 14 days → more fatigue
  v_matches_14d := LEAST(14, v_prev.matches_last_14d + 1)::SMALLINT;
  IF v_matches_14d >= 3 THEN
    v_fatigue_gain := LEAST(50, v_fatigue_gain + (v_matches_14d - 2) * 5)::SMALLINT;
  END IF;

  v_new_fatigue   := LEAST(100, v_prev.fatigue_level + v_fatigue_gain)::SMALLINT;
  v_new_sharpness := LEAST(100, v_prev.match_sharpness + v_sharpness_gain)::SMALLINT;
  v_new_condition := GREATEST(0, 100 - v_new_fatigue
                    + ROUND(v_new_sharpness * 0.3))::SMALLINT;
  v_new_condition := LEAST(100, v_new_condition)::SMALLINT;

  INSERT INTO player_fitness_snapshots (
    player_id, snapshot_date,
    match_sharpness, fatigue_level, condition,
    training_load, days_since_match, days_since_training,
    matches_last_14d, trigger_source
  ) VALUES (
    p_player_id, p_match_date,
    v_new_sharpness, v_new_fatigue, v_new_condition,
    'heavy', 0,
    COALESCE(v_prev.match_sharpness, 1),  -- proxy
    v_matches_14d, 'match'
  )
  ON CONFLICT (player_id, snapshot_date) DO UPDATE SET
    match_sharpness   = EXCLUDED.match_sharpness,
    fatigue_level     = EXCLUDED.fatigue_level,
    condition         = EXCLUDED.condition,
    matches_last_14d  = EXCLUDED.matches_last_14d,
    trigger_source    = 'match';

  -- Denormalise to players
  UPDATE players SET
    match_sharpness  = v_new_sharpness,
    fatigue_level    = v_new_fatigue,
    fitness_condition = v_new_condition,
    days_since_match = 0,
    updated_at       = NOW()
  WHERE id = p_player_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_fitness_after_match(UUID, INTEGER, DATE) TO authenticated;

-- ── 10d. update_fitness_nightly() ────────────────────────────
-- Runs each night. Applies fatigue recovery and sharpness decay
-- for players who did not play or train.

CREATE OR REPLACE FUNCTION update_fitness_nightly(p_player_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prev          RECORD;
  v_trained_today BOOLEAN := false;
  v_played_today  BOOLEAN := false;
  v_fatigue_recovery  SMALLINT := 8;   -- daily recovery when resting
  v_sharpness_decay   SMALLINT := 3;   -- daily sharpness loss when not playing
  v_new_fatigue       SMALLINT;
  v_new_sharpness     SMALLINT;
  v_new_condition     SMALLINT;
BEGIN
  SELECT match_sharpness, fatigue_level, condition, days_since_match,
         days_since_training, training_load
  INTO v_prev
  FROM player_fitness_snapshots
  WHERE player_id = p_player_id
  ORDER BY snapshot_date DESC LIMIT 1;

  v_prev.match_sharpness    := COALESCE(v_prev.match_sharpness, 60);
  v_prev.fatigue_level      := COALESCE(v_prev.fatigue_level,   15);
  v_prev.days_since_match   := COALESCE(v_prev.days_since_match, 7) + 1;
  v_prev.days_since_training:= COALESCE(v_prev.days_since_training, 1) + 1;

  -- Did player train today?
  SELECT EXISTS (
    SELECT 1 FROM player_training_attendance pta
    JOIN training_sessions ts ON ts.id = pta.session_id
    WHERE pta.player_id = p_player_id
      AND ts.session_date = CURRENT_DATE
      AND pta.status = 'present'
  ) INTO v_trained_today;

  -- Did player play today?
  SELECT EXISTS (
    SELECT 1 FROM match_lineups ml
    JOIN fixtures f ON f.id = ml.fixture_id
    WHERE ml.player_id = p_player_id
      AND f.match_date = CURRENT_DATE
      AND f.status = 'completed'
  ) INTO v_played_today;

  -- Training restores sharpness, adds some fatigue
  IF v_trained_today THEN
    v_sharpness_decay    := -5;       -- training actually increases sharpness
    v_fatigue_recovery   := -6;       -- training adds fatigue, net lower recovery
    v_prev.days_since_training := 0;
  END IF;

  -- Recovery: reduce fatigue
  v_new_fatigue := GREATEST(0,
    v_prev.fatigue_level - v_fatigue_recovery
  )::SMALLINT;

  -- Sharpness decays when not playing
  IF NOT v_played_today THEN
    IF v_prev.days_since_match > 14 THEN
      v_sharpness_decay := v_sharpness_decay + 2;  -- accelerated loss if very idle
    END IF;
    v_new_sharpness := GREATEST(20, v_prev.match_sharpness - v_sharpness_decay)::SMALLINT;
  ELSE
    v_new_sharpness := v_prev.match_sharpness; -- updated by update_fitness_after_match
  END IF;

  v_new_condition := GREATEST(0, LEAST(100,
    100 - v_new_fatigue + ROUND(v_new_sharpness * 0.3)
  ))::SMALLINT;

  INSERT INTO player_fitness_snapshots (
    player_id, snapshot_date,
    match_sharpness, fatigue_level, condition,
    training_load, days_since_match, days_since_training,
    matches_last_14d, trigger_source
  ) VALUES (
    p_player_id, CURRENT_DATE,
    v_new_sharpness, v_new_fatigue, v_new_condition,
    CASE WHEN v_trained_today THEN 'normal' ELSE 'rest' END,
    v_prev.days_since_match,
    v_prev.days_since_training,
    COALESCE(v_prev.match_sharpness, 0),  -- reused as proxy
    'nightly'
  )
  ON CONFLICT (player_id, snapshot_date) DO UPDATE SET
    match_sharpness     = EXCLUDED.match_sharpness,
    fatigue_level       = EXCLUDED.fatigue_level,
    condition           = EXCLUDED.condition,
    training_load       = EXCLUDED.training_load,
    days_since_match    = EXCLUDED.days_since_match,
    days_since_training = EXCLUDED.days_since_training;

  UPDATE players SET
    match_sharpness   = v_new_sharpness,
    fatigue_level     = v_new_fatigue,
    fitness_condition = v_new_condition,
    days_since_match  = v_prev.days_since_match,
    last_training_date = CASE WHEN v_trained_today THEN CURRENT_DATE
                              ELSE players.last_training_date END,
    updated_at        = NOW()
  WHERE id = p_player_id;
END;
$$;

GRANT EXECUTE ON FUNCTION update_fitness_nightly(UUID) TO authenticated;

-- ── 10e. compute_player_morale() ─────────────────────────────

CREATE OR REPLACE FUNCTION compute_player_morale(p_player_id UUID)
RETURNS SMALLINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_minutes_last_5    SMALLINT := 450;
  v_starts_last_5     SMALLINT := 5;
  v_avg_rating_last_3 NUMERIC  := 6.5;
  v_training_score    NUMERIC  := 70;
  v_playing_sat       SMALLINT;
  v_training_sat      SMALLINT;
  v_form_sat          SMALLINT;
  v_team_harmony      SMALLINT := 70;  -- Default; no team-level tracking yet
  v_morale            SMALLINT;
  v_band              TEXT;
BEGIN
  -- Playing time in last 5 fixtures
  SELECT
    COALESCE(SUM(pms.minutes_played), 0),
    COALESCE(SUM(CASE WHEN pms.started THEN 1 ELSE 0 END), 0)
  INTO v_minutes_last_5, v_starts_last_5
  FROM player_match_stats pms
  JOIN fixtures f ON f.id = pms.fixture_id
  WHERE pms.player_id = p_player_id
    AND f.status = 'completed'
    AND f.match_date >= CURRENT_DATE - 42  -- last ~6 weeks
  ORDER BY f.match_date DESC LIMIT 5;

  -- Recent form (avg match rating)
  SELECT COALESCE(AVG(pms.match_rating), 6.5) INTO v_avg_rating_last_3
  FROM player_match_stats pms
  JOIN fixtures f ON f.id = pms.fixture_id
  WHERE pms.player_id = p_player_id
    AND f.status = 'completed'
    AND pms.match_rating IS NOT NULL
  ORDER BY f.match_date DESC LIMIT 3;

  -- Weekly training score (last week)
  v_training_score := compute_weekly_training_score(p_player_id, DATE_TRUNC('week', CURRENT_DATE)::DATE);

  -- Playing time satisfaction (450 min in 5 games = happy; 0 = miserable)
  v_playing_sat := LEAST(100, GREATEST(0,
    ROUND(v_minutes_last_5::NUMERIC / 450.0 * 80 + v_starts_last_5 * 4)
  ))::SMALLINT;

  -- Training satisfaction (based on training score and attendance)
  v_training_sat := LEAST(100, GREATEST(0, ROUND(v_training_score)))::SMALLINT;

  -- Form satisfaction (avg match rating 1–10 → 10–100 scale)
  v_form_sat := LEAST(100, GREATEST(10, ROUND(v_avg_rating_last_3 * 10)))::SMALLINT;

  -- Overall morale: weighted composite
  v_morale := ROUND(
    v_playing_sat  * 0.40
    + v_form_sat     * 0.25
    + v_training_sat * 0.20
    + v_team_harmony * 0.15
  )::SMALLINT;

  v_morale := GREATEST(0, LEAST(100, v_morale));

  v_band := CASE
    WHEN v_morale >= 90 THEN 'ecstatic'
    WHEN v_morale >= 75 THEN 'happy'
    WHEN v_morale >= 55 THEN 'content'
    WHEN v_morale >= 40 THEN 'unsettled'
    WHEN v_morale >= 25 THEN 'unhappy'
    ELSE                     'miserable'
  END;

  INSERT INTO player_morale_snapshots (
    player_id, snapshot_date,
    morale_score, morale_band,
    playing_time_satisfaction, training_satisfaction,
    form_satisfaction, team_harmony,
    minutes_last_5_matches, starts_last_5,
    recent_form
  ) VALUES (
    p_player_id, CURRENT_DATE,
    v_morale, v_band,
    v_playing_sat, v_training_sat,
    v_form_sat, v_team_harmony,
    v_minutes_last_5, v_starts_last_5,
    ROUND(v_avg_rating_last_3 * 10)::SMALLINT
  )
  ON CONFLICT (player_id, snapshot_date) DO UPDATE SET
    morale_score              = EXCLUDED.morale_score,
    morale_band               = EXCLUDED.morale_band,
    playing_time_satisfaction = EXCLUDED.playing_time_satisfaction,
    training_satisfaction     = EXCLUDED.training_satisfaction,
    form_satisfaction         = EXCLUDED.form_satisfaction,
    minutes_last_5_matches    = EXCLUDED.minutes_last_5_matches,
    starts_last_5             = EXCLUDED.starts_last_5,
    recent_form               = EXCLUDED.recent_form;

  UPDATE players SET
    morale_score = v_morale,
    morale_band  = v_band,
    updated_at   = NOW()
  WHERE id = p_player_id;

  RETURN v_morale;
END;
$$;

GRANT EXECUTE ON FUNCTION compute_player_morale(UUID) TO authenticated;

-- ── 10f. assess_injury_risk() ─────────────────────────────────

CREATE OR REPLACE FUNCTION assess_injury_risk(p_player_id UUID)
RETURNS TEXT  -- returns risk_level
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fatigue         SMALLINT := 20;
  v_matches_14d     SMALLINT := 0;
  v_injuries_12m    SMALLINT := 0;
  v_days_injured    SMALLINT := 0;
  v_age             INTEGER  := 22;
  v_injury_prone    SMALLINT := 10;
  v_fatigue_contrib SMALLINT;
  v_workload_contrib SMALLINT;
  v_history_contrib SMALLINT;
  v_age_contrib     SMALLINT;
  v_risk_score      SMALLINT;
  v_risk_level      TEXT;
  v_vulnerable_part TEXT;
BEGIN
  -- Fetch current fatigue and workload
  SELECT fatigue_level, matches_last_14d
  INTO v_fatigue, v_matches_14d
  FROM player_fitness_snapshots
  WHERE player_id = p_player_id
  ORDER BY snapshot_date DESC LIMIT 1;

  v_fatigue     := COALESCE(v_fatigue, 20);
  v_matches_14d := COALESCE(v_matches_14d, 0);

  -- Injury history (last 12 months)
  SELECT
    COUNT(*),
    COALESCE(SUM(
      CASE
        WHEN actual_return_date IS NOT NULL
          THEN (actual_return_date - injury_date)
        WHEN expected_return_date IS NOT NULL
          THEN (expected_return_date - injury_date)
        ELSE 7
      END
    ), 0)
  INTO v_injuries_12m, v_days_injured
  FROM player_injuries
  WHERE player_id  = p_player_id
    AND injury_date >= CURRENT_DATE - 365;

  -- Player age
  SELECT EXTRACT(YEAR FROM AGE(date_of_birth))::INTEGER INTO v_age
  FROM players WHERE id = p_player_id;
  v_age := COALESCE(v_age, 22);

  -- Injury proneness (hidden attribute)
  SELECT COALESCE(injury_proneness, 10) INTO v_injury_prone
  FROM player_hidden_attributes WHERE player_id = p_player_id;

  -- Most common injury body part
  SELECT body_part INTO v_vulnerable_part
  FROM player_injuries
  WHERE player_id = p_player_id
    AND injury_date >= CURRENT_DATE - 365
  GROUP BY body_part ORDER BY COUNT(*) DESC LIMIT 1;

  -- Component contributions (0–100)
  v_fatigue_contrib  := LEAST(100, v_fatigue)::SMALLINT;
  v_workload_contrib := LEAST(100, v_matches_14d * 14)::SMALLINT;
  v_history_contrib  := LEAST(100,
    v_injuries_12m * 20 + ROUND(v_days_injured / 3.65)
  )::SMALLINT;
  v_age_contrib      := CASE
    WHEN v_age < 20 THEN 10
    WHEN v_age < 25 THEN 20
    WHEN v_age < 30 THEN 30
    WHEN v_age < 33 THEN 45
    WHEN v_age < 36 THEN 60
    ELSE                 75
  END::SMALLINT;

  -- Injury proneness scales all factors
  v_risk_score := ROUND(
    (v_fatigue_contrib  * 0.35
     + v_workload_contrib * 0.25
     + v_history_contrib  * 0.25
     + v_age_contrib       * 0.15)
    * (v_injury_prone::NUMERIC / 10.0)
  )::SMALLINT;

  v_risk_score := GREATEST(0, LEAST(100, v_risk_score));

  v_risk_level := CASE
    WHEN v_risk_score >= 75 THEN 'very_high'
    WHEN v_risk_score >= 50 THEN 'high'
    WHEN v_risk_score >= 25 THEN 'medium'
    ELSE                         'low'
  END;

  INSERT INTO player_injury_risk_profiles (
    player_id, risk_level, risk_score,
    fatigue_contribution, workload_contribution,
    history_contribution, age_contribution,
    vulnerable_body_part, injuries_last_12m, days_injured_last_12m
  ) VALUES (
    p_player_id, v_risk_level, v_risk_score,
    v_fatigue_contrib, v_workload_contrib,
    v_history_contrib, v_age_contrib,
    v_vulnerable_part, v_injuries_12m, v_days_injured::SMALLINT
  )
  ON CONFLICT (player_id) DO UPDATE SET
    risk_level            = EXCLUDED.risk_level,
    risk_score            = EXCLUDED.risk_score,
    fatigue_contribution  = EXCLUDED.fatigue_contribution,
    workload_contribution = EXCLUDED.workload_contribution,
    history_contribution  = EXCLUDED.history_contribution,
    age_contribution      = EXCLUDED.age_contribution,
    vulnerable_body_part  = EXCLUDED.vulnerable_body_part,
    injuries_last_12m     = EXCLUDED.injuries_last_12m,
    days_injured_last_12m = EXCLUDED.days_injured_last_12m,
    computed_at           = NOW(),
    updated_at            = NOW();

  UPDATE players SET
    injury_risk_level = v_risk_level,
    updated_at        = NOW()
  WHERE id = p_player_id;

  RETURN v_risk_level;
END;
$$;

GRANT EXECUTE ON FUNCTION assess_injury_risk(UUID) TO authenticated;

-- ── 10g. apply_position_training() ───────────────────────────
-- Called when a player completes training sessions in a
-- non-natural position. Increases familiarity percentage.

CREATE OR REPLACE FUNCTION apply_position_training(
  p_player_id     UUID,
  p_position_code TEXT,
  p_position_label TEXT,
  p_sessions      INTEGER DEFAULT 1,
  p_is_natural    BOOLEAN DEFAULT false
)
RETURNS SMALLINT  -- new familiarity_pct
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_pct  SMALLINT := 0;
  v_current_fam  TEXT     := 'unfamiliar';
  v_gain_per_session SMALLINT := 2;  -- 2% per training session
  v_new_pct      SMALLINT;
  v_new_fam      TEXT;
BEGIN
  SELECT familiarity_pct, familiarity
  INTO v_current_pct, v_current_fam
  FROM player_position_familiarity
  WHERE player_id = p_player_id AND position_code = p_position_code;

  v_current_pct := COALESCE(v_current_pct, 0);

  -- Gain: 2% per session; diminishes as familiarity increases
  v_gain_per_session := GREATEST(1,
    ROUND(2 * (1 - v_current_pct::NUMERIC / 100.0))
  )::SMALLINT;

  v_new_pct := LEAST(100, v_current_pct + (v_gain_per_session * p_sessions))::SMALLINT;

  -- Familiarity bands
  v_new_fam := CASE
    WHEN p_is_natural OR v_new_pct >= 90 THEN 'natural'
    WHEN v_new_pct >= 70                  THEN 'accomplished'
    WHEN v_new_pct >= 50                  THEN 'competent'
    WHEN v_new_pct >= 20                  THEN 'learning'
    ELSE                                       'unfamiliar'
  END;

  INSERT INTO player_position_familiarity (
    player_id, position_code, position_label,
    familiarity, familiarity_pct, training_in_pos, is_natural
  ) VALUES (
    p_player_id, p_position_code, p_position_label,
    v_new_fam, v_new_pct, p_sessions, p_is_natural
  )
  ON CONFLICT (player_id, position_code) DO UPDATE SET
    familiarity     = EXCLUDED.familiarity,
    familiarity_pct = EXCLUDED.familiarity_pct,
    training_in_pos = player_position_familiarity.training_in_pos + p_sessions,
    updated_at      = NOW();

  RETURN v_new_pct;
END;
$$;

GRANT EXECUTE ON FUNCTION apply_position_training(UUID, TEXT, TEXT, INTEGER, BOOLEAN) TO authenticated;

-- ── 10h. compute_development_projection() ────────────────────

CREATE OR REPLACE FUNCTION compute_development_projection(p_player_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_age             INTEGER;
  v_dna_overall     SMALLINT;
  v_potential       SMALLINT;
  v_ambition        SMALLINT := 10;
  v_professionalism SMALLINT := 10;
  v_trend_slope     NUMERIC  := 0;
  v_proj_18         SMALLINT;
  v_proj_21         SMALLINT;
  v_proj_peak       SMALLINT;
  v_peak_age        SMALLINT;
  v_dev_phase       TEXT;
  v_confidence      SMALLINT;
  v_is_wonderkid    BOOLEAN  := false;
  v_wk_score        SMALLINT := 0;
  v_limiting        TEXT;
  v_accelerating    TEXT;
  v_years_to_18     INTEGER;
  v_years_to_21     INTEGER;
BEGIN
  SELECT
    EXTRACT(YEAR FROM AGE(date_of_birth))::INTEGER,
    COALESCE(dna_overall, 50),
    COALESCE(potential_score, 50)
  INTO v_age, v_dna_overall, v_potential
  FROM players WHERE id = p_player_id;

  -- Hidden personality factors
  SELECT
    COALESCE(ambition, 10),
    COALESCE(professionalism, 10)
  INTO v_ambition, v_professionalism
  FROM player_hidden_attributes WHERE player_id = p_player_id;

  -- Development trend slope from attribute history (last 6 months)
  SELECT COALESCE(
    REGR_SLOPE(current_value::NUMERIC, EXTRACT(EPOCH FROM recorded_at)), 0
  ) * 3600 * 24 * 30  -- convert to monthly slope
  INTO v_trend_slope
  FROM player_attribute_history
  WHERE player_id  = p_player_id
    AND recorded_at >= NOW() - INTERVAL '6 months';

  -- Normalise slope to a useful scale (0.5 units/month = good)
  v_trend_slope := GREATEST(-2.0, LEAST(2.0, COALESCE(v_trend_slope, 0)));

  -- Development phase
  v_dev_phase := CASE
    WHEN v_age <= 17 THEN 'emerging'
    WHEN v_age <= 22 THEN 'developing'
    WHEN v_age <= 29 THEN 'peak'
    WHEN v_age <= 33 THEN 'declining'
    ELSE                   'veteran'
  END;

  -- Peak age estimate (influenced by position)
  v_peak_age := CASE
    WHEN v_age <= 18 THEN
      CASE
        WHEN v_ambition >= 15       THEN 24
        WHEN v_professionalism >= 15 THEN 25
        ELSE 26
      END
    WHEN v_age BETWEEN 19 AND 25 THEN v_age + 3
    ELSE v_age + 2
  END;
  v_peak_age := LEAST(32, GREATEST(20, v_peak_age))::SMALLINT;

  -- Projection calculations
  v_years_to_18 := GREATEST(0, 18 - v_age);
  v_years_to_21 := GREATEST(0, 21 - v_age);

  -- Base annual growth rate from trend
  DECLARE
    v_annual_growth NUMERIC := v_trend_slope * 12
                             + (v_ambition::NUMERIC / 20.0) * 3
                             + (v_professionalism::NUMERIC / 20.0) * 2;
    v_peak_boost    NUMERIC := (v_potential - v_dna_overall)::NUMERIC * 0.15;
  BEGIN
    v_annual_growth := GREATEST(-5, LEAST(15, v_annual_growth));

    v_proj_18 := CASE
      WHEN v_age >= 18 THEN v_dna_overall
      ELSE LEAST(100, GREATEST(1,
             ROUND(v_dna_overall + v_annual_growth * v_years_to_18)
           ))
    END::SMALLINT;

    v_proj_21 := CASE
      WHEN v_age >= 21 THEN v_dna_overall
      ELSE LEAST(100, GREATEST(1,
             ROUND(v_dna_overall + v_annual_growth * v_years_to_21 + v_peak_boost)
           ))
    END::SMALLINT;

    v_proj_peak := LEAST(100, GREATEST(1,
      ROUND(GREATEST(v_dna_overall,
              v_dna_overall + v_annual_growth * (v_peak_age - v_age)
                             + v_peak_boost))
    ))::SMALLINT;

    -- Cap peak at potential score (potential is the ceiling)
    v_proj_peak := LEAST(v_proj_peak, v_potential)::SMALLINT;
  END;

  -- Confidence (increases with data)
  SELECT LEAST(95, COUNT(*) * 5) INTO v_confidence
  FROM player_attribute_history WHERE player_id = p_player_id;
  v_confidence := GREATEST(10, COALESCE(v_confidence, 10))::SMALLINT;

  -- Wonderkid detection: young player with high potential
  IF v_age <= 21 AND v_proj_peak >= 75 THEN
    v_is_wonderkid := true;
    v_wk_score := LEAST(100, (v_proj_peak - 60) * 2 + (21 - v_age) * 3)::SMALLINT;
  END IF;

  -- Limiting and accelerating factors
  v_limiting := CASE
    WHEN v_ambition        < 8  THEN 'low_ambition'
    WHEN v_professionalism < 8  THEN 'poor_professionalism'
    WHEN v_age             > 28 THEN 'physical_decline'
    WHEN v_trend_slope     < -0.5 THEN 'negative_trend'
    ELSE NULL
  END;

  v_accelerating := CASE
    WHEN v_ambition >= 16 AND v_professionalism >= 16 THEN 'elite_personality'
    WHEN v_ambition >= 14                              THEN 'high_ambition'
    WHEN v_professionalism >= 14                       THEN 'professional_approach'
    WHEN v_trend_slope > 0.5                           THEN 'strong_development_trend'
    ELSE NULL
  END;

  -- Write projection
  INSERT INTO player_development_projections (
    player_id, computed_date,
    current_dna, current_age,
    projected_dna_18, projected_dna_21, projected_dna_peak,
    projected_peak_age, projection_confidence,
    development_phase, limiting_factor, accelerating_factor,
    is_wonderkid, wonderkid_score
  ) VALUES (
    p_player_id, CURRENT_DATE,
    v_dna_overall, v_age,
    v_proj_18, v_proj_21, v_proj_peak,
    v_peak_age, v_confidence,
    v_dev_phase, v_limiting, v_accelerating,
    v_is_wonderkid, NULLIF(v_wk_score, 0)
  )
  ON CONFLICT (player_id, computed_date) DO UPDATE SET
    current_dna          = EXCLUDED.current_dna,
    current_age          = EXCLUDED.current_age,
    projected_dna_18     = EXCLUDED.projected_dna_18,
    projected_dna_21     = EXCLUDED.projected_dna_21,
    projected_dna_peak   = EXCLUDED.projected_dna_peak,
    projected_peak_age   = EXCLUDED.projected_peak_age,
    projection_confidence = EXCLUDED.projection_confidence,
    development_phase    = EXCLUDED.development_phase,
    limiting_factor      = EXCLUDED.limiting_factor,
    accelerating_factor  = EXCLUDED.accelerating_factor,
    is_wonderkid         = EXCLUDED.is_wonderkid,
    wonderkid_score      = EXCLUDED.wonderkid_score;

  -- Denormalise to players
  UPDATE players SET
    projected_peak_dna  = v_proj_peak,
    projected_peak_age  = v_peak_age,
    development_phase   = v_dev_phase,
    updated_at          = NOW()
  WHERE id = p_player_id;

  RETURN JSONB_BUILD_OBJECT(
    'player_id',        p_player_id,
    'current_dna',      v_dna_overall,
    'projected_18',     v_proj_18,
    'projected_21',     v_proj_21,
    'projected_peak',   v_proj_peak,
    'peak_age',         v_peak_age,
    'phase',            v_dev_phase,
    'is_wonderkid',     v_is_wonderkid,
    'wonderkid_score',  v_wk_score,
    'confidence',       v_confidence
  );
END;
$$;

GRANT EXECUTE ON FUNCTION compute_development_projection(UUID) TO authenticated;

-- ── 10i. run_weekly_growth() ──────────────────────────────────
-- Applies training-based attribute growth to all active players.
-- Called by Supabase Cron on Mondays at 04:00 MYT.

CREATE OR REPLACE FUNCTION run_weekly_growth(
  p_week_start DATE DEFAULT DATE_TRUNC('week', CURRENT_DATE)::DATE
)
RETURNS INTEGER  -- count of attribute updates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id  UUID;
  v_attr_code  TEXT;
  v_growth     NUMERIC;
  v_applied    NUMERIC;
  v_count      INTEGER := 0;
  v_season_id  UUID;
BEGIN
  FOR v_player_id IN
    SELECT id FROM players WHERE is_active = true
  LOOP
    -- Get active season for this player
    SELECT s.id INTO v_season_id
    FROM player_league_registrations plr
    JOIN seasons s ON s.id = plr.season_id
    WHERE plr.player_id = v_player_id
      AND plr.status = 'approved'
      AND plr.is_current = true
    ORDER BY plr.created_at DESC LIMIT 1;

    FOR v_attr_code IN
      SELECT code FROM attribute_definitions WHERE is_active = true
    LOOP
      v_growth := compute_attribute_growth(v_player_id, v_attr_code, p_week_start);

      IF ABS(v_growth) >= 0.05 THEN
        v_applied := apply_capped_attribute_update(
          v_player_id,
          v_attr_code,
          v_growth,
          v_season_id,
          'ai_batch'
        );
        IF v_applied <> 0 THEN
          v_count := v_count + 1;
        END IF;
      END IF;
    END LOOP;

    -- Recompute DNA after all attributes updated
    PERFORM calculate_player_dna(v_player_id);
  END LOOP;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION run_weekly_growth(DATE) TO authenticated;

-- ── 10j. run_development_nightly() ───────────────────────────
-- Master nightly development batch. Processes all active players.
-- Called by Supabase Cron nightly at 03:00 MYT.

CREATE OR REPLACE FUNCTION run_development_nightly()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id       UUID;
  v_fitness_count   INTEGER := 0;
  v_morale_count    INTEGER := 0;
  v_injury_count    INTEGER := 0;
  v_proj_count      INTEGER := 0;
  v_total           INTEGER := 0;
BEGIN
  FOR v_player_id IN
    SELECT id FROM players WHERE is_active = true
    ORDER BY passport_computed_at ASC NULLS FIRST
    LIMIT 1000
  LOOP
    BEGIN
      -- 1. Update fitness
      PERFORM update_fitness_nightly(v_player_id);
      v_fitness_count := v_fitness_count + 1;

      -- 2. Compute morale
      PERFORM compute_player_morale(v_player_id);
      v_morale_count := v_morale_count + 1;

      -- 3. Assess injury risk
      PERFORM assess_injury_risk(v_player_id);
      v_injury_count := v_injury_count + 1;

      -- 4. Development projections (daily update for under-25s, weekly for others)
      IF (
        SELECT EXTRACT(YEAR FROM AGE(date_of_birth)) < 25 OR
               EXTRACT(DOW FROM CURRENT_DATE) = 1  -- Monday = weekly for all
        FROM players WHERE id = v_player_id
      ) THEN
        PERFORM compute_development_projection(v_player_id);
        v_proj_count := v_proj_count + 1;
      END IF;

      v_total := v_total + 1;

    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Development nightly failed for player %: %', v_player_id, SQLERRM;
    END;
  END LOOP;

  RETURN JSONB_BUILD_OBJECT(
    'players_processed', v_total,
    'fitness_updates',   v_fitness_count,
    'morale_updates',    v_morale_count,
    'injury_assessments', v_injury_count,
    'projections',       v_proj_count,
    'run_at',            NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION run_development_nightly() TO authenticated;

-- ════════════════════════════════════════════════════════════
-- SECTION 11: VIEWS
-- ════════════════════════════════════════════════════════════

-- ── 11a. Football Passport integration view ───────────────────
-- Combines development data for the public passport page.

CREATE OR REPLACE VIEW v_player_development_passport
WITH (security_invoker = true)
AS
SELECT
  p.id                                          AS player_id,
  COALESCE(p.preferred_name, p.full_name)       AS display_name,
  p.position,
  p.best_position,
  p.playing_role,
  p.development_phase,
  p.development_trend,
  p.scout_recommendation,
  -- DNA
  p.dna_overall,
  p.dna_band,
  p.dna_technical,
  p.dna_physical,
  p.dna_mental,
  p.dna_tactical,
  -- Potential & Projection
  p.potential_score,
  p.potential_category,
  p.projected_peak_dna,
  p.projected_peak_age,
  -- Fitness
  p.fitness_condition,
  p.match_sharpness,
  p.fatigue_level,
  p.training_load,
  -- Morale (band only — no score for public)
  p.morale_band,
  -- Injury risk (level only — no details for public)
  p.injury_risk_level,
  -- Passport
  p.passport_score,
  p.passport_band,
  -- Latest projection details
  dp.projected_dna_18,
  dp.projected_dna_21,
  dp.is_wonderkid,
  dp.accelerating_factor,
  dp.limiting_factor,
  dp.projection_confidence,
  -- Latest morale details (for claimed player / guardian only)
  CASE
    WHEN p.id = get_my_player_id() OR is_guardian_of(p.id)
         OR get_my_role() IN ('developer','club_admin','coach')
    THEN ms.morale_score
    ELSE NULL
  END AS morale_score_private,
  -- Age
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
  p.photo_url,
  p.share_url_slug,
  c.name AS club_name,
  c.logo_url AS club_logo,
  p.pipeline_last_run
FROM players p
LEFT JOIN clubs c ON c.id = p.club_id
LEFT JOIN LATERAL (
  SELECT projected_dna_18, projected_dna_21, is_wonderkid,
         accelerating_factor, limiting_factor, projection_confidence
  FROM player_development_projections
  WHERE player_id = p.id AND computed_date = CURRENT_DATE
  LIMIT 1
) dp ON true
LEFT JOIN LATERAL (
  SELECT morale_score FROM player_morale_snapshots
  WHERE player_id = p.id AND snapshot_date = CURRENT_DATE
  LIMIT 1
) ms ON true
WHERE p.is_active = true
  AND p.is_passport_public = true;

-- ── 11b. Squad development report (club dashboard) ────────────

CREATE OR REPLACE VIEW v_squad_development_report
WITH (security_invoker = true)
AS
SELECT
  p.id                                          AS player_id,
  COALESCE(p.preferred_name, p.full_name)       AS display_name,
  p.position,
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
  p.best_position,
  p.playing_role,
  p.development_phase,
  p.development_trend,
  p.dna_overall,
  p.potential_score,
  p.projected_peak_dna,
  p.projected_peak_age,
  p.fitness_condition,
  p.match_sharpness,
  p.fatigue_level,
  p.morale_score,
  p.morale_band,
  p.injury_risk_level,
  p.training_load,
  p.club_id,
  -- Training this week
  ROUND(compute_weekly_training_score(p.id,
    DATE_TRUNC('week', CURRENT_DATE)::DATE
  ))::SMALLINT                                  AS weekly_training_score,
  -- Wonderkid flag
  dp.is_wonderkid,
  dp.wonderkid_score,
  dp.accelerating_factor,
  dp.limiting_factor,
  -- Hidden attribute summary (visible to club only)
  CASE
    WHEN get_my_role() IN ('developer','club_admin','coach')
    THEN pha.professionalism ELSE NULL
  END AS professionalism,
  CASE
    WHEN get_my_role() IN ('developer','club_admin','coach')
    THEN pha.ambition ELSE NULL
  END AS ambition,
  CASE
    WHEN get_my_role() IN ('developer','club_admin','coach')
    THEN pha.injury_proneness ELSE NULL
  END AS injury_proneness
FROM players p
LEFT JOIN LATERAL (
  SELECT is_wonderkid, wonderkid_score, accelerating_factor, limiting_factor
  FROM player_development_projections
  WHERE player_id = p.id
  ORDER BY computed_date DESC LIMIT 1
) dp ON true
LEFT JOIN player_hidden_attributes pha ON pha.player_id = p.id
WHERE p.is_active = true
  AND (
    get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND p.club_id IN (
          SELECT id FROM clubs WHERE admin_id = auth.uid()
        ))
    OR (get_my_role() = 'coach' AND p.club_id IN (
          SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
        ))
  );

-- ── 11c. Development leaderboard (public) ────────────────────

CREATE OR REPLACE VIEW v_development_leaderboard
WITH (security_invoker = true)
AS
SELECT
  p.id                                          AS player_id,
  COALESCE(p.preferred_name, p.full_name)       AS display_name,
  p.position,
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
  p.dna_overall,
  p.dna_band,
  p.projected_peak_dna,
  p.projected_peak_age,
  p.development_phase,
  p.development_trend,
  p.potential_score,
  p.potential_category,
  p.passport_score,
  p.photo_url,
  p.share_url_slug,
  c.name AS club_name,
  l.name AS league_name,
  -- Improvement ratio (projected vs current)
  CASE
    WHEN COALESCE(p.dna_overall, 0) > 0
    THEN ROUND(
      (COALESCE(p.projected_peak_dna, p.dna_overall) - COALESCE(p.dna_overall, 50))::NUMERIC
      / COALESCE(p.dna_overall, 50) * 100
    , 1)
    ELSE 0
  END AS improvement_headroom_pct
FROM players p
LEFT JOIN clubs c ON c.id = p.club_id
LEFT JOIN (
  SELECT DISTINCT ON (plr.player_id) plr.player_id, s.league_id
  FROM player_league_registrations plr
  JOIN seasons s ON s.id = plr.season_id
  WHERE plr.status = 'approved' AND plr.is_current = true
  ORDER BY plr.player_id, plr.created_at DESC
) cur ON cur.player_id = p.id
LEFT JOIN leagues l ON l.id = cur.league_id
WHERE p.is_active = true
  AND p.is_passport_public = true
  AND p.dna_overall IS NOT NULL
ORDER BY p.projected_peak_dna DESC NULLS LAST;

-- ── 11d. Wonderkid radar (club and public) ────────────────────

CREATE OR REPLACE VIEW v_wonderkid_radar
WITH (security_invoker = true)
AS
SELECT
  p.id                                          AS player_id,
  COALESCE(p.preferred_name, p.full_name)       AS display_name,
  p.position,
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
  p.dna_overall,
  p.projected_peak_dna,
  dp.wonderkid_score,
  dp.accelerating_factor,
  p.development_trend,
  p.potential_score,
  p.potential_category,
  p.playing_role,
  p.photo_url,
  p.share_url_slug,
  c.name AS club_name,
  c.logo_url AS club_logo,
  l.name AS league_name
FROM players p
JOIN player_development_projections dp
  ON dp.player_id = p.id AND dp.is_wonderkid = true
LEFT JOIN clubs   c ON c.id = p.club_id
LEFT JOIN (
  SELECT DISTINCT ON (plr.player_id) plr.player_id, s.league_id
  FROM player_league_registrations plr
  JOIN seasons s ON s.id = plr.season_id
  WHERE plr.status = 'approved' AND plr.is_current = true
  ORDER BY plr.player_id, plr.created_at DESC
) cur ON cur.player_id = p.id
LEFT JOIN leagues l ON l.id = cur.league_id
WHERE p.is_active = true
  AND p.is_passport_public = true
ORDER BY dp.wonderkid_score DESC NULLS LAST;

-- ── 11e. Player fitness timeline (for growth chart) ──────────

CREATE OR REPLACE VIEW v_player_fitness_timeline
WITH (security_invoker = true)
AS
SELECT
  pfs.player_id,
  p.full_name,
  COALESCE(p.preferred_name, p.full_name) AS display_name,
  pfs.snapshot_date,
  pfs.match_sharpness,
  pfs.fatigue_level,
  pfs.condition,
  pfs.training_load,
  pfs.days_since_match,
  pfs.matches_last_14d
FROM player_fitness_snapshots pfs
JOIN players p ON p.id = pfs.player_id
WHERE p.is_active = true
  AND (
    get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND p.club_id IN (
          SELECT id FROM clubs WHERE admin_id = auth.uid()
        ))
    OR (get_my_role() = 'coach' AND p.club_id IN (
          SELECT id FROM coaches WHERE profile_id = auth.uid() AND is_active = true
        ))
    OR pfs.player_id = get_my_player_id()
    OR is_guardian_of(pfs.player_id)
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 12: MATERIALISED VIEWS (dashboard performance)
-- ════════════════════════════════════════════════════════════

CREATE MATERIALIZED VIEW mv_squad_development AS
SELECT
  p.club_id,
  p.id                                          AS player_id,
  COALESCE(p.preferred_name, p.full_name)       AS display_name,
  p.position,
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
  p.dna_overall,
  p.dna_band,
  p.potential_score,
  p.projected_peak_dna,
  p.development_phase,
  p.development_trend,
  p.fitness_condition,
  p.morale_band,
  p.injury_risk_level,
  dp.is_wonderkid,
  dp.wonderkid_score,
  p.scout_recommendation,
  p.playing_role
FROM players p
LEFT JOIN LATERAL (
  SELECT is_wonderkid, wonderkid_score
  FROM player_development_projections
  WHERE player_id = p.id
  ORDER BY computed_date DESC LIMIT 1
) dp ON true
WHERE p.is_active = true
WITH DATA;

CREATE UNIQUE INDEX mv_squad_dev_player  ON mv_squad_development(player_id);
CREATE INDEX mv_squad_dev_club           ON mv_squad_development(club_id, dna_overall DESC);
CREATE INDEX mv_squad_dev_wonderkid      ON mv_squad_development(is_wonderkid, wonderkid_score DESC)
  WHERE is_wonderkid = true;

-- ════════════════════════════════════════════════════════════
-- SECTION 13: INITIALISE HIDDEN ATTRIBUTES FOR EXISTING PLAYERS
-- Default values (10 = average) for all currently active players
-- who don't yet have a hidden attribute record.
-- ════════════════════════════════════════════════════════════

INSERT INTO player_hidden_attributes (
  player_id, professionalism, ambition, loyalty,
  temperament, consistency, injury_proneness,
  pressure_handling, confidence,
  assessed_by_type
)
SELECT
  p.id,
  -- Derive rough defaults from existing data where possible
  CASE WHEN p.dna_mental >= 14 THEN 14
       WHEN p.dna_mental >= 10 THEN 10
       ELSE 8 END,           -- professionalism proxy from mental DNA
  CASE WHEN p.potential_score >= 80 THEN 15
       WHEN p.potential_score >= 60 THEN 12
       ELSE 9 END,           -- ambition from potential
  10,                         -- loyalty: neutral default
  CASE WHEN EXISTS (
         SELECT 1 FROM disciplinary_records dr
         WHERE dr.player_id = p.id AND dr.card_type = 'red'
       ) THEN 8 ELSE 11 END, -- temperament: lower for red card history
  CASE WHEN p.dna_mental >= 14 THEN 13 ELSE 10 END,  -- consistency
  CASE WHEN p.dna_physical IS NOT NULL AND p.dna_physical < 60 THEN 12
       ELSE 10 END,           -- injury_proneness
  10, 10,
  'ai'
FROM players p
WHERE p.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM player_hidden_attributes pha WHERE pha.player_id = p.id
  );

-- ════════════════════════════════════════════════════════════
-- SECTION 14: GRANT EXECUTE
-- ════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION compute_weekly_training_score(UUID, DATE)       TO authenticated, anon;
GRANT EXECUTE ON FUNCTION compute_attribute_growth(UUID, TEXT, DATE)       TO authenticated;
GRANT EXECUTE ON FUNCTION update_fitness_after_match(UUID, INTEGER, DATE)  TO authenticated;
GRANT EXECUTE ON FUNCTION update_fitness_nightly(UUID)                     TO authenticated;
GRANT EXECUTE ON FUNCTION compute_player_morale(UUID)                      TO authenticated;
GRANT EXECUTE ON FUNCTION assess_injury_risk(UUID)                         TO authenticated;
GRANT EXECUTE ON FUNCTION apply_position_training(UUID,TEXT,TEXT,INTEGER,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION compute_development_projection(UUID)             TO authenticated;
GRANT EXECUTE ON FUNCTION run_weekly_growth(DATE)                          TO authenticated;
GRANT EXECUTE ON FUNCTION run_development_nightly()                        TO authenticated;

-- ════════════════════════════════════════════════════════════
-- SECTION 15: VERIFICATION QUERIES (run manually after deploy)
-- ════════════════════════════════════════════════════════════

-- 1. All new tables created:
-- SELECT tablename FROM pg_tables WHERE schemaname = 'public'
-- AND tablename IN (
--   'training_programmes','training_sessions',
--   'player_training_attendance','player_training_performance',
--   'player_hidden_attributes','player_development_curves',
--   'player_fitness_snapshots','player_morale_snapshots',
--   'player_injury_risk_profiles','player_position_familiarity',
--   'player_development_projections'
-- );

-- 2. Development curves seeded (128 rows: 32 ages × 4 categories):
-- SELECT category, COUNT(*) FROM player_development_curves GROUP BY category;

-- 3. Hidden attributes initialised:
-- SELECT COUNT(*) FROM player_hidden_attributes;

-- 4. Player columns added:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'players'
-- AND column_name IN (
--   'fitness_condition','match_sharpness','fatigue_level',
--   'training_load','morale_score','morale_band',
--   'projected_peak_dna','projected_peak_age',
--   'development_phase','injury_risk_level',
--   'last_training_date','days_since_match'
-- );

-- 5. Test projection for a player:
-- SELECT compute_development_projection('<player-uuid>');

-- 6. Test morale:
-- SELECT compute_player_morale('<player-uuid>');

-- 7. Test fitness update:
-- SELECT update_fitness_after_match('<player-uuid>', 90, CURRENT_DATE);

-- 8. Wonderkid radar:
-- SELECT * FROM v_wonderkid_radar LIMIT 10;

-- 9. Test nightly batch (will process up to 1000 players):
-- SELECT run_development_nightly();

COMMIT;

-- ============================================================
-- PHASE 6.8 SUMMARY
-- ============================================================
-- New tables:             11
--   training_programmes
--   training_sessions
--   player_training_attendance
--   player_training_performance
--   player_hidden_attributes        (8 hidden attrs, 1–20 scale)
--   player_development_curves       (128 rows seeded: 32 ages × 4 categories)
--   player_fitness_snapshots
--   player_morale_snapshots
--   player_injury_risk_profiles
--   player_position_familiarity
--   player_development_projections
--
-- New columns on players: 12
--   fitness_condition, match_sharpness, fatigue_level,
--   training_load, morale_score, morale_band,
--   projected_peak_dna, projected_peak_age, development_phase,
--   injury_risk_level, last_training_date, days_since_match
--
-- New functions:          10
--   compute_weekly_training_score()
--   compute_attribute_growth()      ← age curve + coach + professionalism
--   update_fitness_after_match()    ← fatigue/sharpness from match minutes
--   update_fitness_nightly()        ← daily recovery and decay
--   compute_player_morale()         ← 4-component morale formula
--   assess_injury_risk()            ← fatigue + workload + history + age
--   apply_position_training()       ← familiarity % increase per session
--   compute_development_projection()← 18/21/peak DNA + wonderkid detection
--   run_weekly_growth()             ← Monday batch: training growth to attributes
--   run_development_nightly()       ← 03:00 MYT master nightly batch
--
-- New views:               5
--   v_player_development_passport   ← Football Passport integration
--   v_squad_development_report      ← Club dashboard (gated by RLS)
--   v_development_leaderboard       ← Public leaderboard
--   v_wonderkid_radar               ← Wonderkid detection list
--   v_player_fitness_timeline       ← Fitness history chart
--
-- New materialized views:  1
--   mv_squad_development            ← Fast club dashboard queries
--
-- RLS policies:            22 (on all 11 tables)
-- Audit triggers:           5 (on write-heavy tables)
-- Enum values added:        8 (notification_type, Part A)
-- Development curve rows: 128 (ages 14–45, 4 categories)
-- ============================================================
-- NIGHTLY CRON SCHEDULE (Supabase):
--   03:00 MYT → run_development_nightly()     (fitness/morale/risk/projections)
--   04:00 MYT → run_weekly_growth()            (Mondays only: attribute growth)
--   05:00 MYT → run_intelligence_batch()       (from Phase 6.6: DNA/passport)
--   06:00 MYT → refresh_all_public_views()     (from Sprint 1: matviews)
-- ============================================================
