/*
 * PlayPro Model 6 — Core Supabase Client Bridge
 * Pure bridge only. It reuses the existing legacy Supabase client when present.
 */
(function attachModel6SupabaseClient(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};

  function resolveExistingClient() {
    try {
      if (typeof SB !== 'undefined' && SB && typeof SB.from === 'function') {
        return SB;
      }
    } catch (ignore) {}

    if (root.SB && typeof root.SB.from === 'function') {
      return root.SB;
    }

    if (bridge.Core.supabase && typeof bridge.Core.supabase.from === 'function') {
      return bridge.Core.supabase;
    }

    if (
      root.supabase &&
      typeof root.supabase.createClient === 'function' &&
      root.PLAYPRO_SUPABASE_URL &&
      root.PLAYPRO_SUPABASE_ANON_KEY
    ) {
      return root.supabase.createClient(
        root.PLAYPRO_SUPABASE_URL,
        root.PLAYPRO_SUPABASE_ANON_KEY,
        { auth: { persistSession: true, autoRefreshToken: true } }
      );
    }

    return null;
  }

  bridge.Core.supabase = resolveExistingClient();
  bridge.Core.status = bridge.Core.supabase ? 'ready' : 'supabase_client_not_ready';
  bridge.Core.getSupabase = function getSupabase() {
    if (!bridge.Core.supabase) {
      bridge.Core.supabase = resolveExistingClient();
      bridge.Core.status = bridge.Core.supabase ? 'ready' : 'supabase_client_not_ready';
    }
    return bridge.Core.supabase;
  };
})(typeof window !== 'undefined' ? window : globalThis);
