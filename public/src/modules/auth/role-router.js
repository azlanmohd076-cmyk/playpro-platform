/*
 * PlayPro Model 6 — Role-Based Dashboard Router
 * Isolated router only. Does not edit legacy public/index.html.
 *
 * Purpose:
 * - Detect authenticated user's role from profiles or auth metadata.
 * - If role === coach, hide Player Passport containers and render Coach Workspace.
 */
(function attachRoleRouter(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};
  bridge.Auth = bridge.Auth || {};

  var onboardingObserver = null;
  var originalShowOnboarding = null;
  var coachOnboardingSessionCache = {};
  var coachProfileSessionCache = {};

  function getSupabaseClient() {
    if (bridge.Core && typeof bridge.Core.getSupabase === 'function') {
      return bridge.Core.getSupabase();
    }
    return bridge.Core.supabase || root.supabase || null;
  }

  function normalizeRole(role) {
    return String(role || '').trim().toLowerCase();
  }

  function isCoachRole(role) {
    var r = normalizeRole(role);
    return r === 'coach' || r === 'jurulatih' || r === 'technical_assessor';
  }

  function isManagerRole(role) {
    var r = normalizeRole(role);
    return r === 'club_admin' || r === 'manager' || r === 'club_manager' || r === 'pengurus_kelab';
  }

  function getProfileRoot() {
    return document.getElementById('tab-profile') || document.getElementById('main') || document.body;
  }

  function hidePlayerPassportUI() {
    var ids = [
      'pp-guest',
      'pp-norec',
      'pp-main',
      'pp-loading',
      'pp-data-wrap',
      'kad-modal',
      'other-player-bar'
    ];

    ids.forEach(function(id) {
      var node = document.getElementById(id);
      if (node) node.style.setProperty('display', 'none', 'important');
    });
  }

  function hideNodeHard(node) {
    if (!node || !node.style) return;
    node.style.setProperty('display', 'none', 'important');
    node.style.setProperty('visibility', 'hidden', 'important');
    node.style.setProperty('pointer-events', 'none', 'important');
    node.setAttribute('aria-hidden', 'true');
  }

  function nukePlayerOnboardingModal() {
    var knownIds = [
      'onboarding-mask',
      'onboarding-sheet',
      'ob-step1',
      'ob-step2'
    ];

    knownIds.forEach(function(id) {
      hideNodeHard(document.getElementById(id));
    });

    var all = document.querySelectorAll('div, section, aside');
    for (var i = 0; i < all.length; i++) {
      var node = all[i];
      if (!node || !node.textContent) continue;
      var txt = node.textContent;
      if (
        txt.indexOf('Lengkapkan Profil Kau') !== -1 ||
        (txt.indexOf('POSISI UTAMA') !== -1 && txt.indexOf('KAKI DOMINAN') !== -1)
      ) {
        hideNodeHard(node);
      }
    }
  }

  function blockLegacyPlayerOnboardingForCoach() {
    nukePlayerOnboardingModal();

    if (typeof root.showOnboarding === 'function' && root.showOnboarding.__model6CoachBlocked !== true) {
      originalShowOnboarding = originalShowOnboarding || root.showOnboarding;
      var blocked = function blockedShowOnboardingForCoach() {
        nukePlayerOnboardingModal();
        console.warn('[PlayPro Model 6] Player onboarding modal blocked for coach account.');
      };
      blocked.__model6CoachBlocked = true;
      root.showOnboarding = blocked;
    }

    if (!onboardingObserver && root.MutationObserver) {
      onboardingObserver = new MutationObserver(function() {
        nukePlayerOnboardingModal();
        hidePlayerPassportUI();
        var mount = document.getElementById('model6-coach-dashboard');
        if (mount) mount.style.setProperty('display', 'block', 'important');
      });
      onboardingObserver.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['style', 'class']
      });
    }

    function enforceCoachView() {
      nukePlayerOnboardingModal();
      hidePlayerPassportUI();
      var mount = document.getElementById('model6-coach-dashboard');
      if (mount) mount.style.setProperty('display', 'block', 'important');
    }

    setTimeout(enforceCoachView, 50);
    setTimeout(enforceCoachView, 250);
    setTimeout(enforceCoachView, 900);
    setTimeout(enforceCoachView, 1800);
  }

  function unblockLegacyPlayerOnboarding() {
    if (originalShowOnboarding && root.showOnboarding && root.showOnboarding.__model6CoachBlocked === true) {
      root.showOnboarding = originalShowOnboarding;
    }
    if (onboardingObserver) {
      onboardingObserver.disconnect();
      onboardingObserver = null;
    }
  }

  function ensureCoachMount() {
    var rootNode = getProfileRoot();
    var mount = document.getElementById('model6-coach-dashboard');
    if (!mount) {
      mount = document.createElement('div');
      mount.id = 'model6-coach-dashboard';
      rootNode.appendChild(mount);
    }
    mount.style.display = 'block';
    return mount;
  }

  function hideCoachMount() {
    var mount = document.getElementById('model6-coach-dashboard');
    if (mount) mount.style.display = 'none';
  }

  async function getCurrentUserAndProfile() {
    var supabase = getSupabaseClient();
    if (!supabase || !supabase.auth || typeof supabase.auth.getUser !== 'function') {
      return { user: null, profile: null, role: null, reason: 'SUPABASE_AUTH_NOT_READY' };
    }

    var userResult = await supabase.auth.getUser();
    var user = userResult && userResult.data ? userResult.data.user : null;

    if (!user && typeof supabase.auth.getSession === 'function') {
      var sessionResult = await supabase.auth.getSession();
      user = sessionResult && sessionResult.data && sessionResult.data.session ? sessionResult.data.session.user : null;
    }

    if (!user) {
      return { user: null, profile: null, role: null, reason: 'NO_AUTH_USER' };
    }

    var metaRole = normalizeRole(
      (user.app_metadata && user.app_metadata.role) ||
      (user.user_metadata && user.user_metadata.role)
    );

    var profile = null;
    var dbRole = null;

    try {
      var profileResult = await supabase
        .from('profiles')
        .select('id,full_name,email,role,avatar_url,phone,is_active,date_of_birth,ic_number,passport_number,nationality')
        .eq('id', user.id)
        .maybeSingle();

      if (profileResult.error && profileResult.error.code === '42703') {
        profileResult = await supabase
          .from('profiles')
          .select('id,full_name,email,role,avatar_url,phone,is_active')
          .eq('id', user.id)
          .maybeSingle();
      }

      if (!profileResult.error && profileResult.data) {
        profile = profileResult.data;
        dbRole = normalizeRole(profile.role);
      }
    } catch (err) {
      console.warn('[PlayPro Model 6] Role profile lookup failed:', err);
    }

    return {
      user: user,
      profile: profile || {
        id: user.id,
        full_name: (user.user_metadata && user.user_metadata.full_name) || user.email || 'Coach',
        email: user.email,
        role: metaRole || null,
        date_of_birth: user.user_metadata && user.user_metadata.date_of_birth || null,
        ic_number: user.user_metadata && user.user_metadata.ic_number || null,
        passport_number: user.user_metadata && user.user_metadata.passport_number || null,
        nationality: user.user_metadata && user.user_metadata.nationality || 'Malaysian'
      },
      role: dbRole || metaRole || null,
      reason: 'OK'
    };
  }

  function coachNeedsOnboarding(profile, caps) {
    var pid = profile && (profile.id || profile.profile_id);
    if (pid && coachOnboardingSessionCache[pid] === true) return false;

    var hasDoc = !!(profile && (profile.ic_number || profile.passport_number));
    var hasPhone = !!(profile && profile.phone);
    var hasLicense = !!(caps && caps.licenseType);
    return !(hasDoc && hasPhone && hasLicense);
  }

  async function saveCoachOnboarding(profileId, payload) {
    var supabase = getSupabaseClient();
    if (!supabase || typeof supabase.rpc !== 'function') {
      return { success: false, reason: 'SUPABASE_RPC_NOT_READY', message: 'Sambungan sistem belum bersedia.' };
    }
    var result = await supabase.rpc('save_coach_onboarding_profile', {
      p_profile_id: profileId,
      p_payload: payload
    });
    if (result.error) {
      return { success: false, reason: 'RPC_ERROR', message: result.error.message || 'Gagal menyimpan profil coach.' };
    }
    return result.data || { success: true };
  }

  function installShowOnboardingInterceptor() {
    if (typeof root.showOnboarding !== 'function' || root.showOnboarding.__model6RoleAware === true) {
      return;
    }

    var legacyShowOnboarding = root.showOnboarding;
    var wrapped = function model6RoleAwareShowOnboarding() {
      var selectedRole = '';
      try {
        var roleInput = document.getElementById('d-role');
        selectedRole = roleInput ? normalizeRole(roleInput.value) : '';
      } catch (ignore) {}

      getCurrentUserAndProfile().then(function(session) {
        var detectedRole = normalizeRole(session.role || selectedRole);
        if (isCoachRole(detectedRole)) {
          blockLegacyPlayerOnboardingForCoach();
          RoleRouter.renderCoachRoute(session.profile || (session.user ? { id: session.user.id, email: session.user.email, role: 'coach' } : { role: 'coach' }));
          return;
        }
        if (isManagerRole(detectedRole)) {
          blockLegacyPlayerOnboardingForCoach();
          RoleRouter.renderClubManagerRoute(session.profile || (session.user ? { id: session.user.id, email: session.user.email, role: 'club_admin' } : { role: 'club_admin' }));
          return;
        }
        legacyShowOnboarding.apply(root, arguments);
      }).catch(function() {
        if (isCoachRole(selectedRole)) {
          blockLegacyPlayerOnboardingForCoach();
          return;
        }
        legacyShowOnboarding.apply(root, arguments);
      });
    };

    wrapped.__model6RoleAware = true;
    wrapped.__legacyShowOnboarding = legacyShowOnboarding;
    root.showOnboarding = wrapped;
  }

  function buildCoachProfileFromOnboarding(profile, payload) {
    var base = Object.assign({}, profile || {});
    base.ic_number = payload.ic_number || base.ic_number || null;
    base.passport_number = payload.passport_number || base.passport_number || null;
    base.date_of_birth = payload.date_of_birth || base.date_of_birth || null;
    base.phone = payload.phone || base.phone || null;
    base.height_cm = payload.height_cm || base.height_cm || null;
    base.weight_kg = payload.weight_kg || base.weight_kg || null;
    base.nationality = payload.nationality || base.nationality || 'Malaysian';
    base.license_type = payload.license_type || base.license_type || base.licenseType || null;
    base.licenseType = base.license_type;
    return base;
  }

  function markCoachOnboardingComplete(profileId, updatedProfile) {
    if (profileId) {
      coachOnboardingSessionCache[profileId] = true;
      if (updatedProfile) coachProfileSessionCache[profileId] = updatedProfile;
      try {
        if (root.localStorage && updatedProfile) {
          root.localStorage.setItem('PLAYPRO_COACH_PROFILE_CACHE_' + profileId, JSON.stringify({
            license_type: updatedProfile.license_type || updatedProfile.licenseType || null,
            ic_number: updatedProfile.ic_number || null,
            passport_number: updatedProfile.passport_number || null,
            date_of_birth: updatedProfile.date_of_birth || null,
            phone: updatedProfile.phone || null,
            nationality: updatedProfile.nationality || 'Malaysian'
          }));
        }
      } catch (ignore) {}
    }
  }

  async function getManagedClub(profileId) {
    var supabase = getSupabaseClient();
    if (!profileId || !supabase || typeof supabase.from !== 'function') return null;
    try {
      var result = await supabase
        .from('clubs')
        .select('id,name,year_founded,home_venue,colours,admin_id')
        .eq('admin_id', profileId)
        .order('created_at', { ascending: true })
        .limit(1)
        .maybeSingle();
      if (!result.error && result.data) return result.data;
    } catch (ignore) {}
    return null;
  }

  async function saveClubManagerOnboarding(profileId, payload) {
    var supabase = getSupabaseClient();
    if (!supabase || typeof supabase.rpc !== 'function') {
      return { success: false, reason: 'SUPABASE_RPC_NOT_READY', message: 'Sambungan sistem belum bersedia.' };
    }
    var result = await supabase.rpc('save_club_manager_onboarding_profile', {
      p_profile_id: profileId,
      p_payload: payload
    });
    if (result.error) return { success: false, reason: 'RPC_ERROR', message: result.error.message || 'Gagal menyimpan profil manager kelab.' };
    return result.data || { success: true };
  }

  var RoleRouter = {
    lastRole: null,

    async routeCurrentSession() {
      try {
        var session = await getCurrentUserAndProfile();
        var role = normalizeRole(session.role);
        this.lastRole = role;

        if (isCoachRole(role)) {
          blockLegacyPlayerOnboardingForCoach();
          await this.renderCoachRoute(session.profile || { id: session.user && session.user.id });
          return { routed: true, role: role, target: 'coach-dashboard' };
        }

        if (isManagerRole(role)) {
          blockLegacyPlayerOnboardingForCoach();
          await this.renderClubManagerRoute(session.profile || { id: session.user && session.user.id });
          return { routed: true, role: role, target: 'club-manager-dashboard' };
        }

        unblockLegacyPlayerOnboarding();
        hideCoachMount();
        return { routed: false, role: role || null, target: 'legacy-ui' };
      } catch (err) {
        console.error('[PlayPro Model 6] Role router error:', err);
        return { routed: false, role: null, target: 'legacy-ui', error: err && err.message ? err.message : String(err) };
      }
    },

    async renderCoachRoute(profile) {
      hidePlayerPassportUI();
      blockLegacyPlayerOnboardingForCoach();
      var mount = ensureCoachMount();
      var coachProfile = profile || {};
      var coachIdForCache = coachProfile.id || coachProfile.profile_id;
      if (coachIdForCache && coachProfileSessionCache[coachIdForCache]) {
        coachProfile = Object.assign({}, coachProfile, coachProfileSessionCache[coachIdForCache]);
      }
      var caps = null;

      if (bridge.Coach && typeof bridge.Coach.getCoachCapabilities === 'function') {
        caps = await bridge.Coach.getCoachCapabilities(coachProfile.id || coachProfile.profile_id);
      }

      if (coachNeedsOnboarding(coachProfile, caps)) {
        if (bridge.Coach && bridge.Coach.UI && typeof bridge.Coach.UI.renderCoachOnboardingForm === 'function') {
          bridge.Coach.UI.renderCoachOnboardingForm(mount, coachProfile, async function(payload, msgNode) {
            var saved = await saveCoachOnboarding(coachProfile.id || coachProfile.profile_id, payload);
            if (!saved.success) {
              if (msgNode) msgNode.textContent = saved.message || 'Gagal menyimpan profil coach.';
              return;
            }

            var coachId = coachProfile.id || coachProfile.profile_id;
            var updatedProfile = buildCoachProfileFromOnboarding(coachProfile, payload);
            markCoachOnboardingComplete(coachId, updatedProfile);
            if (msgNode) msgNode.textContent = 'Profil coach berjaya disimpan. Membuka Coach Passport...';
            if (bridge.Coach && bridge.Coach.UI && typeof bridge.Coach.UI.renderCoachWorkspaceDashboard === 'function') {
              setTimeout(async function() {
                await bridge.Coach.UI.renderCoachWorkspaceDashboard(mount, updatedProfile);
                hidePlayerPassportUI();
                nukePlayerOnboardingModal();
              }, 150);
            } else {
              setTimeout(function() { RoleRouter.routeCurrentSession(); }, 250);
            }
          });
        } else {
          mount.innerHTML = '<div style="padding:16px;background:#111827;color:#fff;border-radius:12px;margin:12px">Borang onboarding coach sedang dimuatkan...</div>';
        }
        hidePlayerPassportUI();
        nukePlayerOnboardingModal();
        return;
      }

      if (bridge.Coach && bridge.Coach.UI && typeof bridge.Coach.UI.renderCoachWorkspaceDashboard === 'function') {
        await bridge.Coach.UI.renderCoachWorkspaceDashboard(mount, coachProfile);
        hidePlayerPassportUI();
        nukePlayerOnboardingModal();
      } else {
        mount.innerHTML = '<div style="padding:16px;background:#111827;color:#fff;border-radius:12px;margin:12px">Coach Workspace sedang dimuatkan...</div>';
      }
    },

    async renderClubManagerRoute(profile) {
      hidePlayerPassportUI();
      blockLegacyPlayerOnboardingForCoach();
      var mount = ensureCoachMount();
      var managerProfile = profile || {};
      var profileId = managerProfile.id || managerProfile.profile_id;
      var club = await getManagedClub(profileId);

      if (!club) {
        if (bridge.Club && bridge.Club.ManagerUI && typeof bridge.Club.ManagerUI.renderClubManagerOnboardingForm === 'function') {
          bridge.Club.ManagerUI.renderClubManagerOnboardingForm(mount, managerProfile, async function(payload, msgNode) {
            var saved = await saveClubManagerOnboarding(profileId, payload);
            if (!saved.success) {
              if (msgNode) msgNode.textContent = saved.message || 'Gagal menyimpan profil manager kelab.';
              return;
            }
            if (msgNode) msgNode.textContent = 'Profil manager kelab berjaya disimpan.';
            setTimeout(function() { RoleRouter.routeCurrentSession(); }, 250);
          });
        } else {
          mount.innerHTML = '<div style="padding:16px;background:#111827;color:#fff;border-radius:12px;margin:12px">Borang manager kelab sedang dimuatkan...</div>';
        }
        return;
      }

      if (bridge.Club && bridge.Club.ManagerUI && typeof bridge.Club.ManagerUI.renderClubManagerWorkspace === 'function') {
        bridge.Club.ManagerUI.renderClubManagerWorkspace(mount, managerProfile, club);
      } else {
        mount.innerHTML = '<div style="padding:16px;background:#111827;color:#fff;border-radius:12px;margin:12px">Club Manager Workspace sedang dimuatkan...</div>';
      }
    },

    init() {
      var self = this;
      installShowOnboardingInterceptor();
      this.routeCurrentSession();
      setTimeout(function(){ installShowOnboardingInterceptor(); self.routeCurrentSession(); }, 250);
      setTimeout(function(){ self.routeCurrentSession(); }, 1000);
      setTimeout(function(){ self.routeCurrentSession(); }, 2500);
      setTimeout(function(){ self.routeCurrentSession(); }, 5000);

      var supabase = getSupabaseClient();
      if (supabase && supabase.auth && typeof supabase.auth.onAuthStateChange === 'function') {
        supabase.auth.onAuthStateChange(function() {
          setTimeout(function() { installShowOnboardingInterceptor(); self.routeCurrentSession(); }, 50);
        });
      }

      document.addEventListener('PlayProProfileRouteCheck', function() {
        self.routeCurrentSession();
      });
    }
  };

  bridge.Auth.RoleRouter = RoleRouter;

  document.addEventListener('PlayProModel6Ready', function() {
    RoleRouter.init();
  });

  if (bridge.ready === true) {
    RoleRouter.init();
  }
})(typeof window !== 'undefined' ? window : globalThis);
