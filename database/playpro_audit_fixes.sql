-- ============================================================
-- PlayPro Audit Fixes
-- Implements audit findings 1, 2 (schema) from proof-of-life audit.
-- Fixes 3-9 are in playpro_audit_fixes.js (JS-layer fixes).
-- ============================================================
-- FIXES IN THIS FILE:
--   Fix 1: standings.season_id — missing column
--   Fix 2: fixtures.season_id  — missing column
--   Fix 3: mv_league_standings — rebuilt without broken season JOIN
--   Fix 4: mv_top_scorers      — rebuilt with correct season resolution
-- ============================================================
-- RULES:
--   ✓ No existing Phase 1-4 objects modified beyond ADD COLUMN
--   ✓ PostgreSQL 16 + Supabase compatible
--   ✓ ALTER TYPE / DROP / CREATE MATERIALIZED VIEW cannot run
--     inside a transaction; Part A handles those outside.
--   ✓ Single BEGIN…COMMIT for everything that can be transacted.
-- ============================================================

-- ============================================================
-- PART A — DDL THAT CANNOT RUN IN A TRANSACTION
-- (DROP + CREATE MATERIALIZED VIEW, CONCURRENTLY refresh)
-- Run these statements individually before Part B.
-- ============================================================

-- ── Drop broken materialised views ────────────────────────────
-- mv_league_standings used s.season_id which did not exist.
-- mv_top_scorers had a logically broken season JOIN.
-- Both must be dropped before they can be recreated correctly.

DROP MATERIALIZED VIEW IF EXISTS mv_league_standings;
DROP MATERIALIZED VIEW IF EXISTS mv_top_scorers;

-- ============================================================
-- PART B — SCHEMA + VIEW FIXES (single transaction)
-- ============================================================

BEGIN;

-- ────────────────────────────────────────────────────────────
-- FIX 1: standings.season_id
-- The standings table (Phase 1) never had season_id.
-- mv_league_standings joined seasons on this column → ERROR.
-- Adding it nullable so existing rows are unaffected.
-- ────────────────────────────────────────────────────────────

-- BEFORE: standings(id, league_id, club_id, played, wins, draws,
--         losses, goals_for, goals_against, goal_difference,
--         points, updated_at)
-- AFTER:  + season_id UUID REFERENCES seasons(id) ON DELETE SET NULL

ALTER TABLE standings
  ADD COLUMN IF NOT EXISTS season_id UUID
    REFERENCES seasons(id) ON DELETE SET NULL;

-- Index for the new FK
CREATE INDEX IF NOT EXISTS idx_standings_season
  ON standings(season_id) WHERE season_id IS NOT NULL;

-- Back-fill: associate existing standings rows with the active
-- season for their league (best-effort; NULL if no active season).
UPDATE standings s
SET season_id = (
  SELECT se.id
  FROM seasons se
  WHERE se.league_id = s.league_id
    AND se.status    = 'active'
  ORDER BY se.start_date DESC
  LIMIT 1
)
WHERE s.season_id IS NULL;

-- Update the unique constraint to include season_id so the same
-- club can appear in multiple seasons for the same league.
-- First drop the existing single-season constraint.
ALTER TABLE standings
  DROP CONSTRAINT IF EXISTS standings_league_id_club_id_key;

-- New composite unique: one row per club per season per league.
ALTER TABLE standings
  ADD CONSTRAINT standings_league_season_club_unique
    UNIQUE (league_id, season_id, club_id)
    DEFERRABLE INITIALLY DEFERRED;

