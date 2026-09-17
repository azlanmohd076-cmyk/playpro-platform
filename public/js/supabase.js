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
  supabaseUrl:     window.PLAYPRO_SUPABASE_URL     || 'https://YOUR_PROJECT.supabase.co',
  supabaseAnonKey: window.PLAYPRO_SUPABASE_ANON_KEY || 'YOUR_ANON_KEY',
  authRedirectUrl: window.PLAYPRO_SUPABASE_REDIRECT_URL || `${window.location.origin}/auth/callback`,
  defaultPageSize: 50,
  cacheTtlMs:      30_000,
};

/* ── Bootstrap Supabase JS from CDN ───────────────────────────── */
var SB = window.SB;
var supabaseSdk = window.supabase;
if (!SB && supabaseSdk && typeof supabaseSdk.createClient === 'function') {
  SB = supabaseSdk.createClient(PLAYPRO_CONFIG.supabaseUrl, PLAYPRO_CONFIG.supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce' },
    realtime: { params: { eventsPerSecond: 10 } },
    global: { headers: { 'x-application-name': 'playpro-dashboard' } },
  });
}
if (!SB) {
  console.error('[PlayPro] Supabase client unavailable; using safe empty client.');
  const emptyQuery = () => ({
    select: emptyQuery, eq: emptyQuery, neq: emptyQuery, in: emptyQuery, order: emptyQuery, limit: emptyQuery,
    maybeSingle: async () => ({ data: null, error: null }), single: async () => ({ data: null, error: null }),
    then: (resolve) => resolve({ data: [], error: null }),
  });
  SB = {
    from: emptyQuery, rpc: async () => ({ data: null, error: null }),
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
function _cacheSet(key, data) { _cache.set(key, { data, ts: Date.now() }); }
function cacheInvalidate(prefix) { for (const k of _cache.keys()) if (k.startsWith(prefix)) _cache.delete(k); }

/* ── Auth helpers ─────────────────────────────────────────────── */
const Auth = {
  async session() { const { data: { session } } = await SB.auth.getSession(); return session; },
  async profile() {
    const session = await Auth.session(); if (!session) return null;
    const cached = _cacheGet('profile:' + session.user.id); if (cached) return cached;
    const { data, error } = await SB.from('profiles').select('id, full_name, email, role, avatar_url, is_active').eq('id', session.user.id).single();
    if (error) { console.error('[Auth.profile]', error.message); return null; }
    _cacheSet('profile:' + session.user.id, data); return data;
  },
  async signIn(email, password) { const { data, error } = await SB.auth.signInWithPassword({ email, password }); if (!error) cacheInvalidate('profile:'); return { session: data?.session ?? null, error }; },
  async signOut() { cacheInvalidate('profile:'); return SB.auth.signOut(); },
  async signUp(email, password, meta = {}) { return SB.auth.signUp({ email, password, options: { emailRedirectTo: PLAYPRO_CONFIG.authRedirectUrl, data: meta } }); },
  onStateChange(cb) { return SB.auth.onAuthStateChange(cb); },
  async uid() { const s = await Auth.session(); return s?.user?.id ?? null; },
  async hasRole(...roles) { const p = await Auth.profile(); return p ? roles.includes(p.role) : false; },
};

/* ── Global login guard ───────────────────────────────────────── */
async function mustLogin(nextUrl = window.location.href) {
  const session = await Auth.session();
  if (session) return true;
  const loginUrl = new URL('/player_signup.html', window.location.origin);
  if (nextUrl) loginUrl.searchParams.set('next', nextUrl);
  window.location.assign(loginUrl.href); return false;
}
window.mustLogin = mustLogin;

function _handle(label, { data, error }) { if (error) { console.error(`[PlayPro:${label}]`, error.message, error.details ?? ''); return null; } return data; }

/* ── Realtime subscription helper ─────────────────────────────── */
const Realtime = {
  clubFeed(clubId, cb) { return SB.channel('club-feed-' + clubId).on('postgres_changes', { event: '*', schema: 'public', table: 'match_events', filter: `club_id=eq.${clubId}` }, cb).on('postgres_changes', { event: '*', schema: 'public', table: 'player_fitness_snapshots' }, cb).subscribe(); },
  notifications(profileId, cb) { return SB.channel('notif-' + profileId).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notification_recipients', filter: `profile_id=eq.${profileId}` }, cb).subscribe(); },
  fixtureFeed(fixtureId, cb) { return SB.channel('fixture-' + fixtureId).on('postgres_changes', { event: '*', schema: 'public', table: 'match_events', filter: `fixture_id=eq.${fixtureId}` }, cb).on('postgres_changes', { event: '*', schema: 'public', table: 'match_results', filter: `fixture_id=eq.${fixtureId}` }, cb).subscribe(); },
};

/* ── Player profile live fixes ────────────────────────────────── */
async function _refreshPlayerFollowerCount(playerId) {
  if (!playerId || !SB?.rpc) return null;
  const { data, error } = await SB.rpc('get_player_profile', { p_player_id: playerId });
  if (error) { console.error('[PlayPro:followers]', error.message); return null; }
  const count = Number(data?.player?.follower_count ?? 0);
  const el = document.getElementById('count-followers-val');
  if (el) el.textContent = count.toLocaleString('en-US');
  return { count, profile: data };
}

async function aksiToggleFollowPlayer(playerId) {
  const pid = playerId || window._pd?.id || window.currentPlayerId;
  if (!pid) return;
  const { data: { user } = {} } = await SB.auth.getUser();
  if (!user) { if (typeof window.mustLogin === 'function') window.mustLogin(); else if (typeof window.showLogin === 'function') window.showLogin(); return; }
  const { data: profileData, error: profileError } = await SB.rpc('get_player_profile', { p_player_id: pid });
  if (profileError) { console.error('[PlayPro:follow]', profileError.message); if (typeof window.toast === 'function') window.toast('⚠️ Gagal mendapatkan status follow.'); return; }
  const currentStatus = profileData?.follow_status || 'none';
  const result = (currentStatus === 'approved' || currentStatus === 'pending') ? await SB.rpc('unfollow_player', { p_player_id: pid }) : await SB.rpc('follow_player', { p_player_id: pid });
  if (result.error) { console.error('[PlayPro:follow]', result.error.message); if (typeof window.toast === 'function') window.toast('⚠️ ' + result.error.message); return; }
  const fresh = await _refreshPlayerFollowerCount(pid);
  const nextStatus = result.data?.status || ((currentStatus === 'approved' || currentStatus === 'pending') ? 'none' : 'approved');
  const btn = document.getElementById('btn-follow-action') || document.getElementById('follow-btn');
  if (btn) btn.textContent = nextStatus === 'approved' ? '✓ FOLLOWING' : nextStatus === 'pending' ? 'REQUESTED' : '+ FOLLOW';
  if (typeof window.toast === 'function') window.toast(nextStatus === 'approved' ? '✅ Mengikuti pemain.' : nextStatus === 'pending' ? '📨 Permintaan follow dihantar.' : '✓ Follow dibatalkan.');
  return fresh;
}

function updateFollowButtonStateForProfile(playerOrId, isOwnProfile) {
  const player = (playerOrId && typeof playerOrId === 'object') ? playerOrId : null;
  const pid = player?.id || playerOrId || window._pd?.id || window.currentPlayerId;
  const own = isOwnProfile ?? Boolean(player?.profile_id && window._u?.id && player.profile_id === window._u.id);
  const btn = document.getElementById('btn-follow-action') || document.getElementById('follow-btn');
  if (btn) { btn.style.display = own ? 'none' : ''; if (!own) { const status = player?.follow_status || 'none'; btn.textContent = status === 'approved' ? '✓ FOLLOWING' : status === 'pending' ? 'REQUESTED' : '+ FOLLOW'; } }
  const count = Number(player?.follower_count ?? NaN);
  const countEl = document.getElementById('count-followers-val');
  if (countEl && Number.isFinite(count)) countEl.textContent = count.toLocaleString('en-US');
  if (pid && !Number.isFinite(count) && !own) _refreshPlayerFollowerCount(pid);
}

/* Live view columns: profile_id, club_id, joined_at, left_at, status, club_name.
 * Legacy index.html queried player_id/year_from/year_to/is_current/is_verified,
 * which is the direct cause of the PostgREST 400 seen in production. */
function _installPlayerClubHistoryFix() {
  const install = () => {
    if (typeof window.renderClubHistory2 !== 'function') return false;
    window.renderClubHistory2 = function(p) {
      const el = document.getElementById('club2-list'); if (!el) return;
      el.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--mute);font-size:.75rem">Memuatkan sejarah kelab...</div>';
      const profileId = p?.profile_id || p?.profileId || null;
      if (!profileId) { el.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--mute);font-size:.75rem">Tiada sejarah kelab.</div>'; return; }
      SB.from('player_club_history').select('profile_id,club_id,joined_at,left_at,status,club_name').eq('profile_id', profileId).order('joined_at', { ascending: false, nullsFirst: false }).then(({ data, error }) => {
        if (error) { console.error('[PlayPro:club-history]', error.message); el.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--mute);font-size:.75rem">Sejarah kelab tidak dapat dimuatkan.</div>'; return; }
        if (!data?.length) { el.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--mute);font-size:.75rem">Tiada sejarah kelab.</div>'; return; }
        el.innerHTML = data.map(row => {
          const joined = row.joined_at ? new Date(row.joined_at).getFullYear() : '—';
          const left = row.left_at ? new Date(row.left_at).getFullYear() : 'Kini';
          const status = row.status ? String(row.status).toUpperCase() : '';
          return '<div class="club2-item"><div style="display:flex;align-items:center;justify-content:space-between;gap:.6rem"><div style="font-weight:800;color:var(--txt)">' + (row.club_name || 'Kelab') + '</div><div style="font-size:.62rem;color:var(--mute)">' + joined + ' — ' + left + '</div></div>' + (status ? '<div style="font-size:.58rem;color:var(--g);font-weight:700;margin-top:.25rem">' + status + '</div>' : '') + '</div>';
        }).join('');
      });
    };
    return true;
  };
  if (install()) return;
  let tries = 0;
  const timer = window.setInterval(() => { if (install() || ++tries >= 20) window.clearInterval(timer); }, 100);
}

/* Replace the legacy 1,284 DOM seed with the live canonical follower_count. */
function _installPlayerFollowerSync() {
  const sync = () => { const pid = window._pd?.id || window.currentPlayerId; if (pid) { _refreshPlayerFollowerCount(pid); return true; } return false; };
  if (sync()) return;
  let tries = 0;
  const timer = window.setInterval(() => { if (sync() || ++tries >= 30) window.clearInterval(timer); }, 250);
}

/* ── Expose globals ───────────────────────────────────────────── */
window.SB = SB;
window.Auth = Auth;
window.Realtime = Realtime;
window._ppCache = { invalidate: cacheInvalidate };
window.aksiToggleFollowPlayer = aksiToggleFollowPlayer;
window.updateFollowButtonStateForProfile = updateFollowButtonStateForProfile;
window._refreshPlayerFollowerCount = _refreshPlayerFollowerCount;
window.addEventListener('DOMContentLoaded', function() { _installPlayerClubHistoryFix(); _installPlayerFollowerSync(); });

/* ── SPLASH FAIL-SAFE ─────────────────────────────────────────── */
(function installSplashFailsafe() {
  const release = () => { const splash = document.getElementById('splash'); if (!splash) return; splash.classList.add('fade'); window.setTimeout(() => { splash.style.display = 'none'; splash.setAttribute('aria-hidden', 'true'); }, 450); };
  window.setTimeout(release, 3000);
  window.addEventListener('error', () => release(), { once: true });
  window.addEventListener('unhandledrejection', () => release(), { once: true });
})();
