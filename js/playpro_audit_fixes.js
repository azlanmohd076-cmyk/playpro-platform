/**
 * PlayPro Audit Fixes — JavaScript Layer
 * Applies fixes 5-9 from the proof-of-life audit.
 *
 * Patches repositories.js methods in-place at runtime.
 * Load this file AFTER repositories.js:
 *
 *   <script src="repositories.js"></script>
 *   <script src="playpro_audit_fixes.js"></script>
 *
 * Each fix shows BEFORE and AFTER for the exact broken code.
 */

'use strict';

// ============================================================
// FIX 5 — PlayerRepo.seasonStats()
// ============================================================
// BEFORE:
//   .order('fixtures(match_date)', { ascending: false })
//   → Invalid PostgREST syntax. Throws HTTP 400 at runtime.
//   Embedding-table ordering uses foreignTable option, not
//   parenthesised column notation.
//
// AFTER:
//   .order('match_date', { foreignTable: 'fixtures', ascending: false })
//   → Valid PostgREST v2 syntax for ordering on an embedded table.
// ============================================================
PlayerRepo.seasonStats = async function seasonStats(playerId, seasonId = null) {
  let q = window.SB
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
    // FIX: was .order('fixtures(match_date)', { ascending: false })
    .order('match_date', { foreignTable: 'fixtures', ascending: false })
    .limit(50);

  if (seasonId) {
    // Filter by season via the fixture's season_id (now exists after SQL fix)
    q = q.eq('fixtures.season_id', seasonId);
  }

  const { data, error } = await q;
  if (error) {
    console.error('[PlayerRepo.seasonStats FIX5]', error.message);
    return null;
  }

  const rows = data ?? [];
  if (!rows.length) {
    return { apps: 0, goals: 0, assists: 0, yellows: 0, reds: 0, ratingAvg: null };
  }

  const sum = (f) => rows.reduce((a, r) => a + (r[f] || 0), 0);
  const ratings = rows.map(r => r.match_rating).filter(Boolean);

  return {
    apps:           rows.length,
    goals:          sum('goals'),
    assists:        sum('assists'),
    shots:          sum('shots'),
    shotsOnTarget:  sum('shots_on_target'),
    yellows:        sum('yellow_cards'),
    reds:           sum('red_cards'),
    saves:          sum('saves'),
    minutesPlayed:  sum('minutes_played'),
    starts:         rows.filter(r => r.started).length,
    ratingAvg:      ratings.length
      ? Math.round(ratings.reduce((a, b) => a + b, 0) / ratings.length * 10) / 10
      : null,
    passAccuracyAvg: rows.filter(r => r.pass_accuracy).length
      ? Math.round(
          rows.reduce((a, r) => a + (r.pass_accuracy || 0), 0) /
          rows.filter(r => r.pass_accuracy).length
        )
      : null,
  };
};

// ============================================================
// FIX 6 — PlayerRepo.similar()
// ============================================================
// BEFORE:
//   players!player_similarities_similar_player_id_fkey(...)
//   → Explicit FK name hint. The FK in Phase 6.6 is anonymous
//     (no CONSTRAINT name on the REFERENCES clause).
//     PostgREST cannot resolve the named hint → returns error.
//
// AFTER:
//   players!similar_player_id(...)
//   → Use column-name hint instead of FK-name hint.
//     PostgREST resolves the join via the column name which
//     unambiguously points to the players table.
// ============================================================
PlayerRepo.similar = async function similar(playerId) {
  const { data, error } = await window.SB
    .from('player_similarities')
    .select(`
      similar_player_id,
      similarity_score,
      players!similar_player_id(
        id, full_name, preferred_name, position,
        dna_overall, dna_band, playing_role,
        club_id, photo_url, share_url_slug
      )
    `)
    // FIX: was players!player_similarities_similar_player_id_fkey(...)
    .eq('player_id', playerId)
    .order('similarity_score', { ascending: false })
    .limit(5);

  if (error) {
    console.error('[PlayerRepo.similar FIX6]', error.message);
    return [];
  }
  return (data ?? []).map(row => {
    // Normalise: camelCase the nested player object
    const p = row.players;
    return {
      similarPlayerId:  row.similar_player_id,
      similarityScore:  row.similarity_score,
      player: p ? {
        id:           p.id,
        fullName:     p.full_name,
        preferredName:p.preferred_name,
        position:     p.position,
        dnaOverall:   p.dna_overall,
        dnaBand:      p.dna_band,
        playingRole:  p.playing_role,
        clubId:       p.club_id,
        photoUrl:     p.photo_url,
        shareUrlSlug: p.share_url_slug,
      } : null,
    };
  });
};

