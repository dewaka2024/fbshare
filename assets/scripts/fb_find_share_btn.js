/**
 * fb_find_share_btn.js  v1.0
 * Scans page top-to-bottom.
 * Finds the FIRST element where:
 *   - role="button"
 *   - aria-label includes "share" (case-insensitive, after stripping any icon symbols)
 * Highlights it with a green border.
 * NO clicks. Returns JSON to Flutter.
 */
(function () {
  'use strict';

  var TIMEOUT_MS   = 7000;
  var HIGHLIGHT_MS = 6000;

  // Strip any non-ASCII / PUA icon symbols, then check if "share" is included
  function ariaHasShare(el) {
    var raw = el.getAttribute('aria-label') || '';
    var cleaned = raw
      .replace(/[\uE000-\uF8FF]/g, '')               // BMP Private Use Area
      .replace(/[\uDB80-\uDBFF][\uDC00-\uDFFF]/g, '') // Supplementary PUA
      .replace(/[^\x00-\x7F]/g, '')                   // any remaining non-ASCII
      .toLowerCase()
      .trim();
    return cleaned.indexOf('share') !== -1;
  }

  // Find first matching element — querySelectorAll preserves DOM order (top→bottom)
  function findShareButton() {
    var all = document.querySelectorAll('[role="button"]');
    for (var i = 0; i < all.length; i++) {
      if (ariaHasShare(all[i])) return all[i];
    }
    return null;
  }

  // ── Highlight ─────────────────────────────────────────────────────────────
  function highlight(el) {
    // Injected <style> so React can't wipe it
    if (!document.getElementById('__fbFSB_style')) {
      var s = document.createElement('style');
      s.id = '__fbFSB_style';
      s.textContent =
        '.__fbFSB_hl{outline:4px solid #00FF00 !important;' +
        'outline-offset:2px !important;' +
        'background:rgba(0,255,0,0.10) !important;' +
        'transition:none !important;}';
      (document.head || document.documentElement).appendChild(s);
    }
    el.classList.add('__fbFSB_hl');

    // Fixed overlay so it shows even inside overflow:hidden
    var r = el.getBoundingClientRect();
    var ov = document.createElement('div');
    ov.id = '__fbFSB_overlay';
    ov.style.cssText =
      'position:fixed;' +
      'top:'    + (Math.round(r.top)    - 4) + 'px;' +
      'left:'   + (Math.round(r.left)   - 4) + 'px;' +
      'width:'  + (Math.round(r.width)  + 8) + 'px;' +
      'height:' + (Math.round(r.height) + 8) + 'px;' +
      'border:4px solid #00FF00;' +
      'background:rgba(0,255,0,0.07);' +
      'z-index:2147483647;pointer-events:none;' +
      'border-radius:6px;box-sizing:border-box;';

    var badge = document.createElement('div');
    badge.style.cssText =
      'position:absolute;top:-26px;left:0;' +
      'background:#00AA00;color:#fff;' +
      'font:bold 11px/1 sans-serif;' +
      'padding:3px 8px;border-radius:4px 4px 0 0;white-space:nowrap;';
    badge.textContent = '\u2705 Share button found';
    ov.appendChild(badge);
    document.body.appendChild(ov);

    setTimeout(function () {
      el.classList.remove('__fbFSB_hl');
      var st = document.getElementById('__fbFSB_style');
      if (st) st.remove();
      var o = document.getElementById('__fbFSB_overlay');
      if (o) o.remove();
    }, HIGHLIGHT_MS);

    console.log('[fbFSB] Highlighted: aria-label="' +
      (el.getAttribute('aria-label') || '') + '"');
  }

  // ── Result builders ───────────────────────────────────────────────────────
  function ok(el) {
    var r = el.getBoundingClientRect();
    var result = {
      status:   'success',
      message:  'Share button found',
      ariaLabel: el.getAttribute('aria-label') || '',
      boundingRect: {
        top: Math.round(r.top), left: Math.round(r.left),
        width: Math.round(r.width), height: Math.round(r.height),
      },
    };
    window.__fbFindShareResult = result;
    try { window.chrome.webview.postMessage(
      JSON.stringify({ type: 'FB_SHARE_BTN_FOUND', payload: JSON.stringify(result) }));
    } catch (_) {}
    return result;
  }

  function fail() {
    var result = { status: 'failed' };
    window.__fbFindShareResult = result;
    console.log('[fbFSB] FAILED — no share button found within ' + TIMEOUT_MS + 'ms');
    return result;
  }

  // ── Main ──────────────────────────────────────────────────────────────────
  window.__fbFindShareButton = function () {
    return new Promise(function (resolve) {
      var settled = false, observer = null, timer = null;

      function settle(result) {
        if (settled) return;
        settled = true;
        if (observer) { observer.disconnect(); observer = null; }
        if (timer)    { clearTimeout(timer);   timer    = null; }
        resolve(result);
      }

      var found = findShareButton();
      if (found) { highlight(found); settle(ok(found)); return; }

      console.log('[fbFSB] Not found yet — watching DOM...');

      observer = new MutationObserver(function () {
        if (settled) return;
        var late = findShareButton();
        if (!late) return;
        highlight(late);
        settle(ok(late));
      });
      observer.observe(document.body, {
        childList: true, subtree: true,
        attributes: true, attributeFilter: ['role', 'aria-label'],
      });

      timer = setTimeout(function () { settle(fail()); }, TIMEOUT_MS);
    });
  };

  return window.__fbFindShareButton().then(function (r) {
    return JSON.stringify(r);
  });

}());
