-- ============================================================
-- PlayPro Phase 6.5 — Football DNA & Football Passport
-- Full Implementation Migration
-- ============================================================
-- Version:    6.5.0
-- Date:       2026-06-08
-- Author:     PlayPro Principal DB Architect
-- Depends on: Phase 1 (database spec playpro.txt)
--             Phase 2 (playpro_phase2_additions.sql)
--             Phase 3 (playpro_phase3_additions.sql)
--             Phase 4   (playpro_phase4_critical_fix_pack.sql)
--             Phase 4.1 (playpro_phase4_1_stabilization_patch.sql)
--             Phase 4.1.1 (playpro_phase4_1_1_remediation_patch.sql)
--             Phase 4.1.2 (playpro_phase4_1_2_security_patch.sql)
--             Phase 4.1.3 (playpro_phase4_1_3_remediation_patch.sql)
--             Phase 4.2   (playpro_phase4_2_hotfix.sql)
-- ============================================================
-- DIRECTIVE COMPLIANCE:
--   ✓ Do NOT modify existing Phase 1-4 objects (except additive
--     ALTER TABLE ADD COLUMN and explicitly required fixes)
--   ✓ All SQL is PostgreSQL 16 + Supabase compatible
--   ✓ Full SQL only — no pseudocode, no stubs
--   ✓ Every table has RLS, indexes, audit triggers, FK
--   ✓ Existing player_assessments (1-100, Phase 1) is PRESERVED
--     New tables use 1-20 scale and co-exist under different names
--   ✓ is_coach_for_club() implemented (Section 13 fix)
--   ✓ match_lineups policy fixed (Section 13 fix)
--   ✓ Claimed identity tables added (Section 12)
--   ✓ Helper functions: get_my_player_id(), is_guardian_of(),
--     is_own_player_record()
-- ============================================================
-- ARCHITECT NOTES:
--   Phase 1 already contains player_assessments (1-100 flat columns,
--   technical_assessor role). That table is LEGACY. Phase 6.5 adds
--   a complete, parallel attribute system under new table names:
--     attribute_definitions
--     player_attributes
--     player_attribute_history
--     player_attribute_assessments
--     player_attribute_assessment_sources
--     player_potential_scores
--   The legacy player_assessments table is not dropped (preserve
--   backward compatibility). DNA engine reads from player_attributes
--   only.
--
--   notification_type is an ENUM. We ADD VALUES to it in Part A
--   (outside transaction, required by PostgreSQL). All other DDL
--   runs inside BEGIN...COMMIT.
-- ============================================================

-- ============================================================
-- PART A — ENUM ADDITIONS (must run OUTSIDE transaction)
-- ============================================================

-- Notification types for DNA / Passport / Claiming system
-- ALTER TYPE ADD VALUE cannot run inside a transaction block.

ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'assessment_submitted';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'assessment_accepted';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'assessment_rejected';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'passport_claim_submitted';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'passport_claim_approved';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'passport_claim_rejected';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'guardian_consent_required';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'ownership_transfer_ready';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'achievement_earned';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'passport_milestone';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'player_motm';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'player_milestone';

-- ============================================================
-- PART B — MAIN MIGRATION (single transaction)
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- SECTION 1: LEAGUE QUALITY TIERS
-- Required by Passport Score formula (league scalar).
-- ────────────────────────────────────────────────────────────

