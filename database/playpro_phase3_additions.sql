-- ============================================================
-- PLAYPRO — PHASE 3 SCHEMA ADDITIONS
-- Apply AFTER Phase 1 and Phase 2 are fully applied.
-- Run top to bottom exactly as written.
-- Zero modifications to any existing table, enum, trigger,
-- function, index, policy or view from Phase 1 or Phase 2.
-- ============================================================


-- ============================================================
-- SECTION A: NEW ENUMS
-- ============================================================

-- -------------------------------------------------------
-- A1. club_staff_role
-- All non-coach, non-player staff roles for a club.
-- coaches table (Phase 1) covers head coaches only.
-- club_staff covers every other backroom role.
-- -------------------------------------------------------
CREATE TYPE club_staff_role AS ENUM (
  'manager',              -- Team manager / head coach (distinct from coaches table)
  'assistant_coach',      -- First-team assistant
  'goalkeeper_coach',     -- Specialist GK coach
  'physiotherapist',      -- Medical / injury rehab
  'analyst',              -- Video / data analyst
  'kit_manager'           -- Equipment and kit
);

-- -------------------------------------------------------
-- A2. injury_type
-- Anatomical classification of a player injury.
-- -------------------------------------------------------
CREATE TYPE injury_type AS ENUM (
  'muscular',             -- Muscle tear / strain / pull
  'ligament',             -- ACL, MCL, ankle ligament
  'fracture',             -- Bone break
  'concussion',           -- Head trauma
  'tendon',               -- Achilles, patellar tendon
  'cartilage',            -- Meniscus, articular cartilage
  'bruising',             -- Contusion / haematoma
  'laceration',           -- Cut / open wound
  'dislocation',          -- Joint dislocation
  'illness',              -- Non-contact (flu, virus, etc.)
  'other'                 -- Catch-all
);

-- -------------------------------------------------------
-- A3. injury_severity
-- Clinical severity band for squad availability planning.
-- -------------------------------------------------------
CREATE TYPE injury_severity AS ENUM (
  'minor',                -- 1–7 days expected absence
  'moderate',             -- 8–28 days
  'serious',              -- 29–90 days
  'severe',               -- 90+ days / surgery required
  'career_threatening'    -- Indefinite / retirement risk
);

-- -------------------------------------------------------
-- A4. media_asset_type
-- All content categories for the media module.
-- -------------------------------------------------------
CREATE TYPE media_asset_type AS ENUM (
  'livestream',
  'match_highlight',
  'press_conference',
  'interview',
  'photo_gallery'
);

-- -------------------------------------------------------
-- A5. media_visibility
-- Access level for a media asset.
-- -------------------------------------------------------
CREATE TYPE media_visibility AS ENUM (
  'public',               -- Anyone, including unauthenticated
  'members_only',         -- Authenticated users only
  'club_only',            -- Club admin + staff of that club
  'league_only',          -- League admin of that league
  'private'               -- Developer / uploader only
);

-- -------------------------------------------------------
-- A6. media_status
-- Publishing lifecycle for a media asset.
-- -------------------------------------------------------
CREATE TYPE media_status AS ENUM (
  'draft',                -- Being prepared, not published
  'processing',           -- Video encoding / upload in progress
  'published',            -- Live and visible
  'archived',             -- Hidden from feeds, retained for records
  'deleted'               -- Soft-deleted
);

-- -------------------------------------------------------
-- A7. notification_channel
-- How a notification is delivered.
-- -------------------------------------------------------
CREATE TYPE notification_channel AS ENUM (
  'in_app',               -- In-app notification bell
  'email',
  'push',                 -- Mobile push (FCM / APNs)
  'sms'
);

-- -------------------------------------------------------
-- A8. notification_type
-- Semantic category — drives icon, colour and routing.
-- -------------------------------------------------------
CREATE TYPE notification_type AS ENUM (
  -- League-wide events
  'league_announcement',
  'league_status_change',
  -- Fixture events
  'fixture_scheduled',
  'fixture_rescheduled',
  'fixture_postponed',
  'fixture_cancelled',
  'fixture_result_entered',
  'fixture_result_official',
  -- Disciplinary
  'card_issued',
  'suspension_imposed',
  'suspension_match_served',
  'suspension_completed',
  -- Payments
  'payment_due',
  'payment_overdue',
  'payment_received',
  'payment_approved',
  'payment_rejected',
  -- Transfers
  'transfer_requested',
  'transfer_approved',
  'transfer_rejected',
  -- Injuries
  'injury_reported',
  'injury_updated',
  'player_cleared',
  -- Media
  'media_published',
  -- Generic
  'general'
);


-- ============================================================
-- SECTION B: MODULE 1 — CLUB STAFF
-- ============================================================
-- Design rationale:
--   Phase 1 coaches table covers registered head coaches with
--   UEFA/FAM licences. club_staff covers every OTHER backroom
--   role (managers, physios, analysts, kit staff, etc.).
--   A person can hold multiple staff roles at the same club
--   (e.g. assistant coach + analyst) — one row per role.
--   Optional profile_id links to a system user account; staff
--   without system accounts are still recordable.
-- ============================================================

CREATE TABLE club_staff (
  id              UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),

  club_id         UUID            NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  -- Optional: link to a system profile (for app access)
  profile_id      UUID            REFERENCES profiles(id) ON DELETE SET NULL,

  full_name       TEXT            NOT NULL,
  role            club_staff_role NOT NULL,

  -- Professional credentials / qualifications
  qualifications  TEXT,

  -- Contact
  email           TEXT,
  phone           TEXT,
  photo_url       TEXT,

  -- Employment period at this club
  joined_date     DATE,
  left_date       DATE,           -- NULL = currently active

  is_active       BOOLEAN         NOT NULL DEFAULT true,

  -- Who registered this staff member
  registered_by   UUID            REFERENCES profiles(id) ON DELETE SET NULL,

  notes           TEXT,

  created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

  -- A profile can only hold one active instance of each role per club
  -- (allows same person to leave and rejoin without violating uniqueness)
  CONSTRAINT chk_staff_dates
    CHECK (left_date IS NULL OR left_date >= joined_date)
);

