/*
 * PlayPro — obComplete() regression test for register_my_player RPC
 * Run: node tests/obcomplete-register.test.js
 *
 * No framework, no install. Mocks the Supabase client surface and verifies
 * that obComplete() correctly:
 *   - Calls register_my_player RPC with {p_payload: ...}
 *   - Accepts rpcData.ok === true OR rpcData.success === true
 *   - Extracts player ID from rpcData.player_id OR rpcData.id
 *   - Handles JSON string or parsed object responses
 *   - Persists ID to window.currentPlayerId and sessionStorage
 *   - Closes modal (hideOnboarding called)
 *   - Resets _pd / window._pd
 *   - Triggers loadProfile
 */
'use strict';

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

/* ---------- mock DOM ---------- */
function makeMockDom() {
  const elements = {};
  function getEl(id) {
    if (!elements[id]) elements[id] = { value: null, checked: false, textContent: '', disabled: false, style: {} };
    return elements[id];
  }
  // Pre-set required values for happy path
  getEl('ob-position').value = 'st';
  getEl('ob-phone-code').value = '+60';
  getEl('ob-phone').value = '123456789';
  return { elements, getEl };
}

/* ---------- mock sessionStorage ---------- */
function makeSessionStorage() {
  const store = {};
  return {
    store,
    getItem(k) { return store[k] || null; },
    setItem(k, v) { store[k] = String(v); },
    removeItem(k) { delete store[k]; },
    clear() { Object.keys(store).forEach(k => delete store[k]); }
  };
}

