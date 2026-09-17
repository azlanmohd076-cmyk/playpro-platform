BEGIN;

-- Fix 403 on the canonical player attribute state endpoint.
-- RLS already contains the correct owner predicate; the missing piece in
-- production was the table-level SELECT grant for authenticated users.
GRANT SELECT ON TABLE public.player_attribute_state TO authenticated;

DROP POLICY IF EXISTS "player attribute owner read" ON public.player_attribute_state;
CREATE POLICY "player attribute owner read"
ON public.player_attribute_state
FOR SELECT
TO authenticated
USING (
  player_id IN (
    SELECT p.id
    FROM public.players p
    WHERE p.profile_id = (SELECT auth.uid())
  )
);

-- Legacy root UI still probes player_club_history. The canonical source is
-- club_memberships; expose a read-only, auth-scoped compatibility projection
-- so the legacy request no longer produces a 404 while the newer Club History
-- surface continues to read club_history_records.
CREATE OR REPLACE VIEW public.player_club_history
WITH (security_invoker = true)
AS
SELECT
  cm.profile_id,
  cm.club_id,
  cm.joined_at,
  cm.left_at,
  cm.status,
  c.name AS club_name
FROM public.club_memberships cm
JOIN public.clubs c ON c.id = cm.club_id
WHERE cm.profile_id = (SELECT auth.uid());

GRANT SELECT ON public.player_club_history TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