-- updated_at trigger
CREATE TRIGGER trg_club_staff_updated_at
  BEFORE UPDATE ON club_staff
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Indexes
CREATE INDEX idx_cstaff_club            ON club_staff(club_id);
CREATE INDEX idx_cstaff_role            ON club_staff(role);
CREATE INDEX idx_cstaff_profile         ON club_staff(profile_id);
CREATE INDEX idx_cstaff_active          ON club_staff(club_id, is_active);

-- RLS
ALTER TABLE club_staff ENABLE ROW LEVEL SECURITY;

CREATE POLICY "club_staff: public read"
  ON club_staff FOR SELECT
  USING (true);

-- Club admin manages their own staff; developers manage any
CREATE POLICY "club_staff: club admin insert"
  ON club_staff FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
  );

CREATE POLICY "club_staff: club admin update"
  ON club_staff FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
  );

CREATE POLICY "club_staff: club admin delete"
  ON club_staff FOR DELETE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
  );

-- View: full club backroom card
CREATE VIEW v_club_staff AS
SELECT
  cs.id,
  cs.club_id,
  cl.name           AS club_name,
  cl.logo_url       AS club_logo,
  cs.full_name,
  cs.role,
  cs.qualifications,
  cs.email,
  cs.phone,
  cs.photo_url,
  cs.joined_date,
  cs.left_date,
  cs.is_active,
  cs.notes,
  pr.email          AS system_email,
  pr.role           AS system_role
FROM club_staff cs
JOIN  clubs    cl ON cl.id = cs.club_id
LEFT JOIN profiles pr ON pr.id = cs.profile_id
ORDER BY cs.club_id, cs.role, cs.full_name;


-- ============================================================
-- SECTION C: MODULE 2 — PLAYER INJURIES
-- ============================================================
-- Design rationale:
--   One row per injury incident. A player can have multiple
--   concurrent or sequential injuries. is_active = true means
--   the player is currently unavailable due to this injury.
--   When a player is cleared, cleared_at is set and
--   is_active flips to false automatically via trigger.
--   fixture_id (nullable) links to the match where the
--   injury occurred, if known.
-- ============================================================

CREATE TABLE player_injuries (
  id                    UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),

  player_id             UUID              NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  club_id               UUID              NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  -- Optional: the match during which the injury occurred
  fixture_id            UUID              REFERENCES fixtures(id) ON DELETE SET NULL,

  injury_type           injury_type       NOT NULL,
  severity              injury_severity   NOT NULL,

  -- Body part (free text for precision: "left hamstring", "right ankle", etc.)
  body_part             TEXT              NOT NULL,

  -- Dates
  injury_date           DATE              NOT NULL,
  expected_return_date  DATE,             -- Estimated clearance date
  actual_return_date    DATE,             -- Set when player is cleared

  -- Medical workflow
  diagnosis             TEXT,             -- Clinical diagnosis
  treatment_notes       TEXT,             -- Treatment plan / progress
  medical_notes         TEXT,             -- Confidential physio notes

  -- Whether the player is CURRENTLY unavailable due to this injury
  is_active             BOOLEAN           NOT NULL DEFAULT true,

  -- Clearance — set by physio or club admin when player is fit
  cleared_by            UUID              REFERENCES profiles(id) ON DELETE SET NULL,
  cleared_at            TIMESTAMPTZ,
  clearance_notes       TEXT,

  -- Who reported / entered the injury
  reported_by           UUID              REFERENCES profiles(id) ON DELETE SET NULL,

  created_at            TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ       NOT NULL DEFAULT NOW(),

  -- Sanity checks
  CONSTRAINT chk_injury_return_after_injury
    CHECK (expected_return_date IS NULL OR expected_return_date >= injury_date),
  CONSTRAINT chk_actual_return_after_injury
    CHECK (actual_return_date IS NULL OR actual_return_date >= injury_date)
);

-- ---------------------------------------------------------------
-- Trigger: auto-deactivate injury when cleared_at is set
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION auto_clear_injury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- When cleared_at is first populated, mark the injury inactive
  -- and stamp the actual_return_date if not already set
  IF (OLD.cleared_at IS NULL AND NEW.cleared_at IS NOT NULL) THEN
    NEW.is_active          := false;
    NEW.actual_return_date := COALESCE(NEW.actual_return_date, CURRENT_DATE);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auto_clear_injury
  BEFORE UPDATE ON player_injuries
  FOR EACH ROW EXECUTE FUNCTION auto_clear_injury();

-- updated_at trigger
CREATE TRIGGER trg_player_injuries_updated_at
  BEFORE UPDATE ON player_injuries
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Indexes
CREATE INDEX idx_inj_player            ON player_injuries(player_id);
CREATE INDEX idx_inj_club              ON player_injuries(club_id);
CREATE INDEX idx_inj_fixture           ON player_injuries(fixture_id);
CREATE INDEX idx_inj_active            ON player_injuries(is_active);
CREATE INDEX idx_inj_severity          ON player_injuries(severity);
-- Fast lookup: all active injuries per club (physio dashboard)
CREATE INDEX idx_inj_club_active       ON player_injuries(club_id, is_active)
  WHERE is_active = true;
-- Fast lookup: active injuries per player (availability check)
CREATE INDEX idx_inj_player_active     ON player_injuries(player_id, is_active)
  WHERE is_active = true;

-- RLS
ALTER TABLE player_injuries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_injuries: public read"
  ON player_injuries FOR SELECT
  USING (true);

-- Club admin and physio (via profile_id on club_staff) can create injuries
CREATE POLICY "player_injuries: club admin insert"
  ON player_injuries FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    -- Club staff with a system account can also report injuries for their club
    OR EXISTS (
      SELECT 1 FROM club_staff cs
      WHERE cs.club_id    = club_id
        AND cs.profile_id = auth.uid()
        AND cs.is_active  = true
        AND cs.role       = 'physiotherapist'
    )
  );

-- Same principals can update (clearance, treatment notes, etc.)
CREATE POLICY "player_injuries: club admin update"
  ON player_injuries FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR EXISTS (
      SELECT 1 FROM club_staff cs
      WHERE cs.club_id    = club_id
        AND cs.profile_id = auth.uid()
        AND cs.is_active  = true
        AND cs.role       = 'physiotherapist'
    )
  );

