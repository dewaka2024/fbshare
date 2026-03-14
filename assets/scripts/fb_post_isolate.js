// ─────────────────────────────────────────────────────────────────────────────
// fb_post_isolate.js  v8
//
// Approach: "Surgical hide" — instead of hiding chrome elements by role/pagelet
// (which misses wrapper divs), we:
//   1. Find the post card via Share button anchor.
//   2. Hide EVERY sibling of EVERY ancestor of the post card all the way up
//      to <body>. This removes everything except the post's exact DOM path.
//   3. Give post card pointer-events:all; freeze body pointer-events:none.
//   4. When a [role="dialog"] appears, elevate it above the post card.
//
// This is the only reliable approach because Facebook's wrapper div structure
// is deeply nested and not identified by stable selectors.
//
// API:
//   window.__fbIsolatePost(postUrl?, timeoutMs?)  → Promise<r>
//   window.__fbRestorePost()
// ─────────────────────────────────────────────────────────────────────────────
(function () {
  if (window.__fbIsolateDefined) return;
  window.__fbIsolateDefined = true;

  // ── Helpers ────────────────────────────────────────────────────────────────

  function isVisible(el) {
    if (!el) return false;
    var r = el.getBoundingClientRect();
    return r.width > 0 || r.height > 0;
  }

  // Walk UP from el to find the outermost post card — prefer FeedUnit pagelet,
  // fall back to [role="article"]. Returns ONLY ONE result.
  function findPostCard(shareBtn) {
    // First pass: look for FeedUnit pagelet (most specific)
    var cur = shareBtn;
    while (cur && cur !== document.body) {
      if (/^FeedUnit/.test(cur.getAttribute('data-pagelet') || '')) return cur;
      cur = cur.parentElement;
    }
    // Second pass: [role="article"]
    cur = shareBtn;
    while (cur && cur !== document.body) {
      if (cur.getAttribute('role') === 'article' || cur.tagName === 'ARTICLE') return cur;
      cur = cur.parentElement;
    }
    // Third pass: direct child of [role="feed"]
    cur = shareBtn;
    while (cur && cur !== document.body) {
      var p = cur.parentElement;
      if (p && p.getAttribute('role') === 'feed') return cur;
      cur = p;
    }
    // Fourth pass: mobile view (no FeedUnit/article/feed roles)
    // Walk up from Share button — find the first ancestor tall enough
    // to be a post card (>200px) whose parent is even taller or is body.
    cur = shareBtn;
    while (cur && cur.parentElement && cur.parentElement !== document.body) {
      var ph = cur.parentElement.offsetHeight;
      var ch = cur.offsetHeight;
      // Post card: taller than 200px, and parent is significantly taller
      // (meaning cur is just one item in a list, not the whole page)
      if (ch > 200 && ph > ch * 1.5) return cur;
      cur = cur.parentElement;
    }
    // Last resort: largest ancestor under 90% of viewport height
    cur = shareBtn;
    var best = null;
    while (cur && cur !== document.body) {
      var h = cur.offsetHeight;
      if (h > 150 && h < window.innerHeight * 0.9) best = cur;
      cur = cur.parentElement;
    }
    return best;
  }

  var SHARE_ARIA = [
    'Send this to friends or post it on your profile.',
    'Send this to friends or post it on your profile',
    'share', 'Share', 'Share post', 'Share this post',
    '\u0db6\u0dd9\u0daf\u0dcf\u0d9c\u0db1\u0dca\u0db1',
    '\u0db6\u0dd9\u0daf\u0dcf \u0d9c\u0db1\u0dca\u0db1',
    'Partager', 'Teilen',
  ];

  function findFirstShareButton() {
    // 1. aria-label match (www.facebook.com)
    for (var i = 0; i < SHARE_ARIA.length; i++) {
      var els = document.querySelectorAll('[aria-label="' + SHARE_ARIA[i] + '"]');
      for (var j = 0; j < els.length; j++) {
        if (isVisible(els[j])) return els[j];
      }
    }
    // 2. m.facebook.com — Share appears as an <a> or button with text "Share"
    var SHARE_TEXT = ['Share', 'බෙදාගන්න', 'බෙදා ගන්න', 'Partager', 'Teilen'];
    var candidates = document.querySelectorAll('a[href],button,[role="button"]');
    for (var k = 0; k < candidates.length; k++) {
      var el = candidates[k];
      if (!isVisible(el)) continue;
      var txt = (el.innerText || el.textContent || '').trim();
      for (var t = 0; t < SHARE_TEXT.length; t++) {
        if (txt === SHARE_TEXT[t]) return el;
      }
    }
    return null;
  }

  // ── Surgical hide ──────────────────────────────────────────────────────────
  // Walk from postCard up to body. At each level, hide all siblings of the
  // current node. This leaves only the post card's exact ancestor chain visible.

  var _saved     = []; // { el, display }
  var _bodyPE    = '';
  var _postCard  = null;
  var _dialogEl  = null;
  var _isolated  = false;
  var _waitObs   = null;
  var _dialogObs = null;

  function hideEl(el) {
    if (!el || el.__fbHidden) return;
    el.__fbHidden = true;
    _saved.push({ el: el, display: el.style.display });
    el.style.display = 'none';
  }

  function surgicalHide(postCard) {
    // Walk from postCard up to body.
    // At every level, hide ALL siblings of the current node.
    // This is the only reliable way to remove the feed regardless of wrapper depth.
    // Dialogs are elevated via DLG_Z (999999) so they appear above everything.
    var cur = postCard;
    while (cur && cur.parentElement && cur !== document.body) {
      var parent = cur.parentElement;
      for (var i = 0; i < parent.children.length; i++) {
        var sib = parent.children[i];
        if (sib !== cur) hideEl(sib);
      }
      cur = parent;
    }
  }

  // ── Focus / pointer management ─────────────────────────────────────────────

  var POST_Z  = '99999';
  var DLG_Z   = '999999';

  function elevate(el, z) {
    if (!el) return;
    el.setAttribute('data-fbi-pz',  el.style.zIndex   || '');
    el.setAttribute('data-fbi-pp',  el.style.position || '');
    el.setAttribute('data-fbi-pe',  el.style.pointerEvents || '');
    if (!el.style.position || el.style.position === 'static') el.style.position = 'relative';
    el.style.zIndex        = z;
    el.style.pointerEvents = 'all';
  }

  function delevate(el) {
    if (!el) return;
    el.style.zIndex        = el.getAttribute('data-fbi-pz') || '';
    el.style.position      = el.getAttribute('data-fbi-pp') || '';
    el.style.pointerEvents = el.getAttribute('data-fbi-pe') || '';
    el.removeAttribute('data-fbi-pz');
    el.removeAttribute('data-fbi-pp');
    el.removeAttribute('data-fbi-pe');
  }

  // ── Dialog tracking ────────────────────────────────────────────────────────

  function getTopDialog() {
    // Find ANY visible dialog that is NOT the post card itself
    var dialogs = document.querySelectorAll(
      '[role="dialog"],[role="alertdialog"],[aria-modal="true"]'
    );
    var best = null, bestArea = 0;
    for (var i = 0; i < dialogs.length; i++) {
      var d = dialogs[i];
      if (!isVisible(d)) continue;
      if (d === _postCard || _postCard.contains(d)) continue; // skip if inside post
      // Pick dialog with largest area (most likely the foreground one)
      var r = d.getBoundingClientRect();
      var area = r.width * r.height;
      if (area > bestArea) { bestArea = area; best = d; }
    }
    return best;
  }

  function onDialogChange() {
    if (!_isolated) return;
    var dlg = getTopDialog();
    if (dlg && dlg !== _dialogEl) {
      // New dialog opened
      if (_dialogEl) delevate(_dialogEl);
      _dialogEl = dlg;
      elevate(_dialogEl, DLG_Z);
    } else if (!dlg && _dialogEl) {
      // Dialog closed
      delevate(_dialogEl);
      _dialogEl = null;
    }
  }

  // ── Core isolation ─────────────────────────────────────────────────────────

  function doIsolate(postCard, resolve) {
    _postCard = postCard;

    // Surgical hide — remove all siblings along the ancestor chain
    surgicalHide(postCard);

    // Freeze body pointer-events; elevate post card
    _bodyPE = document.body.style.pointerEvents;
    document.body.style.pointerEvents = 'none';
    elevate(postCard, POST_Z);
    postCard.setAttribute('data-fbi-z', '1'); // marker for getSearchScope()
    postCard.scrollIntoView({ behavior: 'smooth', block: 'center' });

    // Watch for dialogs
    _dialogObs = new MutationObserver(onDialogChange);
    _dialogObs.observe(document.body, { childList: true, subtree: true });

    if (typeof window.__fbRemoveCover === 'function') {
      window.__fbRemoveCover('\u2713 Post isolated');
    }

    _isolated = true;
    resolve({ success: true, hiddenCount: _saved.length, strategy: 'surgical-sibling-hide' });
  }

  // ── __fbIsolatePost ────────────────────────────────────────────────────────

  window.__fbIsolatePost = function (postUrl, timeoutMs) {
    if (_isolated) return Promise.resolve({ success: true, note: 'already isolated' });
    var waitMs = timeoutMs || 15000;

    return new Promise(function (resolve) {
      var settled = false;

      function tryNow() {
        var btn  = findFirstShareButton();
        if (!btn) return false;
        var card = findPostCard(btn);
        if (!card) return false;
        settled = true;
        if (_waitObs) { _waitObs.disconnect(); _waitObs = null; }
        doIsolate(card, resolve);
        return true;
      }

      if (tryNow()) return;

      _waitObs = new MutationObserver(function () {
        if (settled) { if (_waitObs) { _waitObs.disconnect(); _waitObs = null; } return; }
        tryNow();
      });
      _waitObs.observe(document.body, { childList: true, subtree: true });

      setTimeout(function () {
        if (settled) return;
        settled = true;
        if (_waitObs) { _waitObs.disconnect(); _waitObs = null; }
        if (typeof window.__fbRemoveCover === 'function') {
          window.__fbRemoveCover('\u26a0 Could not isolate');
        }
        resolve({ success: false, error: 'Share button not found after ' + waitMs + 'ms.' });
      }, waitMs);
    });
  };

  // ── __fbRestorePost ────────────────────────────────────────────────────────

  window.__fbRestorePost = function () {
    if (!_isolated) return;
    if (_dialogObs) { _dialogObs.disconnect(); _dialogObs = null; }
    if (_waitObs)   { _waitObs.disconnect();   _waitObs   = null; }

    // Restore all hidden elements
    for (var i = 0; i < _saved.length; i++) {
      _saved[i].el.style.display = _saved[i].display;
      delete _saved[i].el.__fbHidden;
    }
    _saved = [];

    // Restore body
    document.body.style.pointerEvents = _bodyPE;

    // Delevate dialog and post card
    if (_dialogEl) { delevate(_dialogEl); _dialogEl = null; }
    if (_postCard) {
      delevate(_postCard);
      _postCard.removeAttribute('data-fbi-z');
      _postCard = null;
    }

    _isolated = false;
  };

})();