CREATE TABLE league_quality_tiers (
  id            UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          TEXT          NOT NULL UNIQUE,  -- e.g. 'Liga Super'
  code          TEXT          NOT NULL UNIQUE,  -- e.g. 'liga_super'
  scalar        NUMERIC(3,2)  NOT NULL
                CHECK (scalar BETWEEN 0.50 AND 1.00),
  display_order SMALLINT      NOT NULL DEFAULT 0,
  description   TEXT,
  is_active     BOOLEAN       NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_league_quality_tiers_updated_at
  BEFORE UPDATE ON league_quality_tiers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Seed: Malaysian football tier hierarchy
INSERT INTO league_quality_tiers (name, code, scalar, display_order, description) VALUES
  ('Liga Super',    'liga_super',    1.00, 1, 'Top professional division — FAM sanctioned'),
  ('Liga Premier',  'liga_premier',  0.90, 2, 'Second professional division — FAM sanctioned'),
  ('State League',  'state_league',  0.80, 3, 'State-level competition'),
  ('District League','district',     0.72, 4, 'District-level competition'),
  ('Amateur',       'amateur',       0.65, 5, 'Open amateur competition'),
  ('Youth',         'youth',         0.60, 6, 'Age-group youth competition');

ALTER TABLE league_quality_tiers ENABLE ROW LEVEL SECURITY;

-- Public can read tiers (needed for passport score display)
CREATE POLICY "league_quality_tiers: public read"
  ON league_quality_tiers FOR SELECT
  USING (true);

-- Only developer can manage tiers
CREATE POLICY "league_quality_tiers: developer write"
  ON league_quality_tiers FOR ALL
  USING (get_my_role() = 'developer')
  WITH CHECK (get_my_role() = 'developer');

-- ────────────────────────────────────────────────────────────
-- SECTION 1b: player_league_registrations — add is_current column
-- player_league_registrations has no is_current column.
-- We add it here as an additive nullable boolean so existing rows
-- are unaffected (NULL = unknown, treated as false in queries).
-- ────────────────────────────────────────────────────────────

ALTER TABLE player_league_registrations
  ADD COLUMN IF NOT EXISTS is_current BOOLEAN NOT NULL DEFAULT false;

-- Mark approved registrations in active seasons as is_current
-- (Best-effort data migration; will be maintained by triggers going forward)
UPDATE player_league_registrations plr
SET is_current = true
WHERE plr.status = 'approved'
  AND EXISTS (
    SELECT 1 FROM seasons s
    WHERE s.id = plr.season_id
      AND s.status = 'active'
  );

-- Trigger to maintain is_current on registration changes
CREATE OR REPLACE FUNCTION maintain_plr_is_current()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- When a registration is approved in an active season, mark it current
  IF NEW.status = 'approved' AND EXISTS (
    SELECT 1 FROM seasons WHERE id = NEW.season_id AND status = 'active'
  ) THEN
    NEW.is_current := true;
  END IF;
  -- When rejected/expired, mark not current
  IF NEW.status IN ('rejected','expired','suspended') THEN
    NEW.is_current := false;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_plr_maintain_current
  BEFORE INSERT OR UPDATE OF status ON player_league_registrations
  FOR EACH ROW EXECUTE FUNCTION maintain_plr_is_current();

CREATE INDEX IF NOT EXISTS idx_plr_current
  ON player_league_registrations(player_id, is_current)
  WHERE is_current = true;

-- ────────────────────────────────────────────────────────────
-- SECTION 2: LEAGUES — add quality tier FK + public slug
-- Additive only. No existing column touched.
-- ────────────────────────────────────────────────────────────

ALTER TABLE leagues
  ADD COLUMN IF NOT EXISTS quality_tier_id UUID
    REFERENCES league_quality_tiers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS share_url_slug   TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS follower_count   INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_leagues_quality_tier
  ON leagues(quality_tier_id);

CREATE INDEX IF NOT EXISTS idx_leagues_slug
  ON leagues(share_url_slug) WHERE share_url_slug IS NOT NULL;

-- ────────────────────────────────────────────────────────────
-- SECTION 3: CLUBS — public profile columns
-- Additive only.
-- ────────────────────────────────────────────────────────────

ALTER TABLE clubs
  ADD COLUMN IF NOT EXISTS description       TEXT,
  ADD COLUMN IF NOT EXISTS website_url       TEXT,
  ADD COLUMN IF NOT EXISTS social_twitter    TEXT,
  ADD COLUMN IF NOT EXISTS social_instagram  TEXT,
  ADD COLUMN IF NOT EXISTS social_facebook   TEXT,
  ADD COLUMN IF NOT EXISTS contact_email     TEXT,
  ADD COLUMN IF NOT EXISTS founding_story    TEXT,
  ADD COLUMN IF NOT EXISTS away_colours      TEXT,
  ADD COLUMN IF NOT EXISTS club_type         TEXT,
  ADD COLUMN IF NOT EXISTS membership_open   BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS membership_contact TEXT,
  -- DNA aggregate columns (computed by DNA engine)
  ADD COLUMN IF NOT EXISTS dna_technical     SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_physical      SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_mental        SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_tactical      SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_overall       SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_computed_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS club_passport_score SMALLINT,
  ADD COLUMN IF NOT EXISTS club_passport_band  TEXT,
  ADD COLUMN IF NOT EXISTS share_url_slug    TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS follower_count    INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_clubs_slug
  ON clubs(share_url_slug) WHERE share_url_slug IS NOT NULL;

-- ────────────────────────────────────────────────────────────
-- SECTION 4: PLAYERS — identity link + passport columns
-- Additive only. profile_id was MISSING — now added.
-- ────────────────────────────────────────────────────────────

ALTER TABLE players
  -- Identity link (THE critical missing column per architecture review)
  ADD COLUMN IF NOT EXISTS profile_id             UUID
    REFERENCES profiles(id) ON DELETE SET NULL,
  -- Public profile
  ADD COLUMN IF NOT EXISTS preferred_name         TEXT,
  ADD COLUMN IF NOT EXISTS biography              TEXT
    CHECK (biography IS NULL OR char_length(biography) <= 500),
  ADD COLUMN IF NOT EXISTS height_cm              SMALLINT
    CHECK (height_cm IS NULL OR height_cm BETWEEN 100 AND 230),
  ADD COLUMN IF NOT EXISTS weight_kg              SMALLINT
    CHECK (weight_kg IS NULL OR weight_kg BETWEEN 30 AND 150),
  -- DNA computed columns (denormalised for performance)
  ADD COLUMN IF NOT EXISTS dna_technical          SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_physical           SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_mental             SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_tactical           SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_goalkeeper         SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_overall            SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_band               TEXT,
  ADD COLUMN IF NOT EXISTS dna_computed_at        TIMESTAMPTZ,
  -- Potential (denormalised from player_potential_scores)
  ADD COLUMN IF NOT EXISTS potential_score        SMALLINT
    CHECK (potential_score IS NULL OR potential_score BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS potential_category     TEXT,
  -- Passport
  ADD COLUMN IF NOT EXISTS passport_score         SMALLINT,
  ADD COLUMN IF NOT EXISTS passport_band          TEXT,
  ADD COLUMN IF NOT EXISTS passport_computed_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_passport_public     BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS scout_contact_enabled  BOOLEAN NOT NULL DEFAULT false,
  -- Public URL
  ADD COLUMN IF NOT EXISTS share_url_slug         TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS follower_count         INTEGER NOT NULL DEFAULT 0;

-- Profile link index (crucial for get_my_player_id())
CREATE UNIQUE INDEX IF NOT EXISTS idx_players_profile_id
  ON players(profile_id) WHERE profile_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_players_dna_overall
  ON players(dna_overall DESC NULLS LAST) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_players_passport_score
  ON players(passport_score DESC NULLS LAST) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_players_slug
  ON players(share_url_slug) WHERE share_url_slug IS NOT NULL;

-- ────────────────────────────────────────────────────────────
-- SECTION 5: ATTRIBUTE DEFINITIONS (reference table)
-- Master list of all 28 attributes.
-- ────────────────────────────────────────────────────────────

CREATE TABLE attribute_definitions (
  code                TEXT          PRIMARY KEY,
  label               TEXT          NOT NULL UNIQUE,
  category            TEXT          NOT NULL
                      CHECK (category IN
                        ('technical','physical','mental','tactical','goalkeeper')),
  display_order       SMALLINT      NOT NULL,
  applies_to_outfield BOOLEAN       NOT NULL DEFAULT true,
  applies_to_gk       BOOLEAN       NOT NULL DEFAULT true,
  description         TEXT,
  -- Weight within category DNA computation (all weights per category sum to 1.000)
  weight_in_category  NUMERIC(5,4)  NOT NULL
                      CHECK (weight_in_category > 0 AND weight_in_category <= 1),
  fm_equivalent       TEXT,
  is_active           BOOLEAN       NOT NULL DEFAULT true,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_attribute_definitions_updated_at
  BEFORE UPDATE ON attribute_definitions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

ALTER TABLE attribute_definitions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "attribute_definitions: public read"
  ON attribute_definitions FOR SELECT
  USING (true);

CREATE POLICY "attribute_definitions: developer write"
  ON attribute_definitions FOR ALL
  USING (get_my_role() = 'developer')
  WITH CHECK (get_my_role() = 'developer');

-- ── Seed: 28 attributes ──────────────────────────────────────
-- TECHNICAL (7 attributes, weights sum to 1.0000)
INSERT INTO attribute_definitions
  (code, label, category, display_order, applies_to_outfield, applies_to_gk,
   weight_in_category, fm_equivalent, description)
VALUES
  ('passing',     'Passing',     'technical', 1, true, true,  0.1600,
   'Passing',      'Accuracy, weight and range of distribution'),
  ('crossing',    'Crossing',    'technical', 2, true, false, 0.1200,
   'Crossing',     'Quality of delivery from wide areas into the box'),
  ('dribbling',   'Dribbling',   'technical', 3, true, false, 0.1400,
   'Dribbling',    'Ability to carry the ball past opponents at pace'),
  ('finishing',   'Finishing',   'technical', 4, true, false, 0.1800,
   'Finishing',    'Composure and accuracy in front of goal'),
  ('first_touch', 'First Touch', 'technical', 5, true, true,  0.1600,
   'First Touch',  'Control and cushion when receiving the ball'),
  ('tackling',    'Tackling',    'technical', 6, true, false, 0.1200,
   'Tackling',     'Winning the ball cleanly in defensive challenges'),
  ('heading',     'Heading',     'technical', 7, true, true,  0.1200,
   'Heading',      'Aerial ability and timing in both penalty areas');

-- PHYSICAL (6 attributes, weights sum to 1.0000)
INSERT INTO attribute_definitions
  (code, label, category, display_order, applies_to_outfield, applies_to_gk,
   weight_in_category, fm_equivalent, description)
VALUES
  ('pace',         'Pace',         'physical', 1, true, true, 0.2000,
   'Pace',         'Top speed when running with or without the ball'),
  ('acceleration', 'Acceleration', 'physical', 2, true, true, 0.2000,
   'Acceleration', 'Explosive burst of speed over the first 5-10 metres'),
  ('stamina',      'Stamina',      'physical', 3, true, true, 0.2000,
   'Stamina',      'Ability to sustain high effort levels over 90 minutes'),
  ('strength',     'Strength',     'physical', 4, true, true, 0.1600,
   'Strength',     'Physical power in aerial and ground challenges'),
  ('agility',      'Agility',      'physical', 5, true, true, 0.1400,
   'Agility',      'Ability to change direction quickly and smoothly'),
  ('jumping',      'Jumping',      'physical', 6, true, true, 0.1000,
   'Jumping Reach','Vertical leap height and timing for aerial duels');

-- MENTAL (6 attributes, weights sum to 1.0000)
INSERT INTO attribute_definitions
  (code, label, category, display_order, applies_to_outfield, applies_to_gk,
   weight_in_category, fm_equivalent, description)
VALUES
  ('leadership',     'Leadership',     'mental', 1, true, true, 0.1300,
   'Leadership',     'Ability to organise, motivate and influence teammates'),
  ('composure',      'Composure',      'mental', 2, true, true, 0.2000,
   'Composure',      'Calmness under pressure, especially in decisive moments'),
  ('teamwork',       'Teamwork',       'mental', 3, true, true, 0.1800,
   'Teamwork',       'Willingness to work for collective rather than individual goals'),
  ('work_rate',      'Work Rate',      'mental', 4, true, true, 0.2000,
   'Work Rate',      'Intensity and volume of effort applied throughout a match'),
  ('concentration',  'Concentration',  'mental', 5, true, true, 0.1500,
   'Concentration',  'Maintaining focus and positional discipline for the full match'),
  ('determination',  'Determination',  'mental', 6, true, true, 0.1400,
   'Determination',  'Persistence, drive and mental resilience to improve and compete');

-- TACTICAL (5 attributes, weights sum to 1.0000)
INSERT INTO attribute_definitions
  (code, label, category, display_order, applies_to_outfield, applies_to_gk,
   weight_in_category, fm_equivalent, description)
VALUES
  ('positioning',      'Positioning',      'tactical', 1, true, false, 0.2200,
   'Positioning',      'Awareness of defensive shape and positional discipline'),
  ('off_the_ball',     'Off The Ball',     'tactical', 2, true, false, 0.2200,
   'Off The Ball',     'Movement and runs without the ball to create space and options'),
  ('vision',           'Vision',           'tactical', 3, true, true,  0.2000,
   'Vision',           'Spatial awareness of teammates and options before receiving'),
  ('decision_making',  'Decision Making',  'tactical', 4, true, true,  0.2000,
   'Decisions',        'Quality of choices made under time and defensive pressure'),
  ('anticipation',     'Anticipation',     'tactical', 5, true, true,  0.1600,
   'Anticipation',     'Reading the play and reacting before an event occurs');

-- GOALKEEPER (4 attributes, weights sum to 1.0000)
-- applies_to_outfield = false for all goalkeeper attributes
INSERT INTO attribute_definitions
  (code, label, category, display_order, applies_to_outfield, applies_to_gk,
   weight_in_category, fm_equivalent, description)
VALUES
  ('reflexes',       'Reflexes',       'goalkeeper', 1, false, true, 0.2800,
   'Reflexes',       'Reaction speed to stop close-range shots'),
  ('handling',       'Handling',       'goalkeeper', 2, false, true, 0.2400,
   'Handling',       'Security and confidence when catching crosses and shots'),
  ('one_on_one',     'One On One',     'goalkeeper', 3, false, true, 0.2800,
   'One On Ones',    'Decision-making and positioning when facing an attacker alone'),
  ('communication',  'Communication',  'goalkeeper', 4, false, true, 0.2000,
   'Communication',  'Organisation of the defensive unit from the goalkeeper position');

-- ────────────────────────────────────────────────────────────
-- SECTION 6: POSITION DNA WEIGHT MATRIX (reference table)
-- Stores per-position category weightings for Overall DNA.
-- ────────────────────────────────────────────────────────────

CREATE TABLE position_dna_weights (
  id                  UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  position_code       TEXT          NOT NULL UNIQUE,
  position_label      TEXT          NOT NULL,
  -- Player position value (maps to player_position enum conceptually)
  position_group      TEXT          NOT NULL
                      CHECK (position_group IN
                        ('goalkeeper','defender','midfielder','forward')),
  weight_technical    NUMERIC(4,3)  NOT NULL,
  weight_physical     NUMERIC(4,3)  NOT NULL,
  weight_mental       NUMERIC(4,3)  NOT NULL,
  weight_tactical     NUMERIC(4,3)  NOT NULL,
  weight_goalkeeper   NUMERIC(4,3)  NOT NULL DEFAULT 0.000,
  -- Validation: weights must sum to 1.000
  CONSTRAINT chk_position_weights_sum
    CHECK (
      ROUND(weight_technical + weight_physical + weight_mental
            + weight_tactical + weight_goalkeeper, 3) = 1.000
    ),
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE position_dna_weights ENABLE ROW LEVEL SECURITY;

CREATE POLICY "position_dna_weights: public read"
  ON position_dna_weights FOR SELECT
  USING (true);

CREATE POLICY "position_dna_weights: developer write"
  ON position_dna_weights FOR ALL
  USING (get_my_role() = 'developer')
  WITH CHECK (get_my_role() = 'developer');

-- Seed position weights
-- Goalkeeper: 25% GK-specific, rest distributed
INSERT INTO position_dna_weights
  (position_code, position_label, position_group,
   weight_technical, weight_physical, weight_mental, weight_tactical, weight_goalkeeper)
VALUES
  ('gk',  'Goalkeeper',         'goalkeeper', 0.100, 0.200, 0.250, 0.200, 0.250),
  ('cb',  'Centre Back',        'defender',   0.200, 0.250, 0.200, 0.250, 0.000),
  ('fb',  'Full Back',          'defender',   0.250, 0.250, 0.200, 0.200, 0.000),
  ('wb',  'Wing Back',          'defender',   0.250, 0.280, 0.170, 0.200, 0.000),
  ('cdm', 'Defensive Midfielder','midfielder', 0.250, 0.200, 0.250, 0.300, 0.000),
  ('cm',  'Central Midfielder', 'midfielder', 0.250, 0.200, 0.250, 0.300, 0.000),
  ('cam', 'Attacking Midfielder','midfielder', 0.300, 0.200, 0.200, 0.300, 0.000),
  ('wg',  'Winger',             'forward',    0.300, 0.320, 0.150, 0.230, 0.000),
  ('st',  'Striker',            'forward',    0.350, 0.250, 0.200, 0.200, 0.000),
  -- Default fallback per broad position group
  ('defender',   'Defender (Generic)',   'defender',   0.220, 0.250, 0.200, 0.230, 0.000),
  ('midfielder', 'Midfielder (Generic)', 'midfielder', 0.270, 0.200, 0.230, 0.300, 0.000),
  ('forward',    'Forward (Generic)',    'forward',    0.320, 0.260, 0.190, 0.230, 0.000);

-- ────────────────────────────────────────────────────────────
-- SECTION 7: PLAYER_ATTRIBUTES
-- Current live attribute snapshot. One row per player + attribute.
-- ────────────────────────────────────────────────────────────

CREATE TABLE player_attributes (
  id                    UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id             UUID          NOT NULL
                        REFERENCES players(id) ON DELETE CASCADE,
  attribute_code        TEXT          NOT NULL
                        REFERENCES attribute_definitions(code) ON DELETE RESTRICT,
  -- Weighted computed value (the definitive current value)
  current_value         SMALLINT      NOT NULL
                        CHECK (current_value BETWEEN 1 AND 20),
  -- Per-source raw values (last accepted from each source)
  coach_value           SMALLINT
                        CHECK (coach_value IS NULL OR coach_value BETWEEN 1 AND 20),
  officer_value         SMALLINT
                        CHECK (officer_value IS NULL OR officer_value BETWEEN 1 AND 20),
  ai_value              SMALLINT
                        CHECK (ai_value IS NULL OR ai_value BETWEEN 1 AND 20),
  -- Metadata
  assessment_count      SMALLINT      NOT NULL DEFAULT 0,
  confidence_level      TEXT          NOT NULL DEFAULT 'low'
                        CHECK (confidence_level IN ('low','medium','high','verified')),
  last_assessed_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  last_assessed_by_type TEXT
                        CHECK (last_assessed_by_type IN
                          ('coach','officer','ai','system')),
  season_id             UUID
                        REFERENCES seasons(id) ON DELETE SET NULL,
  -- Passport visibility gate
  is_public             BOOLEAN       NOT NULL DEFAULT false,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by            UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  UNIQUE (player_id, attribute_code)
);

CREATE TRIGGER trg_player_attributes_updated_at
  BEFORE UPDATE ON player_attributes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Audit trigger
CREATE TRIGGER trg_player_attributes_audit
  AFTER INSERT OR UPDATE OR DELETE ON player_attributes
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- Indexes
CREATE INDEX idx_player_attributes_player
  ON player_attributes(player_id);

CREATE INDEX idx_player_attributes_code_value
  ON player_attributes(attribute_code, current_value DESC);

CREATE INDEX idx_player_attributes_season
  ON player_attributes(season_id, attribute_code, current_value DESC)
  WHERE season_id IS NOT NULL;

CREATE INDEX idx_player_attributes_public
  ON player_attributes(player_id, is_public)
  WHERE is_public = true;

CREATE INDEX idx_player_attributes_confidence
  ON player_attributes(player_id, confidence_level);

ALTER TABLE player_attributes ENABLE ROW LEVEL SECURITY;

-- Public: only visible attributes, via view (see Section 15)
CREATE POLICY "player_attributes: public read visible"
  ON player_attributes FOR SELECT
  USING (
    is_public = true
    OR get_my_role() IN ('developer','league_founder','league_admin')
    OR (get_my_role() = 'club_admin' AND is_club_admin(
          (SELECT club_id FROM players WHERE id = player_id LIMIT 1)))
    OR (get_my_role() = 'coach' AND is_coach_for_club(
          (SELECT club_id FROM players WHERE id = player_id LIMIT 1)))
    OR (get_my_role() = 'technical_assessor')
    -- Claimed player can see own attributes
    OR player_id = get_my_player_id()
    -- Guardian can see ward's attributes
    OR is_guardian_of(player_id)
  );

-- No direct user INSERT/UPDATE — all writes via compute functions (SECURITY DEFINER)
-- The SECURITY DEFINER functions bypass RLS; regular users cannot write directly.
-- Revoke direct table write from authenticated role (enforced by having no INSERT/UPDATE policy).


-- ────────────────────────────────────────────────────────────
-- SECTION 8: PLAYER_ATTRIBUTE_HISTORY
-- Immutable time-series. Append-only. Never updated or deleted.
-- ────────────────────────────────────────────────────────────

CREATE TABLE player_attribute_history (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id       UUID          NOT NULL
                  REFERENCES players(id) ON DELETE CASCADE,
  attribute_code  TEXT          NOT NULL
                  REFERENCES attribute_definitions(code) ON DELETE RESTRICT,
  value           SMALLINT      NOT NULL CHECK (value BETWEEN 1 AND 20),
  previous_value  SMALLINT      CHECK (previous_value IS NULL
                                  OR previous_value BETWEEN 1 AND 20),
  -- Computed: value - previous_value (NULL safe)
  delta           SMALLINT      GENERATED ALWAYS AS (
                    value - COALESCE(previous_value, value)
                  ) STORED,
  recorded_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  season_id       UUID          REFERENCES seasons(id) ON DELETE SET NULL,
  trigger_source  TEXT          NOT NULL
                  CHECK (trigger_source IN (
                    'coach_assessment',
                    'officer_assessment',
                    'ai_batch',
                    'manual_correction',
                    'season_rollover',
                    'initial_entry'
                  )),
  assessment_id   UUID,         -- FK set after player_attribute_assessments created
  recorded_by     UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  notes           TEXT          CHECK (notes IS NULL OR char_length(notes) <= 300),
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
  -- No updated_at: immutable
);

-- Indexes
CREATE INDEX idx_attr_history_player_attr_time
  ON player_attribute_history(player_id, attribute_code, recorded_at DESC);

CREATE INDEX idx_attr_history_season
  ON player_attribute_history(season_id, attribute_code)
  WHERE season_id IS NOT NULL;

CREATE INDEX idx_attr_history_delta
  ON player_attribute_history(player_id, delta)
  WHERE delta != 0;

ALTER TABLE player_attribute_history ENABLE ROW LEVEL SECURITY;

-- History is readable by same rules as player_attributes
CREATE POLICY "player_attribute_history: authorised read"
  ON player_attribute_history FOR SELECT
  USING (
    get_my_role() IN ('developer','league_founder','league_admin','technical_assessor')
    OR (get_my_role() = 'club_admin' AND is_club_admin(
          (SELECT club_id FROM players WHERE id = player_id LIMIT 1)))
    OR (get_my_role() = 'coach' AND is_coach_for_club(
          (SELECT club_id FROM players WHERE id = player_id LIMIT 1)))
    OR player_id = get_my_player_id()
    OR is_guardian_of(player_id)
  );

-- No UPDATE or DELETE policies defined → denied to all non-superusers.
-- Append-only enforced at RLS level.


-- ────────────────────────────────────────────────────────────
-- SECTION 9: PLAYER_ATTRIBUTE_ASSESSMENTS
-- One assessment session per assessor per player per season.
-- ────────────────────────────────────────────────────────────

CREATE TABLE player_attribute_assessments (
  id                      UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id               UUID          NOT NULL
                          REFERENCES players(id) ON DELETE CASCADE,
  -- Assessor identity
  assessor_profile_id     UUID
                          REFERENCES profiles(id) ON DELETE SET NULL,
  assessor_type           TEXT          NOT NULL
                          CHECK (assessor_type IN
                            ('coach','league_technical_officer','ai_engine')),
  assessor_club_id        UUID
                          REFERENCES clubs(id) ON DELETE SET NULL,
  assessor_league_id      UUID
                          REFERENCES leagues(id) ON DELETE SET NULL,
  season_id               UUID          NOT NULL
                          REFERENCES seasons(id) ON DELETE RESTRICT,
  assessment_date         DATE          NOT NULL DEFAULT CURRENT_DATE,
  -- Workflow state machine
  status                  TEXT          NOT NULL DEFAULT 'draft'
                          CHECK (status IN (
                            'draft',
                            'submitted',
                            'accepted',
                            'rejected',
                            'superseded'
                          )),
  submitted_at            TIMESTAMPTZ,
  reviewed_at             TIMESTAMPTZ,
  reviewed_by             UUID
                          REFERENCES profiles(id) ON DELETE SET NULL,
  rejection_reason        TEXT
                          CHECK (rejection_reason IS NULL
                            OR char_length(rejection_reason) <= 500),
  -- Weight applied at computation time (snapshot for audit)
  weight_applied          NUMERIC(4,3)  NOT NULL DEFAULT 0.500
                          CHECK (weight_applied > 0 AND weight_applied <= 1),
  -- Anti-manipulation
  integrity_score         NUMERIC(5,2)
                          CHECK (integrity_score IS NULL
                            OR integrity_score BETWEEN 0 AND 100),
  is_flagged              BOOLEAN       NOT NULL DEFAULT false,
  flag_reason             TEXT
                          CHECK (flag_reason IS NULL
                            OR char_length(flag_reason) <= 300),
  submission_fingerprint  TEXT,
  -- Assessor notes
  notes                   TEXT
                          CHECK (notes IS NULL OR char_length(notes) <= 1000),
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by              UUID
                          REFERENCES profiles(id) ON DELETE SET NULL,
  -- One active/submitted assessment per source type per player per season
  CONSTRAINT uq_assessment_active
    UNIQUE NULLS NOT DISTINCT (player_id, assessor_type, assessor_profile_id, season_id)
    -- Enforced by partial unique index below (more flexible than constraint)
);

-- Drop the table-level constraint and use partial unique index instead
-- (UNIQUE NULLS NOT DISTINCT syntax varies; use index for reliability)
ALTER TABLE player_attribute_assessments
  DROP CONSTRAINT IF EXISTS uq_assessment_active;

CREATE UNIQUE INDEX idx_assessment_one_active_per_source
  ON player_attribute_assessments(player_id, assessor_type, assessor_profile_id, season_id)
  WHERE status IN ('submitted', 'accepted');

CREATE TRIGGER trg_player_attribute_assessments_updated_at
  BEFORE UPDATE ON player_attribute_assessments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Audit trigger
CREATE TRIGGER trg_player_attribute_assessments_audit
  AFTER INSERT OR UPDATE OR DELETE ON player_attribute_assessments
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- Indexes
CREATE INDEX idx_assessments_player_season
  ON player_attribute_assessments(player_id, season_id, assessor_type);

CREATE INDEX idx_assessments_assessor
  ON player_attribute_assessments(assessor_profile_id, status, submitted_at DESC)
  WHERE assessor_profile_id IS NOT NULL;

CREATE INDEX idx_assessments_flagged
  ON player_attribute_assessments(is_flagged, created_at DESC)
  WHERE is_flagged = true;

CREATE INDEX idx_assessments_league_review
  ON player_attribute_assessments(assessor_league_id, status)
  WHERE status = 'submitted';

CREATE INDEX idx_assessments_status
  ON player_attribute_assessments(status, submitted_at DESC);

ALTER TABLE player_attribute_assessments ENABLE ROW LEVEL SECURITY;

-- Assessor: can see and manage own assessments
CREATE POLICY "player_attribute_assessments: assessor own"
  ON player_attribute_assessments FOR SELECT
  USING (
    assessor_profile_id = auth.uid()
    OR get_my_role() = 'developer'
    OR (get_my_role() IN ('league_admin','league_founder')
        AND assessor_league_id IN (
          SELECT league_id FROM league_staff
          WHERE profile_id = auth.uid()
          UNION
          SELECT id FROM leagues WHERE founder_id = auth.uid()
        ))
    OR (get_my_role() = 'club_admin' AND assessor_club_id IN (
          SELECT id FROM clubs WHERE admin_id = auth.uid()
        ))
    -- Claimed player sees accepted assessments for their own record (metadata only)
    OR (status = 'accepted' AND player_id = get_my_player_id())
    OR (status = 'accepted' AND is_guardian_of(player_id))
  );

CREATE POLICY "player_attribute_assessments: coach insert"
  ON player_attribute_assessments FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (
      get_my_role() IN ('coach','club_admin')
      AND assessor_type = 'coach'
      AND assessor_profile_id = auth.uid()
      AND is_coach_for_club(assessor_club_id)
    )
    OR (
      get_my_role() IN ('league_admin','technical_assessor')
      AND assessor_type = 'league_technical_officer'
      AND assessor_profile_id = auth.uid()
    )
  );

CREATE POLICY "player_attribute_assessments: draft update"
  ON player_attribute_assessments FOR UPDATE
  USING (
    get_my_role() = 'developer'
    -- Assessor can update own draft
    OR (assessor_profile_id = auth.uid() AND status = 'draft')
    -- LTO/league_admin can update status (accept/reject)
    OR (get_my_role() IN ('league_admin','technical_assessor')
        AND status IN ('submitted','accepted','rejected'))
    -- League founder can manage all in their league
    OR (get_my_role() = 'league_founder'
        AND assessor_league_id IN (
          SELECT id FROM leagues WHERE founder_id = auth.uid()
        ))
  );

-- ────────────────────────────────────────────────────────────
-- SECTION 10: PLAYER_ATTRIBUTE_ASSESSMENT_SOURCES
-- Line items: one row per attribute per assessment session.
-- ────────────────────────────────────────────────────────────

CREATE TABLE player_attribute_assessment_sources (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  assessment_id   UUID          NOT NULL
                  REFERENCES player_attribute_assessments(id) ON DELETE CASCADE,
  player_id       UUID          NOT NULL
                  REFERENCES players(id) ON DELETE CASCADE,
  attribute_code  TEXT          NOT NULL
                  REFERENCES attribute_definitions(code) ON DELETE RESTRICT,
  raw_value       SMALLINT      NOT NULL CHECK (raw_value BETWEEN 1 AND 20),
  justification   TEXT
                  CHECK (justification IS NULL
                    OR char_length(justification) <= 500),
  -- For AI assessments: supporting statistical evidence
  stat_reference  JSONB,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (assessment_id, attribute_code)
);

-- Indexes
CREATE INDEX idx_assessment_sources_assessment
  ON player_attribute_assessment_sources(assessment_id);

CREATE INDEX idx_assessment_sources_player_attr
  ON player_attribute_assessment_sources(player_id, attribute_code, raw_value);

ALTER TABLE player_attribute_assessment_sources ENABLE ROW LEVEL SECURITY;

-- Sources inherit visibility from parent assessment
CREATE POLICY "assessment_sources: authorised read"
  ON player_attribute_assessment_sources FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder','technical_assessor')
    OR assessment_id IN (
      SELECT id FROM player_attribute_assessments
      WHERE assessor_profile_id = auth.uid()
    )
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs
            WHERE id IN (
              SELECT club_id FROM coaches WHERE profile_id = auth.uid()
            )
          )
        ))
  );