-- View: current injury list per club (physio dashboard)
CREATE VIEW v_active_injuries AS
SELECT
  pi.id,
  pi.player_id,
  pl.full_name          AS player_name,
  pl.position           AS player_position,
  pl.photo_url,
  pi.club_id,
  cl.name               AS club_name,
  pi.fixture_id,
  pi.injury_type,
  pi.severity,
  pi.body_part,
  pi.injury_date,
  pi.expected_return_date,
  (pi.expected_return_date - CURRENT_DATE) AS days_remaining,
  pi.diagnosis,
  pi.treatment_notes,
  pi.is_active
FROM player_injuries pi
JOIN  players pl ON pl.id = pi.player_id
JOIN  clubs   cl ON cl.id = pi.club_id
WHERE pi.is_active = true
ORDER BY pi.severity DESC, pi.expected_return_date ASC;

-- View: full injury history per player
CREATE VIEW v_player_injury_history AS
SELECT
  pi.id,
  pi.player_id,
  pl.full_name          AS player_name,
  cl.name               AS club_name,
  pi.injury_type,
  pi.severity,
  pi.body_part,
  pi.injury_date,
  pi.expected_return_date,
  pi.actual_return_date,
  (pi.actual_return_date - pi.injury_date) AS days_out,
  pi.diagnosis,
  pi.is_active,
  pi.cleared_at
FROM player_injuries pi
JOIN  players pl ON pl.id = pi.player_id
JOIN  clubs   cl ON cl.id = pi.club_id
ORDER BY pi.player_id, pi.injury_date DESC;


-- ============================================================
-- SECTION D: MODULE 3 — SUSPENSION SERVING
-- ============================================================
-- Design rationale:
--   Phase 1 suspensions table has matches_suspended and
--   matches_served columns and an is_active flag, but no
--   automatic mechanism to increment matches_served or flip
--   is_active when the ban is complete.
--
--   This module adds:
--   1. suspension_served_matches — audit log of every match
--      counted against each active suspension. One row per
--      fixture per suspension. Prevents double-counting.
--   2. Trigger on INSERT into suspension_served_matches:
--      a. Increments suspensions.matches_served by 1.
--      b. Flips suspensions.is_active = false when
--         matches_served >= matches_suspended.
--      c. Fires a notification row into notifications.
--   3. Helper view v_suspension_progress for dashboards.
--
--   NO columns are added to the existing suspensions table.
--   All state is derived from this audit table + the trigger.
-- ============================================================

CREATE TABLE suspension_served_matches (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  suspension_id   UUID        NOT NULL REFERENCES suspensions(id) ON DELETE CASCADE,
  fixture_id      UUID        NOT NULL REFERENCES fixtures(id) ON DELETE RESTRICT,

  -- Snapshot fields stored at time of recording for audit integrity
  player_id       UUID        NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  league_id       UUID        NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  -- Running total AFTER this match is counted (calculated by trigger)
  served_total_after  INTEGER NOT NULL DEFAULT 0,

  -- Who marked this match as served
  recorded_by     UUID        REFERENCES profiles(id) ON DELETE SET NULL,
  recorded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One fixture can only be counted once per suspension
  UNIQUE (suspension_id, fixture_id)
);

-- ---------------------------------------------------------------
-- Trigger: increment matches_served and auto-complete suspension
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION process_suspension_served_match()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_suspended   INTEGER;
  v_served_new  INTEGER;
BEGIN
  -- Increment matches_served on the parent suspension
  UPDATE suspensions
  SET
    matches_served = matches_served + 1,
    updated_at     = NOW()
  WHERE id = NEW.suspension_id
  RETURNING matches_suspended, matches_served
  INTO v_suspended, v_served_new;

  -- Store the running total in the audit row
  NEW.served_total_after := v_served_new;

  -- Auto-deactivate suspension when ban is fully served
  IF v_served_new >= v_suspended THEN
    UPDATE suspensions
    SET
      is_active  = false,
      updated_at = NOW()
    WHERE id = NEW.suspension_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_process_suspension_served
  BEFORE INSERT ON suspension_served_matches
  FOR EACH ROW EXECUTE FUNCTION process_suspension_served_match();

-- Indexes
CREATE INDEX idx_ssm_suspension        ON suspension_served_matches(suspension_id);
CREATE INDEX idx_ssm_fixture           ON suspension_served_matches(fixture_id);
CREATE INDEX idx_ssm_player            ON suspension_served_matches(player_id);
CREATE INDEX idx_ssm_league            ON suspension_served_matches(league_id);

-- RLS
ALTER TABLE suspension_served_matches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ssm: public read"
  ON suspension_served_matches FOR SELECT
  USING (true);

-- Only league admin records a served match (prevents clubs self-clearing bans)
CREATE POLICY "ssm: league admin insert"
  ON suspension_served_matches FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR is_league_admin(league_id)
  );

-- Audit rows are immutable — no UPDATE or DELETE permitted via app layer
-- (corrections must be made by developer with direct access)

-- View: suspension progress dashboard
CREATE VIEW v_suspension_progress AS
SELECT
  s.id                                          AS suspension_id,
  s.player_id,
  pl.full_name                                  AS player_name,
  pl.position                                   AS player_position,
  cl.name                                       AS club_name,
  s.league_id,
  l.name                                        AS league_name,
  s.suspension_reason,
  s.matches_suspended,
  s.matches_served,
  (s.matches_suspended - s.matches_served)      AS matches_remaining,
  s.is_active,
  s.reason_notes,
  s.created_at                                  AS imposed_at,
  -- Last fixture counted
  (
    SELECT f.match_date
    FROM suspension_served_matches ssm
    JOIN fixtures f ON f.id = ssm.fixture_id
    WHERE ssm.suspension_id = s.id
    ORDER BY f.match_date DESC
    LIMIT 1
  )                                             AS last_served_match_date,
  -- Fixtures served audit list
  (
    SELECT COUNT(*)
    FROM suspension_served_matches ssm
    WHERE ssm.suspension_id = s.id
  )                                             AS audit_served_count
FROM suspensions s
JOIN  players pl ON pl.id = s.player_id
LEFT JOIN clubs   cl ON cl.id = pl.club_id
JOIN  leagues l  ON l.id  = s.league_id
ORDER BY s.is_active DESC, s.created_at DESC;


