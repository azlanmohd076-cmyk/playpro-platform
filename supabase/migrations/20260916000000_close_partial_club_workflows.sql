-- Close safe, non-business-choice gaps in the Club partial workflow.
-- 1) Platform fee is a PlayPro business invariant: 5.00%, never club-configurable.
-- 2) Training sessions get owner/coach controlled CRUD/read RPCs.
-- 3) Official ratified match results project into Club History; TMR is never used as history.

UPDATE public.club_membership_settings SET platform_fee_percent = 5.00, updated_at = now()
WHERE platform_fee_percent IS DISTINCT FROM 5.00;

ALTER TABLE public.club_membership_settings DROP CONSTRAINT IF EXISTS club_fee_platform_pct_chk;
ALTER TABLE public.club_membership_settings ADD CONSTRAINT club_fee_platform_pct_chk CHECK (platform_fee_percent = 5.00);

CREATE OR REPLACE FUNCTION public.playpro_save_club_fee_settings(p_club_id uuid,p_enabled boolean,p_fee numeric,p_cycle text,p_description text DEFAULT NULL,p_instructions text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
 IF v_uid IS NULL OR NOT public.playpro_is_club_manager(p_club_id) THEN RAISE EXCEPTION 'Hanya owner/admin kelab boleh mengurus yuran.' USING ERRCODE='42501'; END IF;
 IF p_fee < 0 THEN RAISE EXCEPTION 'Yuran tidak boleh negatif.' USING ERRCODE='22023'; END IF;
 IF p_cycle NOT IN ('one_time','monthly','quarterly','annual','custom') THEN RAISE EXCEPTION 'Kitaran yuran tidak sah.' USING ERRCODE='22023'; END IF;
 INSERT INTO public.club_membership_settings(club_id,fee_collection_enabled,player_registration_fee,currency,billing_cycle,fee_description,platform_fee_percent,payment_instructions,updated_by)
 VALUES(p_club_id,coalesce(p_enabled,false),p_fee,'MYR',p_cycle,p_description,5.00,p_instructions,v_uid)
 ON CONFLICT(club_id) DO UPDATE SET fee_collection_enabled=excluded.fee_collection_enabled,player_registration_fee=excluded.player_registration_fee,billing_cycle=excluded.billing_cycle,fee_description=excluded.fee_description,payment_instructions=excluded.payment_instructions,platform_fee_percent=5.00,updated_by=excluded.updated_by,updated_at=now();
 RETURN jsonb_build_object('success',true,'club_id',p_club_id,'enabled',p_enabled,'fee',p_fee,'platform_fee_percent',5.00);
END; $function$;

CREATE OR REPLACE FUNCTION public.playpro_prepare_membership_payment(p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_uid uuid := auth.uid(); v_req public.club_membership_requests%ROWTYPE; v_fee numeric(12,2); v_pay uuid;
BEGIN
 SELECT * INTO v_req FROM public.club_membership_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND OR v_req.profile_id<>v_uid OR v_req.status<>'payment_pending' OR NOT v_req.payment_required THEN RAISE EXCEPTION 'Permintaan ini belum bersedia untuk bayaran.' USING ERRCODE='42501'; END IF;
 SELECT player_registration_fee INTO v_fee FROM public.club_membership_settings WHERE club_id=v_req.club_id; v_fee:=coalesce(v_fee,0);
 SELECT id INTO v_pay FROM public.club_membership_payments WHERE request_id=p_request_id;
 IF v_pay IS NULL THEN
  INSERT INTO public.club_membership_payments(request_id,club_id,payer_profile_id,gross_amount,platform_fee_amount,club_net_amount,currency,status)
  VALUES(p_request_id,v_req.club_id,v_uid,v_fee,round(v_fee*0.05,2),round(v_fee-(v_fee*0.05),2),'MYR','pending') RETURNING id INTO v_pay;
 ELSE
  UPDATE public.club_membership_payments SET gross_amount=v_fee,platform_fee_amount=round(v_fee*0.05,2),club_net_amount=round(v_fee-(v_fee*0.05),2),updated_at=now() WHERE id=v_pay AND status='pending';
 END IF;
 RETURN jsonb_build_object('success',true,'payment_id',v_pay,'gross_amount',v_fee,'platform_fee_amount',round(v_fee*0.05,2),'club_net_amount',round(v_fee-(v_fee*0.05),2),'currency','MYR','status','pending');
END; $function$;

CREATE OR REPLACE FUNCTION public.playpro_create_training_session(p_team_id uuid,p_title text,p_session_type text,p_starts_at timestamptz,p_ends_at timestamptz DEFAULT NULL,p_venue_id uuid DEFAULT NULL,p_coach_profile_id uuid DEFAULT NULL,p_notes text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_uid uuid:=auth.uid(); v_club_id uuid; v_id uuid;
BEGIN
 SELECT club_id INTO v_club_id FROM public.club_teams WHERE id=p_team_id;
 IF v_uid IS NULL OR v_club_id IS NULL OR NOT public.playpro_is_club_manager(v_club_id) THEN RAISE EXCEPTION 'Akses latihan tidak dibenarkan.' USING ERRCODE='42501'; END IF;
 IF nullif(trim(p_title),'') IS NULL OR p_starts_at IS NULL THEN RAISE EXCEPTION 'Tajuk dan masa latihan diperlukan.' USING ERRCODE='22023'; END IF;
 IF p_ends_at IS NOT NULL AND p_ends_at < p_starts_at THEN RAISE EXCEPTION 'Masa tamat tidak boleh sebelum masa mula.' USING ERRCODE='22023'; END IF;
 IF p_venue_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.club_training_venues v WHERE v.id=p_venue_id AND v.club_id=v_club_id) THEN RAISE EXCEPTION 'Venue bukan milik kelab ini.' USING ERRCODE='22023'; END IF;
 INSERT INTO public.team_training_sessions(team_id,coach_profile_id,venue_id,title,session_type,starts_at,ends_at,notes,status,created_by)
 VALUES(p_team_id,p_coach_profile_id,p_venue_id,trim(p_title),coalesce(nullif(trim(p_session_type),''),'training'),p_starts_at,p_ends_at,p_notes,'scheduled',v_uid) RETURNING id INTO v_id;
 RETURN jsonb_build_object('success',true,'session_id',v_id);
END; $function$;

CREATE OR REPLACE FUNCTION public.playpro_list_team_training_sessions(p_team_id uuid,p_limit integer DEFAULT 50) RETURNS SETOF public.team_training_sessions
LANGUAGE sql SECURITY DEFINER SET search_path TO '' AS $function$
 SELECT s.* FROM public.team_training_sessions s JOIN public.club_teams t ON t.id=s.team_id
 WHERE s.team_id=p_team_id AND auth.uid() IS NOT NULL AND public.playpro_is_club_manager(t.club_id)
 ORDER BY s.starts_at DESC LIMIT LEAST(GREATEST(coalesce(p_limit,50),1),200);
$function$;

CREATE OR REPLACE FUNCTION public.playpro_update_training_session(p_session_id uuid,p_title text,p_session_type text,p_starts_at timestamptz,p_ends_at timestamptz DEFAULT NULL,p_venue_id uuid DEFAULT NULL,p_coach_profile_id uuid DEFAULT NULL,p_notes text DEFAULT NULL,p_status text DEFAULT 'scheduled') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_uid uuid:=auth.uid(); v_club_id uuid;
BEGIN
 SELECT t.club_id INTO v_club_id FROM public.team_training_sessions s JOIN public.club_teams t ON t.id=s.team_id WHERE s.id=p_session_id;
 IF v_uid IS NULL OR v_club_id IS NULL OR NOT public.playpro_is_club_manager(v_club_id) THEN RAISE EXCEPTION 'Akses latihan tidak dibenarkan.' USING ERRCODE='42501'; END IF;
 IF p_status NOT IN ('scheduled','completed','cancelled') THEN RAISE EXCEPTION 'Status latihan tidak sah.' USING ERRCODE='22023'; END IF;
 UPDATE public.team_training_sessions SET title=trim(p_title),session_type=coalesce(nullif(trim(p_session_type),''),'training'),starts_at=p_starts_at,ends_at=p_ends_at,venue_id=p_venue_id,coach_profile_id=p_coach_profile_id,notes=p_notes,status=p_status,updated_at=now() WHERE id=p_session_id;
 RETURN jsonb_build_object('success',true,'session_id',p_session_id);
END; $function$;

CREATE OR REPLACE FUNCTION public.playpro_project_official_match_to_club_history() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE f public.fixtures%ROWTYPE; l public.leagues%ROWTYPE; home_name text; away_name text; v_title text; v_result text;
BEGIN
 IF NEW.is_official IS NOT TRUE OR NEW.ratified_at IS NULL THEN RETURN NEW; END IF;
 SELECT * INTO f FROM public.fixtures WHERE id=NEW.fixture_id; IF NOT FOUND THEN RETURN NEW; END IF;
 SELECT * INTO l FROM public.leagues WHERE id=f.league_id;
 SELECT name INTO home_name FROM public.clubs WHERE id=f.home_club_id; SELECT name INTO away_name FROM public.clubs WHERE id=f.away_club_id;
 v_title:=coalesce(home_name,'Home')||' vs '||coalesce(away_name,'Away'); v_result:=NEW.home_goals::text||'–'||NEW.away_goals::text;
 INSERT INTO public.club_history_records(club_id,record_type,title,competition_name,season,result_text,event_date,source_fixture_id,created_by)
 VALUES
 (f.home_club_id,'official_match',v_title,coalesce(l.name,'Competition'),l.season,CASE WHEN NEW.home_goals>NEW.away_goals THEN 'MENANG '||v_result WHEN NEW.home_goals<NEW.away_goals THEN 'KALAH '||v_result ELSE 'SERI '||v_result END,coalesce(f.match_date::date,current_date),f.id,NEW.ratified_by),
 (f.away_club_id,'official_match',v_title,coalesce(l.name,'Competition'),l.season,CASE WHEN NEW.away_goals>NEW.home_goals THEN 'MENANG '||v_result WHEN NEW.away_goals<NEW.home_goals THEN 'KALAH '||v_result ELSE 'SERI '||v_result END,coalesce(f.match_date::date,current_date),f.id,NEW.ratified_by)
 ON CONFLICT DO NOTHING;
 RETURN NEW;
END; $function$;

CREATE UNIQUE INDEX IF NOT EXISTS club_history_official_match_uq ON public.club_history_records(club_id,record_type,source_fixture_id) WHERE record_type='official_match' AND source_fixture_id IS NOT NULL;
DROP TRIGGER IF EXISTS trg_playpro_project_official_match_history ON public.match_results;
CREATE TRIGGER trg_playpro_project_official_match_history AFTER INSERT OR UPDATE OF is_official,ratified_at,ratified_by,home_goals,away_goals ON public.match_results FOR EACH ROW EXECUTE FUNCTION public.playpro_project_official_match_to_club_history();

REVOKE ALL ON FUNCTION public.playpro_create_training_session(uuid,text,text,timestamptz,timestamptz,uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.playpro_update_training_session(uuid,text,text,timestamptz,timestamptz,uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.playpro_list_team_training_sessions(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.playpro_create_training_session(uuid,text,text,timestamptz,timestamptz,uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.playpro_update_training_session(uuid,text,text,timestamptz,timestamptz,uuid,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.playpro_list_team_training_sessions(uuid,integer) TO authenticated;