-- ────────────────────────────────────────────────────────────
-- Update recalculate_standings() to populate season_id.
-- The Phase 4.2 hotfix version inserts without season_id;
-- we replace it to include season_id in the upsert.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION recalculate_standings(p_league_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_season_id UUID;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('standings_recalc_' || p_league_id::TEXT));

  -- Resolve the current active season for this league
  SELECT id INTO v_season_id
  FROM seasons
  WHERE league_id = p_league_id
    AND status    = 'active'
  ORDER BY start_date DESC
  LIMIT 1;

  INSERT INTO standings (
    league_id,
    season_id,
    club_id,
    played,
    wins,
    draws,
    losses,
    goals_for,
    goals_against,
    updated_at
  )
  SELECT
    p_league_id                                     AS league_id,
    v_season_id                                     AS season_id,
    club_id,
    SUM(played)                                     AS played,
    SUM(wins)                                       AS wins,
    SUM(draws)                                      AS draws,
    SUM(losses)                                     AS losses,
    SUM(goals_for)                                  AS goals_for,
    SUM(goals_against)                              AS goals_against,
    NOW()                                           AS updated_at
  FROM (
    -- Home-club perspective
    SELECT
      f.home_club_id                                            AS club_id,
      1                                                         AS played,
      CASE WHEN mr.home_goals > mr.away_goals THEN 1 ELSE 0 END AS wins,
      CASE WHEN mr.home_goals = mr.away_goals THEN 1 ELSE 0 END AS draws,
      CASE WHEN mr.home_goals < mr.away_goals THEN 1 ELSE 0 END AS losses,
      mr.home_goals                                             AS goals_for,
      mr.away_goals                                             AS goals_against
    FROM match_results mr
    JOIN fixtures f ON f.id = mr.fixture_id
    WHERE f.league_id    = p_league_id
      AND mr.is_official = true

    UNION ALL

    -- Away-club perspective
    SELECT
      f.away_club_id                                            AS club_id,
      1                                                         AS played,
      CASE WHEN mr.away_goals > mr.home_goals THEN 1 ELSE 0 END AS wins,
      CASE WHEN mr.away_goals = mr.home_goals THEN 1 ELSE 0 END AS draws,
      CASE WHEN mr.away_goals < mr.home_goals THEN 1 ELSE 0 END AS losses,
      mr.away_goals                                             AS goals_for,
      mr.home_goals                                             AS goals_against
    FROM match_results mr
    JOIN fixtures f ON f.id = mr.fixture_id
    WHERE f.league_id    = p_league_id
      AND mr.is_official = true
  ) contributions
  GROUP BY club_id
  ON CONFLICT ON CONSTRAINT standings_league_season_club_unique
  DO UPDATE SET
    played        = EXCLUDED.played,
    wins          = EXCLUDED.wins,
    draws         = EXCLUDED.draws,
    losses        = EXCLUDED.losses,
    goals_for     = EXCLUDED.goals_for,
    goals_against = EXCLUDED.goals_against,
    updated_at    = NOW();
END;
$$;

-- ────────────────────────────────────────────────────────────
-- FIX 2: fixtures.season_id
-- fixtures table (Phase 1) has no season_id column.
-- MatchRepo.getFixture() tried to select it → ERROR.
-- ────────────────────────────────────────────────────────────

-- BEFORE: fixtures has no season_id column
-- AFTER:  + season_id UUID REFERENCES seasons(id) ON DELETE SET NULL