-- ============================================================
-- SECTION E: MODULE 4 — MEDIA ASSETS
-- ============================================================
-- Design rationale:
--   Single table (media_assets) stores metadata for all five
--   content types. The media_asset_type enum determines which
--   optional fields are relevant. Physical files live in
--   Supabase Storage; only URLs and metadata are stored here.
--
--   media_asset_tags is a lightweight many-to-many tag system
--   for categorisation and search without a fixed taxonomy.
--
--   Relationships:
--     - league_id (optional) — league-level content
--     - club_id   (optional) — club-specific content
--     - fixture_id (optional) — match-specific content
--       (highlights, press conferences, etc.)
--     - player_id (optional) — player-specific content
--       (interviews, feature pieces)
-- ============================================================

CREATE TABLE media_assets (
  id                  UUID                PRIMARY KEY DEFAULT uuid_generate_v4(),

  asset_type          media_asset_type    NOT NULL,
  title               TEXT                NOT NULL,
  description         TEXT,
  thumbnail_url       TEXT,

  -- Primary media URL (stream URL, video URL, gallery cover)
  media_url           TEXT,

  -- For livestreams: the stream key / embed code
  stream_key          TEXT,
  stream_provider     TEXT,               -- e.g. 'youtube', 'mux', 'twitch'

  -- For photo galleries: JSON array of image URLs
  -- e.g. '["https://...", "https://..."]'
  gallery_urls        JSONB,

  -- Duration in seconds (for video/audio content)
  duration_seconds    INTEGER             CHECK (duration_seconds >= 0),

  -- Content relationships (all optional — use what applies)
  league_id           UUID                REFERENCES leagues(id) ON DELETE SET NULL,
  club_id             UUID                REFERENCES clubs(id) ON DELETE SET NULL,
  fixture_id          UUID                REFERENCES fixtures(id) ON DELETE SET NULL,
  player_id           UUID                REFERENCES players(id) ON DELETE SET NULL,

  -- Publishing
  visibility          media_visibility    NOT NULL DEFAULT 'public',
  status              media_status        NOT NULL DEFAULT 'draft',
  published_at        TIMESTAMPTZ,

  -- For scheduled publishing
  scheduled_at        TIMESTAMPTZ,

  -- Engagement counters (incremented by app logic, not triggers)
  view_count          INTEGER             NOT NULL DEFAULT 0 CHECK (view_count >= 0),
  like_count          INTEGER             NOT NULL DEFAULT 0 CHECK (like_count >= 0),

  -- Ownership
  created_by          UUID                REFERENCES profiles(id) ON DELETE SET NULL,
  updated_by          UUID                REFERENCES profiles(id) ON DELETE SET NULL,

  created_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ         NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------
-- Trigger: auto-stamp published_at when status → 'published'
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION stamp_media_published_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF (OLD.status <> 'published' AND NEW.status = 'published'
      AND NEW.published_at IS NULL) THEN
    NEW.published_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_stamp_media_published_at
  BEFORE UPDATE ON media_assets
  FOR EACH ROW EXECUTE FUNCTION stamp_media_published_at();

-- updated_at trigger
CREATE TRIGGER trg_media_assets_updated_at
  BEFORE UPDATE ON media_assets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Tags: lightweight free-text tag attached to a media asset
CREATE TABLE media_asset_tags (
  id          UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
  asset_id    UUID  NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
  tag         TEXT  NOT NULL,
  UNIQUE (asset_id, tag)
);

-- Indexes — media_assets
CREATE INDEX idx_media_type            ON media_assets(asset_type);
CREATE INDEX idx_media_status          ON media_assets(status);
CREATE INDEX idx_media_visibility      ON media_assets(visibility);
CREATE INDEX idx_media_league          ON media_assets(league_id);
CREATE INDEX idx_media_club            ON media_assets(club_id);
CREATE INDEX idx_media_fixture         ON media_assets(fixture_id);
CREATE INDEX idx_media_player          ON media_assets(player_id);
CREATE INDEX idx_media_published       ON media_assets(published_at DESC)
  WHERE status = 'published';
-- Feed query: published public content ordered by recency
CREATE INDEX idx_media_public_feed     ON media_assets(status, visibility, published_at DESC)
  WHERE status = 'published' AND visibility = 'public';

-- Indexes — media_asset_tags
CREATE INDEX idx_media_tags_asset      ON media_asset_tags(asset_id);
CREATE INDEX idx_media_tags_tag        ON media_asset_tags(tag);

-- RLS — media_assets
ALTER TABLE media_assets     ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_asset_tags ENABLE ROW LEVEL SECURITY;

-- Public reads published public assets
CREATE POLICY "media_assets: public read published"
  ON media_assets FOR SELECT
  USING (
    -- Public assets available to all
    (status = 'published' AND visibility = 'public')
    -- Authenticated users see members_only published assets
    OR (status = 'published' AND visibility = 'members_only' AND auth.uid() IS NOT NULL)
    -- Club members see their own club's club_only assets
    OR (status = 'published' AND visibility = 'club_only'
        AND auth.uid() IS NOT NULL
        AND club_id IS NOT NULL AND is_club_admin(club_id))
    -- League admins see league_only assets for their leagues
    OR (status = 'published' AND visibility = 'league_only'
        AND auth.uid() IS NOT NULL
        AND league_id IS NOT NULL AND is_league_admin(league_id))
    -- Creators always see their own assets in any status
    OR (auth.uid() IS NOT NULL AND created_by = auth.uid())
    -- Developers and league admins see everything
    OR get_my_role() = 'developer'
    OR (league_id IS NOT NULL AND is_league_admin(league_id))
  );

-- League admin and club admin create media for their scope
CREATE POLICY "media_assets: admin insert"
  ON media_assets FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (league_id IS NOT NULL AND is_league_admin(league_id))
    OR (club_id IS NOT NULL AND is_club_admin(club_id))
    OR get_my_role() IN ('league_admin', 'league_founder', 'club_admin')
  );

-- Same principals can update / publish
CREATE POLICY "media_assets: admin update"
  ON media_assets FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR created_by = auth.uid()
    OR (league_id IS NOT NULL AND is_league_admin(league_id))
    OR (club_id IS NOT NULL AND is_club_admin(club_id))
  );

-- RLS — media_asset_tags (inherit from parent asset)
CREATE POLICY "media_asset_tags: public read"
  ON media_asset_tags FOR SELECT
  USING (true);

CREATE POLICY "media_asset_tags: admin insert"
  ON media_asset_tags FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR EXISTS (
      SELECT 1 FROM media_assets ma
      WHERE ma.id = asset_id
        AND (
          ma.created_by = auth.uid()
          OR (ma.league_id IS NOT NULL AND is_league_admin(ma.league_id))
          OR (ma.club_id IS NOT NULL AND is_club_admin(ma.club_id))
        )
    )
  );

