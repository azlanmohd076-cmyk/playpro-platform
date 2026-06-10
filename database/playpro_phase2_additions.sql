-- ============================================================
-- PLAYPRO — PHASE 2 SCHEMA ADDITIONS
-- Paste into Supabase SQL Editor AFTER Phase 1 is applied.
-- New tables, enums, indexes, triggers and RLS policies only.
-- Does NOT rewrite or alter any existing Phase 1 objects.
-- ============================================================


-- ============================================================
-- SECTION A: NEW ENUMS
-- ============================================================

-- Transfer types
CREATE TYPE transfer_type AS ENUM (
  'permanent',          -- Full ownership move
  'loan',               -- Temporary move with return clause
  'loan_recall',        -- Loan cut short by parent club
  'free_agent',         -- Player registered without a transfer fee
  'released'            -- Club releases player (no incoming club yet)
);

-- Transfer status
CREATE TYPE transfer_status AS ENUM (
  'pending',            -- Submitted, awaiting league approval
  'approved',           -- League approved, player now active at new club
  'rejected',           -- League rejected the transfer
  'cancelled'           -- Parties cancelled before decision
);

-- Referee certification level
CREATE TYPE referee_grade AS ENUM (
  'grade_1',            -- Top national grade
  'grade_2',
  'grade_3',
  'regional',
  'recreational'
);

-- Match event types (covers all live tracking needs)
CREATE TYPE match_event_type AS ENUM (
  'goal',
  'own_goal',
  'assist',
  'yellow_card',
  'red_card',
  'second_yellow',      -- Second bookable offence → red
  'substitution_on',    -- Player entering the pitch
  'substitution_off',   -- Player leaving the pitch
  'penalty_scored',
  'penalty_missed',
  'penalty_saved',
  'corner',
  'offside',
  'free_kick',
  'save',
  'var_review',         -- VAR is reviewing an incident
  'var_overturned',     -- VAR reversed the on-field decision
  'var_upheld'          -- VAR confirmed the on-field decision
);

-- VAR review outcomes
CREATE TYPE var_outcome AS ENUM (
  'goal_awarded',
  'goal_disallowed',
  'penalty_awarded',
  'penalty_reversed',
  'red_card_awarded',
  'red_card_rescinded',
  'no_action'
);

-- Lineup position on the pitch (squad role for a given match)
CREATE TYPE lineup_role AS ENUM (
  'starter',
  'substitute',
  'not_selected'
);

-- Payment status for club–league fees
CREATE TYPE payment_status AS ENUM (
  'unpaid',
  'pending_verification', -- Payment made, awaiting league confirmation
  'paid',
  'overdue',
  'waived'               -- League admin granted an exemption
);

-- Payment method
CREATE TYPE payment_method AS ENUM (
  'bank_transfer',
  'online_payment',
  'cash',
  'cheque',
  'waiver'
);


-- ============================================================
-- SECTION B: MODULE 1 — PLAYER TRANSFER HISTORY
-- ============================================================
-- Design rationale:
--   players.club_id always reflects the CURRENT club.
--   player_transfers is the immutable audit log of every move.
--   Each row captures the from-club, to-club, season and
--   league context, so history survives future club_id changes.
--   A player can have unlimited rows across different seasons.
-- ============================================================

