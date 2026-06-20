/*
 * PlayPro Model 6 — Club Manager Onboarding & Workspace UI
 * Isolated module. public/index.html remains untouched.
 */
(function attachClubManagerUI(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};
  bridge.Club = bridge.Club || {};

  function el(tag, className, text) {
    var n = document.createElement(tag);
    if (className) n.className = className;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
  }

  function field(wrap, label, input) {
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

  var ClubManagerUI = {
    renderClubManagerOnboardingForm: function(container, profile, onSubmit) {
      var target = typeof container === 'string' ? document.querySelector(container) : container;
      if (!target) return null;
      target.innerHTML = '';

      var wrap = el('div', 'pp-club-manager-onboarding');
      wrap.style.cssText = 'max-width:560px;margin:14px auto 90px;background:#0f172a;color:#e5e7eb;border:1px solid #facc15;border-radius:16px;padding:18px;box-shadow:0 12px 32px rgba(0,0,0,.35);font-family:Arial,Helvetica,sans-serif';

      var title = el('div', null, 'Sila Lengkapkan Profil Manager Kelab');
      title.style.cssText = 'font-size:1.15rem;font-weight:900;color:#facc15;margin-bottom:6px';
      var sub = el('div', null, 'Daftar kelab rasmi anda sebelum mengurus pemain, coach dan League OS.');
      sub.style.cssText = 'font-size:.82rem;color:#cbd5e1;line-height:1.45;margin-bottom:14px';
      wrap.appendChild(title);
      wrap.appendChild(sub);

      var clubName = field(wrap, 'Nama Kelab', el('input'));
      clubName.placeholder = 'Contoh: Larkin Jaya FC';
      var year = field(wrap, 'Tahun Ditubuhkan', el('input'));
      year.type = 'number';
      year.placeholder = 'Contoh: 2024';
      var ground = field(wrap, 'Padang Latihan / Home Venue', el('input'));
      ground.placeholder = 'Contoh: Padang Awam Kepayang';
      var phone = field(wrap, 'No Telefon Manager', el('input'));
      phone.type = 'tel';
      phone.placeholder = '+60123456789';
      phone.value = profile && profile.phone || '';

      var row = el('div');
      row.style.cssText = 'display:grid;grid-template-columns:1fr 1fr;gap:10px';
      var cat = el('select');
      ['Akademi','Kelab Akar Umbi','Sekolah','Komuniti','Semi-Pro','Liga Sosial'].forEach(function(v){ var o=el('option', null, v); o.value=v; cat.appendChild(o); });
      var players = el('input');
      players.type = 'number';
      players.placeholder = 'Contoh: 25';
      field(row, 'Kategori Kelab', cat);
      field(row, 'Pemain Berdaftar', players);
      wrap.appendChild(row);

      var colours = field(wrap, 'Warna Kelab', el('input'));
      colours.placeholder = 'Contoh: Biru / Putih';

      var msg = el('div');
      msg.style.cssText = 'font-size:.78rem;margin:8px 0;color:#fbbf24;font-weight:800;min-height:18px';
      wrap.appendChild(msg);

      var btn = el('button', null, 'Simpan & Buka Club Manager Workspace');
      btn.type = 'button';
      btn.style.cssText = 'width:100%;padding:11px;border:none;border-radius:10px;background:#facc15;color:#07111f;font-weight:900;cursor:pointer;margin-top:8px';
      btn.addEventListener('click', async function() {
        var payload = {
          club_name: clubName.value.trim(),
          year_founded: year.value,
          training_ground: ground.value.trim(),
          phone: phone.value.trim(),
          category: cat.value,
          registered_players_count: players.value,
          club_colours: colours.value.trim()
        };
        if (!payload.club_name) {
          msg.textContent = 'Nama kelab wajib diisi.';
          return;
        }
        btn.disabled = true;
        btn.textContent = 'Menyimpan...';
        if (typeof onSubmit === 'function') await onSubmit(payload, msg);
        btn.disabled = false;
        btn.textContent = 'Simpan & Buka Club Manager Workspace';
      });
      wrap.appendChild(btn);
      target.appendChild(wrap);
      return wrap;
    },

    renderClubManagerWorkspace: function(container, profile, clubData) {
      var target = typeof container === 'string' ? document.querySelector(container) : container;
      if (!target) return null;
      target.innerHTML = '';
      var club = clubData || {};
      var wrap = el('div');
      wrap.style.cssText = 'max-width:900px;margin:14px auto 90px;background:#0f172a;color:#fff;border-radius:16px;border:1px solid #facc15;padding:18px;font-family:Arial,Helvetica,sans-serif';
      var h = el('div', null, club.name || 'Club Manager Workspace');
      h.style.cssText = 'font-size:1.4rem;font-weight:900;color:#facc15;margin-bottom:8px';
      var s = el('div', null, 'Manager: ' + ((profile && (profile.full_name || profile.email)) || '—') + ' · Tahun: ' + (club.year_founded || '—') + ' · Venue: ' + (club.home_venue || '—'));
      s.style.cssText = 'font-size:.85rem;color:#dbeafe;margin-bottom:14px';
      var actions = el('div');
      actions.style.cssText = 'display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px';
      ['👥 Urus Pemain','👨‍🏫 Urus Coach','🏆 League OS'].forEach(function(t){ var c=el('div', null, t); c.style.cssText='background:#111827;border:1px solid #334155;border-radius:12px;padding:16px;font-weight:900;text-align:center;color:#e5e7eb'; actions.appendChild(c); });
      wrap.appendChild(h); wrap.appendChild(s); wrap.appendChild(actions); target.appendChild(wrap); return wrap;
    }
  };

  bridge.Club.ManagerUI = ClubManagerUI;
})(typeof window !== 'undefined' ? window : globalThis);
