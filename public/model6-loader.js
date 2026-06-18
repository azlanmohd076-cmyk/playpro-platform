/*
 * PlayPro Model 6 Dynamic Loader Bridge
 * Single-point bootstrapper for isolated Model 6 modules.
 *
 * IMPORTANT:
 * - public/index.html only needs ONE script tag: /model6-loader.js
 * - Runtime module files are served from /src/... via public/src mirror.
 */
(function attachPlayProModel6DynamicLoader(global) {
  'use strict';

  var existing = global.PlayProModel6 || {};

  global.PlayProModel6 = {
    version: '1.0.0-core',
    ready: false,
    loading: true,
    loadErrors: [],
    Core: existing.Core || {},
    LeagueOS: existing.LeagueOS || {},
    Passport: existing.Passport || {},
    Wallet: existing.Wallet || {},
    Verification: existing.Verification || {},
    Scout: existing.Scout || {},
    Coach: existing.Coach || {}
  };

  var dependencies = [
    '/src/core/supabase-client.js',
    '/src/modules/passport/passport-status.js',
    '/src/modules/league-os/eligibility-engine.js',
    '/src/modules/league-os/matchday-engine.js',
    '/src/modules/wallet/wallet.service.js',
    '/src/modules/verification/verification.service.js',
    '/src/modules/scout-marketplace/scout.service.js',
    '/src/modules/coach/coach.service.js',
    '/src/modules/coach/coach-assessment.js',
    '/src/modules/coach/coach-ui.js'
  ];

  function loadScript(src) {
    return new Promise(function(resolve, reject) {
      var script = document.createElement('script');
      script.src = src;
      script.async = false;
      script.defer = false;
      script.onload = function() { resolve(src); };
      script.onerror = function() {
        reject(new Error('Gagal memuatkan komponen Model 6: ' + src));
      };
      document.head.appendChild(script);
    });
  }

  function loadSequentially(list) {
    return list.reduce(function(chain, src) {
      return chain.then(function() { return loadScript(src); });
    }, Promise.resolve());
  }

  loadSequentially(dependencies)
    .then(function() {
      global.PlayProModel6.ready = true;
      global.PlayProModel6.loading = false;
      global.PlayProModel6.loadedAt = new Date().toISOString();

      console.log('🚀 [PlayPro Model 6] Kesemua enjin modular berjaya diaktifkan.');
      document.dispatchEvent(new CustomEvent('PlayProModel6Ready', {
        detail: {
          version: global.PlayProModel6.version,
          dependencies: dependencies.slice()
        }
      }));
    })
    .catch(function(err) {
      global.PlayProModel6.ready = false;
      global.PlayProModel6.loading = false;
      global.PlayProModel6.loadErrors.push(err && err.message ? err.message : String(err));

      console.error('❌ [PlayPro Model 6] Kegagalan kritikal memuatkan infrastruktur:', err);
      document.dispatchEvent(new CustomEvent('PlayProModel6Failed', {
        detail: {
          error: err && err.message ? err.message : String(err),
          dependencies: dependencies.slice()
        }
      }));
    });
})(window);