CREATE POLICY "media_asset_tags: admin delete"
  ON media_asset_tags FOR DELETE
  USING (
    get_my_role() = 'developer'
    OR EXISTS (
      SELECT 1 FROM media_assets ma
      WHERE ma.id = asset_id
        AND (
          ma.created_by = auth.uid()
          OR (ma.league_id IS NOT NULL AND is_league_admin(ma.league_id))
          OR (ma.club_id IS NOT NULL AND is_club_admin(ma.club_id))
        )
    )
  );

-- View: published media feed (used by public portal)
CREATE VIEW v_media_feed AS
SELECT
  ma.id,
  ma.asset_type,
  ma.title,
  ma.description,
  ma.thumbnail_url,
  ma.media_url,
  ma.stream_provider,
  ma.duration_seconds,
  ma.league_id,
  l.name            AS league_name,
  ma.club_id,
  cl.name           AS club_name,
  ma.fixture_id,
  ma.player_id,
  pl.full_name      AS player_name,
  ma.visibility,
  ma.published_at,
  ma.view_count,
  ma.like_count,
  -- Aggregated tag list
  (
    SELECT ARRAY_AGG(mt.tag ORDER BY mt.tag)
    FROM media_asset_tags mt
    WHERE mt.asset_id = ma.id
  )                 AS tags
FROM media_assets ma
LEFT JOIN leagues l  ON l.id  = ma.league_id
LEFT JOIN clubs   cl ON cl.id = ma.club_id
LEFT JOIN players pl ON pl.id = ma.player_id
WHERE ma.status = 'published'
ORDER BY ma.published_at DESC;

-- View: match media bundle (all content for a single fixture)
CREATE VIEW v_fixture_media AS
SELECT
  ma.id,
  ma.fixture_id,
  f.match_date,
  hc.name           AS home_club,
  ac.name           AS away_club,
  ma.asset_type,
  ma.title,
  ma.thumbnail_url,
  ma.media_url,
  ma.published_at,
  ma.view_count
FROM media_assets ma
JOIN  fixtures f   ON f.id  = ma.fixture_id
JOIN  clubs    hc  ON hc.id = f.home_club_id
JOIN  clubs    ac  ON ac.id = f.away_club_id
WHERE ma.status     = 'published'
  AND ma.fixture_id IS NOT NULL
ORDER BY ma.fixture_id, ma.asset_type, ma.published_at DESC;

-- Storage bucket for media uploads
INSERT INTO storage.buckets (id, name, public)
VALUES
  ('media-videos',    'media-videos',    false),  -- private; served via signed URLs
  ('media-thumbnails','media-thumbnails', true),  -- public CDN
  ('media-galleries', 'media-galleries',  true)   -- public CDN
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "storage: auth upload media-videos"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'media-videos' AND auth.uid() IS NOT NULL);

CREATE POLICY "storage: auth read media-videos"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'media-videos' AND auth.uid() IS NOT NULL);

CREATE POLICY "storage: public read media-thumbnails"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'media-thumbnails');

CREATE POLICY "storage: auth upload media-thumbnails"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'media-thumbnails' AND auth.uid() IS NOT NULL);

CREATE POLICY "storage: public read media-galleries"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'media-galleries');

CREATE POLICY "storage: auth upload media-galleries"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'media-galleries' AND auth.uid() IS NOT NULL);


-- ============================================================
-- SECTION F: MODULE 5 — NOTIFICATIONS
-- ============================================================
-- Design rationale:
--   Two-table approach:
--
--   notifications        — the canonical notification record.
--                          One row per event. Stores the type,
--                          human-readable message, and all
--                          optional context FKs. Acts as both
--                          the delivery queue and the inbox.
--
--   notification_recipients — fan-out table. One row per
--                          (notification, recipient profile).
--                          Tracks per-user read status and
--                          delivery channel. Enables broadcast
--                          (league-wide, club-wide) while
--                          keeping per-user state private.
--
--   Supabase Realtime on notification_recipients enables the
--   in-app bell feed: subscribe WHERE profile_id = auth.uid().
--
--   System triggers in other modules INSERT into notifications
--   and then INSERT fan-out rows into notification_recipients.
--   The app layer handles push / email / SMS delivery using
--   the channel column as the routing instruction.
-- ============================================================

CREATE TABLE notifications (
  id                UUID                  PRIMARY KEY DEFAULT uuid_generate_v4(),

  notification_type notification_type     NOT NULL,
  channel           notification_channel  NOT NULL DEFAULT 'in_app',

  -- Human-readable content
  title             TEXT                  NOT NULL,
  body              TEXT                  NOT NULL,

  -- Deep-link path for the app (e.g. '/fixtures/abc-123')
  action_url        TEXT,

  -- Optional context FKs — populate whichever are relevant
  league_id         UUID                  REFERENCES leagues(id) ON DELETE SET NULL,
  club_id           UUID                  REFERENCES clubs(id) ON DELETE SET NULL,
  fixture_id        UUID                  REFERENCES fixtures(id) ON DELETE SET NULL,
  player_id         UUID                  REFERENCES players(id) ON DELETE SET NULL,
  suspension_id     UUID                  REFERENCES suspensions(id) ON DELETE SET NULL,
  injury_id         UUID                  REFERENCES player_injuries(id) ON DELETE SET NULL,
  media_asset_id    UUID                  REFERENCES media_assets(id) ON DELETE SET NULL,

  -- Who or what generated this notification
  -- NULL = system-generated (trigger)
  sent_by           UUID                  REFERENCES profiles(id) ON DELETE SET NULL,

  -- Scheduling: if set, delivery is deferred until this time
  scheduled_at      TIMESTAMPTZ,

  -- Expiry: notification auto-hides from feeds after this time
  expires_at        TIMESTAMPTZ,

  created_at        TIMESTAMPTZ           NOT NULL DEFAULT NOW()
  -- No updated_at — notifications are immutable once created.
  -- Cancel by setting expires_at = NOW() on the row.
);