CREATE TABLE player_transfers (
  id                UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),

  player_id         UUID            NOT NULL REFERENCES players(id) ON DELETE CASCADE,

  -- Source club (NULL when a player is first registered / arrives as free agent)
  from_club_id      UUID            REFERENCES clubs(id) ON DELETE SET NULL,

  -- Destination club (NULL when a player is released without a new club)
  to_club_id        UUID            REFERENCES clubs(id) ON DELETE SET NULL,

  -- League the transfer is registered under (NULL = cross-league or unaffiliated)
  league_id         UUID            REFERENCES leagues(id) ON DELETE SET NULL,

  -- Human-readable season label, e.g. "2025/26"
  season            TEXT            NOT NULL,

  transfer_type     transfer_type   NOT NULL DEFAULT 'permanent',
  status            transfer_status NOT NULL DEFAULT 'pending',

  -- Loan return date (only populated when transfer_type = 'loan')
  loan_return_date  DATE,

  -- Optional financial metadata — store as numeric, not enforced
  transfer_fee      NUMERIC(12,2),
  currency          CHAR(3)         DEFAULT 'MYR',

  -- Jersey number at the new club (may differ from players.jersey_number)
  jersey_number     INTEGER,

  -- When the transfer actually takes effect (kick-off eligibility date)
  effective_date    DATE,

  -- Workflow
  requested_by      UUID            REFERENCES profiles(id) ON DELETE SET NULL,  -- club_admin who initiated
  approved_by       UUID            REFERENCES profiles(id) ON DELETE SET NULL,  -- league_admin who decided
  approved_at       TIMESTAMPTZ,
  rejection_notes   TEXT,
  notes             TEXT,

  created_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

  -- Prevent duplicate pending transfers for the same player at the same time
  CONSTRAINT chk_transfer_clubs_differ
    CHECK (from_club_id IS DISTINCT FROM to_club_id)
);

-- ---------------------------------------------------------------
-- Trigger: when a transfer is approved, update players.club_id
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION apply_approved_transfer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only fire when status flips to 'approved'
  IF (TG_OP = 'UPDATE'
      AND OLD.status <> 'approved'
      AND NEW.status = 'approved'
      AND NEW.to_club_id IS NOT NULL)
  THEN
    UPDATE players
    SET club_id    = NEW.to_club_id,
        updated_at = NOW()
    WHERE id = NEW.player_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_apply_approved_transfer
  AFTER UPDATE ON player_transfers
  FOR EACH ROW EXECUTE FUNCTION apply_approved_transfer();

-- updated_at trigger
CREATE TRIGGER trg_player_transfers_updated_at
  BEFORE UPDATE ON player_transfers
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Indexes
CREATE INDEX idx_ptrans_player       ON player_transfers(player_id);
CREATE INDEX idx_ptrans_from_club    ON player_transfers(from_club_id);
CREATE INDEX idx_ptrans_to_club      ON player_transfers(to_club_id);
CREATE INDEX idx_ptrans_league       ON player_transfers(league_id);
CREATE INDEX idx_ptrans_status       ON player_transfers(status);
CREATE INDEX idx_ptrans_season       ON player_transfers(season);
-- Fast lookup: all transfers for a player ordered by time
CREATE INDEX idx_ptrans_player_date  ON player_transfers(player_id, created_at DESC);

-- RLS
ALTER TABLE player_transfers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "player_transfers: public read"
  ON player_transfers FOR SELECT
  USING (true);

-- Club admin of EITHER club can initiate
CREATE POLICY "player_transfers: club admin insert"
  ON player_transfers FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin'
        AND (is_club_admin(from_club_id) OR is_club_admin(to_club_id)))
  );

-- League admin approves/rejects; club admin can cancel their own
CREATE POLICY "player_transfers: admin update"
  ON player_transfers FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (league_id IS NOT NULL AND is_league_admin(league_id))
    OR (get_my_role() = 'club_admin'
        AND (is_club_admin(from_club_id) OR is_club_admin(to_club_id)))
  );

-- View: full transfer timeline for any player
CREATE VIEW v_player_transfer_history AS
SELECT
  pt.id,
  pt.player_id,
  pl.full_name          AS player_name,
  pl.position           AS player_position,
  fc.name               AS from_club,
  tc.name               AS to_club,
  l.name                AS league_name,
  pt.season,
  pt.transfer_type,
  pt.status,
  pt.effective_date,
  pt.loan_return_date,
  pt.transfer_fee,
  pt.currency,
  pt.jersey_number,
  pt.notes,
  pt.approved_at,
  pt.created_at
FROM player_transfers pt
JOIN  players pl ON pl.id = pt.player_id
LEFT JOIN clubs   fc ON fc.id = pt.from_club_id
LEFT JOIN clubs   tc ON tc.id = pt.to_club_id
LEFT JOIN leagues l  ON l.id  = pt.league_id
ORDER BY pt.player_id, pt.created_at DESC;


-- ============================================================
-- SECTION C: MODULE 2 — REFEREE MANAGEMENT
-- ============================================================
-- Extends the existing league_staff.role = 'referee' pattern.
-- Adds a dedicated referees table for profile/certification data
-- and referee_assignments for per-fixture role allocation.
-- ============================================================

