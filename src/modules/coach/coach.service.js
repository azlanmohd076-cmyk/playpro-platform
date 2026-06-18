/*
 * PlayPro Model 6 — Coach Permission Layer / Assessment Score Guard
 * Pure service layer only. Not connected to legacy public/index.html UI yet.
 *
 * Data Integrity & Anti-Inflation Rule:
 * - GRED 1: daily/non-certified coach => max 5 per attribute.
 * - GRED 2: active certified assessor/PCSAP => max_attribute_score, capped at 20.
 * - Fail closed: if DB/client/error occurs, fallback to GRED 1.
 */
(function attachCoachPassportService(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};
  bridge.Coach = bridge.Coach || {};

  function getSupabaseClient() {
    return bridge.Core.supabase || root.supabase || null;
  }

  function toNumber(value) {
    var n = Number(value);
    return Number.isFinite(n) ? n : NaN;
  }

  function clampMaxScore(value) {
    var n = toNumber(value);
    if (!Number.isFinite(n)) return 20;
    if (n < 1) return 1;
    if (n > 20) return 20;
    return Math.floor(n);
  }

  function fallbackCaps(reason) {
    return {
      isCertified: false,
      maxScore: 5,
      grade: reason || 'GRED_1_DAILY_COACH',
      licenseType: null,
      certificateUrl: null,
      trustScore: null,
      data: null
    };
  }

  var CoachPassportService = {
    /**
     * Menyemak gred kuasa dan had mata maksimum bagi seseorang jurulatih.
     *
     * @param {string} profileId - UUID profil jurulatih/assessor.
     * @returns {Promise<{isCertified:boolean,maxScore:number,grade:string,licenseType:string|null,certificateUrl:string|null,trustScore:number|null,data:Object|null}>}
     */
    async getCoachCapabilities(profileId) {
      try {
        if (!profileId) {
          return fallbackCaps('PROFILE_ID_TIDAK_LENGKAP');
        }

        var supabase = getSupabaseClient();
        if (!supabase || typeof supabase.from !== 'function') {
          return fallbackCaps('SUPABASE_CLIENT_NOT_READY');
        }

        var result = await supabase
          .from('certified_assessors')
          .select('id,profile_id,license_type,certificate_url,status,trust_score,max_attribute_score,updated_at')
          .eq('profile_id', profileId)
          .eq('status', 'active')
          .maybeSingle();

        if (result.error) {
          if (result.error.code === '42P01') {
            return fallbackCaps('CERTIFIED_ASSESSORS_TABLE_NOT_READY');
          }
          throw result.error;
        }

        if (!result.data) {
          return fallbackCaps('GRED_1_DAILY_COACH');
        }

        return {
          isCertified: true,
          maxScore: clampMaxScore(result.data.max_attribute_score || 20),
          grade: 'GRED_2_CERTIFIED_ASSESSOR',
          licenseType: result.data.license_type || null,
          certificateUrl: result.data.certificate_url || null,
          trustScore: result.data.trust_score !== null ? Number(result.data.trust_score) : null,
          data: result.data
        };
      } catch (err) {
        console.error('Ralat Coach Permission Engine:', err);
        return fallbackCaps('FALLBACK_GRED_1');
      }
    },

    /**
     * Memvalidasi senarai markah atribut mengikut had kelayakan gred jurulatih.
     *
     * @param {string} profileId - UUID jurulatih/assessor.
     * @param {Object} attributesObj - Contoh: { pace: 18, passing: 12, shooting: 5 }.
     * @returns {Promise<{isValid:boolean,reason:string|null,maxScore:number,grade:string,violations:Array}>}
     */
    async validateAssessmentScores(profileId, attributesObj) {
      var caps = await this.getCoachCapabilities(profileId);
      var attrs = attributesObj || {};
      var violations = [];

      Object.keys(attrs).forEach(function(key) {
        var score = toNumber(attrs[key]);

        if (!Number.isFinite(score)) {
          violations.push({
            attribute: key,
            score: attrs[key],
            reason: 'MARKAH_BUKAN_NOMBOR'
          });
          return;
        }

        if (score < 0) {
          violations.push({
            attribute: key,
            score: score,
            reason: 'MARKAH_NEGATIF_TIDAK_DIBENARKAN'
          });
          return;
        }

        if (score > caps.maxScore) {
          violations.push({
            attribute: key,
            score: score,
            maxScore: caps.maxScore,
            reason: 'HAD_MARKAH_DILANGGARI'
          });
        }
      });

      if (violations.length) {
        return {
          isValid: false,
          reason: 'HAD_MARKAH_DILANGGARI: Gred akaun anda (' + caps.grade + ') hanya membenarkan input markah maksima sebanyak ' + caps.maxScore + ' mata bagi setiap atribut.',
          maxScore: caps.maxScore,
          grade: caps.grade,
          violations: violations
        };
      }

      return {
        isValid: true,
        reason: null,
        maxScore: caps.maxScore,
        grade: caps.grade,
        violations: []
      };
    }
  };

  bridge.Coach = Object.assign({}, bridge.Coach, CoachPassportService);
})(typeof window !== 'undefined' ? window : globalThis);
