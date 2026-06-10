/* ============================================================
   PlayPro Shared Dashboard Components v1.0
   Used by: coach, club, parent, player command centers
   ============================================================ */

'use strict';

/* ── MOCK DATA LAYER ────────────────────────────────────────── */
/* In production, replace these with Supabase RPC calls:
   supabase.rpc('function_name', { param: value })
   supabase.from('table').select('*').eq('col', val)
*/

const PP = {

  /* ── Data Store ─────────────────────────────────────────── */
  data: {
    user: {
      id: 'u1', name: 'Ahmad Razali', role: 'coach',
      club: 'FC Seremban U21', club_id: 'c1', email: 'ahmad@fcseremban.my',
      avatar: null
    },
    players: [
      { id:'p1', name:'Zulkifli Ahmad', preferred:'Zulkifli', pos:'midfielder', jersey:7,
        age:21, club:'FC Seremban U21',
        dna:{ overall:77, technical:74, physical:71, mental:84, tactical:80, band:'advanced' },
        potential:{ score:88, category:'national_prospect' },
        passport:{ score:72, band:'advanced' },
        fitness:{ condition:82, sharpness:78, fatigue:18, load:'normal' },
        morale:{ score:81, band:'happy', playing_sat:85, training_sat:78 },
        hidden:{ professionalism:15, ambition:16, injury_proneness:8 },
        injury_risk:'low',
        projection:{ peak_dna:91, peak_age:24, phase:'developing', wonderkid:true, wonderkid_score:82 },
        trend:'improving',
        market_value: 28500,
        reputation:{ score:61, band:'prominent' },
        role:'Advanced Playmaker',
        attrs:{ passing:14, dribbling:15, finishing:11, first_touch:14, tackling:9, heading:11,
                pace:14, stamina:15, strength:12, agility:13,
                leadership:13, composure:16, teamwork:15, work_rate:17,
                positioning:15, vision:16, decision_making:15, anticipation:14 },
        stats:{ apps:18, goals:4, assists:7, yellows:2, reds:0, rating_avg:7.2 },
        training_score:84, position_familiarity:[
          {pos:'CAM',pct:95,level:'natural'},{pos:'CM',pct:72,level:'accomplished'},{pos:'AML',pct:48,level:'competent'}
        ]
      },
      { id:'p2', name:'Fariz Ibrahim', preferred:'Fariz', pos:'forward', jersey:9,
        age:19, club:'FC Seremban U21',
        dna:{ overall:70, technical:71, physical:74, mental:68, tactical:65, band:'developing' },
        potential:{ score:82, category:'national_prospect' },
        passport:{ score:65, band:'developing' },
        fitness:{ condition:90, sharpness:85, fatigue:10, load:'normal' },
        morale:{ score:74, band:'happy', playing_sat:72, training_sat:76 },
        hidden:{ professionalism:12, ambition:17, injury_proneness:9 },
        injury_risk:'low',
        projection:{ peak_dna:85, peak_age:23, phase:'developing', wonderkid:true, wonderkid_score:74 },
        trend:'rapidly_improving',
        market_value: 19200,
        reputation:{ score:48, band:'known' },
        role:'Poacher',
        attrs:{ passing:11, dribbling:13, finishing:16, first_touch:13, tackling:7, heading:14,
                pace:16, stamina:14, strength:13, agility:15,
                leadership:10, composure:13, teamwork:14, work_rate:14,
                positioning:12, vision:11, decision_making:13, anticipation:12 },
        stats:{ apps:16, goals:11, assists:3, yellows:3, reds:0, rating_avg:7.4 },
        training_score:76, position_familiarity:[
          {pos:'ST',pct:95,level:'natural'},{pos:'AML',pct:55,level:'competent'}
        ]
      },
      { id:'p3', name:'Azrul Nizam', preferred:'Azrul', pos:'defender', jersey:5,
        age:22, club:'FC Seremban U21',
        dna:{ overall:71, technical:64, physical:76, mental:70, tactical:74, band:'developing' },
        potential:{ score:70, category:'regional_prospect' },
        passport:{ score:64, band:'developing' },
        fitness:{ condition:68, sharpness:62, fatigue:36, load:'heavy' },
        morale:{ score:55, band:'content', playing_sat:60, training_sat:50 },
        hidden:{ professionalism:11, ambition:12, injury_proneness:13 },
        injury_risk:'medium',
        projection:{ peak_dna:74, peak_age:26, phase:'developing', wonderkid:false },
        trend:'stable',
        market_value: 14800,
        reputation:{ score:38, band:'known' },
        role:'Ball-Playing Centre Back',
        attrs:{ passing:10, dribbling:9, finishing:8, first_touch:11, tackling:14, heading:13,
                pace:13, stamina:15, strength:16, agility:11,
                leadership:14, composure:13, teamwork:16, work_rate:15,
                positioning:15, vision:12, decision_making:14, anticipation:13 },
        stats:{ apps:20, goals:1, assists:2, yellows:4, reds:1, rating_avg:6.4 },
        training_score:62, position_familiarity:[
          {pos:'CB',pct:95,level:'natural'},{pos:'CDM',pct:38,level:'learning'}
        ]
      },
      { id:'p4', name:'Norzaidi Hamid', preferred:'Zaidi', pos:'midfielder', jersey:8,
        age:20, club:'FC Seremban U21',
        dna:{ overall:67, technical:66, physical:69, mental:72, tactical:63, band:'developing' },
        potential:{ score:74, category:'regional_prospect' },
        passport:{ score:60, band:'developing' },
        fitness:{ condition:76, sharpness:70, fatigue:24, load:'normal' },
        morale:{ score:68, band:'content', playing_sat:65, training_sat:72 },
        hidden:{ professionalism:14, ambition:11, injury_proneness:10 },
        injury_risk:'low',
        projection:{ peak_dna:78, peak_age:25, phase:'developing', wonderkid:false },
        trend:'improving',
        market_value: 11400,
        reputation:{ score:32, band:'emerging' },
        role:'Box-to-Box Midfielder',
        attrs:{ passing:12, dribbling:11, finishing:9, first_touch:13, tackling:12, heading:10,
                pace:12, stamina:14, strength:11, agility:12,
                leadership:13, composure:12, teamwork:15, work_rate:16,
                positioning:12, vision:11, decision_making:12, anticipation:11 },
        stats:{ apps:14, goals:2, assists:4, yellows:1, reds:0, rating_avg:6.8 },
        training_score:79, position_familiarity:[
          {pos:'CM',pct:88,level:'accomplished'},{pos:'CDM',pct:60,level:'competent'}
        ]
      },
      { id:'p5', name:'Hafiz Rahman', preferred:'Hafiz', pos:'goalkeeper', jersey:1,
        age:24, club:'FC Seremban U21',
        dna:{ overall:72, technical:68, physical:72, mental:76, tactical:70, band:'advanced' },
        potential:{ score:75, category:'regional_prospect' },
        passport:{ score:68, band:'developing' },
        fitness:{ condition:88, sharpness:80, fatigue:12, load:'normal' },
        morale:{ score:79, band:'happy', playing_sat:90, training_sat:70 },
        hidden:{ professionalism:13, ambition:11, injury_proneness:7 },
        injury_risk:'low',
        projection:{ peak_dna:78, peak_age:27, phase:'developing', wonderkid:false },
        trend:'stable',
        market_value: 16200,
        reputation:{ score:52, band:'known' },
        role:'Shot Stopper',
        attrs:{ passing:9, dribbling:5, finishing:4, first_touch:10, tackling:6, heading:11,
                pace:10, stamina:14, strength:15, agility:12,
                leadership:15, composure:16, teamwork:14, work_rate:13,
                positioning:15, vision:13, decision_making:15, anticipation:14 },
        stats:{ apps:22, goals:0, assists:0, yellows:1, reds:0, rating_avg:6.9 },
        training_score:72, position_familiarity:[
          {pos:'GK',pct:95,level:'natural'}
        ]
      }
    ],
    club: {
      id:'c1', name:'FC Seremban U21', league:'Liga 1 Seremban U21',
      tier:'youth', season:'2025/26', formation:'4-3-3',
      founded:2019, colours:'Green/White',
      dna:{ overall:71, technical:68, physical:72, mental:74, tactical:70 },
      passport_score:65, reputation:{ score:58, band:'known' },
      squad_size:22, assessed:18,
      standing:{ position:1, played:16, w:11, d:2, l:3, pts:35, gf:34, ga:18, gd:16 },
      followers:142, market_value_total:145000,
      next_match:{ opponent:'Nilai FC', date:'15 Jun 2026', venue:'Padang Seremban', is_home:true },
      wonderkids:2, high_risk_players:1,
      last_5_results:['W','W','D','W','L']
    },
    recent_events:[
      { type:'goal', icon:'⚽', title:'Fariz scored vs Nilai FC', time:'2h ago', player:'Fariz' },
      { type:'assessment', icon:'🧬', title:'DNA assessment completed for Zulkifli', time:'Yesterday', player:'Zulkifli' },
      { type:'training', icon:'🏃', title:'Training session completed — 18/22 attended', time:'Yesterday', player:null },
      { type:'injury', icon:'🩺', title:'Azrul: fatigue level elevated — monitor', time:'2 days ago', player:'Azrul' },
      { type:'milestone', icon:'🌟', title:'Fariz reached 10 goals this season', time:'3 days ago', player:'Fariz' }
    ],
    upcoming_sessions:[
      { date:'Mon 10 Jun', time:'09:00', type:'Tactical', intensity:'normal', expected:20 },
      { date:'Wed 12 Jun', time:'09:00', type:'Technical', intensity:'heavy', expected:22 },
      { date:'Fri 14 Jun', time:'09:00', type:'Recovery', intensity:'light', expected:18 }
    ],
    passport_history:[72,68,64,61,58,55,52,50],
    dna_history:[77,74,71,68,65,62,58,55],
    attr_history:{
      passing:[14,13,13,12,12,11,11,10],
      pace:[14,14,13,13,12,12,11,11],
      vision:[16,15,14,14,13,12,12,11]
    }
  },

  /* ── Navigation ─────────────────────────────────────────── */
  currentPage: null,

  initNav(tabs, pages, defaultPage) {
    tabs.forEach(t => {
      t.addEventListener('click', () => {
        const page = t.dataset.page;
        tabs.forEach(x => x.classList.remove('active'));
        t.classList.add('active');
        pages.forEach(p => p.classList.toggle('active', p.id === 'page-' + page));
        PP.currentPage = page;
      });
    });
    // activate default
    const dt = [...tabs].find(t => t.dataset.page === defaultPage);
    if (dt) dt.click();
  },

  initSidebarNav(items) {
    items.forEach(item => {
      item.addEventListener('click', () => {
        items.forEach(x => x.classList.remove('active'));
        item.classList.add('active');
        const page = item.dataset.page;
        document.querySelectorAll('.page').forEach(p => {
          p.classList.toggle('active', p.id === 'page-' + page);
        });
      });
    });
  },

  /* ── Toast ──────────────────────────────────────────────── */
  toast(msg, duration=2400) {
    let t = document.getElementById('pp-toast');
    if (!t) {
      t = document.createElement('div');
      t.id = 'pp-toast';
      t.className = 'toast';
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(t._timer);
    t._timer = setTimeout(() => t.classList.remove('show'), duration);
  },

  /* ── Modal ──────────────────────────────────────────────── */
  modal: { bg: null, box: null },
  openModal(html) {
    let bg = document.getElementById('pp-modal-bg');
    if (!bg) {
      bg = document.createElement('div');
      bg.className = 'modal-bg';
      bg.id = 'pp-modal-bg';
      bg.innerHTML = '<div class="modal-box" id="pp-modal-box"></div>';
      bg.addEventListener('click', e => { if (e.target === bg) PP.closeModal(); });
      document.body.appendChild(bg);
    }
    document.getElementById('pp-modal-box').innerHTML = html;
    bg.classList.add('open');
  },
  closeModal() {
    const bg = document.getElementById('pp-modal-bg');
    if (bg) bg.classList.remove('open');
  },

  /* ── SVG Chart: Line ────────────────────────────────────── */
  lineChart(data, opts={}) {
    const {
      w=280, h=80, color='var(--green)', showDots=true, showLabels=false,
      labels=[], yMin=null, yMax=null, showArea=true
    } = opts;
    const pad = { t:14, r:8, b:18, l:8 };
    const cw = w - pad.l - pad.r;
    const ch = h - pad.t - pad.b;
    const mn = yMin ?? Math.min(...data) - 2;
    const mx = yMax ?? Math.max(...data) + 2;
    const range = mx - mn || 1;
    const xs = data.map((_, i) => pad.l + (i / (data.length - 1)) * cw);
    const ys = data.map(v => pad.t + ch - ((v - mn) / range) * ch);
    const path = xs.map((x,i) => `${i===0?'M':'L'}${x.toFixed(1)},${ys[i].toFixed(1)}`).join(' ');
    const area = `M${xs[0].toFixed(1)},${(pad.t+ch).toFixed(1)} ` +
      xs.map((x,i)=>`L${x.toFixed(1)},${ys[i].toFixed(1)}`).join(' ') +
      ` L${xs[xs.length-1].toFixed(1)},${(pad.t+ch).toFixed(1)} Z`;
    const gradId = 'grad_' + Math.random().toString(36).slice(2,7);
    return `<svg viewBox="0 0 ${w} ${h}" style="width:100%;height:${h}px">
      <defs>
        <linearGradient id="${gradId}" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="${color}" stop-opacity=".25"/>
          <stop offset="100%" stop-color="${color}" stop-opacity="0"/>
        </linearGradient>
      </defs>
      ${showArea ? `<path d="${area}" fill="url(#${gradId})"/>` : ''}
      <path d="${path}" fill="none" stroke="${color}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>
      ${showDots ? xs.map((x,i)=>`<circle cx="${x.toFixed(1)}" cy="${ys[i].toFixed(1)}" r="3.5" fill="${color}"/>
        <text x="${x.toFixed(1)}" y="${(ys[i]-7).toFixed(1)}" text-anchor="middle" font-size="10" font-weight="700" fill="var(--grey-700)">${data[i]}</text>`).join('') : ''}
      ${showLabels ? labels.map((l,i)=>`<text x="${xs[i].toFixed(1)}" y="${(h-2).toFixed(1)}" text-anchor="middle" font-size="9" fill="var(--grey-400)">${l}</text>`).join('') : ''}
    </svg>`;
  },

  /* ── SVG Chart: Bar ─────────────────────────────────────── */
  barChart(data, labels, opts={}) {
    const { w=280, h=80, color='var(--green)', highlightLast=true } = opts;
    const pad = { t:14, r:6, b=18, l:6 };
    const cw = w - pad.l - pad.r;
    const ch = h - pad.t - pad.b;
    const max = Math.max(...data, 1);
    const barW = cw / data.length * 0.6;
    const barGap = cw / data.length;
    return `<svg viewBox="0 0 ${w} ${h}" style="width:100%;height:${h}px">
      ${data.map((v,i) => {
        const bh = (v / max) * ch;
        const x = pad.l + i * barGap + (barGap - barW)/2;
        const y = pad.t + ch - bh;
        const isLast = highlightLast && i === data.length - 1;
        const col = isLast ? color : 'var(--grey-200)';
        return `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${barW.toFixed(1)}" height="${bh.toFixed(1)}" fill="${col}" rx="3"/>
          <text x="${(x+barW/2).toFixed(1)}" y="${(y-4).toFixed(1)}" text-anchor="middle" font-size="10" font-weight="700" fill="${isLast?color:'var(--grey-400)'}">${v}</text>
          ${labels ? `<text x="${(x+barW/2).toFixed(1)}" y="${(h-2).toFixed(1)}" text-anchor="middle" font-size="9" fill="var(--grey-400)">${labels[i]||''}</text>` : ''}`;
      }).join('')}
    </svg>`;
  },

  /* ── SVG: Ring / Donut ──────────────────────────────────── */
  ring(value, max=100, opts={}) {
    const { size=64, stroke=7, color='var(--green)', label='', sublabel='' } = opts;
    const r = (size - stroke) / 2;
    const circ = 2 * Math.PI * r;
    const pct = Math.max(0, Math.min(1, value / max));
    const dash = circ * pct;
    const cx = size / 2;
    return `<svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}">
      <circle cx="${cx}" cy="${cx}" r="${r}" fill="none" stroke="var(--grey-200)" stroke-width="${stroke}"/>
      <circle cx="${cx}" cy="${cx}" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}"
        stroke-dasharray="${dash.toFixed(2)} ${circ.toFixed(2)}"
        stroke-linecap="round" transform="rotate(-90 ${cx} ${cx})"/>
      <text x="${cx}" y="${cx + (sublabel?-3:5)}" text-anchor="middle" font-size="${sublabel?14:16}" font-weight="800" fill="var(--grey-800)">${label}</text>
      ${sublabel ? `<text x="${cx}" y="${cx+14}" text-anchor="middle" font-size="9" fill="var(--grey-400)">${sublabel}</text>` : ''}
    </svg>`;
  },

  /* ── SVG: Radar (5-axis) ────────────────────────────────── */
  radar(values, labels, opts={}) {
    // values: array of 0–100, labels: same length
    const { size=160, color='var(--green)' } = opts;
    const n = values.length;
    const cx = size / 2, cy = size / 2, r = size / 2 - 20;
    const angle = i => (i / n) * 2 * Math.PI - Math.PI / 2;
    const px = (i, rad) => cx + rad * Math.cos(angle(i));
    const py = (i, rad) => cy + rad * Math.sin(angle(i));
    const gridLevels = [0.25, 0.5, 0.75, 1.0];
    const grid = gridLevels.map(l => {
      const pts = Array.from({length:n},(_,i)=>`${px(i,r*l).toFixed(1)},${py(i,r*l).toFixed(1)}`).join(' ');
      return `<polygon points="${pts}" fill="none" stroke="var(--grey-200)" stroke-width="1"/>`;
    }).join('');
    const spokes = Array.from({length:n},(_,i)=>
      `<line x1="${cx}" y1="${cy}" x2="${px(i,r).toFixed(1)}" y2="${py(i,r).toFixed(1)}" stroke="var(--grey-200)" stroke-width="1"/>`
    ).join('');
    const pts = values.map((v,i) => {
      const rad = (Math.max(0,Math.min(100,v)) / 100) * r;
      return `${px(i,rad).toFixed(1)},${py(i,rad).toFixed(1)}`;
    }).join(' ');
    const lbls = labels.map((l,i) => {
      const lr = r + 14;
      const lx = px(i,lr), ly = py(i,lr);
      const anchor = Math.abs(lx - cx) < 5 ? 'middle' : lx < cx ? 'end' : 'start';
      return `<text x="${lx.toFixed(1)}" y="${(ly+4).toFixed(1)}" text-anchor="${anchor}" font-size="10" fill="var(--grey-500)">${l}</text>`;
    }).join('');
    return `<svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}">
      ${grid}${spokes}
      <polygon points="${pts}" fill="${color}" fill-opacity=".2" stroke="${color}" stroke-width="2"/>
      ${lbls}
    </svg>`;
  },

  /* ── Helpers ────────────────────────────────────────────── */
  bandColor(band) {
    return { elite:'var(--gold)', advanced:'var(--green)', developing:'var(--blue)',
             emerging:'var(--grey-500)', beginner:'var(--grey-400)' }[band] || 'var(--grey-400)';
  },
  bandBadge(band) {
    const map = { elite:'badge-gold', advanced:'badge-green', developing:'badge-blue',
                  emerging:'badge-grey', beginner:'badge-grey' };
    const labels = { elite:'Elite', advanced:'Advanced', developing:'Developing',
                     emerging:'Emerging', beginner:'Beginner' };
    return `<span class="badge ${map[band]||'badge-grey'}">${labels[band]||band}</span>`;
  },
  posLabel(pos) {
    return { goalkeeper:'GK', defender:'DEF', midfielder:'MID', forward:'FWD' }[pos] || pos.toUpperCase();
  },
  trendIcon(t) {
    return { rapidly_improving:'↑↑', improving:'↑', stable:'→', declining:'↓', rapidly_declining:'↓↓', insufficient_data:'—' }[t] || '—';
  },
  trendColor(t) {
    return { rapidly_improving:'var(--green)', improving:'var(--green)', stable:'var(--grey-500)',
             declining:'var(--gold)', rapidly_declining:'var(--red)', insufficient_data:'var(--grey-400)' }[t];
  },
  potLabel(cat) {
    return { elite_prospect:'Elite Prospect', national_prospect:'National Prospect',
             regional_prospect:'Regional Prospect', development_prospect:'Development',
             recreational:'Recreational' }[cat] || cat;
  },
  moraleBadge(band) {
    return `<div class="morale-indicator morale-${band}"><div class="morale-dot"></div><div class="morale-text">${band.charAt(0).toUpperCase()+band.slice(1)}</div></div>`;
  },
  riskBadge(risk) {
    const r = risk||'low';
    return `<span class="badge risk-${r.replace('_','_')}">${r.replace('_',' ').replace(/\b\w/g,c=>c.toUpperCase())}</span>`;
  },
  fmtMyr(v) {
    if (!v) return 'MYR —';
    if (v >= 1000000) return `MYR ${(v/1000000).toFixed(2)}M`;
    if (v >= 1000) return `MYR ${(v/1000).toFixed(1)}K`;
    return `MYR ${v}`;
  },
  initials(name) { return (name||'?').split(' ').slice(0,2).map(w=>w[0]).join('').toUpperCase(); },
  ago(n) { return n===0?'Today':n===1?'Yesterday':n+' days ago'; },

  /* ── DNA Bar Component ──────────────────────────────────── */
  dnaBar(label, value, colorVar='var(--green)') {
    return `<div class="dna-row">
      <div class="dna-label">${label}</div>
      <div class="dna-track"><div class="dna-fill" style="width:${value}%;background:${colorVar}"></div></div>
      <div class="dna-val">${value}</div>
    </div>`;
  },

  /* ── Attribute Dots ─────────────────────────────────────── */
  attrDots(name, value, cls='') {
    const dots = Array.from({length:20},(_,i)=>`<div class="attr-dot ${i<value?'on '+cls:''}"></div>`).join('');
    return `<div class="attr-dots-row">
      <div class="attr-dot-name">${name}</div>
      <div class="attr-dots">${dots}</div>
      <div class="attr-dot-val">${value}</div>
    </div>`;
  },

  /* ── Player Card Mini ───────────────────────────────────── */
  playerRowHTML(p, onClick='') {
    const trend = PP.trendIcon(p.trend);
    const tColor = PP.trendColor(p.trend);
    return `<div class="player-row" onclick="${onClick}">
      <div class="player-avatar" style="background:${PP.bandColor(p.dna.band)}15;color:${PP.bandColor(p.dna.band)}">${PP.initials(p.name)}</div>
      <div class="player-info">
        <div class="player-name">${p.preferred||p.name}</div>
        <div class="player-meta">${PP.posLabel(p.pos)} · #${p.jersey} · ${p.age}y</div>
      </div>
      <div style="text-align:right;flex-shrink:0">
        <div style="font-size:20px;font-weight:800;color:${PP.bandColor(p.dna.band)}">${p.dna.overall}</div>
        <div style="font-size:11px;font-weight:600;color:${tColor}">${trend} ${p.trend?.replace(/_/g,' ')?.replace(/\b\w/g,c=>c.toUpperCase())||''}</div>
      </div>
    </div>`;
  },

  /* ── Fitness mini ───────────────────────────────────────── */
  fitClass(v) { return v>=80?'fit-100':v>=60?'fit-75':v>=40?'fit-50':'fit-low'; },

  /* ── Form strip (W/D/L) ─────────────────────────────────── */
  formStrip(results) {
    return results.map(r => {
      const c = r==='W'?'background:var(--green)':r==='D'?'background:var(--gold)':'background:var(--red)';
      return `<div style="width:22px;height:22px;border-radius:4px;${c};color:white;font-size:11px;font-weight:800;display:flex;align-items:center;justify-content:center">${r}</div>`;
    }).join('');
  }
};