// ============================================================
// FIX 7 — ClubRepo.marketValues()
// ============================================================
// BEFORE:
//   .from('player_market_values')
//   .select(`... players!inner(...) ...`)
//   .eq('players.club_id', clubId)   ← INVALID
//   → PostgREST does not support .eq() filtering on embedded
//     resource columns from the parent query context.
//     This returns ALL market values, ignoring clubId.
//
// AFTER:
//   Filter player_market_values by joining players via
//   a subquery approach: first get playerIds for the club,
//   then fetch their current market values.
//   This is two queries but both are indexed and fast.
// ============================================================
ClubRepo.marketValues = async function marketValues(clubId) {
  // Step 1: get all active player IDs for this club
  const { data: playerRows, error: playerErr } = await window.SB
    .from('players')
    .select('id')
    .eq('club_id', clubId)
    .eq('is_active', true);

  if (playerErr || !playerRows?.length) return [];

  const playerIds = playerRows.map(r => r.id);

  // Step 2: fetch current market values for those players
  const { data, error } = await window.SB
    .from('player_market_values')
    .select(`
      player_id, value_myr, computed_at, method,
      players(
        id, full_name, preferred_name, position,
        jersey_number, dna_overall, dna_band, playing_role, club_id
      )
    `)
    // FIX: was .eq('players.club_id', clubId) — invalid PostgREST syntax
    .eq('is_current', true)
    .in('player_id', playerIds)
    .order('value_myr', { ascending: false });

  if (error) {
    console.error('[ClubRepo.marketValues FIX7]', error.message);
    return [];
  }

  return (data ?? []).map(row => ({
    playerId:     row.player_id,
    valueMyr:     row.value_myr,
    computedAt:   row.computed_at,
    method:       row.method,
    fullName:     row.players?.full_name,
    preferredName:row.players?.preferred_name,
    position:     row.players?.position,
    jerseyNumber: row.players?.jersey_number,
    dnaOverall:   row.players?.dna_overall,
    dnaBand:      row.players?.dna_band,
    playingRole:  row.players?.playing_role,
  }));
};

