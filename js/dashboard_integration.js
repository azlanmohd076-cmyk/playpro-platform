/**
 * PlayPro — Dashboard Integration Patch
 * Replaces all mock data / PP.data / DATA hardcoded arrays
 * with live Supabase queries via repositories.js.
 *
 * Depends on: supabase.js → repositories.js → shared_dashboard_components.js
 *
 * Each dashboard HTML includes this file LAST:
 *   <script src="supabase.js"></script>
 *   <script src="repositories.js"></script>
 *   <script src="shared_dashboard_components.js"></script>
 *   <script src="dashboard_integration.js"></script>
 *   <!-- then the inline <script> block that calls DI.boot() -->
 *
 * Each HTML's inline script is reduced to:
 *   DI.boot('<dashboard-type>');
 *
 * dashboard types: 'coach' | 'club' | 'parent' | 'player' | 'public' | 'observer'
 */

'use strict';

/* ── Loading overlay helpers ────────────────────────────────── */
const _Loading = {
  show(msg = 'Loading…') {
    let el = document.getElementById('di-loader');
    if (!el) {
      el = document.createElement('div');
      el.id = 'di-loader';
      el.style.cssText = [
        'position:fixed;inset:0;background:rgba(10,46,22,.92);z-index:9999',
        'display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px',
      ].join(';');
      el.innerHTML = `
        <svg width="48" height="48" viewBox="0 0 48 48">
          <circle cx="24" cy="24" r="20" fill="none" stroke="rgba(255,255,255,.2)" stroke-width="4"/>
          <circle cx="24" cy="24" r="20" fill="none" stroke="#00b341" stroke-width="4"
            stroke-dasharray="80 48" stroke-linecap="round"
            transform="rotate(-90 24 24)">
            <animateTransform attributeName="transform" type="rotate"
              values="-90 24 24;270 24 24" dur="1s" repeatCount="indefinite"/>
          </circle>
        </svg>
        <div id="di-loader-msg" style="color:white;font-size:14px;font-weight:600;font-family:system-ui">${msg}</div>`;
      document.body.appendChild(el);
    }
    document.getElementById('di-loader-msg').textContent = msg;
    el.style.display = 'flex';
  },
  hide() {
    const el = document.getElementById('di-loader');
    if (el) el.style.display = 'none';
  },
  status(msg) {
    const el = document.getElementById('di-loader-msg');
    if (el) el.textContent = msg;
  },
};

/* ── Error boundary ─────────────────────────────────────────── */
function _err(ctx, e) {
  console.error(`[DI:${ctx}]`, e);
}

/* ── Notification badge updater ─────────────────────────────── */
async function _updateNotifBadge() {
  try {
    const count = await NotifRepo.unreadCount();
    document.querySelectorAll('[data-notif-badge]').forEach(el => {
      el.textContent = count > 0 ? count : '';
      el.style.display = count > 0 ? 'inline-flex' : 'none';
    });
  } catch(e) { /* silent */ }
}

/* ── Realtime notification listener ────────────────────────── */
async function _initNotifListener() {
  const uid = await Auth.uid();
  if (!uid) return;
  Realtime.notifications(uid, () => _updateNotifBadge());
  _updateNotifBadge();
}