/* ---------- build obComplete in isolation ---------- */
function buildObComplete(mockConfig) {
  mockConfig = mockConfig || {};
  const dom = makeMockDom();
  const sessionStorage = makeSessionStorage();
  const state = {
    hideOnboardingCalled: false,
    loadProfileCalled: false,
    goToCalled: null,
    toastMessages: [],
    errorMsgs: [],
    _pd: 'stale-data',
    windowPd: 'stale-data',
    windowCurrentPlayerId: null,
    _obJustCompleted: false,
    clubHistoryPlayerId: null,
  };

  const rpcCalls = [];

  // Mock setMsg (used in error path)
  function setMsg(id, msg, type) {
    state.errorMsgs.push({ id, msg, type });
  }

  // Mock toast
  function toast(msg) { state.toastMessages.push(msg); }

  // Mock navigation
  function go(target) { state.goToCalled = target; }

  // Mock hideOnboarding
  function hideOnboarding() { state.hideOnboardingCalled = true; }

  // Mock saveClubHistoryOnboarding
  async function saveClubHistoryOnboarding(id) { state.clubHistoryPlayerId = id; }

  // Mock _obDOB
  const _obDOB = mockConfig.noDOB ? null : '2000-01-15';

  // Build mock supabase client
  const mockSB = {
    rpc(fn, params) {
      rpcCalls.push({ fn, params });
      if (mockConfig.rpcThrows) {
        return Promise.reject(new Error(mockConfig.rpcThrows));
      }
      if (fn === 'ensure_profile_after_signup') {
        if (mockConfig.profileError) {
          return Promise.resolve({ data: null, error: { message: mockConfig.profileError } });
        }
        return Promise.resolve({ data: { id: 'uuid-user-1' }, error: null });
      }
      if (fn === 'register_my_player') {
        if (mockConfig.rpcResult) {
          return Promise.resolve(mockConfig.rpcResult);
        }
        return Promise.resolve({ data: null, error: { message: 'unknown rpc' } });
      }
      return Promise.resolve({ data: null, error: { message: 'unknown rpc' } });
    }
  };

  // Mock getPlayProSupabase
  const mockGetPlayProSupabase = () => mockSB;

  // Mock _u (current user)
  const mockUser = mockConfig.noUser ? null : {
    id: 'uuid-test-user-1',
    user_metadata: { full_name: 'Ahmad Pemain', role: 'player', phone: '+60123456789' }
  };
  let _u = mockUser;

  // The ACTUAL obComplete function matching the production code in public/index.html
  async function obComplete() {
    var btn = dom.getEl('ob-btn2');
    btn.disabled = true;
    btn.textContent = 'Menyimpan...';
    try {
      var onboardingClient = mockGetPlayProSupabase?.() || mockSB;
      if (!onboardingClient || typeof onboardingClient.rpc !== 'function') {
        throw new Error('Sambungan Supabase belum tersedia. Sila muat semula halaman dan cuba lagi.');
      }
      if (!_u) throw new Error('Sila log masuk dahulu.');

      var position = dom.getEl('ob-position')?.value || '';
      if (!_obDOB) throw new Error('Tarikh lahir yang sah diperlukan.');
      if (!position) throw new Error('Sila pilih posisi utama.');

      var name = _u.user_metadata?.full_name || 'Pemain Baru';
      var obPhoneCode = dom.getEl('ob-phone-code')?.value || '+60';
      var obPhoneNum = (dom.getEl('ob-phone')?.value || '').trim();
      var phone = obPhoneNum ? (obPhoneCode + obPhoneNum) : (_u.user_metadata?.phone || null);

      // Guarantee the private profile first
      var profileResult = await onboardingClient.rpc('ensure_profile_after_signup', {
        p_full_name: name, p_phone: phone
      });
      if (profileResult.error) throw profileResult.error;

      // Atomic server-side upsert via register_my_player RPC
      var payload = {
        date_of_birth: _obDOB,
        position: position,
        preferred_foot: dom.getEl('ob-foot')?.value || null,
        jersey_number: dom.getEl('ob-jersey')?.value || null,
        height_cm: dom.getEl('ob-height')?.value || null,
        weight_kg: dom.getEl('ob-weight')?.value || null,
        preferred_name: dom.getEl('ob-nickname')?.value?.trim() || name,
        phone: phone,
        document_type: 'mykad',
        document_number: null
      };
      var playerResult = await onboardingClient.rpc('register_my_player', { p_payload: payload });

      var rpcData = playerResult?.data;
      var rpcError = playerResult?.error;

      // RPC may return a JSON string or a parsed object — normalise both
      if (typeof rpcData === 'string') {
        try { rpcData = JSON.parse(rpcData); } catch (pe) { rpcData = null; }
      }

      // Success is signalled by rpcData.ok===true OR rpcData.success===true
      var rpcOk = Boolean(rpcData && (rpcData.ok === true || rpcData.success === true));

      // Extract player ID from rpcData.player_id or rpcData.id
      var newPlayerId = rpcData ? (rpcData.player_id || rpcData.id || null) : null;

      if (rpcError || !rpcOk) {
        var errMsg = rpcError?.message || (rpcData?.error) || 'Pendaftaran pemain gagal. Sila cuba lagi.';
        console.error('[PlayPro] register_my_player failed:', errMsg, 'rpcData:', rpcData);
        throw new Error(String(errMsg));
      }

      if (!newPlayerId) {
        console.error('[PlayPro] register_my_player returned no player ID', rpcData);
        throw new Error('ID pemain tidak dikembalikan. Sila cuba lagi.');
      }

      // Persist player ID for downstream modules
      state.windowCurrentPlayerId = newPlayerId;
      try { sessionStorage.setItem('currentPlayerId', newPlayerId); } catch (se) { }

      if (newPlayerId) await saveClubHistoryOnboarding(newPlayerId);

      // Close onboarding modal
      hideOnboarding();
      toast('✅ Profil disimpan! Selamat datang ke PlayPro!');
      state._obJustCompleted = true;

      // Reset cached profile data so loadProfile fetches fresh
      state._pd = null;
      state.windowPd = null;

      go('profile');
      // setTimeout -> loadProfile
      state.loadProfileCalled = true;
    } catch (e) {
      console.error('[PlayPro onboarding]', e);
      var message = String(e?.message || 'Pendaftaran pemain gagal. Sila cuba lagi.');
      setMsg('ob-msg2', '❌ ' + message, 'err');
      toast('⚠️ ' + message);
    } finally {
      btn.disabled = false;
      btn.textContent = 'Simpan & Mula →';
    }
  }

  return { obComplete, state, dom, sessionStorage, rpcCalls };
}


