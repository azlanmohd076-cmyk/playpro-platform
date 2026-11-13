-- PLAYPRO — PLAYER PROFILE GOVERNANCE (DRAFT ONLY)
-- 2026-11-13
-- DO NOT APPLY until Phase 2C production baseline/reconciliation is complete.
--
-- Findings confirmed against live production:
-- 1. player_assessments currently has permissive public SELECT and an
--    authenticated INSERT policy with WITH CHECK (true).
-- 2. get_player_match_history is SECURITY DEFINER and EXECUTE is granted to
--    anon/authenticated, but the current function does not enforce the target
--    player's profile_visibility. The profile page hides the tab for a private
--    profile, but a direct RPC call bypasses that frontend check.
-- 3. player_profile reads player_attribute_state, while player_assessments
--    uses a different attribute set. No trigger/function was found that syncs
--    assessments into player_attribute_state. Do not invent a mapping:
--    reconcile the canonical 18-attribute model before writing the sync job.

BEGIN;

-- ---------------------------------------------------------------------------
-- A. Restrict raw assessment records to the player owner, assigned assessor,
--    or developer. Public profile consumers should receive only the approved
--    aggregate returned by get_player_profile, not raw assessor submissions.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Membenarkan bacaan penilaian" ON public.player_assessments;
DROP POLICY IF EXISTS "player_assessments: public read" ON public.player_assessments;
DROP POLICY IF EXISTS "Membenarkan technical_assessor membuat penilaian" ON public.player_assessments;

CREATE POLICY "player_assessments: owner assessor developer read"
ON public.player_assessments
FOR SELECT
TO authenticated
USING (
  assessor_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1 FROM public.players p
    WHERE p.id = player_assessments.player_id
      AND p.profile_id = (SELECT auth.uid())
  )
  OR public.get_my_role() = 'developer'::public.user_role
);

CREATE POLICY "player_assessments: accredited assessor insert"
ON public.player_assessments
FOR INSERT
TO authenticated
WITH CHECK (
  public.get_my_role() = ANY (
    ARRAY['technical_assessor'::public.user_role,'developer'::public.user_role]
  )
  AND assessor_id = (SELECT auth.uid())
);

-- Keep the existing UPDATE policy only after confirming its WITH CHECK behavior
-- in the Phase 2C baseline. Do not add DELETE rights to assessor accounts.

-- ---------------------------------------------------------------------------
-- B. Enforce the same profile visibility rule for direct match-history RPC
--    calls as the player profile page.
--    Public profile: visible to anyone.
--    Private profile: owner and approved followers only.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_player_match_history(
  p_player_id uuid,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_owner uuid;
  v_visibility text;
BEGIN
  SELECT p.profile_id, p.profile_visibility
  INTO v_owner, v_visibility
  FROM public.players p
  WHERE p.id = p_player_id
    AND p.is_active = true;

  IF NOT FOUND THEN
    RETURN '[]'::jsonb;
  END IF;

  IF v_visibility <> 'public'
     AND v_uid IS DISTINCT FROM v_owner
     AND NOT EXISTS (
       SELECT 1
       FROM public.player_follows pf
       WHERE pf.player_id = p_player_id
         AND pf.follower_profile_id = v_uid
         AND pf.status = 'approved'
     )
  THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN (
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.match_date DESC),'[]'::jsonb)
    FROM (
      SELECT
        f.id AS fixture_id,
        f.match_date,
        f.round_name,
        f.home_club_id,
        f.away_club_id,
        hc.name AS home_club,
        ac.name AS away_club,
        mr.home_goals,
        mr.away_goals,
        pms.minutes_played,
        pms.goals,
        pms.assists,
        pms.yellow_cards,
        pms.red_cards,
        pms.started
      FROM public.player_match_stats pms
      JOIN public.fixtures f ON f.id = pms.fixture_id
      JOIN public.match_results mr
        ON mr.fixture_id = f.id
       AND mr.is_official = true
      LEFT JOIN public.clubs hc ON hc.id = f.home_club_id
      LEFT JOIN public.clubs ac ON ac.id = f.away_club_id
      WHERE pms.player_id = p_player_id
      ORDER BY f.match_date DESC NULLS LAST
      LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),200)
    ) x
  );
END;
$function$;

COMMIT;

-- ---------------------------------------------------------------------------
-- C. Mandatory follow-up before this module can be marked complete:
--    1. Canonical Player DNA v1 is exactly 18 outfield attributes:
--       passing, dribbling, finishing, first_touch, tackling, heading,
--       pace, stamina, strength, agility, leadership, composure, teamwork,
--       work_rate, positioning, vision, decision_making, anticipation.
--       The canonical v1 model has NO separate GK DNA attributes. GK card
--       face stats must be selected from these 18; do not invent new columns.
--    2. Live player_assessments is a legacy 19-field evidence table:
--       passing, crossing, tackling, finishing, dribbling, first_touch,
--       leadership, teamwork, determination, decisions, positioning, pace,
--       strength, agility, balance, stamina, gk_handling, gk_reflexes,
--       gk_positioning. No safe one-to-one mapping exists for all 18 canonical
--       DNA fields. Do not assume decisions=decision_making or map other fields.
--    3. Live player_assessments has a 1–20 CHECK constraint, while the current
--       technical_assessor.html form advertises 1–100; its history query asks
--       for created_at although the live table exposes assessed_at. Fix the
--       assessor workflow only after its canonical storage contract is chosen.
--    4. The assessor UI currently queries public.players directly, but the
--       live players SELECT policy is owner-only. Add a role-checked, minimal
--       assessor directory RPC; do not grant broad player-table SELECT.
--    5. Decide the canonical assessment schema and the aggregation rule for
--       multiple assessors (e.g. median/mean/latest with confidence) with Owner
--       approval. Only then create a controlled sync into player_attribute_state.
--    6. Add a safe follower-request projection for the profile owner so pending
--       requests can be identified and approved/rejected without exposing
--       private profiles or unrestricted profiles rows.
--    7. Enforce profile_visibility inside get_player_match_history itself;
--       frontend tab hiding is not a security boundary.
--    8. Test owner/public/private/approved-follower/anonymous access and ensure
--       raw assessment rows are never publicly readable or writable.
--
-- Live counts checked 2026-11-13 on playpro2: players=5,
-- player_attribute_state=5 (all source='none', confidence=0, no rated values),
-- player_assessments=0, player_match_stats=0, player_posts=0, player_follows=0.
-- No production DDL has been applied for these follow-up items.
-- ---------------------------------------------------------------------------