/* ═══════════════════════════════════════════════════════════
   NORMALISE: convert DB row → PP player shape
   (so existing render functions work unchanged)
═══════════════════════════════════════════════════════════ */
function _toPlayerShape(row, stats = null, attrs = {}, fitness = null, morale = null, proj = null, hidden = null, training = 0) {
  const age = row.dateOfBirth
    ? Math.floor((Date.now() - new Date(row.dateOfBirth)) / 3.156e10)
    : (row.age ?? 0);

  return {
    id:       row.id,
    name:     row.fullName,
    preferred: row.preferredName || row.fullName,
    pos:      row.position,
    jersey:   row.jerseyNumber ?? 0,
    age,
    club:     row.clubName || '',
    club_id:  row.clubId,
    photo:    row.photoUrl,

    dna: {
      overall:   row.dnaOverall   ?? null,
      band:      row.dnaBand      ?? null,
      technical: row.dnaTechnical ?? null,
      physical:  row.dnaPhysical  ?? null,
      mental:    row.dnaMental    ?? null,
      tactical:  row.dnaTactical  ?? null,
      goalkeeper:row.dnaGoalkeeper ?? null,
    },
    potential: {
      score:    row.potentialScore    ?? null,
      category: row.potentialCategory ?? null,
    },
    passport: {
      score: row.passportScore ?? null,
      band:  row.passportBand  ?? null,
    },
    fitness: {
      condition: (fitness ?? row).fitnessCondition ?? (fitness ?? row).condition ?? null,
      sharpness: (fitness ?? row).matchSharpness   ?? null,
      fatigue:   (fitness ?? row).fatigueLevel     ?? null,
      load:      (fitness ?? row).trainingLoad     ?? null,
    },
    morale: {
      score:       (morale ?? row).moraleScore           ?? null,
      band:        (morale ?? row).moraleBand            ?? null,
      playing_sat: (morale ?? row).playingTimeSatisfaction ?? null,
      training_sat:(morale ?? row).trainingSatisfaction  ?? null,
      form_sat:    (morale ?? row).formSatisfaction      ?? null,
    },
    hidden: {
      professionalism: hidden?.professionalism ?? null,
      ambition:        hidden?.ambition        ?? null,
      injury_proneness:hidden?.injuryProneness ?? null,
    },
    injury_risk: row.injuryRiskLevel ?? null,
    projection: {
      peak_dna:      (proj ?? row).projectedPeakDna  ?? (proj ?? row).projectedDnaPeak ?? null,
      peak_age:      (proj ?? row).projectedPeakAge  ?? null,
      phase:         (proj ?? row).developmentPhase  ?? row.developmentPhase ?? null,
      wonderkid:     (proj ?? row).isWonderkid       ?? false,
      wonderkid_score: (proj ?? row).wonderkidScore  ?? null,
    },
    trend:          row.developmentTrend    ?? null,
    market_value:   row.marketValueMyr      ?? null,
    reputation:     { score: row.reputationScore ?? null, band: row.reputationBand ?? null },
    role:           row.playingRole         ?? null,
    scout_recommendation: row.scoutRecommendation ?? null,

    attrs: attrs,   // {passing: 14, dribbling: 15, ...}

    stats: stats ? {
      apps:        stats.apps        ?? 0,
      goals:       stats.goals       ?? 0,
      assists:     stats.assists     ?? 0,
      yellows:     stats.yellows     ?? 0,
      reds:        stats.reds        ?? 0,
      rating_avg:  stats.ratingAvg   ?? null,
    } : { apps:0, goals:0, assists:0, yellows:0, reds:0, rating_avg:null },

    training_score:      training,
    position_familiarity:[],
    timeline: [],
  };
}

/* ── Convert attrs map {code: row} → flat object {passing:14, ...} */
function _flatAttrs(attrsMap) {
  const out = {};
  for (const [code, row] of Object.entries(attrsMap)) {
    out[code] = row.currentValue ?? null;
  }
  return out;
}

/* ═══════════════════════════════════════════════════════════
   COACH DASHBOARD INTEGRATION
═══════════════════════════════════════════════════════════ */
const CoachDI = {
  clubId:  null,
  club:    null,
  players: [],
  events:  [],

  async boot() {
    _Loading.show('Loading squad data…');
    try {
      const profile = await Auth.profile();
      if (!profile) { _Loading.hide(); _showAuthError(); return; }

      this.clubId = await UserRepo.myClubId();
      if (!this.clubId) { _Loading.hide(); _showRoleError('coach or club admin'); return; }

      _Loading.status('Fetching club…');
      this.club = await ClubRepo.get(this.clubId);

      _Loading.status('Fetching squad…');
      const rawPlayers = await PlayerRepo.byClub(this.clubId);

      _Loading.status('Fetching player detail…');
      this.players = await Promise.all(rawPlayers.map(async p => {
        const [stats, attrMap, training] = await Promise.all([
          PlayerRepo.seasonStats(p.id),
          PlayerRepo.attributes(p.id),
          PlayerRepo.weeklyTrainingScore(p.id),
        ]);
        return _toPlayerShape(p, stats, _flatAttrs(attrMap), null, null, null, null, training);
      }));

      _Loading.status('Fetching activity feed…');
      const notifs   = await NotifRepo.recent(10);
      const sessions = await ClubRepo.upcomingSessions(this.clubId, 5);
      const fixtures = await FixtureRepo.byClub(this.clubId, 3);
      const nextFix  = await FixtureRepo.nextForClub(this.clubId);
      const lastRes  = await FixtureRepo.lastResults(this.clubId, 5);

      // Patch PP.data so existing render functions work without modification
      PP.data.user    = { name: profile.fullName, role: profile.role, email: profile.email };
      PP.data.players = this.players;
      PP.data.club    = _toClubShape(this.club, lastRes, nextFix, fixtures);
      PP.data.recent_events    = _notifsToEvents(notifs, fixtures);
      PP.data.upcoming_sessions= _sessionsToShape(sessions);
      PP.data.dna_history      = []; // populated per-player on demand

      _initNotifListener();
      _Loading.hide();

    } catch(e) { _err('CoachDI.boot', e); _Loading.hide(); _showGenericError(); }
  },
};

