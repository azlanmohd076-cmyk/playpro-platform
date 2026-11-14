-- P0 hotfix: remove anonymous access to private profile records.
-- Production applied: 2026-11-13 04:47:47 UTC
-- Scope is intentionally limited to public.profiles read access.

BEGIN;

REVOKE SELECT ON TABLE public.profiles FROM anon;

DROP POLICY IF EXISTS "profiles: public read" ON public.profiles;

CREATE POLICY "profiles: read own or developer"
ON public.profiles
FOR SELECT
TO authenticated
USING (
  id = (SELECT auth.uid())
  OR (SELECT public.get_my_role()) = 'developer'::public.user_role
);

COMMIT;