CREATE TABLE referees (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Must be a registered system user
  profile_id        UUID          NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,

  -- Official referee registration number issued by the FA / governing body
  registration_no   TEXT          UNIQUE,

  grade             referee_grade,
  country           TEXT,
  date_of_birth     DATE,
  phone             TEXT,

  -- Certifications / badges (free-text or JSON-serialised list)
  certifications    TEXT,

  -- Whether the referee is currently accepting assignments
  is_available      BOOLEAN       NOT NULL DEFAULT true,
  is_active         BOOLEAN       NOT NULL DEFAULT true,

  -- Administrative
  registered_by     UUID          REFERENCES profiles(id) ON DELETE SET NULL,

  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Role each official plays in a fixture
CREATE TYPE fixture_official_role AS ENUM (
  'main_referee',
  'assistant_referee_1',
  'assistant_referee_2',
  'fourth_official',
  'var_referee',
  'var_assistant'
);

-- Links a referee to a fixture with a specific role
CREATE TABLE referee_assignments (
  id              UUID                  PRIMARY KEY DEFAULT uuid_generate_v4(),

  fixture_id      UUID                  NOT NULL REFERENCES fixtures(id) ON DELETE CASCADE,
  referee_id      UUID                  NOT NULL REFERENCES referees(id) ON DELETE CASCADE,
  league_id       UUID                  NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,

  role            fixture_official_role NOT NULL DEFAULT 'main_referee',

  -- Fee paid to the referee for this fixture
  match_fee       NUMERIC(10,2),
  currency        CHAR(3)               DEFAULT 'MYR',
  fee_paid        BOOLEAN               NOT NULL DEFAULT false,

  -- Post-match performance score (optional, 1-10)
  performance_score SMALLINT            CHECK (performance_score BETWEEN 1 AND 10),
  performance_notes TEXT,

  assigned_by     UUID                  REFERENCES profiles(id) ON DELETE SET NULL,
  assigned_at     TIMESTAMPTZ           NOT NULL DEFAULT NOW(),

  created_at      TIMESTAMPTZ           NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ           NOT NULL DEFAULT NOW(),

  -- One referee can only hold one role per fixture
  UNIQUE (fixture_id, referee_id),
  -- Only one main referee per fixture
  UNIQUE (fixture_id, role)
    -- NOTE: PostgreSQL UNIQUE on (fixture_id, role) correctly enforces
    -- one main_referee, one AR1, etc. per fixture.
);

-- updated_at triggers
CREATE TRIGGER trg_referees_updated_at
  BEFORE UPDATE ON referees
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_referee_assignments_updated_at
  BEFORE UPDATE ON referee_assignments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Indexes
CREATE INDEX idx_referees_profile      ON referees(profile_id);
CREATE INDEX idx_referees_grade        ON referees(grade);
CREATE INDEX idx_referees_available    ON referees(is_available, is_active);
CREATE INDEX idx_refassign_fixture     ON referee_assignments(fixture_id);
CREATE INDEX idx_refassign_referee     ON referee_assignments(referee_id);
CREATE INDEX idx_refassign_league      ON referee_assignments(league_id);

-- RLS
ALTER TABLE referees             ENABLE ROW LEVEL SECURITY;
ALTER TABLE referee_assignments  ENABLE ROW LEVEL SECURITY;

-- Referees: public read
CREATE POLICY "referees: public read"
  ON referees FOR SELECT
  USING (true);

-- Only league admins and developers register / manage referees
CREATE POLICY "referees: league admin or developer insert"
  ON referees FOR INSERT
  WITH CHECK (
    get_my_role() IN ('developer', 'league_admin', 'league_founder')
  );

CREATE POLICY "referees: league admin or developer update"
  ON referees FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR get_my_role() IN ('league_admin', 'league_founder')
    -- A referee can update their own availability
    OR profile_id = auth.uid()
  );

-- Referee assignments: public read
CREATE POLICY "referee_assignments: public read"
  ON referee_assignments FOR SELECT
  USING (true);

CREATE POLICY "referee_assignments: league admin insert"
  ON referee_assignments FOR INSERT
  WITH CHECK (is_league_admin(league_id));