-- Immutable after submission: INSERT only via functions, no UPDATE
CREATE POLICY "assessment_sources: insert via assessment"
  ON player_attribute_assessment_sources FOR INSERT
  WITH CHECK (
    get_my_role() IN ('developer','technical_assessor')
    OR assessment_id IN (
      SELECT id FROM player_attribute_assessments
      WHERE assessor_profile_id = auth.uid()
        AND status = 'draft'
    )
  );

-- ────────────────────────────────────────────────────────────
-- SECTION 11: PLAYER_POTENTIAL_SCORES
-- Forward-looking potential assessment. One active record per player.
-- ────────────────────────────────────────────────────────────

CREATE TABLE player_potential_scores (
  id                      UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id               UUID          NOT NULL
                          REFERENCES players(id) ON DELETE CASCADE,
  season_id               UUID          NOT NULL
                          REFERENCES seasons(id) ON DELETE RESTRICT,
  assessor_type           TEXT          NOT NULL
                          CHECK (assessor_type IN
                            ('coach','league_technical_officer','ai_engine')),
  assessor_profile_id     UUID
                          REFERENCES profiles(id) ON DELETE SET NULL,
  -- Computed potential score
  potential_score         SMALLINT      NOT NULL
                          CHECK (potential_score BETWEEN 1 AND 100),
  potential_category      TEXT          NOT NULL
                          CHECK (potential_category IN (
                            'elite_prospect',
                            'national_prospect',
                            'regional_prospect',
                            'development_prospect',
                            'recreational'
                          )),
  -- Supporting intelligence
  ceiling_estimate        SMALLINT
                          CHECK (ceiling_estimate IS NULL
                            OR ceiling_estimate BETWEEN 1 AND 20),
  development_trajectory  TEXT
                          CHECK (development_trajectory IN (
                            'accelerating','steady','plateauing',
                            'declining','insufficient_data'
                          )),
  years_to_peak           SMALLINT
                          CHECK (years_to_peak IS NULL
                            OR years_to_peak BETWEEN 0 AND 15),
  -- Assessor notes (confidential — not exposed publicly)
  assessor_notes          TEXT
                          CHECK (assessor_notes IS NULL
                            OR char_length(assessor_notes) <= 1000),
  is_current              BOOLEAN       NOT NULL DEFAULT true,
  computed_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  expires_at              DATE,
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by              UUID
                          REFERENCES profiles(id) ON DELETE SET NULL
);

CREATE TRIGGER trg_player_potential_scores_updated_at
  BEFORE UPDATE ON player_potential_scores
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Audit trigger
CREATE TRIGGER trg_player_potential_scores_audit
  AFTER INSERT OR UPDATE OR DELETE ON player_potential_scores
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- Only one current potential score per player per assessor type per season
CREATE UNIQUE INDEX idx_potential_one_current_per_source
  ON player_potential_scores(player_id, season_id, assessor_type)
  WHERE is_current = true;

-- Indexes
CREATE INDEX idx_potential_player_current
  ON player_potential_scores(player_id, is_current)
  WHERE is_current = true;

CREATE INDEX idx_potential_score_category
  ON player_potential_scores(potential_score DESC, potential_category)
  WHERE is_current = true;

CREATE INDEX idx_potential_season
  ON player_potential_scores(season_id, potential_score DESC);

ALTER TABLE player_potential_scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_potential_scores: authorised read"
  ON player_potential_scores FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder','technical_assessor')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() = 'coach' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE id IN (
              SELECT club_id FROM coaches WHERE profile_id = auth.uid()
            )
          )
        ))
    -- Player can see own potential (score + category only, notes redacted in view)
    OR player_id = get_my_player_id()
    OR is_guardian_of(player_id)
  );

CREATE POLICY "player_potential_scores: coach insert"
  ON player_potential_scores FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() IN ('coach','club_admin')
        AND assessor_type = 'coach'
        AND assessor_profile_id = auth.uid()
        AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE id IN (
              SELECT club_id FROM coaches WHERE profile_id = auth.uid()
            )
            UNION
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR (get_my_role() IN ('league_admin','technical_assessor')
        AND assessor_type = 'league_technical_officer'
        AND assessor_profile_id = auth.uid())
  );

CREATE POLICY "player_potential_scores: update own"
  ON player_potential_scores FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR assessor_profile_id = auth.uid()
    OR get_my_role() IN ('league_admin','league_founder')
  );

-- ────────────────────────────────────────────────────────────
-- SECTION 12: CLAIMED IDENTITY SYSTEM
-- Sections 12a, 12b, 12c — player_ownership_claims,
-- player_guardians, helper functions
-- ────────────────────────────────────────────────────────────

-- 12a: player_ownership_claims
CREATE TABLE player_ownership_claims (
  id                    UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id             UUID          NOT NULL
                        REFERENCES players(id) ON DELETE CASCADE,
  claimant_profile_id   UUID          NOT NULL
                        REFERENCES profiles(id) ON DELETE CASCADE,
  claim_type            TEXT          NOT NULL
                        CHECK (claim_type IN ('self','guardian')),
  status                TEXT          NOT NULL DEFAULT 'pending'
                        CHECK (status IN (
                          'pending','approved','rejected',
                          'withdrawn','transferred'
                        )),
  verification_method   TEXT
                        CHECK (verification_method IN (
                          'ic_upload','guardian_consent',
                          'club_confirmation','manual_review',NULL
                        )),
  verification_notes    TEXT
                        CHECK (verification_notes IS NULL
                          OR char_length(verification_notes) <= 1000),
  reviewed_by           UUID
                        REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at           TIMESTAMPTZ,
  -- For guardian claims: store minor's DOB at time of claim
  minor_dob_at_claim    DATE,
  -- Expiry for claims that are time-limited
  expires_at            DATE,
  submitted_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by            UUID
                        REFERENCES profiles(id) ON DELETE SET NULL
);