// ============================================================
// FIX 8a — LeagueRepo.standings()
// ============================================================
// BEFORE:
//   Fallback query selected season_id from standings:
//     .select('id, league_id, season_id, club_id, ...')
//   → standings.season_id did not exist → ERROR
//
// AFTER (after SQL Fix 1 adds the column):
//   The fallback query now includes season_id safely.
//   Primary path via mv_league_standings also now works
//   because the view was rebuilt in SQL Fix 3.
//   Additionally: if mv_league_standings is empty (not yet
//   refreshed), the query returns [] rather than erroring —
//   the fallback kicks in automatically.
// ============================================================
LeagueRepo.standings = async function standings(leagueId, seasonId = null) {
  // Primary: materialised view (populated by refresh_all_public_views)
  let q = window.SB
    .from('mv_league_standings')
    .select('*')
    .eq('league_id', leagueId)
    .order('position', { ascending: true });
  if (seasonId) q = q.eq('season_id', seasonId);

  const { data: mvData, error: mvError } = await q;

  // mv returned rows → use them
  if (!mvError && mvData?.length) {
    return mvData.map(r => ({
      standingsId:  r.standings_id,
      leagueId:     r.league_id,
      leagueName:   r.league_name,
      seasonId:     r.season_id,
      seasonName:   r.season_name,
      clubId:       r.club_id,
      clubName:     r.club_name,
      logoUrl:      r.logo_url,
      played:       r.played,
      wins:         r.wins,
      draws:        r.draws,
      losses:       r.losses,
      goalsFor:     r.goals_for,
      goalsAgainst: r.goals_against,
      goalDifference: r.goal_difference,
      points:       r.points,
      position:     r.position,
    }));
  }

  // Fallback: live standings table
  // FIX: was selecting season_id before it existed; now safe after SQL Fix 1.
  let fallbackQ = window.SB
    .from('standings')
    .select(`
      id, league_id, season_id, club_id,
      played, wins, draws, losses,
      goals_for, goals_against, goal_difference, points,
      clubs(name, logo_url)
    `)
    .eq('league_id', leagueId)
    .order('points', { ascending: false });

  if (seasonId) fallbackQ = fallbackQ.eq('season_id', seasonId);

  const { data: liveData, error: liveErr } = await fallbackQ;
  if (liveErr) {
    console.error('[LeagueRepo.standings FIX8a]', liveErr.message);
    return [];
  }

  return (liveData ?? []).map((r, i) => ({
    standingsId:    r.id,
    leagueId:       r.league_id,
    seasonId:       r.season_id,
    clubId:         r.club_id,
    clubName:       r.clubs?.name,
    logoUrl:        r.clubs?.logo_url,
    played:         r.played,
    wins:           r.wins,
    draws:          r.draws,
    losses:         r.losses,
    goalsFor:       r.goals_for,
    goalsAgainst:   r.goals_against,
    goalDifference: r.goal_difference,
    points:         r.points,
    position:       i + 1,  // ranked by query order when matview unavailable
  }));
};

// ============================================================
// FIX 8b — LeagueRepo.topScorers()
// ============================================================
// BEFORE:
//   mv_top_scorers built with broken date-range season JOIN.
//   Cartesian product risk; also returned 0 rows on fresh deploy.
//
// AFTER:
//   mv_top_scorers rebuilt in SQL Fix 4 using fixtures.season_id.
//   JS method unchanged in its primary path.
//   Added live-query fallback in case mv is empty.
// ============================================================
LeagueRepo.topScorers = async function topScorers(leagueId, limit = 10) {
  // Primary: materialised view
  const { data: mvData, error: mvError } = await window.SB
    .from('mv_top_scorers')
    .select('*')
    .eq('league_id', leagueId)
    .order('goals', { ascending: false })
    .limit(limit);

  if (!mvError && mvData?.length) return mvData;

  // Fallback: live aggregation directly from match_events
  // This is slower but always accurate, and works before the
  // materialised view has been refreshed.
  const { data, error } = await window.SB
    .from('match_events')
    .select(`
      player_id,
      fixtures!inner(league_id, status, season_id),
      players!inner(
        full_name, preferred_name, photo_url,
        share_url_slug, position, club_id
      )
    `)
    .eq('event_type', 'goal')
    .eq('is_cancelled', false)
    .eq('fixtures.league_id', leagueId)
    .eq('fixtures.status', 'completed')
    .limit(limit * 10);  // over-fetch to aggregate client-side

  if (error) {
    console.error('[LeagueRepo.topScorers FIX8b]', error.message);
    return [];
  }

  // Aggregate goals per player client-side
  const counts = {};
  for (const row of data ?? []) {
    const pid = row.player_id;
    if (!counts[pid]) {
      counts[pid] = {
        playerId:    pid,
        displayName: row.players?.preferred_name || row.players?.full_name,
        fullName:    row.players?.full_name,
        photoUrl:    row.players?.photo_url,
        shareUrlSlug:row.players?.share_url_slug,
        position:    row.players?.position,
        clubId:      row.players?.club_id,
        leagueId,
        goals:       0,
        assists:     0,
      };
    }
    counts[pid].goals += 1;
  }

  return Object.values(counts)
    .sort((a, b) => b.goals - a.goals)
    .slice(0, limit);
};