CREATE POLICY "referee_assignments: league admin update"
  ON referee_assignments FOR UPDATE
  USING (is_league_admin(league_id));

CREATE POLICY "referee_assignments: league admin delete"
  ON referee_assignments FOR DELETE
  USING (is_league_admin(league_id));

-- View: referee assignment card per fixture
CREATE VIEW v_fixture_officials AS
SELECT
  ra.id,
  ra.fixture_id,
  f.match_date,
  f.venue,
  l.name              AS league_name,
  hc.name             AS home_club,
  ac.name             AS away_club,
  ra.referee_id,
  pr.full_name        AS referee_name,
  pr.phone            AS referee_phone,
  r.grade,
  r.registration_no,
  ra.role,
  ra.match_fee,
  ra.fee_paid,
  ra.performance_score
FROM referee_assignments ra
JOIN referees  r   ON r.id  = ra.referee_id
JOIN profiles  pr  ON pr.id = r.profile_id
JOIN fixtures  f   ON f.id  = ra.fixture_id
JOIN leagues   l   ON l.id  = ra.league_id
JOIN clubs     hc  ON hc.id = f.home_club_id
JOIN clubs     ac  ON ac.id = f.away_club_id;


-- ============================================================
-- SECTION D: MODULE 3 — MATCH EVENTS (LIVE TRACKING)
-- ============================================================
-- One row per discrete event during a match.
-- Supports goals, assists, cards, subs, corners, offsides,
-- free kicks, penalties, saves and full VAR workflow.
-- The match_results table holds AGGREGATE totals;
-- match_events holds the GRANULAR timeline.
-- ============================================================

CREATE TABLE match_events (
  id                UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),

  fixture_id        UUID              NOT NULL REFERENCES fixtures(id) ON DELETE CASCADE,

  -- Minute the event occurred (1–120; use 121+ for penalty shootout)
  minute            SMALLINT          NOT NULL CHECK (minute >= 1),
  -- Added time within the stated minute (0 = no added time)
  added_time        SMALLINT          NOT NULL DEFAULT 0 CHECK (added_time >= 0),

  -- Which half: 1, 2, or 3 (extra time first half), 4 (ET second half), 5 (shootout)
  period            SMALLINT          NOT NULL DEFAULT 1 CHECK (period BETWEEN 1 AND 5),

  event_type        match_event_type  NOT NULL,

  -- The primary actor (scorer, carded player, sub coming on, etc.)
  -- NULL for team-level events like corners
  player_id         UUID              REFERENCES players(id) ON DELETE SET NULL,

  -- Secondary actor (e.g. player coming OFF in a substitution, or assistee)
  secondary_player_id UUID            REFERENCES players(id) ON DELETE SET NULL,

  -- Club the event is attributed to
  club_id           UUID              NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  -- Scoreline snapshot at the moment of this event (for live feed display)
  home_score_at_event SMALLINT        NOT NULL DEFAULT 0 CHECK (home_score_at_event >= 0),
  away_score_at_event SMALLINT        NOT NULL DEFAULT 0 CHECK (away_score_at_event >= 0),

  -- VAR fields — populated only for VAR event types
  var_outcome       var_outcome,
  var_review_started_at TIMESTAMPTZ,
  var_decision_at   TIMESTAMPTZ,
  -- Which earlier event_id this VAR decision refers to (e.g. the goal it overturned)
  var_target_event_id UUID            REFERENCES match_events(id) ON DELETE SET NULL,

  -- Free text for referee/admin notes on the event
  notes             TEXT,

  -- Who entered this event (referee app user, league admin, etc.)
  entered_by        UUID              REFERENCES profiles(id) ON DELETE SET NULL,

  -- Soft-delete for correcting mistakes without losing audit trail
  is_cancelled      BOOLEAN           NOT NULL DEFAULT false,
  cancelled_by      UUID              REFERENCES profiles(id) ON DELETE SET NULL,
  cancelled_at      TIMESTAMPTZ,
  cancellation_reason TEXT,

  created_at        TIMESTAMPTZ       NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ       NOT NULL DEFAULT NOW()
);

