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
  }

  function boot() {
    classifyAndClean();
    // Existing PlayPro pages can render navigation after initial load.
    const observer = new MutationObserver(() => classifyAndClean());
    observer.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(() => observer.disconnect(), 10000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }
})();
