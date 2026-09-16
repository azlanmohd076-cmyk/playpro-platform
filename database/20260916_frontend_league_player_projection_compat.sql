-- PlayPro — frontend/live-schema compatibility repair
-- Applied to Supabase playpro2 on 2026-09-16.
-- Purpose: keep the existing frontend repository queries compatible with
-- denormalised league/player projection fields defined by the historical
-- Phase 6.5–6.8 model. Existing rows are untouched; all new fields are
-- nullable except follower counters which default to 0.

BEGIN;

ALTER TABLE public.leagues
  ADD COLUMN IF NOT EXISTS reputation_score SMALLINT
    CHECK (reputation_score IS NULL OR reputation_score BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS reputation_band TEXT,
  ADD COLUMN IF NOT EXISTS share_url_slug TEXT,
  ADD COLUMN IF NOT EXISTS follower_count INTEGER NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS idx_leagues_share_url_slug_compat
  ON public.leagues(share_url_slug) WHERE share_url_slug IS NOT NULL;

ALTER TABLE public.players
  ADD COLUMN IF NOT EXISTS dna_technical SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_physical SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_mental SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_tactical SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_goalkeeper SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_overall SMALLINT,
  ADD COLUMN IF NOT EXISTS dna_band TEXT,
  ADD COLUMN IF NOT EXISTS dna_computed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS potential_score SMALLINT
    CHECK (potential_score IS NULL OR potential_score BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS potential_category TEXT,
  ADD COLUMN IF NOT EXISTS passport_score SMALLINT,
  ADD COLUMN IF NOT EXISTS passport_band TEXT,
  ADD COLUMN IF NOT EXISTS passport_computed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS fitness_condition SMALLINT
    CHECK (fitness_condition IS NULL OR fitness_condition BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS match_sharpness SMALLINT
    CHECK (match_sharpness IS NULL OR match_sharpness BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS fatigue_level SMALLINT
    CHECK (fatigue_level IS NULL OR fatigue_level BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS training_load TEXT
    CHECK (training_load IN ('rest','light','normal','heavy','intense') OR training_load IS NULL),
  ADD COLUMN IF NOT EXISTS morale_score SMALLINT
    CHECK (morale_score IS NULL OR morale_score BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS morale_band TEXT
    CHECK (morale_band IN ('ecstatic','happy','content','unsettled','unhappy','miserable') OR morale_band IS NULL),
  ADD COLUMN IF NOT EXISTS injury_risk_level TEXT
    CHECK (injury_risk_level IN ('low','medium','high','very_high') OR injury_risk_level IS NULL),
  ADD COLUMN IF NOT EXISTS best_position TEXT,
  ADD COLUMN IF NOT EXISTS secondary_position TEXT,
  ADD COLUMN IF NOT EXISTS playing_role TEXT,
  ADD COLUMN IF NOT EXISTS development_trend TEXT
    CHECK (development_trend IN ('rapidly_improving','improving','stable','declining','rapidly_declining','insufficient_data') OR development_trend IS NULL),
  ADD COLUMN IF NOT EXISTS scout_recommendation TEXT
    CHECK (scout_recommendation IN ('strongly_recommended','recommended','monitor','development_prospect','not_recommended') OR scout_recommendation IS NULL),
  ADD COLUMN IF NOT EXISTS projected_peak_dna SMALLINT
    CHECK (projected_peak_dna IS NULL OR projected_peak_dna BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS projected_peak_age SMALLINT
    CHECK (projected_peak_age IS NULL OR projected_peak_age BETWEEN 14 AND 45),
  ADD COLUMN IF NOT EXISTS development_phase TEXT
    CHECK (development_phase IN ('emerging','developing','peak','declining','veteran') OR development_phase IS NULL),
  ADD COLUMN IF NOT EXISTS market_value_myr NUMERIC(14,2),
  ADD COLUMN IF NOT EXISTS reputation_score SMALLINT
    CHECK (reputation_score IS NULL OR reputation_score BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS reputation_band TEXT,
  ADD COLUMN IF NOT EXISTS follower_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS pipeline_last_run TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS idx_players_share_url_slug_compat
  ON public.players(share_url_slug) WHERE share_url_slug IS NOT NULL;

COMMIT;

-- PostgREST schema cache refresh is intentionally separate from the DDL
-- migration and is performed by the deployment operator when required:
-- NOTIFY pgrst, 'reload schema';