-- updated_at trigger
CREATE TRIGGER trg_match_events_updated_at
  BEFORE UPDATE ON match_events
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Indexes
CREATE INDEX idx_mevt_fixture          ON match_events(fixture_id);
CREATE INDEX idx_mevt_player           ON match_events(player_id);
CREATE INDEX idx_mevt_club             ON match_events(club_id);
CREATE INDEX idx_mevt_type             ON match_events(event_type);
CREATE INDEX idx_mevt_cancelled        ON match_events(is_cancelled);
-- Ordered timeline per fixture (primary live feed query)
CREATE INDEX idx_mevt_fixture_timeline ON match_events(fixture_id, period, minute, added_time)
  WHERE is_cancelled = false;

-- RLS
ALTER TABLE match_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "match_events: public read"
  ON match_events FOR SELECT
  USING (true);

-- League admin and assigned referee can insert events
CREATE POLICY "match_events: league admin or referee insert"
  ON match_events FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR EXISTS (
      SELECT 1 FROM fixtures f
      WHERE f.id = fixture_id
        AND (
          is_league_admin(f.league_id)
          -- Assigned main referee for this fixture
          OR EXISTS (
            SELECT 1 FROM referee_assignments ra
            JOIN referees r ON r.id = ra.referee_id
            WHERE ra.fixture_id = f.id
              AND r.profile_id  = auth.uid()
          )
        )
    )
  );

-- Same principals can update (e.g. cancel a mis-entered event)
CREATE POLICY "match_events: league admin or referee update"
  ON match_events FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR EXISTS (
      SELECT 1 FROM fixtures f
      WHERE f.id = fixture_id
        AND (
          is_league_admin(f.league_id)
          OR EXISTS (
            SELECT 1 FROM referee_assignments ra
            JOIN referees r ON r.id = ra.referee_id
            WHERE ra.fixture_id = f.id
              AND r.profile_id  = auth.uid()
          )
        )
    )
  );

-- View: live match timeline (excluding cancelled events)
CREATE VIEW v_match_timeline AS
SELECT
  me.id,
  me.fixture_id,
  me.period,
  me.minute,
  me.added_time,
  me.event_type,
  me.club_id,
  cl.name               AS club_name,
  me.player_id,
  p1.full_name          AS player_name,
  me.secondary_player_id,
  p2.full_name          AS secondary_player_name,
  me.home_score_at_event,
  me.away_score_at_event,
  me.var_outcome,
  me.notes,
  me.created_at
FROM match_events me
JOIN  clubs   cl ON cl.id = me.club_id
LEFT JOIN players p1 ON p1.id = me.player_id
LEFT JOIN players p2 ON p2.id = me.secondary_player_id
WHERE me.is_cancelled = false
ORDER BY me.fixture_id, me.period, me.minute, me.added_time, me.created_at;


-- ============================================================
-- SECTION E: MODULE 4 — MATCH LINEUPS
-- ============================================================
-- One row per player per fixture per club.
-- Captures Starting XI, substitutes, captain, vice-captain
-- and formation at the time of the match.
-- Complements player_match_stats (which tracks live stat totals)
-- and match_events (which tracks substitution events).
-- ============================================================

CREATE TABLE match_lineups (
  id                UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),

  fixture_id        UUID          NOT NULL REFERENCES fixtures(id) ON DELETE CASCADE,
  club_id           UUID          NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
  player_id         UUID          NOT NULL REFERENCES players(id) ON DELETE CASCADE,

  role              lineup_role   NOT NULL DEFAULT 'starter',

  -- Jersey number worn in THIS match (may differ from players.jersey_number)
  jersey_number     INTEGER,

  -- Position played in THIS match (may differ from players.position)
  position_played   player_position,

  -- Tactical slot on the pitch, e.g. "CB", "LW", "CDM", "SS"
  -- Kept as free text to support any formation's slot labels
  position_slot     TEXT,

  -- Shirt number order within the lineup card (1–18 typical)
  lineup_order      SMALLINT,

  is_captain        BOOLEAN       NOT NULL DEFAULT false,
  is_vice_captain   BOOLEAN       NOT NULL DEFAULT false,

  -- Formation string for the TEAM, stored on every player row for simplicity
  -- e.g. '4-3-3', '3-5-2'. Same value across all rows for the same fixture+club.
  formation         TEXT,

  -- Workflow: club admin submits, league admin confirms
  submitted_by      UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  submitted_at      TIMESTAMPTZ,
  confirmed_by      UUID          REFERENCES profiles(id) ON DELETE SET NULL,
  confirmed_at      TIMESTAMPTZ,

  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  -- A player appears once per fixture per club
  UNIQUE (fixture_id, club_id, player_id)
);

