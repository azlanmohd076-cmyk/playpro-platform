-- ============================================================
-- PlayPro Model 6: Demo Coach Passport Seed Data
-- Safe seed for 5 realistic coach profiles.
--
-- IMPORTANT:
-- profiles.id references auth.users(id). This script only inserts/updates
-- profiles for IDs that already exist in auth.users. It will not create
-- Supabase Auth users.
-- ============================================================

CREATE TEMP TABLE tmp_model6_demo_coaches (
  id UUID PRIMARY KEY,
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  license_type TEXT NOT NULL,
  status TEXT NOT NULL,
  max_attribute_score INT NOT NULL,
  exam_attempts_count INT NOT NULL,
  last_exam_at TIMESTAMPTZ,
  wallet_balance NUMERIC(14,2) NOT NULL,
  metadata JSONB NOT NULL
) ON COMMIT DROP;

INSERT INTO tmp_model6_demo_coaches VALUES
('9b1deb4d-3b7d-419a-9e23-f3900693a1c1','Syukri Nor','syukri.coach.demo@playpro.local','Grassroots','pending',5,0,NULL,0.00,
 '{"age":29,"experience_years":1,"coach_attributes":{"judging_ability":5,"judging_potential":5,"tactical_knowledge":5,"coaching_outfield":5,"coaching_goalkeepers":5,"technical_coaching":5,"attacking_coaching":5,"defending_coaching":5,"fitness_coaching":5,"set_piece_coaching":5,"man_management":5,"motivating":5,"discipline_management":5,"physiotherapy":5,"sports_science":5,"working_with_youngsters":5,"adaptability":5,"determination":5,"data_analysis":5,"communication":5,"coaching_style":5}}'::jsonb),
('a18cd29f-124b-47bf-8f81-da9e120dcf55','Zainal Abidin bin Mat','zainal.coach.demo@playpro.local','FAM C License','pending',5,3,NOW() - INTERVAL '2 hours',0.00,
 '{"age":42,"experience_years":5,"last_mock_exam_status":"COOLDOWN_ACTIVE","coach_attributes":{"judging_ability":5,"judging_potential":5,"tactical_knowledge":11,"coaching_outfield":14,"coaching_goalkeepers":8,"technical_coaching":14,"attacking_coaching":12,"defending_coaching":13,"fitness_coaching":10,"set_piece_coaching":9,"man_management":10,"motivating":12,"discipline_management":11,"physiotherapy":8,"sports_science":8,"working_with_youngsters":14,"adaptability":9,"determination":10,"data_analysis":8,"communication":11,"coaching_style":10}}'::jsonb),
('e82f3411-cf01-49b4-bdf7-f104d48a1299','Khairul Azhar','khairul.coach.demo@playpro.local','FAM C License + Sports Science Level 1','active',20,1,NOW() - INTERVAL '1 day',125.00,
 '{"age":34,"experience_years":3,"last_mock_exam_status":"PASSED","last_mock_exam_error_margin":1.2,"coach_attributes":{"judging_ability":15,"judging_potential":14,"tactical_knowledge":13,"coaching_outfield":14,"coaching_goalkeepers":10,"technical_coaching":14,"attacking_coaching":12,"defending_coaching":11,"fitness_coaching":13,"set_piece_coaching":12,"man_management":12,"motivating":14,"discipline_management":13,"physiotherapy":14,"sports_science":14,"working_with_youngsters":15,"adaptability":11,"determination":15,"data_analysis":12,"communication":13,"coaching_style":13}}'::jsonb),
('334cc81d-ef12-4011-aa90-bdf1920cd777','Aris Zainal','aris.coach.demo@playpro.local','AFC B License + Sports Science Diploma','active',20,1,NOW() - INTERVAL '5 days',1625.00,
 '{"age":48,"experience_years":12,"last_mock_exam_status":"PASSED","last_mock_exam_error_margin":0.4,"coach_attributes":{"judging_ability":19,"judging_potential":18,"tactical_knowledge":17,"coaching_outfield":17,"coaching_goalkeepers":13,"technical_coaching":17,"attacking_coaching":18,"defending_coaching":17,"fitness_coaching":18,"set_piece_coaching":16,"man_management":17,"motivating":18,"discipline_management":19,"physiotherapy":20,"sports_science":20,"working_with_youngsters":16,"adaptability":16,"determination":18,"data_analysis":17,"communication":18,"coaching_style":17}}'::jsonb),
