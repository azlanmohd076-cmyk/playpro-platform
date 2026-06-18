/*
 * PlayPro Model 6 — Verification Seal Service
 * Pure service layer only. Not connected to legacy public/index.html yet.
 *
 * Responsibility:
 * - Check whether an organization has an active PlayPro Verification Seal.
 * - Fail closed if Supabase/client/table state is not ready.
 */
(function attachVerificationService(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};
  bridge.Verification = bridge.Verification || {};

  function getSupabaseClient() {
    return bridge.Core.supabase || root.supabase || null;
  }

  function toDateOnly(value) {
    if (!value) return null;
    var date = value instanceof Date ? value : new Date(value);
    if (isNaN(date.getTime())) return null;
    return date.toISOString().slice(0, 10);
  }

  function normalizeStatus(status) {
    return String(status || '').trim().toLowerCase();
  }

  function emptyResult(reason) {
    return {
      isVerified: false,
      reason: reason,
      sealCode: null,
      package: null,
      expiresAt: null,
      data: null
    };
  }

  var VerificationService = {
    /**
     * Menyemak sama ada organisasi/akademi mempunyai Seal aktif.
     * Production enum currently uses 'verified'. The service also accepts
     * 'approved' defensively for future naming compatibility.
     *
     * @param {string} organizationId - UUID organizations.id.
     * @param {Object} options - Optional: { asOfDate: Date|string }.
     * @returns {Promise<{isVerified:boolean, reason:string, sealCode:string|null, package:string|null, expiresAt:string|null, data:Object|null}>}
     */
    async checkOrganizationVerification(organizationId, options) {
      try {
        if (!organizationId) {
          return emptyResult('ORGANIZATION_ID_TIDAK_LENGKAP');
        }

        var supabase = getSupabaseClient();
        if (!supabase || typeof supabase.from !== 'function') {
          return emptyResult('SUPABASE_CLIENT_NOT_READY');
        }

        var result = await supabase
          .from('organization_verifications')
          .select('id,organization_id,status,seal_code,package_name,valid_from,valid_until,paid_at,approved_at,metadata')
          .eq('organization_id', organizationId)
          .order('valid_until', { ascending: false })
          .limit(1)
          .maybeSingle();

        if (result.error) throw result.error;

        if (!result.data) {
          return emptyResult('SEAL_TIDAK_WUJUD');
        }

        var row = result.data;
        var today = toDateOnly((options && options.asOfDate) || new Date());
        var expiry = toDateOnly(row.valid_until);
        var status = normalizeStatus(row.status);
        var statusOk = status === 'verified' || status === 'approved';
        var dateOk = !!expiry && today <= expiry;

        if (!statusOk) {
          return Object.assign(emptyResult('SEAL_BELUM_DILULUSKAN'), { data: row });
        }

        if (!dateOk) {
          return Object.assign(emptyResult('SEAL_TAMAT_TEMPOH'), { data: row });
        }

        return {
          isVerified: true,
          reason: 'SEAL_VALID',
          sealCode: row.seal_code || null,
          package: row.package_name || null,
          expiresAt: row.valid_until || null,
          data: row
        };
      } catch (err) {
        console.error('Ralat Verification Seal Engine:', err);
        return emptyResult('RALAT_SEMAKAN_VERIFICATION_SEAL');
      }
    }
  };

  bridge.Verification = Object.assign({}, bridge.Verification, VerificationService);
})(typeof window !== 'undefined' ? window : globalThis);
