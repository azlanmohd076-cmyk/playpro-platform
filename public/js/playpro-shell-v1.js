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

  function classifyAndClean() {
    const primary = ['LIVE', 'CARI', 'MYHUB', 'MYTEAM', 'PASSPORT', 'LIGA', 'KEDAI', 'HUB'];
    const secondary = ['HUB', 'LIGA', 'PADANG', 'PENGADIL'];
    const bottom = ['HUB', 'CARI', 'MYHUB', 'MYTEAM', 'INBOX', 'PASSPORT'];

    const candidates = Array.from(document.querySelectorAll('header, nav, footer, [role="navigation"]'));

    // Remove the old secondary global navigation row.
    candidates.forEach((root) => {
      if (hasLabels(root, secondary) >= 3) {
        root.setAttribute('data-playpro-shell', 'secondary-global');
        root.style.display = 'none';
      }
    });

    // Clean the first primary/header navigation that contains the old global labels.
    const primaryRoots = candidates.filter((root) => hasLabels(root, primary) >= 3);
    if (primaryRoots.length) {
      const root = primaryRoots[0];
      root.setAttribute('data-playpro-shell', 'primary');
      directActionNodes(root).forEach((el) => {
        const text = label(el);
        if (['HUB', 'MYHUB', 'LIGA', 'PASSPORT'].includes(text)) hideAction(el);
      });
    }

    // Clean the bottom/fixed navigation. Only four destinations remain.
    const bottomRoots = candidates.filter((root) => hasLabels(root, bottom) >= 4);
    bottomRoots.forEach((root) => {
      root.setAttribute('data-playpro-shell', 'bottom');
      directActionNodes(root).forEach((el) => {
        const text = label(el);
        if (['HUB', 'MYHUB'].includes(text)) hideAction(el);
      });
    });

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
