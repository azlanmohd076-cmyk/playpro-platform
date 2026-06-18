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

  function getSupabaseClient() {
    if (bridge.Core && typeof bridge.Core.getSupabase === 'function') {
      return bridge.Core.getSupabase();
    }
    return bridge.Core.supabase || root.supabase || null;
  }

  function normalizeRole(role) {
    return String(role || '').trim().toLowerCase();
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
      if (node) node.style.display = 'none';
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
      });
      onboardingObserver.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['style', 'class']
      });
    }

    setTimeout(nukePlayerOnboardingModal, 50);
    setTimeout(nukePlayerOnboardingModal, 250);
    setTimeout(nukePlayerOnboardingModal, 900);
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
    if (userResult.error || !userResult.data || !userResult.data.user) {
      return { user: null, profile: null, role: null, reason: 'NO_AUTH_USER' };
    }

    var user = userResult.data.user;
    var metaRole = normalizeRole(
      (user.app_metadata && user.app_metadata.role) ||
      (user.user_metadata && user.user_metadata.role)
    );

    var profile = null;
    var dbRole = null;

    try {
      var profileResult = await supabase
        .from('profiles')
        .select('id,full_name,email,role,avatar_url,phone,is_active')
        .eq('id', user.id)
        .maybeSingle();

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
        role: metaRole || null
      },
      role: dbRole || metaRole || null,
      reason: 'OK'
    };
  }

  var RoleRouter = {
    lastRole: null,

    async routeCurrentSession() {
      try {
        var session = await getCurrentUserAndProfile();
        var role = normalizeRole(session.role);
        this.lastRole = role;

        if (role === 'coach') {
          blockLegacyPlayerOnboardingForCoach();
          await this.renderCoachRoute(session.profile || { id: session.user && session.user.id });
          return { routed: true, role: role, target: 'coach-dashboard' };
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

      if (bridge.Coach && bridge.Coach.UI && typeof bridge.Coach.UI.renderCoachWorkspaceDashboard === 'function') {
        await bridge.Coach.UI.renderCoachWorkspaceDashboard(mount, profile || {});
      } else {
        mount.innerHTML = '<div style="padding:16px;background:#111827;color:#fff;border-radius:12px;margin:12px">Coach Workspace sedang dimuatkan...</div>';
      }
    },

    init() {
      var self = this;
      this.routeCurrentSession();

      var supabase = getSupabaseClient();
      if (supabase && supabase.auth && typeof supabase.auth.onAuthStateChange === 'function') {
        supabase.auth.onAuthStateChange(function() {
          setTimeout(function() { self.routeCurrentSession(); }, 50);
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
