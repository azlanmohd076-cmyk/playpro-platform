/**
 * PlayPro — Supabase Client
 * Singleton client + auth helpers + session management
 *
 * Usage:
 *   <script src="supabase.js"></script>
 *   const { data, error } = await SB.from('players').select('*')
 *   const { data, error } = await SB.rpc('search_players', { p_position: 'midfielder' })
 *   const session = await Auth.session()
 */

'use strict';

/* ── Environment ──────────────────────────────────────────────── */
const PLAYPRO_CONFIG = {
  /* Replace with your real project values.
     In production, inject via a build-time env or a small
     /config endpoint served by Supabase Edge Functions.      */
  supabaseUrl:     window.PLAYPRO_SUPABASE_URL     || 'https://YOUR_PROJECT.supabase.co',
  supabaseAnonKey: window.PLAYPRO_SUPABASE_ANON_KEY || 'YOUR_ANON_KEY',

  /* App settings */
  authRedirectUrl: window.PLAYPRO_SUPABASE_REDIRECT_URL || `${window.location.origin}/auth/callback`,
  defaultPageSize: 50,
  cacheTtlMs:      30_000,   // 30 s in-memory cache for read-heavy queries
};

/* ── Bootstrap Supabase JS from CDN (injected at runtime) ─────── */
/*
 * The Supabase JS client is loaded via a single <script> tag that
 * the page HTML must include BEFORE this file:
 *
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
 *   <script src="supabase.js"></script>
 *
 * We access it via the global `supabase` namespace the CDN exposes.
 */
/* ── Singleton Client ─────────────────────────────────────────── */
// Publish the client on window as well as the legacy global name. This avoids
// a ReferenceError when the static HTML calls SB before module code runs.
var SB = window.SB;
var supabaseSdk = window.supabase;

if (!SB && supabaseSdk && typeof supabaseSdk.createClient === 'function') {
  SB = supabaseSdk.createClient(
    PLAYPRO_CONFIG.supabaseUrl,
    PLAYPRO_CONFIG.supabaseAnonKey,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        flowType: 'pkce',
      },
      realtime: { params: { eventsPerSecond: 10 } },
      global: {
        headers: { 'x-application-name': 'playpro-dashboard' },
      },
    }
  );
}

if (!SB) {
  console.error('[PlayPro] Supabase client unavailable; using safe empty client.');
  const emptyQuery = () => ({
    select: emptyQuery, eq: emptyQuery, neq: emptyQuery, in: emptyQuery,
    order: emptyQuery, limit: emptyQuery, maybeSingle: async () => ({ data: null, error: null }),
    single: async () => ({ data: null, error: null }), then: (resolve) => resolve({ data: [], error: null }),
  });
  SB = {
    from: emptyQuery,
    rpc: async () => ({ data: null, error: null }),
    auth: {
      getSession: async () => ({ data: { session: null }, error: null }),
      getUser: async () => ({ data: { user: null }, error: null }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
      signInWithPassword: async () => ({ data: { session: null, user: null }, error: null }),
      signUp: async () => ({ data: { session: null, user: null }, error: null }),
      signOut: async () => ({ error: null }),
    },
  };
}

window.SB = SB;

/* ── Simple in-memory cache ───────────────────────────────────── */
const _cache = new Map();

function _cacheGet(key) {
  const hit = _cache.get(key);
  if (!hit) return null;
  if (Date.now() - hit.ts > PLAYPRO_CONFIG.cacheTtlMs) { _cache.delete(key); return null; }
  return hit.data;
}
function _cacheSet(key, data) {
  _cache.set(key, { data, ts: Date.now() });
}
function cacheInvalidate(prefix) {
  for (const k of _cache.keys()) { if (k.startsWith(prefix)) _cache.delete(k); }
}

/* ── Auth helpers ─────────────────────────────────────────────── */
const Auth = {

  /** Returns the current session or null. */
  async session() {
    const { data: { session } } = await SB.auth.getSession();
    return session;
  },

  /** Returns the current user profile row from `profiles` table, or null. */
  async profile() {
    const session = await Auth.session();
    if (!session) return null;
    const cached = _cacheGet('profile:' + session.user.id);
    if (cached) return cached;
    const { data, error } = await SB
      .from('profiles')
      .select('id, full_name, email, role, avatar_url, is_active')
      .eq('id', session.user.id)
      .single();
    if (error) { console.error('[Auth.profile]', error.message); return null; }
    _cacheSet('profile:' + session.user.id, data);
    return data;
  },

  /** Sign in with email + password. Returns { session, error }. */
  async signIn(email, password) {
    const { data, error } = await SB.auth.signInWithPassword({ email, password });
    if (!error) cacheInvalidate('profile:');
    return { session: data?.session ?? null, error };
  },

  /** Sign out the current user. */
  async signOut() {
    cacheInvalidate('profile:');
    return SB.auth.signOut();
  },

  /** Register a new user. Returns { session, error }. */
  async signUp(email, password, meta = {}) {
    return SB.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: PLAYPRO_CONFIG.authRedirectUrl,
        data: meta,
      },
    });
  },

  /** Listen to auth state changes. */
  onStateChange(cb) {
    return SB.auth.onAuthStateChange(cb);
  },

  /** Returns the current user's UUID or null. */
  async uid() {
    const s = await Auth.session();
    return s?.user?.id ?? null;
  },

  /** Returns true if the current user has one of the given roles. */
  async hasRole(...roles) {
    const p = await Auth.profile();
    return p ? roles.includes(p.role) : false;
  },
};

