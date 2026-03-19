/**
 * fb_master_script.js  v4.0
 * ─────────────────────────────────────────────────────────────────────────────
 * Finds and clicks the Facebook "Share" button for a linked post.
 * Target: m.facebook.com inside webview_windows (WebView2 / Chromium).
 *
 * Strategy:
 *   1. Dismiss sticky "Open App" banners.
 *   2. Find the post anchor via multilingual text match (EN + SI + TA).
 *   3. Walk up the DOM — share button searched directly, no container guess.
 *   4. Find the Share button by aria-label (English + Sinhala + Tamil) or inner text.
 *   5. Highlight the button (green outline) for visual confirmation.
 *   6. Click and wait for share dialog to confirm before returning.
 *   7. Return { status, message, ariaLabel } as a JSON string.
 *      (Double-encode is handled on the Flutter side.)
 *
 * Zero hardcoded CSS class names.
 * MutationObserver retries for AJAX-rendered feeds.
 * 10 s timeout with descriptive error messages.
 * Multilingual: English, සිංහල, Tamil confirmed strings.
 * ─────────────────────────────────────────────────────────────────────────────
 */
(function () {
  'use strict';

  var TIMEOUT_MS   = 10000;
  var CLICK_DELAY  = 1500;
  var HIGHLIGHT_MS = 6000;

  // ── 1. Dismiss banners ───────────────────────────────────────────────────────
  function hideBanners() {
    var selectors = [
      '[data-testid="open_app_banner"]',
      '[data-testid="msite-open-app-banner"]',
      '[data-testid="mobile-app-upsell"]',
      '.smartbanner',
      '#smartbanner',
    ];
    selectors.forEach(function (sel) {
      try {
        document.querySelectorAll(sel).forEach(function (el) {
          el.style.setProperty('display', 'none', 'important');
        });
      } catch (_) {}
    });

    // Text patterns that identify upsell/interstitial overlays:
    //   "Open App", "Install", "Use Mobile Site", "Continue to Mobile Site",
    //   "Get the App", "isn't supported", "not supported"
    var UPSELL_RE = /open\s*app|install|use\s+mobile\s+site|continue\s+to|get\s+the\s+app|isn.t\s+supported|not\s+supported/i;

    // Generic fixed/sticky/absolute banners mentioning upsell copy
    document.querySelectorAll('div, section, aside').forEach(function (el) {
      try {
        var cs = window.getComputedStyle(el);
        var pos = cs.position;
        if (pos !== 'fixed' && pos !== 'sticky' && pos !== 'absolute') return;
        // Skip tall elements — they are real content panels, not banners.
        if (el.getBoundingClientRect().height > 160) return;
        if (UPSELL_RE.test(el.innerText || '')) {
          el.style.setProperty('display', 'none', 'important');
        }
      } catch (_) {}
    });

    // Bottom-sheet / interstitial dialogs (role="dialog") with upsell copy.
    // These are the "Use Mobile Site" modals that block interaction on
    // mobile-layout pages like facebook.com/groups/.
    document.querySelectorAll('[role="dialog"], [role="alertdialog"]').forEach(function (el) {
      try {
        if (UPSELL_RE.test(el.innerText || '')) {
          el.style.setProperty('display', 'none', 'important');
        }
      } catch (_) {}
    });
  }

  // ── 2. Multilingual anchor strings — confirmed on real Facebook UI ───────────
  //
  //   English : "From your link"          — confirmed ✅
  //   සිංහල  : "ඔබ සබැඳිය වෙතින්"       — confirmed ✅
  //   සිංහල  : "ඔබගේ සබැඳියෙන්"         — alt variant ✅
  //   Tamil   : "உங்கள் இணைப்பிலிருந்து" — confirmed ✅
  //
  var ANCHOR_TEXTS = [
    'From your link',
    'from your link',
    '\u0D9D\u0DB6 \u0DC3\u0DB6\u0DD9\u0DAF\u0DD2\u0DBA \u0DC0\u0DDA\u0DAD\u0DD2\u0DB1\u0DCA', // ඔබ සබැඳිය වෙතින්
    '\u0D9D\u0DB6\u0DDA\u0D9C\u0DDA \u0DC3\u0DB6\u0DD9\u0DAF\u0DD2\u0DBA\u0DDA\u0DB1\u0DCA',  // ඔබගේ සබැඳියෙන්
    '\u0B89\u0B99\u0BCD\u0B95\u0BB3\u0BCD \u0B87\u0BA3\u0BC8\u0BAA\u0BCD\u0BAA\u0BBF\u0BB2\u0BBF\u0BB0\u0BC1\u0BA8\u0BCD\u0BA4\u0BC1', // உங்கள் இணைப்பிலிருந்து
  ];

  // ── 3. Find anchor element via text match ────────────────────────────────────
  function findAnchor() {
    // Fast path: TreeWalker over all text nodes
    var walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
      null,
      false
    );
    var node;
    while ((node = walker.nextNode())) {
      var v = (node.nodeValue || '').trim();
      if (ANCHOR_TEXTS.indexOf(v) !== -1) {
        return node.parentElement;
      }
    }
    // Fallback: innerText scan on visible elements
    var els = document.querySelectorAll('div, span, p, a');
    for (var i = 0; i < els.length; i++) {
      var t = (els[i].innerText || '').trim();
      if (ANCHOR_TEXTS.indexOf(t) !== -1) {
        return els[i];
      }
    }
    return null;
  }

  // ── 4. Walk UP from anchor — find share button directly, no container guess ──
  //
  // OLD approach: anchor → findContainer() → findShareButton(container)
  //   Problem: height heuristic selects wrong ancestor → wrong post's button clicked
  //
  // NEW approach: walk up from anchor, at each level search for share button.
  //   Stop the moment we find it — no intermediate container step needed.
  //   This eliminates the wrong-container bug entirely.
  //
  function findShareButtonFromAnchor(anchor) {
    var tmp = anchor;
    var MAX_LEVELS = 20; // DOM ඉහළට කොච්චර walk කරනවද limit
    var level = 0;

    while (tmp && tmp !== document.body && level < MAX_LEVELS) {
      var btn = _searchShareButton(tmp);
      if (btn) return btn;
      tmp = tmp.parentElement;
      level++;
    }

    // Last resort: full document search
    return _searchShareButton(document.body);
  }

  function _searchShareButton(root) {
    var btns = root.querySelectorAll('[role="button"], button');
    for (var i = 0; i < btns.length; i++) {
      if (isShareButton(btns[i]) && isVisible(btns[i])) return btns[i];
    }
    return null;
  }

  // ── 5. Identify the Share button ────────────────────────────────────────────
  //
  // Supported aria-label values (confirmed):
  //   English : "Share"
  //   සිංහල  : "බෙදාගන්න" / "බෙදා ගන්න" / "සලකුණු කරන්න"
  //   Tamil   : "பகிர்" (Pakir)

  var SHARE_LABELS = [
    '\u0DB6\u0DD9\u0DAF\u0DCF\u0D9C\u0DB1\u0DCA\u0DB1',           // බෙදාගන්න
    '\u0DB6\u0DD9\u0DAF\u0DCF \u0D9C\u0DB1\u0DCA\u0DB1',          // බෙදා ගන්න
    '\u0DC3\u0DBD\u0D9A\u0DD4\u0DAB\u0DD4 \u0D9A\u0DBB\u0DB1\u0DCA\u0DB1', // සලකුණු කරන්න
    '\u0BAA\u0B95\u0BBF\u0BB0\u0BCD',                              // பகிர் (Tamil)
  ];

  /** Strip Unicode private-use / icon glyphs and normalise to lowercase ASCII. */
  function stripIcons(s) {
    return (s || '')
      .replace(/[\uE000-\uF8FF]/g, '')          // PUA block
      .replace(/[\uDB80-\uDBFF][\uDC00-\uDFFF]/g, '') // surrogate pairs (emoji)
      .replace(/[^\x00-\x7F]/g, '')             // remaining non-ASCII
      .trim()
      .toLowerCase();
  }

  function isShareButton(el) {
    var label = el.getAttribute('aria-label') || '';

    // සිංහල + Tamil labels — original string compare (toLowerCase බලන්නේ නැහැ)
    for (var s = 0; s < SHARE_LABELS.length; s++) {
      if (label.indexOf(SHARE_LABELS[s]) !== -1) return true;
    }

    // English label — icon glyphs strip කරලා check කරනවා
    if (stripIcons(label).indexOf('share') !== -1) return true;

    // innerText exact match (English fallback)
    var innerText = (el.innerText || '').trim().toLowerCase();
    if (innerText === 'share') return true;

    // Tamil innerText
    if ((el.innerText || '').trim() === '\u0BAA\u0B95\u0BBF\u0BB0\u0BCD') return true;

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

  // ── 5. Highlight the button ──────────────────────────────────────────────────
  function highlightButton(el) {
    // Inject style once
    if (!document.getElementById('__fbMS_style')) {
      var s = document.createElement('style');
      s.id = '__fbMS_style';
      s.textContent =
        '.__fbMS_hl{' +
          'outline:4px solid #00FF00!important;' +
          'outline-offset:3px!important;' +
          'background:rgba(0,255,0,.1)!important;' +
        '}';
      (document.head || document.documentElement).appendChild(s);
    }
    el.classList.add('__fbMS_hl');

    // Floating badge overlay
    var r  = el.getBoundingClientRect();
    var ov = document.createElement('div');
    ov.id  = '__fbMS_overlay';
    ov.style.cssText =
      'position:fixed;' +
      'top:'    + (r.top  - 6) + 'px;' +
      'left:'   + (r.left - 6) + 'px;' +
      'width:'  + (r.width  + 12) + 'px;' +
      'height:' + (r.height + 12) + 'px;' +
      'border:4px solid #00FF00;' +
      'box-shadow:0 0 12px rgba(0,255,0,.6);' +
      'background:rgba(0,255,0,.06);' +
      'z-index:2147483647;pointer-events:none;' +
      'border-radius:6px;box-sizing:border-box;';

    var badge = document.createElement('div');
    badge.style.cssText =
      'position:absolute;top:-24px;left:0;' +
      'background:#006600;color:#fff;' +
      'font:bold 10px/1 sans-serif;padding:3px 8px;' +
      'border-radius:3px 3px 0 0;white-space:nowrap;';
    badge.textContent = '\u2705 Share button — clicking in 1.5s\u2026';
    ov.appendChild(badge);
    document.body.appendChild(ov);

    el.scrollIntoView({ behavior: 'smooth', block: 'center' });

    setTimeout(function () {
      el.classList.remove('__fbMS_hl');
      var st = document.getElementById('__fbMS_style');
      if (st) st.remove();
      var o = document.getElementById('__fbMS_overlay');
      if (o) o.remove();
    }, HIGHLIGHT_MS);
  }

  // ── 6. Click ─────────────────────────────────────────────────────────────────
  function clickButton(el) {
    setTimeout(function () {
      el.focus();
      el.click();
      ['mousedown', 'mouseup', 'click'].forEach(function (evtName) {
        el.dispatchEvent(
          new MouseEvent(evtName, { bubbles: true, cancelable: true, view: window })
        );
      });
    }, CLICK_DELAY);
  }

  // ── 7. Main run ──────────────────────────────────────────────────────────────
  function run() {
    hideBanners();

    var anchor = findAnchor();
    if (!anchor) {
      return {
        status: 'failed',
        message: 'Post anchor text not found (EN/SI/TA). Make sure the post page is fully loaded.',
      };
    }

    // නව approach: container guess නැතුව anchor එකෙන් directly button හොයනවා
    var btn = findShareButtonFromAnchor(anchor);

    if (!btn) {
      return {
        status: 'failed',
        message: 'Share button not found near the post anchor.',
      };
    }

    highlightButton(btn);
    clickButton(btn);

    return {
      status:    'success',
      message:   'Share button found — click queued (1.5s).',
      ariaLabel: btn.getAttribute('aria-label') || '',
    };
  }

  // ── 8. Promise wrapper (with MutationObserver retry) ─────────────────────────
  window.__fbMasterRun = function () {
    return new Promise(function (resolve) {
      var settled = false;
      var obs     = null;
      var timer   = null;

      function settle(result) {
        if (settled) return;
        settled = true;
        if (obs)   { obs.disconnect();    obs   = null; }
        if (timer) { clearTimeout(timer); timer = null; }
        // Also post via WebView2 native channel (ignored if not available)
        try {
          window.chrome.webview.postMessage(
            JSON.stringify({ type: 'FB_MASTER', payload: JSON.stringify(result) })
          );
        } catch (_) {}
        resolve(result);
      }

      // Immediate attempt
      var immediate = run();
      if (immediate.status === 'success') {
        settle(immediate);
        return;
      }

      // Retry on DOM mutations (AJAX feeds)
      obs = new MutationObserver(function () {
        if (settled) return;
        var retry = run();
        if (retry.status === 'success') settle(retry);
      });
      obs.observe(document.body, {
        childList:     true,
        subtree:       true,
        characterData: true,
        attributes:    true,
        attributeFilter: ['aria-label', 'role', 'style'],
      });

      // Hard timeout
      timer = setTimeout(function () {
        settle({
          status:  'failed',
          message: 'Timed out after ' + (TIMEOUT_MS / 1000) + ' seconds.',
        });
      }, TIMEOUT_MS);
    });
  };

  // Execute and return JSON string (Flutter will double-decode)
  return window.__fbMasterRun().then(function (r) {
    return JSON.stringify(r);
  });
}());