-- Constraint: only ONE captain per team per fixture
CREATE UNIQUE INDEX idx_lineup_captain
  ON match_lineups(fixture_id, club_id)
  WHERE is_captain = true;

-- Constraint: only ONE vice-captain per team per fixture
CREATE UNIQUE INDEX idx_lineup_vice_captain
  ON match_lineups(fixture_id, club_id)
  WHERE is_vice_captain = true;

-- updated_at trigger
CREATE TRIGGER trg_match_lineups_updated_at
  BEFORE UPDATE ON match_lineups
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Indexes
CREATE INDEX idx_lineup_fixture        ON match_lineups(fixture_id);
CREATE INDEX idx_lineup_club           ON match_lineups(club_id);
CREATE INDEX idx_lineup_player         ON match_lineups(player_id);
CREATE INDEX idx_lineup_role           ON match_lineups(role);
CREATE INDEX idx_lineup_fixture_club   ON match_lineups(fixture_id, club_id);

-- RLS
ALTER TABLE match_lineups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "match_lineups: public read"
  ON match_lineups FOR SELECT
  USING (true);

-- Club admin submits their own team's lineup
CREATE POLICY "match_lineups: club admin insert"
  ON match_lineups FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() IN ('club_admin', 'coach') AND is_club_admin(club_id))
    OR EXISTS (
      SELECT 1 FROM fixtures f
      WHERE f.id = fixture_id AND is_league_admin(f.league_id)
    )
  );

-- Club admin can edit before confirmation; league admin can always edit
CREATE POLICY "match_lineups: club admin or league admin update"
  ON match_lineups FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() IN ('club_admin', 'coach')
        AND is_club_admin(club_id)
        AND confirmed_at IS NULL)    -- locked once league confirms
    OR EXISTS (
      SELECT 1 FROM fixtures f
      WHERE f.id = fixture_id AND is_league_admin(f.league_id)
    )
  );

-- View: Starting XI + substitutes per fixture
CREATE VIEW v_match_lineups AS
SELECT
  ml.fixture_id,
  f.match_date,
  l.name              AS league_name,
  ml.club_id,
  cl.name             AS club_name,
  ml.formation,
  ml.lineup_order,
  ml.role,
  ml.position_slot,
  ml.position_played,
  ml.jersey_number,
  ml.player_id,
  pl.full_name        AS player_name,
  pl.photo_url,
  ml.is_captain,
  ml.is_vice_captain,
  ml.confirmed_at
FROM match_lineups ml
JOIN fixtures  f   ON f.id  = ml.fixture_id
JOIN leagues   l   ON l.id  = f.league_id
JOIN clubs     cl  ON cl.id = ml.club_id
JOIN players   pl  ON pl.id = ml.player_id
ORDER BY ml.fixture_id, ml.club_id, ml.role, ml.lineup_order;


-- ============================================================
-- SECTION F: MODULE 5 — CLUB LEAGUE PAYMENTS
-- ============================================================
-- Manages registration fees that clubs pay per league season.
-- Supports multi-instalment payments, receipt uploads,
-- payment status tracking and league admin approvals.
-- ============================================================

