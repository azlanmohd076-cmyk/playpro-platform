/* PlayPro UI Shell v1
 * Navigation contract:
 * Top: LIVE | CARI | MYTEAM | KEDAI
 * Bottom: CARI | MYTEAM | INBOX | PASSPORT
 * Secondary global nav is removed.
 * Match Observer / Match Statistics remain contextual to tournament management.
 */
(function () {
  'use strict';

  const norm = (value) => String(value || '')
    .replace(/\s+/g, ' ')
    .trim()
    .toUpperCase();

  const label = (el) => norm(el?.textContent || el?.getAttribute('aria-label') || '');

  const directActionNodes = (root) => Array.from(
    root.querySelectorAll(':scope > a, :scope > button, :scope > [role="button"]')
  );

  const hasLabels = (root, wanted) => {
    const labels = directActionNodes(root).map(label);
    return wanted.filter((x) => labels.includes(x)).length;
  };

  const hideAction = (el) => {
    el.setAttribute('data-playpro-shell-hidden', 'true');
    el.setAttribute('aria-hidden', 'true');
    el.style.display = 'none';
  };

  /* HUB owns the competition portal; it must not leak into Passport/Profile. */
  function syncHubOnlySections() {
    const portal = document.getElementById('public-competition-portal');
    const home = document.getElementById('tab-home');
    if (!portal || !home) return;
    const homeVisible = getComputedStyle(home).display !== 'none';
    portal.style.display = homeVisible ? '' : 'none';
    portal.setAttribute('aria-hidden', homeVisible ? 'false' : 'true');
  }

  /*
   * Legacy Passport code still asks for player_attributes + embedded
   * attribute_definitions. Production now uses player_attribute_state as the
   * canonical 18-attribute source. Adapt this one read at the shell boundary
   * so the legacy page stops producing 404s without creating a second source
   * of truth in Supabase.
   */
  function installPlayerAttributeCompatibility() {
    const client = window.SB;
    if (!client || client.__playproAttributeCompat) return;
    if (typeof client.from !== 'function') return;

    const nativeFrom = client.from.bind(client);
    const definitions = {
      passing: ['Passing', 'technical', 1],
      dribbling: ['Dribbling', 'technical', 2],
      finishing: ['Finishing', 'technical', 3],
      first_touch: ['First Touch', 'technical', 4],
      tackling: ['Tackling', 'technical', 5],
      heading: ['Heading', 'technical', 6],
      pace: ['Pace', 'physical', 7],
      stamina: ['Stamina', 'physical', 8],
      strength: ['Strength', 'physical', 9],
      agility: ['Agility', 'physical', 10],
      leadership: ['Leadership', 'mental', 11],
      composure: ['Composure', 'mental', 12],
      teamwork: ['Teamwork', 'mental', 13],
      work_rate: ['Work Rate', 'mental', 14],
      positioning: ['Positioning', 'tactical', 15],
      vision: ['Vision', 'tactical', 16],
      decision_making: ['Decision Making', 'tactical', 17],
      anticipation: ['Anticipation', 'tactical', 18],
    };

    const compatFrom = (table) => {
      if (table !== 'player_attributes') return nativeFrom(table);

      let playerId = null;
      let publicOnly = null;
      let resultPromise = null;

      const query = {
        select() { return query; },
        eq(column, value) {
          if (column === 'player_id') playerId = value;
          if (column === 'is_public') publicOnly = value;
          return query;
        },
        then(resolve, reject) {
          if (!resultPromise) {
            let source = nativeFrom('player_attribute_state').select('*');
            if (playerId) source = source.eq('player_id', playerId);
            resultPromise = source.then(({ data, error }) => {
              if (error) return { data: null, error };
              const rows = [];
              for (const state of (data || [])) {
                for (const [code, meta] of Object.entries(definitions)) {
                  rows.push({
                    attribute_code: code,
                    current_value: state[code],
                    coach_value: state[code],
                    officer_value: null,
                    ai_value: null,
                    confidence_level: state.confidence ?? 0,
                    last_assessed_at: state.updated_at ?? null,
                    is_public: publicOnly === false ? false : true,
                    attribute_definitions: {
                      label: meta[0],
                      category: meta[1],
                      display_order: meta[2],
                    },
                  });
                }
              }
              return { data: rows, error: null };
            });
          }
          return resultPromise.then(resolve, reject);
        },
      };
      return query;
    };

    client.from = compatFrom;
    client.__playproAttributeCompat = true;
  }

  /*
   * PlayPro Navigation v2
   * Product contract:
   * TOP    = Home | Cari | Pertandingan | Kedai
   * SUB    = Pengesahan KYC | Asesmen Player/Coach
   * BOTTOM = Create | My Team | Inbox | Passport
   *
   * This shell intentionally changes navigation only. It does not touch
   * Supabase, schema, auth policy, or application data.
   */
  function hideLegacyHomeBanners() {
    const phrases = [
      'RUANG SOSIAL OTAI',
      'MYTEAM & COACH COMMAND CENTER',
    ];
    const all = Array.from(document.querySelectorAll('body *'));
    all.forEach((el) => {
      if (el.children.length > 4) return;
      const text = norm(el.textContent || '');
      if (!phrases.some((phrase) => text.includes(phrase))) return;
      const target = el.closest('.card, article, section') || el;
      if (target.id === 'tab-home') return;
      target.setAttribute('data-playpro-legacy-banner', 'hidden');
      target.style.display = 'none';
    });
  }

  function navigateTab(tab) {
    if (typeof window.go === 'function' && ['home','explore','team','inbox','profile'].includes(tab)) {
      window.go(tab);
      return;
    }
    const el = document.getElementById('tab-' + tab);
    if (el) {
      document.querySelectorAll('[id^="tab-"]').forEach((node) => { node.style.display = 'none'; });
      el.style.display = 'block';
    }
  }

  function openCreateMenu() {
    let mask = document.getElementById('playpro-create-menu');
    if (!mask) {
      mask = document.createElement('div');
      mask.id = 'playpro-create-menu';
      mask.innerHTML = '<div class="pp-create-panel" role="dialog" aria-modal="true" aria-label="Create PlayPro">' +
        '<div class="pp-create-head"><strong>➕ Create</strong><button type="button" class="pp-create-close" aria-label="Tutup">✕</button></div>' +
        '<div class="pp-create-grid">' +
          '<a href="/player_onboarding_v2.html">⚽<span>Player</span></a>' +
          '<a href="/coach_profile_v2.html">🧑‍🏫<span>Coach</span></a>' +
          '<a href="/club.html">🏢<span>Kelab</span></a>' +
          '<a href="/organizer/competitions">🏆<span>Organiser</span></a>' +
          '<a href="/referee">🧑‍⚖️<span>Referee</span></a>' +
          '<button type="button" data-coming-soon="true">🛍️<span>Peniaga</span></button>' +
        '</div>' +
      '</div>';
      const style = document.createElement('style');
      style.id = 'playpro-create-menu-style';
      style.textContent = '#playpro-create-menu{position:fixed;inset:0;z-index:9998;background:rgba(0,0,0,.45);display:flex;align-items:flex-end;justify-content:center;padding:16px}' +
        '.pp-create-panel{width:min(520px,100%);background:var(--bg2);color:var(--txt);border:1px solid var(--bdr);border-radius:14px;box-shadow:0 18px 60px rgba(0,0,0,.3);overflow:hidden}' +
        '.pp-create-head{display:flex;align-items:center;justify-content:space-between;padding:14px 16px;border-bottom:1px solid var(--bdr);font-size:.95rem}' +
        '.pp-create-close{border:0;background:var(--bg3);color:var(--txt);border-radius:8px;width:32px;height:32px;cursor:pointer}' +
        '.pp-create-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;padding:12px}' +
        '.pp-create-grid a,.pp-create-grid button{min-height:82px;border:1px solid var(--bdr);background:var(--bg3);color:var(--txt);border-radius:10px;text-decoration:none;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:7px;font:600 .72rem Inter,system-ui,sans-serif;cursor:pointer}' +
        '.pp-create-grid a:hover,.pp-create-grid button:hover{border-color:var(--g);color:var(--g);background:var(--glt)}' +
        '.pp-create-grid a:first-child,.pp-create-grid a:nth-child(2){background:var(--glt)}' +
        '.pp-create-grid a span,.pp-create-grid button span{font-size:.72rem}' +
        '@media(max-width:480px){.pp-create-grid{grid-template-columns:repeat(2,1fr)}}';
      document.head.appendChild(style);
      document.body.appendChild(mask);
      mask.querySelector('.pp-create-close').addEventListener('click', () => mask.remove());
      mask.addEventListener('click', (event) => { if (event.target === mask) mask.remove(); });
      mask.querySelector('[data-coming-soon="true"]').addEventListener('click', () => {
        mask.remove();
        if (typeof window.toast === 'function') window.toast('🛍️ Peniaga / Kedai akan dibuka dalam modul Kedai.');
      });
    }
    mask.style.display = 'flex';
  }
  window.openCreateMenu = openCreateMenu;

  function openKedai() {
    /* Kedai has no dedicated public page in the current repo. Keep the link live
       by opening discovery rather than sending the user to a 404 page. */
    navigateTab('explore');
    if (typeof window.toast === 'function') window.toast('🛍️ Kedai PlayPro — katalog sedang disediakan.');
  }
  window.openKedai = openKedai;

  function buildNavigationV2() {
    const top = document.getElementById('hdr-nav');
    if (top) {
      top.innerHTML =
        '<div class="hn-item on" id="hn-home" data-pp-nav="home">🏠 Home</div>' +
        '<div class="hn-item" id="hn-explore" data-pp-nav="explore">🔍 Cari</div>' +
        '<div class="hn-item" id="hn-competition" data-pp-nav="competition">🏆 Pertandingan</div>' +
        '<div class="hn-item" id="hn-shop" data-pp-nav="shop">🛍️ Kedai</div>';
      top.querySelector('[data-pp-nav="home"]').onclick = () => navigateTab('home');
      top.querySelector('[data-pp-nav="explore"]').onclick = () => navigateTab('explore');
      top.querySelector('[data-pp-nav="competition"]').onclick = () => { window.location.assign('/organizer/competitions'); };
      top.querySelector('[data-pp-nav="shop"]').onclick = openKedai;
    }

    const sub = document.getElementById('hdr-bread');
    if (sub) {
      sub.innerHTML =
        '<a class="hb-item" href="/player_kyc.html"><span class="hb-ic">✓</span> Pengesahan KYC</a>' +
        '<span class="hb-arrow">›</span>' +
        '<a class="hb-item" href="/technical_assessor.html"><span class="hb-ic">📊</span> Asesmen Player/Coach</a>';
    }

    const bottom = document.getElementById('bnav');
    if (bottom) {
      bottom.style.gridTemplateColumns = 'repeat(4,1fr)';
      bottom.innerHTML =
        '<div class="bn" id="bn-create"><div class="bn-ic">➕</div><div class="bn-lb">Create</div></div>' +
        '<div class="bn" id="bn-team"><div class="bn-ic">👥</div><div class="bn-lb">My Team</div></div>' +
        '<div class="bn" id="bn-inbox"><div class="bn-ic">📬</div><div class="bn-lb">Inbox</div></div>' +
        '<div class="bn" id="bn-profile"><div class="bn-ic">📋</div><div class="bn-lb">Passport</div></div>';
      document.getElementById('bn-create').onclick = openCreateMenu;
      document.getElementById('bn-team').onclick = () => navigateTab('team');
      document.getElementById('bn-inbox').onclick = () => navigateTab('inbox');
      document.getElementById('bn-profile').onclick = () => navigateTab('profile');
    }

    hideLegacyHomeBanners();
  }

  function classifyAndClean() {
    buildNavigationV2();
    syncHubOnlySections();
  }

  function boot() {
    installPlayerAttributeCompatibility();
    classifyAndClean();
    // Existing PlayPro pages can render navigation after initial load.
    const observer = new MutationObserver(() => {
      classifyAndClean();
      installPlayerAttributeCompatibility();
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(() => observer.disconnect(), 10000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }
})();
