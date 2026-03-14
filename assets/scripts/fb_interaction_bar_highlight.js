/**
 * fb_interaction_bar_highlight.js  v1.0
 * ─────────────────────────────────────────────────────────────────────────────
 * Logic (exact approach from user):
 *   1. Find element containing "From your link" text.
 *   2. Walk up to nearest post container (article or parent chain).
 *   3. Inside that container, find button whose aria-label includes "share".
 *   4. Highlight that button's parent (interaction bar) — gold border + glow.
 *   5. Scroll it into view.
 *   6. Return JSON. NO clicks ever.
 * ─────────────────────────────────────────────────────────────────────────────
 */
(function () {
  'use strict';

  var TIMEOUT_MS   = 7000;
  var HIGHLIGHT_MS = 6000;

  // Strip PUA icon symbols before checking aria-label
  function stripIcons(s) {
    return (s || '')
      .replace(/[\uE000-\uF8FF]/g, '')
      .replace(/[\uDB80-\uDBFF][\uDC00-\uDFFF]/g, '')
      .replace(/[^\x00-\x7F]/g, '')
      .trim()
      .toLowerCase();
  }

  function labelHasShare(el) {
    return stripIcons(el.getAttribute('aria-label') || '').indexOf('share') !== -1;
  }

  // ── Step 1: Find "From your link" anchor ─────────────────────────────────────
  function findAnchor() {
    // span / div / a — exact approach from user
    var els = document.querySelectorAll('span, div, a');
    for (var i = 0; i < els.length; i++) {
      if (els[i].textContent.includes('From your link')) {
        return els[i];
      }
    }
    return null;
  }

  // ── Step 2: Post container ───────────────────────────────────────────────────
  function findPostContainer(anchor) {
    // Prefer nearest <article>, fall back to grandparent
    return anchor.closest('article') ||
           (anchor.parentElement && anchor.parentElement.parentElement) ||
           anchor.parentElement ||
           anchor;
  }

  // ── Step 3: Share button → interaction bar ───────────────────────────────────
  function findInteractionBar(container) {
    var btns = container.querySelectorAll('[role="button"], [aria-label]');
    for (var i = 0; i < btns.length; i++) {
      if (labelHasShare(btns[i])) {
        return btns[i].parentElement || btns[i];
      }
    }
    return null;
  }

  // ── Step 4: Highlight (gold border + glow) ───────────────────────────────────
  function highlight(bar) {
    bar.style.setProperty('border',        '4px solid #FFD700', 'important');
    bar.style.setProperty('border-radius', '8px',               'important');
    bar.style.setProperty('box-shadow',    '0 0 15px #FFD700',  'important');
    bar.style.setProperty('transition',    'all 0.5s ease',     'important');

    // Fixed overlay + badge (visible even inside overflow:hidden)
    var r = bar.getBoundingClientRect();
    var ov = document.createElement('div');
    ov.id = '__fbIBH_overlay';
    ov.style.cssText =
      'position:fixed;' +
      'top:'    + (Math.round(r.top)    - 4) + 'px;' +
      'left:'   + (Math.round(r.left)   - 4) + 'px;' +
      'width:'  + (Math.round(r.width)  + 8) + 'px;' +
      'height:' + (Math.round(r.height) + 8) + 'px;' +
      'border:4px solid #FFD700;' +
      'box-shadow:0 0 15px #FFD700;' +
      'background:rgba(255,215,0,0.08);' +
      'z-index:2147483647;pointer-events:none;' +
      'border-radius:8px;box-sizing:border-box;';

    var badge = document.createElement('div');
    badge.style.cssText =
      'position:absolute;top:-26px;left:0;' +
      'background:#B8860B;color:#fff;' +
      'font:bold 11px/1 sans-serif;' +
      'padding:3px 8px;border-radius:4px 4px 0 0;white-space:nowrap;';
    badge.textContent = '\u2705 Interaction bar detected';
    ov.appendChild(badge);
    document.body.appendChild(ov);

    // Step 5: Scroll into view
    bar.scrollIntoView({ behavior: 'smooth', block: 'center' });

    console.log('[fbIBH] Highlighted at: top=' + Math.round(r.top) +
      ' w=' + Math.round(r.width) + ' h=' + Math.round(r.height));

    // Auto-remove after HIGHLIGHT_MS
    setTimeout(function () {
      bar.style.removeProperty('border');
      bar.style.removeProperty('border-radius');
      bar.style.removeProperty('box-shadow');
      bar.style.removeProperty('transition');
      var o = document.getElementById('__fbIBH_overlay');
      if (o) o.remove();
    }, HIGHLIGHT_MS);
  }

  // ── Core attempt ─────────────────────────────────────────────────────────────
  function tryDetect() {
    var anchor = findAnchor();
    if (!anchor) return null;

    var container = findPostContainer(anchor);
    var bar       = findInteractionBar(container);

    // If not found in container, widen search to entire document
    if (!bar) {
      var allBtns = document.querySelectorAll('[role="button"], [aria-label]');
      for (var i = 0; i < allBtns.length; i++) {
        if (labelHasShare(allBtns[i])) {
          bar = allBtns[i].parentElement || allBtns[i];
          break;
        }
      }
    }

    return bar || null;
  }

  // ── Main Promise ──────────────────────────────────────────────────────────────
  window.__fbHighlightInteractionBar = function () {
    return new Promise(function (resolve) {
      var settled = false, observer = null, timer = null;

      function settle(result) {
        if (settled) return;
        settled = true;
        if (observer) { observer.disconnect(); observer = null; }
        if (timer)    { clearTimeout(timer);   timer    = null; }
        resolve(result);
      }

      var bar = tryDetect();
      if (bar) {
        highlight(bar);
        settle({ status: 'success', message: 'Interaction bar detected and highlighted' });
        return;
      }

      console.log('[fbIBH] Not found immediately — watching DOM...');

      observer = new MutationObserver(function () {
        if (settled) return;
        var late = tryDetect();
        if (!late) return;
        highlight(late);
        settle({ status: 'success', message: 'Interaction bar detected and highlighted' });
      });
      observer.observe(document.body, {
        childList: true, subtree: true, characterData: true,
        attributes: true, attributeFilter: ['aria-label', 'role'],
      });

      timer = setTimeout(function () {
        var anchor = findAnchor();
        settle(!anchor
          ? { status: 'failed', message: "Marker 'From your link' not found" }
          : { status: 'failed', message: 'Share button found but interaction bar missing' }
        );
      }, TIMEOUT_MS);
    });
  };

  return window.__fbHighlightInteractionBar().then(function (r) {
    return JSON.stringify(r);
  });

}());
