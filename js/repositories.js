/**
 * PlayPro — Data Repositories
 * Every database query is defined here.
 * All dashboards import from this file only — no raw SB calls in HTML.
 *
 * Depends on: supabase.js (SB, Auth, _handle, _cacheGet, _cacheSet)
 *
 * Normalisation convention:
 *   DB snake_case  →  JS camelCase via _norm()
 *   All dates come back as ISO strings; format in UI layer.
 */

'use strict';

/* ─────────────────────────────────────────────────────────────
   Utility: snake → camel normaliser
───────────────────────────────────────────────────────────── */
function _toCamel(s) {
  return s.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
}
function _norm(obj) {
  if (!obj || typeof obj !== 'object') return obj;
  if (Array.isArray(obj)) return obj.map(_norm);
  return Object.fromEntries(
    Object.entries(obj).map(([k, v]) => [_toCamel(k), _norm(v)])
  );
}

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Auth / User
───────────────────────────────────────────────────────────── */
const UserRepo = {

  /** Full profile for the current authenticated user. */
  async me() {
    return Auth.profile();
  },

  /**
   * For coach/club_admin: resolve which club this user manages.
   * Returns club_id or null.
   */
  async myClubId() {
    const profile = await Auth.profile();
    if (!profile) return null;
    if (profile.role === 'club_admin') {
      const { data } = await SB
        .from('clubs')
        .select('id')
        .eq('admin_id', profile.id)
        .single();
      return data?.id ?? null;
    }
    if (profile.role === 'coach') {
      const { data } = await SB
        .from('coaches')
        .select('club_id')
        .eq('profile_id', profile.id)
        .eq('is_active', true)
        .single();
      return data?.club_id ?? null;
    }
    return null;
  },

  /** Returns the player record linked to the current user (claimed player). */
  async myPlayerId() {
    const { data } = await SB.rpc('get_my_player_id');
    return data ?? null;
  },

  /** Returns all player_ids this user is guardian of. */
  async myWardIds() {
    const uid = await Auth.uid();
    if (!uid) return [];
    const { data } = await SB
      .from('player_guardians')
      .select('player_id')
      .eq('guardian_profile_id', uid)
      .eq('is_active', true)
      .eq('consent_given', true);
    return (data ?? []).map(r => r.player_id);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Players
───────────────────────────────────────────────────────────── */
const PlayerRepo = {

  /**
   * All players for a given club with full development data.
   * Used by coach + club dashboards.
   */
  async byClub(clubId) {
    const cacheKey = 'players:club:' + clubId;
    const hit = _cacheGet(cacheKey);
    if (hit) return hit;

    const { data, error } = await SB
      .from('players')
      .select(`
        id, full_name, preferred_name, position, jersey_number, date_of_birth,
        nationality, height_cm, photo_url, share_url_slug, is_active,
        club_id,
        dna_overall, dna_band, dna_technical, dna_physical, dna_mental, dna_tactical,
        dna_goalkeeper, dna_computed_at,
        potential_score, potential_category,
        passport_score, passport_band, passport_computed_at,
        fitness_condition, match_sharpness, fatigue_level, training_load,
        morale_score, morale_band,
        injury_risk_level,
        best_position, secondary_position, playing_role,
        development_trend, scout_recommendation,
        projected_peak_dna, projected_peak_age, development_phase,
        market_value_myr, reputation_score, reputation_band,
        follower_count, pipeline_last_run
      `)
      .eq('club_id', clubId)
      .eq('is_active', true)
      .order('dna_overall', { ascending: false });

    if (error) { console.error('[PlayerRepo.byClub]', error.message); return []; }
    const result = _norm(data ?? []);
    _cacheSet(cacheKey, result);
    return result;
  },

  /**
   * Single player — full passport view.
   * Reads from v_player_passport_full (public view, RLS-gated).
   */
  async passport(playerId) {
    const { data, error } = await SB
      .from('v_player_passport_full')
      .select('*')
      .eq('id', playerId)
      .single();
    if (error) { console.error('[PlayerRepo.passport]', error.message); return null; }
    return _norm(data);
  },

  /**
   * Public DNA view — for passport pages & public search.
   */
  async dnaPublic(playerId) {
    const { data, error } = await SB
      .from('v_player_dna_public')
      .select('*')
      .eq('player_id', playerId)
      .single();
    if (error) { console.error('[PlayerRepo.dnaPublic]', error.message); return null; }
    return _norm(data);
  },

  /**
   * Development passport view — fitness, morale, projections, trends.
   */
  async development(playerId) {
    const { data, error } = await SB
      .from('v_player_development_passport')
      .select('*')
      .eq('player_id', playerId)
      .single();
    if (error) { console.error('[PlayerRepo.development]', error.message); return null; }
    return _norm(data);
  },

  /**
   * All 18 attributes for a player.
   */
  async attributes(playerId) {
    const { data, error } = await SB
      .from('player_attributes')
      .select(`
        attribute_code, current_value, coach_value, officer_value, ai_value,
        confidence_level, last_assessed_at, is_public
      `)
      .eq('player_id', playerId);
    if (error) { console.error('[PlayerRepo.attributes]', error.message); return []; }
    // Convert to a keyed object {code: {currentValue, coachValue, ...}}
    const map = {};
    for (const row of _norm(data ?? [])) {
      map[row.attributeCode] = row;
    }
    return map;
  },

  /**
   * Attribute history for progression charts.
   * Returns [{attributeCode, value, recordedAt, delta, triggerSource}]
   */
  async attributeHistory(playerId, attrCode = null, limit = 30) {
    let q = SB
      .from('player_attribute_history')
      .select('attribute_code, value, previous_value, delta, recorded_at, trigger_source, season_id')
      .eq('player_id', playerId)
      .order('recorded_at', { ascending: false })
      .limit(limit);
    if (attrCode) q = q.eq('attribute_code', attrCode);
    const { data, error } = await q;
    if (error) { console.error('[PlayerRepo.attributeHistory]', error.message); return []; }
    return _norm(data ?? []);
  },

  /**
   * Passport score history — for trend charts.
   */
  async passportHistory(playerId, limit = 12) {
    const { data, error } = await SB
      .from('player_passport_score_history')
      .select(`
        computed_date, passport_score, passport_band,
        match_performance_score, attribute_dna_score, discipline_score,
        activity_score, development_score, raw_score, league_quality_scalar
      `)
      .eq('player_id', playerId)
      .order('computed_date', { ascending: false })
      .limit(limit);
    if (error) { console.error('[PlayerRepo.passportHistory]', error.message); return []; }
    return _norm(data ?? []).reverse();   // oldest-first for charting
  },

  /**
   * Season statistics from player_match_stats.
   */
  async seasonStats(playerId, seasonId = null) {
    let q = SB
      .from('player_match_stats')
      .select(`
        goals, assists, shots, shots_on_target, yellow_cards, red_cards,
        saves, minutes_played, started, match_rating,
        passes_completed, passes_attempted, pass_accuracy,
        tackles_won, tackles_attempted, tackle_success_rate,
        fixtures!inner(match_date, status, league_id)
      `)
      .eq('player_id', playerId)
      .eq('fixtures.status', 'completed')
      .order('fixtures(match_date)', { ascending: false })
      .limit(50);

    const { data, error } = await q;
    if (error) { console.error('[PlayerRepo.seasonStats]', error.message); return null; }

    const rows = data ?? [];
    if (!rows.length) return { apps: 0, goals: 0, assists: 0, yellows: 0, reds: 0, ratingAvg: null };

    const sum = (f) => rows.reduce((a, r) => a + (r[f] || 0), 0);
    const ratings = rows.map(r => r.match_rating).filter(Boolean);

    return {
      apps:       rows.length,
      goals:      sum('goals'),
      assists:    sum('assists'),
      shots:      sum('shots'),
      shotsOnTarget: sum('shots_on_target'),
      yellows:    sum('yellow_cards'),
      reds:       sum('red_cards'),
      saves:      sum('saves'),
      minutesPlayed: sum('minutes_played'),
      starts:     rows.filter(r => r.started).length,
      ratingAvg:  ratings.length
        ? Math.round(ratings.reduce((a,b) => a+b, 0) / ratings.length * 10) / 10
        : null,
      passAccuracyAvg: rows.filter(r=>r.pass_accuracy).length
        ? Math.round(rows.reduce((a,r)=>a+(r.pass_accuracy||0),0)/rows.filter(r=>r.pass_accuracy).length)
        : null,
    };
  },

  /**
   * Current development projection.
   */
  async projection(playerId) {
    const { data, error } = await SB
      .from('player_development_projections')
      .select('*')
      .eq('player_id', playerId)
      .order('computed_date', { ascending: false })
      .limit(1)
      .single();
    if (error) { console.error('[PlayerRepo.projection]', error.message); return null; }
    return _norm(data);
  },

  /**
   * Current fitness snapshot.
   */
  async fitness(playerId) {
    const { data, error } = await SB
      .from('player_fitness_snapshots')
      .select('*')
      .eq('player_id', playerId)
      .order('snapshot_date', { ascending: false })
      .limit(1)
      .single();
    if (error) { return null; }
    return _norm(data);
  },

  /**
   * Current morale snapshot.
   */
  async morale(playerId) {
    const { data, error } = await SB
      .from('player_morale_snapshots')
      .select('*')
      .eq('player_id', playerId)
      .order('snapshot_date', { ascending: false })
      .limit(1)
      .single();
    if (error) { return null; }
    return _norm(data);
  },

  /**
   * Hidden attributes (restricted — coach/club_admin only).
   */
  async hidden(playerId) {
    const { data, error } = await SB
      .from('player_hidden_attributes')
      .select('professionalism, ambition, loyalty, temperament, consistency, injury_proneness, pressure_handling, confidence')
      .eq('player_id', playerId)
      .single();
    if (error) { return null; }
    return _norm(data);
  },

  /**
   * Position familiarity.
   */
  async positionFamiliarity(playerId) {
    const { data, error } = await SB
      .from('player_position_familiarity')
      .select('position_code, position_label, familiarity, familiarity_pct, matches_in_pos, is_natural')
      .eq('player_id', playerId)
      .order('familiarity_pct', { ascending: false });
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /**
   * Injury risk profile.
   */
  async injuryRisk(playerId) {
    const { data, error } = await SB
      .from('player_injury_risk_profiles')
      .select('*')
      .eq('player_id', playerId)
      .single();
    if (error) { return null; }
    return _norm(data);
  },

  /**
   * Weekly training score for a player.
   */
  async weeklyTrainingScore(playerId) {
    const { data, error } = await SB.rpc('compute_weekly_training_score', {
      p_player_id: playerId,
      p_week_start: _mondayOfThisWeek(),
    });
    if (error) { console.error('[PlayerRepo.weeklyTrainingScore]', error.message); return 0; }
    return data ?? 0;
  },

  /**
   * Similar players (pre-computed).
   */
  async similar(playerId) {
    const { data, error } = await SB
      .from('player_similarities')
      .select(`
        similar_player_id, similarity_score,
        players!player_similarities_similar_player_id_fkey(
          id, full_name, preferred_name, position, dna_overall, dna_band,
          playing_role, club_id, photo_url, share_url_slug
        )
      `)
      .eq('player_id', playerId)
      .order('similarity_score', { ascending: false })
      .limit(5);
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /**
   * Training attendance history for a player (last N sessions).
   */
  async trainingAttendance(playerId, limit = 8) {
    const { data, error } = await SB
      .from('player_training_attendance')
      .select(`
        status, minutes_trained, created_at,
        training_sessions(session_date, focus_category, intensity, duration_minutes)
      `)
      .eq('player_id', playerId)
      .order('created_at', { ascending: false })
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Clubs
───────────────────────────────────────────────────────────── */
const ClubRepo = {

  /** Single club with all metadata. */
  async get(clubId) {
    const cacheKey = 'club:' + clubId;
    const hit = _cacheGet(cacheKey);
    if (hit) return hit;

    const { data, error } = await SB
      .from('clubs')
      .select(`
        id, name, logo_url, year_founded, home_venue, colours, away_colours,
        description, website_url, contact_email, founding_story,
        club_type, membership_open,
        dna_technical, dna_physical, dna_mental, dna_tactical, dna_overall,
        club_passport_score, club_passport_band, dna_computed_at,
        reputation_score, reputation_band,
        share_url_slug, follower_count, market_value_myr
      `)
      .eq('id', clubId)
      .single();

    if (error) { console.error('[ClubRepo.get]', error.message); return null; }
    const result = _norm(data);
    _cacheSet(cacheKey, result);
    return result;
  },

  /**
   * Club DNA summary from mv_club_dna materialised view.
   */
  async dna(clubId) {
    const { data, error } = await SB
      .from('mv_club_dna')
      .select('*')
      .eq('club_id', clubId)
      .single();
    if (error) { return null; }
    return _norm(data);
  },

  /**
   * Squad development report (gated view, auth required).
   */
  async squadDevelopment(clubId) {
    const { data, error } = await SB
      .from('v_squad_development_report')
      .select('*')
      .eq('club_id', clubId)
      .order('dna_overall', { ascending: false });
    if (error) { console.error('[ClubRepo.squadDevelopment]', error.message); return []; }
    return _norm(data ?? []);
  },

  /**
   * Recent notifications scoped to a club.
   * Uses notification_recipients joined to notifications.
   */
  async recentActivity(clubId, limit = 10) {
    // Fetch recent match events, training sessions, assessments for this club
    const { data, error } = await SB
      .from('notifications')
      .select(`
        id, notification_type, title, body, created_at, is_read,
        notification_recipients!inner(profile_id, is_read)
      `)
      .order('created_at', { ascending: false })
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /**
   * Upcoming training sessions for a club.
   */
  async upcomingSessions(clubId, limit = 5) {
    const { data, error } = await SB
      .from('training_sessions')
      .select('id, session_date, session_time, focus_category, intensity, duration_minutes, status')
      .eq('club_id', clubId)
      .gte('session_date', new Date().toISOString().slice(0, 10))
      .order('session_date', { ascending: true })
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /**
   * Market values for all squad players.
   */
  async marketValues(clubId) {
    const { data, error } = await SB
      .from('player_market_values')
      .select(`
        player_id, value_myr, computed_at, method,
        players!inner(full_name, preferred_name, position, jersey_number, dna_overall, dna_band, playing_role, club_id)
      `)
      .eq('is_current', true)
      .eq('players.club_id', clubId)
      .order('value_myr', { ascending: false });
    if (error) { return []; }
    return _norm(data ?? []);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Leagues
───────────────────────────────────────────────────────────── */
const LeagueRepo = {

  /** All active leagues. */
  async all(statusFilter = null) {
    let q = SB
      .from('leagues')
      .select(`
        id, name, logo_url, description, season, status, founder_id,
        share_url_slug, follower_count, reputation_score, reputation_band,
        quality_tier_id,
        league_quality_tiers(name, code, scalar)
      `)
      .order('follower_count', { ascending: false });
    if (statusFilter) q = q.eq('status', statusFilter);
    const { data, error } = await q;
    if (error) { console.error('[LeagueRepo.all]', error.message); return []; }
    return _norm(data ?? []);
  },

  /** Single league detail. */
  async get(leagueId) {
    const { data, error } = await SB
      .from('leagues')
      .select(`
        id, name, logo_url, description, season, status,
        share_url_slug, follower_count, reputation_score, reputation_band,
        quality_tier_id,
        league_quality_tiers(name, code, scalar),
        league_clubs(count)
      `)
      .eq('id', leagueId)
      .single();
    if (error) { return null; }
    return _norm(data);
  },

  /**
   * Standings from mv_league_standings materialised view.
   */
  async standings(leagueId, seasonId = null) {
    let q = SB
      .from('mv_league_standings')
      .select('*')
      .eq('league_id', leagueId)
      .order('position', { ascending: true });
    if (seasonId) q = q.eq('season_id', seasonId);
    const { data, error } = await q;
    if (error) {
      // Fallback to live standings table if matview not yet populated
      const { data: liveData, error: liveErr } = await SB
        .from('standings')
        .select(`
          id, league_id, season_id, club_id,
          played, wins, draws, losses, goals_for, goals_against,
          goal_difference, points,
          clubs(name, logo_url)
        `)
        .eq('league_id', leagueId)
        .order('points', { ascending: false });
      if (liveErr) { return []; }
      return _norm(liveData ?? []);
    }
    return _norm(data ?? []);
  },

  /** Top scorers from mv_top_scorers materialised view. */
  async topScorers(leagueId, limit = 10) {
    const { data, error } = await SB
      .from('mv_top_scorers')
      .select('*')
      .eq('league_id', leagueId)
      .order('goals', { ascending: false })
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Fixtures
───────────────────────────────────────────────────────────── */
const FixtureRepo = {

  /** Fixtures for a league, optionally filtered by status. */
  async byLeague(leagueId, statusFilter = null, limit = 20) {
    let q = SB
      .from('fixtures')
      .select(`
        id, league_id, match_date, status, venue,
        home_club_id, away_club_id,
        home_club:clubs!fixtures_home_club_id_fkey(id, name, logo_url),
        away_club:clubs!fixtures_away_club_id_fkey(id, name, logo_url),
        match_results(home_goals, away_goals)
      `)
      .eq('league_id', leagueId)
      .order('match_date', { ascending: false })
      .limit(limit);
    if (statusFilter) q = q.eq('status', statusFilter);
    const { data, error } = await q;
    if (error) { console.error('[FixtureRepo.byLeague]', error.message); return []; }
    return _norm(data ?? []);
  },

  /** Fixtures for a club (home or away). */
  async byClub(clubId, limit = 10) {
    const { data, error } = await SB
      .from('fixtures')
      .select(`
        id, league_id, match_date, status, venue,
        home_club_id, away_club_id,
        home_club:clubs!fixtures_home_club_id_fkey(id, name, logo_url),
        away_club:clubs!fixtures_away_club_id_fkey(id, name, logo_url),
        match_results(home_goals, away_goals)
      `)
      .or(`home_club_id.eq.${clubId},away_club_id.eq.${clubId}`)
      .order('match_date', { ascending: false })
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /** Next upcoming fixture for a club. */
  async nextForClub(clubId) {
    const { data, error } = await SB
      .from('fixtures')
      .select(`
        id, match_date, status, venue,
        home_club:clubs!fixtures_home_club_id_fkey(id, name),
        away_club:clubs!fixtures_away_club_id_fkey(id, name)
      `)
      .or(`home_club_id.eq.${clubId},away_club_id.eq.${clubId}`)
      .eq('status', 'scheduled')
      .gte('match_date', new Date().toISOString().slice(0, 10))
      .order('match_date', { ascending: true })
      .limit(1)
      .single();
    if (error) { return null; }
    return _norm(data);
  },

  /** Last N match results for a club (for form strip). */
  async lastResults(clubId, limit = 5) {
    const { data, error } = await SB
      .from('fixtures')
      .select(`
        id, home_club_id, away_club_id, match_date,
        match_results(home_goals, away_goals)
      `)
      .or(`home_club_id.eq.${clubId},away_club_id.eq.${clubId}`)
      .eq('status', 'completed')
      .not('match_results', 'is', null)
      .order('match_date', { ascending: false })
      .limit(limit);
    if (error) { return []; }
    const rows = _norm(data ?? []);
    return rows.map(f => {
      const r = f.matchResults;
      if (!r) return 'U';
      const isHome = f.homeClubId === clubId;
      const scored   = isHome ? r.homeGoals   : r.awayGoals;
      const conceded = isHome ? r.awayGoals   : r.homeGoals;
      return scored > conceded ? 'W' : scored < conceded ? 'L' : 'D';
    }).reverse();
  },

  /**
   * Live fixture events for a given fixture_id.
   * Used by the Match Observer to load existing events.
   */
  async events(fixtureId) {
    const { data, error } = await SB
      .from('match_events')
      .select(`
        id, event_type, minute, added_time, period,
        player_id, secondary_player_id, club_id,
        home_score_at_event, away_score_at_event, is_cancelled, notes
      `)
      .eq('fixture_id', fixtureId)
      .eq('is_cancelled', false)
      .order('period').order('minute').order('added_time');
    if (error) { return []; }
    return _norm(data ?? []);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Passport
───────────────────────────────────────────────────────────── */
const PassportRepo = {

  /**
   * Passport leaderboard — from mv_player_passport_scores.
   */
  async leaderboard(filters = {}, limit = 50) {
    const { position, leagueId, bandFilter, potentialMin } = filters;
    let q = SB
      .from('mv_player_passport_scores')
      .select('*')
      .order('dna_overall', { ascending: false })
      .limit(limit);
    if (position)    q = q.eq('position', position);
    if (leagueId)    q = q.eq('league_id', leagueId);
    if (bandFilter)  q = q.eq('dna_band', bandFilter);
    if (potentialMin) q = q.gte('potential_score', potentialMin);
    const { data, error } = await q;
    if (error) { console.error('[PassportRepo.leaderboard]', error.message); return []; }
    return _norm(data ?? []);
  },

  /**
   * Wonderkid radar — players flagged as wonderkids.
   */
  async wonderkids(limit = 10) {
    const { data, error } = await SB
      .from('v_wonderkid_radar')
      .select('*')
      .order('wonderkid_score', { ascending: false })
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /**
   * Development leaderboard.
   */
  async developmentLeaderboard(limit = 20) {
    const { data, error } = await SB
      .from('v_development_leaderboard')
      .select('*')
      .order('improvement_headroom_pct', { ascending: false })
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: DNA / Attributes
───────────────────────────────────────────────────────────── */
const DnaRepo = {

  /**
   * All attribute definitions (reference table — cached indefinitely).
   */
  async definitions() {
    const hit = _cacheGet('attr-defs');
    if (hit) return hit;
    const { data, error } = await SB
      .from('attribute_definitions')
      .select('code, label, category, display_order, description, weight_in_category, is_active')
      .eq('is_active', true)
      .order('category').order('display_order');
    if (error) { return []; }
    const result = _norm(data ?? []);
    // Cache for session lifetime (attrs don't change)
    _cacheSet('attr-defs', result);
    return result;
  },

  /**
   * Attribute progression (for SVG line charts).
   * Returns [{attributeCode, value, recordedAt}] sorted oldest-first.
   */
  async progression(playerId, attrCodes = [], limit = 20) {
    let q = SB
      .from('player_attribute_history')
      .select('attribute_code, value, recorded_at, delta, trigger_source')
      .eq('player_id', playerId)
      .order('recorded_at', { ascending: true })
      .limit(limit);
    if (attrCodes.length) q = q.in('attribute_code', attrCodes);
    const { data, error } = await q;
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /**
   * Club DNA from mv_club_dna.
   */
  async clubDna(clubId) {
    return ClubRepo.dna(clubId);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Development
───────────────────────────────────────────────────────────── */
const DevRepo = {

  /** Squad development report (full, for club dashboard). */
  async squadReport(clubId) {
    return ClubRepo.squadDevelopment(clubId);
  },

  /** Fitness history (line chart data). */
  async fitnessHistory(playerId, days = 30) {
    const since = new Date(Date.now() - days * 864e5).toISOString().slice(0, 10);
    const { data, error } = await SB
      .from('player_fitness_snapshots')
      .select('snapshot_date, match_sharpness, fatigue_level, condition, training_load')
      .eq('player_id', playerId)
      .gte('snapshot_date', since)
      .order('snapshot_date', { ascending: true });
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /** Training performance history for sparklines. */
  async trainingHistory(playerId, weeks = 8) {
    const since = new Date(Date.now() - weeks * 7 * 864e5).toISOString().slice(0, 10);
    const { data, error } = await SB
      .from('player_training_performance')
      .select(`
        rating, effort_rating, created_at,
        training_sessions(session_date, focus_category, intensity)
      `)
      .eq('player_id', playerId)
      .gte('training_sessions.session_date', since)
      .order('created_at', { ascending: true });
    if (error) { return []; }
    return _norm(data ?? []);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Market Value
───────────────────────────────────────────────────────────── */
const MarketValueRepo = {

  /** Current market values for public display. */
  async public(filters = {}, limit = 50) {
    let q = SB
      .from('v_player_market_values_public')
      .select('*')
      .order('value_myr', { ascending: false })
      .limit(limit);
    if (filters.clubId)   q = q.eq('club_id', filters.clubId);
    if (filters.position) q = q.eq('position', filters.position);
    const { data, error } = await q;
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /** Market value history for a player (chart). */
  async history(playerId, limit = 12) {
    const { data, error } = await SB
      .from('market_value_history')
      .select('recorded_date, value_myr, method')
      .eq('player_id', playerId)
      .order('recorded_date', { ascending: true })
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Notifications
───────────────────────────────────────────────────────────── */
const NotifRepo = {

  /** Unread notification count for current user. */
  async unreadCount() {
    const uid = await Auth.uid();
    if (!uid) return 0;
    const { count, error } = await SB
      .from('notification_recipients')
      .select('id', { count: 'exact', head: true })
      .eq('profile_id', uid)
      .eq('is_read', false);
    return error ? 0 : (count ?? 0);
  },

  /** Recent notifications for current user. */
  async recent(limit = 20) {
    const uid = await Auth.uid();
    if (!uid) return [];
    const { data, error } = await SB
      .from('notification_recipients')
      .select(`
        id, is_read, received_at,
        notifications(
          id, notification_type, title, body, created_at
        )
      `)
      .eq('profile_id', uid)
      .order('received_at', { ascending: false })
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /** Mark a notification as read. */
  async markRead(recipientId) {
    const { error } = await SB
      .from('notification_recipients')
      .update({ is_read: true, read_at: new Date().toISOString() })
      .eq('id', recipientId);
    return !error;
  },

  /** Mark all notifications as read for current user. */
  async markAllRead() {
    const uid = await Auth.uid();
    if (!uid) return false;
    const { error } = await SB
      .from('notification_recipients')
      .update({ is_read: true })
      .eq('profile_id', uid)
      .eq('is_read', false);
    return !error;
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Scout Search
───────────────────────────────────────────────────────────── */
const ScoutRepo = {

  /**
   * Advanced player search using search_players() RPC.
   * All params are optional — omit to get full passport leaderboard.
   */
  async search(params = {}) {
    const {
      query, position, ageMin, ageMax,
      dnaMin, dnaMax, potentialMin,
      leagueId, clubId, leagueTier, nationality, passportMin,
      attrPassing, attrPace, attrFinishing, attrVision,
      attrTackling, attrStrength, attrComposure, attrWorkRate,
      sortBy = 'dna_overall', sortDir = 'DESC',
      limit = 50, offset = 0,
    } = params;

    const rpcParams = {
      p_query:           query        ?? null,
      p_position:        position     ?? null,
      p_age_min:         ageMin       ?? null,
      p_age_max:         ageMax       ?? null,
      p_dna_min:         dnaMin       ?? null,
      p_dna_max:         dnaMax       ?? null,
      p_potential_min:   potentialMin ?? null,
      p_league_id:       leagueId     ?? null,
      p_club_id:         clubId       ?? null,
      p_league_tier:     leagueTier   ?? null,
      p_nationality:     nationality  ?? null,
      p_passport_min:    passportMin  ?? null,
      p_attr_passing:    attrPassing  ?? null,
      p_attr_pace:       attrPace     ?? null,
      p_attr_finishing:  attrFinishing ?? null,
      p_attr_vision:     attrVision   ?? null,
      p_attr_tackling:   attrTackling ?? null,
      p_attr_strength:   attrStrength ?? null,
      p_attr_composure:  attrComposure ?? null,
      p_attr_work_rate:  attrWorkRate ?? null,
      p_sort_by:         sortBy,
      p_sort_dir:        sortDir,
      p_limit:           limit,
      p_offset:          offset,
    };

    const { data, error } = await SB.rpc('search_players', rpcParams);
    if (error) { console.error('[ScoutRepo.search]', error.message); return { players: [], total: 0 }; }
    const rows = _norm(data ?? []);
    const total = rows[0]?.totalCount ?? rows.length;
    return { players: rows, total };
  },

  /** AI Scout report for a player. */
  async report(playerId) {
    const { data, error } = await SB
      .from('v_scout_reports_public')
      .select('*')
      .eq('player_id', playerId)
      .order('created_at', { ascending: false })
      .limit(1)
      .single();
    if (error) { return null; }
    return _norm(data);
  },

  /** Reputation leaderboard. */
  async reputationLeaderboard(entityType = 'player', limit = 20) {
    const { data, error } = await SB
      .from('v_reputation_leaderboard')
      .select('*')
      .eq('entity_type', entityType)
      .order('score', { ascending: false })
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: Match Observer
───────────────────────────────────────────────────────────── */
const MatchRepo = {

  /**
   * Save a batch of match events to the database.
   * Called by the Match Observer "Finalise" button.
   * events: [{type, playerId, clubId, minute, half, minute_added?}]
   */
  async saveEvents(fixtureId, events) {
    if (!events.length) return { ok: true };

    const rows = events
      .filter(e => e.playerId && e.type !== 'full_time_summary')
      .map(e => ({
        fixture_id:           fixtureId,
        event_type:           e.type,
        minute:               Math.max(1, e.minute || 1),
        added_time:           e.addedTime || 0,
        period:               e.half || 1,
        player_id:            e.playerId || null,
        secondary_player_id:  e.playerOffId || null,
        club_id:              e.clubId,
        home_score_at_event:  e.homeScore ?? 0,
        away_score_at_event:  e.awayScore ?? 0,
        is_cancelled:         false,
      }));

    const { error } = await SB.from('match_events').insert(rows);
    if (error) { console.error('[MatchRepo.saveEvents]', error.message); return { ok: false, error }; }
    return { ok: true };
  },

  /**
   * Upsert player_match_stats rows after a match.
   * Called before triggering the pipeline.
   */
  async savePlayerStats(fixtureId, statsMap, players) {
    // statsMap: {playerId: {goals, assists, sot, shots, pass_ok, pass_fail, ...}}
    const rows = Object.entries(statsMap).map(([pid, s]) => {
      const p = players.find(x => x.id === pid);
      return {
        fixture_id:          fixtureId,
        player_id:           pid,
        club_id:             p?.clubId || null,
        started:             s.role === 'starter',
        minutes_played:      s.minutes ?? 90,
        goals:               s.goals ?? 0,
        assists:             s.assists ?? 0,
        shots:               s.shots ?? 0,
        shots_on_target:     s.sot ?? 0,
        yellow_cards:        s.yellows ?? 0,
        red_cards:           s.reds ?? 0,
        saves:               s.saves ?? 0,
        passes_completed:    s.passOk ?? 0,
        passes_attempted:    (s.passOk ?? 0) + (s.passFail ?? 0),
        tackles_won:         s.tacklesWon ?? 0,
        tackles_attempted:   (s.tacklesWon ?? 0) + (s.tacklesLost ?? 0),
        interceptions:       s.interceptions ?? 0,
        match_rating:        s.rating ?? null,
        is_motm:             s.motm ?? false,
      };
    });

    const { error } = await SB
      .from('player_match_stats')
      .upsert(rows, { onConflict: 'fixture_id,player_id' });
    if (error) { console.error('[MatchRepo.savePlayerStats]', error.message); return { ok: false, error }; }
    return { ok: true };
  },

  /**
   * Mark fixture as 'completed' — this triggers the database trigger
   * trg_fixture_status_pipeline which calls run_post_match_pipeline().
   */
  async completeFixture(fixtureId) {
    const { error } = await SB
      .from('fixtures')
      .update({ status: 'completed', updated_at: new Date().toISOString() })
      .eq('id', fixtureId);
    if (error) { console.error('[MatchRepo.completeFixture]', error.message); return { ok: false, error }; }
    return { ok: true };
  },

  /**
   * Explicit pipeline call for cases where the trigger is not
   * sufficient (e.g. fixture was already 'completed' before events were added).
   */
  async runPipeline(fixtureId, seasonId = null) {
    const params = { p_fixture_id: fixtureId };
    if (seasonId) params.p_season_id = seasonId;
    const { data, error } = await SB.rpc('run_post_match_pipeline', params);
    if (error) { console.error('[MatchRepo.runPipeline]', error.message); return { ok: false, error }; }
    return { ok: true, result: _norm(data) };
  },

  /**
   * Lookup fixture by ID (for Match Observer setup).
   */
  async getFixture(fixtureId) {
    const { data, error } = await SB
      .from('fixtures')
      .select(`
        id, match_date, status, venue, league_id, season_id,
        home_club:clubs!fixtures_home_club_id_fkey(id, name, logo_url),
        away_club:clubs!fixtures_away_club_id_fkey(id, name, logo_url),
        leagues(name)
      `)
      .eq('id', fixtureId)
      .single();
    if (error) { return null; }
    return _norm(data);
  },

  /**
   * Load lineup for a fixture+club.
   */
  async lineup(fixtureId, clubId) {
    const { data, error } = await SB
      .from('match_lineups')
      .select(`
        id, role, jersey_number, position_played, position_slot, lineup_order,
        is_captain, is_vice_captain, formation,
        players(id, full_name, preferred_name, position)
      `)
      .eq('fixture_id', fixtureId)
      .eq('club_id', clubId)
      .order('lineup_order');
    if (error) { return []; }
    return _norm(data ?? []);
  },

  /**
   * Save a lineup entry.
   */
  async saveLineupEntry(entry) {
    const { error } = await SB
      .from('match_lineups')
      .upsert(entry, { onConflict: 'fixture_id,club_id,player_id' });
    return { ok: !error, error };
  },

  /**
   * Pipeline log — last N runs.
   */
  async pipelineLog(limit = 10) {
    const { data, error } = await SB
      .from('v_pipeline_summary')
      .select('*')
      .limit(limit);
    if (error) { return []; }
    return _norm(data ?? []);
  },
};

/* ─────────────────────────────────────────────────────────────
   REPOSITORY: User Follows
───────────────────────────────────────────────────────────── */
const FollowRepo = {

  async toggle(entityType, entityId) {
    const uid = await Auth.uid();
    if (!uid) return { ok: false, error: 'Not authenticated' };

    const { data: existing } = await SB
      .from('user_follows')
      .select('id')
      .eq('profile_id', uid)
      .eq('entity_type', entityType)
      .eq('entity_id', entityId)
      .single();

    if (existing) {
      const { error } = await SB.from('user_follows').delete().eq('id', existing.id);
      return { ok: !error, following: false, error };
    } else {
      const { error } = await SB
        .from('user_follows')
        .insert({ profile_id: uid, entity_type: entityType, entity_id: entityId });
      return { ok: !error, following: true, error };
    }
  },

  async isFollowing(entityType, entityId) {
    const uid = await Auth.uid();
    if (!uid) return false;
    const { data } = await SB
      .from('user_follows')
      .select('id')
      .eq('profile_id', uid)
      .eq('entity_type', entityType)
      .eq('entity_id', entityId)
      .single();
    return !!data;
  },

  async myFollows() {
    const uid = await Auth.uid();
    if (!uid) return [];
    const { data } = await SB
      .from('user_follows')
      .select('entity_type, entity_id, created_at')
      .eq('profile_id', uid);
    return _norm(data ?? []);
  },
};

/* ─────────────────────────────────────────────────────────────
   Utility helpers
───────────────────────────────────────────────────────────── */
function _mondayOfThisWeek() {
  const d = new Date();
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  d.setDate(diff);
  return d.toISOString().slice(0, 10);
}

/* ── Expose all repositories globally ─────────────────────── */
window.UserRepo       = UserRepo;
window.PlayerRepo     = PlayerRepo;
window.ClubRepo       = ClubRepo;
window.LeagueRepo     = LeagueRepo;
window.FixtureRepo    = FixtureRepo;
window.PassportRepo   = PassportRepo;
window.DnaRepo        = DnaRepo;
window.DevRepo        = DevRepo;
window.MarketValueRepo = MarketValueRepo;
window.NotifRepo      = NotifRepo;
window.ScoutRepo      = ScoutRepo;
window.MatchRepo      = MatchRepo;
window.FollowRepo     = FollowRepo;
