-- Repair the authenticated player/profile link and backfill role-profile rows.
-- DNA/assessment values remain NULL; no synthetic football ratings are created.

INSERT INTO public.profile_role_profiles (profile_id, role_code, subject_id, is_active)
SELECT p.profile_id, 'player', p.id, true
FROM public.players p
LEFT JOIN public.profile_role_profiles r
  ON r.profile_id = p.profile_id
 AND r.role_code = 'player'
WHERE r.id IS NULL;

INSERT INTO public.players (
  id, profile_id, full_name, preferred_name, date_of_birth,
  preferred_foot, position, height_cm, weight_kg, nationality,
  jersey_number, is_active, profile_visibility, verification_status,
  display_name_mode, profile_completed_at
)
SELECT
  gen_random_uuid(),
  'd9aa74be-f1e7-4046-91a5-bf9c4024aed7'::uuid,
  'Azlan Mohd',
  'Azlan',
  '1976-09-27'::date,
  'right',
  'midfielder',
  170,
  68,
  'Malaysian',
  8,
  true,
  'public',
  'unverified',
  'preferred',
  now()
WHERE NOT EXISTS (
  SELECT 1 FROM public.players
  WHERE profile_id = 'd9aa74be-f1e7-4046-91a5-bf9c4024aed7'::uuid
);

INSERT INTO public.profile_role_profiles (profile_id, role_code, subject_id, is_active)
SELECT p.profile_id, 'player', p.id, true
FROM public.players p
WHERE p.profile_id = 'd9aa74be-f1e7-4046-91a5-bf9c4024aed7'::uuid
  AND NOT EXISTS (
    SELECT 1 FROM public.profile_role_profiles r
    WHERE r.profile_id = p.profile_id AND r.role_code = 'player'
  );

INSERT INTO public.player_attribute_state (player_id, source, confidence)
SELECT p.id, 'none', 0
FROM public.players p
WHERE p.profile_id = 'd9aa74be-f1e7-4046-91a5-bf9c4024aed7'::uuid
  AND NOT EXISTS (
    SELECT 1 FROM public.player_attribute_state s WHERE s.player_id = p.id
  );
