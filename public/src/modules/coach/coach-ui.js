/*
 * PlayPro Model 6 — Coach Retro Grid UI
 * Isolated UI helper only. Not connected to legacy public/index.html yet.
 * Uses DOM creation to avoid unsafe HTML/template literal injection.
 */
(function attachCoachRetroGridUI(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Coach = bridge.Coach || {};

  var LABELS = {
    judging_ability: 'Judging Ability',
    judging_potential: 'Judging Potential',
    tactical_knowledge: 'Tactical Knowledge',
    coaching_outfield: 'Coaching Outfield',
    coaching_goalkeepers: 'Coaching GK',
    technical_coaching: 'Technical Coaching',
    attacking_coaching: 'Attacking Coaching',
    defending_coaching: 'Defending Coaching',
    fitness_coaching: 'Fitness Coaching',
    set_piece_coaching: 'Set Piece Coaching',
    man_management: 'Man Management',
    motivating: 'Motivating',
    discipline_management: 'Discipline',
    physiotherapy: 'Physiotherapy',
    sports_science: 'Sports Science',
    working_with_youngsters: 'Working With Youngsters',
    adaptability: 'Adaptability',
    determination: 'Determination',
    data_analysis: 'Data Analysis',
    communication: 'Communication',
    coaching_style: 'Coaching Style'
  };

  var FIELD_ATTRS = [
    'judging_ability', 'judging_potential', 'tactical_knowledge',
    'coaching_outfield', 'coaching_goalkeepers', 'technical_coaching',
    'attacking_coaching', 'defending_coaching', 'fitness_coaching',
    'set_piece_coaching'
  ];

  var SUPPORT_ATTRS = [
    'man_management', 'motivating', 'discipline_management',
    'physiotherapy', 'sports_science', 'working_with_youngsters',
    'adaptability', 'determination', 'data_analysis',
    'communication', 'coaching_style'
  ];

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  function scoreClass(score, maxScore) {
    if (maxScore <= 5) return 'pp-coach-score locked';
    if (score >= 16) return 'pp-coach-score elite';
    if (score >= 11) return 'pp-coach-score good';
    if (score >= 6) return 'pp-coach-score mid';
    return 'pp-coach-score low';
  }

  function calculateAge(dob) {
    if (!dob) return null;
    var d = new Date(dob);
    if (isNaN(d.getTime())) return null;
    var now = new Date();
    var age = now.getFullYear() - d.getFullYear();
    var m = now.getMonth() - d.getMonth();
    if (m < 0 || (m === 0 && now.getDate() < d.getDate())) age--;
    return age >= 0 ? age : null;
  }

  function formatCmDate(dob) {
    if (!dob) return null;
    var d = new Date(dob);
    if (isNaN(d.getTime())) return null;
    var yy = String(d.getFullYear()).slice(-2);
    return d.getDate() + '.' + (d.getMonth() + 1) + '.' + yy;
  }

  function buildCmBioLine(profile) {
    var dob = profile.date_of_birth || profile.dob || null;
    var formatted = formatCmDate(dob);
    var age = calculateAge(dob);
    var nat = profile.nationality || 'Malaysian';

    if (!formatted && age === null) {
      return 'Born — (Age —). ' + nat + '.';
    }

    return 'Born ' + (formatted || '—') + ' (Age ' + (age !== null ? age : '—') + '). ' + nat + '.';
  }

  function injectStylesOnce() {
    if (document.getElementById('pp-coach-retro-grid-style')) return;
    var style = document.createElement('style');
    style.id = 'pp-coach-retro-grid-style';
    style.textContent = ''
      + '.pp-coach-panel{font-family:Arial,Helvetica,sans-serif;background:#f2f2e8;border:1px solid #a8a899;color:#111;max-width:760px;box-shadow:0 2px 8px rgba(0,0,0,.18)}'
      + '.pp-coach-head{display:flex;justify-content:space-between;align-items:center;background:#182d4f;color:#fff;padding:8px 10px;font-weight:800;font-size:13px;text-transform:uppercase;letter-spacing:.04em}'
      + '.pp-coach-grade{font-size:11px;background:#f7c948;color:#111;padding:3px 7px;border-radius:2px;font-weight:900}'
      + '.pp-coach-grade.locked{background:#777;color:#fff}'
      + '.pp-coach-body{display:grid;grid-template-columns:1fr 1fr;gap:8px;padding:8px}'
      + '.pp-coach-col{border:1px solid #c5c5b5;background:#fff}'
      + '.pp-coach-col-title{background:#d6d6c8;color:#111;font-weight:900;font-size:12px;padding:5px 7px;border-bottom:1px solid #b8b8a8;text-transform:uppercase}'
      + '.pp-coach-row{display:grid;grid-template-columns:1fr 34px;align-items:center;min-height:24px;border-bottom:1px solid #eee;font-size:12px}'
      + '.pp-coach-row:nth-child(even){background:#f8f8f0}'
      + '.pp-coach-name{padding:4px 7px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}'
      + '.pp-coach-score{text-align:center;font-weight:900;padding:3px 0;border-left:1px solid #ddd;color:#111}'
      + '.pp-coach-score.elite{color:#0f8a3b}.pp-coach-score.good{color:#d26900}.pp-coach-score.mid{color:#005eb8}.pp-coach-score.low{color:#222}.pp-coach-score.locked{color:#777;background:#e4e4e4}'
      + '.pp-coach-lock-note{padding:7px 10px;background:#e9e9e0;border-top:1px solid #c5c5b5;color:#555;font-size:12px;font-weight:700}'
      + '.pp-assessment-scale{display:flex;gap:3px;flex-wrap:wrap;padding:8px;background:#fff;border-top:1px solid #ccc}'
      + '.pp-scale-cell{width:22px;height:22px;display:flex;align-items:center;justify-content:center;border:1px solid #bbb;font-size:11px;font-weight:900;background:#f8f8f8;color:#111}'
      + '.pp-scale-cell.disabled{background:#d7d7d7;color:#888;text-decoration:line-through;opacity:.55}'
      + '@media(max-width:640px){.pp-coach-body{grid-template-columns:1fr}.pp-coach-panel{max-width:100%}}';
    document.head.appendChild(style);
  }

  function renderColumn(title, keys, attrs, maxScore) {
    var col = el('div', 'pp-coach-col');
    col.appendChild(el('div', 'pp-coach-col-title', title));

    keys.forEach(function(key) {
      var row = el('div', 'pp-coach-row');
      var score = Number(attrs[key] || 0);
      row.appendChild(el('div', 'pp-coach-name', LABELS[key] || key));
      row.appendChild(el('div', scoreClass(score, maxScore), String(score || '—')));
      col.appendChild(row);
    });

    return col;
  }

  var CoachRetroGridUI = {
    labels: Object.assign({}, LABELS),

    renderCoachRetroGrid: function(container, data) {
      injectStylesOnce();

      var target = typeof container === 'string' ? document.querySelector(container) : container;
      if (!target) return null;

      var payload = data || {};
      var attrs = payload.attributes || {};
      var grade = payload.grade || 'GRED_1_DAILY_COACH';
      var maxScore = Number(payload.maxScore || 5);
      var isLocked = maxScore <= 5;

      target.innerHTML = '';

      var panel = el('div', 'pp-coach-panel');
      var head = el('div', 'pp-coach-head');
      head.appendChild(el('div', null, 'Coach Attributes'));
      head.appendChild(el('div', isLocked ? 'pp-coach-grade locked' : 'pp-coach-grade', grade));
      panel.appendChild(head);

      var body = el('div', 'pp-coach-body');
      body.appendChild(renderColumn('Atribut Padang', FIELD_ATTRS, attrs, maxScore));
      body.appendChild(renderColumn('Atribut Sokongan', SUPPORT_ATTRS, attrs, maxScore));
      panel.appendChild(body);

      if (isLocked) {
        panel.appendChild(el('div', 'pp-coach-lock-note', 'GRED 1 aktif: input penilaian pemain dikunci pada skala 1–5. Skala 6–20 disekat sehingga lulus Ujian Video PCSAP.'));
      }

      target.appendChild(panel);
      return panel;
    },

    renderCoachWorkspaceDashboard: async function(container, profile) {
      injectStylesOnce();

      var target = typeof container === 'string' ? document.querySelector(container) : container;
      if (!target) return null;

      var coachProfile = profile || {};
      var profileId = coachProfile.id || coachProfile.profile_id || null;
      var name = coachProfile.full_name || coachProfile.name || coachProfile.email || 'Coach';
      var cmBioLine = buildCmBioLine(coachProfile);

      target.innerHTML = '';

      var shell = el('div', 'pp-coach-workspace');
      shell.style.cssText = 'padding:14px;max-width:960px;margin:0 auto 90px;font-family:Arial,Helvetica,sans-serif';

      var hero = el('div', 'pp-coach-workspace-hero');
      hero.style.cssText = 'background:linear-gradient(135deg,#0f172a,#1e3a8a);color:#fff;border-radius:14px;padding:16px;margin-bottom:12px;border:1px solid rgba(255,255,255,.12);box-shadow:0 8px 22px rgba(0,0,0,.28)';
      var title = el('div', null, 'Coach Passport Workspace');
      title.style.cssText = 'font-size:1.25rem;font-weight:900;letter-spacing:.02em;margin-bottom:4px';
      var cmBio = el('div', null, cmBioLine);
      cmBio.style.cssText = 'font-size:1rem;color:#facc15;font-weight:900;text-align:center;margin:6px 0 8px;text-shadow:0 1px 2px rgba(0,0,0,.7)';
      var sub = el('div', null, 'Selamat datang, ' + name + '. Paparan Player Passport disorok untuk akaun coach.');
      sub.style.cssText = 'font-size:.86rem;color:#dbeafe;line-height:1.45';
      hero.appendChild(title);
      hero.appendChild(cmBio);
      hero.appendChild(sub);
      shell.appendChild(hero);

      var data = {
        ok: true,
        grade: 'GRED_1_DAILY_COACH',
        isCertified: false,
        maxScore: 5,
        attributes: {}
      };
      var caps = null;

      if (bridge.Coach && typeof bridge.Coach.getCoachAttributes === 'function') {
        data = await bridge.Coach.getCoachAttributes(profileId);
      }
      if (bridge.Coach && typeof bridge.Coach.getCoachCapabilities === 'function') {
        caps = await bridge.Coach.getCoachCapabilities(profileId);
      }

      caps = caps || {
        isCertified: !!data.isCertified,
        grade: data.grade || 'GRED_1_DAILY_COACH',
        maxScore: data.maxScore || 5,
        licenseType: 'Tiada / Grassroots',
        examAttemptsCount: 0,
        cooldown: { isActive: false, cooldownUntil: null, attemptsCount: 0, attemptsLimit: 3, remainingMs: 0 },
        wallet: { availableBalance: 0, pendingBalance: 0, currency: 'MYR' }
      };

      var wallet = caps.wallet || { availableBalance: 0, pendingBalance: 0, currency: 'MYR' };
      var cooldown = caps.cooldown || { isActive: false, cooldownUntil: null, attemptsCount: caps.examAttemptsCount || 0, attemptsLimit: 3, remainingMs: 0 };
      var available = Number(wallet.availableBalance || 0).toFixed(2);
      var pending = Number(wallet.pendingBalance || 0).toFixed(2);
      var currency = wallet.currency || 'MYR';
      var attempts = cooldown.attemptsCount !== undefined ? cooldown.attemptsCount : (caps.examAttemptsCount || 0);

      var cards = el('div', 'pp-coach-identity-grid');
      cards.style.cssText = 'display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;margin-bottom:12px';

      function metric(label, value, tone) {
        var card = el('div', null);
        card.style.cssText = 'background:#111827;color:#e5e7eb;border:1px solid #374151;border-radius:10px;padding:10px;min-height:70px';
        var l = el('div', null, label);
        l.style.cssText = 'font-size:.68rem;color:#9ca3af;font-weight:800;text-transform:uppercase;margin-bottom:5px';
        var v = el('div', null, value);
        v.style.cssText = 'font-size:.95rem;font-weight:900;color:' + (tone || '#fbbf24') + ';line-height:1.25';
        card.appendChild(l);
        card.appendChild(v);
        return card;
      }

      cards.appendChild(metric('Lesen Semasa', caps.licenseType || 'Tiada / Grassroots', '#38bdf8'));
      cards.appendChild(metric('Gred Kuasa', caps.grade || data.grade || 'GRED_1_DAILY_COACH', caps.isCertified ? '#22c55e' : '#fbbf24'));
      cards.appendChild(metric('Had Skala Input', '1–' + (caps.maxScore || data.maxScore || 5), caps.isCertified ? '#22c55e' : '#f97316'));
      cards.appendChild(metric('Agent Wallet', currency + ' ' + available + (pending > 0 ? ' · Pending ' + pending : ''), '#a7f3d0'));
      shell.appendChild(cards);

      var statusCard = el('div', 'pp-coach-status-card');
      statusCard.style.cssText = 'background:#111827;color:#e5e7eb;border:1px solid #374151;border-radius:12px;padding:12px;margin-bottom:12px;display:flex;gap:10px;justify-content:space-between;align-items:center;flex-wrap:wrap';
      var statusText = el('div', null, 'Cubaan Ujian Video: ' + attempts + '/3');
      statusText.style.cssText = 'font-size:.88rem;font-weight:800';
      var action = el('button', null, 'Ambil Ujian Video PCSAP');
      action.type = 'button';
      action.style.cssText = 'background:#38bdf8;color:#07111f;border:none;border-radius:8px;padding:9px 12px;font-weight:900;cursor:pointer';

      if (caps.isCertified || data.isCertified) {
        action.textContent = '🏆 Certified Assessor Active';
        action.disabled = true;
        action.style.background = '#16a34a';
        action.style.color = '#fff';
        action.style.cursor = 'default';
      } else if (cooldown.isActive) {
        action.textContent = '⏳ Cooldown Aktif';
        action.disabled = true;
        action.style.background = '#374151';
        action.style.color = '#9ca3af';
        action.style.cursor = 'not-allowed';
        statusText.textContent = 'COOLDOWN_ACTIVE · Cubaan: 3/3 · Dibuka semula: ' + new Date(cooldown.cooldownUntil).toLocaleString('ms-MY');
      } else {
        action.addEventListener('click', function() {
          if (root.toast) root.toast('Ujian Video PCSAP akan dibuka dalam panel seterusnya.');
          else console.log('Ujian Video PCSAP akan dibuka dalam panel seterusnya.');
        });
      }

      statusCard.appendChild(statusText);
      statusCard.appendChild(action);
      shell.appendChild(statusCard);

      var gridMount = el('div', 'pp-coach-grid-mount');
      shell.appendChild(gridMount);

      var scaleTitle = el('div', null, 'Had Input Penilaian Pemain');
      scaleTitle.style.cssText = 'margin:12px 0 6px;font-size:.82rem;font-weight:900;color:#111827;text-transform:uppercase';
      var scaleMount = el('div', 'pp-coach-scale-mount');
      shell.appendChild(scaleTitle);
      shell.appendChild(scaleMount);

      target.appendChild(shell);
      this.renderCoachRetroGrid(gridMount, data);
      this.renderAssessmentScaleLock(scaleMount, caps.maxScore || data.maxScore || 5);

      return shell;
    },

    renderAssessmentScaleLock: function(container, maxScore) {
      injectStylesOnce();

      var target = typeof container === 'string' ? document.querySelector(container) : container;
      if (!target) return null;

      var max = Number(maxScore || 5);
      target.innerHTML = '';

      var wrap = el('div', 'pp-assessment-scale');
      for (var i = 1; i <= 20; i++) {
        wrap.appendChild(el('div', i > max ? 'pp-scale-cell disabled' : 'pp-scale-cell', String(i)));
      }
      target.appendChild(wrap);
      return wrap;
    }
  };

  bridge.Coach.UI = Object.assign({}, bridge.Coach.UI || {}, CoachRetroGridUI);
})(typeof window !== 'undefined' ? window : globalThis);
