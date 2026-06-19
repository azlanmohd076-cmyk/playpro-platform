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
      return 'Profil Identiti Belum Dikemas kini';
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

  function attrValue(attrs, key, fallback) {
    var n = Number(attrs && attrs[key]);
    if (!Number.isFinite(n)) return fallback || 5;
    return Math.max(1, Math.min(20, Math.floor(n)));
  }

  function progressColor(v) {
    if (v >= 16) return '#22c55e';
    if (v >= 11) return '#f59e0b';
    if (v >= 6) return '#38bdf8';
    return '#94a3b8';
  }

  function renderProgressRow(label, value) {
    var row = el('div', 'pp-coach-public-attr-row');
    row.style.cssText = 'display:grid;grid-template-columns:1fr 34px;gap:8px;align-items:center;margin-bottom:9px';

    var left = el('div');
    var name = el('div', null, label);
    name.style.cssText = 'font-size:.78rem;font-weight:800;color:#e5e7eb;margin-bottom:4px';
    var track = el('div');
    track.style.cssText = 'height:8px;border-radius:999px;background:rgba(148,163,184,.22);overflow:hidden;border:1px solid rgba(255,255,255,.06)';
    var bar = el('div');
    bar.style.cssText = 'height:100%;width:' + Math.max(5, Math.min(100, value * 5)) + '%;background:' + progressColor(value) + ';border-radius:999px;box-shadow:0 0 10px ' + progressColor(value) + '66';
    track.appendChild(bar);
    left.appendChild(name);
    left.appendChild(track);

    var score = el('div', null, String(value));
    score.style.cssText = 'font-size:1rem;font-weight:900;color:' + progressColor(value) + ';text-align:right';

    row.appendChild(left);
    row.appendChild(score);
    return row;
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

    renderCoachOnboardingForm: function(container, profile, onSubmit) {
      injectStylesOnce();
      var target = typeof container === 'string' ? document.querySelector(container) : container;
      if (!target) return null;
      target.innerHTML = '';

      var p = profile || {};
      var wrap = el('div', 'pp-coach-onboarding');
      wrap.style.cssText = 'max-width:520px;margin:14px auto 90px;background:#0f172a;color:#e5e7eb;border:1px solid #38bdf8;border-radius:16px;padding:18px;box-shadow:0 12px 32px rgba(0,0,0,.35);font-family:Arial,Helvetica,sans-serif';

      var title = el('div', null, 'Sila Lengkapkan Profil Pentauliahan Coach');
      title.style.cssText = 'font-size:1.15rem;font-weight:900;color:#facc15;margin-bottom:6px';
      var sub = el('div', null, 'Flow ini sama seperti pendaftaran pemain: sahkan identiti, butiran asas, kemudian pilih tahap lesen sebelum masuk ke Coach Passport.');
      sub.style.cssText = 'font-size:.82rem;color:#cbd5e1;line-height:1.45;margin-bottom:14px';
      wrap.appendChild(title);
      wrap.appendChild(sub);

      function field(label, input) {
        var box = el('div');
        box.style.cssText = 'margin-bottom:10px';
        var l = el('label', null, label);
        l.style.cssText = 'display:block;font-size:.68rem;font-weight:900;color:#94a3b8;text-transform:uppercase;margin-bottom:5px;letter-spacing:.06em';
        input.style.cssText = 'width:100%;box-sizing:border-box;padding:10px;border:1px solid #334155;border-radius:9px;background:#111827;color:#fff;font-weight:700;outline:none';
        box.appendChild(l);
        box.appendChild(input);
        wrap.appendChild(box);
        return input;
      }

      var ic = field('No MyKad / Passport', el('input'));
      ic.placeholder = 'Contoh: 820618051234 atau Passport No.';
      ic.value = p.ic_number || p.passport_number || '';

      var dob = field('Tarikh Lahir', el('input'));
      dob.type = 'date';
      dob.value = p.date_of_birth || '';

      var phone = field('No Telefon', el('input'));
      phone.type = 'tel';
      phone.placeholder = '+60123456789';
      phone.value = p.phone || '';

      var row = el('div');
      row.style.cssText = 'display:grid;grid-template-columns:1fr 1fr;gap:10px';
      var hBox = el('div');
      var wBox = el('div');
      var hLabel = el('label', null, 'Tinggi (cm)');
      var wLabel = el('label', null, 'Berat (kg)');
      [hLabel,wLabel].forEach(function(x){x.style.cssText='display:block;font-size:.68rem;font-weight:900;color:#94a3b8;text-transform:uppercase;margin-bottom:5px;letter-spacing:.06em';});
      var height = el('input'); height.type='number'; height.placeholder='170'; height.value=p.height_cm||'';
      var weight = el('input'); weight.type='number'; weight.placeholder='68'; weight.value=p.weight_kg||'';
      [height,weight].forEach(function(x){x.style.cssText='width:100%;box-sizing:border-box;padding:10px;border:1px solid #334155;border-radius:9px;background:#111827;color:#fff;font-weight:700;outline:none';});
      hBox.appendChild(hLabel); hBox.appendChild(height); wBox.appendChild(wLabel); wBox.appendChild(weight); row.appendChild(hBox); row.appendChild(wBox); wrap.appendChild(row);

      var license = el('select');
      ['Grassroots / Lesen D','Lesen C','Lesen B','Lesen A','Pro Diploma'].forEach(function(v){ var o=el('option', null, v); o.value=v; license.appendChild(o); });
      field('Tahap Lesen Malaysia', license);

      var msg = el('div');
      msg.style.cssText = 'font-size:.78rem;margin:8px 0;color:#fbbf24;font-weight:800;min-height:18px';
      wrap.appendChild(msg);

      var btn = el('button', null, 'Simpan & Buka Coach Passport');
      btn.type = 'button';
      btn.style.cssText = 'width:100%;padding:11px;border:none;border-radius:10px;background:#38bdf8;color:#07111f;font-weight:900;cursor:pointer;margin-top:8px';
      btn.addEventListener('click', async function() {
        var payload = {
          ic_number: ic.value.trim(),
          date_of_birth: dob.value,
          phone: phone.value.trim(),
          height_cm: height.value,
          weight_kg: weight.value,
          license_type: license.value,
          nationality: 'Malaysian'
        };
        if (!payload.ic_number || !payload.phone || !payload.license_type) {
          msg.textContent = 'Sila lengkapkan MyKad/Passport, telefon dan tahap lesen.';
          return;
        }
        btn.disabled = true;
        btn.textContent = 'Menyimpan...';
        if (typeof onSubmit === 'function') {
          await onSubmit(payload, msg);
        }
        btn.disabled = false;
        btn.textContent = 'Simpan & Buka Coach Passport';
      });
      wrap.appendChild(btn);
      target.appendChild(wrap);
      return wrap;
    },

    renderCoachPublicProfile: function(container, payload) {
      injectStylesOnce();

      var target = typeof container === 'string' ? document.querySelector(container) : container;
      if (!target) return null;

      var data = payload || {};
      var profile = data.profile || data;
      var assessor = data.assessor || {};
      var metadata = assessor.metadata || profile.metadata || {};
      var attrs = metadata.coach_attributes || data.attributes || {};
      var name = profile.full_name || profile.name || profile.email || 'Coach';
      var bioLine = buildCmBioLine(profile);
      var license = assessor.license_type || metadata.license_type || 'Grassroots / Tiada Maklumat';
      var formation = metadata.preferred_formation || '4-4-2';
      var style = metadata.preferred_style || metadata.coaching_style_label || 'Balanced';
      var contract = metadata.contract_status || 'Unemployed';

      target.innerHTML = '';

      var shell = el('div', 'pp-coach-public-profile');
      shell.style.cssText = 'background:linear-gradient(180deg,#10204a,#07111f);color:#e5e7eb;border:1px solid #2563eb;border-radius:14px;overflow:hidden;box-shadow:0 10px 28px rgba(0,0,0,.32);margin:10px 0 90px;font-family:Arial,Helvetica,sans-serif';

      var head = el('div');
      head.style.cssText = 'background:linear-gradient(90deg,#065fdb,#dc2626);padding:16px 14px;text-align:center;border-bottom:3px solid #2e1065';
      var title = el('div', null, name);
      title.style.cssText = 'font-size:1.55rem;font-weight:900;color:#fff;letter-spacing:.02em;text-shadow:0 2px 4px rgba(0,0,0,.55)';
      var bio = el('div', null, bioLine);
      bio.style.cssText = 'font-size:1rem;font-weight:900;color:#facc15;margin-top:7px;text-shadow:0 1px 2px rgba(0,0,0,.7)';
      head.appendChild(title);
      head.appendChild(bio);
      shell.appendChild(head);

      var body = el('div');
      body.style.cssText = 'display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.25fr);gap:12px;padding:14px;background:linear-gradient(rgba(4,10,25,.88),rgba(4,10,25,.92))';

      var left = el('div');
      left.style.cssText = 'background:rgba(15,23,42,.82);border:1px solid rgba(148,163,184,.25);border-radius:10px;padding:12px';
      var leftTitle = el('div', null, 'INFO TAKTIKAL & KELAYAKAN');
      leftTitle.style.cssText = 'font-size:.74rem;font-weight:900;color:#facc15;margin-bottom:10px;letter-spacing:.08em';
      left.appendChild(leftTitle);

      function infoRow(label, value) {
        var r = el('div');
        r.style.cssText = 'display:grid;grid-template-columns:120px 1fr;gap:8px;padding:7px 0;border-bottom:1px solid rgba(148,163,184,.16);font-size:.82rem';
        var l = el('div', null, label);
        l.style.cssText = 'color:#94a3b8;font-weight:800';
        var v = el('div', null, value || 'Tiada Maklumat');
        v.style.cssText = 'color:#e5e7eb;font-weight:900';
        r.appendChild(l);
        r.appendChild(v);
        left.appendChild(r);
      }

      infoRow('Lesen Semasa', license);
      infoRow('Preferred Formation', formation);
      infoRow('Preferred Style', style);
      infoRow('Status Kontrak', contract);
      infoRow('Gred Kuasa', assessor.status === 'active' ? 'GRED_2_CERTIFIED_ASSESSOR' : 'GRED_1_DAILY_COACH');

      var right = el('div');
      right.style.cssText = 'background:rgba(15,23,42,.82);border:1px solid rgba(148,163,184,.25);border-radius:10px;padding:12px';
      var rightTitle = el('div', null, 'ATRIBUT JURULATIH');
      rightTitle.style.cssText = 'font-size:.74rem;font-weight:900;color:#facc15;margin-bottom:10px;letter-spacing:.08em';
      right.appendChild(rightTitle);

      right.appendChild(renderProgressRow('Tactical Knowledge', attrValue(attrs, 'tactical_knowledge', 5)));
      right.appendChild(renderProgressRow('Man Management', attrValue(attrs, 'man_management', 5)));
      right.appendChild(renderProgressRow('Motivating', attrValue(attrs, 'motivating', 5)));
      right.appendChild(renderProgressRow('Level of Discipline', attrValue(attrs, 'discipline_management', 5)));
      right.appendChild(renderProgressRow('Judging Player Ability', attrValue(attrs, 'judging_ability', 5)));
      right.appendChild(renderProgressRow('Judging Player Potential', attrValue(attrs, 'judging_potential', 5)));
      right.appendChild(renderProgressRow('Coaching Outfield', attrValue(attrs, 'coaching_outfield', 5)));
      right.appendChild(renderProgressRow('Coaching Goalkeepers', attrValue(attrs, 'coaching_goalkeepers', 5)));

      body.appendChild(left);
      body.appendChild(right);
      shell.appendChild(body);

      var foot = el('div', null, contract);
      foot.style.cssText = 'padding:10px;text-align:center;font-size:1rem;font-weight:900;color:#67e8f9;background:rgba(0,0,0,.28);border-top:1px solid rgba(148,163,184,.18)';
      shell.appendChild(foot);

      target.appendChild(shell);
      return shell;
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