/* ── Error handler ────────────────────────────────────────────── */
function _handle(label, { data, error }) {
  if (error) {
    console.error(`[PlayPro:${label}]`, error.message, error.details ?? '');
    return null;
  }
  return data;
}

/* ── Realtime subscription helper ─────────────────────────────── */
const Realtime = {
  /**
   * Subscribe to INSERT/UPDATE/DELETE on any table scoped to a
   * user's club. Returns the channel object (call .unsubscribe() to clean up).
   *
   *   const ch = Realtime.clubFeed(clubId, (payload) => console.log(payload))
   *   // later:
   *   ch.unsubscribe()
   */
  clubFeed(clubId, cb) {
    return SB
      .channel('club-feed-' + clubId)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: 'match_events',
        filter: `club_id=eq.${clubId}`,
      }, cb)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: 'player_fitness_snapshots',
      }, cb)
      .subscribe();
  },

  /** Subscribe to notifications for the current user. */
  notifications(profileId, cb) {
    return SB
      .channel('notif-' + profileId)
      .on('postgres_changes', {
        event: 'INSERT', schema: 'public', table: 'notification_recipients',
        filter: `profile_id=eq.${profileId}`,
      }, cb)
      .subscribe();
  },

  /** Subscribe to live fixture score updates. */
  fixtureFeed(fixtureId, cb) {
    return SB
      .channel('fixture-' + fixtureId)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: 'match_events',
        filter: `fixture_id=eq.${fixtureId}`,
      }, cb)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: 'match_results',
        filter: `fixture_id=eq.${fixtureId}`,
      }, cb)
      .subscribe();
  },
};

/* ── Player profile hotfixes ──────────────────────────────────── */
/*
 * The profile UI is currently a legacy monolith, so these bindings
 * provide the missing live behaviour without changing unrelated modules.
 * Counts come from the canonical player-profile RPC; follow mutations
 * use the existing server-side follow_player/unfollow_player RPCs.
 */
async function _refreshPlayerFollowerCount(playerId) {
  if (!playerId || !SB?.rpc) return null;
  const { data, error } = await SB.rpc('get_player_profile', { p_player_id: playerId });
  if (error) {
    console.error('[PlayPro:followers]', error.message);
    return null;
  }
  const count = Number(data?.player?.follower_count ?? 0);
  const el = document.getElementById('count-followers-val');
  if (el) el.textContent = count.toLocaleString('en-US');
  return { count, profile: data };
}

async function aksiToggleFollowPlayer(playerId) {
  const pid = playerId || window._pd?.id || window.currentPlayerId;
  if (!pid) return;
  const { data: { user } = {} } = await SB.auth.getUser();
  if (!user) {
    if (typeof window.mustLogin === 'function') window.mustLogin();
    else if (typeof window.showLogin === 'function') window.showLogin();
    return;
  }

  const { data: profileData, error: profileError } = await SB.rpc('get_player_profile', { p_player_id: pid });
  if (profileError) {
    console.error('[PlayPro:follow]', profileError.message);
    if (typeof window.toast === 'function') window.toast('⚠️ Gagal mendapatkan status follow.');
    return;
  }

  const currentStatus = profileData?.follow_status || 'none';
  let result;
  if (currentStatus === 'approved' || currentStatus === 'pending') {
    result = await SB.rpc('unfollow_player', { p_player_id: pid });
  } else {
    result = await SB.rpc('follow_player', { p_player_id: pid });
  }

  if (result.error) {
    console.error('[PlayPro:follow]', result.error.message);
    if (typeof window.toast === 'function') window.toast('⚠️ ' + result.error.message);
    return;
  }

  const fresh = await _refreshPlayerFollowerCount(pid);
  const nextStatus = result.data?.status || (currentStatus === 'approved' || currentStatus === 'pending' ? 'none' : 'approved');
  const btn = document.getElementById('btn-follow-action');
  if (btn) {
    btn.textContent = nextStatus === 'approved' ? '✓ FOLLOWING' : nextStatus === 'pending' ? 'REQUESTED' : '+ FOLLOW';
  }
  if (typeof window.toast === 'function') {
    window.toast(nextStatus === 'approved' ? '✅ Mengikuti pemain.' : nextStatus === 'pending' ? '📨 Permintaan follow dihantar.' : '✓ Follow dibatalkan.');
  }
  return fresh;
}