-- Per-user delivery and read-status record
CREATE TABLE notification_recipients (
  id                UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

  notification_id   UUID        NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  profile_id        UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  -- Delivery state
  is_read           BOOLEAN     NOT NULL DEFAULT false,
  read_at           TIMESTAMPTZ,

  -- Delivery channel for this specific recipient (may differ from parent)
  channel           notification_channel NOT NULL DEFAULT 'in_app',

  -- Whether the external delivery (email/push/SMS) was sent successfully
  delivered         BOOLEAN     NOT NULL DEFAULT false,
  delivered_at      TIMESTAMPTZ,
  delivery_error    TEXT,       -- Error message if delivery failed

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (notification_id, profile_id)
);

-- ---------------------------------------------------------------
-- Trigger: auto-stamp read_at when is_read flips to true
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION stamp_notification_read_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF (OLD.is_read = false AND NEW.is_read = true AND NEW.read_at IS NULL) THEN
    NEW.read_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_stamp_notification_read_at
  BEFORE UPDATE ON notification_recipients
  FOR EACH ROW EXECUTE FUNCTION stamp_notification_read_at();

-- updated_at trigger
CREATE TRIGGER trg_notification_recipients_updated_at
  BEFORE UPDATE ON notification_recipients
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ---------------------------------------------------------------
-- Trigger: when a suspension is auto-completed (is_active → false),
-- create a system notification and fan out to the club admin.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_suspension_completed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_notif_id    UUID;
  v_club_admin  UUID;
  v_player_name TEXT;
  v_league_name TEXT;
BEGIN
  -- Only fire when is_active flips false (ban fully served)
  IF (OLD.is_active = true AND NEW.is_active = false) THEN

    SELECT pl.full_name, l.name
    INTO   v_player_name, v_league_name
    FROM   players pl
    JOIN   leagues l ON l.id = NEW.league_id
    WHERE  pl.id = NEW.player_id;

    -- Create the notification record
    INSERT INTO notifications (
      notification_type, channel, title, body,
      league_id, player_id, suspension_id
    )
    VALUES (
      'suspension_completed',
      'in_app',
      'Suspension Completed',
      v_player_name || ' has served their full suspension in ' || v_league_name || ' and is now eligible to play.',
      NEW.league_id,
      NEW.player_id,
      NEW.id
    )
    RETURNING id INTO v_notif_id;

    -- Fan out to the club admin of the player's current club
    SELECT c.admin_id INTO v_club_admin
    FROM   players pl
    JOIN   clubs   c ON c.id = pl.club_id
    WHERE  pl.id = NEW.player_id;

    IF v_club_admin IS NOT NULL THEN
      INSERT INTO notification_recipients (notification_id, profile_id, channel)
      VALUES (v_notif_id, v_club_admin, 'in_app')
      ON CONFLICT (notification_id, profile_id) DO NOTHING;
    END IF;

  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_notify_suspension_completed
  AFTER UPDATE ON suspensions
  FOR EACH ROW EXECUTE FUNCTION notify_suspension_completed();

-- ---------------------------------------------------------------
-- Trigger: when a disciplinary_record is inserted (card issued),
-- notify the affected player's club admin.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_card_issued()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_notif_id    UUID;
  v_club_admin  UUID;
  v_player_name TEXT;
  v_card_label  TEXT;
