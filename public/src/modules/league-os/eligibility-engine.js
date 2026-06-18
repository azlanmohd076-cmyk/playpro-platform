/*
 * PlayPro Model 6 — League OS Eligibility Engine
 * Pure service layer only. Not connected to legacy public/index.html yet.
 *
 * Responsibility:
 * - Verify age-group eligibility using competition reference year.
 * - Check active disciplinary suspension from existing suspensions table.
 */
(function attachEligibilityEngine(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};
  bridge.LeagueOS = bridge.LeagueOS || {};

  function getSupabaseClient() {
    return bridge.Core.supabase || root.supabase || null;
  }

  function parseYearFromDob(dobString) {
    if (!dobString) return null;
    var dob = new Date(dobString);
    if (isNaN(dob.getTime())) return null;
    return dob.getFullYear();
  }

  function normalizeReason(data) {
    if (!data) return 'Hukuman Kad/Disiplin';
    return data.reason_notes || data.suspension_reason || 'Hukuman Kad/Disiplin';
  }

  var EligibilityEngine = {
    /**
     * Menapis penipuan umur berdasarkan DOB vs peraturan liga.
     * Formula standard: Tahun Kejohanan - Tahun Lahir.
     *
     * @param {string} dobString - Format tarikh lahir, contoh 'YYYY-MM-DD'.
     * @param {number} minAge - Had umur minimum liga.
     * @param {number} maxAge - Had umur maksimum liga.
     * @param {number} referenceYear - Tahun rujukan pertandingan.
     * @returns {{isEligible: boolean, calculatedAge: number, reason: string|null}}
     */
    verifyAgeGroup(dobString, minAge, maxAge, referenceYear) {
      var refYear = Number(referenceYear || new Date().getFullYear());
      var min = Number(minAge);
      var max = Number(maxAge);
      var birthYear = parseYearFromDob(dobString);

      if (!birthYear || !min || !max || min > max) {
        return { isEligible: false, calculatedAge: 0, reason: 'DATA_UMUR_TIDAK_LENGKAP' };
      }

      var calculatedAge = refYear - birthYear;
      var isEligible = calculatedAge >= min && calculatedAge <= max;

      return {
        isEligible: isEligible,
        calculatedAge: calculatedAge,
        reason: isEligible ? null : 'HAD_UMUR_TIDAK_SAH'
      };
    },

    /**
     * Menyemak sama ada pemain sedang menjalani hukuman penggantungan.
     * Uses existing production schema: suspensions.is_active,
     * matches_suspended, matches_served, suspension_reason, reason_notes.
     *
     * @param {string} playerId - UUID pemain.
     * @param {string} leagueId - UUID liga.
     * @param {string} matchDateString - Reserved for future dated suspension rules.
     * @returns {Promise<{isSuspended: boolean, reason: string|null, data: Object|null}>}
     */
    async checkSuspension(playerId, leagueId, matchDateString) {
      try {
        if (!playerId || !leagueId) {
          return {
            isSuspended: true,
            reason: 'PARAMETER_PENGGANTUNGAN_TIDAK_LENGKAP',
            data: null
          };
        }

        var supabase = getSupabaseClient();
        if (!supabase || typeof supabase.from !== 'function') {
          return {
            isSuspended: true,
            reason: 'SUPABASE_CLIENT_NOT_READY',
            data: null
          };
        }

        var result = await supabase
          .from('suspensions')
          .select('id,player_id,league_id,suspension_reason,reason_notes,matches_suspended,matches_served,is_active,created_at,updated_at')
          .eq('player_id', playerId)
          .eq('league_id', leagueId)
          .eq('is_active', true)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();

        if (result.error) throw result.error;

        if (result.data) {
          return {
            isSuspended: true,
            reason: 'GANTUNG_PERLAWANAN: ' + normalizeReason(result.data),
            data: result.data
          };
        }

        return { isSuspended: false, reason: null, data: null };
      } catch (err) {
        console.error('Ralat Suspension Engine:', err);
        return {
          isSuspended: true,
          reason: 'RALAT_SEMAKAN_PENGGANTUNGAN_SISTEM',
          data: null
        };
      }
    }
  };

  bridge.LeagueOS = Object.assign({}, bridge.LeagueOS, {
    EligibilityEngine: EligibilityEngine
  });
})(typeof window !== 'undefined' ? window : globalThis);