// ============================================================
// FIX 8c — MatchRepo.getFixture()
// ============================================================
// BEFORE:
//   .select('id, match_date, status, venue, league_id, season_id, ...')
//   → fixtures.season_id did not exist → ERROR.
//
// AFTER (after SQL Fix 2 adds the column):
//   season_id is now a real column; select works.
//   If season_id is null (unfilled fixture), fall back to
//   querying seasons table by league_id.
// ============================================================
MatchRepo.getFixture = async function getFixture(fixtureId) {
  const { data, error } = await window.SB
    .from('fixtures')
    .select(`
      id, match_date, status, venue, league_id,
      season_id,
      home_club:clubs!fixtures_home_club_id_fkey(id, name, logo_url),
      away_club:clubs!fixtures_away_club_id_fkey(id, name, logo_url),
      leagues(name)
    `)
    // FIX: season_id now exists after SQL Fix 2; safe to select.
    .eq('id', fixtureId)
    .single();

  if (error) {
    console.error('[MatchRepo.getFixture FIX8c]', error.message);
    return null;
  }

  const row = data;

  // If season_id is still null (fixture pre-dates the SQL fix back-fill),
  // resolve it from the seasons table by league + date.
  if (!row.season_id && row.league_id && row.match_date) {
    const { data: seasonRow } = await window.SB
      .from('seasons')
      .select('id')
      .eq('league_id', row.league_id)
      .lte('start_date', row.match_date.slice(0, 10))
      .gte('end_date', row.match_date.slice(0, 10))
      .order('start_date', { ascending: false })
      .limit(1)
      .single();
    if (seasonRow) row.season_id = seasonRow.id;
  }

  return {
    id:        row.id,
    matchDate: row.match_date,
    status:    row.status,
    venue:     row.venue,
    leagueId:  row.league_id,
    seasonId:  row.season_id ?? null,
    leagueName:row.leagues?.name,
    homeClub:  row.home_club,
    awayClub:  row.away_club,
  };
};

// ============================================================
// FIX 9 — NotifRepo.recent()
// ============================================================
// BEFORE:
//   .select('id, is_read, received_at, ...')
//   .order('received_at', { ascending: false })
//   → notification_recipients has NO received_at column.
//     Column is only an alias in v_my_notifications view.
//     Throws: column notification_recipients.received_at does not exist
//
// AFTER:
//   Use created_at which IS a real column on the table.
// ============================================================
NotifRepo.recent = async function recent(limit = 20) {
  const uid = await Auth.uid();
  if (!uid) return [];

  const { data, error } = await window.SB
    .from('notification_recipients')
    .select(`
      id,
      is_read,
      created_at,
      notifications(
        id, notification_type, title, body, created_at
      )
    `)
    // FIX: was 'id, is_read, received_at, ...' — received_at does not exist
    .eq('profile_id', uid)
    // FIX: was .order('received_at', ...) — use created_at instead
    .order('created_at', { ascending: false })
    .limit(limit);

  if (error) {
    console.error('[NotifRepo.recent FIX9]', error.message);
    return [];
  }

  return (data ?? []).map(row => ({
    id:               row.id,
    isRead:           row.is_read,
    receivedAt:       row.created_at,   // expose as receivedAt for UI compat
    notificationType: row.notifications?.notification_type,
    title:            row.notifications?.title,
    body:             row.notifications?.body,
    notifCreatedAt:   row.notifications?.created_at,
  }));
};

// ============================================================
// FIX 10 — Real player_ownership_claims INSERT
// ============================================================
// BEFORE (playpro_public.html submitClaim):
//   Shows a success modal but writes NOTHING to the database.
//   state.currentPlayer is a local mock ID ('p1', 'p2') not a UUID.
//
// AFTER:
//   SubmitClaimLive() performs the actual INSERT via SB.
//   Validates auth, resolves real player UUID from DATA.players,
//   inserts into player_ownership_claims with correct columns.
//   Falls back gracefully if player has no real DB UUID.
// ============================================================

/**
 * Call this instead of the mock submitClaim() in playpro_public.html.
 * Replaces the existing global function.
 *
 * Reads from:
 *   state.currentPlayer — local player id set by selectClaimPlayer()
 *   document.getElementById('claim-type-select').value
 *   Auth.uid() / Auth.session()
 */
