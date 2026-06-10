-- ============================================================
-- PlayPro Sprint 1 — Identity Foundation Patch
-- ============================================================
-- Applies on top of playpro_phase6_5_dna_migration.sql
-- Revises attribute_definitions seed to 18 attributes (V1)
-- Adds missing materialized views for public leaderboards
-- ============================================================

-- PART A: ENUM additions (outside transaction)
-- (already added in phase 6.5, these are idempotent)

-- PART B: main patch
BEGIN;

-- ── 1. Revise attribute seed to 18 attributes (V1) ───────────
-- Delete the 10 attributes not in V1 scope:
-- crossing, acceleration, jumping, concentration, teamwork,
-- determination, off_the_ball, reflexes, handling, one_on_one, communication
-- Keep: passing, dribbling, finishing, first_touch, tackling, heading,
--        pace, stamina, strength, agility,
--        leadership, composure, teamwork, work_rate,
--        positioning, vision, decision_making, anticipation

DELETE FROM attribute_definitions
WHERE code IN (
  'crossing','acceleration','jumping',
  'concentration','determination',
  'off_the_ball',
  'reflexes','handling','one_on_one','communication'
);

-- Rebalance weights so they sum to 1.0000 within each category

-- TECHNICAL (6): passing dribbling finishing first_touch tackling heading
UPDATE attribute_definitions SET weight_in_category = 0.1667 WHERE code IN
  ('passing','dribbling','finishing','first_touch','tackling','heading');

-- PHYSICAL (4): pace stamina strength agility
UPDATE attribute_definitions SET weight_in_category = 0.2500 WHERE code IN
  ('pace','stamina','strength','agility');

-- MENTAL (4): leadership composure teamwork work_rate
UPDATE attribute_definitions SET weight_in_category = 0.2500 WHERE code IN
  ('leadership','composure','teamwork','work_rate');

-- TACTICAL (4): positioning vision decision_making anticipation
UPDATE attribute_definitions SET weight_in_category = 0.2500 WHERE code IN
  ('positioning','vision','decision_making','anticipation');

-- ── 2. Remove goalkeeper category from position_dna_weights ──
-- V1 has no goalkeeper-specific attributes; set gk weight to 0
UPDATE position_dna_weights SET
  weight_goalkeeper = 0.000,
  weight_tactical   = weight_tactical + weight_goalkeeper
WHERE position_code = 'gk';

-- ── 3. Materialised views for public leaderboards ─────────────

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_league_standings AS
SELECT
  s.id                                  AS standings_id,
  s.league_id,
  l.name                                AS league_name,
  s.season_id,
  sn.name                               AS season_name,
  s.club_id,
  c.name                                AS club_name,
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
  )                                     AS position
FROM standings s
JOIN leagues l   ON l.id = s.league_id
JOIN seasons sn  ON sn.id = s.season_id
JOIN clubs   c   ON c.id = s.club_id
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_standings_pk
  ON mv_league_standings(standings_id);
CREATE INDEX IF NOT EXISTS mv_standings_league_season
  ON mv_league_standings(league_id, season_id, position);

-- ── Top scorers materialized view ────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_top_scorers AS
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
  s.id                                      AS season_id,
  s.name                                    AS season_name,
  COUNT(*)                                  AS goals,
  COUNT(CASE WHEN me2.event_type = 'assist' THEN 1 END) AS assists
FROM match_events me
JOIN fixtures   f  ON f.id  = me.fixture_id
JOIN leagues    l  ON l.id  = f.league_id
JOIN seasons    s  ON s.league_id = f.league_id
                   AND f.match_date BETWEEN s.start_date AND s.end_date
JOIN players    p  ON p.id  = me.player_id
LEFT JOIN clubs c  ON c.id  = p.club_id
LEFT JOIN match_events me2
  ON me2.fixture_id  = me.fixture_id
  AND me2.player_id  = me.player_id
  AND me2.event_type = 'assist'
  AND me2.is_cancelled = false
WHERE me.event_type    = 'goal'
  AND me.is_cancelled  = false
  AND f.status         = 'completed'
GROUP BY
  me.player_id, p.full_name, p.preferred_name, p.photo_url,
  p.share_url_slug, p.position, p.club_id, c.name, c.logo_url,
  f.league_id, l.name, s.id, s.name
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_scorers_pk
  ON mv_top_scorers(player_id, league_id, season_id);
CREATE INDEX IF NOT EXISTS mv_scorers_goals
  ON mv_top_scorers(league_id, season_id, goals DESC);

-- ── Club DNA materialized view ────────────────────────────────
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_club_dna AS
SELECT
  c.id                      AS club_id,
  c.name                    AS club_name,
  c.logo_url,
  c.share_url_slug,
  c.dna_technical,
  c.dna_physical,
  c.dna_mental,
  c.dna_tactical,
  c.dna_overall,
  c.club_passport_score,
  c.club_passport_band,
  c.dna_computed_at,
  COUNT(DISTINCT p.id)      AS squad_size,
  COUNT(DISTINCT CASE WHEN p.dna_overall IS NOT NULL THEN p.id END) AS assessed_count
FROM clubs c
LEFT JOIN players p ON p.club_id = c.id AND p.is_active = true
GROUP BY
  c.id, c.name, c.logo_url, c.share_url_slug,
  c.dna_technical, c.dna_physical, c.dna_mental, c.dna_tactical,
  c.dna_overall, c.club_passport_score, c.club_passport_band, c.dna_computed_at
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS mv_club_dna_pk
  ON mv_club_dna(club_id);
CREATE INDEX IF NOT EXISTS mv_club_dna_score
  ON mv_club_dna(club_passport_score DESC NULLS LAST);

-- ── 4. Refresh all materialized views function ────────────────
CREATE OR REPLACE FUNCTION refresh_all_public_views()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_league_standings;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_top_scorers;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_club_dna;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_player_passport_scores;
$$;

GRANT EXECUTE ON FUNCTION refresh_all_public_views() TO authenticated;

COMMIT;