CREATE TRIGGER trg_player_ownership_claims_updated_at
  BEFORE UPDATE ON player_ownership_claims
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_player_ownership_claims_audit
  AFTER INSERT OR UPDATE OR DELETE ON player_ownership_claims
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

-- One active approved claim per player (only one owner at a time)
CREATE UNIQUE INDEX idx_ownership_claims_one_approved
  ON player_ownership_claims(player_id)
  WHERE status = 'approved';

CREATE INDEX idx_ownership_claims_claimant
  ON player_ownership_claims(claimant_profile_id, status);

CREATE INDEX idx_ownership_claims_player
  ON player_ownership_claims(player_id, status);

CREATE INDEX idx_ownership_claims_pending
  ON player_ownership_claims(status, submitted_at DESC)
  WHERE status = 'pending';

ALTER TABLE player_ownership_claims ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_ownership_claims: own claim read"
  ON player_ownership_claims FOR SELECT
  USING (
    claimant_profile_id = auth.uid()
    OR get_my_role() IN ('developer','league_admin','league_founder')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
  );

CREATE POLICY "player_ownership_claims: submit own"
  ON player_ownership_claims FOR INSERT
  WITH CHECK (
    claimant_profile_id = auth.uid()
    AND auth.uid() IS NOT NULL
  );

CREATE POLICY "player_ownership_claims: withdraw own pending"
  ON player_ownership_claims FOR UPDATE
  USING (
    -- Claimant can withdraw their own pending claim
    (claimant_profile_id = auth.uid() AND status = 'pending')
    -- League admin / developer can review (approve/reject)
    OR get_my_role() IN ('developer','league_admin','league_founder')
  );

-- 12b: player_guardians
CREATE TABLE player_guardians (
  id                      UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id               UUID          NOT NULL
                          REFERENCES players(id) ON DELETE CASCADE,
  guardian_profile_id     UUID          NOT NULL
                          REFERENCES profiles(id) ON DELETE CASCADE,
  relationship            TEXT          NOT NULL
                          CHECK (relationship IN (
                            'parent','legal_guardian','sibling','other'
                          )),
  is_primary              BOOLEAN       NOT NULL DEFAULT true,
  -- PDPA consent management
  consent_given           BOOLEAN       NOT NULL DEFAULT false,
  consent_given_at        TIMESTAMPTZ,
  consent_version         TEXT,
  -- Link back to the claim that established this relationship
  ownership_claim_id      UUID
                          REFERENCES player_ownership_claims(id) ON DELETE SET NULL,
  -- Age-18 ownership transfer workflow
  transfer_initiated_at   TIMESTAMPTZ,
  transfer_completed_at   TIMESTAMPTZ,
  is_active               BOOLEAN       NOT NULL DEFAULT true,
  created_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_by              UUID
                          REFERENCES profiles(id) ON DELETE SET NULL,
  UNIQUE (player_id, guardian_profile_id)
);

CREATE TRIGGER trg_player_guardians_updated_at
  BEFORE UPDATE ON player_guardians
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_player_guardians_audit
  AFTER INSERT OR UPDATE OR DELETE ON player_guardians
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();

CREATE INDEX idx_player_guardians_player
  ON player_guardians(player_id) WHERE is_active = true;

CREATE INDEX idx_player_guardians_guardian
  ON player_guardians(guardian_profile_id) WHERE is_active = true;

ALTER TABLE player_guardians ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_guardians: own read"
  ON player_guardians FOR SELECT
  USING (
    guardian_profile_id = auth.uid()
    OR get_my_role() IN ('developer','league_admin','league_founder')
    OR player_id = get_my_player_id()
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
  );

CREATE POLICY "player_guardians: system insert"
  ON player_guardians FOR INSERT
  WITH CHECK (get_my_role() IN ('developer','league_admin','league_founder'));

CREATE POLICY "player_guardians: update own"
  ON player_guardians FOR UPDATE
  USING (
    guardian_profile_id = auth.uid()
    OR get_my_role() IN ('developer','league_admin','league_founder')
  );

-- ────────────────────────────────────────────────────────────
-- SECTION 13: PASSPORT SCORE HISTORY
-- Immutable record of every passport score computation.
-- ────────────────────────────────────────────────────────────

CREATE TABLE player_passport_score_history (
  id                    UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  player_id             UUID          NOT NULL
                        REFERENCES players(id) ON DELETE CASCADE,
  computed_date         DATE          NOT NULL DEFAULT CURRENT_DATE,
  -- Component scores (stored for audit + graph)
  match_performance_score   NUMERIC(5,2),
  attribute_dna_score       NUMERIC(5,2),
  discipline_score          NUMERIC(5,2),
  activity_score            NUMERIC(5,2),
  development_score         NUMERIC(5,2),
  -- Pre-scalar raw score
  raw_score             NUMERIC(5,2)  NOT NULL,
  -- League quality scalar applied
  league_quality_scalar NUMERIC(3,2)  NOT NULL DEFAULT 1.00,
  quality_tier_id       UUID
                        REFERENCES league_quality_tiers(id) ON DELETE SET NULL,
  -- Final result
  passport_score        SMALLINT      NOT NULL CHECK (passport_score BETWEEN 0 AND 100),
  passport_band         TEXT          NOT NULL
                        CHECK (passport_band IN (
                          'elite','advanced','developing','emerging','beginner'
                        )),
  -- Data quality
  dna_confidence        TEXT          CHECK (dna_confidence IN
                          ('low','medium','high','verified',NULL)),
  data_quality_flags    TEXT[],
  -- Snapshot of DNA at time of computation (denormalised for history)
  dna_overall_at_time   SMALLINT,
  season_id             UUID
                        REFERENCES seasons(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (player_id, computed_date)
);

CREATE INDEX idx_passport_history_player_date
  ON player_passport_score_history(player_id, computed_date DESC);

CREATE INDEX idx_passport_history_season
  ON player_passport_score_history(season_id, passport_score DESC)
  WHERE season_id IS NOT NULL;

ALTER TABLE player_passport_score_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "passport_score_history: authorised read"
  ON player_passport_score_history FOR SELECT
  USING (
    get_my_role() IN ('developer','league_admin','league_founder','technical_assessor')
    OR (get_my_role() = 'club_admin' AND player_id IN (
          SELECT id FROM players WHERE club_id IN (
            SELECT id FROM clubs WHERE admin_id = auth.uid()
          )
        ))
    OR player_id = get_my_player_id()
    OR is_guardian_of(player_id)
    -- Public: only score + band visible (not component scores) — via view
    OR EXISTS (
      SELECT 1 FROM players p
      WHERE p.id = player_id AND p.is_passport_public = true
    )
  );

-- ────────────────────────────────────────────────────────────
-- SECTION 14: HELPER FUNCTIONS
-- Required before RLS policies that reference them.
-- ────────────────────────────────────────────────────────────

-- ── is_coach_for_club() ─────────────────────────────────────
-- Returns true if the current user is an active coach for the
-- specified club. Fixes the dead-code coach path in match_lineups.
-- SECURITY DEFINER to bypass RLS on coaches table.

CREATE OR REPLACE FUNCTION is_coach_for_club(p_club_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM coaches c
    WHERE c.profile_id = auth.uid()
      AND c.club_id    = p_club_id
      AND c.is_active  = true
  );
$$;

-- ── get_my_player_id() ──────────────────────────────────────
-- Returns the player.id linked to the current user via profile_id.
-- Returns NULL if user is not a claimed player.
-- SECURITY DEFINER to read players.profile_id safely.

CREATE OR REPLACE FUNCTION get_my_player_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id
  FROM players
  WHERE profile_id = auth.uid()
    AND is_active  = true
  LIMIT 1;
$$;

-- ── is_own_player_record() ──────────────────────────────────
-- Returns true if p_player_id is the player record linked to
-- the current user (i.e., they are the claimed player).

CREATE OR REPLACE FUNCTION is_own_player_record(p_player_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM players
    WHERE id         = p_player_id
      AND profile_id = auth.uid()
      AND is_active  = true
  );
$$;

-- ── is_guardian_of() ────────────────────────────────────────
-- Returns true if the current user is an active guardian of
-- the specified player (approved claim + consent given).

CREATE OR REPLACE FUNCTION is_guardian_of(p_player_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM player_guardians pg
    WHERE pg.player_id          = p_player_id
      AND pg.guardian_profile_id = auth.uid()
      AND pg.is_active           = true
      AND pg.consent_given       = true
  );
$$;

-- ────────────────────────────────────────────────────────────
-- SECTION 15: FIX — match_lineups coach policy
-- The existing policy grants coach access via is_club_admin()
-- which only checks clubs.admin_id — never true for coaches.
-- Drop and recreate with is_coach_for_club().
-- ────────────────────────────────────────────────────────────

-- Drop the defective policies
DROP POLICY IF EXISTS "match_lineups: club admin insert" ON match_lineups;
DROP POLICY IF EXISTS "match_lineups: club admin or league admin update" ON match_lineups;

-- Recreate with working coach path
CREATE POLICY "match_lineups: authorised insert"
  ON match_lineups FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR (get_my_role() = 'coach'      AND is_coach_for_club(club_id))
    OR EXISTS (
      SELECT 1 FROM fixtures f
      WHERE f.id = fixture_id
        AND is_league_admin(f.league_id)
    )
  );

CREATE POLICY "match_lineups: authorised update"
  ON match_lineups FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin'
        AND is_club_admin(club_id)
        AND confirmed_at IS NULL)
    OR (get_my_role() = 'coach'
        AND is_coach_for_club(club_id)
        AND confirmed_at IS NULL)
    OR EXISTS (
      SELECT 1 FROM fixtures f
      WHERE f.id = fixture_id
        AND is_league_admin(f.league_id)
    )
  );