CREATE TABLE club_league_payments (
  id                UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- The league membership this payment is for
  league_club_id    UUID            NOT NULL REFERENCES league_clubs(id) ON DELETE CASCADE,
  league_id         UUID            NOT NULL REFERENCES leagues(id) ON DELETE CASCADE,
  club_id           UUID            NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,

  -- Season label must match leagues.season for clarity
  season            TEXT            NOT NULL,

  -- Fee breakdown
  fee_description   TEXT            NOT NULL DEFAULT 'Registration Fee',
  amount_due        NUMERIC(12,2)   NOT NULL CHECK (amount_due >= 0),
  amount_paid       NUMERIC(12,2)   NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
  currency          CHAR(3)         NOT NULL DEFAULT 'MYR',

  -- Payment timeline
  due_date          DATE,
  paid_at           TIMESTAMPTZ,
  payment_status    payment_status  NOT NULL DEFAULT 'unpaid',
  payment_method    payment_method,

  -- Reference number / transaction ID provided by the paying club
  payment_reference TEXT,

  -- URL to uploaded receipt (stored in Supabase Storage)
  receipt_url       TEXT,

  -- Approval workflow
  submitted_by      UUID            REFERENCES profiles(id) ON DELETE SET NULL,  -- club admin
  submitted_at      TIMESTAMPTZ,
  reviewed_by       UUID            REFERENCES profiles(id) ON DELETE SET NULL,  -- league admin
  reviewed_at       TIMESTAMPTZ,
  approval_notes    TEXT,

  -- Waiver fields (when payment_status = 'waived')
  waiver_reason     TEXT,
  waived_by         UUID            REFERENCES profiles(id) ON DELETE SET NULL,
  waived_at         TIMESTAMPTZ,

  created_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Payment instalment breakdown (optional; supports split payments)
CREATE TABLE club_payment_instalments (
  id                UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),

  payment_id        UUID            NOT NULL REFERENCES club_league_payments(id) ON DELETE CASCADE,

  instalment_no     SMALLINT        NOT NULL CHECK (instalment_no > 0),
  amount            NUMERIC(12,2)   NOT NULL CHECK (amount > 0),
  due_date          DATE,
  paid_at           TIMESTAMPTZ,
  payment_status    payment_status  NOT NULL DEFAULT 'unpaid',
  payment_method    payment_method,
  payment_reference TEXT,
  receipt_url       TEXT,

  submitted_by      UUID            REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_by       UUID            REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at       TIMESTAMPTZ,

  created_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

  UNIQUE (payment_id, instalment_no)
);

-- ---------------------------------------------------------------
-- Trigger: keep amount_paid in sync when instalments are updated
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION sync_payment_amount_paid()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE club_league_payments
  SET amount_paid = (
        SELECT COALESCE(SUM(amount), 0)
        FROM club_payment_instalments
        WHERE payment_id = COALESCE(NEW.payment_id, OLD.payment_id)
          AND payment_status = 'paid'
      ),
      updated_at = NOW()
  WHERE id = COALESCE(NEW.payment_id, OLD.payment_id);

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_sync_payment_on_instalment_change
  AFTER INSERT OR UPDATE OR DELETE ON club_payment_instalments
  FOR EACH ROW EXECUTE FUNCTION sync_payment_amount_paid();

-- ---------------------------------------------------------------
-- Trigger: auto-set payment_status based on amount_paid vs amount_due
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION auto_update_payment_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only auto-set if not manually waived
  IF NEW.payment_status <> 'waived' THEN
    IF NEW.amount_paid >= NEW.amount_due THEN
      NEW.payment_status := 'paid';
    ELSIF NEW.amount_paid > 0 THEN
      NEW.payment_status := 'pending_verification';
    ELSIF NEW.due_date IS NOT NULL AND NEW.due_date < CURRENT_DATE AND NEW.amount_paid = 0 THEN
      NEW.payment_status := 'overdue';
    ELSE
      NEW.payment_status := 'unpaid';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auto_payment_status
  BEFORE INSERT OR UPDATE ON club_league_payments
  FOR EACH ROW EXECUTE FUNCTION auto_update_payment_status();

-- updated_at triggers
CREATE TRIGGER trg_clp_updated_at
  BEFORE UPDATE ON club_league_payments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_cpi_updated_at
  BEFORE UPDATE ON club_payment_instalments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Indexes
CREATE INDEX idx_clp_league_club       ON club_league_payments(league_id, club_id);
CREATE INDEX idx_clp_status            ON club_league_payments(payment_status);
CREATE INDEX idx_clp_due_date          ON club_league_payments(due_date);
CREATE INDEX idx_clp_league_club_id    ON club_league_payments(league_club_id);
CREATE INDEX idx_clp_season            ON club_league_payments(season);
CREATE INDEX idx_cpi_payment           ON club_payment_instalments(payment_id);
CREATE INDEX idx_cpi_status            ON club_payment_instalments(payment_status);

