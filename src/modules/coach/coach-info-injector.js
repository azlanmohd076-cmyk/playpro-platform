/*
 * PlayPro Model 6 — Coach Matrix Info Injector
 * Injects one safe sidebar row above Tetapan and preloads the PCSAC info modal.
 * Does not edit public/index.html directly.
 */
(function attachCoachInfoInjector(root) {
  'use strict';

  var bridge = root.PlayProModel6 = root.PlayProModel6 || {};

  var CoachInfoService = {
    modalLoaded: false,
    menuInjected: false,

    async init() {
      console.log('⚙️ [PlayPro Model 6] Menjalankan suntikan menu Matriks Penarafan Coach...');
      this.injectSidebarMenu();
      await this.preloadModalStructure();
    },

    findTetapanRow() {
      var labels = document.querySelectorAll('span, div, a, li');
      for (var i = 0; i < labels.length; i++) {
        var el = labels[i];
        if (!el || !el.textContent) continue;
        if (el.textContent.trim() === 'Tetapan' && el.children.length === 0) {
          var row = el.closest ? el.closest('.dr-row') : null;
          return row || (el.closest ? (el.closest('div') || el.closest('li') || el.closest('a')) : null);
        }
      }
      return null;
    },

    injectSidebarMenu() {
      if (this.menuInjected || document.getElementById('dr-coach-pcsap-info')) return;

      var tetapanRow = this.findTetapanRow();
      if (!tetapanRow || !tetapanRow.parentNode) {
        console.warn("⚠️ [PlayPro Model 6] Gagal menemui menu 'Tetapan' untuk suntikan PCSAC.");
        return;
      }

      var newMenuRow = document.createElement(tetapanRow.tagName.toLowerCase());
      newMenuRow.id = 'dr-coach-pcsap-info';
      newMenuRow.className = tetapanRow.className || 'dr-row';
      newMenuRow.style.cssText = tetapanRow.style.cssText || '';
      newMenuRow.style.cursor = 'pointer';
      newMenuRow.setAttribute('role', 'button');
      newMenuRow.setAttribute('tabindex', '0');
      newMenuRow.setAttribute('title', 'Matriks Penarafan Coach PCSAP');

      var icon = document.createElement('span');
      icon.className = 'dr-ic';
      icon.textContent = '📊';

      var text = document.createElement('span');
      text.className = 'dr-tx';
      text.textContent = 'Penarafan Coach (PCSAP)';

      newMenuRow.appendChild(icon);
      newMenuRow.appendChild(text);

      var self = this;
      newMenuRow.addEventListener('click', function(e) {
        e.preventDefault();
        self.toggleModal();
      });
      newMenuRow.addEventListener('keydown', function(e) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          self.toggleModal();
        }
      });

      tetapanRow.parentNode.insertBefore(newMenuRow, tetapanRow);
      this.menuInjected = true;
      console.log("🚀 [PlayPro Model 6] Menu 'Penarafan Coach (PCSAP)' berjaya disuntik.");
    },

    async preloadModalStructure() {
      if (this.modalLoaded || document.getElementById('playpro-matrix-modal')) {
        this.modalLoaded = true;
        return;
      }

      try {
        var response = await fetch('/src/modules/coach/coach-matrix-info.html');
        if (!response.ok) throw new Error('Gagal memuatkan fail HTML info.');

        var htmlContent = await response.text();
        var wrapper = document.createElement('div');
        wrapper.innerHTML = htmlContent;

        while (wrapper.firstChild) {
          document.body.appendChild(wrapper.firstChild);
        }

        this.modalLoaded = true;
      } catch (err) {
        console.log('🔄 Using static string fallback for Coach Info Modal injection.');
        this.injectStaticFallback();
      }
    },

    toggleModal() {
      var modal = document.getElementById('playpro-matrix-modal');
      if (modal) {
        modal.classList.toggle('hidden');
      } else {
        console.error("❌ Elemen modal 'playpro-matrix-modal' tidak dijumpai dalam DOM.");
      }
    },

    injectStaticFallback() {
      if (document.getElementById('playpro-matrix-modal')) {
        this.modalLoaded = true;
        return;
      }

      var style = document.createElement('style');
      style.textContent = '.playpro-modal-container{position:fixed;inset:0;background:rgba(0,0,0,0.8);z-index:99999;display:flex;align-items:center;justify-content:center;padding:16px}.playpro-modal-container.hidden{display:none!important}';

      var modal = document.createElement('div');
      modal.id = 'playpro-matrix-modal';
      modal.className = 'playpro-modal-container hidden';

      var content = document.createElement('div');
      content.style.cssText = 'background:#111827;color:#fff;padding:20px;border-radius:8px;max-width:500px;text-align:center;font-family:sans-serif';

      var title = document.createElement('h3');
      title.textContent = '📊 Info Matriks Penarafan Coach';
      var para = document.createElement('p');
      para.textContent = 'Sistem pengurusan kuota penilaian 1-5 mata (Gred 1) dan 1-20 mata (Gred 2 PCSAP).';
      var button = document.createElement('button');
      button.textContent = 'Tutup';
      button.style.cssText = 'background:#38bdf8;color:#000;padding:6px 12px;border:none;border-radius:4px;cursor:pointer';
      button.addEventListener('click', this.toggleModal.bind(this));

      content.appendChild(title);
      content.appendChild(para);
      content.appendChild(button);
      modal.appendChild(content);
      document.head.appendChild(style);
      document.body.appendChild(modal);
      this.modalLoaded = true;
    }
  };

  bridge.CoachInfo = CoachInfoService;

  document.addEventListener('PlayProModel6Ready', function() {
    CoachInfoService.init();
  });

  if (bridge.ready === true) {
    CoachInfoService.init();
  }
})(typeof window !== 'undefined' ? window : globalThis);
