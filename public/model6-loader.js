/*
 * PlayPro Model 6 Loader Bridge
 * Safe global namespace bridge for legacy SPA integration.
 * This file is intentionally isolated from public/index.html for now.
 * Future integration point:
 *   window.PlayProModel6.Passport.checkActivePassport(...)
 */
(function attachPlayProModel6Bridge(global) {
  'use strict';

  if (global.PlayProModel6) {
    return;
  }

  global.PlayProModel6 = {
    version: '0.1.0-placeholder',
    ready: false,

    Core: {
      status: 'placeholder'
    },

    LeagueOS: {
      status: 'placeholder'
    },

    Passport: {
      status: 'placeholder'
    },

    Wallet: {
      status: 'placeholder'
    },

    Verification: {
      status: 'placeholder'
    },

    Scout: {
      status: 'placeholder'
    }
  };
})(window);