('771bc29a-dfbb-411a-8812-cc90e210111d','Mazlan Idrose','mazlan.coach.demo@playpro.local','FAM C + GK Level 1','active',20,1,NOW() - INTERVAL '2 days',375.00,
 '{"age":39,"experience_years":7,"specialty":"GK Data","last_mock_exam_status":"PASSED","last_mock_exam_error_margin":1.1,"coach_attributes":{"judging_ability":16,"judging_potential":15,"tactical_knowledge":12,"coaching_outfield":8,"coaching_goalkeepers":18,"technical_coaching":13,"attacking_coaching":9,"defending_coaching":11,"fitness_coaching":13,"set_piece_coaching":16,"man_management":11,"motivating":14,"discipline_management":15,"physiotherapy":12,"sports_science":12,"working_with_youngsters":16,"adaptability":12,"determination":14,"data_analysis":13,"communication":14,"coaching_style":13}}'::jsonb);

-- Insert/update profiles only when matching auth.users exist.
INSERT INTO public.profiles (id, full_name, email, role, updated_at)
SELECT s.id, s.full_name, s.email, 'coach'::user_role, NOW()
FROM tmp_model6_demo_coaches s
WHERE EXISTS (SELECT 1 FROM auth.users au WHERE au.id = s.id)
ON CONFLICT (id) DO UPDATE
SET full_name = EXCLUDED.full_name,
    role = 'coach'::user_role,
    updated_at = NOW();

-- Insert/update certified assessor state for profiles that exist.
INSERT INTO public.certified_assessors (
  profile_id,
  license_type,
  status,
  max_attribute_score,
  exam_attempts_count,
  last_exam_at,
  metadata,
  updated_at
)
SELECT
  s.id,
  s.license_type,
  s.status,
  s.max_attribute_score,
  s.exam_attempts_count,
  s.last_exam_at,
  s.metadata,
  NOW()
FROM tmp_model6_demo_coaches s
WHERE EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = s.id)
ON CONFLICT (profile_id) DO UPDATE
SET license_type = EXCLUDED.license_type,
    status = EXCLUDED.status,
    max_attribute_score = EXCLUDED.max_attribute_score,
    exam_attempts_count = EXCLUDED.exam_attempts_count,
    last_exam_at = EXCLUDED.last_exam_at,
    metadata = EXCLUDED.metadata,
    updated_at = NOW();

-- Seed agent wallets using Model 6 table agent_wallets, not legacy wallets.
INSERT INTO public.agent_wallets (
  profile_id,
  wallet_code,
  status,
  currency,
  available_balance,
  pending_balance,
  lifetime_earned,
  lifetime_paid_out,
  metadata,
  updated_at
)
SELECT
  s.id,
  'WAL-DEMO-' || replace(s.id::text, '-', ''),
  'active'::wallet_status,
  'MYR',
  s.wallet_balance,
  0.00,
  s.wallet_balance,
  0.00,
  jsonb_build_object('seed', 'model6_demo_coaches'),
  NOW()
FROM tmp_model6_demo_coaches s
WHERE EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = s.id)
ON CONFLICT (wallet_code) DO UPDATE
SET available_balance = EXCLUDED.available_balance,
    lifetime_earned = EXCLUDED.lifetime_earned,
    updated_at = NOW();

-- Result summary.
SELECT
  (SELECT COUNT(*) FROM public.profiles p JOIN tmp_model6_demo_coaches s ON s.id = p.id) AS seeded_profiles,
  (SELECT COUNT(*) FROM public.certified_assessors ca JOIN tmp_model6_demo_coaches s ON s.id = ca.profile_id) AS seeded_assessors,
  (SELECT COUNT(*) FROM public.agent_wallets aw JOIN tmp_model6_demo_coaches s ON s.id = aw.profile_id) AS seeded_wallets;
