/*
 * PlayPro P0 — Auth Session Service test harness
 * Run: node tests/auth-session.test.js
 *
 * No framework, no install. Mocks the supabase-js surface and replays
 * the EXACT production failures found in the 2026-07-26 audit.
 *
 * Critically, the mock reproduces supabase-js semantics faithfully:
 * queries RESOLVE with {data,error} rather than rejecting. That is why
 * the legacy `try{...}catch(e){console.warn(e)}` in doRegister() never
 * fired and every profile failure was invisible.
 */
import { readFileSync } from 'node:fs';
import { runInThisContext } from 'node:vm';

const serviceSource = readFileSync(new URL('../src/modules/auth/auth-session.service.js', import.meta.url), 'utf8');

/* ---------- tiny assertion kit ---------- */
let passed = 0, failed = 0;
const failures = [];

function check(name, cond, detail) {
  if (cond) { passed++; console.log('  PASS  ' + name); }
  else {
    failed++; failures.push(name);
    console.log('  FAIL  ' + name + (detail ? '\n          -> ' + detail : ''));
  }
}
function section(t) { console.log('\n' + t + '\n' + '-'.repeat(t.length)); }

/* ---------- mock supabase-js ---------- */
function makeMock(cfg) {
  cfg = cfg || {};
  const calls = { signUp: 0, signIn: 0, rpc: [], directProfileWrite: 0 };

  const mock = {
    calls,
    auth: {
      signUp(args) {
        calls.signUp++;
        calls.lastSignUpArgs = args;
        if (cfg.networkDown) return Promise.reject(new TypeError('Failed to fetch'));
        if (cfg.signUpError) return Promise.resolve({ data: null, error: cfg.signUpError });
        return Promise.resolve({
          data: {
            user: { id: 'uuid-user-1', email: args.email, user_metadata: args.options.data },
            session: cfg.requireEmailConfirm ? null : { access_token: 'tok' }
          },
          error: null
        });
      },
      signInWithPassword(args) {
        calls.signIn++;
        if (cfg.networkDown) return Promise.reject(new TypeError('Failed to fetch'));
        if (cfg.signInError) return Promise.resolve({ data: null, error: cfg.signInError });
        return Promise.resolve({
          data: { user: { id: 'uuid-user-1', email: args.email }, session: { access_token: 'tok' } },
          error: null
        });
      },
      signOut() { return Promise.resolve({ error: null }); },
      getSession() { return Promise.resolve({ data: { session: null }, error: null }); }
    },
    rpc(fn, params) {
      calls.rpc.push({ fn, params });
      if (cfg.networkDown) return Promise.reject(new TypeError('Failed to fetch'));
      if (cfg.rpcError) return Promise.resolve({ data: null, error: cfg.rpcError });
      if (fn === 'ensure_profile_after_signup' || fn === 'get_my_profile') {
        return Promise.resolve({
          data: {
            id: 'uuid-user-1',
            full_name: (params && params.p_full_name) || 'Ahmad Zaki',
            email: 'ahmad@example.com',
            role: cfg.roleFromDb || 'player',
            phone: (params && params.p_phone) || null
          },
          error: null
        });
      }
      return Promise.resolve({ data: null, error: { message: 'unknown rpc', code: 'PGRST202' } });
    },
    // Guard: if the service ever writes profiles directly, we catch it.
    from(table) {
      if (table === 'profiles') calls.directProfileWrite++;
      const chain = {
        upsert: () => Promise.resolve({ data: null, error: null }),
        insert: () => Promise.resolve({ data: null, error: null }),
        update: () => chain,
        select: () => chain,
        eq: () => chain
      };
      return chain;
    }
  };
  return mock;
}

/* ---------- load service into a fresh global ---------- */
function loadService(mock, opts) {
  opts = opts || {};
  globalThis.window = globalThis;
  globalThis.PlayProModel6 = {
    Core: { getSupabase: () => mock, supabase: mock }
  };
  globalThis.PLAYPRO_SUPABASE_URL = 'https://example.supabase.co';
  globalThis.PLAYPRO_SUPABASE_ANON_KEY = 'anon-key';
  globalThis.fetch = opts.networkDown
    ? () => Promise.reject(new TypeError('Failed to fetch'))
    : () => Promise.resolve({ ok: true, status: 200 });

  runInThisContext(serviceSource, { filename: 'auth-session.service.js' });
  return globalThis.PlayProModel6.Auth.Session;
}

