/*
 * PlayPro Model 6 — Football Passport Status Service
 * Pure service layer only. Not connected to legacy public/index.html yet.
 *
 * Responsibility:
 * - Check whether a player has an active Football Passport for a season.
 * - Return safe, explicit reason codes for League OS eligibility decisions.
 */
(function attachPassportStatusService(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};
  bridge.Passport = bridge.Passport || {};

  function getSupabaseClient() {
    return bridge.Core.supabase || root.supabase || null;
  }

  function toDateOnly(value) {
    if (!value) return null;
    if (value instanceof Date && !isNaN(value.getTime())) {
      return value.toISOString().slice(0, 10);
    }
    var date = new Date(value);
    if (isNaN(date.getTime())) return null;
    return date.toISOString().slice(0, 10);
  }

  function normalizeStatus(status) {
    return String(status || '').trim().toLowerCase();
  }

  var PassportStatusService = {
    /**
     * Menyemak sama ada pemain mempunyai passport aktif untuk musim liga semasa.
     *
     * @param {string} playerId - UUID pemain.
     * @param {string} seasonId - UUID musim kejohanan.
     * @param {Object} options - Optional: { asOfDate: Date|string }.
     * @returns {Promise<{isActive: boolean, reason: string, data: Object|null}>}
     */
    async checkActivePassport(playerId, seasonId, options) {
      try {
        if (!playerId || !seasonId) {
          return { isActive: false, reason: 'PARAMETER_TIDAK_LENGKAP', data: null };
        }

        var supabase = getSupabaseClient();
        if (!supabase || typeof supabase.from !== 'function') {
          return { isActive: false, reason: 'SUPABASE_CLIENT_NOT_READY', data: null };
        }

        var query = supabase
          .from('player_passports')
          .select('*')
          .eq('player_id', playerId)
          .eq('season_id', seasonId)
          .maybeSingle();

        var result = await query;
        var data = result.data;
        var error = result.error;

        if (error) throw error;

        if (!data) {
          return { isActive: false, reason: 'TIADA_PASSPORT_DAFTAR', data: null };
        }

        var today = toDateOnly((options && options.asOfDate) || new Date());
        var expiryDate = toDateOnly(data.tarikh_tamat);
        var status = normalizeStatus(data.status);
        var statusAllowed = status === 'active' || status === 'approved' || status === 'verified';

        if (!statusAllowed) {
          return { isActive: false, reason: 'PASSPORT_BELUM_DISAHKAN', data: data };
        }

        if (data.status_aktif !== true) {
          return { isActive: false, reason: 'PASSPORT_TIDAK_AKTIF', data: data };
        }

        if (!expiryDate || today > expiryDate) {
          return { isActive: false, reason: 'PASSPORT_TAMAT_TEMPOH', data: data };
        }

        return { isActive: true, reason: 'PASSPORT_VALID', data: data };
      } catch (err) {
        console.error('Ralat Passport Engine:', err);
        return { isActive: false, reason: 'RALAT_SISTEM_PASSPORT', data: null };
      }
    }
  };

  bridge.Passport = Object.assign({}, bridge.Passport, PassportStatusService);
})(typeof window !== 'undefined' ? window : globalThis);
