/**
 * fb_master_script.js  v3.1
 * ─────────────────────────────────────────────────────────────────────────────
 * FIX (v3.1): webview_windows' executeScript() does NOT await Promises.
 *   The old v3.0 code returned `window.__fbMasterRun().then(...)` — a Promise
 *   — which executeScript() serialised as {} immediately, causing the
 *   symptom: `RAW result: {}` → status=unknown → ❌ FAILED.
 *
 * New strategy:
 *   a) Run synchronously first. If the Share button is already in the DOM,
 *      return JSON.stringify(result) directly. executeScript() captures it. ✅
 *   b) If DOM is not ready, register a MutationObserver and return the string
 *      'pending'. The observer posts the result via postMessage when ready.
 *      Flutter listens on _webMessageStream for 'MASTER_RESULT:<json>'.
 * ─────────────────────────────────────────────────────────────────────────────
 */
(function () {
  'use strict';

  var TIMEOUT_MS   = 10000;
  var CLICK_DELAY  = 1500;
  var HIGHLIGHT_MS = 6000;

  // ── 1. Dismiss banners ──────────────────────────────────────────────────────
  function hideBanners() {
    document.querySelectorAll('.fixed-container.bottom').forEach(function(el) {
      try { el.parentNode && el.parentNode.removeChild(el); } catch(_) {}
    });
    var UPSELL_RE = /open\s*app|install|use\s+mobile\s+site|continue\s+to|get\s+the\s+app|isn.t\s+supported|not\s+supported/i;
    document.querySelectorAll('div, section, aside').forEach(function (el) {
      try {
        var cs = window.getComputedStyle(el);
        var pos = cs.position;
        if (pos !== 'fixed' && pos !== 'sticky' && pos !== 'absolute') return;
        if (el.getBoundingClientRect().height > 160) return;
        if (UPSELL_RE.test(el.innerText || '')) {
          el.style.setProperty('display', 'none', 'important');
        }
      } catch (_) {}
    });
    document.querySelectorAll('[role="dialog"], [role="alertdialog"]').forEach(function (el) {
      try {
        if (UPSELL_RE.test(el.innerText || '')) {
          el.style.setProperty('display', 'none', 'important');
        }
      } catch (_) {}
    });
  }

  // ── 2. Find "From your link" anchor ────────────────────────────────────────
  function findAnchor() {
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
    var node;
    while ((node = walker.nextNode())) {
      var v = (node.nodeValue || '').trim();
      if (v === 'From your link' || v === 'from your link') return node.parentElement;
    }
    var els = document.querySelectorAll('div, span, p, a');
    for (var i = 0; i < els.length; i++) {
      if ((els[i].innerText || '').trim() === 'From your link') return els[i];
    }
    return null;
  }

  // ── 3. Walk to post container ───────────────────────────────────────────────
  function findContainer(anchor) {
    var tmp = anchor;
    while (tmp && tmp !== document.body) {
      if (/^FeedUnit/.test(tmp.getAttribute('data-pagelet') || '')) return tmp;
      tmp = tmp.parentElement;
    }
    tmp = anchor;
    while (tmp && tmp !== document.body) {
      var role = (tmp.getAttribute('role') || '');
      if (role === 'article' || tmp.tagName === 'ARTICLE') return tmp;
      tmp = tmp.parentElement;
    }
    tmp = anchor;
    while (tmp && tmp !== document.body) {
      var parent = tmp.parentElement;
      if (parent && parent.getAttribute('role') === 'feed') return tmp;
      tmp = parent;
    }
    tmp = anchor;
    while (tmp && tmp.parentElement && tmp.parentElement !== document.body) {
      if (tmp.offsetHeight >= 200 && tmp.parentElement.offsetHeight > tmp.offsetHeight * 1.2) return tmp;
      tmp = tmp.parentElement;
    }
    return (anchor.parentElement && anchor.parentElement.parentElement) || anchor.parentElement || anchor;
  }

  // ── 4. Identify the Share button ────────────────────────────────────────────
  var SHARE_SINHALA = [
    '\u0DB6\u0DD9\u0DAF\u0DCF\u0D9C\u0DB1\u0DCA\u0DB1',
    '\u0DB6\u0DD9\u0DAF\u0DCF \u0D9C\u0DB1\u0DCA\u0DB1',
    '\u0DC3\u0DBD\u0D9A\u0DD4\u0DAB\u0DD4 \u0D9A\u0DBB\u0DB1\u0DCA\u0DB1',
  ];

  function stripIcons(s) {
    return (s || '').replace(/[\uE000-\uF8FF]/g, '').replace(/[\uDB80-\uDBFF][\uDC00-\uDFFF]/g, '').replace(/[^\x00-\x7F]/g, '').trim().toLowerCase();
  }

  function isShareButton(el) {
    var label = el.getAttribute('aria-label') || '';
    var labelLC = label.toLowerCase();
    for (var s = 0; s < SHARE_SINHALA.length; s++) {
      if (labelLC.indexOf(SHARE_SINHALA[s]) !== -1) return true;
    }
    if (stripIcons(label).indexOf('share') !== -1) return true;
    if ((el.innerText || '').trim().toLowerCase() === 'share') return true;
    return false;
  }

  function isVisible(el) {
    if (!el) return false;
    var r = el.getBoundingClientRect();
    if (!r.width || !r.height) return false;
    var cur = el;
    while (cur && cur !== document.body) {
      var cs = window.getComputedStyle(cur);
      if (cs.display === 'none' || cs.visibility === 'hidden') return false;
      cur = cur.parentElement;
    }
    return true;
  }

  function findShareButton(container) {
    var btns = container.querySelectorAll('[role="button"]');
    for (var i = 0; i < btns.length; i++) {
      if (isShareButton(btns[i]) && isVisible(btns[i])) return btns[i];
    }
    var all = document.querySelectorAll('[role="button"]');
    for (var j = 0; j < all.length; j++) {
      if (isShareButton(all[j]) && isVisible(all[j])) return all[j];
    }
    return null;
  }

  // ── 5. Highlight ────────────────────────────────────────────────────────────
  function highlightButton(el) {
    if (!document.getElementById('__fbMS_style')) {
      var s = document.createElement('style');
      s.id = '__fbMS_style';
      s.textContent = '.__fbMS_hl{outline:4px solid #00FF00!important;outline-offset:3px!important;background:rgba(0,255,0,.1)!important;}';
      (document.head || document.documentElement).appendChild(s);
    }
    el.classList.add('__fbMS_hl');
    var r = el.getBoundingClientRect();
    var ov = document.createElement('div');
    ov.id = '__fbMS_overlay';
    ov.style.cssText =
      'position:fixed;top:'+(r.top-6)+'px;left:'+(r.left-6)+'px;'+
      'width:'+(r.width+12)+'px;height:'+(r.height+12)+'px;'+
      'border:4px solid #00FF00;box-shadow:0 0 12px rgba(0,255,0,.6);'+
      'background:rgba(0,255,0,.06);z-index:2147483647;pointer-events:none;'+
      'border-radius:6px;box-sizing:border-box;';
    var badge = document.createElement('div');
    badge.style.cssText = 'position:absolute;top:-24px;left:0;background:#006600;color:#fff;font:bold 10px/1 sans-serif;padding:3px 8px;border-radius:3px 3px 0 0;white-space:nowrap;';
    badge.textContent = '\u2705 Share button \u2014 clicking in 1.5s\u2026';
    ov.appendChild(badge);
    document.body.appendChild(ov);
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    setTimeout(function () {
      el.classList.remove('__fbMS_hl');
      var st = document.getElementById('__fbMS_style'); if (st) st.remove();
      var o = document.getElementById('__fbMS_overlay'); if (o) o.remove();
    }, HIGHLIGHT_MS);
  }

  // ── 6. Click ────────────────────────────────────────────────────────────────
  function clickButton(el) {
    setTimeout(function () {
      el.focus();
      el.click();
      ['mousedown', 'mouseup', 'click'].forEach(function (evtName) {
        el.dispatchEvent(new MouseEvent(evtName, { bubbles: true, cancelable: true, view: window }));
      });
    }, CLICK_DELAY);
  }

  // ── 7. Post result back to Flutter ──────────────────────────────────────────
  function postResult(result) {
    try { window.chrome.webview.postMessage('MASTER_RESULT:' + JSON.stringify(result)); } catch (_) {}
  }

  // ── 8. Core logic (always synchronous) ─────────────────────────────────────
  function run() {
    hideBanners();
    var anchor = findAnchor();
    if (!anchor) {
      return { status: 'failed', message: '"From your link" text not found. Make sure the post page is fully loaded.' };
    }
    var container = findContainer(anchor);
    var btn = findShareButton(container);
    if (!btn) {
      return { status: 'failed', message: 'Share button not found in the post container.' };
    }
    highlightButton(btn);
    clickButton(btn);
    return { status: 'success', message: 'Share button located and clicked.', ariaLabel: btn.getAttribute('aria-label') || '' };
  }

  // ── 9. Entry point ──────────────────────────────────────────────────────────
  //
  // executeScript() in webview_windows is synchronous — it captures whatever
  // the IIFE *returns*.  Promises are NOT awaited; they serialise as {}.
  //
  // Path A (fast): button already in DOM → return JSON string directly.
  // Path B (slow): DOM still loading → return 'pending', observer posts result
  //                via postMessage('MASTER_RESULT:<json>') when ready.
  //
  var immediate = run();
  if (immediate.status === 'success') {
    return JSON.stringify(immediate);   // Path A ✅
  }

  // Path B — set up retry observer (guard against double-injection)
  if (!window.__fbMSObserver) {
    var settled = false;
    var obsTimer = null;

    function settle(result) {
      if (settled) return;
      settled = true;
      if (window.__fbMSObserver) { window.__fbMSObserver.disconnect(); window.__fbMSObserver = null; }
      if (obsTimer) { clearTimeout(obsTimer); obsTimer = null; }
      postResult(result);
    }

    window.__fbMSObserver = new MutationObserver(function () {
      if (settled) return;
      var retry = run();
      if (retry.status === 'success') settle(retry);
    });

    window.__fbMSObserver.observe(document.body, {
      childList: true, subtree: true, characterData: true,
      attributes: true, attributeFilter: ['aria-label', 'role', 'style'],
    });

    obsTimer = setTimeout(function () {
      settle({ status: 'failed', message: 'Timed out after ' + (TIMEOUT_MS / 1000) + ' seconds.' });
    }, TIMEOUT_MS);
  }

  return 'pending';   // Flutter: wait for MASTER_RESULT webMessage
}());