(async function run() {
  console.log('PlayPro P0 — Auth Session Service verification');
  console.log('==============================================');

  /* ============================================================ */
  section('1. Role normalisation (enum-safety gate)');
  {
    const svc = loadService(makeMock());
    check("'player' preserved (was fatal 22P02 pre-fix)", svc.normalizeRole('player') === 'player');
    check("'referee' preserved (was fatal 22P02 pre-fix)", svc.normalizeRole('referee') === 'referee');
    check("'coach' preserved", svc.normalizeRole('coach') === 'coach');
    check("'club_admin' preserved", svc.normalizeRole('club_admin') === 'club_admin');
    check("'league_admin' preserved", svc.normalizeRole('league_admin') === 'league_admin');

    check("Malay 'pemain' -> player", svc.normalizeRole('pemain') === 'player');
    check("Malay 'jurulatih' -> coach", svc.normalizeRole('jurulatih') === 'coach');
    check("'club_manager' -> club_admin", svc.normalizeRole('club_manager') === 'club_admin');
    check("' Coach ' (untrimmed/case) -> coach", svc.normalizeRole('  Coach ') === 'coach');

    // Privilege escalation must be impossible from the client.
    check("'developer' BLOCKED -> player", svc.normalizeRole('developer') === 'player');
    check("'league_founder' BLOCKED -> player", svc.normalizeRole('league_founder') === 'player');
    check("'technical_assessor' BLOCKED -> player (must be earned via PCSAP)",
      svc.normalizeRole('technical_assessor') === 'player');
    check('garbage -> player', svc.normalizeRole('<script>') === 'player');
    check('null/undefined -> player',
      svc.normalizeRole(null) === 'player' && svc.normalizeRole(undefined) === 'player');
  }

  /* ============================================================ */
  section('2. Error classification (the "Failed to fetch" fix)');
  {
    const svc = loadService(makeMock());

    const net = svc.classifyError(new TypeError('Failed to fetch'));
    check('"Failed to fetch" -> kind=network', net.kind === 'network', 'got ' + net.kind);
    check('network error NOT blamed on credentials', net.code === 'NETWORK_UNREACHABLE');
    check('network error has actionable dev hint', /hostname resolves|paused/i.test(net.devMessage));
    check('network user message is honest (not "wrong password")',
      /sambungan|pelayan/i.test(net.userMessage));

    check('ERR_NAME_NOT_RESOLVED -> network',
      svc.classifyError({ message: 'net::ERR_NAME_NOT_RESOLVED' }).kind === 'network');
    check('Safari "Load failed" -> network',
      svc.classifyError({ message: 'Load failed' }).kind === 'network');

    check('22P02 -> ENUM_MISMATCH',
      svc.classifyError({ code: '22P02', message: 'invalid input value for enum user_role: "player"' })
        .code === 'ENUM_MISMATCH');
    check('42501 -> RLS_DENIED',
      svc.classifyError({ code: '42501', message: 'permission denied' }).code === 'RLS_DENIED');
    check('role-escalation msg -> RLS_DENIED',
      svc.classifyError({ message: 'you cannot modify your own role' }).code === 'RLS_DENIED');
    check('23502 -> NOT_NULL_VIOLATION (missing email)',
      svc.classifyError({ code: '23502', message: 'null value in column "email"' })
        .code === 'NOT_NULL_VIOLATION');
    check('bad credentials still classified correctly',
      svc.classifyError({ message: 'Invalid login credentials' }).code === 'BAD_CREDENTIALS');
    check('missing RPC -> RPC_MISSING (patch not applied)',
      svc.classifyError({ code: 'PGRST202', message: 'function does not exist' })
        .code === 'RPC_MISSING');
  }

  /* ============================================================ */
  section('3. signUp happy path (ordering contract)');
  {
    const mock = makeMock({ roleFromDb: 'coach' });
    const svc = loadService(mock);
    const res = await svc.signUp({
      email: 'ahmad@example.com', password: 'password123',
      fullName: 'Ahmad Zaki', phone: '+60123456789', role: 'coach'
    });

    check('signUp ok', res.ok === true, JSON.stringify(res.error || {}));
    check('readyForOnboarding only after profile confirmed', res.readyForOnboarding === true);
    check('role resolved from DB, not client guess', res.role === 'coach');
    check('ensure_profile_after_signup RPC was called',
      mock.calls.rpc.some(c => c.fn === 'ensure_profile_after_signup'));
    check('NO direct write to profiles table (avoids 42501)',
      mock.calls.directProfileWrite === 0,
      'direct writes: ' + mock.calls.directProfileWrite);

    const meta = mock.calls.lastSignUpArgs.options.data;
    check('signup metadata carries full_name', meta.full_name === 'Ahmad Zaki');
    check('signup metadata carries normalised role', meta.role === 'coach');
  }

  /* ============================================================ */
  section('4. Privilege escalation attempt via signUp');
  {
    const mock = makeMock();
    const svc = loadService(mock);
    await svc.signUp({
      email: 'attacker@example.com', password: 'password123',
      fullName: 'Attacker', role: 'developer'
    });
    check("client downgrades 'developer' -> 'player' before it reaches the server",
      mock.calls.lastSignUpArgs.options.data.role === 'player',
      'sent: ' + mock.calls.lastSignUpArgs.options.data.role);
  }

  /* ============================================================ */
  section('5. Network down — the exact reported bug');
  {
    const mock = makeMock({ networkDown: true });
    const svc = loadService(mock, { networkDown: true });
    const res = await svc.signUp({
      email: 'a@b.com', password: 'password123', fullName: 'Test', role: 'player'
    });
    check('signUp fails cleanly', res.ok === false);
    check('classified as network (not credentials)', res.error.kind === 'network');
    check('preflight short-circuits before auth call', mock.calls.signUp === 0,
      'signUp calls: ' + mock.calls.signUp);
    check('user sees honest message', /sambungan|pelayan/i.test(res.error.userMessage));
  }

  /* ============================================================ */
  section('6. Profile write fails -> onboarding MUST be blocked');
  {
    const mock = makeMock({ rpcError: { code: '42501', message: 'permission denied' } });
    const svc = loadService(mock);
    const res = await svc.signUp({
      email: 'a@b.com', password: 'password123', fullName: 'Test', role: 'player'
    });
    check('result marked NOT ok', res.ok === false);
    check('flagged partial (auth exists, profile missing)', res.partial === true);
    check('readyForOnboarding is NOT set', !res.readyForOnboarding);
    check('failure is surfaced, not swallowed by console.warn',
      !!res.error && !!res.error.userMessage);
  }

  /* ============================================================ */
  section('7. Email-confirmation flow (no session yet)');
  {
    const mock = makeMock({ requireEmailConfirm: true });
    const svc = loadService(mock);
    const res = await svc.signUp({
      email: 'a@b.com', password: 'password123', fullName: 'Test', role: 'player'
    });
    check('ok with pendingConfirmation', res.ok === true && res.pendingConfirmation === true);
    check('does NOT claim readyForOnboarding', !res.readyForOnboarding);
    check('no profile RPC attempted without a session',
      !mock.calls.rpc.some(c => c.fn === 'ensure_profile_after_signup'));
  }

  /* ============================================================ */
  section('8. Validation guards');
  {
    const svc = loadService(makeMock());
    const short = await svc.signUp({
      email: 'a@b.com', password: 'abc', fullName: 'Test', role: 'player'
    });
    check('password < 8 rejected', short.ok === false && short.error.code === 'WEAK_PASSWORD');
    const missing = await svc.signUp({ email: '', password: '', fullName: '' });
    check('empty fields rejected', missing.ok === false && missing.error.code === 'MISSING_FIELDS');
  }

  /* ============================================================ */
  section('9. signIn self-heals legacy orphaned profiles');
  {
    const mock = makeMock({ roleFromDb: 'club_admin' });
    const svc = loadService(mock);
    const res = await svc.signIn({ email: 'old@user.com', password: 'password123' });
    check('signIn ok', res.ok === true);
    check('ensureProfile called on every login (self-heal)',
      mock.calls.rpc.some(c => c.fn === 'ensure_profile_after_signup'));
    check('role returned from DB', res.role === 'club_admin');
  }

  /* ============================================================ */
  section('10. Regression: legacy swallow-the-error bug');
  {
    // Proves WHY the old code was blind: supabase-js resolves with
    // {error}, so a try/catch around an un-destructured await sees nothing.
    const mock = makeMock();
    let legacyCaught = false;
    try {
      await mock.from('profiles').upsert({ id: 'x' }, { onConflict: 'id' });
    } catch (e) { legacyCaught = true; }
    check('legacy try/catch catches NOTHING (root cause of silent failure)',
      legacyCaught === false);

    const svc = loadService(makeMock({ rpcError: { code: '42501', message: 'permission denied' } }));
    const r = await svc.ensureProfile('Test', null);
    check('new service RETURNS the error instead of swallowing it',
      r.ok === false && r.error.code === 'RLS_DENIED');
  }

  /* ---------- summary ---------- */
  console.log('\n' + '='.repeat(46));
  console.log('TOTAL: ' + (passed + failed) + '   PASSED: ' + passed + '   FAILED: ' + failed);
  if (failed) {
    console.log('\nFailed tests:');
    failures.forEach(f => console.log('  - ' + f));
    process.exit(1);
  }
  console.log('ALL TESTS PASSED');
  console.log('='.repeat(46));
})();
