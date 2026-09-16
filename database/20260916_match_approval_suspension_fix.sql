-- PlayPro production repair: referee is the formal match approval gate; red-card suspension is rule-config driven.
-- Applied in production before/alongside this source-of-truth record.

create or replace function public.finalize_match(p_fixture_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_referee_profile_id uuid; v_result_exists boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select ra.profile_id into v_referee_profile_id
  from public.referee_assignments ra join public.fixtures f on f.id=ra.fixture_id
  where ra.fixture_id=p_fixture_id and ra.role='referee'::public.fixture_official_role
    and ra.status in ('assigned','accepted','active') and f.match_state='ended'
  order by ra.assigned_at desc limit 1;
  if v_referee_profile_id is null then raise exception 'Match must be ENDED and have an active appointed referee before approval'; end if;
  if v_referee_profile_id<>auth.uid() then raise exception 'Only the appointed referee can approve/finalize this match' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='referee'::public.user_role) then raise exception 'Authenticated approver must have referee role' using errcode='42501'; end if;
  select exists(select 1 from public.match_results mr where mr.fixture_id=p_fixture_id) into v_result_exists;
  if not v_result_exists then raise exception 'MATCH REPORT/result is required before referee approval'; end if;
  update public.match_results set is_official=true,ratified_by=auth.uid(),ratified_at=now(),entered_by=coalesce(entered_by,auth.uid()),updated_at=now() where fixture_id=p_fixture_id and is_official=false;
  if not found and not exists(select 1 from public.match_results where fixture_id=p_fixture_id and is_official=true and ratified_by=auth.uid()) then raise exception 'Match result is already official and was ratified by another authority'; end if;
  update public.fixtures set match_state='finalized',updated_at=now() where id=p_fixture_id and match_state='ended';
  if not found then raise exception 'Match finalization failed because the fixture state changed'; end if;
  return true;
end; $$;

create or replace function public.auto_suspend_on_red_card()
returns trigger language plpgsql security definer set search_path='public','pg_temp'
as $$
declare v_matches integer; v_rule_config_id uuid; v_club_id uuid; v_home_club uuid; v_away_club uuid; v_player_club uuid; v_match_date timestamptz;
begin
  if new.card_type in ('red','second_yellow') then
    select f.home_club_id,f.away_club_id,f.match_date into v_home_club,v_away_club,v_match_date from public.fixtures f where f.id=new.fixture_id and f.league_id=new.league_id;
    if v_home_club is null or v_away_club is null then raise exception 'Cannot create suspension: fixture % is missing valid team context',new.fixture_id; end if;
    select c.id,case when new.card_type='red' then c.red_card_suspension_matches else c.second_yellow_suspension_matches end into v_rule_config_id,v_matches
    from public.competition_rule_config c where c.league_id=new.league_id and c.effective_from<=coalesce(v_match_date,now()) and (c.effective_to is null or c.effective_to>coalesce(v_match_date,now())) order by c.version desc,c.effective_from desc limit 1;
    if v_rule_config_id is null or v_matches is null then raise exception 'No competition suspension rule configuration exists for league %',new.league_id; end if;
    select mp.club_id into v_club_id from public.match_participants mp where mp.fixture_id=new.fixture_id and mp.player_id=new.player_id and mp.club_id in(v_home_club,v_away_club) order by mp.created_at desc limit 1;
    if v_club_id is null then select p.club_id into v_player_club from public.players p where p.id=new.player_id; if v_player_club in(v_home_club,v_away_club) then v_club_id:=v_player_club; end if; end if;
    if v_club_id is null then raise exception 'Cannot create suspension: player % has no valid team context for fixture %',new.player_id,new.fixture_id; end if;
    insert into public.suspensions(player_id,league_id,club_id,rule_config_id,suspension_reason,matches_suspended,matches_served,matches_remaining,served_fixture_ids,start_fixture_id,reason_notes,is_active,imposed_by)
    values(new.player_id,new.league_id,v_club_id,v_rule_config_id,'automatic_red_card',v_matches,0,v_matches,'{}'::uuid[],new.fixture_id,case when new.card_type='second_yellow' then 'Automatic suspension for second-yellow dismissal on '||new.match_date::text else 'Automatic suspension for red card on '||new.match_date::text end,true,new.created_by)
    on conflict(player_id,league_id,start_fixture_id,suspension_reason) where start_fixture_id is not null do nothing;
  end if;
  return new;
end; $$;
