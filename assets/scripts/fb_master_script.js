/**
 * fb_master_script.js  v3.0
 * ─────────────────────────────────────────────────────────────────────────────
 * Finds and clicks the Facebook "Share" button for a linked post.
 * Target: m.facebook.com inside webview_windows (WebView2 / Chromium).
 *
 * Strategy:
 *   1. Dismiss sticky "Open App" banners.
 *   2. Find the "From your link" post anchor via TreeWalker.
 *   3. Walk up to the nearest post container.
 *   4. Find the Share button by aria-label (English + Sinhala) or inner text.
 *   5. Highlight the button (green outline) for visual confirmation.
 *   6. Click it after a 1.5 s delay.
 *   7. Return { status, message, ariaLabel } as a JSON string.
 *      (Double-encode is handled on the Flutter side.)
 *
 * Zero hardcoded CSS class names.
 * MutationObserver retries for AJAX-rendered feeds.
 * 10 s timeout with descriptive error messages.
 * ─────────────────────────────────────────────────────────────────────────────
 */
(function () {
  'use strict';

  var TIMEOUT_MS   = 10000;
  var CLICK_DELAY  = 1500;
  var HIGHLIGHT_MS = 6000;

  // ── 1. Dismiss banners ───────────────────────────────────────────────────────
  function hideBanners() {
    // Remove the "Open app" bottom bar — class="m fixed-container bottom"
    // Use classList check for exact match (both classes must be present).
    document.querySelectorAll('.fixed-container.bottom').forEach(function(el) {
      try { el.parentNode && el.parentNode.removeChild(el); } catch(_) {}
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

  // ── 2. Locate "From your link" text node ────────────────────────────────────
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
      if (v === 'From your link' || v === 'from your link') {
        return node.parentElement;
      }
    }
    // Fallback: innerText scan
    var els = document.querySelectorAll('div, span, p, a');
    for (var i = 0; i < els.length; i++) {
      if ((els[i].innerText || '').trim() === 'From your link') {
        return els[i];
      }
    }
    return null;
  }

  // ── 3. Climb to post container ───────────────────────────────────────────────
  function findContainer(anchor) {
    var tmp = anchor;

    // data-pagelet="FeedUnit.*"
    while (tmp && tmp !== document.body) {
      if (/^FeedUnit/.test(tmp.getAttribute('data-pagelet') || '')) return tmp;
      tmp = tmp.parentElement;
    }
    // role="article" / <article>
    tmp = anchor;
    while (tmp && tmp !== document.body) {
      var role = (tmp.getAttribute('role') || '');
      if (role === 'article' || tmp.tagName === 'ARTICLE') return tmp;
      tmp = tmp.parentElement;
    }
    // Direct child of role="feed"
    tmp = anchor;
    while (tmp && tmp !== document.body) {
      var parent = tmp.parentElement;
      if (parent && parent.getAttribute('role') === 'feed') return tmp;
      tmp = parent;
    }
    // Height heuristic: first ancestor ≥ 200 px
    tmp = anchor;
    while (tmp && tmp.parentElement && tmp.parentElement !== document.body) {
      if (
        tmp.offsetHeight >= 200 &&
        tmp.parentElement.offsetHeight > tmp.offsetHeight * 1.2
      ) return tmp;
      tmp = tmp.parentElement;
    }
    // Last resort: grandparent
    return (anchor.parentElement && anchor.parentElement.parentElement)
        || anchor.parentElement
        || anchor;
  }

  // ── 4. Identify the Share button ────────────────────────────────────────────
  //
  // Supported aria-label values:
  //   English : "Share"  (case-insensitive, icon characters stripped)
  //   Sinhala : "බෙදාගන්න"  (U+0DB6 U+0DD9 U+0DAF U+0DCF U+0D9C U+0DB1 U+0DCA U+0DB1)
  //             "Share"  written as "බෙදා ගන්න" (with space) also accepted
  //             "සලකුණු කරන්න" (Mark / tag — some locales map to share)

  var SHARE_SINHALA = [
    '\u0DB6\u0DD9\u0DAF\u0DCF\u0D9C\u0DB1\u0DCA\u0DB1',  // බෙදාගන්න
    '\u0DB6\u0DD9\u0DAF\u0DCF \u0D9C\u0DB1\u0DCA\u0DB1', // බෙදා ගන්න
    '\u0DC3\u0DBD\u0D9A\u0DD4\u0DAB\u0DD4 \u0D9A\u0DBB\u0DB1\u0DCA\u0DB1', // සලකුණු කරන්න
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
    var label    = el.getAttribute('aria-label') || '';
    var labelLC  = label.toLowerCase();

    // Sinhala labels (exact substring match, preserves Unicode)
    for (var s = 0; s < SHARE_SINHALA.length; s++) {
      if (labelLC.indexOf(SHARE_SINHALA[s]) !== -1) return true;
    }

    // English label after stripping icon glyphs
    if (stripIcons(label).indexOf('share') !== -1) return true;

    // Inner text exact match
    var innerText = (el.innerText || '').trim().toLowerCase();
    if (innerText === 'share') return true;

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
    // Search within container first
    var btns = container.querySelectorAll('[role="button"]');
    for (var i = 0; i < btns.length; i++) {
      if (isShareButton(btns[i]) && isVisible(btns[i])) return btns[i];
    }
    // Widen to full document
    var all = document.querySelectorAll('[role="button"]');
    for (var j = 0; j < all.length; j++) {
      if (isShareButton(all[j]) && isVisible(all[j])) return all[j];
    }
    return null;
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
        message: '"From your link" text not found. Make sure the post page is fully loaded.',
      };
    }

    var container = findContainer(anchor);
    var btn       = findShareButton(container);

    if (!btn) {
      return {
        status: 'failed',
        message: 'Share button not found in the post container.',
      };
    }

    highlightButton(btn);
    clickButton(btn);

    return {
      status:    'success',
      message:   'Share button located and clicked.',
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