/* ═══════════════════════════════════════════════════════════
   CLUB DASHBOARD INTEGRATION
═══════════════════════════════════════════════════════════ */
const ClubDI = {
  clubId: null,

  async boot() {
    _Loading.show('Loading club data…');
    try {
      const profile = await Auth.profile();
      if (!profile) { _Loading.hide(); _showAuthError(); return; }

      this.clubId = await UserRepo.myClubId();
      if (!this.clubId) { _Loading.hide(); _showRoleError('club admin'); return; }

      _Loading.status('Fetching club…');
      const [club, rawPlayers, sessions, lastRes, nextFix, fixtures] = await Promise.all([
        ClubRepo.get(this.clubId),
        PlayerRepo.byClub(this.clubId),
        ClubRepo.upcomingSessions(this.clubId, 5),
        FixtureRepo.lastResults(this.clubId, 5),
        FixtureRepo.nextForClub(this.clubId),
        FixtureRepo.byClub(this.clubId, 5),
      ]);

      _Loading.status('Enriching squad…');
      const players = await Promise.all(rawPlayers.map(async p => {
        const [stats, attrMap, training] = await Promise.all([
          PlayerRepo.seasonStats(p.id),
          PlayerRepo.attributes(p.id),
          PlayerRepo.weeklyTrainingScore(p.id),
        ]);
        return _toPlayerShape(p, stats, _flatAttrs(attrMap), null, null, null, null, training);
      }));

      const notifs = await NotifRepo.recent(10);

      PP.data.user    = { name: profile.fullName, role: profile.role };
      PP.data.players = players;
      PP.data.club    = _toClubShape(club, lastRes, nextFix, fixtures);
      PP.data.recent_events     = _notifsToEvents(notifs, fixtures);
      PP.data.upcoming_sessions = _sessionsToShape(sessions);

      _initNotifListener();
      _Loading.hide();

    } catch(e) { _err('ClubDI.boot', e); _Loading.hide(); _showGenericError(); }
  },
};

/* ═══════════════════════════════════════════════════════════
   PARENT DASHBOARD INTEGRATION
═══════════════════════════════════════════════════════════ */
const ParentDI = {
  childPlayerId: null,

  async boot() {
    _Loading.show('Loading your child\'s passport…');
    try {
      const profile = await Auth.profile();
      if (!profile) { _Loading.hide(); _showAuthError(); return; }

      const wardIds = await UserRepo.myWardIds();
      if (!wardIds.length) { _Loading.hide(); _showNoWardError(); return; }
      this.childPlayerId = wardIds[0];

      _Loading.status('Loading passport…');
      const [passport, development, attrMap, stats, proj, fitness, morale,
             passHistory, attrHistory, sessions, familiarity] = await Promise.all([
        PlayerRepo.passport(this.childPlayerId),
        PlayerRepo.development(this.childPlayerId),
        PlayerRepo.attributes(this.childPlayerId),
        PlayerRepo.seasonStats(this.childPlayerId),
        PlayerRepo.projection(this.childPlayerId),
        PlayerRepo.fitness(this.childPlayerId),
        PlayerRepo.morale(this.childPlayerId),
        PlayerRepo.passportHistory(this.childPlayerId, 8),
        PlayerRepo.attributeHistory(this.childPlayerId, null, 40),
        ClubRepo.upcomingSessions(passport?.clubId, 5),
        PlayerRepo.positionFamiliarity(this.childPlayerId),
      ]);

      const p = _toPlayerShape(
        { ...passport, ...development },
        stats,
        _flatAttrs(attrMap),
        fitness, morale, proj
      );
      p.position_familiarity = familiarity;
      p.timeline = _buildTimeline(stats, p);

      // Compute training history scores (ratings from last 8 weeks)
      const trainHist = await DevRepo.trainingHistory(this.childPlayerId, 8);
      const trainingScoreHistory = _trainHistToScores(trainHist);

      PP.data.players          = [p];
      PP.data.passport_history = passHistory.map(r => r.passportScore ?? 0);
      PP.data.dna_history      = passHistory.map(r => r.dnaOverallAtTime ?? r.passportScore ?? 0);
      PP.data.upcoming_sessions= _sessionsToShape(sessions);
      PP.data._trainingScoreHistory = trainingScoreHistory;
      PP.data._child = p;

      _initNotifListener();
      _Loading.hide();

    } catch(e) { _err('ParentDI.boot', e); _Loading.hide(); _showGenericError(); }
  },
};

