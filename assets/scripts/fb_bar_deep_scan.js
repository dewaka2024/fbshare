/**
 * fb_bar_deep_scan.js  v1.0
 * User-provided logic, cleaned up with:
 *  - MutationObserver + 7s timeout (late-render support)
 *  - Icon-strip for aria-label matching
 *  - Fixed overlay so highlight shows inside overflow:hidden
 *  - postMessage to Flutter
 *  - NO clicks ever
 */
(function () {
  'use strict';

  var TIMEOUT_MS   = 7000;
  var HIGHLIGHT_MS = 6000;

  // ── Step 1: Find marker (exact text match) ──────────────────────────────────
  function findMarker() {
    var els = document.querySelectorAll('div, span, p');
    for (var i = 0; i < els.length; i++) {
      if (els[i].textContent.trim() === 'From your link') return els[i];
    }
    return null;
  }

  // ── Step 2: Walk UP max 15 levels, look for share area ──────────────────────
  function findInteractionBar(anchor) {
    var current = anchor;
    for (var i = 0; i < 15; i++) {
      if (!current.parentElement) break;
      current = current.parentElement;

      // aria-label contains "share" (strip icons first)
      var shareBtn = null;
      var candidates = current.querySelectorAll('[aria-label]');
      for (var j = 0; j < candidates.length; j++) {
        var raw = (candidates[j].getAttribute('aria-label') || '')
          .replace(/[\uE000-\uF8FF]/g, '')
          .replace(/[\uDB80-\uDBFF][\uDC00-\uDFFF]/g, '')
          .replace(/[^\x00-\x7F]/g, '')
          .trim().toLowerCase();
        if (raw.indexOf('share') !== -1) { shareBtn = candidates[j]; break; }
      }

      // fallback: role="button" i or svg inside current
      if (!shareBtn) {
        shareBtn = current.querySelector('[role="button"] i') ||
                   current.querySelector('[role="button"] svg') ||
                   current.querySelector('svg');
      }

      if (shareBtn) {
        // Return the closest div — that's the interaction bar row
        return shareBtn.closest('div') || shareBtn.parentElement;
      }
    }
    return null;
  }

  // ── Step 3: Highlight ────────────────────────────────────────────────────────
  function highlight(bar) {
    bar.style.setProperty('outline',          '5px solid #FF0000', 'important');
    bar.style.setProperty('background-color', 'rgba(255,255,0,0.2)', 'important');

    // Fixed overlay (visible even inside overflow:hidden)
    var r = bar.getBoundingClientRect();
    var ov = document.createElement('div');
    ov.id = '__fbBDS_ov';
    ov.style.cssText =
      'position:fixed;' +
      'top:'    + (Math.round(r.top)    - 4) + 'px;' +
      'left:'   + (Math.round(r.left)   - 4) + 'px;' +
      'width:'  + (Math.round(r.width)  + 8) + 'px;' +
      'height:' + (Math.round(r.height) + 8) + 'px;' +
      'border:5px solid #FF0000;' +
      'background:rgba(255,255,0,0.15);' +
      'z-index:2147483647;pointer-events:none;' +
      'border-radius:6px;box-sizing:border-box;';
    var badge = document.createElement('div');
    badge.style.cssText =
      'position:absolute;top:-24px;left:0;' +
      'background:#CC0000;color:#fff;' +
      'font:bold 11px/1 sans-serif;' +
      'padding:3px 8px;border-radius:4px 4px 0 0;white-space:nowrap;';
    badge.textContent = '\u2705 Bar highlighted';
    ov.appendChild(badge);
    document.body.appendChild(ov);

    bar.scrollIntoView({ behavior: 'smooth', block: 'center' });

    setTimeout(function () {
      bar.style.removeProperty('outline');
      bar.style.removeProperty('background-color');
      var o = document.getElementById('__fbBDS_ov');
      if (o) o.remove();
    }, HIGHLIGHT_MS);
  }

  // ── Core ─────────────────────────────────────────────────────────────────────
  function tryDetect() {
    var marker = findMarker();
    if (!marker) return null;
    return findInteractionBar(marker);
  }

  // ── Main Promise ──────────────────────────────────────────────────────────────
  window.__fbBarDeepScan = function () {
    return new Promise(function (resolve) {
      var settled = false, observer = null, timer = null;

      function settle(r) {
        if (settled) return;
        settled = true;
        if (observer) { observer.disconnect(); observer = null; }
        if (timer)    { clearTimeout(timer);   timer    = null; }
        resolve(r);
      }

      // Immediate attempt
      var bar = tryDetect();
      if (bar) {
        highlight(bar);
        settle({ status: 'success', message: 'Bar highlighted' });
        return;
      }

      // MutationObserver for late-rendered content
      observer = new MutationObserver(function () {
        if (settled) return;
        var late = tryDetect();
        if (!late) return;
        highlight(late);
        settle({ status: 'success', message: 'Bar highlighted' });
      });
      observer.observe(document.body, {
        childList: true, subtree: true, characterData: true,
        attributes: true, attributeFilter: ['aria-label', 'role'],
      });

      // 7s timeout
      timer = setTimeout(function () {
        var m = findMarker();
        settle(!m
          ? { status: 'failed', message: 'Marker not found' }
          : { status: 'failed', message: 'Could not locate share area' });
      }, TIMEOUT_MS);
    });
  };

  return window.__fbBarDeepScan().then(function (r) {
    try {
      window.chrome.webview.postMessage(
        JSON.stringify({ type: 'FB_BAR_SCAN', payload: JSON.stringify(r) }));
    } catch (_) {}
    return JSON.stringify(r);
  });

}());