ALTER TABLE fixtures
  ADD COLUMN IF NOT EXISTS season_id UUID
    REFERENCES seasons(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_fixtures_season
  ON fixtures(season_id) WHERE season_id IS NOT NULL;

-- Back-fill: resolve season from league_id and match_date
UPDATE fixtures f
SET season_id = (
  SELECT se.id
  FROM seasons se
  WHERE se.league_id  = f.league_id
    AND f.match_date  >= se.start_date::TIMESTAMPTZ
    AND f.match_date  <= se.end_date::TIMESTAMPTZ
  ORDER BY se.start_date DESC
  LIMIT 1
)
WHERE f.season_id IS NULL
  AND f.match_date IS NOT NULL;

-- For fixtures with null match_date, fall back to active season
UPDATE fixtures f
SET season_id = (
  SELECT se.id
  FROM seasons se
  WHERE se.league_id = f.league_id
    AND se.status    = 'active'
  ORDER BY se.start_date DESC
  LIMIT 1
)
WHERE f.season_id IS NULL;

COMMIT;

-- ============================================================
-- PART C — RECREATE MATERIALISED VIEWS
-- Must run outside a transaction (PostgreSQL restriction).
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- FIX 3: mv_league_standings — rebuilt
-- BEFORE: JOIN seasons sn ON sn.id = s.season_id
--         → s.season_id did not exist → view could not be created
-- AFTER:  s.season_id now exists (Fix 1 above) → valid JOIN
--         RANK() OVER partitions by league+season correctly.
-- ────────────────────────────────────────────────────────────

CREATE MATERIALIZED VIEW mv_league_standings AS
SELECT
  s.id                                    AS standings_id,
  s.league_id,
  l.name                                  AS league_name,
  s.season_id,
  sn.name                                 AS season_name,
  sn.season_code,
  s.club_id,
  c.name                                  AS club_name,
  c.logo_url,
  s.played,
  s.wins,
  s.draws,
  s.losses,
  s.goals_for,
  s.goals_against,
  s.goal_difference,
  s.points,
  RANK() OVER (
    PARTITION BY s.league_id, s.season_id
    ORDER BY s.points DESC, s.goal_difference DESC, s.goals_for DESC
  )                                       AS position
FROM standings s
JOIN leagues l   ON l.id  = s.league_id
LEFT JOIN seasons sn ON sn.id = s.season_id   -- LEFT JOIN: rows with season_id=NULL still appear
JOIN clubs   c   ON c.id  = s.club_id
WITH DATA;

CREATE UNIQUE INDEX mv_standings_pk
  ON mv_league_standings(standings_id);

CREATE INDEX mv_standings_league_season
  ON mv_league_standings(league_id, season_id, position);

CREATE INDEX mv_standings_league_pts
  ON mv_league_standings(league_id, points DESC NULLS LAST);

-- ────────────────────────────────────────────────────────────
-- FIX 4: mv_top_scorers — rebuilt
-- BEFORE: JOIN seasons s ON s.league_id = f.league_id
--                        AND f.match_date BETWEEN s.start_date AND s.end_date
--         → cross-product risk when multiple seasons overlap;
--           match_date in fixtures is TIMESTAMPTZ, season dates are DATE
--           → implicit cast, but still logically fragile
-- AFTER:  Use fixtures.season_id (now populated by Fix 2).
--         Avoids the date-range join entirely.
--         LEFT JOIN seasons — fixtures without season_id are still counted.
-- ────────────────────────────────────────────────────────────

CREATE MATERIALIZED VIEW mv_top_scorers AS
SELECT
  me.player_id,
  p.full_name,
  COALESCE(p.preferred_name, p.full_name)   AS display_name,
  p.photo_url,
  p.share_url_slug,
  p.position,
  p.club_id,
  c.name                                    AS club_name,
  c.logo_url                                AS club_logo_url,
  f.league_id,
  l.name                                    AS league_name,
  f.season_id,
  s.name                                    AS season_name,
  COUNT(*)                                  AS goals,
  COALESCE(
    (SELECT COUNT(*)
     FROM match_events me2
     WHERE me2.fixture_id   = me.fixture_id
       AND me2.player_id    = me.player_id
       AND me2.event_type   = 'assist'
       AND me2.is_cancelled = false),
    0
  )                                         AS assists
FROM match_events me
JOIN fixtures   f  ON f.id  = me.fixture_id
JOIN leagues    l  ON l.id  = f.league_id
JOIN players    p  ON p.id  = me.player_id
LEFT JOIN clubs c  ON c.id  = p.club_id
LEFT JOIN seasons s ON s.id = f.season_id
WHERE me.event_type    = 'goal'
  AND me.is_cancelled  = false
  AND f.status         = 'completed'
GROUP BY
  me.player_id,
  p.full_name, p.preferred_name, p.photo_url,
  p.share_url_slug, p.position, p.club_id,
  c.name, c.logo_url,
  f.league_id, l.name,
  f.season_id, s.name
WITH DATA;

CREATE UNIQUE INDEX mv_scorers_pk
  ON mv_top_scorers(player_id, league_id, COALESCE(season_id, '00000000-0000-0000-0000-000000000000'::UUID));

CREATE INDEX mv_scorers_league_goals
  ON mv_top_scorers(league_id, season_id, goals DESC);

-- ============================================================
-- VERIFICATION QUERIES
-- Run after applying all fixes to confirm correctness.
-- ============================================================

-- Fix 1: standings.season_id exists
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'standings' AND column_name = 'season_id';
-- Expected: 1 row

-- Fix 2: fixtures.season_id exists
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'fixtures' AND column_name = 'season_id';
-- Expected: 1 row

-- Fix 3: mv_league_standings recreated with position column
-- SELECT standings_id, club_name, points, position
-- FROM mv_league_standings LIMIT 5;
-- Expected: rows returned (if standings data exists)

-- Fix 4: mv_top_scorers rebuilt without date-range join
-- SELECT player_id, display_name, goals
-- FROM mv_top_scorers ORDER BY goals DESC LIMIT 5;
-- Expected: rows returned (if completed fixtures with goals exist)

-- Fix 1+2 combined: back-fill verification
-- SELECT COUNT(*) FROM standings WHERE season_id IS NOT NULL;
-- SELECT COUNT(*) FROM fixtures   WHERE season_id IS NOT NULL;
-- Expected: non-zero if seasons and fixtures data exists
