/*
 * PlayPro Model 6 — Auth Session Service
 * File: src/modules/auth/auth-session.service.js
 * Mirror: public/src/modules/auth/auth-session.service.js
 *
 * P0 repair (2026-07-26). Replaces the ad-hoc auth logic in
 * public/index.html doRegister()/doLogin().
 *
 * WHY THIS EXISTS
 *  1. The legacy client wrote profiles.role directly. Because
 *     handle_new_user() had already inserted the row, that upsert became
 *     an UPDATE and tripped trg_prevent_role_escalation (SQLSTATE 42501),
 *     so the profile write failed on EVERY signup.
 *  2. The legacy upsert omitted `email`, which is NOT NULL on profiles.
 *  3. The legacy catch was `catch(e){console.warn(...)}` — but supabase-js
 *     RESOLVES with {data,error} instead of throwing, so that catch block
 *     never ran. Every profile failure was invisible to the user AND to
 *     the developer.
 *  4. "Failed to fetch" is a NETWORK-LAYER failure (DNS/offline/CORS), not
 *     a credentials failure. It must be reported as such instead of being
 *     shown as a generic error.
 *
 * CONTRACT
 *   Role is owned by the database. This client NEVER writes profiles.role.
 *   Requires: database/model6_p0_auth_identity_repair.sql
 *
 * No build step. No bundler. Attaches to window.PlayProModel6.Auth.
 */
