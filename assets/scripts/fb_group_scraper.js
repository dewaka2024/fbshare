/**
 * fb_group_scraper.js  v9.0  — Debug-first approach
 * Posts detailed diagnostic info so we can see exactly what the DOM looks like
 * and which scroll container is being found.
 */
(function () {
  'use strict';

  if (window.__fbScrollScraper) return;
  window.__fbScrollScraper = true;

  var SCROLL_PAUSE_MS = 3000;
  var RETRY_PAUSE_MS  = 3000;
  var MAX_RETRIES     = 4;

  var SKIP_NAMES = /^(create\s+(a\s+)?group|sort|discover|posts?|invitations?|your\s+groups?|groups?|find\s+new\s+groups?|suggested\s+groups?)$/i;
  var NOISE_LINE = /^\d+\+?\s+(new\s+)?posts?$|^updated\s+\d|^new\s+activity$|^\d+$|^•$/i;

  function postMsg(msg) {
    try { window.chrome.webview.postMessage(msg); } catch (e) {
      try { window.Toaster.postMessage(msg); } catch (_) {}
    }
  }

  function sleep(ms) {
    return new Promise(function (r) { setTimeout(r, ms); });
  }

  function dismissBanners() {
    var UPSELL = /open\s*app|install|use\s+mobile/i;
    document.querySelectorAll(
      '[data-testid="msite-open-app-banner"],[data-testid="open_app_banner"],.smartbanner,#smartbanner'
    ).forEach(function (el) { el.style.setProperty('display','none','important'); });
    document.querySelectorAll('div,a,section,footer').forEach(function (el) {
      try {
        var pos = window.getComputedStyle(el).position;
        if (pos !== 'fixed' && pos !== 'sticky') return;
        if (UPSELL.test(el.innerText||'')) el.style.setProperty('display','none','important');
      } catch(_) {}
    });
  }

  // ── Count group rows ───────────────────────────────────────────────────────
  function countRows() {
    var n = 0;
    document.querySelectorAll('[data-mcomponent="MContainer"][tabindex="0"]')
      .forEach(function(el){ if(el.querySelector('img')) n++; });
    return n;
  }

  // ── Find ALL scrollable elements in the page ───────────────────────────────
  // Instead of guessing one container, we scroll ALL of them.
  function getAllScrollables() {
    var result = [];
    var all = document.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      try {
        var st = window.getComputedStyle(el);
        var ov = st.overflowY;
        if ((ov === 'scroll' || ov === 'auto') && el.scrollHeight > el.clientHeight + 20) {
          result.push(el);
        }
      } catch(_) {}
    }
    // Always include documentElement and body
    result.push(document.documentElement);
    result.push(document.body);
    return result;
  }

  // ── Scroll everything ──────────────────────────────────────────────────────
  function scrollAll() {
    var containers = getAllScrollables();
    containers.forEach(function(el) {
      try {
        el.scrollTop = el.scrollHeight;
        el.dispatchEvent(new Event('scroll', { bubbles: true }));
      } catch(_) {}
    });

    // window-level scroll
    window.scrollTo(0, 99999999);
    window.dispatchEvent(new Event('scroll'));

    // Simulate wheel event on body and document
    [document.body, document.documentElement].forEach(function(el) {
      try {
        el.dispatchEvent(new WheelEvent('wheel', {
          bubbles: true, cancelable: true,
          deltaY: 1000, deltaMode: 0
        }));
      } catch(_) {}
    });

    // Also try scrollBy on window
    window.scrollBy(0, 99999);
  }

  // ── Extract name ───────────────────────────────────────────────────────────
  function extractName(el) {
    var f2 = el.querySelector('span[class*="f2"],span._5wj-');
    if (f2) {
      var t = (f2.innerText||'').trim();
      if (t.length >= 2 && !NOISE_LINE.test(t) && !SKIP_NAMES.test(t)) return t;
    }
    var lbl = (el.getAttribute('aria-label')||'').trim();
    if (lbl.length >= 2 && !SKIP_NAMES.test(lbl)) return lbl;
    var spans = el.querySelectorAll('span,div');
    for (var i = 0; i < spans.length; i++) {
      var raw = (spans[i].innerText||'').trim();
      var first = raw.split('\n')[0].trim();
      if (first.length >= 2 && !NOISE_LINE.test(first) && !SKIP_NAMES.test(first)) return first;
    }
    return null;
  }

  // ── Extract URL ────────────────────────────────────────────────────────────
  function extractUrl(el) {
    var anchors = el.querySelectorAll('a[href]');
    for (var i = 0; i < anchors.length; i++) {
      var href = anchors[i].getAttribute('href')||'';
      if (/\/groups\/[^?#/]+/.test(href)) {
        return href.startsWith('http')
          ? href.split('?')[0]
          : 'https://www.facebook.com' + href.split('?')[0];
      }
    }
    return '';
  }

  // ── Main loop ──────────────────────────────────────────────────────────────
  async function run() {
    dismissBanners();
    await sleep(2000);

    // POST diagnostic info about what scrollables exist
    var scrollables = getAllScrollables();
    var diagInfo = scrollables.map(function(el) {
      return (el.tagName || 'unknown') + 
             '[' + (el.id || el.getAttribute('data-mcomponent') || el.className.split(' ')[0] || '') + ']' +
             ' sh=' + el.scrollHeight + ' ch=' + el.clientHeight;
    }).join(' | ');
    postMsg('COUNT:' + countRows() + ' DBG:' + diagInfo.substring(0, 200));

    var lastCount = 0;
    var retries   = 0;

    while (true) {
      scrollAll();
      await sleep(SCROLL_PAUSE_MS);
      dismissBanners();

      var currentCount = countRows();
      postMsg('COUNT:' + currentCount);

      if (currentCount > lastCount) {
        lastCount = currentCount;
        retries   = 0;
        await sleep(500);
        scrollAll();
        await sleep(1500);
      } else {
        retries++;
        if (retries >= MAX_RETRIES) break;
        postMsg('COUNT:' + currentCount);
        await sleep(RETRY_PAUSE_MS);
        // Scroll up slightly then back down to re-trigger observers
        getAllScrollables().forEach(function(el) {
          try { el.scrollTop = Math.max(0, el.scrollTop - 400); } catch(_) {}
        });
        window.scrollBy(0, -400);
        await sleep(600);
        scrollAll();
      }
    }

    // Final extraction
    var results = [];
    window.__foundGroups = [];
    var index = 0;
    document.querySelectorAll('[data-mcomponent="MContainer"][tabindex="0"]')
      .forEach(function(el) {
        if (!el.querySelector('img')) return;
        var name = extractName(el);
        if (!name || SKIP_NAMES.test(name)) return;
        window.__foundGroups.push(el);
        results.push({
          name:     name,
          index:    index++,
          imageUrl: (el.querySelector('img')||{}).src || '',
          url:      extractUrl(el)
        });
      });

    window.navigateToGroup = function(i) {
      var el = window.__foundGroups[i];
      if (!el) return false;
      el.scrollIntoView({behavior:'smooth',block:'center'});
      ['mousedown','mouseup','click'].forEach(function(t) {
        el.dispatchEvent(new MouseEvent(t,{bubbles:true,cancelable:true,view:window}));
      });
      return true;
    };

    postMsg('FINAL_DATA:' + JSON.stringify(results));
  }

  run().catch(function(e) {
    postMsg('FINAL_DATA:' + JSON.stringify([]));
  });
})();