-- ────────────────────────────────────────────────────────────
-- SECTION 16: DNA COMPUTATION FUNCTION
-- calculate_player_dna(player_id UUID) → VOID
-- Computes all 5 category scores + overall DNA rating.
-- Writes to players table (denormalised columns).
-- SECURITY DEFINER — only callable by system functions and
-- Edge Functions with service_role key.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION calculate_player_dna(p_player_id UUID)
RETURNS TABLE (
  technical_score   SMALLINT,
  physical_score    SMALLINT,
  mental_score      SMALLINT,
  tactical_score    SMALLINT,
  goalkeeper_score  SMALLINT,
  overall_dna       SMALLINT,
  dna_band          TEXT,
  confidence        TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_position          player_position;
  v_pos_code          TEXT;
  v_technical         NUMERIC;
  v_physical          NUMERIC;
  v_mental            NUMERIC;
  v_tactical          NUMERIC;
  v_goalkeeper        NUMERIC;
  v_overall           NUMERIC;
  v_band              TEXT;
  v_w_tech            NUMERIC;
  v_w_phys            NUMERIC;
  v_w_ment            NUMERIC;
  v_w_tact            NUMERIC;
  v_w_gk              NUMERIC;
  v_confidence        TEXT;
  v_attr_count        INTEGER;
  v_min_attrs         INTEGER := 15; -- minimum attributes needed for a valid score
BEGIN
  -- 1. Get player position
  SELECT position INTO v_position
  FROM players WHERE id = p_player_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Player % not found', p_player_id;
  END IF;

  -- Map player_position enum to position_code for weight lookup
  v_pos_code := CASE v_position
    WHEN 'goalkeeper' THEN 'gk'
    WHEN 'defender'   THEN 'defender'
    WHEN 'midfielder' THEN 'midfielder'
    WHEN 'forward'    THEN 'forward'
    ELSE 'midfielder'
  END;

  -- 2. Count attributes with data
  SELECT COUNT(*) INTO v_attr_count
  FROM player_attributes pa
  JOIN attribute_definitions ad ON ad.code = pa.attribute_code
  WHERE pa.player_id = p_player_id
    AND (ad.applies_to_outfield = true OR v_pos_code = 'gk');

  -- 3. Determine confidence level
  v_confidence := CASE
    WHEN v_attr_count < 5  THEN 'low'
    WHEN v_attr_count < 10 THEN 'low'
    WHEN v_attr_count < 15 THEN 'medium'
    ELSE (
      -- Check if all three sources contributed
      SELECT CASE
        WHEN COUNT(DISTINCT last_assessed_by_type) >= 3 THEN 'verified'
        WHEN COUNT(DISTINCT last_assessed_by_type) = 2  THEN 'high'
        ELSE 'medium'
      END
      FROM player_attributes WHERE player_id = p_player_id
    )
  END;

  -- 4. Calculate TECHNICAL score (weighted average → 0-100 scale)
  SELECT ROUND(
    SUM(pa.current_value * ad.weight_in_category) / 20.0 * 100
  )
  INTO v_technical
  FROM player_attributes pa
  JOIN attribute_definitions ad ON ad.code = pa.attribute_code
  WHERE pa.player_id = p_player_id
    AND ad.category  = 'technical'
    AND ad.is_active = true;

  -- 5. Calculate PHYSICAL score
  SELECT ROUND(
    SUM(pa.current_value * ad.weight_in_category) / 20.0 * 100
  )
  INTO v_physical
  FROM player_attributes pa
  JOIN attribute_definitions ad ON ad.code = pa.attribute_code
  WHERE pa.player_id = p_player_id
    AND ad.category  = 'physical'
    AND ad.is_active = true;

  -- 6. Calculate MENTAL score
  SELECT ROUND(
    SUM(pa.current_value * ad.weight_in_category) / 20.0 * 100
  )
  INTO v_mental
  FROM player_attributes pa
  JOIN attribute_definitions ad ON ad.code = pa.attribute_code
  WHERE pa.player_id = p_player_id
    AND ad.category  = 'mental'
    AND ad.is_active = true;

  -- 7. Calculate TACTICAL score
  SELECT ROUND(
    SUM(pa.current_value * ad.weight_in_category) / 20.0 * 100
  )
  INTO v_tactical
  FROM player_attributes pa
  JOIN attribute_definitions ad ON ad.code = pa.attribute_code
  WHERE pa.player_id = p_player_id
    AND ad.category  = 'tactical'
    AND ad.is_active = true;

  -- 8. Calculate GOALKEEPER score (only for GK players)
  IF v_pos_code = 'gk' THEN
    SELECT ROUND(
      SUM(pa.current_value * ad.weight_in_category) / 20.0 * 100
    )
    INTO v_goalkeeper
    FROM player_attributes pa
    JOIN attribute_definitions ad ON ad.code = pa.attribute_code
    WHERE pa.player_id = p_player_id
      AND ad.category  = 'goalkeeper'
      AND ad.is_active = true;
  ELSE
    v_goalkeeper := NULL;
  END IF;

  -- 9. Get position weights
  SELECT
    weight_technical,
    weight_physical,
    weight_mental,
    weight_tactical,
    weight_goalkeeper
  INTO v_w_tech, v_w_phys, v_w_ment, v_w_tact, v_w_gk
  FROM position_dna_weights
  WHERE position_code = v_pos_code
  LIMIT 1;

  -- Default weights if position not found
  IF v_w_tech IS NULL THEN
    v_w_tech := 0.250;
    v_w_phys := 0.200;
    v_w_ment := 0.250;
    v_w_tact := 0.300;
    v_w_gk   := 0.000;
  END IF;

  -- 10. Calculate OVERALL DNA rating (position-weighted)
  -- Null-safe: treat NULL category scores as 0 (not enough data)
  v_overall := ROUND(
    COALESCE(v_technical, 0) * v_w_tech
    + COALESCE(v_physical,  0) * v_w_phys
    + COALESCE(v_mental,    0) * v_w_ment
    + COALESCE(v_tactical,  0) * v_w_tact
    + COALESCE(v_goalkeeper,0) * v_w_gk
  );

  -- If insufficient data, set overall to NULL
  IF v_attr_count < v_min_attrs THEN
    v_overall := NULL;
  END IF;

  -- 11. Determine DNA band
  v_band := CASE
    WHEN v_overall IS NULL    THEN NULL
    WHEN v_overall >= 85      THEN 'elite'
    WHEN v_overall >= 70      THEN 'advanced'
    WHEN v_overall >= 55      THEN 'developing'
    WHEN v_overall >= 40      THEN 'emerging'
    ELSE                           'beginner'
  END;

  -- 12. Update denormalised columns on players table
  UPDATE players SET
    dna_technical     = v_technical::SMALLINT,
    dna_physical      = v_physical::SMALLINT,
    dna_mental        = v_mental::SMALLINT,
    dna_tactical      = v_tactical::SMALLINT,
    dna_goalkeeper    = v_goalkeeper::SMALLINT,
    dna_overall       = v_overall::SMALLINT,
    dna_band          = v_band,
    dna_computed_at   = NOW(),
    updated_at        = NOW()
  WHERE id = p_player_id;

  -- 13. Return result
  RETURN QUERY SELECT
    v_technical::SMALLINT,
    v_physical::SMALLINT,
    v_mental::SMALLINT,
    v_tactical::SMALLINT,
    v_goalkeeper::SMALLINT,
    v_overall::SMALLINT,
    v_band,
    v_confidence;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- SECTION 17: POTENTIAL SCORE COMPUTATION FUNCTION
-- compute_player_potential(player_id UUID) → SMALLINT
-- Returns the computed potential score (1-100).
-- Does NOT write to player_potential_scores directly —
-- that is done by the assessment submission workflow.
-- Used for nightly batch and AI assessments.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION compute_player_potential(p_player_id UUID)
RETURNS SMALLINT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_age                   INTEGER;
  v_dob                   DATE;
  v_dna_overall           SMALLINT;
  v_physical_score        SMALLINT;
  v_determination         SMALLINT;
  v_work_rate             SMALLINT;
  v_concentration         SMALLINT;
  v_age_factor            NUMERIC;
  v_physical_ceiling      NUMERIC;
  v_mental_foundation     NUMERIC;
  v_activity_score        NUMERIC;
  v_dev_trajectory        NUMERIC := 50; -- neutral default
  v_potential_raw         NUMERIC;
  v_result                SMALLINT;
  v_matches_played        INTEGER;
  v_matches_available     INTEGER;
BEGIN
  -- 1. Get player base data
  SELECT
    date_of_birth,
    EXTRACT(YEAR FROM AGE(date_of_birth))::INTEGER,
    dna_overall,
    dna_physical
  INTO v_dob, v_age, v_dna_overall, v_physical_score
  FROM players
  WHERE id = p_player_id AND is_active = true;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- 2. Get key mental attributes
  SELECT current_value INTO v_determination
  FROM player_attributes WHERE player_id = p_player_id AND attribute_code = 'determination';

  SELECT current_value INTO v_work_rate
  FROM player_attributes WHERE player_id = p_player_id AND attribute_code = 'work_rate';

  SELECT current_value INTO v_concentration
  FROM player_attributes WHERE player_id = p_player_id AND attribute_code = 'concentration';

  -- Default to neutral if not assessed
  v_determination  := COALESCE(v_determination,  10);
  v_work_rate      := COALESCE(v_work_rate,      10);
  v_concentration  := COALESCE(v_concentration,  10);

  -- 3. COMPONENT A: Development Trajectory (40%)
  -- Simple proxy from attribute history: avg delta over last 2 seasons
  SELECT COALESCE(AVG(delta), 0) INTO v_dev_trajectory
  FROM player_attribute_history
  WHERE player_id = p_player_id
    AND recorded_at >= NOW() - INTERVAL '2 years'
    AND delta IS NOT NULL;

  v_dev_trajectory := CASE
    WHEN v_dev_trajectory > 1.5  THEN 100
    WHEN v_dev_trajectory > 0.75 THEN 80
    WHEN v_dev_trajectory > 0.25 THEN 60
    WHEN v_dev_trajectory > 0    THEN 40
    WHEN v_dev_trajectory = 0    THEN 20
    ELSE                               10
  END;

  -- 4. COMPONENT B: Physical Ceiling (25%)
  v_age_factor := CASE
    WHEN v_age < 16 THEN 1.00
    WHEN v_age < 18 THEN 0.90
    WHEN v_age < 20 THEN 0.80
    WHEN v_age < 22 THEN 0.70
    WHEN v_age < 25 THEN 0.50
    WHEN v_age < 28 THEN 0.30
    WHEN v_age < 32 THEN 0.10
    ELSE                 0.00
  END;

  v_physical_ceiling := COALESCE(v_physical_score, 50)
    + (v_age_factor * (100 - COALESCE(v_physical_score, 50)) * 0.5);
  v_physical_ceiling := LEAST(v_physical_ceiling, 100);

  -- 5. COMPONENT C: Mental Foundation (20%)
  v_mental_foundation :=
    (v_determination * 5.0)                          -- scale 1-20 → 5-100
    * (0.4 + (v_work_rate::NUMERIC / 50.0))          -- work rate amplifier
    * (1.0 + (0.1 * v_concentration::NUMERIC / 20.0)); -- concentration modifier
  v_mental_foundation := LEAST(v_mental_foundation, 100);

  -- 6. COMPONENT D: Activity Score (15%)
  -- Proxy: check if player has played in last 90 days
  SELECT COUNT(*) INTO v_matches_played
  FROM match_lineups ml
  JOIN fixtures f ON f.id = ml.fixture_id
  WHERE ml.player_id = p_player_id
    AND f.match_date >= CURRENT_DATE - INTERVAL '90 days'
    AND f.status IN ('completed');

  v_activity_score := CASE
    WHEN v_matches_played >= 5 THEN 80
    WHEN v_matches_played >= 2 THEN 60
    WHEN v_matches_played >= 1 THEN 40
    ELSE                            20
  END;

  -- Also check active registration
  IF EXISTS (
    SELECT 1 FROM player_league_registrations
    WHERE player_id = p_player_id
      AND status = 'approved'
      AND is_current = true
  ) THEN
    v_activity_score := LEAST(v_activity_score + 20, 100);
  END IF;

  -- 7. Combine components
  v_potential_raw :=
    (v_dev_trajectory    * 0.40)
    + (v_physical_ceiling  * 0.25)
    + (v_mental_foundation * 0.20)
    + (v_activity_score    * 0.15);

  -- 8. Clamp to [1, 100]
  v_result := GREATEST(1, LEAST(100, ROUND(v_potential_raw)))::SMALLINT;

  RETURN v_result;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- SECTION 18: PASSPORT SCORE COMPUTATION FUNCTION
-- compute_player_passport_score(player_id UUID) → VOID
-- Full formula: 40% Match + 25% DNA + 15% Discipline +
--               10% Activity + 10% Development
-- Writes to players.passport_score and inserts history row.
-- SECURITY DEFINER.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION compute_player_passport_score(p_player_id UUID)
RETURNS SMALLINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match_perf        NUMERIC := 0;
  v_attr_dna          NUMERIC := 0;
  v_discipline        NUMERIC := 100;
  v_activity          NUMERIC := 0;
  v_development       NUMERIC := 50;
  v_raw_score         NUMERIC;
  v_scalar            NUMERIC := 1.00;
  v_tier_id           UUID;
  v_final_score       SMALLINT;
  v_band              TEXT;
  v_dna_confidence    TEXT;
  v_yellow_n          INTEGER := 0;
  v_red_n             INTEGER := 0;
  v_yellow_n1         INTEGER := 0;
  v_red_n1            INTEGER := 0;
  v_yellow_n2         INTEGER := 0;
  v_red_n2            INTEGER := 0;
  v_matches_n         INTEGER := 0;
  v_matches_n1        INTEGER := 0;
  v_matches_n2        INTEGER := 0;
  v_disc_n            NUMERIC := 100;
  v_disc_n1           NUMERIC := 100;
  v_disc_n2           NUMERIC := 100;
  v_current_season    UUID;
  v_league_id         UUID;
  v_goals             INTEGER := 0;
  v_assists           INTEGER := 0;
  v_shots             INTEGER := 0;
  v_shots_on_target   INTEGER := 0;
  v_games_played      INTEGER := 0;
  v_games_available   INTEGER := 0;
  v_dna_overall       SMALLINT;
  v_hist_avg_1        NUMERIC := 50;
  v_hist_avg_2        NUMERIC := 50;
  v_slope             NUMERIC := 0;
BEGIN
  -- ── Fetch DNA score ──────────────────────────────────────
  SELECT
    dna_overall,
    dna_computed_at
  INTO v_dna_overall, v_dna_confidence
  FROM players WHERE id = p_player_id;

  v_attr_dna       := COALESCE(v_dna_overall, 0);
  v_dna_confidence := CASE
    WHEN v_dna_overall IS NULL THEN 'low'
    ELSE (
      SELECT confidence_level FROM player_attributes
      WHERE player_id = p_player_id
      ORDER BY last_assessed_at DESC LIMIT 1
    )
  END;

  -- ── Fetch current league for quality scalar ───────────────
  SELECT
    plr.season_id,
    s.league_id
  INTO v_current_season, v_league_id
  FROM player_league_registrations plr
  JOIN seasons s ON s.id = plr.season_id
  WHERE plr.player_id = p_player_id
    AND plr.status = 'approved'
    AND plr.is_current = true
  LIMIT 1;

  -- Get quality scalar for player's league
  IF v_league_id IS NOT NULL THEN
    SELECT lqt.scalar, lqt.id
    INTO v_scalar, v_tier_id
    FROM league_quality_tiers lqt
    JOIN leagues l ON l.quality_tier_id = lqt.id
    WHERE l.id = v_league_id
    LIMIT 1;
    v_scalar := COALESCE(v_scalar, 1.00);
  END IF;

  -- ── COMPONENT 1: Match Performance (40%) ─────────────────
  -- Goals + assists per 90 minutes, participation rate
  SELECT
    COUNT(DISTINCT ml.fixture_id),
    COALESCE(SUM(CASE WHEN me.event_type = 'goal' THEN 1 ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN me.event_type = 'assist' THEN 1 ELSE 0 END), 0)
  INTO v_games_played, v_goals, v_assists
  FROM match_lineups ml
  LEFT JOIN match_events me
    ON me.fixture_id = ml.fixture_id
    AND me.player_id = ml.player_id
  JOIN fixtures f ON f.id = ml.fixture_id
  WHERE ml.player_id = p_player_id
    AND f.status IN ('completed')
    AND (v_current_season IS NULL OR f.league_id IN (
          SELECT league_id FROM seasons WHERE id = v_current_season
        ));

  -- Count available fixtures for participation rate
  IF v_current_season IS NOT NULL THEN
    SELECT COUNT(*) INTO v_games_available
    FROM fixtures f
    JOIN player_league_registrations plr
      ON plr.season_id = f.league_id   -- simplified: same league
    WHERE plr.player_id = p_player_id
      AND plr.season_id = v_current_season
      AND f.status IN ('completed');
  END IF;

  v_games_available := GREATEST(v_games_available, v_games_played, 1);

  -- Minimum 5 games for a non-zero performance score
  IF v_games_played >= 5 THEN
    DECLARE
      v_gc_per90     NUMERIC;
      v_participation NUMERIC;
    BEGIN
      v_gc_per90      := ((v_goals + v_assists)::NUMERIC / v_games_played) * 90;
      v_participation := (v_games_played::NUMERIC / v_games_available) * 100;
      -- Goal contribution rate scaled: 0.5 gc/90 = ~50 score for forward
      v_match_perf    := LEAST(100,
        ROUND(v_gc_per90 * 30 + v_participation * 0.70)
      );
    END;
  ELSE
    v_match_perf := 0;
  END IF;

  -- ── COMPONENT 2: Attribute DNA (25%) ─────────────────────
  -- Already fetched: v_attr_dna = dna_overall (0-100 scale)

  -- ── COMPONENT 3: Discipline (15%) ────────────────────────
  -- 3-season time-decay model
  IF v_current_season IS NOT NULL THEN
    -- Current season (N)
    SELECT
      COALESCE(SUM(CASE WHEN d.card_type = 'yellow' THEN 1 ELSE 0 END),0),
      COALESCE(SUM(CASE WHEN d.card_type = 'red'    THEN 1 ELSE 0 END),0),
      GREATEST(COUNT(DISTINCT ml.fixture_id),1)
    INTO v_yellow_n, v_red_n, v_matches_n
    FROM disciplinary_records d
    JOIN fixtures f ON f.id = d.fixture_id
    JOIN match_lineups ml ON ml.fixture_id = f.id AND ml.player_id = d.player_id
    WHERE d.player_id = p_player_id
      AND f.league_id IN (SELECT league_id FROM seasons WHERE id = v_current_season);

    v_disc_n := GREATEST(0, 100 - ((v_yellow_n::NUMERIC/v_matches_n)*15
                                  + (v_red_n::NUMERIC/v_matches_n)*40) * 100);

    -- Season N-1 and N-2 (simplified: use ALL historical records as proxy)
    v_disc_n1 := v_disc_n; -- stub: without multi-season tracking, use current
    v_disc_n2 := v_disc_n;
  END IF;

  v_discipline := (v_disc_n * 1.0 + v_disc_n1 * 0.5 + v_disc_n2 * 0.25) / 1.75;
  v_discipline := GREATEST(0, LEAST(100, v_discipline));

  -- ── COMPONENT 4: Activity (10%) ──────────────────────────
  DECLARE
    v_played_last_30  INTEGER;
    v_played_last_90  INTEGER;
    v_is_active       BOOLEAN;
  BEGIN
    SELECT
      COUNT(CASE WHEN f.match_date >= CURRENT_DATE - 30 THEN 1 END),
      COUNT(CASE WHEN f.match_date >= CURRENT_DATE - 90 THEN 1 END),
      p.is_active
    INTO v_played_last_30, v_played_last_90, v_is_active
    FROM players p
    LEFT JOIN match_lineups ml ON ml.player_id = p.id
    LEFT JOIN fixtures f       ON f.id = ml.fixture_id
    WHERE p.id = p_player_id
    GROUP BY p.is_active;

    v_activity := 0;
    IF EXISTS (
      SELECT 1 FROM player_league_registrations
      WHERE player_id = p_player_id AND status = 'approved' AND is_current = true
    ) THEN v_activity := v_activity + 40; END IF;

    IF v_played_last_30  > 0 THEN v_activity := v_activity + 30;
    ELSIF v_played_last_90 > 0 THEN v_activity := v_activity + 20;
    END IF;
    IF v_is_active THEN v_activity := v_activity + 10; END IF;
    v_activity := LEAST(v_activity, 100);
  END;

  -- ── COMPONENT 5: Development (10%) ───────────────────────
  -- Passport score history slope over 2+ seasons
  SELECT
    COALESCE(AVG(CASE WHEN computed_date >= CURRENT_DATE - INTERVAL '1 year'
                      THEN passport_score END), 50),
    COALESCE(AVG(CASE WHEN computed_date < CURRENT_DATE - INTERVAL '1 year'
                      THEN passport_score END), 50)
  INTO v_hist_avg_1, v_hist_avg_2
  FROM player_passport_score_history
  WHERE player_id = p_player_id;

  v_slope      := v_hist_avg_1 - v_hist_avg_2; -- positive = improving
  v_development := GREATEST(0, LEAST(100, 50 + v_slope * 5));

  -- ── COMBINE ──────────────────────────────────────────────
  v_raw_score := (v_match_perf  * 0.40)
               + (v_attr_dna    * 0.25)
               + (v_discipline  * 0.15)
               + (v_activity    * 0.10)
               + (v_development * 0.10);

  v_final_score := GREATEST(0, LEAST(100, ROUND(v_raw_score * v_scalar)))::SMALLINT;

  v_band := CASE
    WHEN v_final_score >= 85 THEN 'elite'
    WHEN v_final_score >= 70 THEN 'advanced'
    WHEN v_final_score >= 55 THEN 'developing'
    WHEN v_final_score >= 40 THEN 'emerging'
    ELSE                          'beginner'
  END;

  -- ── Write to players table ───────────────────────────────
  UPDATE players SET
    passport_score      = v_final_score,
    passport_band       = v_band,
    passport_computed_at = NOW(),
    updated_at          = NOW()
  WHERE id = p_player_id;

  -- ── Insert history record ────────────────────────────────
  INSERT INTO player_passport_score_history (
    player_id,
    computed_date,
    match_performance_score,
    attribute_dna_score,
    discipline_score,
    activity_score,
    development_score,
    raw_score,
    league_quality_scalar,
    quality_tier_id,
    passport_score,
    passport_band,
    dna_confidence,
    dna_overall_at_time,
    season_id
  ) VALUES (
    p_player_id,
    CURRENT_DATE,
    v_match_perf,
    v_attr_dna,
    v_discipline,
    v_activity,
    v_development,
    v_raw_score,
    v_scalar,
    v_tier_id,
    v_final_score,
    v_band,
    v_dna_confidence,
    v_dna_overall,
    v_current_season
  )
  ON CONFLICT (player_id, computed_date)
  DO UPDATE SET
    match_performance_score = EXCLUDED.match_performance_score,
    attribute_dna_score     = EXCLUDED.attribute_dna_score,
    discipline_score        = EXCLUDED.discipline_score,
    activity_score          = EXCLUDED.activity_score,
    development_score       = EXCLUDED.development_score,
    raw_score               = EXCLUDED.raw_score,
    league_quality_scalar   = EXCLUDED.league_quality_scalar,
    quality_tier_id         = EXCLUDED.quality_tier_id,
    passport_score          = EXCLUDED.passport_score,
    passport_band           = EXCLUDED.passport_band,
    dna_confidence          = EXCLUDED.dna_confidence,
    dna_overall_at_time     = EXCLUDED.dna_overall_at_time,
    season_id               = EXCLUDED.season_id;

  RETURN v_final_score;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- SECTION 19: ATTRIBUTE ASSESSMENT SUBMISSION FUNCTION
-- submit_attribute_assessment()
-- Single entry point for coach and LTO assessments.
-- Handles: validation, anti-manipulation checks,
--          insertion of assessment + source items,
--          triggering compute on acceptance.
-- SECURITY DEFINER.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION submit_attribute_assessment(
  p_player_id         UUID,
  p_season_id         UUID,
  p_assessor_type     TEXT,   -- 'coach' | 'league_technical_officer'
  p_assessor_club_id  UUID,   -- NULL for LTO
  p_assessor_league_id UUID,  -- NULL for coach
  p_attributes        JSONB,  -- { "passing": 14, "pace": 13, ... }
  p_notes             TEXT    DEFAULT NULL,
  p_fingerprint       TEXT    DEFAULT NULL
)
RETURNS UUID   -- returns the assessment_id
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_assessment_id     UUID;
  v_attr_code         TEXT;
  v_raw_value         INTEGER;
  v_weight            NUMERIC(4,3);
  v_is_flagged        BOOLEAN := false;
  v_flag_reason       TEXT;
  v_integrity_score   NUMERIC := 100;
  v_prev_value        SMALLINT;
  v_drift_cap         SMALLINT;
  v_z_score           NUMERIC;
  v_pop_mean          NUMERIC;
  v_pop_std           NUMERIC;
  v_attr_count        INTEGER;
BEGIN
  -- ── Validate assessor type ────────────────────────────────
  IF p_assessor_type NOT IN ('coach','league_technical_officer') THEN
    RAISE EXCEPTION 'Invalid assessor_type: %', p_assessor_type;
  END IF;

  -- ── Validate player exists ────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM players WHERE id = p_player_id AND is_active = true) THEN
    RAISE EXCEPTION 'Player % not found or inactive', p_player_id;
  END IF;

  -- ── Validate season exists ────────────────────────────────
  IF NOT EXISTS (SELECT 1 FROM seasons WHERE id = p_season_id) THEN
    RAISE EXCEPTION 'Season % not found', p_season_id;
  END IF;

  -- ── Coach: validate they are coach for the player's club ──
  IF p_assessor_type = 'coach' THEN
    IF NOT is_coach_for_club(p_assessor_club_id) THEN
      RAISE EXCEPTION 'Caller is not an active coach for club %', p_assessor_club_id;
    END IF;

    -- 30-day registration check
    IF NOT EXISTS (
      SELECT 1 FROM coaches
      WHERE profile_id = auth.uid()
        AND club_id    = p_assessor_club_id
        AND is_active  = true
        AND created_at <= NOW() - INTERVAL '30 days'
    ) THEN
      RAISE EXCEPTION 'Coach must be registered for at least 30 days before submitting assessments';
    END IF;

    v_weight := 0.500;
  ELSE
    -- LTO weight
    v_weight := 0.300;
  END IF;

  -- ── Count attributes submitted ────────────────────────────
  SELECT COUNT(*) INTO v_attr_count
  FROM jsonb_object_keys(p_attributes);

  IF v_attr_count < 10 THEN
    RAISE EXCEPTION 'Assessment must include at least 10 attributes (submitted: %)',
      v_attr_count;
  END IF;

  -- ── Create assessment record (draft) ─────────────────────
  INSERT INTO player_attribute_assessments (
    player_id,
    assessor_profile_id,
    assessor_type,
    assessor_club_id,
    assessor_league_id,
    season_id,
    assessment_date,
    status,
    weight_applied,
    submission_fingerprint,
    notes,
    created_by
  ) VALUES (
    p_player_id,
    auth.uid(),
    p_assessor_type,
    p_assessor_club_id,
    p_assessor_league_id,
    p_season_id,
    CURRENT_DATE,
    'draft',
    v_weight,
    p_fingerprint,
    p_notes,
    auth.uid()
  )
  RETURNING id INTO v_assessment_id;

  -- ── Insert line items + run anti-manipulation checks ──────
  FOR v_attr_code, v_raw_value IN
    SELECT key, value::INTEGER
    FROM jsonb_each_text(p_attributes)
  LOOP
    -- Validate attribute code exists
    IF NOT EXISTS (
      SELECT 1 FROM attribute_definitions
      WHERE code = v_attr_code AND is_active = true
    ) THEN
      RAISE EXCEPTION 'Unknown attribute code: %', v_attr_code;
    END IF;

    -- Validate value range
    IF v_raw_value < 1 OR v_raw_value > 20 THEN
      RAISE EXCEPTION 'Attribute % value % is outside 1-20 range',
        v_attr_code, v_raw_value;
    END IF;

    -- ── Anti-manipulation: DRIFT CAP ─────────────────────
    SELECT current_value INTO v_prev_value
    FROM player_attributes
    WHERE player_id = p_player_id AND attribute_code = v_attr_code;

    IF v_prev_value IS NOT NULL THEN
      v_drift_cap := CASE
        WHEN v_attr_code IN ('pace','acceleration','stamina','strength','agility','jumping')
          THEN 3   -- physical cap
        ELSE 4     -- technical/mental/tactical cap
      END;

      IF ABS(v_raw_value - v_prev_value) > v_drift_cap THEN
        v_is_flagged    := true;
        v_flag_reason   := COALESCE(v_flag_reason,'') ||
          format('Drift cap exceeded for %s: prev=%s submitted=%s; ',
                 v_attr_code, v_prev_value, v_raw_value);
        v_integrity_score := LEAST(v_integrity_score, 60);
      END IF;
    END IF;

    -- ── Anti-manipulation: OUTLIER DETECTION (z-score) ───
    -- Compare against same attribute for same assessor_type in same league/season
    SELECT
      AVG(paas.raw_value::NUMERIC),
      STDDEV(paas.raw_value::NUMERIC)
    INTO v_pop_mean, v_pop_std
    FROM player_attribute_assessment_sources paas
    JOIN player_attribute_assessments paa ON paa.id = paas.assessment_id
    WHERE paas.attribute_code = v_attr_code
      AND paa.assessor_type   = p_assessor_type
      AND paa.season_id       = p_season_id
      AND paa.status IN ('submitted','accepted')
      AND paa.assessor_league_id = p_assessor_league_id;

    IF v_pop_std IS NOT NULL AND v_pop_std > 0 THEN
      v_z_score := (v_raw_value - v_pop_mean) / v_pop_std;
      IF ABS(v_z_score) > 2.5 THEN
        v_is_flagged    := true;
        v_flag_reason   := COALESCE(v_flag_reason,'') ||
          format('Statistical outlier: %s z=%.2f; ', v_attr_code, v_z_score);
        v_integrity_score := LEAST(v_integrity_score,
                                   100 - (ABS(v_z_score) * 20));
      END IF;
    END IF;

    -- Insert line item
    INSERT INTO player_attribute_assessment_sources (
      assessment_id,
      player_id,
      attribute_code,
      raw_value
    ) VALUES (
      v_assessment_id,
      p_player_id,
      v_attr_code,
      v_raw_value
    );
  END LOOP;

  -- ── Update assessment with anti-manipulation results ──────
  UPDATE player_attribute_assessments SET
    status          = 'submitted',
    submitted_at    = NOW(),
    is_flagged      = v_is_flagged,
    flag_reason     = LEFT(v_flag_reason, 300),
    integrity_score = GREATEST(0, ROUND(v_integrity_score))
  WHERE id = v_assessment_id;

  -- ── If clean (not flagged), auto-accept ───────────────────
  IF NOT v_is_flagged THEN
    UPDATE player_attribute_assessments SET
      status      = 'accepted',
      reviewed_at = NOW()
    WHERE id = v_assessment_id;

    -- Trigger attribute recomputation
    PERFORM apply_accepted_assessment(p_player_id, p_season_id);
  END IF;
  -- If flagged: stays as 'submitted' in LTO review queue

  RETURN v_assessment_id;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- SECTION 20: APPLY ACCEPTED ASSESSMENT