(async function run() {
  console.log('PlayPro — obComplete() register_my_player regression tests');
  console.log('='.repeat(60));

  /* ============================================================ */
  section('1. Happy path: rpcData.ok === true with player_id');
  {
    const ctx = buildObComplete({
      rpcResult: {
        data: { ok: true, player_id: 'pid-001' },
        error: null
      }
    });
    await ctx.obComplete();

    check('register_my_player RPC was called with p_payload',
      ctx.rpcCalls.some(c => c.fn === 'register_my_player' && c.params?.p_payload));
    check('window.currentPlayerId set to pid-001',
      ctx.state.windowCurrentPlayerId === 'pid-001',
      'got: ' + ctx.state.windowCurrentPlayerId);
    check('sessionStorage stores currentPlayerId',
      ctx.sessionStorage.store.currentPlayerId === 'pid-001');
    check('hideOnboarding was called', ctx.state.hideOnboardingCalled === true);
    check('_pd reset to null', ctx.state._pd === null);
    check('window._pd reset to null', ctx.state.windowPd === null);
    check('loadProfile triggered', ctx.state.loadProfileCalled === true);
    check('success toast shown',
      ctx.state.toastMessages.some(m => /Profil disimpan/.test(m)));
    check('club history saved with player ID',
      ctx.state.clubHistoryPlayerId === 'pid-001');
  }

  /* ============================================================ */
  section('2. Happy path: rpcData.success === true with id field');
  {
    const ctx = buildObComplete({
      rpcResult: {
        data: { success: true, id: 'pid-002' },
        error: null
      }
    });
    await ctx.obComplete();

    check('success===true accepted as valid response',
      ctx.state.windowCurrentPlayerId === 'pid-002',
      'got: ' + ctx.state.windowCurrentPlayerId);
    check('rpcData.id used as fallback for player_id',
      ctx.state.windowCurrentPlayerId === 'pid-002');
    check('sessionStorage updated',
      ctx.sessionStorage.store.currentPlayerId === 'pid-002');
  }

  /* ============================================================ */
  section('3. JSON string response (not pre-parsed object)');
  {
    const ctx = buildObComplete({
      rpcResult: {
        data: JSON.stringify({ ok: true, player_id: 'pid-003' }),
        error: null
      }
    });
    await ctx.obComplete();

    check('JSON string parsed correctly',
      ctx.state.windowCurrentPlayerId === 'pid-003',
      'got: ' + ctx.state.windowCurrentPlayerId);
    check('sessionStorage has parsed ID',
      ctx.sessionStorage.store.currentPlayerId === 'pid-003');
  }

  /* ============================================================ */
  section('4. RPC returns error object — must throw');
  {
    const ctx = buildObComplete({
      rpcResult: {
        data: null,
        error: { message: 'permission denied', code: '42501' }
      }
    });
    await ctx.obComplete();

    check('hideOnboarding NOT called on error', ctx.state.hideOnboardingCalled === false);
    check('_pd NOT reset on error (still stale)', ctx.state._pd === 'stale-data');
    check('error toast shown',
      ctx.state.toastMessages.some(m => /permission denied/.test(m)));
    check('no player ID stored', ctx.state.windowCurrentPlayerId === null);
  }

  /* ============================================================ */
  section('5. RPC returns ok:false — must throw');
  {
    const ctx = buildObComplete({
      rpcResult: {
        data: { ok: false, error: 'duplicate' },
        error: null
      }
    });
    await ctx.obComplete();

    check('ok:false treated as failure',
      ctx.state.toastMessages.some(m => /duplicate/.test(m) || /Pendaftaran pemain gagal/.test(m)));
    check('hideOnboarding NOT called', ctx.state.hideOnboardingCalled === false);
    check('window._pd not reset', ctx.state.windowPd === 'stale-data');
  }

  /* ============================================================ */
  section('6. RPC throws network error — must catch');
  {
    const ctx = buildObComplete({
      rpcThrows: 'Failed to fetch'
    });
    await ctx.obComplete();

    check('network error surfaced to user',
      ctx.state.toastMessages.some(m => /Failed to fetch|Gagal/.test(m)));
    check('hideOnboarding NOT called', ctx.state.hideOnboardingCalled === false);
    check('no currentPlayerId stored', ctx.state.windowCurrentPlayerId === null);
  }

  /* ============================================================ */
  section('7. RPC returns no player_id and no id — must throw');
  {
    const ctx = buildObComplete({
      rpcResult: {
        data: { ok: true }, // ok but no ID
        error: null
      }
    });
    await ctx.obComplete();

    check('missing player ID triggers error toast',
      ctx.state.toastMessages.some(m => /ID pemain tidak dikembalikan/.test(m)));
    check('hideOnboarding NOT called', ctx.state.hideOnboardingCalled === false);
  }

  /* ============================================================ */
  section('8. Malformed JSON string — handled gracefully');
  {
    const ctx = buildObComplete({
      rpcResult: {
        data: '{invalid json!!}',
        error: null
      }
    });
    await ctx.obComplete();

    check('invalid JSON does not crash',
      ctx.state.toastMessages.some(m => /Pendaftaran pemain gagal/.test(m)));
    check('hideOnboarding NOT called on parse failure',
      ctx.state.hideOnboardingCalled === false);
  }

  /* ============================================================ */
  section('9. Both ok and success present (prefer ok)');
  {
    const ctx = buildObComplete({
      rpcResult: {
        data: { ok: true, success: true, player_id: 'pid-009' },
        error: null
      }
    });
    await ctx.obComplete();

    check('both flags accepted', ctx.state.windowCurrentPlayerId === 'pid-009');
    check('sessionStorage updated',
      ctx.sessionStorage.store.currentPlayerId === 'pid-009');
  }

  /* ============================================================ */
  section('10. player_id preferred over id when both present');
  {
    const ctx = buildObComplete({
      rpcResult: {
        data: { ok: true, player_id: 'primary-id', id: 'secondary-id' },
        error: null
      }
    });
    await ctx.obComplete();

    check('player_id takes precedence',
      ctx.state.windowCurrentPlayerId === 'primary-id',
      'got: ' + ctx.state.windowCurrentPlayerId);
  }

  /* ============================================================ */
  section('11. Profile RPC failure blocks registration');
  {
    const ctx = buildObComplete({
      profileError: 'permission denied',
      rpcResult: { data: { ok: true, player_id: 'should-not-reach' }, error: null }
    });
    await ctx.obComplete();

    check('register_my_player NOT called when profile fails',
      !ctx.rpcCalls.some(c => c.fn === 'register_my_player'));
    check('hideOnboarding NOT called', ctx.state.hideOnboardingCalled === false);
    check('no player ID stored', ctx.state.windowCurrentPlayerId === null);
  }

  /* ---------- summary ---------- */
  console.log('\n' + '='.repeat(60));
  console.log('TOTAL: ' + (passed + failed) + '   PASSED: ' + passed + '   FAILED: ' + failed);
  if (failed) {
    console.log('\nFailed tests:');
    failures.forEach(f => console.log('  - ' + f));
    process.exit(1);
  }
  console.log('ALL TESTS PASSED');
  console.log('='.repeat(60));
})();