(function attachAuthSessionService(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};
  bridge.Auth = bridge.Auth || {};

  var SELF_SERVE_ROLES = ['player', 'coach', 'club_admin', 'league_admin', 'referee'];

  var ROLE_ALIASES = {
    pemain: 'player',
    jurulatih: 'coach',
    pengurus_kelab: 'club_admin',
    club_manager: 'club_admin',
    manager: 'club_admin',
    penganjur_liga: 'league_admin',
    pengadil: 'referee'
  };

  function getClient() {
    if (bridge.Core && typeof bridge.Core.getSupabase === 'function') {
      return bridge.Core.getSupabase();
    }
    return (bridge.Core && bridge.Core.supabase) || root.SB || null;
  }

  function normalizeRole(role) {
    var r = String(role || '').trim().toLowerCase();
    if (ROLE_ALIASES[r]) r = ROLE_ALIASES[r];
    return SELF_SERVE_ROLES.indexOf(r) === -1 ? 'player' : r;
  }

  /* ---------------------------------------------------------
   * Error classification.
   * The single most important function in this file: it turns an
   * opaque failure into an actionable one.
   * ------------------------------------------------------- */
  function classifyError(err) {
    if (!err) return null;

    var msg = String(err.message || err.error_description || err.error || err || '');
    var code = String(err.code || err.status || '');
    var low = msg.toLowerCase();

    // Network layer: fetch never reached the server.
    if (low.indexOf('failed to fetch') !== -1 ||
        low.indexOf('networkerror') !== -1 ||
        low.indexOf('load failed') !== -1 ||
        low.indexOf('err_name_not_resolved') !== -1 ||
        low.indexOf('name_not_resolved') !== -1) {
      return {
        kind: 'network',
        code: 'NETWORK_UNREACHABLE',
        userMessage:
          'Tidak dapat hubungi pelayan PlayPro. Ini masalah sambungan/pelayan, ' +
          'bukan kata laluan anda. Sila cuba sebentar lagi.',
        devMessage:
          'Fetch to Supabase failed at the network layer. Check: (1) project ' +
          'hostname resolves in DNS, (2) project not paused/deleted, ' +
          '(3) PLAYPRO_SUPABASE_URL correct, (4) site origin allowed in ' +
          'Supabase Auth URL config, (5) client online.',
        raw: msg
      };
    }

    if (code === '22P02' || low.indexOf('invalid input value for enum') !== -1) {
      return {
        kind: 'schema',
        code: 'ENUM_MISMATCH',
        userMessage: 'Peranan yang dipilih tidak sah. Sila hubungi sokongan PlayPro.',
        devMessage:
          'profiles.role received a value outside the user_role enum. Apply ' +
          'database/model6_p0_auth_identity_repair.sql (adds player + referee).',
        raw: msg
      };
    }

    if (code === '42501' || low.indexOf('permission denied') !== -1 ||
        low.indexOf('row-level security') !== -1 ||
        low.indexOf('cannot modify your own role') !== -1) {
      return {
        kind: 'permission',
        code: 'RLS_DENIED',
        userMessage: 'Akaun dibuat, tetapi profil gagal dikemas kini. Sila log masuk semula.',
        devMessage:
          'RLS/trigger rejected the write. Most likely the client attempted to ' +
          'write profiles.role (blocked by trg_prevent_role_escalation). Use ' +
          'the ensure_profile_after_signup RPC instead.',
        raw: msg
      };
    }

    if (code === '23502' || low.indexOf('null value in column') !== -1) {
      return {
        kind: 'schema',
        code: 'NOT_NULL_VIOLATION',
        userMessage: 'Data profil tidak lengkap. Sila hubungi sokongan PlayPro.',
        devMessage: 'A NOT NULL column (likely profiles.email) was omitted.',
        raw: msg
      };
    }

    if (code === '23505' || low.indexOf('duplicate key') !== -1 ||
        low.indexOf('already registered') !== -1) {
      return {
        kind: 'conflict',
        code: 'ALREADY_EXISTS',
        userMessage: 'Emel ini sudah didaftarkan. Sila log masuk atau guna "Lupa kata laluan?".',
        devMessage: 'Unique violation on profiles/auth.users.',
        raw: msg
      };
    }

    if (low.indexOf('invalid login') !== -1 || low.indexOf('credentials') !== -1) {
      return {
        kind: 'credentials',
        code: 'BAD_CREDENTIALS',
        userMessage: 'Emel atau kata laluan tidak tepat.',
        devMessage: 'Supabase rejected the credentials.',
        raw: msg
      };
    }

    if (low.indexOf('email not confirmed') !== -1) {
      return {
        kind: 'unconfirmed',
        code: 'EMAIL_NOT_CONFIRMED',
        userMessage: 'Emel belum disahkan. Sila semak inbox (dan folder spam).',
        devMessage: 'Auth requires email confirmation.',
        raw: msg
      };
    }

    if (low.indexOf('function') !== -1 &&
        (low.indexOf('does not exist') !== -1 || code === 'PGRST202')) {
      return {
        kind: 'schema',
        code: 'RPC_MISSING',
        userMessage: 'Sistem sedang dikemas kini. Sila cuba sebentar lagi.',
        devMessage:
          'RPC not found. Apply database/model6_p0_auth_identity_repair.sql, ' +
          'then reload the PostgREST schema cache.',
        raw: msg
      };
    }

    return {
      kind: 'unknown',
      code: code || 'UNKNOWN',
      userMessage: 'Ralat tidak dijangka: ' + msg,
      devMessage: 'Unclassified error.',
      raw: msg
    };
  }

  function fail(err, stage) {
    var info = classifyError(err);
    info.stage = stage;
    try {
      console.error('[PlayPro Auth] ' + stage + ' -> ' + info.code + ': ' + info.raw);
      if (info.devMessage) console.error('[PlayPro Auth] hint: ' + info.devMessage);
    } catch (ignore) {}
    return { ok: false, error: info };
  }

  function noClient(stage) {
    return fail(
      { message: 'Supabase client not initialised' },
      stage
    );
  }

  /* ---------------------------------------------------------
   * Preflight reachability probe.
   * Distinguishes "server unreachable" from "wrong password"
   * BEFORE the user is blamed for anything.
   * ------------------------------------------------------- */
  function preflight() {
    var url = root.PLAYPRO_SUPABASE_URL;
    var key = root.PLAYPRO_SUPABASE_ANON_KEY;
    if (!url || !key || typeof root.fetch !== 'function') {
      return Promise.resolve({ ok: true, skipped: true });
    }
    return root.fetch(url.replace(/\/+$/, '') + '/auth/v1/health', {
      method: 'GET',
      headers: { apikey: key }
    }).then(function (res) {
      return { ok: res.ok, status: res.status };
    }).catch(function (e) {
      return { ok: false, networkError: e };
    });
  }

  function ensureProfile(fullName, phone) {
    var SB = getClient();
    if (!SB) return Promise.resolve(noClient('ensureProfile'));

    return SB.rpc('ensure_profile_after_signup', {
      p_full_name: fullName || null,
      p_phone: phone || null
    }).then(function (res) {
      if (res.error) return fail(res.error, 'ensureProfile');
      return { ok: true, profile: res.data || null };
    }).catch(function (e) {
      return fail(e, 'ensureProfile');
    });
  }

  function getCurrentRole() {
    var SB = getClient();
    if (!SB) return Promise.resolve(noClient('getCurrentRole'));

    return SB.rpc('get_my_profile').then(function (res) {
      if (res.error) return fail(res.error, 'getCurrentRole');
      var profile = res.data || null;
      return {
        ok: true,
        profile: profile,
        role: profile ? normalizeRole(profile.role) : null
      };
    }).catch(function (e) {
      return fail(e, 'getCurrentRole');
    });
  }

  /* ---------------------------------------------------------
   * signUp — the P0 flow.
   * Order matters: auth -> profile confirmed -> role -> onboarding.
   * ------------------------------------------------------- */
  function signUp(opts) {
    opts = opts || {};
    var SB = getClient();
    if (!SB) return Promise.resolve(noClient('signUp'));

    var email = String(opts.email || '').trim();
    var password = String(opts.password || '');
    var fullName = String(opts.fullName || '').trim();
    var phone = String(opts.phone || '').trim();
    var role = normalizeRole(opts.role);

    if (!email || !password || !fullName) {
      return Promise.resolve({
        ok: false,
        error: {
          kind: 'validation', code: 'MISSING_FIELDS',
          userMessage: 'Sila isi nama, emel dan kata laluan.'
        }
      });
    }
    if (password.length < 8) {
      return Promise.resolve({
        ok: false,
        error: {
          kind: 'validation', code: 'WEAK_PASSWORD',
          userMessage: 'Kata laluan mesti 8 aksara ke atas.'
        }
      });
    }

    return preflight().then(function (health) {
      if (!health.ok && health.networkError) {
        return fail(health.networkError, 'signUp:preflight');
      }

      return SB.auth.signUp({
        email: email,
        password: password,
        options: { data: { full_name: fullName, role: role, phone: phone } }
      }).then(function (res) {
        if (res.error) return fail(res.error, 'signUp');

        var user = res.data && res.data.user;
        var session = res.data && res.data.session;

        // Email confirmation required: no session yet, so no profile
        // write is possible. The DB trigger already created the row.
        if (!session) {
          return {
            ok: true,
            pendingConfirmation: true,
            user: user || null,
            role: role,
            message: 'Akaun dibuat. Sila semak emel ' + email + ' untuk pengesahan.'
          };
        }

        // Session exists -> guarantee the profile row before any UI moves.
        return ensureProfile(fullName, phone).then(function (profRes) {
          if (!profRes.ok) {
            return {
              ok: false,
              partial: true,
              user: user || null,
              error: profRes.error,
              message:
                'Akaun auth dibuat tetapi profil gagal disimpan. ' +
                'Jangan teruskan onboarding sehingga profil dibaiki.'
            };
          }
          var profile = profRes.profile || {};
          return {
            ok: true,
            user: user || null,
            profile: profile,
            role: normalizeRole(profile.role || role),
            readyForOnboarding: true
          };
        });
      }).catch(function (e) {
        return fail(e, 'signUp');
      });
    });
  }

  function signIn(opts) {
    opts = opts || {};
    var SB = getClient();
    if (!SB) return Promise.resolve(noClient('signIn'));

    var email = String(opts.email || '').trim();
    var password = String(opts.password || '');

    if (!email || !password) {
      return Promise.resolve({
        ok: false,
        error: {
          kind: 'validation', code: 'MISSING_FIELDS',
          userMessage: 'Sila isi emel dan kata laluan.'
        }
      });
    }

    return preflight().then(function (health) {
      if (!health.ok && health.networkError) {
        return fail(health.networkError, 'signIn:preflight');
      }

      return SB.auth.signInWithPassword({ email: email, password: password })
        .then(function (res) {
          if (res.error) return fail(res.error, 'signIn');

          // Self-heal legacy accounts whose profile row never existed.
          return ensureProfile(null, null).then(function (profRes) {
            var profile = profRes.ok ? (profRes.profile || {}) : {};
            return {
              ok: true,
              user: res.data ? res.data.user : null,
              session: res.data ? res.data.session : null,
              profile: profile,
              role: profile.role ? normalizeRole(profile.role) : null,
              profileWarning: profRes.ok ? null : profRes.error
            };
          });
        }).catch(function (e) {
          return fail(e, 'signIn');
        });
    });
  }

  function signOut() {
    var SB = getClient();
    if (!SB) return Promise.resolve(noClient('signOut'));
    return SB.auth.signOut().then(function (res) {
      if (res && res.error) return fail(res.error, 'signOut');
      return { ok: true };
    }).catch(function (e) {
      return fail(e, 'signOut');
    });
  }

  function getSession() {
    var SB = getClient();
    if (!SB) return Promise.resolve(noClient('getSession'));
    return SB.auth.getSession().then(function (res) {
      if (res.error) return fail(res.error, 'getSession');
      return {
        ok: true,
        session: res.data ? res.data.session : null,
        user: res.data && res.data.session ? res.data.session.user : null
      };
    }).catch(function (e) {
      return fail(e, 'getSession');
    });
  }

  bridge.Auth.Session = {
    version: '1.0.0-p0',
    SELF_SERVE_ROLES: SELF_SERVE_ROLES,
    normalizeRole: normalizeRole,
    classifyError: classifyError,
    preflight: preflight,
    signUp: signUp,
    signIn: signIn,
    signOut: signOut,
    ensureProfile: ensureProfile,
    getCurrentRole: getCurrentRole,
    getSession: getSession
  };
})(typeof window !== 'undefined' ? window : globalThis);