/* ═══════════════════════════════════════════════════════════
   PLAYER DASHBOARD INTEGRATION
═══════════════════════════════════════════════════════════ */
const PlayerDI = {
  playerId: null,

  async boot() {
    _Loading.show('Loading your Football Passport…');
    try {
      const profile = await Auth.profile();
      if (!profile) { _Loading.hide(); _showAuthError(); return; }

      this.playerId = await UserRepo.myPlayerId();
      if (!this.playerId) { _Loading.hide(); _showClaimPrompt(); return; }

      _Loading.status('Loading passport data…');
      const [passport, development, attrMap, stats, proj, fitness, morale,
             passHistory, familiarity, similar, hidden, injuryRisk] = await Promise.all([
        PlayerRepo.passport(this.playerId),
        PlayerRepo.development(this.playerId),
        PlayerRepo.attributes(this.playerId),
        PlayerRepo.seasonStats(this.playerId),
        PlayerRepo.projection(this.playerId),
        PlayerRepo.fitness(this.playerId),
        PlayerRepo.morale(this.playerId),
        PlayerRepo.passportHistory(this.playerId, 8),
        PlayerRepo.positionFamiliarity(this.playerId),
        PlayerRepo.similar(this.playerId),
        PlayerRepo.hidden(this.playerId),
        PlayerRepo.injuryRisk(this.playerId),
      ]);

      const p = _toPlayerShape(
        { ...passport, ...development },
        stats, _flatAttrs(attrMap),
        fitness, morale, proj, hidden,
        await PlayerRepo.weeklyTrainingScore(this.playerId)
      );
      p.position_familiarity = familiarity;
      p.timeline             = _buildTimeline(stats, p);
      p.similar              = similar;
      p.injury_risk          = injuryRisk?.riskLevel ?? p.injury_risk;
      p.injury_risk_detail   = injuryRisk;

      // Scout report
      const scoutReport = await ScoutRepo.report(this.playerId);

      PP.data.players          = [p];
      PP.data.passport_history = passHistory.map(r => r.passportScore ?? 0);
      PP.data.dna_history      = passHistory.map(r => r.dnaOverallAtTime ?? 0);
      PP.data._me              = p;
      PP.data._scoutReport     = scoutReport;

      _initNotifListener();
      _Loading.hide();

    } catch(e) { _err('PlayerDI.boot', e); _Loading.hide(); _showGenericError(); }
  },
};

