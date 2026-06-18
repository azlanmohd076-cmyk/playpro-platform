/*
 * PlayPro Model 6 — Coach Assessment Engine / Video Mock Exam
 * Pure service layer only. Not connected to legacy public/index.html UI yet.
 *
 * Purpose:
 * - Test coach judging ability against Master Assessor benchmark.
 * - Auto-qualify to GRED 2 if average absolute error <= 1.5.
 * - Fail closed if Supabase is unavailable.
 */
(function attachCoachAssessmentEngine(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};
  bridge.Coach = bridge.Coach || {};

  var PASSING_ERROR_MARGIN = 1.5;

  var MASTER_BENCHMARKS = {
    judging_ability: 16,
    judging_potential: 15,
    tactical_knowledge: 14,
    coaching_outfield: 15,
    coaching_goalkeepers: 10,
    technical_coaching: 15,
    attacking_coaching: 14,
    defending_coaching: 13,
    fitness_coaching: 12,
    set_piece_coaching: 13,
    man_management: 15,
    motivating: 16,
    discipline_management: 14,
    physiotherapy: 9,
    sports_science: 11,
    working_with_youngsters: 17,
    adaptability: 13,
    determination: 16,
    data_analysis: 12,
    communication: 15,
    coaching_style: 14
  };

  var DEFAULT_COACH_ATTRIBUTES = {
    judging_ability: 5,
    judging_potential: 5,
    tactical_knowledge: 5,
    coaching_outfield: 5,
    coaching_goalkeepers: 5,
    technical_coaching: 5,
    attacking_coaching: 5,
    defending_coaching: 5,
    fitness_coaching: 5,
    set_piece_coaching: 5,
    man_management: 5,
    motivating: 5,
    discipline_management: 5,
    physiotherapy: 5,
    sports_science: 5,
    working_with_youngsters: 5,
    adaptability: 5,
    determination: 5,
    data_analysis: 5,
    communication: 5,
    coaching_style: 5
  };

  function getSupabaseClient() {
    return bridge.Core.supabase || root.supabase || null;
  }

  function asNumber(value) {
    var n = Number(value);
    return Number.isFinite(n) ? n : NaN;
  }

  function round2(value) {
    return Math.round(value * 100) / 100;
  }

  function benchmarkKeys() {
    return Object.keys(MASTER_BENCHMARKS);
  }

  function safeFail(reason, extra) {
    return Object.assign({ ok: false, status: 'ERROR', reason: reason }, extra || {});
  }

  async function tryActivateCertifiedAssessor(profileId, errorMargin) {
    var supabase = getSupabaseClient();
    if (!supabase || typeof supabase.from !== 'function') {
      return { synced: false, reason: 'SUPABASE_CLIENT_NOT_READY' };
    }

    var payload = {
      profile_id: profileId,
      license_type: 'PCSAP_VIDEO_MOCK_EXAM',
      status: 'active',
      max_attribute_score: 20,
      trust_score: 1.00,
      updated_at: new Date().toISOString()
    };

    try {
      var result = await supabase
        .from('certified_assessors')
        .upsert(payload, { onConflict: 'profile_id' })
        .select('id,profile_id,status,max_attribute_score,license_type,updated_at')
        .maybeSingle();

      if (result.error) {
        return {
          synced: false,
          reason: 'CERTIFIED_ASSESSOR_UPDATE_FAILED',
          error: result.error.message || String(result.error),
          code: result.error.code || null
        };
      }

      return {
        synced: true,
        reason: 'CERTIFIED_ASSESSOR_ACTIVATED',
        data: result.data || null,
        errorMargin: errorMargin
      };
    } catch (err) {
      return {
        synced: false,
        reason: 'CERTIFIED_ASSESSOR_UPDATE_EXCEPTION',
        error: err && err.message ? err.message : String(err),
        errorMargin: errorMargin
      };
    }
  }

  var CoachAssessmentEngine = {
    benchmarks: Object.assign({}, MASTER_BENCHMARKS),

    /**
     * Submit video mock exam and compare submitted scores against master benchmark.
     * Formula:
     *   averageAbsoluteError = SUM(ABS(submittedScore - benchmarkScore)) / 21
     * Passing threshold:
     *   averageAbsoluteError <= 1.5
     *
     * @param {string} profileId - UUID profiles.id coach/assessor.
     * @param {Object} submittedScores - 21 attribute scores, scale 1-20.
     * @returns {Promise<Object>}
     */
    async submitVideoMockExam(profileId, submittedScores) {
      if (!profileId) {
        return safeFail('PROFILE_ID_TIDAK_LENGKAP');
      }

      var submitted = submittedScores || {};
      var keys = benchmarkKeys();
      var totalAbsError = 0;
      var breakdown = [];
      var missing = [];
      var invalid = [];

      keys.forEach(function(key) {
        var benchmark = MASTER_BENCHMARKS[key];
        var raw = submitted[key];
        var score = asNumber(raw);

        if (raw === undefined || raw === null || raw === '') {
          missing.push(key);
          return;
        }

        if (!Number.isFinite(score) || score < 1 || score > 20) {
          invalid.push(key);
          return;
        }

        var absError = Math.abs(score - benchmark);
        totalAbsError += absError;
        breakdown.push({
          attribute: key,
          submittedScore: score,
          benchmarkScore: benchmark,
          absoluteError: round2(absError)
        });
      });

      if (missing.length || invalid.length) {
        return safeFail('MOCK_EXAM_DATA_TIDAK_LENGKAP_ATAU_TIDAK_SAH', {
          missingAttributes: missing,
          invalidAttributes: invalid,
          expectedAttributeCount: keys.length
        });
      }

      var averageError = round2(totalAbsError / keys.length);
      var passed = averageError <= PASSING_ERROR_MARGIN;

      if (!passed) {
        return {
          ok: true,
          status: 'FAILED',
          newGrade: 'GRED_1_DAILY_COACH',
          errorMargin: averageError,
          passingErrorMargin: PASSING_ERROR_MARGIN,
          activation: { synced: false, reason: 'NOT_ELIGIBLE' },
          breakdown: breakdown
        };
      }

      var activation = await tryActivateCertifiedAssessor(profileId, averageError);

      return {
        ok: true,
        status: 'PASSED',
        newGrade: 'GRED_2_CERTIFIED_ASSESSOR',
        errorMargin: averageError,
        passingErrorMargin: PASSING_ERROR_MARGIN,
        activation: activation,
        breakdown: breakdown
      };
    },

    /**
     * Return 21 coach attributes for profile display.
     * Current source order:
     * 1) certified_assessors.metadata.coach_attributes if available later.
     * 2) default GRED 1 baseline attributes.
     *
     * @param {string} profileId - UUID profiles.id coach.
     * @returns {Promise<{ok:boolean, grade:string, attributes:Object, categories:Object}>}
     */
    async getCoachAttributes(profileId) {
      var attrs = Object.assign({}, DEFAULT_COACH_ATTRIBUTES);
      var grade = 'GRED_1_DAILY_COACH';
      var caps = null;

      try {
        if (bridge.Coach && typeof bridge.Coach.getCoachCapabilities === 'function') {
          caps = await bridge.Coach.getCoachCapabilities(profileId);
          grade = caps.grade || grade;
        }

        var supabase = getSupabaseClient();
        if (profileId && supabase && typeof supabase.from === 'function') {
          var result = await supabase
            .from('certified_assessors')
            .select('status,max_attribute_score,metadata')
            .eq('profile_id', profileId)
            .maybeSingle();

          if (!result.error && result.data && result.data.metadata && result.data.metadata.coach_attributes) {
            Object.keys(attrs).forEach(function(key) {
              if (result.data.metadata.coach_attributes[key] !== undefined) {
                var v = asNumber(result.data.metadata.coach_attributes[key]);
                if (Number.isFinite(v)) attrs[key] = Math.max(1, Math.min(20, Math.floor(v)));
              }
            });
          }
        }

        return {
          ok: true,
          grade: grade,
          isCertified: !!(caps && caps.isCertified),
          maxScore: caps ? caps.maxScore : 5,
          attributes: attrs,
          categories: {
            field: [
              'judging_ability', 'judging_potential', 'tactical_knowledge',
              'coaching_outfield', 'coaching_goalkeepers', 'technical_coaching',
              'attacking_coaching', 'defending_coaching', 'fitness_coaching',
              'set_piece_coaching'
            ],
            support: [
              'man_management', 'motivating', 'discipline_management',
              'physiotherapy', 'sports_science', 'working_with_youngsters',
              'adaptability', 'determination', 'data_analysis',
              'communication', 'coaching_style'
            ]
          }
        };
      } catch (err) {
        console.error('Ralat Coach Attributes Engine:', err);
        return {
          ok: false,
          grade: 'FALLBACK_GRED_1',
          isCertified: false,
          maxScore: 5,
          attributes: attrs,
          categories: {
            field: [],
            support: []
          }
        };
      }
    }
  };

  bridge.Coach = Object.assign({}, bridge.Coach, CoachAssessmentEngine);
})(typeof window !== 'undefined' ? window : globalThis);