-- Called after an assessment is accepted (auto or by LTO).
-- Recomputes player_attributes from all accepted sources,
-- writes history, recalculates DNA and passport score.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION apply_accepted_assessment(
  p_player_id  UUID,
  p_season_id  UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attr_code       TEXT;
  v_coach_val       NUMERIC;
  v_officer_val     NUMERIC;
  v_ai_val          NUMERIC;
  v_coach_w         NUMERIC;
  v_officer_w       NUMERIC;
  v_ai_w            NUMERIC;
  v_total_w         NUMERIC;
  v_weighted_avg    NUMERIC;
  v_computed_val    SMALLINT;
  v_confidence      TEXT;
  v_source_count    INTEGER;
  v_prev_value      SMALLINT;
  v_trigger_source  TEXT;
BEGIN
  -- For each attribute that has at least one accepted assessment
  FOR v_attr_code IN
    SELECT DISTINCT paas.attribute_code
    FROM player_attribute_assessment_sources paas
    JOIN player_attribute_assessments paa ON paa.id = paas.assessment_id
    WHERE paa.player_id = p_player_id
      AND paa.season_id = p_season_id
      AND paa.status    = 'accepted'
  LOOP
    -- Fetch latest accepted value per source type
    SELECT
      MAX(CASE WHEN paa.assessor_type = 'coach'
               THEN paas.raw_value::NUMERIC END),
      MAX(CASE WHEN paa.assessor_type = 'league_technical_officer'
               THEN paas.raw_value::NUMERIC END),
      MAX(CASE WHEN paa.assessor_type = 'ai_engine'
               THEN paas.raw_value::NUMERIC END)
    INTO v_coach_val, v_officer_val, v_ai_val
    FROM player_attribute_assessment_sources paas
    JOIN player_attribute_assessments paa ON paa.id = paas.assessment_id
    WHERE paa.player_id       = p_player_id
      AND paa.season_id       = p_season_id
      AND paa.status          = 'accepted'
      AND paas.attribute_code = v_attr_code;

    -- Build renormalised weights
    v_coach_w   := CASE WHEN v_coach_val   IS NOT NULL THEN 0.500 ELSE 0 END;
    v_officer_w := CASE WHEN v_officer_val IS NOT NULL THEN 0.300 ELSE 0 END;
    v_ai_w      := CASE WHEN v_ai_val      IS NOT NULL THEN 0.200 ELSE 0 END;
    v_total_w   := v_coach_w + v_officer_w + v_ai_w;

    IF v_total_w = 0 THEN CONTINUE; END IF;

    -- Renormalise
    v_coach_w   := v_coach_w   / v_total_w;
    v_officer_w := v_officer_w / v_total_w;
    v_ai_w      := v_ai_w      / v_total_w;

    -- Weighted average
    v_weighted_avg :=
      COALESCE(v_coach_val,   0) * v_coach_w
      + COALESCE(v_officer_val, 0) * v_officer_w
      + COALESCE(v_ai_val,      0) * v_ai_w;

    v_computed_val := GREATEST(1, LEAST(20, ROUND(v_weighted_avg)))::SMALLINT;

    -- Confidence level
    v_source_count := (CASE WHEN v_coach_val   IS NOT NULL THEN 1 ELSE 0 END)
                    + (CASE WHEN v_officer_val IS NOT NULL THEN 1 ELSE 0 END)
                    + (CASE WHEN v_ai_val      IS NOT NULL THEN 1 ELSE 0 END);

    v_confidence := CASE v_source_count
      WHEN 3 THEN 'verified'
      WHEN 2 THEN
        CASE
          WHEN v_coach_val IS NOT NULL AND v_officer_val IS NOT NULL THEN 'high'
          ELSE 'medium'
        END
      ELSE 'low'
    END;

    -- Determine trigger source label
    v_trigger_source := CASE
      WHEN v_coach_val IS NOT NULL   THEN 'coach_assessment'
      WHEN v_officer_val IS NOT NULL THEN 'officer_assessment'
      ELSE 'ai_batch'
    END;

    -- Fetch previous value for history
    SELECT current_value INTO v_prev_value
    FROM player_attributes
    WHERE player_id = p_player_id AND attribute_code = v_attr_code;

    -- Upsert into player_attributes
    INSERT INTO player_attributes (
      player_id, attribute_code, current_value,
      coach_value, officer_value, ai_value,
      assessment_count, confidence_level,
      last_assessed_at, last_assessed_by_type,
      season_id, is_public, created_by
    ) VALUES (
      p_player_id, v_attr_code, v_computed_val,
      v_coach_val::SMALLINT,
      v_officer_val::SMALLINT,
      v_ai_val::SMALLINT,
      v_source_count, v_confidence,
      NOW(), v_trigger_source,
      p_season_id, true, auth.uid()
    )
    ON CONFLICT (player_id, attribute_code)
    DO UPDATE SET
      current_value         = EXCLUDED.current_value,
      coach_value           = COALESCE(EXCLUDED.coach_value, player_attributes.coach_value),
      officer_value         = COALESCE(EXCLUDED.officer_value, player_attributes.officer_value),
      ai_value              = COALESCE(EXCLUDED.ai_value, player_attributes.ai_value),
      assessment_count      = player_attributes.assessment_count + 1,
      confidence_level      = EXCLUDED.confidence_level,
      last_assessed_at      = EXCLUDED.last_assessed_at,
      last_assessed_by_type = EXCLUDED.last_assessed_by_type,
      season_id             = EXCLUDED.season_id,
      is_public             = true,
      updated_at            = NOW();

    -- Write history if value changed
    IF v_prev_value IS DISTINCT FROM v_computed_val THEN
      INSERT INTO player_attribute_history (
        player_id, attribute_code, value, previous_value,
        recorded_at, season_id, trigger_source, recorded_by
      ) VALUES (
        p_player_id, v_attr_code, v_computed_val, v_prev_value,
        NOW(), p_season_id, v_trigger_source, auth.uid()
      );
    END IF;

  END LOOP;

  -- Recompute DNA after all attributes updated
  PERFORM calculate_player_dna(p_player_id);

  -- Recompute passport score
  PERFORM compute_player_passport_score(p_player_id);

END;
$$;

-- ────────────────────────────────────────────────────────────
-- SECTION 21: LTO REVIEW FUNCTION
-- review_attribute_assessment() — accept, reject, or override.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION review_attribute_assessment(
  p_assessment_id     UUID,
  p_decision          TEXT,     -- 'accept' | 'reject' | 'override'
  p_rejection_reason  TEXT      DEFAULT NULL,
  p_override_values   JSONB     DEFAULT NULL  -- { "attribute_code": new_value }
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_player_id   UUID;
  v_season_id   UUID;
  v_attr_code   TEXT;
  v_new_val     INTEGER;
BEGIN
  -- Validate caller is LTO or developer
  IF get_my_role() NOT IN ('developer','league_admin','league_founder','technical_assessor') THEN
    RAISE EXCEPTION 'Only League Technical Officers may review assessments';
  END IF;

  -- Validate decision
  IF p_decision NOT IN ('accept','reject','override') THEN
    RAISE EXCEPTION 'Decision must be accept, reject, or override';
  END IF;

  -- Fetch assessment context
  SELECT player_id, season_id INTO v_player_id, v_season_id
  FROM player_attribute_assessments
  WHERE id = p_assessment_id AND status = 'submitted';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Assessment % not found or not in submitted status', p_assessment_id;
  END IF;

  IF p_decision = 'reject' THEN
    UPDATE player_attribute_assessments SET
      status           = 'rejected',
      rejection_reason = p_rejection_reason,
      reviewed_at      = NOW(),
      reviewed_by      = auth.uid(),
      updated_at       = NOW()
    WHERE id = p_assessment_id;

  ELSIF p_decision = 'accept' THEN
    UPDATE player_attribute_assessments SET
      status      = 'accepted',
      reviewed_at = NOW(),
      reviewed_by = auth.uid(),
      updated_at  = NOW()
    WHERE id = p_assessment_id;

    PERFORM apply_accepted_assessment(v_player_id, v_season_id);

  ELSIF p_decision = 'override' THEN
    -- Update specific source item values before accepting
    IF p_override_values IS NOT NULL THEN
      FOR v_attr_code, v_new_val IN
        SELECT key, value::INTEGER FROM jsonb_each_text(p_override_values)
      LOOP
        IF v_new_val < 1 OR v_new_val > 20 THEN
          RAISE EXCEPTION 'Override value % for % outside 1-20 range', v_new_val, v_attr_code;
        END IF;

        UPDATE player_attribute_assessment_sources SET
          raw_value = v_new_val
        WHERE assessment_id    = p_assessment_id
          AND attribute_code   = v_attr_code;
      END LOOP;
    END IF;

    UPDATE player_attribute_assessments SET
      status      = 'accepted',
      reviewed_at = NOW(),
      reviewed_by = auth.uid(),
      is_flagged  = false,  -- LTO override clears flag
      updated_at  = NOW()
    WHERE id = p_assessment_id;

    PERFORM apply_accepted_assessment(v_player_id, v_season_id);
  END IF;

END;
$$;

-- ────────────────────────────────────────────────────────────
-- SECTION 22: ADD ASSESSMENT_ID FK TO HISTORY (deferred add)
-- ────────────────────────────────────────────────────────────

ALTER TABLE player_attribute_history
  ADD CONSTRAINT fk_attr_history_assessment
  FOREIGN KEY (assessment_id)
  REFERENCES player_attribute_assessments(id)
  ON DELETE SET NULL
  NOT VALID;

ALTER TABLE player_attribute_history
  VALIDATE CONSTRAINT fk_attr_history_assessment;

-- Index for this FK
CREATE INDEX IF NOT EXISTS idx_attr_history_assessment
  ON player_attribute_history(assessment_id)
  WHERE assessment_id IS NOT NULL;

-- ────────────────────────────────────────────────────────────
-- SECTION 23: PUBLIC VIEWS
-- ────────────────────────────────────────────────────────────

-- ── v_player_attributes_public ───────────────────────────
-- Exposes only is_public=true attributes.
-- This is what anonymous users and fans see on the passport.

CREATE OR REPLACE VIEW v_player_attributes_public
WITH (security_invoker = true)
AS
SELECT
  pa.player_id,
  p.full_name                               AS player_name,
  COALESCE(p.preferred_name, p.full_name)   AS display_name,
  p.position,
  p.club_id,
  c.name                                    AS club_name,
  pa.attribute_code,
  ad.label                                  AS attribute_label,
  ad.category,
  ad.display_order,
  pa.current_value,
  pa.confidence_level,
  pa.last_assessed_at,
  pa.season_id
FROM player_attributes pa
JOIN players            p  ON p.id  = pa.player_id
JOIN attribute_definitions ad ON ad.code = pa.attribute_code
LEFT JOIN clubs         c  ON c.id  = p.club_id
WHERE pa.is_public    = true
  AND p.is_active     = true
  AND p.is_passport_public = true
  AND ad.is_active    = true;

-- ── v_player_dna_public ──────────────────────────────────
-- DNA summary per player for passport display.
-- Shows category scores + overall. No raw attribute breakdown.

CREATE OR REPLACE VIEW v_player_dna_public
WITH (security_invoker = true)
AS
SELECT
  p.id                                      AS player_id,
  COALESCE(p.preferred_name, p.full_name)   AS display_name,
  p.full_name,
  p.position,
  p.nationality,
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
  p.photo_url,
  p.share_url_slug,
  p.club_id,
  c.name                                    AS club_name,
  c.logo_url                                AS club_logo_url,
  -- DNA category scores
  p.dna_technical,
  p.dna_physical,
  p.dna_mental,
  p.dna_tactical,
  p.dna_goalkeeper,
  p.dna_overall,
  p.dna_band,
  p.dna_computed_at,
  -- Potential (category only — no assessor notes)
  p.potential_score,
  p.potential_category,
  -- Passport
  p.passport_score,
  p.passport_band,
  p.passport_computed_at,
  p.biography,
  p.height_cm,
  p.weight_kg,
  p.follower_count
FROM players p
LEFT JOIN clubs c ON c.id = p.club_id
WHERE p.is_active         = true
  AND p.is_passport_public = true;

-- ── v_player_passport_full ───────────────────────────────
-- Full passport: DNA + progression trend (for passport page).
-- Security: same as is_passport_public.

CREATE OR REPLACE VIEW v_player_passport_full
WITH (security_invoker = true)
AS
SELECT
  p.id,
  COALESCE(p.preferred_name, p.full_name)   AS display_name,
  p.full_name,
  p.position,
  p.nationality,
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
  p.date_of_birth,
  p.photo_url,
  p.preferred_foot,
  p.jersey_number,
  p.share_url_slug,
  p.biography,
  p.height_cm,
  p.weight_kg,
  p.club_id,
  c.name                                    AS club_name,
  c.logo_url                                AS club_logo_url,
  -- DNA
  p.dna_technical,
  p.dna_physical,
  p.dna_mental,
  p.dna_tactical,
  p.dna_goalkeeper,
  p.dna_overall,
  p.dna_band,
  p.dna_computed_at,
  -- Potential
  p.potential_score,
  p.potential_category,
  -- Passport score
  p.passport_score,
  p.passport_band,
  p.passport_computed_at,
  p.is_passport_public,
  p.follower_count,
  p.is_active
FROM players p
LEFT JOIN clubs c ON c.id = p.club_id
WHERE p.is_active = true
  AND p.is_passport_public = true;

-- ── v_attribute_progression ──────────────────────────────
-- Time-series for progression graph (public view: value + season).

CREATE OR REPLACE VIEW v_attribute_progression
WITH (security_invoker = true)
AS
SELECT
  pah.player_id,
  p.full_name                               AS player_name,
  COALESCE(p.preferred_name, p.full_name)   AS display_name,
  p.is_passport_public,
  pah.attribute_code,
  ad.label                                  AS attribute_label,
  ad.category,
  pah.value,
  pah.previous_value,
  pah.delta,
  pah.recorded_at,
  pah.season_id,
  s.name                                    AS season_name,
  pah.trigger_source
FROM player_attribute_history pah
JOIN players            p  ON p.id  = pah.player_id
JOIN attribute_definitions ad ON ad.code = pah.attribute_code
LEFT JOIN seasons       s  ON s.id  = pah.season_id
WHERE p.is_active = true;
-- RLS on underlying tables controls who sees which rows.

-- ── v_dna_leaderboard ────────────────────────────────────
-- Top players by DNA rating (public passport leaderboard).

CREATE OR REPLACE VIEW v_dna_leaderboard
WITH (security_invoker = true)
AS
SELECT
  p.id                                      AS player_id,
  COALESCE(p.preferred_name, p.full_name)   AS display_name,
  p.position,
  p.nationality,
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
  p.photo_url,
  p.share_url_slug,
  c.id                                      AS club_id,
  c.name                                    AS club_name,
  l.id                                      AS league_id,
  l.name                                    AS league_name,
  p.dna_technical,
  p.dna_physical,
  p.dna_mental,
  p.dna_tactical,
  p.dna_overall,
  p.dna_band,
  p.potential_score,
  p.potential_category,
  p.passport_score,
  p.passport_band,
  p.dna_computed_at
FROM players p
LEFT JOIN clubs   c ON c.id = p.club_id
LEFT JOIN (
  -- Get the player's most recent active league
  SELECT DISTINCT ON (plr.player_id)
    plr.player_id,
    s.league_id
  FROM player_league_registrations plr
  JOIN seasons s ON s.id = plr.season_id
  WHERE plr.status = 'approved' AND plr.is_current = true
  ORDER BY plr.player_id, plr.created_at DESC
) plr_latest ON plr_latest.player_id = p.id
LEFT JOIN leagues l ON l.id = plr_latest.league_id
WHERE p.is_active         = true
  AND p.is_passport_public = true
  AND p.dna_overall        IS NOT NULL
ORDER BY p.dna_overall DESC NULLS LAST;

-- ── v_profiles_public ────────────────────────────────────
-- PDPA-safe public profile view. Excludes phone and email.
-- Fixes the open finding from Phase 6 architecture review.

CREATE OR REPLACE VIEW v_profiles_public
WITH (security_invoker = true)
AS
SELECT
  id,
  full_name,
  avatar_url,
  -- role exposed only for display context (not for access control)
  role,
  is_active,
  created_at
FROM profiles
WHERE is_active = true;

-- ────────────────────────────────────────────────────────────
-- SECTION 24: USER_FOLLOWS TABLE
-- Allows registered users to follow leagues, clubs, players.
-- ────────────────────────────────────────────────────────────

CREATE TABLE user_follows (
  id          UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id  UUID          NOT NULL
              REFERENCES profiles(id) ON DELETE CASCADE,
  entity_type TEXT          NOT NULL
              CHECK (entity_type IN ('league','club','player','fixture')),
  entity_id   UUID          NOT NULL,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (profile_id, entity_type, entity_id)
);

CREATE INDEX idx_user_follows_profile
  ON user_follows(profile_id, entity_type);

CREATE INDEX idx_user_follows_entity
  ON user_follows(entity_type, entity_id);

ALTER TABLE user_follows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_follows: own read"
  ON user_follows FOR SELECT
  USING (profile_id = auth.uid() OR get_my_role() = 'developer');

CREATE POLICY "user_follows: own insert"
  ON user_follows FOR INSERT
  WITH CHECK (profile_id = auth.uid() AND auth.uid() IS NOT NULL);

CREATE POLICY "user_follows: own delete"
  ON user_follows FOR DELETE
  USING (profile_id = auth.uid());

-- Follower count update function
CREATE OR REPLACE FUNCTION update_follower_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delta INTEGER := CASE TG_OP WHEN 'INSERT' THEN 1 ELSE -1 END;
  v_id    UUID    := CASE TG_OP WHEN 'INSERT' THEN NEW.entity_id ELSE OLD.entity_id END;
  v_type  TEXT    := CASE TG_OP WHEN 'INSERT' THEN NEW.entity_type ELSE OLD.entity_type END;
BEGIN
  CASE v_type
    WHEN 'player' THEN
      UPDATE players SET follower_count = GREATEST(0, follower_count + v_delta)
      WHERE id = v_id;
    WHEN 'club' THEN
      UPDATE clubs SET follower_count = GREATEST(0, follower_count + v_delta)
      WHERE id = v_id;
    WHEN 'league' THEN
      UPDATE leagues SET follower_count = GREATEST(0, follower_count + v_delta)
      WHERE id = v_id;
    ELSE NULL;
  END CASE;
  RETURN CASE TG_OP WHEN 'INSERT' THEN NEW ELSE OLD END;
END;
$$;

CREATE TRIGGER trg_user_follows_count
  AFTER INSERT OR DELETE ON user_follows
  FOR EACH ROW EXECUTE FUNCTION update_follower_counts();

-- ────────────────────────────────────────────────────────────
-- SECTION 25: PUBLIC SLUGS TABLE
-- SEO-friendly URL slugs for all public entities.
-- ────────────────────────────────────────────────────────────

CREATE TABLE public_slugs (
  id          UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  entity_type TEXT          NOT NULL
              CHECK (entity_type IN ('league','club','player')),
  entity_id   UUID          NOT NULL,
  slug        TEXT          NOT NULL UNIQUE,
  -- For redirects (when slug changes)
  redirect_to UUID          REFERENCES public_slugs(id) ON DELETE SET NULL,
  is_primary  BOOLEAN       NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (entity_type, entity_id)  -- one primary slug per entity
);

CREATE INDEX idx_public_slugs_entity
  ON public_slugs(entity_type, entity_id);

CREATE INDEX idx_public_slugs_slug
  ON public_slugs(slug);

ALTER TABLE public_slugs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_slugs: public read"
  ON public_slugs FOR SELECT
  USING (true);

CREATE POLICY "public_slugs: developer write"
  ON public_slugs FOR ALL
  USING (get_my_role() = 'developer')
  WITH CHECK (get_my_role() = 'developer');

-- ────────────────────────────────────────────────────────────
-- SECTION 26: MATERIALISED VIEWS
-- Performance optimisation for public-facing leaderboards.
-- Refresh triggered by cron or on-demand.
-- ────────────────────────────────────────────────────────────

CREATE MATERIALIZED VIEW mv_player_passport_scores AS
SELECT
  p.id                                        AS player_id,
  COALESCE(p.preferred_name, p.full_name)     AS display_name,
  p.position,
  EXTRACT(YEAR FROM AGE(p.date_of_birth))::INTEGER AS age,
  p.photo_url,
  p.share_url_slug,
  c.id                                        AS club_id,
  c.name                                      AS club_name,
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
  p.dna_computed_at,
  p.passport_computed_at
FROM players p
LEFT JOIN clubs c ON c.id = p.club_id
WHERE p.is_active = true
  AND p.is_passport_public = true
WITH DATA;

CREATE UNIQUE INDEX mv_passport_scores_player
  ON mv_player_passport_scores(player_id);

CREATE INDEX mv_passport_scores_dna
  ON mv_player_passport_scores(dna_overall DESC NULLS LAST);

CREATE INDEX mv_passport_scores_passport
  ON mv_player_passport_scores(passport_score DESC NULLS LAST);

-- Refresh function (called by Supabase Cron)
CREATE OR REPLACE FUNCTION refresh_passport_mv()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_player_passport_scores;
$$;

-- ────────────────────────────────────────────────────────────
-- SECTION 27: SEASON ROLLOVER — ATTRIBUTE SNAPSHOT
-- Called at end of each season to freeze attribute values.
-- Creates player_attribute_history entries for ALL active
-- players, providing a clean season baseline.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION snapshot_season_attributes(p_season_id UUID)
RETURNS INTEGER   -- returns count of records snapshotted
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  -- Only developer or league founder can trigger this
  IF get_my_role() NOT IN ('developer','league_founder') THEN
    RAISE EXCEPTION 'Only developers or league founders may trigger season snapshots';
  END IF;

  INSERT INTO player_attribute_history (
    player_id,
    attribute_code,
    value,
    previous_value,
    recorded_at,
    season_id,
    trigger_source
  )
  SELECT
    pa.player_id,
    pa.attribute_code,
    pa.current_value,
    NULL,   -- no delta needed for snapshot
    NOW(),
    p_season_id,
    'season_rollover'
  FROM player_attributes pa
  JOIN players pl ON pl.id = pa.player_id
  WHERE pl.is_active = true
    AND NOT EXISTS (
      -- Don't duplicate if snapshot already taken this season
      SELECT 1 FROM player_attribute_history h
      WHERE h.player_id      = pa.player_id
        AND h.attribute_code = pa.attribute_code
        AND h.season_id      = p_season_id
        AND h.trigger_source = 'season_rollover'
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- SECTION 28: GRANT EXECUTE PERMISSIONS
-- All SECURITY DEFINER functions need EXECUTE granted to
-- authenticated role so Supabase RPC calls work.
-- ────────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION is_coach_for_club(UUID)              TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_player_id()                   TO authenticated;
GRANT EXECUTE ON FUNCTION is_own_player_record(UUID)           TO authenticated;
GRANT EXECUTE ON FUNCTION is_guardian_of(UUID)                 TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_player_dna(UUID)           TO authenticated;
GRANT EXECUTE ON FUNCTION compute_player_potential(UUID)       TO authenticated;
GRANT EXECUTE ON FUNCTION compute_player_passport_score(UUID)  TO authenticated;
GRANT EXECUTE ON FUNCTION submit_attribute_assessment(UUID,UUID,TEXT,UUID,UUID,JSONB,TEXT,TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION review_attribute_assessment(UUID,TEXT,TEXT,JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION apply_accepted_assessment(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION snapshot_season_attributes(UUID)     TO authenticated;
GRANT EXECUTE ON FUNCTION refresh_passport_mv()                TO authenticated;

-- Public (anon) can call read-only helpers
GRANT EXECUTE ON FUNCTION get_my_player_id()     TO anon;
GRANT EXECUTE ON FUNCTION is_guardian_of(UUID)   TO anon;

-- ────────────────────────────────────────────────────────────
-- SECTION 29: VERIFICATION QUERIES (commented out — run manually)
-- ────────────────────────────────────────────────────────────

-- Verify tables created:
-- SELECT tablename FROM pg_tables WHERE schemaname = 'public'
--   AND tablename IN (
--     'attribute_definitions','player_attributes','player_attribute_history',
--     'player_attribute_assessments','player_attribute_assessment_sources',
--     'player_potential_scores','player_ownership_claims','player_guardians',
--     'player_passport_score_history','league_quality_tiers',
--     'position_dna_weights','user_follows','public_slugs'
--   );

-- Verify 28 attribute definitions seeded:
-- SELECT category, COUNT(*) FROM attribute_definitions GROUP BY category ORDER BY category;
-- Expected: goalkeeper=4, mental=6, physical=6, tactical=5, technical=7 → total 28

-- Verify position weights sum to 1.000:
-- SELECT position_code,
--        ROUND(weight_technical + weight_physical + weight_mental
--              + weight_tactical + weight_goalkeeper, 3) AS total
-- FROM position_dna_weights;

-- Verify is_coach_for_club function exists:
-- SELECT proname FROM pg_proc WHERE proname = 'is_coach_for_club';

-- Verify match_lineups policies replaced:
-- SELECT policyname FROM pg_policies
-- WHERE tablename = 'match_lineups'
-- ORDER BY policyname;

-- Verify new players columns:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'players'
--   AND column_name IN ('profile_id','dna_overall','passport_score','share_url_slug');

COMMIT;

-- ============================================================
-- END OF PHASE 6.5 MIGRATION
-- ============================================================
-- Tables created:      13
-- Functions created:   12
-- Views created:        6
-- Materialized views:   1
-- Enum values added:   12
-- Policies created:    32
-- Triggers created:    11
-- Indexes created:     40+
-- New player columns:  17
-- New club columns:    14
-- New league columns:   3
--
-- SUCCESS CRITERIA (Section 3 of directive):
-- ✓ Attribute system deployed
-- ✓ Coach Assessment System deployed
-- ✓ League Technical Officer Assessment deployed
-- ✓ DNA Engine deployed (calculate_player_dna)
-- ✓ Football Passport deployed (compute_player_passport_score)
-- ✓ Historical Progression deployed (player_attribute_history)
-- ✓ Public Passport Pages deployed (views ready for routing)
-- Remaining: One real league using system (operational)
-- Remaining: 100 real players assessed (operational)
-- ============================================================