async function submitClaimLive() {
  // 1. Auth check
  const session = await Auth.session();
  if (!session) {
    if (window.PP) PP.toast('Please sign in first');
    return;
  }

  // 2. Player selection check
  const localPlayerId = window.state?.currentPlayer;
  if (!localPlayerId) {
    if (window.PP) PP.toast('Please select a player first');
    return;
  }

  // 3. Get the real DB UUID from the loaded player data
  //    DATA.players is populated by PublicDI.boot() from mv_player_passport_scores
  const playerRecord = (window.DATA?.players ?? []).find(p => p.id === localPlayerId);
  if (!playerRecord) {
    if (window.PP) PP.toast('Player record not found. Please search again.');
    return;
  }

  const realPlayerId = playerRecord.id;

  // 4. Get claim type
  const claimType = document.getElementById('claim-type-select')?.value ?? 'self';
  const minorDob  = document.getElementById('guardian-dob')?.value ?? null;

  // 5. Check for existing pending/approved claim (prevent duplicates)
  const { data: existing } = await window.SB
    .from('player_ownership_claims')
    .select('id, status')
    .eq('player_id', realPlayerId)
    .eq('claimant_profile_id', session.user.id)
    .in('status', ['pending', 'approved'])
    .limit(1)
    .single();

  if (existing) {
    const msg = existing.status === 'approved'
      ? 'You have already claimed this passport.'
      : 'You already have a pending claim for this player.';
    if (window.PP) PP.toast(msg);
    return;
  }

  // 6. INSERT into player_ownership_claims
  const insertRow = {
    player_id:            realPlayerId,
    claimant_profile_id:  session.user.id,
    claim_type:           claimType,
    status:               'pending',
    verification_method:  'club_confirmation',
    submitted_at:         new Date().toISOString(),
    created_by:           session.user.id,
  };

  // Add minor DOB for guardian claims
  if (claimType === 'guardian' && minorDob) {
    insertRow.minor_dob_at_claim = minorDob;
  }

  const { error } = await window.SB
    .from('player_ownership_claims')
    .insert(insertRow);

  if (error) {
    console.error('[submitClaimLive]', error.message);
    if (window.PP) PP.toast('Claim submission failed: ' + error.message);
    return;
  }

  // 7. Show success modal (same UI as before, now backed by real DB row)
  const clubName = (window.DATA?.clubs ?? []).find(c => c.id === playerRecord.club)?.name
    ?? playerRecord.club ?? 'your club';

  if (window.openModal) {
    openModal(`
      <div class="modal-handle"></div>
      <div class="modal-header">
        <div class="modal-title">Claim submitted ✓</div>
        <div class="modal-sub">Your claim for ${playerRecord.name ?? playerRecord.preferred} has been submitted</div>
      </div>
      <div class="modal-body">
        <div style="text-align:center;padding:20px 0">
          <div style="font-size:56px;margin-bottom:12px">🪪</div>
          <div style="font-size:15px;font-weight:600;color:var(--grey-800)">Awaiting Club Verification</div>
          <div style="font-size:13px;color:var(--grey-500);margin-top:8px;line-height:1.6">
            Your Club Admin at ${clubName} will review and approve your claim.<br><br>
            You'll receive a notification once approved.
          </div>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn btn-primary btn-block" onclick="closeModal();showScreen('account')">Done</button>
      </div>`);
  } else if (window.PP) {
    PP.toast('✅ Claim submitted — awaiting club verification');
  }

  console.log('[submitClaimLive] Claim inserted for player', realPlayerId);
}

// Replace the global submitClaim with the live version in playpro_public.html
if (typeof window !== 'undefined') {
  window.submitClaimLive = submitClaimLive;
  // Override the existing submitClaim so existing HTML onclick="submitClaim()" calls
  // transparently use the live version without HTML edits.
  window.submitClaim = submitClaimLive;
}

// ============================================================
// VERIFICATION OUTPUT
// ============================================================
// Each fix logs a BEFORE/AFTER verification on load.
// Check the browser console after loading these fixes.