/* ═══════════════════════════════════════════════════════════
   PUBLIC PLATFORM INTEGRATION
   Replaces DATA object in playpro_public.html
═══════════════════════════════════════════════════════════ */
const PublicDI = {

  async boot() {
    try {
      _Loading.show('Loading PlayPro…');

      const [leagues, passportList, wonderkids] = await Promise.all([
        LeagueRepo.all(),
        PassportRepo.leaderboard({}, 20),
        PassportRepo.wonderkids(6),
      ]);

      // Build public DATA shape matching playpro_public.html expectations
      const players = passportList.map(r => ({
        id:       r.playerId,
        name:     r.fullName,
        preferred:r.displayName || r.fullName,
        pos:      r.position,
        age:      r.age,
        club:     r.clubName,
        photo:    r.photoUrl,
        passport: { score: r.passportScore, band: r.passportBand },
        band:     r.dnaBand,
        dna:      { overall: r.dnaOverall, technical: r.dnaTechnical, physical: r.dnaPhysical, mental: r.dnaMental, tactical: r.dnaTactical },
        potential:{ score: r.potentialScore, cat: r.potentialCategory },
        attrs:    {},  // loaded on demand when passport page opens
        stats:    { apps:0, goals:0, assists:0, yellows:0, reds:0 },
        timeline: [],
        claimed:  false,
      }));

      const clubIds = [...new Set(passportList.map(r => r.clubId).filter(Boolean))].slice(0, 6);
      const clubs = await Promise.all(clubIds.map(async id => {
        const c = await ClubRepo.get(id);
        if (!c) return null;
        return {
          id:   c.id,
          name: c.name,
          tier: 'standard',
          dna:  { overall: c.dnaOverall ?? 0, tech: c.dnaTechnical ?? 0, phys: c.dnaPhysical ?? 0, ment: c.dnaMental ?? 0, tact: c.dnaTactical ?? 0 },
          passport: c.clubPassportScore ?? 0,
          players: 0,
          description: c.description ?? '',
        };
      })).then(r => r.filter(Boolean));

      // Replace DATA global
      window.DATA = {
        leagues,
        clubs,
        players,
        standings: {},
        fixtures: [],
      };

      // Fetch standings for first active league
      if (leagues.length) {
        const s = await LeagueRepo.standings(leagues[0].id);
        window.DATA.standings[leagues[0].id] = s.map((r, i) => ({
          pos: r.position ?? i + 1,
          club: r.clubId,
          name: r.clubName,
          p: r.played ?? 0,
          w: r.wins ?? 0,
          d: r.draws ?? 0,
          l: r.losses ?? 0,
          gf: r.goalsFor ?? 0,
          ga: r.goalsAgainst ?? 0,
          gd: r.goalDifference ?? 0,
          pts: r.points ?? 0,
        }));
        const fx = await FixtureRepo.byLeague(leagues[0].id, null, 5);
        window.DATA.fixtures = fx.map(f => ({
          id:         f.id,
          home:       f.homeClub?.name ?? '',
          away:       f.awayClub?.name ?? '',
          home_score: f.matchResults?.[0]?.homeGoals ?? null,
          away_score: f.matchResults?.[0]?.awayGoals ?? null,
          league:     leagues[0].name,
          date:       f.matchDate ? new Date(f.matchDate).toLocaleDateString('en-GB',{day:'numeric',month:'short',year:'numeric'}) : '',
          status:     f.status,
          minute:     null,
        }));
      }

      // Patch passport open handler to load full player data on demand
      const _origShowPassport = window.showPassport;
      window.showPassport = async function(id) {
        const existing = window.DATA.players.find(p => p.id === id);
        if (existing && !existing._loaded) {
          existing._loaded = true;
          const [attrMap, stats, development] = await Promise.all([
            PlayerRepo.attributes(id),
            PlayerRepo.seasonStats(id),
            PlayerRepo.development(id),
          ]);
          Object.assign(existing.attrs, _flatAttrs(attrMap));
          if (stats) {
            existing.stats.apps    = stats.apps;
            existing.stats.goals   = stats.goals;
            existing.stats.assists = stats.assists;
            existing.stats.yellows = stats.yellows;
            existing.stats.reds    = stats.reds;
            existing.stats.rating_avg = stats.ratingAvg;
          }
          if (development) {
            existing.projection = {
              peak_dna:      development.projectedPeakDna ?? null,
              peak_age:      development.projectedPeakAge ?? null,
              phase:         development.developmentPhase ?? null,
              wonderkid:     development.isWonderkid ?? false,
              wonderkid_score: development.wonderkidScore ?? null,
            };
          }
          existing.timeline = _buildTimeline(stats, existing);
        }
        if (_origShowPassport) _origShowPassport(id);
      };

      // Patch follow toggle
      const _origFollow = window.toggleFollow;
      window.toggleFollow = async function(id, type, btn) {
        const session = await Auth.session();
        if (!session) { if (window.PP) PP.toast('Sign in to follow'); return; }
        const { following, ok } = await FollowRepo.toggle(type, id);
        if (ok) {
          btn.className = following ? 'follow-btn following' : 'follow-btn';
          btn.textContent = following ? '✓ Following' : '+ Follow';
          if (window.PP) PP.toast(following ? "Following! You'll get updates." : 'Unfollowed');
        }
      };

      _Loading.hide();

    } catch(e) { _err('PublicDI.boot', e); _Loading.hide(); }
  },
};

