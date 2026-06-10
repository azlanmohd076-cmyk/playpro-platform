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
if (typeof supabase === 'undefined') {
  console.error('[PlayPro] Supabase JS not loaded. Add the CDN <script> before supabase.js.');
}

/* ── Singleton Client ─────────────────────────────────────────── */
const SB = supabase.createClient(
  PLAYPRO_CONFIG.supabaseUrl,
  PLAYPRO_CONFIG.supabaseAnonKey,
  {
    auth: {
      persistSession:    true,
      autoRefreshToken:  true,
      detectSessionInUrl: true,
    },
    realtime: { params: { eventsPerSecond: 10 } },
    global: {
      headers: { 'x-application-name': 'playpro-dashboard' },
    },
  }
);

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
    return SB.auth.signUp({ email, password, options: { data: meta } });
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

/* ── Expose globals ───────────────────────────────────────────── */
window.SB        = SB;
window.Auth      = Auth;
window.Realtime  = Realtime;
window._ppCache  = { invalidate: cacheInvalidate };