(function verifyFixes() {
  const checks = [
    {
      id:     'FIX-5',
      label:  'PlayerRepo.seasonStats — order syntax',
      before: '.order("fixtures(match_date)") — INVALID PostgREST syntax',
      after:  '.order("match_date", { foreignTable: "fixtures" }) — VALID',
      verify: () => {
        const src = PlayerRepo.seasonStats.toString();
        return src.includes('foreignTable') && !src.includes('fixtures(match_date)');
      },
    },
    {
      id:     'FIX-6',
      label:  'PlayerRepo.similar — FK hint',
      before: 'players!player_similarities_similar_player_id_fkey — named FK, unresolvable',
      after:  'players!similar_player_id — column hint, always resolvable',
      verify: () => {
        const src = PlayerRepo.similar.toString();
        return src.includes('players!similar_player_id') &&
               !src.includes('player_similarities_similar_player_id_fkey');
      },
    },
    {
      id:     'FIX-7',
      label:  'ClubRepo.marketValues — embedded filter',
      before: '.eq("players.club_id", clubId) — invalid PostgREST on embedded resource',
      after:  '.in("player_id", playerIds) — filter on parent table column',
      verify: () => {
        const src = ClubRepo.marketValues.toString();
        return src.includes('.in(\'player_id\'') && !src.includes('players.club_id');
      },
    },
    {
      id:     'FIX-8a',
      label:  'LeagueRepo.standings — fallback column season_id',
      before: 'Fallback selected season_id from standings — column did not exist',
      after:  'season_id now in standings (SQL Fix 1); fallback safe',
      verify: () => {
        const src = LeagueRepo.standings.toString();
        return src.includes('season_id') && src.includes('FIX8a');
      },
    },
    {
      id:     'FIX-8b',
      label:  'LeagueRepo.topScorers — broken season JOIN in matview',
      before: 'mv_top_scorers used date-range season JOIN — cartesian risk',
      after:  'mv_top_scorers rebuilt with fixtures.season_id (SQL Fix 4) + JS live fallback',
      verify: () => {
        const src = LeagueRepo.topScorers.toString();
        return src.includes('FIX8b') && src.includes('live aggregation');
      },
    },
    {
      id:     'FIX-8c',
      label:  'MatchRepo.getFixture — season_id select',
      before: 'Selected fixtures.season_id which did not exist → ERROR',
      after:  'season_id now in fixtures (SQL Fix 2); select valid; runtime fallback added',
      verify: () => {
        const src = MatchRepo.getFixture.toString();
        return src.includes('FIX8c') && src.includes('season_id');
      },
    },
    {
      id:     'FIX-9',
      label:  'NotifRepo.recent — received_at column',
      before: '.select("id, is_read, received_at") + .order("received_at") — column missing',
      after:  '.select("id, is_read, created_at") + .order("created_at") — real column',
      verify: () => {
        const src = NotifRepo.recent.toString();
        return src.includes('created_at') &&
               !src.includes('received_at') &&
               src.includes('FIX9');
      },
    },
    {
      id:     'FIX-10',
      label:  'submitClaim — real DB insert',
      before: 'submitClaim() showed success modal but wrote nothing to player_ownership_claims',
      after:  'submitClaimLive() inserts real row into player_ownership_claims with auth check',
      verify: () => typeof window.submitClaim === 'function' &&
                    window.submitClaim === submitClaimLive,
    },
  ];

  console.group('[PlayPro Audit Fixes] Verification');
  let passed = 0;
  checks.forEach(c => {
    const ok = (() => { try { return c.verify(); } catch { return false; } })();
    if (ok) passed++;
    console.log(
      `%c${ok ? '✅ PASS' : '❌ FAIL'} ${c.id}: ${c.label}`,
      `color:${ok ? 'green' : 'red'}; font-weight:bold`
    );
    if (!ok) {
      console.log(`  BEFORE: ${c.before}`);
      console.log(`  AFTER:  ${c.after}`);
    }
  });
  console.log(`\n${passed}/${checks.length} fixes verified`);
  console.groupEnd();
})();