/* ═══════════════════════════════════════════════════════════
   MATCH OBSERVER INTEGRATION
   Replaces simulateDBWrite() with real pipeline call
═══════════════════════════════════════════════════════════ */
const ObserverDI = {

  fixtureId: null,
  seasonId:  null,

  /** Call after startMatch() to wire up the fixture. */
  async setFixture(fixtureId) {
    this.fixtureId = fixtureId;
    if (!fixtureId) return;
    const fixture = await MatchRepo.getFixture(fixtureId);
    if (fixture) this.seasonId = fixture.seasonId ?? null;
  },

  /**
   * Replaces simulateDBWrite() in match_observer.html.
   * Saves events → stats → marks complete → runs pipeline.
   */
  async finalise(matchState) {
    const { events, stats, players, homeGoals, awayGoals, minute } = matchState;

    const fixtureId = this.fixtureId;
    if (!fixtureId) {
      // No fixture linked — show summary but cannot persist
      console.warn('[ObserverDI] No fixture_id set. Displaying local summary only.');
      return { ok: false, reason: 'no_fixture' };
    }

    window.toast('💾 Saving match events…');

    // 1. Enrich events with club IDs
    const enrichedEvents = events.map(e => {
      const player = players.find(p => p.id === e.playerId);
      return {
        ...e,
        clubId:     player ? (player.team === 'home' ? matchState.homeClubId : matchState.awayClubId) : null,
        homeScore:  homeGoals,
        awayScore:  awayGoals,
      };
    });

    // 2. Save match events
    const evRes = await MatchRepo.saveEvents(fixtureId, enrichedEvents);
    if (!evRes.ok) {
      window.toast('⚠️ Event save failed — check connection');
      return evRes;
    }

    window.toast('💾 Saving player stats…');

    // 3. Enrich stats with club and role info
    const enrichedStats = {};
    for (const [pid, s] of Object.entries(stats)) {
      const p = players.find(x => x.id === pid);
      enrichedStats[pid] = {
        ...s,
        clubId: p ? (p.team === 'home' ? matchState.homeClubId : matchState.awayClubId) : null,
        role:   p?.role ?? 'starter',
      };
    }

    // 4. Save player_match_stats
    const statsRes = await MatchRepo.savePlayerStats(fixtureId, enrichedStats, players.map(p => ({
      id: p.id, clubId: p.team === 'home' ? matchState.homeClubId : matchState.awayClubId
    })));
    if (!statsRes.ok) {
      window.toast('⚠️ Stats save failed — events saved, pipeline may still run');
    }

    window.toast('⚙️ Running DNA pipeline…');

    // 5. Mark fixture completed — triggers pipeline via DB trigger
    const completeRes = await MatchRepo.completeFixture(fixtureId);
    if (!completeRes.ok) {
      // Trigger failed to complete fixture — call pipeline directly
      const pipeRes = await MatchRepo.runPipeline(fixtureId, this.seasonId);
      window.toast(pipeRes.ok
        ? '✅ Pipeline ran — DNA & Passport updated'
        : '⚠️ Pipeline call failed — data saved, will retry on next nightly batch');
      return pipeRes;
    }

    window.toast('✅ Match complete — DNA & Passport updated automatically');
    return { ok: true };
  },
};

/* ═══════════════════════════════════════════════════════════
   AUTH UI INTEGRATION
   Replaces doLogin() / doRegister() / signOut() in all dashboards
═══════════════════════════════════════════════════════════ */
const AuthDI = {

  async login(email, password) {
    const { session, error } = await Auth.signIn(email, password);
    if (error) {
      PP.toast('Sign in failed: ' + error.message);
      return false;
    }
    PP.toast('Welcome back!');
    // Reload the page to re-boot the dashboard with live session
    setTimeout(() => window.location.reload(), 600);
    return true;
  },

  async register(email, password, fullName, role) {
    const { data, error } = await Auth.signUp(email, password, { full_name: fullName, role });
    if (error) {
      PP.toast('Registration failed: ' + error.message);
      return false;
    }
    PP.toast('Account created! Check your email to confirm.');
    return true;
  },

  async signOut() {
    await Auth.signOut();
    window.location.href = 'playpro_public.html';
  },

  async updateNotifBadge() {
    return _updateNotifBadge();
  },
};

/* ═══════════════════════════════════════════════════════════
   SHAPE CONVERTERS
   Convert DB rows into the shapes the existing render
   functions expect (avoids rewriting all HTML JS).
═══════════════════════════════════════════════════════════ */
function _toClubShape(club, lastRes, nextFix, fixtures) {
  if (!club) return PP.data.club;
  return {
    id:     club.id,
    name:   club.name,
    league: club.leagueName ?? '',
    tier:   club.tier ?? 'standard',
    season: club.currentSeason ?? '—',
    formation: club.formation ?? '4-4-2',
    founded: club.yearFounded,
    colours: club.colours,
    dna: {
      overall:   club.dnaOverall   ?? 0,
      technical: club.dnaTechnical ?? 0,
      physical:  club.dnaPhysical  ?? 0,
      mental:    club.dnaMental    ?? 0,
      tactical:  club.dnaTactical  ?? 0,
    },
    passport_score: club.clubPassportScore ?? 0,
    reputation:     { score: club.reputationScore ?? 0, band: club.reputationBand ?? 'unknown' },
    squad_size:     club.squadSize ?? 0,
    assessed:       club.assessed  ?? 0,
    standing: {
      position: 1, played: 0, w: 0, d: 0, l: 0, pts: 0, gf: 0, ga: 0, gd: 0,
    },
    followers:          club.followerCount ?? 0,
    market_value_total: club.marketValueTotal ?? 0,
    next_match: nextFix ? {
      opponent:  nextFix.homeClub?.id === club.id ? nextFix.awayClub?.name : nextFix.homeClub?.name,
      date:      nextFix.matchDate ? new Date(nextFix.matchDate).toLocaleDateString('en-GB',{day:'numeric',month:'short',year:'numeric'}) : '—',
      venue:     nextFix.venue ?? '—',
      is_home:   nextFix.homeClub?.id === club.id,
    } : null,
    wonderkids:        0,
    high_risk_players: 0,
    last_5_results:    lastRes ?? [],
  };
}

