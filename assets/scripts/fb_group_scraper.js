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
    // Remove elements that have BOTH "fixed-container" AND "bottom" classes
    // — exactly matches class="m fixed-container bottom" (the Open app bar).
    document.querySelectorAll('.fixed-container.bottom').forEach(function(el) {
      try { el.parentNode && el.parentNode.removeChild(el); } catch(_) {}
    });
  }

  // ── Check if element is inside a fixed-container (banner) ─────────────────
  function isInsideBanner(el) {
    var node = el;
    while (node && node !== document.body) {
      if ((node.className||'').indexOf('fixed-container') !== -1) return true;
      node = node.parentElement;
    }
    return false;
  }

  // ── Count group rows ───────────────────────────────────────────────────────
  function countRows() {
    var n = 0;
    document.querySelectorAll('[data-mcomponent="MContainer"][tabindex="0"]')
      .forEach(function(el){
        if (el.querySelector('img') && !isInsideBanner(el)) n++;
      });
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

  // ── Progressive image cache — collect imageUrls DURING scroll ────────────
  // Facebook's React DOM recycles off-screen elements, so img.src is empty
  // by the time FINAL_DATA fires. We snapshot imageUrls on every scroll pass
  // and keep the best (longest/non-placeholder) URL per group name.
  var _imageCache = {}; // name -> imageUrl

  var _reportedNames = {}; // track already-reported groups

  function snapshotImages() {
    document.querySelectorAll('[data-mcomponent="MContainer"][tabindex="0"]')
      .forEach(function(el) {
        if (!el.querySelector('img')) return;
        if (isInsideBanner(el)) return;
        var name = extractName(el);
        if (!name) return;
        var src = (el.querySelector('img') || {}).src || '';
        if (src && src.indexOf('data:') !== 0 && src.length > 20) {
          if (!_imageCache[name] || src.length > _imageCache[name].length) {
            _imageCache[name] = src;
          }
        }
        // Stream each new group as it appears — post GROUP: message immediately
        if (!_reportedNames[name]) {
          _reportedNames[name] = true;
          var url = extractUrl(el);
          postMsg('GROUP:' + JSON.stringify({
            name:     name,
            imageUrl: _imageCache[name] || src,
            url:      url,
            index:    Object.keys(_reportedNames).length - 1
          }));
        }
      });
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
      snapshotImages(); // ← capture images while they're in the DOM

      var currentCount = countRows();
      postMsg('COUNT:' + currentCount);

      if (currentCount > lastCount) {
        lastCount = currentCount;
        retries   = 0;
        await sleep(500);
        scrollAll();
        await sleep(1500);
        snapshotImages(); // ← capture again after extra scroll
      } else {
        retries++;
        postMsg('RETRY:retry ' + retries + '/' + MAX_RETRIES + ', groups=' + currentCount);
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
        await sleep(1000);
        snapshotImages(); // ← capture on retry pass too
      }
    }

    // Final extraction — use cached imageUrls, fallback to live DOM
    var results = [];
    window.__foundGroups = [];
    var index = 0;
    document.querySelectorAll('[data-mcomponent="MContainer"][tabindex="0"]')
      .forEach(function(el) {
        if (!el.querySelector('img')) return;
        if (isInsideBanner(el)) return; // skip Open app banner
        var name = extractName(el);
        if (!name || SKIP_NAMES.test(name)) return;
        window.__foundGroups.push(el);
        var liveSrc = (el.querySelector('img') || {}).src || '';
        // Prefer cached URL (captured while element was in viewport)
        // over live DOM src which may be recycled/empty
        var bestImage = _imageCache[name] || '';
        if (!bestImage && liveSrc && liveSrc.indexOf('data:') !== 0) {
          bestImage = liveSrc;
        }
        results.push({
          name:     name,
          index:    index++,
          imageUrl: bestImage,
          url:      extractUrl(el)
        });
      });

    // ── Patch history API to catch SPA navigations ──────────────────────────
    // Facebook msite uses history.pushState() for client-side routing.
    // WebView2's url stream only fires on real navigations, NOT pushState.
    // We intercept pushState/replaceState and postMessage the new URL so
    // Dart can catch it on _webMessageStream with the NAV_URL: prefix.
    (function() {
      if (window.__fbHistoryPatched) return;
      window.__fbHistoryPatched = true;
      function wrapHistory(method) {
        var orig = history[method];
        history[method] = function(state, title, url) {
          var result = orig.apply(this, arguments);
          try {
            var fullUrl = url ? (url.startsWith('http') ? url : 'https://www.facebook.com' + url) : window.location.href;
            postMsg('NAV_URL:' + fullUrl);
          } catch(e) {}
          return result;
        };
      }
      wrapHistory('pushState');
      wrapHistory('replaceState');
      // Also catch popstate (back/forward)
      window.addEventListener('popstate', function() {
        try { postMsg('NAV_URL:' + window.location.href); } catch(e) {}
      });
    })();

    window.navigateToGroup = function(i) {
      var el = window.__foundGroups[i];
      if (!el) return false;
      el.scrollIntoView({behavior:'smooth',block:'center'});
      ['mousedown','mouseup','click'].forEach(function(t) {
        el.dispatchEvent(new MouseEvent(t,{bubbles:true,cancelable:true,view:window}));
      });
      // Also post current URL immediately after click as a fallback
      setTimeout(function() {
        try { postMsg('NAV_URL:' + window.location.href); } catch(e) {}
      }, 800);
      setTimeout(function() {
        try { postMsg('NAV_URL:' + window.location.href); } catch(e) {}
      }, 2500);
      return true;
    };

    postMsg('DONE:scroll complete — ' + results.length + ' groups extracted');
    postMsg('FINAL_DATA:' + JSON.stringify(results));
  }

  run().catch(function(e) {
    postMsg('DONE:scraper error — ' + String(e));
    postMsg('FINAL_DATA:' + JSON.stringify([]));
  });
})();