function updateFollowButtonStateForProfile(playerOrId, isOwnProfile) {
  const player = (playerOrId && typeof playerOrId === 'object') ? playerOrId : null;
  const pid = player?.id || playerOrId || window._pd?.id || window.currentPlayerId;
  const own = isOwnProfile ?? Boolean(player?.profile_id && window._u?.id && player.profile_id === window._u.id);
  const btn = document.getElementById('btn-follow-action');
  if (!btn) return;

  if (own) {
    btn.style.display = 'none';
  } else {
    btn.style.display = '';
    const status = player?.follow_status || 'none';
    btn.textContent = status === 'approved' ? '✓ FOLLOWING' : status === 'pending' ? 'REQUESTED' : '+ FOLLOW';
  }

  const count = Number(player?.follower_count ?? 0);
  const countEl = document.getElementById('count-followers-val');
  if (countEl) countEl.textContent = count.toLocaleString('en-US');
  if (pid && !player?.follower_count && !own) _refreshPlayerFollowerCount(pid);
}

/* The legacy profile function queries old view column names. Replace only
 * that binding after the page scripts have declared it, using the live view:
 * profile_id, club_id, joined_at, left_at, status, club_name. */
function _installPlayerClubHistoryFix() {
  if (typeof window.renderClubHistory2 !== 'function') return;
  window.renderClubHistory2 = function(p) {
    const el = document.getElementById('club2-list');
    if (!el) return;
    el.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--mute);font-size:.75rem">Memuatkan sejarah kelab...</div>';
    const profileId = p?.profile_id || p?.profileId || null;
    if (!profileId) {
      el.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--mute);font-size:.75rem">Tiada sejarah kelab.</div>';
      return;
    }
    SB.from('player_club_history')
      .select('profile_id,club_id,joined_at,left_at,status,club_name')
      .eq('profile_id', profileId)
      .order('joined_at', { ascending: false, nullsFirst: false })
      .then(function({ data, error }) {
        if (error) {
          console.error('[PlayPro:club-history]', error.message);
          el.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--mute);font-size:.75rem">Sejarah kelab tidak dapat dimuatkan.</div>';
          return;
        }
        if (!data?.length) {
          el.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--mute);font-size:.75rem">Tiada sejarah kelab.</div>';
          return;
        }
        el.innerHTML = data.map(function(row) {
          const joined = row.joined_at ? new Date(row.joined_at).getFullYear() : '—';
          const left = row.left_at ? new Date(row.left_at).getFullYear() : 'Kini';
          const status = row.status ? String(row.status).toUpperCase() : '';
          return '<div class="club2-item">'
            + '<div style="display:flex;align-items:center;justify-content:space-between;gap:.6rem">'
            + '<div style="font-weight:800;color:var(--txt)">' + (row.club_name || 'Kelab') + '</div>'
            + '<div style="font-size:.62rem;color:var(--mute)">' + joined + ' — ' + left + '</div>'
            + '</div>'
            + (status ? '<div style="font-size:.58rem;color:var(--g);font-weight:700;margin-top:.25rem">' + status + '</div>' : '')
            + '</div>';
        }).join('');
      });
  };
}

if (typeof window !== 'undefined') {
  window.SB        = SB;
  window.Auth      = Auth;
  window.Realtime  = Realtime;
  window._ppCache  = { invalidate: cacheInvalidate };
  window.aksiToggleFollowPlayer = aksiToggleFollowPlayer;
  window.updateFollowButtonStateForProfile = updateFollowButtonStateForProfile;
  window._refreshPlayerFollowerCount = _refreshPlayerFollowerCount;

  /* index.html declares renderClubHistory2 later in the same document. */
  window.addEventListener('DOMContentLoaded', function() {
    _installPlayerClubHistoryFix();
    if (window._pd?.id) _refreshPlayerFollowerCount(window._pd.id);
  });
}