function _notifsToEvents(notifs, fixtures) {
  const evtMap = { goal:'⚽', assessment:'🧬', training:'🏃', injury:'🩺', milestone:'🌟', general:'📋' };
  const combined = [
    ...notifs.map(n => ({
      icon: evtMap[n.notifications?.notificationType] ?? '📋',
      title: n.notifications?.title ?? n.notifications?.body ?? 'Notification',
      time: _relTime(n.receivedAt ?? n.notifications?.createdAt),
    })),
    ...fixtures.slice(0, 3).map(f => {
      const r = f.matchResults?.[0];
      if (!r) return null;
      return {
        icon: '⚽',
        title: `Result: ${f.homeClub?.name} ${r.homeGoals}–${r.awayGoals} ${f.awayClub?.name}`,
        time: _relTime(f.matchDate),
      };
    }).filter(Boolean),
  ].slice(0, 8);
  return combined;
}

function _sessionsToShape(sessions) {
  return sessions.map(s => ({
    date: s.sessionDate ? new Date(s.sessionDate).toLocaleDateString('en-GB',{weekday:'short',day:'numeric',month:'short'}) : '—',
    time: s.sessionTime?.slice(0,5) ?? '—',
    type: _cap(s.focusCategory ?? 'Mixed'),
    intensity: s.intensity ?? 'normal',
    expected: 20,
  }));
}

function _buildTimeline(stats, player) {
  const items = [];
  if (player.club)  items.push({ icon:'⚽', title:'Joined ' + player.club, date:'Current season' });
  if (stats?.goals >= 10) items.push({ icon:'🥇', title:'10+ goals milestone', date:'This season' });
  if (player.dna?.overall >= 70) items.push({ icon:'🌟', title:'DNA rating reached Advanced', date:'Recent' });
  if (player.projection?.wonderkid) items.push({ icon:'⭐', title:'Identified as Wonderkid', date:'Recent' });
  return items;
}

function _trainHistToScores(history) {
  if (!history.length) return [70, 70, 70, 70, 70, 70, 70, 70];
  const weeks = {};
  history.forEach(h => {
    const wk = h.trainingSessions?.sessionDate?.slice(0, 7) ?? 'unknown';
    if (!weeks[wk]) weeks[wk] = [];
    weeks[wk].push(h.rating ?? 7);
  });
  return Object.values(weeks).map(ratings =>
    Math.round(ratings.reduce((a,b)=>a+b,0)/ratings.length * 10)
  ).slice(-8);
}

function _relTime(isoStr) {
  if (!isoStr) return '—';
  const diff = Date.now() - new Date(isoStr).getTime();
  const h = Math.floor(diff / 3600000);
  if (h < 1)  return 'Just now';
  if (h < 24) return h + 'h ago';
  const d = Math.floor(h / 24);
  if (d === 1) return 'Yesterday';
  return d + ' days ago';
}

function _cap(s) {
  return s ? s.charAt(0).toUpperCase() + s.slice(1).replace(/_/g,' ') : '';
}

