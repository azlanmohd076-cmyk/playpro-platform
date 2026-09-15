CREATE UNIQUE INDEX IF NOT EXISTS club_history_official_match_uq
ON public.club_history_records(club_id, record_type, source_fixture_id)
WHERE record_type='official_match' AND source_fixture_id IS NOT NULL;
