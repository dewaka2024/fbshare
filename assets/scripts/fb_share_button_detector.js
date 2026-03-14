/**
 * fb_share_button_detector.js  v1.0
 * ─────────────────────────────────────────────────────────────────────────────
 * Detects the Share button on the Facebook mobile feed using the exact
 * CSS hierarchy: div.m > div.m.bg-s2 > div.m > div.m
 *
 * Matching criteria:
 *   - role="button"
 *   - aria-label contains "share" (case-insensitive, handles PUA icon prefix)
 *
 * On success:
 *   - Applies a 5px solid #00FF00 green border for visual confirmation.
 *   - Returns JSON: { status, message, details }
 *
 * CONTRACT — STRICTLY NO CLICK:
 *   NO  click(), dispatchEvent, focus() for interaction.
 *   YES Reads DOM, applies border, returns result. Stops immediately.
 * ─────────────────────────────────────────────────────────────────────────────
 */

(function () {
  'use strict';

  console.log('[fbSBD] v1.0 started');

  var TIMEOUT_MS   = 7000;
  var HIGHLIGHT_MS = 5000;

  // ── Highlight ────────────────────────────────────────────────────────────────
  var STYLE_ID = '__fbSBD_style';
  var HL_CLASS = '__fbSBD_hl';

  function applyHighlight(el) {
    if (!document.getElementById(STYLE_ID)) {
      var s = document.createElement('style');
      s.id = STYLE_ID;
      s.textContent = [
        '.' + HL_CLASS + ' {',
        '  outline: 5px solid #00FF00 !important;',
        '  outline-offset: 2px !important;',
        '  background: rgba(0,255,0,0.12) !important;',
        '  transition: none !important;',
        '}',
      ].join('\n');
      (document.head || document.documentElement).appendChild(s);
    }
    el.classList.add(HL_CLASS);

    // Fixed overlay so it's visible even inside overflow:hidden containers
    var r = el.getBoundingClientRect();
    var ov = document.createElement('div');
    ov.id = '__fbSBD_overlay';
    ov.style.cssText = [
      'position:fixed',
      'top:'    + Math.round(r.top    - 4) + 'px',
      'left:'   + Math.round(r.left   - 4) + 'px',
      'width:'  + Math.round(r.width  + 8) + 'px',
      'height:' + Math.round(r.height + 8) + 'px',
      'border:5px solid #00FF00',
      'background:rgba(0,255,0,0.10)',
      'z-index:2147483647',
      'pointer-events:none',
      'border-radius:6px',
      'box-sizing:border-box',
    ].join(';');

    // Badge
    var badge = document.createElement('div');
    badge.style.cssText = [
      'position:absolute',
      'top:-24px', 'left:0',
      'background:#00AA00',
      'color:#fff',
      'font-size:11px',
      'font-weight:bold',
      'padding:2px 8px',
      'border-radius:4px 4px 0 0',
      'white-space:nowrap',
    ].join(';');
    badge.textContent = '\u2713 Share button detected';
    ov.appendChild(badge);
    document.body.appendChild(ov);

    setTimeout(function () {
      el.classList.remove(HL_CLASS);
      var st = document.getElementById(STYLE_ID);
      if (st) st.remove();
      var overlay = document.getElementById('__fbSBD_overlay');
      if (overlay) overlay.remove();
    }, HIGHLIGHT_MS);

    console.log('[fbSBD] Highlight applied — rect: top=' +
      Math.round(r.top) + ' left=' + Math.round(r.left) +
      ' w=' + Math.round(r.width) + ' h=' + Math.round(r.height));
  }

  // ── Label matcher ────────────────────────────────────────────────────────────
  // aria-label may start with a Unicode PUA icon (e.g. 󰍺) before "share".
  // We strip all non-ASCII chars and check if "share" is present.
  function labelMatchesShare(raw) {
    if (!raw) return false;
    // Strip PUA / non-ASCII prefix, then check for "share"
    var cleaned = raw
      .replace(/[\uE000-\uF8FF]/g, '')           // BMP PUA
      .replace(/[\uDB80-\uDBFF][\uDC00-\uDFFF]/g, '') // Supplementary PUA
      .replace(/[^\x00-\x7F]/g, '')              // any other non-ASCII
      .trim()
      .toLowerCase();
    return cleaned.indexOf('share') !== -1;
  }

  // ── Core selector ────────────────────────────────────────────────────────────
  // Exact hierarchy: div.m > div.m.bg-s2 > div.m > div.m
  // Among matched elements find role="button" with share aria-label.
  // Returns the FIRST match (topmost in DOM = "From your link" post).
  function findShareButton() {
    // Primary: exact full hierarchy
    var candidates = document.querySelectorAll(
      'div.m > div.m.bg-s2 > div.m > div.m'
    );

    for (var i = 0; i < candidates.length; i++) {
      var el = candidates[i];
      if (el.getAttribute('role') !== 'button') continue;
      var lbl = el.getAttribute('aria-label') || '';
      if (labelMatchesShare(lbl)) {
        console.log('[fbSBD] Found via full hierarchy. aria-label="' + lbl + '"');
        return { el: el, strategy: 'full hierarchy: div.m > div.m.bg-s2 > div.m > div.m' };
      }
    }

    // Fallback A: relaxed — any div.m.bg-s2 descendant with role=button + share
    var relaxed = document.querySelectorAll('div.m.bg-s2 [role="button"]');
    for (var j = 0; j < relaxed.length; j++) {
      var rel = relaxed[j];
      var rlbl = rel.getAttribute('aria-label') || '';
      if (labelMatchesShare(rlbl)) {
        console.log('[fbSBD] Found via relaxed bg-s2 descendant. aria-label="' + rlbl + '"');
        return { el: rel, strategy: 'relaxed: div.m.bg-s2 descendant' };
      }
    }

    // Fallback B: any role=button with share label (broadest, still first match)
    var broad = document.querySelectorAll('[role="button"]');
    for (var k = 0; k < broad.length; k++) {
      var bel = broad[k];
      var blbl = bel.getAttribute('aria-label') || '';
      if (labelMatchesShare(blbl)) {
        console.log('[fbSBD] Found via broad role=button scan. aria-label="' + blbl + '"');
        return { el: bel, strategy: 'broad: first [role=button] with share aria-label' };
      }
    }

    return null;
  }

  // ── Detail extractor ─────────────────────────────────────────────────────────
  function extractDetails(el, strategy) {
    var r = el.getBoundingClientRect();
    return {
      strategy:      strategy,
      tagName:       el.tagName.toLowerCase(),
      role:          el.getAttribute('role') || null,
      ariaLabel:     el.getAttribute('aria-label') || null,
      className:     (typeof el.className === 'string')
                       ? el.className.trim().split(/\s+/).slice(0, 8).join(' ')
                       : null,
      id:            el.id || null,
      boundingRect: {
        top:    Math.round(r.top),
        left:   Math.round(r.left),
        width:  Math.round(r.width),
        height: Math.round(r.height),
      },
    };
  }

  // ── Result builders ──────────────────────────────────────────────────────────
  function buildSuccess(el, strategy) {
    var result = {
      status:  'success',
      message: 'Target post detected',
      details: 'Found via ' + strategy,
      element: extractDetails(el, strategy),
      detectedAt: Date.now(),
    };
    window.__fbShareBtnResult = result;
    try {
      window.chrome.webview.postMessage(JSON.stringify({
        type: 'FB_SHARE_BTN_DETECTED', payload: JSON.stringify(result),
      }));
    } catch (_) {}
    console.log('[fbSBD] SUCCESS — ' + strategy);
    return result;
  }

  function buildFailure() {
    var result = { status: 'failed', detectedAt: Date.now() };
    window.__fbShareBtnResult = result;
    try {
      window.chrome.webview.postMessage(JSON.stringify({
        type: 'FB_SHARE_BTN_DETECTED', payload: JSON.stringify(result),
      }));
    } catch (_) {}
    console.log('[fbSBD] FAILED — share button not found within ' + TIMEOUT_MS + 'ms');
    return result;
  }

  // ── Main Promise ─────────────────────────────────────────────────────────────
  window.__fbDetectShareButton = function () {
    return new Promise(function (resolve) {
      var settled  = false;
      var observer = null;
      var timer    = null;

      function settle(result) {
        if (settled) return;
        settled = true;
        if (observer) { observer.disconnect(); observer = null; }
        if (timer)    { clearTimeout(timer);   timer    = null; }
        resolve(result);
        // ── STRICT STOP — nothing runs after resolve() ──────────────────
      }

      // Immediate attempt
      var found = findShareButton();
      if (found) {
        applyHighlight(found.el);
        settle(buildSuccess(found.el, found.strategy));
        return;
      }

      console.log('[fbSBD] Not found immediately — watching DOM...');

      // MutationObserver for late-rendered feed content
      observer = new MutationObserver(function () {
        if (settled) return;
        var late = findShareButton();
        if (!late) return;
        applyHighlight(late.el);
        settle(buildSuccess(late.el, late.strategy));
      });

      observer.observe(document.body, {
        childList:     true,
        subtree:       true,
        attributes:    true,
        attributeFilter: ['role', 'aria-label', 'class'],
      });

      // Hard 7-second timeout
      timer = setTimeout(function () {
        settle(buildFailure());
      }, TIMEOUT_MS);
    });
  };

  // Return Promise — Flutter's executeScript() captures the resolved JSON string
  return window.__fbDetectShareButton().then(function (r) {
    return JSON.stringify(r);
  });

}());