/* ── Auth error screens ─────────────────────────────────── */
function _showAuthError() {
  document.body.innerHTML = `
    <div style="min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a2e16;font-family:system-ui">
      <div style="background:white;border-radius:16px;padding:32px;max-width:360px;width:90%;text-align:center">
        <div style="font-size:48px;margin-bottom:16px">🔐</div>
        <div style="font-size:20px;font-weight:800;margin-bottom:8px">Sign In Required</div>
        <div style="font-size:14px;color:#6b7280;margin-bottom:24px">You must be signed in to access this dashboard.</div>
        <a href="playpro_public.html" style="display:block;background:#00b341;color:white;border-radius:999px;padding:14px;font-size:15px;font-weight:700;text-decoration:none">Go to PlayPro →</a>
      </div>
    </div>`;
}
function _showRoleError(required) {
  document.body.innerHTML = `
    <div style="min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a2e16;font-family:system-ui">
      <div style="background:white;border-radius:16px;padding:32px;max-width:360px;width:90%;text-align:center">
        <div style="font-size:48px;margin-bottom:16px">🚫</div>
        <div style="font-size:20px;font-weight:800;margin-bottom:8px">Access Restricted</div>
        <div style="font-size:14px;color:#6b7280;margin-bottom:24px">This dashboard requires <strong>${required}</strong> access.</div>
        <a href="playpro_public.html" style="display:block;background:#00b341;color:white;border-radius:999px;padding:14px;font-size:15px;font-weight:700;text-decoration:none">Return to PlayPro →</a>
      </div>
    </div>`;
}
function _showClaimPrompt() {
  document.body.innerHTML = `
    <div style="min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a2e16;font-family:system-ui">
      <div style="background:white;border-radius:16px;padding:32px;max-width:360px;width:90%;text-align:center">
        <div style="font-size:48px;margin-bottom:16px">🪪</div>
        <div style="font-size:20px;font-weight:800;margin-bottom:8px">Claim Your Passport</div>
        <div style="font-size:14px;color:#6b7280;margin-bottom:24px">Your account isn't linked to a player record yet. Browse PlayPro and claim your passport.</div>
        <a href="playpro_public.html#claim" style="display:block;background:#00b341;color:white;border-radius:999px;padding:14px;font-size:15px;font-weight:700;text-decoration:none">Claim My Passport →</a>
      </div>
    </div>`;
}
function _showNoWardError() {
  document.body.innerHTML = `
    <div style="min-height:100vh;display:flex;align-items:center;justify-content:center;background:#4c1d95;font-family:system-ui">
      <div style="background:white;border-radius:16px;padding:32px;max-width:360px;width:90%;text-align:center">
        <div style="font-size:48px;margin-bottom:16px">👨‍👩‍👦</div>
        <div style="font-size:20px;font-weight:800;margin-bottom:8px">No Linked Child</div>
        <div style="font-size:14px;color:#6b7280;margin-bottom:24px">Your account isn't linked to any player record yet. Submit a guardian claim on your child's passport.</div>
        <a href="playpro_public.html" style="display:block;background:#7c3aed;color:white;border-radius:999px;padding:14px;font-size:15px;font-weight:700;text-decoration:none">Browse PlayPro →</a>
      </div>
    </div>`;
}
function _showGenericError() {
  const msg = document.getElementById('di-loader-msg');
  if (msg) {
    msg.innerHTML = '⚠️ Connection error.<br><span style="font-size:12px;opacity:.7">Check your internet and try refreshing.</span>';
    setTimeout(() => _Loading.hide(), 4000);
  }
}

/* ═══════════════════════════════════════════════════════════
   DI.boot() — single entry point for all dashboards
═══════════════════════════════════════════════════════════ */
const DI = {
  async boot(type) {
    switch (type) {
      case 'coach':    await CoachDI.boot();    break;
      case 'club':     await ClubDI.boot();     break;
      case 'parent':   await ParentDI.boot();   break;
      case 'player':   await PlayerDI.boot();   break;
      case 'public':   await PublicDI.boot();   break;
      case 'observer': /* Observer wires up per-match */ break;
      default: console.warn('[DI.boot] Unknown type:', type);
    }

    // Replace auth functions globally after boot
    window.doLogin = async () => {
      const email = document.getElementById('login-email')?.value?.trim() ?? '';
      const pw    = document.getElementById('login-pw')?.value ?? '';
      await AuthDI.login(email, pw);
    };
    window.doRegister = async () => {
      const name  = document.getElementById('reg-name')?.value?.trim() ?? '';
      const email = document.getElementById('reg-email')?.value?.trim() ?? '';
      const role  = document.getElementById('reg-role')?.value ?? 'fan';
      const pw    = document.getElementById('reg-pw')?.value ?? '';
      await AuthDI.register(email, pw, name, role);
    };
    window.signOut = () => AuthDI.signOut();
  },

  /** Match Observer: wire up the finalise flow. */
  async wireObserver(fixtureId) {
    await ObserverDI.setFixture(fixtureId);
    // Replace simulateDBWrite in match_observer.html scope
    window.simulateDBWrite = async () => {
      const result = await ObserverDI.finalise({
        events:   window.M?.events ?? [],
        stats:    window.M?.stats ?? {},
        players:  window.M?.players ?? [],
        homeGoals: window.M?.homeGoals ?? 0,
        awayGoals: window.M?.awayGoals ?? 0,
        minute:   window.M?.minute ?? 0,
        homeClubId: window.M?.homeClubId ?? null,
        awayClubId: window.M?.awayClubId ?? null,
      });
      return result;
    };
  },
};

/* ── Expose DI globally ─────────────────────────────────── */
window.DI         = DI;
window.AuthDI     = AuthDI;
window.ObserverDI = ObserverDI;
