/**
 * fb_post_isolate_only.js  v1.0
 * ─────────────────────────────────────────────────────────────────────────────
 * Shows ONLY the "From your link" post card on screen.
 * Hides everything else (feed, stories, header, banners).
 * NO clicks. NO navigation. Just visual isolation.
 * ─────────────────────────────────────────────────────────────────────────────
 */

(function () {
  'use strict';

  console.log('[fbPIO] v1.0 started');

  var TIMEOUT_MS = 7000;

  // ── Label matching ───────────────────────────────────────────────────────────
  var LABELS = [
    'from your link', 'from your shared link', 'linked post', 'from link',
    'ඔබේ සබැඳියෙන්', 'ඔබගේ සබැඳියෙන්', 'සබැඳියෙන්',
  ];

  function matchesLabel(text) {
    var t = (text || '').replace(/\s+/g, ' ').trim().toLowerCase();
    for (var i = 0; i < LABELS.length; i++) {
      if (t.indexOf(LABELS[i]) !== -1) return true;
    }
    return false;
  }

  // ── Find "From your link" label via text-node walk ───────────────────────────
  function findLabelNode() {
    var walker = document.createTreeWalker(
      document.body, NodeFilter.SHOW_TEXT, null, false);
    var node;
    while ((node = walker.nextNode())) {
      if (matchesLabel(node.nodeValue)) return node.parentElement;
    }
    // aria-label fallback
    var els = document.querySelectorAll('[aria-label]');
    for (var i = 0; i < els.length; i++) {
      if (matchesLabel(els[i].getAttribute('aria-label'))) return els[i];
    }
    return null;
  }

  // ── Find post card container ─────────────────────────────────────────────────
  function findPostCard(labelEl) {
    var tmp;

    // Pass 1: FeedUnit pagelet
    tmp = labelEl;
    while (tmp && tmp !== document.body) {
      if (/^FeedUnit/.test(tmp.getAttribute('data-pagelet') || '')) return tmp;
      tmp = tmp.parentElement;
    }
    // Pass 2: role="article"
    tmp = labelEl;
    while (tmp && tmp !== document.body) {
      if ((tmp.getAttribute('role') || '') === 'article' || tmp.tagName === 'ARTICLE') return tmp;
      tmp = tmp.parentElement;
    }
    // Pass 3: child of role="feed"
    tmp = labelEl;
    while (tmp && tmp !== document.body) {
      var p = tmp.parentElement;
      if (p && p.getAttribute('role') === 'feed') return tmp;
      tmp = p;
    }
    // Pass 4: height heuristic
    tmp = labelEl;
    while (tmp && tmp.parentElement && tmp.parentElement !== document.body) {
      if (tmp.offsetHeight >= 200 && tmp.parentElement.offsetHeight > tmp.offsetHeight * 1.3) return tmp;
      tmp = tmp.parentElement;
    }
    return labelEl.parentElement || labelEl;
  }

  // ── Hide everything EXCEPT the post card ────────────────────────────────────
  var _hidden = [];

  function hideEl(el) {
    if (!el || el.__fbPIOHidden) return;
    el.__fbPIOHidden = true;
    _hidden.push({ el: el, display: el.style.display });
    el.style.setProperty('display', 'none', 'important');
  }

  function isolateCard(card) {
    // Walk from card up to body — hide all siblings at each level
    var cur = card;
    while (cur && cur.parentElement && cur !== document.body) {
      var parent = cur.parentElement;
      for (var i = 0; i < parent.children.length; i++) {
        if (parent.children[i] !== cur) hideEl(parent.children[i]);
      }
      cur = parent;
    }

    // Hide "Open app" banner
    var banners = document.querySelectorAll(
      '[data-testid="open_app_banner"],[data-testid="msite-open-app-banner"],.smartbanner');
    for (var b = 0; b < banners.length; b++) hideEl(banners[b]);

    // Fixed/sticky elements near bottom (Open app button)
    var all = document.querySelectorAll('*');
    for (var k = 0; k < all.length; k++) {
      var el = all[k];
      try {
        var cs = window.getComputedStyle(el);
        if (cs.position !== 'fixed' && cs.position !== 'sticky') continue;
        var r = el.getBoundingClientRect();
        if (r.top < window.innerHeight * 0.5) continue;
        var txt = (el.innerText || '').toLowerCase();
        if (txt.indexOf('open') !== -1 || txt.indexOf('app') !== -1) hideEl(el);
      } catch (_) {}
    }

    // Style the card to be centered and clearly visible
    card.style.setProperty('position', 'relative', 'important');
    card.style.setProperty('z-index', '99999', 'important');
    card.style.setProperty('pointer-events', 'all', 'important');
    card.style.setProperty('margin', '0 auto', 'important');
    card.style.setProperty('background', '#fff', 'important');

    console.log('[fbPIO] Isolated. Hidden ' + _hidden.length + ' elements.');
  }

  // ── Restore (optional — call window.__fbPIORestore() to undo) ───────────────
  window.__fbPIORestore = function () {
    for (var i = 0; i < _hidden.length; i++) {
      var entry = _hidden[i];
      entry.el.style.display = entry.display;
      delete entry.el.__fbPIOHidden;
    }
    _hidden = [];
    console.log('[fbPIO] Restored.');
  };

  // ── Result builders ──────────────────────────────────────────────────────────
  function buildSuccess(card, labelEl) {
    var r = card.getBoundingClientRect();
    var result = {
      status:  'success',
      message: 'Post card isolated — all other elements hidden',
      details: {
        tagName:     card.tagName.toLowerCase(),
        id:          card.id || null,
        role:        card.getAttribute('role') || null,
        dataPagelet: card.getAttribute('data-pagelet') || null,
        labelText:   (labelEl.innerText || labelEl.textContent || '').trim().substring(0, 60),
        boundingRect: {
          top: Math.round(r.top), left: Math.round(r.left),
          width: Math.round(r.width), height: Math.round(r.height),
        },
        hiddenCount: _hidden.length,
      },
      detectedAt: Date.now(),
    };
    window.__fbPIOResult = result;
    try {
      window.chrome.webview.postMessage(JSON.stringify({
        type: 'FB_POST_ISOLATED', payload: JSON.stringify(result),
      }));
    } catch (_) {}
    console.log('[fbPIO] SUCCESS');
    return result;
  }

  function buildFailure(reason) {
    var result = { status: 'failed', message: reason, detectedAt: Date.now() };
    window.__fbPIOResult = result;
    console.log('[fbPIO] FAILED — ' + reason);
    return result;
  }

  // ── Main ─────────────────────────────────────────────────────────────────────
  window.__fbIsolatePostOnly = function () {
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
      }

      function tryNow() {
        var labelEl = findLabelNode();
        if (!labelEl) return false;
        var card = findPostCard(labelEl);
        isolateCard(card);
        settle(buildSuccess(card, labelEl));
        return true;
      }

      if (tryNow()) return;

      observer = new MutationObserver(function () {
        if (settled) return;
        tryNow();
      });
      observer.observe(document.body, {
        childList: true, subtree: true, characterData: true,
      });

      timer = setTimeout(function () {
        settle(buildFailure('"From your link" not found within ' + TIMEOUT_MS + 'ms'));
      }, TIMEOUT_MS);
    });
  };

  return window.__fbIsolatePostOnly().then(function (r) {
    return JSON.stringify(r);
  });

}());
