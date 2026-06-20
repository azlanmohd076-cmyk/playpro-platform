/*
 * PlayPro Model 6 — Coach Assessment Engine / Secure Video Mock Exam
 * Pure service layer only. Not connected to legacy public/index.html UI yet.
 *
 * Security model:
 * - Master benchmarks are NOT stored in frontend.
 * - Grading is performed by PostgreSQL RPC process_coach_mock_exam_result.
 * - RPC enforces 3 attempts + 12-hour cooldown + RLS-hidden benchmark vault.
 */
(function attachCoachAssessmentEngine(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Core = bridge.Core || {};
  bridge.Coach = bridge.Coach || {};

  var DEFAULT_COACH_ATTRIBUTES = {
    judging_ability: 0,
    judging_potential: 0,
    tactical_knowledge: 0,
    coaching_outfield: 0,
    coaching_goalkeepers: 0,
    technical_coaching: 0,
    attacking_coaching: 0,
    defending_coaching: 0,
    fitness_coaching: 0,
    set_piece_coaching: 0,
    man_management: 0,
    motivating: 0,
    discipline_management: 0,
    physiotherapy: 0,
    sports_science: 0,
    working_with_youngsters: 0,
    adaptability: 0,
    determination: 0,
    data_analysis: 0,
    communication: 0,
    coaching_style: 0
  };

  function getSupabaseClient() {
    return bridge.Core.supabase || root.supabase || null;
  }

  function asNumber(value) {
    var n = Number(value);
    return Number.isFinite(n) ? n : NaN;
  }

  function safeFail(reason, extra) {
    return Object.assign({ ok: false, status: 'ERROR', reason: reason }, extra || {});
  }

  function safeErrorMessage(error) {
    if (!error) return 'UNKNOWN_ERROR';
    return error.message || error.details || error.hint || String(error);
  }

  function licenseRank(licenseType) {
    var l = String(licenseType || '').toLowerCase();
    if (l.indexOf('pro') !== -1 || l.indexOf('diploma') !== -1) return 5;
    if (l.indexOf('lesen a') !== -1 || l.indexOf('afc a') !== -1 || l.indexOf('fam a') !== -1) return 4;
    if (l.indexOf('lesen b') !== -1 || l.indexOf('afc b') !== -1 || l.indexOf('fam b') !== -1) return 3;
    if (l.indexOf('lesen c') !== -1 || l.indexOf('afc c') !== -1 || l.indexOf('fam c') !== -1) return 2;
    if (l.indexOf('lesen d') !== -1 || l.indexOf('grassroots') !== -1) return 1;
    return 0;
  }

  function buildAttributesByLicense(licenseType) {
    var rank = licenseRank(licenseType);
    var base = Object.assign({}, DEFAULT_COACH_ATTRIBUTES);
    if (rank === 0) return base;

    var bump = [0, 0, 8, 12, 15, 17][rank];
    Object.keys(base).forEach(function(key) {
      base[key] = Math.max(0, Math.min(20, base[key] + bump));
    });

    if (rank >= 2) {
      base.tactical_knowledge = Math.min(20, base.tactical_knowledge + 2);
      base.coaching_outfield = Math.min(20, base.coaching_outfield + 2);
      base.technical_coaching = Math.min(20, base.technical_coaching + 2);
    }
    if (String(licenseType || '').toLowerCase().indexOf('gk') !== -1) {
      base.coaching_goalkeepers = Math.max(base.coaching_goalkeepers, 18);
      base.coaching_outfield = Math.min(base.coaching_outfield, 10);
    }
    return base;
  }

  function sanitizeSubmittedScores(submittedScores) {
    var input = submittedScores || {};
    var output = {};
    Object.keys(input).forEach(function(key) {
      var n = asNumber(input[key]);
      if (Number.isFinite(n)) {
        output[key] = n;
      }
    });
    return output;
  }

  var CoachAssessmentEngine = {
    /**
     * Submit video mock exam through secure backend RPC.
     *
     * Formula is executed in DB:
     *   averageAbsoluteError = AVG(ABS(submittedScore - masterBenchmarkScore))
     * Passing threshold in DB:
     *   averageAbsoluteError <= 1.5
     *
     * @param {string} profileId - UUID profiles.id coach/assessor.
     * @param {Object} submittedScores - 21 attribute scores, scale 1-20.
     * @returns {Promise<Object>}
     */
    async submitVideoMockExam(profileId, submittedScores) {
      try {
        if (!profileId) {
          return safeFail('PROFILE_ID_TIDAK_LENGKAP', {
            message: 'Profil jurulatih tidak ditemui.'
          });
        }

        var supabase = getSupabaseClient();
        if (!supabase || typeof supabase.rpc !== 'function') {
          return safeFail('SUPABASE_RPC_NOT_READY', {
            message: 'Sambungan sistem penarafan belum bersedia.'
          });
        }

        var payload = sanitizeSubmittedScores(submittedScores);
        var result = await supabase.rpc('process_coach_mock_exam_result', {
          p_profile_id: profileId,
          p_submitted_scores: payload
        });

        if (result.error) {
          console.error('Ralat RPC process_coach_mock_exam_result:', result.error);
          return safeFail('RPC_PROCESS_COACH_MOCK_EXAM_FAILED', {
            message: 'Sistem ujian video sedang terganggu. Sila cuba lagi nanti.',
            error: safeErrorMessage(result.error),
            code: result.error.code || null
          });
        }

        var data = result.data || {};

        if (data.success === true) {
          return {
            ok: true,
            status: data.status || 'PASSED',
            newGrade: data.newGrade || 'GRED_2_CERTIFIED_ASSESSOR',
            message: data.message || 'Tahniah. Anda telah lulus Ujian Video PCSAP.',
            errorMargin: data.errorMargin !== undefined ? data.errorMargin : null,
            data: data
          };
        }

        return {
          ok: true,
          status: data.status || 'FAILED',
          reason: data.reason || 'EXAM_FAILED',
          message: data.message || 'Keputusan ujian tidak mencapai standard penarafan. Sila cuba lagi.',
          cooldownUntil: data.cooldownUntil || null,
          data: data
        };
      } catch (err) {
        console.error('Ralat Coach Mock Exam Engine:', err);
        return safeFail('RALAT_SISTEM_MOCK_EXAM', {
          message: 'Sistem ujian video sedang terganggu. Sila cuba lagi nanti.',
          error: safeErrorMessage(err)
        });
      }
    },

    /**
     * Return 21 coach attributes for profile display.
     * Current source order:
     * 1) certified_assessors.metadata.coach_attributes if available.
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
          if (caps.isCertified) {
            attrs = buildAttributesByLicense(caps.licenseType || (caps.metadata && caps.metadata.license_type));
          }
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
                if (Number.isFinite(v)) attrs[key] = Math.max(0, Math.min(20, Math.floor(v)));
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
