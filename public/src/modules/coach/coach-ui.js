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
