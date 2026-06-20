/*
 * PlayPro Model 6 — Role-Aware Search Router
 * Overrides legacy Terokai search only when dropdown type === coach.
 * Keeps player search untouched for legacy flow.
 */
(function attachRoleAwareSearchRouter(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Search = bridge.Search || {};

  var originalOnTerSearch = null;

  function getSupabaseClient() {
    if (bridge.Core && typeof bridge.Core.getSupabase === 'function') return bridge.Core.getSupabase();
    return (bridge.Core && bridge.Core.supabase) || root.SB || null;
  }

  function safeText(value, fallback) {
    return String(value || fallback || '').replace(/[<>&"']/g, function(ch) {
      return ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&#39;' })[ch];
    });
  }

  function initials(name) {
    var n = String(name || 'C').trim();
    return n ? n[0].toUpperCase() : 'C';
  }

  function calculateAge(dob) {
    if (!dob) return null;
    var d = new Date(dob);
    if (isNaN(d.getTime())) return null;
    var now = new Date();
    var age = now.getFullYear() - d.getFullYear();
    var m = now.getMonth() - d.getMonth();
    if (m < 0 || (m === 0 && now.getDate() < d.getDate())) age--;
    return age >= 0 ? age : null;
  }

  function buildCoachBioLine(profile) {
    var age = calculateAge(profile.date_of_birth);
    var ic = profile.ic_number || profile.mykad_number || null;
    var pass = profile.passport_number || null;

    if (age === null && !ic && !pass) {
      return 'Tiada Maklumat';
    }

    var parts = [];
    parts.push(age !== null ? (age + ' Tahun') : 'Umur —');
    parts.push('MyKad: ' + (ic || 'Tiada Maklumat'));
    parts.push('Passport: ' + (pass || 'Tiada Maklumat'));
    return parts.join(' | ');
  }

  function setResultsHeader(count) {
    var resEl = document.getElementById('ter-results');
    var defEl = document.getElementById('ter-default');
    var counter = document.getElementById('ter-results-count');
    if (defEl) defEl.style.display = 'none';
    if (resEl) resEl.style.display = 'block';
    if (counter) counter.textContent = count + ' coach ditemui (Role Filter Aktif)';
  }

  function renderCoachResults(rows) {
    var list = document.getElementById('ter-results-list');
    if (!list) return;
    list.innerHTML = '';

    if (!rows || !rows.length) {
      setResultsHeader(0);
      list.innerHTML = '<div style="text-align:center;padding:3rem 1rem;color:var(--mute)"><div style="font-size:3.5rem;margin-bottom:.5rem">👨‍🏫</div><h4 style="font-weight:800;color:var(--txt);margin-bottom:.25rem">Tiada coach ditemui</h4><div style="font-size:.75rem">Tiada profil berperanan coach untuk carian ini.</div></div>';
      return;
    }

    setResultsHeader(rows.length);

    rows.forEach(function(profile) {
      var name = profile.full_name || profile.email || 'Coach';
      var card = document.createElement('div');
      card.className = 'style-result-card model6-coach-result-card';
      card.style.cssText = 'display:flex;align-items:center;gap:.75rem;padding:.85rem 1rem;background:var(--card);border:1.5px solid #38bdf8;border-radius:14px;margin-bottom:.55rem;cursor:pointer;transition:transform .2s, border-color .2s, box-shadow .2s';
      card.innerHTML = ''
        + '<div style="width:46px;height:46px;border-radius:12px;border:2px solid #38bdf8;background:linear-gradient(135deg,#0f172a,#2563eb);display:flex;align-items:center;justify-content:center;font-weight:900;color:#fff;font-size:1.15rem;flex-shrink:0;box-shadow:0 2px 8px rgba(0,0,0,.4)">' + safeText(initials(name)) + '</div>'
        + '<div style="flex:1;min-width:0">'
          + '<div style="display:flex;align-items:center;gap:.4rem;margin-bottom:.1rem">'
            + '<span style="font-size:.95rem;font-weight:800;color:var(--txt)">' + safeText(name) + '</span>'
            + '<span style="font-size:.5rem;background:#2563eb;color:#fff;padding:.08rem .35rem;border-radius:4px;font-weight:800;letter-spacing:.05em">COACH</span>'
          + '</div>'
          + '<div style="font-size:.65rem;color:var(--mute);margin-bottom:.15rem">Coach Passport · PCSAP / Assessment Network</div>'
          + '<div style="font-size:.62rem;color:#38bdf8;font-weight:700">' + safeText(buildCoachBioLine(profile)) + '</div>'
        + '</div>'
        + '<div style="text-align:right;flex-shrink:0">'
          + '<div style="font-size:.78rem;font-weight:900;color:#38bdf8;line-height:1">GRED</div>'
          + '<div style="font-size:.55rem;color:#94a3b8;font-weight:800;margin-top:.2rem">Role: coach</div>'
        + '</div>';

      card.addEventListener('click', function() {
        openCoachPublicProfile(profile.id);
      });
      list.appendChild(card);
    });
  }

  async function openCoachPublicProfile(profileId) {
    var list = document.getElementById('ter-results-list');
    var counter = document.getElementById('ter-results-count');
    if (list) list.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--mute)">Memuatkan Coach Passport...</div>';
    if (counter) counter.textContent = 'Coach Passport';

    var supabase = getSupabaseClient();
    if (!supabase || typeof supabase.from !== 'function') {
      if (list) list.innerHTML = '<div style="padding:1rem;color:var(--mute)">Sambungan data tidak tersedia.</div>';
      return;
    }

    try {
      var payload = null;

      if (typeof supabase.rpc === 'function') {
        var rpcResult = await supabase.rpc('get_public_coach_profile', { p_profile_id: profileId });
        if (!rpcResult.error && rpcResult.data && rpcResult.data.success === true) {
          payload = {
            profile: rpcResult.data.profile || { id: profileId, full_name: 'Coach' },
            assessor: rpcResult.data.assessor || {}
          };
        }
      }

      if (!payload) {
        var profileSelect = 'id,full_name,email,role,avatar_url,date_of_birth,ic_number,passport_number,nationality';
        var profileResult = await supabase
          .from('profiles')
          .select(profileSelect)
          .eq('id', profileId)
          .maybeSingle();

        if (profileResult.error && profileResult.error.code === '42703') {
          profileResult = await supabase
            .from('profiles')
            .select('id,full_name,email,role,avatar_url')
            .eq('id', profileId)
            .maybeSingle();
        }

        if (profileResult.error) throw profileResult.error;

        var assessorResult = await supabase
          .from('certified_assessors')
          .select('profile_id,license_type,status,max_attribute_score,trust_score,metadata')
          .eq('profile_id', profileId)
          .maybeSingle();

        payload = {
          profile: profileResult.data || { id: profileId, full_name: 'Coach' },
          assessor: assessorResult && !assessorResult.error && assessorResult.data ? assessorResult.data : {}
        };
      }

      if (list && bridge.Coach && bridge.Coach.UI && typeof bridge.Coach.UI.renderCoachPublicProfile === 'function') {
        var back = document.createElement('button');
        back.textContent = '← Kembali ke Senarai Coach';
        back.style.cssText = 'margin:0 0 10px;padding:8px 12px;background:#0f172a;color:#fff;border:1px solid #38bdf8;border-radius:8px;font-weight:800;cursor:pointer';
        back.addEventListener('click', function() { searchCoaches(); });
        list.innerHTML = '';
        list.appendChild(back);
        var mount = document.createElement('div');
        list.appendChild(mount);
        bridge.Coach.UI.renderCoachPublicProfile(mount, payload);
      }
    } catch (err) {
      console.warn('[PlayPro Model 6] Coach public profile failed:', err);
      if (list) list.innerHTML = '<div style="padding:1rem;color:var(--mute)">Gagal memuatkan Coach Passport.</div>';
    }
  }

  async function searchCoaches() {
    var list = document.getElementById('ter-results-list');
    if (list) list.innerHTML = '<div style="text-align:center;padding:1.5rem;color:var(--mute)">Mencari coach...</div>';

    var q = (document.getElementById('tr-search') && document.getElementById('tr-search').value || '').trim();
    var supabase = getSupabaseClient();

    if (!supabase || typeof supabase.from !== 'function') {
      renderCoachResults([]);
      return;
    }

    try {
      var selectFields = 'id,full_name,email,role,avatar_url,date_of_birth,ic_number,passport_number,nationality';
      var query = supabase
        .from('profiles')
        .select(selectFields)
        .eq('role', 'coach');

      if (q) query = query.or('full_name.ilike.%' + q + '%,email.ilike.%' + q + '%');

      var result = await query.order('full_name', { ascending: true }).limit(50);

      if (result.error && result.error.code === '42703') {
        var fallbackQuery = supabase
          .from('profiles')
          .select('id,full_name,email,role,avatar_url')
          .eq('role', 'coach');
        if (q) fallbackQuery = fallbackQuery.or('full_name.ilike.%' + q + '%,email.ilike.%' + q + '%');
        result = await fallbackQuery.order('full_name', { ascending: true }).limit(50);
      }

      if (result.error) throw result.error;
      renderCoachResults(result.data || []);
    } catch (err) {
      console.warn('[PlayPro Model 6] Coach search failed:', err);
      renderCoachResults([]);
    }
  }

  function patchedOnTerSearch() {
    var jenis = document.getElementById('tr-jenis') && document.getElementById('tr-jenis').value || '';
    if (jenis === 'coach') {
      return searchCoaches();
    }
    if (typeof originalOnTerSearch === 'function') {
      return originalOnTerSearch.apply(root, arguments);
    }
    return null;
  }

  var RoleSearchRouter = {
    init: function() {
      if (!originalOnTerSearch && typeof root.onTerSearch === 'function') {
        originalOnTerSearch = root.onTerSearch;
      }
      root.onTerSearch = patchedOnTerSearch;
    },
    searchCoaches: searchCoaches
  };

  bridge.Search.RoleSearchRouter = RoleSearchRouter;

  document.addEventListener('PlayProModel6Ready', function() { RoleSearchRouter.init(); });
  if (bridge.ready === true) RoleSearchRouter.init();
})(typeof window !== 'undefined' ? window : globalThis);
