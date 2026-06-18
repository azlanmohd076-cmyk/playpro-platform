/*
 * PlayPro Model 6 — Scout Marketplace Access Control Service
 * Pure service layer only. Not connected to legacy public/index.html yet.
 *
 * Responsibility:
 * - Verify B2B scout subscription tier before sensitive data access.
 * - Fail closed when subscription is missing, expired, insufficient, or table is not ready.
 */
(function attachScoutMarketplaceService(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};
  bridge.Scout = bridge.Scout || {};

  var TIER_RANK = {
    none: 0,
    basic: 1,
    scout_basic: 1,
    pro: 2,
    scout_pro: 2,
    elite: 3,
    scout_elite: 3
  };

  function getSupabaseClient() {
    return bridge.Core.supabase || root.supabase || null;
  }

  function normalizeTier(tier) {
    return String(tier || '').trim().toLowerCase().replace(/\s+/g, '_');
  }

  function normalizeStatus(status) {
    return String(status || '').trim().toLowerCase();
  }

  function toDateOnly(value) {
    if (!value) return null;
    var date = value instanceof Date ? value : new Date(value);
    if (isNaN(date.getTime())) return null;
    return date.toISOString().slice(0, 10);
  }

  function fail(reason, extra) {
    return Object.assign({
      allowed: false,
      reason: reason,
      currentTier: null,
      requiredTier: null,
      expiresAt: null,
      data: null
    }, extra || {});
  }

  function tierRank(tier) {
    return TIER_RANK[normalizeTier(tier)] || 0;
  }

  var ScoutMarketplaceService = {
    /**
     * Menyemak sama ada profile scout mempunyai tier mencukupi.
     * Expected future table: scout_subscriptions.
     * Suggested columns:
     * - profile_id
     * - tier / access_tier / plan_code
     * - status
     * - valid_until / current_period_end / expires_at
     *
     * @param {string} profileId - UUID profiles.id scout/B2B user.
     * @param {string} requiredTier - basic | pro | elite.
     * @param {Object} options - Optional: { asOfDate: Date|string }.
     * @returns {Promise<{allowed:boolean, reason:string, currentTier:string|null, requiredTier:string, expiresAt:string|null, data:Object|null}>}
     */
    async verifyScoutAccessTier(profileId, requiredTier, options) {
      try {
        var required = normalizeTier(requiredTier || 'basic');
        if (!profileId) {
          return fail('PROFILE_ID_TIDAK_LENGKAP', { requiredTier: required });
        }

        if (!TIER_RANK[required]) {
          return fail('REQUIRED_TIER_TIDAK_SAH', { requiredTier: required });
        }

        var supabase = getSupabaseClient();
        if (!supabase || typeof supabase.from !== 'function') {
          return fail('SUPABASE_CLIENT_NOT_READY', { requiredTier: required });
        }

        var result = await supabase
          .from('scout_subscriptions')
          .select('*')
          .eq('profile_id', profileId)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();

        if (result.error) {
          // 42P01 = undefined_table. Fail closed because Scout Marketplace
          // subscription table has not been deployed yet.
          if (result.error.code === '42P01') {
            return fail('SCOUT_SUBSCRIPTIONS_TABLE_NOT_READY', {
              requiredTier: required,
              error: result.error.message
            });
          }
          throw result.error;
        }

        if (!result.data) {
          return fail('SCOUT_SUBSCRIPTION_TIDAK_WUJUD', { requiredTier: required });
        }

        var row = result.data;
        var currentTier = normalizeTier(row.tier || row.access_tier || row.plan_code || row.subscription_tier);
        var status = normalizeStatus(row.status);
        var expiresAt = row.valid_until || row.current_period_end || row.expires_at || null;
        var today = toDateOnly((options && options.asOfDate) || new Date());
        var expiry = toDateOnly(expiresAt);

        var statusOk = status === 'active' || status === 'approved' || status === 'paid' || status === 'trialing';
        if (!statusOk) {
          return fail('SCOUT_SUBSCRIPTION_TIDAK_AKTIF', {
            currentTier: currentTier,
            requiredTier: required,
            expiresAt: expiresAt,
            data: row
          });
        }

        if (expiry && today > expiry) {
          return fail('SCOUT_SUBSCRIPTION_TAMAT_TEMPOH', {
            currentTier: currentTier,
            requiredTier: required,
            expiresAt: expiresAt,
            data: row
          });
        }

        if (tierRank(currentTier) < tierRank(required)) {
          return fail('SCOUT_TIER_TIDAK_MENCUKUPI', {
            currentTier: currentTier,
            requiredTier: required,
            expiresAt: expiresAt,
            data: row
          });
        }

        return {
          allowed: true,
          reason: 'SCOUT_ACCESS_GRANTED',
          currentTier: currentTier,
          requiredTier: required,
          expiresAt: expiresAt,
          data: row
        };
      } catch (err) {
        console.error('Ralat Scout Marketplace Access Engine:', err);
        return fail('RALAT_SEMAKAN_SCOUT_ACCESS', {
          requiredTier: normalizeTier(requiredTier || 'basic'),
          error: err && (err.message || err.details || err.hint) ? (err.message || err.details || err.hint) : String(err)
        });
      }
    },

    /**
     * Helper for future modules to guard sensitive data reads.
     * Examples:
     * - player_market_values: required scout_pro
     * - full scout report: required scout_elite
     */
    async canAccessSensitiveData(profileId, dataType) {
      var map = {
        basic_profile: 'basic',
        potential_score: 'basic',
        player_market_value: 'pro',
        video_metrics: 'pro',
        full_scout_report: 'elite',
        ai_prediction: 'elite',
        transfer_facilitation: 'elite'
      };
      var required = map[normalizeTier(dataType)] || 'elite';
      return this.verifyScoutAccessTier(profileId, required);
    }
  };

  bridge.Scout = Object.assign({}, bridge.Scout, ScoutMarketplaceService);
})(typeof window !== 'undefined' ? window : globalThis);
