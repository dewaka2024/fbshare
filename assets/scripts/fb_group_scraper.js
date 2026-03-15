/**
 * fb_group_scraper.js  v6.0  —  Index-based DOM approach
 * ─────────────────────────────────────────────────────────────────────────────
 * Layout: m.facebook.com/groups/ (mobile msite, Samsung Galaxy UA)
 *
 * DOM facts confirmed via DevTools:
 *   • Group list lives under:
 *       #screen-root > div > div:nth-child(3) > div:nth-child(4)
 *     Fallback: anywhere inside #screen-root
 *   • Every item: <div class="m" data-mcomponent="MContainer" tabindex="0">
 *   • Real groups contain:  <img> (thumbnail) + name text in a <span class="f2">
 *     or the first non-noise text node
 *   • Navigation items (Create, Sort, Discover) have NO <img> → easily excluded
 *
 * Approach:
 *   1. Locate the group list container.
 *   2. Collect all MContainer divs with tabindex="0" that contain an <img>.
 *   3. For each, extract name (first clean span/text) and imageUrl (img src).
 *   4. Store them in window.__foundGroups[] for later click()-based navigation.
 *   5. Expose window.navigateToGroup(index) which clicks the stored element.
 *   6. Return { status, groups: [{name, index, imageUrl}] } as a JSON string.
 *
 * Why click() instead of URL navigation:
 *   Facebook's msite stores navigation targets in an internal action-store
 *   keyed by data-action-id.  There is no extractable href.  Calling .click()
 *   on the original DOM element triggers Facebook's own router correctly.
 * ─────────────────────────────────────────────────────────────────────────────
 */
(function () {
  'use strict';

  // ── 0. Dismiss "Open App" overlay ────────────────────────────────────────────
  (function dismissBanners() {
    var UPSELL = /open\s*app|install|use\s+mobile\s+site|get\s+the\s+app/i;
    document.querySelectorAll(
      '[data-testid="msite-open-app-banner"],'  +
      '[data-testid="open_app_banner"],'        +
      '[data-testid="mobile-app-upsell"],'      +
      '.smartbanner,#smartbanner'
    ).forEach(function (el) {
      el.style.setProperty('display', 'none', 'important');
    });
    // Fixed/sticky upsell sheets (the blue "Open App" bar at the bottom)
    document.querySelectorAll('div,a,section').forEach(function (el) {
      try {
        var pos = window.getComputedStyle(el).position;
        if (pos !== 'fixed' && pos !== 'sticky') return;
        if (UPSELL.test(el.innerText || '')) {
          el.style.setProperty('display', 'none', 'important');
        }
      } catch (_) {}
    });
  })();

  // ── 1. Locate group list container ───────────────────────────────────────────
  var container = (
    document.querySelector('#screen-root > div > div:nth-child(3) > div:nth-child(4)') ||
    document.querySelector('#screen-root') ||
    document.body
  );

  // ── 2. Noise filter for group names ──────────────────────────────────────────
  var SKIP_NAMES = /^(create\s+(a\s+)?group|sort|discover|posts?|invitations?|your\s+groups?|groups?)$/i;
  var NOISE_LINE = /^\d+\+?\s+(new\s+)?posts?$|^updated\s+\d|^new\s+activity$|^\d+$|^•$/i;

  function extractName(el) {
    // Priority 1: span with class containing "f2" (Facebook's bold text class)
    var f2 = el.querySelector('span[class*="f2"], span._5wj-');
    if (f2) {
      var t = (f2.innerText || '').trim();
      if (t.length >= 2 && !NOISE_LINE.test(t)) return t;
    }

    // Priority 2: aria-label on the element itself
    var lbl = (el.getAttribute('aria-label') || '').trim();
    if (lbl.length >= 2 && !SKIP_NAMES.test(lbl)) return lbl;

    // Priority 3: walk all spans, pick first clean non-noise line
    var spans = el.querySelectorAll('span, div');
    for (var i = 0; i < spans.length; i++) {
      // Only leaf-level text nodes (no children with text of their own)
      if (spans[i].children.length > 0) continue;
      var line = (spans[i].innerText || '').trim();
      if (line.length >= 2 && !NOISE_LINE.test(line) && !SKIP_NAMES.test(line)) {
        return line;
      }
    }

    // Priority 4: raw innerText first clean line
    var raw = (el.innerText || '').trim().split('\n');
    for (var j = 0; j < raw.length; j++) {
      var r = raw[j].trim();
      if (r.length >= 2 && !NOISE_LINE.test(r) && !SKIP_NAMES.test(r)) return r;
    }

    return '';
  }

  // ── 3. Collect group rows ─────────────────────────────────────────────────────
  var candidates = container.querySelectorAll(
    '[data-mcomponent="MContainer"][tabindex="0"]'
  );

  window.__foundGroups = [];  // reset global index store
  var groups = [];

  for (var i = 0; i < candidates.length; i++) {
    var el = candidates[i];

    // CRITICAL filter: must contain an <img> (navigation rows don't have images)
    var img = el.querySelector('img');
    if (!img) continue;

    var name = extractName(el);
    if (!name || SKIP_NAMES.test(name)) continue;

    var imageUrl = img.getAttribute('src') || '';

    var idx = window.__foundGroups.length;
    window.__foundGroups.push(el);

    groups.push({
      name:     name,
      index:    idx,
      imageUrl: imageUrl,
    });
  }

  // ── 4. Expose navigation function ─────────────────────────────────────────────
  //
  // Called by Flutter via executeScript('window.navigateToGroup(N)') after the
  // user taps a group in the sidebar.  Simulates a full human-like click so
  // Facebook's msite router handles the navigation correctly.
  //
  window.navigateToGroup = function (index) {
    var el = window.__foundGroups[index];
    if (!el) return false;
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    // Full event sequence: mousedown → mouseup → click
    ['mousedown', 'mouseup', 'click'].forEach(function (type) {
      el.dispatchEvent(new MouseEvent(type, {
        bubbles: true, cancelable: true, view: window
      }));
    });
    el.focus();
    el.click();
    return true;
  };

  // ── 5. Return ─────────────────────────────────────────────────────────────────

  if (groups.length > 0) {
    return JSON.stringify({ status: 'success', groups: groups });
  }

  // Diagnostic payload when empty
  var diagCandidates = container.querySelectorAll('[data-mcomponent="MContainer"]').length;
  var diagTabindex   = container.querySelectorAll('[data-mcomponent="MContainer"][tabindex="0"]').length;
  var diagWithImg    = 0;
  container.querySelectorAll('[data-mcomponent="MContainer"][tabindex="0"]').forEach(function(el){
    if (el.querySelector('img')) diagWithImg++;
  });

  return JSON.stringify({
    status: 'empty',
    groups: [],
    message: 'No groups found.',
    debug: {
      containerFound: container !== document.body,
      mContainers:    diagCandidates,
      withTabindex:   diagTabindex,
      withImg:        diagWithImg,
      url:            window.location.href,
    }
  });

}());