BEGIN
  SELECT pl.full_name INTO v_player_name
  FROM   players pl WHERE pl.id = NEW.player_id;

  v_card_label := CASE NEW.card_type
    WHEN 'yellow'        THEN 'Yellow Card'
    WHEN 'red'           THEN 'Red Card'
    WHEN 'second_yellow' THEN 'Second Yellow (Red)'
  END;

  INSERT INTO notifications (
    notification_type, channel, title, body,
    league_id, player_id, fixture_id
  )
  VALUES (
    'card_issued',
    'in_app',
    v_card_label || ' — ' || v_player_name,
    v_player_name || ' received a ' || v_card_label ||
      ' on ' || NEW.match_date::TEXT || '.',
    NEW.league_id,
    NEW.player_id,
    NEW.fixture_id
  )
  RETURNING id INTO v_notif_id;

  -- Fan out to club admin
  SELECT c.admin_id INTO v_club_admin
  FROM   players pl
  JOIN   clubs   c ON c.id = pl.club_id
  WHERE  pl.id = NEW.player_id;

  IF v_club_admin IS NOT NULL THEN
    INSERT INTO notification_recipients (notification_id, profile_id, channel)
    VALUES (v_notif_id, v_club_admin, 'in_app')
    ON CONFLICT (notification_id, profile_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_notify_card_issued
  AFTER INSERT ON disciplinary_records
  FOR EACH ROW EXECUTE FUNCTION notify_card_issued();

-- ---------------------------------------------------------------
-- Trigger: when a fixture is rescheduled or cancelled, notify
-- both clubs' admins.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_fixture_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_notif_id      UUID;
  v_notif_type    notification_type;
  v_title         TEXT;
  v_body          TEXT;
  v_home_admin    UUID;
  v_away_admin    UUID;
BEGIN
  -- Only fire on status changes that clubs need to know about
  IF OLD.status = NEW.status AND OLD.match_date IS NOT DISTINCT FROM NEW.match_date THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'postponed' THEN
    v_notif_type := 'fixture_postponed';
    v_title      := 'Fixture Postponed';
    v_body       := 'A fixture scheduled for ' ||
                    COALESCE(OLD.match_date::TEXT, 'TBD') ||
                    ' has been postponed.';

  ELSIF NEW.status = 'cancelled' THEN
    v_notif_type := 'fixture_cancelled';
    v_title      := 'Fixture Cancelled';
    v_body       := 'A fixture has been cancelled.';

  ELSIF OLD.match_date IS DISTINCT FROM NEW.match_date
        AND NEW.status NOT IN ('cancelled', 'postponed') THEN
    v_notif_type := 'fixture_rescheduled';
    v_title      := 'Fixture Rescheduled';
    v_body       := 'Fixture date changed to ' ||
                    COALESCE(NEW.match_date::TEXT, 'TBD') || '.';
  ELSE
    RETURN NEW;  -- No notification-worthy change
  END IF;

  INSERT INTO notifications (
    notification_type, channel, title, body,
    league_id, fixture_id
  )
  VALUES (
    v_notif_type, 'in_app', v_title, v_body,
    NEW.league_id, NEW.id
  )
  RETURNING id INTO v_notif_id;

  -- Fan out to home and away club admins
  SELECT admin_id INTO v_home_admin FROM clubs WHERE id = NEW.home_club_id;
  SELECT admin_id INTO v_away_admin FROM clubs WHERE id = NEW.away_club_id;

  IF v_home_admin IS NOT NULL THEN
    INSERT INTO notification_recipients (notification_id, profile_id, channel)
    VALUES (v_notif_id, v_home_admin, 'in_app')
    ON CONFLICT (notification_id, profile_id) DO NOTHING;
  END IF;

  IF v_away_admin IS NOT NULL AND v_away_admin <> v_home_admin THEN
    INSERT INTO notification_recipients (notification_id, profile_id, channel)
    VALUES (v_notif_id, v_away_admin, 'in_app')
    ON CONFLICT (notification_id, profile_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_notify_fixture_change
  AFTER UPDATE ON fixtures
  FOR EACH ROW EXECUTE FUNCTION notify_fixture_change();

-- ---------------------------------------------------------------
-- Trigger: when a result is ratified (is_official → true),
-- notify both clubs.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_result_official()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_notif_id    UUID;
  v_home_admin  UUID;
  v_away_admin  UUID;
  v_league_id   UUID;
  v_fixture_id  UUID;
  v_home_club   UUID;
  v_away_club   UUID;
BEGIN
  IF (TG_OP = 'UPDATE' AND OLD.is_official = false AND NEW.is_official = true)
    OR (TG_OP = 'INSERT' AND NEW.is_official = true) THEN

    SELECT f.league_id, f.home_club_id, f.away_club_id
    INTO   v_league_id, v_home_club, v_away_club
    FROM   fixtures f WHERE f.id = NEW.fixture_id;

    v_fixture_id := NEW.fixture_id;

    INSERT INTO notifications (
      notification_type, channel, title, body,
      league_id, fixture_id
    )
    VALUES (
      'fixture_result_official', 'in_app',
      'Result Ratified',
      'The result has been officially ratified: ' ||
        NEW.home_goals::TEXT || ' – ' || NEW.away_goals::TEXT || '.',
      v_league_id, v_fixture_id
    )
    RETURNING id INTO v_notif_id;

    SELECT admin_id INTO v_home_admin FROM clubs WHERE id = v_home_club;
    SELECT admin_id INTO v_away_admin FROM clubs WHERE id = v_away_club;

    IF v_home_admin IS NOT NULL THEN
      INSERT INTO notification_recipients (notification_id, profile_id, channel)
      VALUES (v_notif_id, v_home_admin, 'in_app')
      ON CONFLICT (notification_id, profile_id) DO NOTHING;
    END IF;

    IF v_away_admin IS NOT NULL AND v_away_admin <> v_home_admin THEN
      INSERT INTO notification_recipients (notification_id, profile_id, channel)
      VALUES (v_notif_id, v_away_admin, 'in_app')
      ON CONFLICT (notification_id, profile_id) DO NOTHING;
    END IF;

  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_notify_result_official
  AFTER INSERT OR UPDATE ON match_results
  FOR EACH ROW EXECUTE FUNCTION notify_result_official();

-- ---------------------------------------------------------------
-- Trigger: when a payment record becomes overdue or is approved,
-- notify the club admin.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_payment_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_notif_id    UUID;
  v_club_admin  UUID;
  v_notif_type  notification_type;
  v_title       TEXT;
  v_body        TEXT;
  v_club_name   TEXT;
BEGIN
  -- Only fire on meaningful status transitions
  IF OLD.payment_status = NEW.payment_status THEN
    RETURN NEW;
  END IF;

  SELECT c.admin_id, c.name
  INTO   v_club_admin, v_club_name
  FROM   clubs c WHERE c.id = NEW.club_id;

  IF NEW.payment_status = 'overdue' THEN
    v_notif_type := 'payment_overdue';
    v_title      := 'Payment Overdue — ' || v_club_name;
    v_body       := 'Your registration fee of ' ||
                    NEW.currency || ' ' || NEW.amount_due::TEXT ||
                    ' is overdue. Please settle immediately.';

  ELSIF NEW.payment_status = 'paid' THEN
    v_notif_type := 'payment_approved';
    v_title      := 'Payment Confirmed — ' || v_club_name;
    v_body       := 'Your payment of ' ||
                    NEW.currency || ' ' || NEW.amount_paid::TEXT ||
                    ' has been confirmed.';

  ELSE
    RETURN NEW;  -- No notification for other status changes
  END IF;

  IF v_club_admin IS NOT NULL THEN
    INSERT INTO notifications (
      notification_type, channel, title, body,
      league_id, club_id
    )
    VALUES (
      v_notif_type, 'in_app', v_title, v_body,
      NEW.league_id, NEW.club_id
    )
    RETURNING id INTO v_notif_id;

    INSERT INTO notification_recipients (notification_id, profile_id, channel)
    VALUES (v_notif_id, v_club_admin, 'in_app')
    ON CONFLICT (notification_id, profile_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_notify_payment_status
  AFTER UPDATE ON club_league_payments
  FOR EACH ROW EXECUTE FUNCTION notify_payment_status_change();

-- ---------------------------------------------------------------
-- Trigger: when a player injury is reported, notify club admin.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_injury_reported()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_notif_id    UUID;
  v_club_admin  UUID;
  v_player_name TEXT;
BEGIN
  SELECT pl.full_name INTO v_player_name
  FROM   players pl WHERE pl.id = NEW.player_id;

  SELECT c.admin_id INTO v_club_admin
  FROM   clubs c WHERE c.id = NEW.club_id;

  INSERT INTO notifications (
    notification_type, channel, title, body,
    club_id, player_id, injury_id
  )
  VALUES (
    'injury_reported', 'in_app',
    'Injury Reported — ' || v_player_name,
    v_player_name || ' has been reported with a ' ||
      NEW.severity::TEXT || ' ' || NEW.injury_type::TEXT ||
      ' injury (' || NEW.body_part || ').',
    NEW.club_id, NEW.player_id, NEW.id
  )
  RETURNING id INTO v_notif_id;

  IF v_club_admin IS NOT NULL THEN
    INSERT INTO notification_recipients (notification_id, profile_id, channel)
    VALUES (v_notif_id, v_club_admin, 'in_app')
    ON CONFLICT (notification_id, profile_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_notify_injury_reported
  AFTER INSERT ON player_injuries
  FOR EACH ROW EXECUTE FUNCTION notify_injury_reported();

-- Indexes — notifications
CREATE INDEX idx_notif_type            ON notifications(notification_type);
CREATE INDEX idx_notif_league          ON notifications(league_id);
CREATE INDEX idx_notif_club            ON notifications(club_id);
CREATE INDEX idx_notif_fixture         ON notifications(fixture_id);
CREATE INDEX idx_notif_player          ON notifications(player_id);
CREATE INDEX idx_notif_created         ON notifications(created_at DESC);
CREATE INDEX idx_notif_scheduled       ON notifications(scheduled_at)
  WHERE scheduled_at IS NOT NULL;

-- Indexes — notification_recipients
CREATE INDEX idx_nr_profile            ON notification_recipients(profile_id);
CREATE INDEX idx_nr_notification       ON notification_recipients(notification_id);
CREATE INDEX idx_nr_unread             ON notification_recipients(profile_id, is_read)
  WHERE is_read = false;
-- Supabase Realtime optimisation: per-user unread feed
CREATE INDEX idx_nr_profile_unread     ON notification_recipients(profile_id, created_at DESC)
  WHERE is_read = false;

-- RLS — notifications
ALTER TABLE notifications            ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_recipients  ENABLE ROW LEVEL SECURITY;

-- Notifications themselves are readable by developers and league admins
-- Regular users read their own via notification_recipients
CREATE POLICY "notifications: admin read"
  ON notifications FOR SELECT
  USING (
    get_my_role() = 'developer'
    OR (league_id IS NOT NULL AND is_league_admin(league_id))
    OR sent_by = auth.uid()
  );

-- Only system triggers (SECURITY DEFINER) and developers insert notifications
CREATE POLICY "notifications: developer insert"
  ON notifications FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (league_id IS NOT NULL AND is_league_admin(league_id))
    OR (club_id IS NOT NULL AND is_club_admin(club_id))
  );

-- RLS — notification_recipients
-- Users see only their own notification rows
CREATE POLICY "notification_recipients: own read"
  ON notification_recipients FOR SELECT
  USING (
    profile_id = auth.uid()
    OR get_my_role() = 'developer'
  );

-- System triggers insert fan-out rows (SECURITY DEFINER bypasses RLS)
-- This policy covers any direct app-layer inserts
CREATE POLICY "notification_recipients: system insert"
  ON notification_recipients FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR profile_id = auth.uid()
  );

-- Users can only mark their own notifications as read
CREATE POLICY "notification_recipients: own update"
  ON notification_recipients FOR UPDATE
  USING (
    profile_id = auth.uid()
    OR get_my_role() = 'developer'
  );

-- View: per-user notification inbox (Realtime-friendly)
CREATE VIEW v_my_notifications AS
SELECT
  nr.id                   AS recipient_id,
  nr.profile_id,
  nr.is_read,
  nr.read_at,
  nr.channel,
  nr.delivered,
  nr.created_at           AS received_at,
  n.id                    AS notification_id,
  n.notification_type,
  n.title,
  n.body,
  n.action_url,
  n.league_id,
  n.club_id,
  n.fixture_id,
  n.player_id,
  n.suspension_id,
  n.injury_id,
  n.media_asset_id,
  n.expires_at,
  n.created_at            AS notification_created_at
FROM notification_recipients nr
JOIN notifications n ON n.id = nr.notification_id
WHERE nr.profile_id = auth.uid()
  AND (n.expires_at IS NULL OR n.expires_at > NOW())
ORDER BY nr.created_at DESC;

-- View: unread notification count per profile (badge counter)
CREATE VIEW v_unread_notification_count AS
SELECT
  nr.profile_id,
  COUNT(*) AS unread_count
FROM notification_recipients nr
JOIN notifications n ON n.id = nr.notification_id
WHERE nr.is_read = false
  AND (n.expires_at IS NULL OR n.expires_at > NOW())
GROUP BY nr.profile_id;

-- View: league-wide notification broadcast history
CREATE VIEW v_league_notifications AS
SELECT
  n.id,
  n.notification_type,
  n.title,
  n.body,
  n.league_id,
  l.name              AS league_name,
  n.fixture_id,
  n.player_id,
  n.created_at,
  COUNT(nr.id)        AS recipient_count,
  COUNT(nr.id) FILTER (WHERE nr.is_read = true) AS read_count
FROM notifications n
JOIN  leagues l  ON l.id = n.league_id
LEFT JOIN notification_recipients nr ON nr.notification_id = n.id
WHERE n.league_id IS NOT NULL
GROUP BY n.id, n.notification_type, n.title, n.body,
         n.league_id, l.name, n.fixture_id, n.player_id, n.created_at
ORDER BY n.created_at DESC;


-- ============================================================
-- PHASE 3 SUMMARY
-- ============================================================
-- New enums:        8   club_staff_role, injury_type,
--                       injury_severity, media_asset_type,
--                       media_visibility, media_status,
--                       notification_channel, notification_type
--
-- New tables:       7   club_staff, player_injuries,
--                       suspension_served_matches,
--                       media_assets, media_asset_tags,
--                       notifications, notification_recipients
--
-- New functions:    9   auto_clear_injury,
--                       process_suspension_served_match,
--                       stamp_media_published_at,
--                       stamp_notification_read_at,
--                       notify_suspension_completed,
--                       notify_card_issued,
--                       notify_fixture_change,
--                       notify_result_official,
--                       notify_payment_status_change,
--                       notify_injury_reported
--
-- New triggers:    13   trg_club_staff_updated_at,
--                       trg_auto_clear_injury,
--                       trg_player_injuries_updated_at,
--                       trg_process_suspension_served,
--                       trg_stamp_media_published_at,
--                       trg_media_assets_updated_at,
--                       trg_stamp_notification_read_at,
--                       trg_notification_recipients_updated_at,
--                       trg_notify_suspension_completed,
--                       trg_notify_card_issued,
--                       trg_notify_fixture_change,
--                       trg_notify_result_official,
--                       trg_notify_payment_status,
--                       trg_notify_injury_reported
--
-- New views:       10   v_club_staff, v_active_injuries,
--                       v_player_injury_history,
--                       v_suspension_progress,
--                       v_media_feed, v_fixture_media,
--                       v_my_notifications,
--                       v_unread_notification_count,
--                       v_league_notifications
--
-- New indexes:     28
-- New RLS policies: 25+
-- New storage buckets: 3
-- ============================================================
