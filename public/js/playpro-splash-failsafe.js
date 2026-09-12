/* PlayPro splash safety valve — independent of Supabase/auth/app bootstrap. */
(function () {
  'use strict';

  var released = false;

  function releaseSplash() {
    if (released) return;
    released = true;

    var splash = document.getElementById('splash');
    if (!splash) return;

    splash.setAttribute('aria-hidden', 'true');
    splash.style.pointerEvents = 'none';
    splash.style.opacity = '0';
    splash.style.visibility = 'hidden';
    splash.style.transition = 'opacity 180ms ease, visibility 0s linear 180ms';

    window.setTimeout(function () {
      splash.style.display = 'none';
    }, 220);
  }

  // Never allow an initialization failure or slow dependency to block the app.
  window.setTimeout(releaseSplash, 3500);

  // A synchronous script error / rejected promise should release it immediately.
  window.addEventListener('error', releaseSplash, { once: true });
  window.addEventListener('unhandledrejection', releaseSplash, { once: true });

  // Normal app bootstrap may remove/hide it first; this remains harmless.
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      window.setTimeout(function () {
        var splash = document.getElementById('splash');
        if (splash && splash.getAttribute('aria-hidden') === 'true') releaseSplash();
      }, 0);
    }, { once: true });
  }
})();