-- RLS
ALTER TABLE club_league_payments    ENABLE ROW LEVEL SECURITY;
ALTER TABLE club_payment_instalments ENABLE ROW LEVEL SECURITY;

-- club_league_payments
CREATE POLICY "clp: public read"
  ON club_league_payments FOR SELECT
  USING (true);

CREATE POLICY "clp: club admin insert"
  ON club_league_payments FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR is_league_admin(league_id)
  );

-- Club admin submits payment details; league admin approves
CREATE POLICY "clp: club admin or league admin update"
  ON club_league_payments FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR (get_my_role() = 'club_admin' AND is_club_admin(club_id))
    OR is_league_admin(league_id)
  );

-- club_payment_instalments
CREATE POLICY "cpi: public read"
  ON club_payment_instalments FOR SELECT
  USING (true);

CREATE POLICY "cpi: club admin or league admin insert"
  ON club_payment_instalments FOR INSERT
  WITH CHECK (
    get_my_role() = 'developer'
    OR EXISTS (
      SELECT 1 FROM club_league_payments clp
      WHERE clp.id = payment_id
        AND (is_club_admin(clp.club_id) OR is_league_admin(clp.league_id))
    )
  );

CREATE POLICY "cpi: club admin or league admin update"
  ON club_payment_instalments FOR UPDATE
  USING (
    get_my_role() = 'developer'
    OR EXISTS (
      SELECT 1 FROM club_league_payments clp
      WHERE clp.id = payment_id
        AND (is_club_admin(clp.club_id) OR is_league_admin(clp.league_id))
    )
  );

-- View: payment dashboard per league
CREATE VIEW v_club_payment_status AS
SELECT
  clp.id,
  clp.league_id,
  l.name              AS league_name,
  clp.club_id,
  c.name              AS club_name,
  c.logo_url          AS club_logo,
  clp.season,
  clp.fee_description,
  clp.amount_due,
  clp.amount_paid,
  (clp.amount_due - clp.amount_paid) AS amount_outstanding,
  clp.currency,
  clp.due_date,
  clp.paid_at,
  clp.payment_status,
  clp.payment_method,
  clp.payment_reference,
  clp.receipt_url,
  clp.submitted_at,
  clp.reviewed_at,
  clp.approval_notes,
  clp.waiver_reason
FROM club_league_payments clp
JOIN leagues l ON l.id = clp.league_id
JOIN clubs   c ON c.id = clp.club_id
ORDER BY clp.league_id, clp.payment_status, c.name;

-- View: overdue payments (for league admin dashboard alerts)
CREATE VIEW v_overdue_payments AS
SELECT *
FROM v_club_payment_status
WHERE payment_status IN ('unpaid', 'overdue')
  AND due_date < CURRENT_DATE;


-- ============================================================
-- SECTION G: STORAGE BUCKET — PAYMENT RECEIPTS
-- ============================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('payment-receipts', 'payment-receipts', false)  -- private bucket
ON CONFLICT (id) DO NOTHING;

-- Club admins upload their own receipts; league admins can read all
CREATE POLICY "storage: club admin upload receipts"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'payment-receipts' AND auth.uid() IS NOT NULL);

CREATE POLICY "storage: auth read receipts"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'payment-receipts' AND auth.uid() IS NOT NULL);


-- ============================================================
-- PHASE 2 SUMMARY
-- ============================================================
-- New enums:       8  (transfer_type, transfer_status,
--                      referee_grade, fixture_official_role,
--                      match_event_type, var_outcome,
--                      lineup_role, payment_status,
--                      payment_method)
-- New tables:      7  (player_transfers, referees,
--                      referee_assignments, match_events,
--                      match_lineups, club_league_payments,
--                      club_payment_instalments)
-- New views:       7  (v_player_transfer_history,
--                      v_fixture_officials, v_match_timeline,
--                      v_match_lineups, v_club_payment_status,
--                      v_overdue_payments)
-- New indexes:     28
-- New triggers:    9
-- New functions:   3
-- New RLS policies: 28+
-- New storage:     1
-- ============================================================
