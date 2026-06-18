/*
 * PlayPro Model 6 — League OS Matchday Engine
 * Pure orchestration layer only. Not connected to legacy public/index.html yet.
 *
 * Responsibility:
 * - Validate full matchday squad before players enter the pitch.
 * - Combine passport, age-group, and suspension checks.
 */
(function attachMatchdayEngine(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Passport = bridge.Passport || {};
  bridge.LeagueOS = bridge.LeagueOS || {};

  function todayDateOnly() {
    return new Date().toISOString().slice(0, 10);
  }

  function getPlayerName(player) {
    return player.name || player.preferred_name || player.full_name || player.nickname || 'Pemain';
  }

  function getPlayerDob(player) {
    return player.dob || player.date_of_birth || player.tarikh_lahir || null;
  }

  function getReferenceYear(leagueRules) {
    return Number(leagueRules.referenceYear || leagueRules.reference_year || new Date().getFullYear());
  }

  function makeBlockedReport(player, reason) {
    return {
      playerId: player && player.id ? player.id : null,
      playerName: player ? getPlayerName(player) : 'Pemain',
      passportValid: false,
      ageValid: false,
      notSuspended: false,
      overallEligible: false,
      blockReason: [reason],
      details: {}
    };
  }

  var MatchdayEngine = {
    /**
     * Mengesahkan kelayakan seluruh pasukan untuk matchday sheet.
     *
     * @param {string} leagueId - UUID liga.
     * @param {string} seasonId - UUID musim.
     * @param {Array<Object>} squadPlayers - [{ id, dob/date_of_birth, name }].
     * @param {Object} leagueRules - { minAge, maxAge, referenceYear }.
     * @returns {Promise<{squadValid: boolean, report: Array<Object>}>}
     */
    async validateMatchdaySquad(leagueId, seasonId, squadPlayers, leagueRules) {
      var report = [];
      var squadValid = true;
      var players = Array.isArray(squadPlayers) ? squadPlayers : [];
      var rules = leagueRules || {};
      var matchDate = rules.matchDate || rules.match_date || todayDateOnly();

      if (!leagueId || !seasonId) {
        return {
          squadValid: false,
          report: [makeBlockedReport({}, 'PARAMETER_LIGA_ATAU_MUSIM_TIDAK_LENGKAP')]
        };
      }

      if (!players.length) {
        return {
          squadValid: false,
          report: [makeBlockedReport({}, 'SENARAI_PEMAIN_KOSONG')]
        };
      }

      if (!bridge.Passport || typeof bridge.Passport.checkActivePassport !== 'function') {
        return {
          squadValid: false,
          report: [makeBlockedReport({}, 'PASSPORT_ENGINE_NOT_READY')]
        };
      }

      if (!bridge.LeagueOS || !bridge.LeagueOS.EligibilityEngine) {
        return {
          squadValid: false,
          report: [makeBlockedReport({}, 'ELIGIBILITY_ENGINE_NOT_READY')]
        };
      }

      for (var i = 0; i < players.length; i++) {
        var player = players[i];
        var playerReport = {
          playerId: player.id,
          playerName: getPlayerName(player),
          passportValid: false,
          ageValid: false,
          notSuspended: false,
          overallEligible: false,
          blockReason: [],
          details: {
            passportReason: null,
            calculatedAge: null,
            suspensionReason: null
          }
        };

        if (!player.id) {
          playerReport.blockReason.push('PLAYER_ID_TIDAK_WUJUD');
          report.push(playerReport);
          squadValid = false;
          continue;
        }

        var passportCheck = await bridge.Passport.checkActivePassport(player.id, seasonId, {
          asOfDate: matchDate
        });
        playerReport.passportValid = passportCheck.isActive;
        playerReport.details.passportReason = passportCheck.reason;
        if (!passportCheck.isActive) {
          playerReport.blockReason.push(passportCheck.reason);
        }

        var ageCheck = bridge.LeagueOS.EligibilityEngine.verifyAgeGroup(
          getPlayerDob(player),
          rules.minAge,
          rules.maxAge,
          getReferenceYear(rules)
        );
        playerReport.ageValid = ageCheck.isEligible;
        playerReport.details.calculatedAge = ageCheck.calculatedAge;
        if (!ageCheck.isEligible) {
          playerReport.blockReason.push('HAD_UMUR_TIDAK_SAH_(' + ageCheck.calculatedAge + '_Tahun)');
        }

        var suspensionCheck = await bridge.LeagueOS.EligibilityEngine.checkSuspension(
          player.id,
          leagueId,
          matchDate
        );
        playerReport.notSuspended = !suspensionCheck.isSuspended;
        playerReport.details.suspensionReason = suspensionCheck.reason;
        if (suspensionCheck.isSuspended) {
          playerReport.blockReason.push(suspensionCheck.reason);
        }

        if (playerReport.passportValid && playerReport.ageValid && playerReport.notSuspended) {
          playerReport.overallEligible = true;
        } else {
          squadValid = false;
        }

        report.push(playerReport);
      }

      return { squadValid: squadValid, report: report };
    }
  };

  bridge.LeagueOS = Object.assign({}, bridge.LeagueOS, {
    MatchdayEngine: MatchdayEngine
  });
})(typeof window !== 'undefined' ? window : globalThis);
