/**
 * fb_linked_post_detector.js  v3.0
 * ─────────────────────────────────────────────────────────────────────────────
 * FIXES over v2 (based on screenshot analysis):
 *
 *  1. "Open App" banner auto-hide — The blue "Open app" button at the bottom
 *     was covering the post container. We now hide it BEFORE scanning so the
 *     container rect is accurate and highlight is visible.
 *
 *  2. Script inject verification — Posts a console.log ping immediately on
 *     load so Flutter's WebView console listener confirms the script ran.
 *
 *  3. Highlight made more aggressive — Uses both outline AND a fixed position
 *     overlay div so it is visible even if the element is clipped by overflow.
 *
 *  4. Wider container detection — Added detection for the Share dialog's own
 *     internal post preview wrapper (not just feed FeedUnit / article).
 *
 *  5. Flutter postMessage channel — After detection, result is also sent via
 *     window.chrome.webview.postMessage() so Flutter can receive it as an
 *     event instead of only via executeScript return value.
 *
 * CONTRACT — READ-ONLY / DETECT-ONLY:
 *   YES  Hides "Open App" banner (cosmetic only, no navigation).
 *   YES  Scans DOM for "From your link" label via text-node walk.
 *   YES  Walks up to enclosing post container.
 *   YES  Highlights container with red border + overlay.
 *   YES  Returns JSON to Flutter via Promise AND postMessage.
 *   NO   click(), submit(), navigation — never.
 * ─────────────────────────────────────────────────────────────────────────────
 */

(function () {
  'use strict';

  // ── Inject verification ping ─────────────────────────────────────────────────
  // Flutter's WebView console listener will see this immediately confirming
  // the script was injected and started executing.
  console.log('[fbLPD] v3.0 script started');

  var TIMEOUT_MS   = 10000;
  var HIGHLIGHT_MS = 5000;

  var LABELS = [
    'from your link',
    'from your shared link',
    'linked post',
    'from link',
    // Sinhala
    '\u0d94\u0db6\u0dda \u0dc3\u0db6\u0dd0\u0ddc\u0daf\u0dd2\u0dba\u0dd9\u0db1\u0dca',
    '\u0d94\u0db6\u0d9c\u0dda \u0dc3\u0db6\u0dd0\u0ddc\u0daf\u0dd2\u0dba\u0dd9\u0db1\u0dca',
    '\u0dc3\u0db6\u0dd0\u0ddc\u0daf\u0dd2\u0dba\u0dd9\u0db1\u0dca',
    // French / German / Spanish / Portuguese
    'depuis votre lien', 'de votre lien',
    'aus deinem link',   'von deinem link',
    'desde tu enlace',   'do seu link',
  ];

  // ── 1. Hide "Open App" banner ────────────────────────────────────────────────
  // The banner sits at the bottom of the Share dialog and covers the post.
  // We hide it before scanning so container rects are accurate.
  function hideOpenAppBanner() {
    var hidden = 0;

    // Known selectors for the Facebook "Open App" smart banner
    var selectors = [
      '[data-testid="open_app_banner"]',
      '[data-testid="msite-open-app-banner"]',
      '.smartbanner', '#smartbanner',
    ];
    selectors.forEach(function (sel) {
      try {
        document.querySelectorAll(sel).forEach(function (el) {
          el.style.setProperty('display', 'none', 'important');
          hidden++;
        });
      } catch (_) {}
    });

    // Heuristic: any fixed/sticky element near the bottom whose text has "open app"
    var all = document.querySelectorAll('*');
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      try {
        var cs = window.getComputedStyle(el);
        if (cs.position !== 'fixed' && cs.position !== 'sticky') continue;
        var r = el.getBoundingClientRect();
        // Must be near bottom of viewport
        if (r.top < window.innerHeight * 0.6) continue;
        var txt = (el.innerText || el.textContent || '').toLowerCase();
        if (txt.indexOf('open') !== -1 && (txt.indexOf('app') !== -1 || txt.indexOf('facebook') !== -1)) {
          el.style.setProperty('display', 'none', 'important');
          hidden++;
        }
      } catch (_) {}
    }

    if (hidden > 0) console.log('[fbLPD] Hidden ' + hidden + ' "Open App" banner element(s)');
    return hidden;
  }

  // ── 2. Label matching ────────────────────────────────────────────────────────
  function norm(s) {
    return (s || '').replace(/\s+/g, ' ').trim().toLowerCase();
  }

  function matchesLabel(text) {
    var t = norm(text);
    if (!t) return false;
    for (var i = 0; i < LABELS.length; i++) {
      if (t.indexOf(LABELS[i]) !== -1) return true;
    }
    return false;
  }

  // ── 3. Label search — three strategies ──────────────────────────────────────
  function findLabelNode() {
    // Strategy A: aria-label attributes
    var ariaEls = document.querySelectorAll('[aria-label]');
    for (var i = 0; i < ariaEls.length; i++) {
      if (matchesLabel(ariaEls[i].getAttribute('aria-label'))) {
        console.log('[fbLPD] Found via aria-label');
        return ariaEls[i];
      }
    }

    // Strategy B: TreeWalker over TEXT NODES (deepest / most reliable)
    var walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
      null,
      false
    );
    var node;
    while ((node = walker.nextNode())) {
      if (matchesLabel(node.nodeValue)) {
        console.log('[fbLPD] Found via text-node walk: "' + node.nodeValue.trim() + '"');
        return node.parentElement;
      }
    }

    // Strategy C: innerText of small elements (span, div, h-tags)
    var smallEls = document.querySelectorAll('span,div,h1,h2,h3,h4,strong,b,p');
    for (var j = 0; j < smallEls.length; j++) {
      var el = smallEls[j];
      // Only check leaf-ish nodes (few children) to avoid false positives
      if (el.children.length > 4) continue;
      var txt = (el.innerText || el.textContent || '');
      // Must be short enough to be a label (not a whole post body)
      if (txt.length > 80) continue;
      if (matchesLabel(txt)) {
        console.log('[fbLPD] Found via innerText scan: "' + txt.trim() + '"');
        return el;
      }
    }

    return null;
  }

  // ── 4. Container detection ───────────────────────────────────────────────────
  function findContainer(labelEl) {
    var tmp;

    // Pass 1: FeedUnit pagelet
    tmp = labelEl;
    while (tmp && tmp !== document.body) {
      if (/^FeedUnit/.test(tmp.getAttribute('data-pagelet') || '')) {
        console.log('[fbLPD] Container found: FeedUnit pagelet');
        return tmp;
      }
      tmp = tmp.parentElement;
    }

    // Pass 2: role="article"
    tmp = labelEl;
    while (tmp && tmp !== document.body) {
      if ((tmp.getAttribute('role') || '') === 'article' || tmp.tagName === 'ARTICLE') {
        console.log('[fbLPD] Container found: role=article');
        return tmp;
      }
      tmp = tmp.parentElement;
    }

    // Pass 3: direct child of role="feed"
    tmp = labelEl;
    while (tmp && tmp !== document.body) {
      var p = tmp.parentElement;
      if (p && p.getAttribute('role') === 'feed') {
        console.log('[fbLPD] Container found: child of role=feed');
        return tmp;
      }
      tmp = p;
    }

    // Pass 4: Share dialog internal post preview
    // In the Share dialog, the post preview is usually a div with role="dialog"
    // or a direct child of the dialog. Walk up looking for role="dialog".
    tmp = labelEl;
    while (tmp && tmp !== document.body) {
      var pr = tmp.getAttribute('role') || '';
      if (pr === 'dialog' || pr === 'presentation') {
        // Return the first child of dialog that contains our label
        var children = tmp.children;
        for (var ci = 0; ci < children.length; ci++) {
          if (children[ci].contains(labelEl)) {
            console.log('[fbLPD] Container found: dialog child');
            return children[ci];
          }
        }
        console.log('[fbLPD] Container found: dialog itself');
        return tmp;
      }
      tmp = tmp.parentElement;
    }

    // Pass 5: Height heuristic — first ancestor ≥150px tall
    tmp = labelEl;
    while (tmp && tmp.parentElement && tmp.parentElement !== document.body) {
      var ch = tmp.offsetHeight;
      var ph = tmp.parentElement.offsetHeight;
      if (ch >= 150 && ph > ch * 1.3) {
        console.log('[fbLPD] Container found: height heuristic (' + ch + 'px)');
        return tmp;
      }
      tmp = tmp.parentElement;
    }

    // Pass 6: Any ancestor with stable id/data attribute
    tmp = labelEl;
    while (tmp && tmp !== document.body) {
      if (tmp.id || tmp.getAttribute('data-pagelet') || tmp.getAttribute('data-testid')) {
        console.log('[fbLPD] Container found: stable attr');
        return tmp;
      }
      tmp = tmp.parentElement;
    }

    console.log('[fbLPD] Container fallback: labelEl.parentElement');
    return labelEl.parentElement || labelEl;
  }

  // ── 5. Highlight — dual strategy ─────────────────────────────────────────────
  // Strategy A: CSS class with !important (survives React re-renders)
  // Strategy B: Fixed-position overlay div (visible even inside overflow:hidden)
  var STYLE_ID   = '__fbLPD_hl_style';
  var HL_CLASS   = '__fbLPD_hl';
  var OVERLAY_ID = '__fbLPD_overlay';

  function highlight(el) {
    // A: Injected <style>
    if (!document.getElementById(STYLE_ID)) {
      var s = document.createElement('style');
      s.id = STYLE_ID;
      s.textContent = [
        '.' + HL_CLASS + ' {',
        '  outline: 4px solid #FF0000 !important;',
        '  outline-offset: 2px !important;',
        '  background-color: rgba(255,0,0,0.10) !important;',
        '  box-shadow: inset 0 0 0 4px rgba(255,0,0,0.3),',
        '              0 0 0 6px rgba(255,0,0,0.15) !important;',
        '  transition: none !important;',
        '}',
      ].join('\n');
      (document.head || document.documentElement).appendChild(s);
    }
    el.classList.add(HL_CLASS);

    // B: Overlay div positioned over the element's bounding rect
    var r = el.getBoundingClientRect();
    var overlay = document.createElement('div');
    overlay.id = OVERLAY_ID;
    overlay.style.cssText = [
      'position:fixed',
      'top:'    + Math.round(r.top)    + 'px',
      'left:'   + Math.round(r.left)   + 'px',
      'width:'  + Math.round(r.width)  + 'px',
      'height:' + Math.round(r.height) + 'px',
      'border: 4px solid #FF0000',
      'background: rgba(255,0,0,0.07)',
      'z-index: 2147483647',
      'pointer-events: none',
      'box-sizing: border-box',
      'border-radius: 6px',
    ].join(';');
    document.body.appendChild(overlay);

    // Label badge
    var badge = document.createElement('div');
    badge.style.cssText = [
      'position:absolute',
      'top:-26px', 'left:0',
      'background:#FF0000',
      'color:#fff',
      'font-size:11px',
      'font-weight:bold',
      'padding:3px 8px',
      'border-radius:4px 4px 0 0',
      'white-space:nowrap',
      'pointer-events:none',
    ].join(';');
    badge.textContent = '\u2713 Post detected: From your link';
    overlay.appendChild(badge);

    console.log('[fbLPD] Highlight applied at rect: top=' + Math.round(r.top) +
      ' left=' + Math.round(r.left) + ' w=' + Math.round(r.width) + ' h=' + Math.round(r.height));

    // Auto-remove after HIGHLIGHT_MS
    setTimeout(function () {
      el.classList.remove(HL_CLASS);
      var st = document.getElementById(STYLE_ID);
      if (st) st.remove();
      var ov = document.getElementById(OVERLAY_ID);
      if (ov) ov.remove();
    }, HIGHLIGHT_MS);
  }

  // ── 6. Detail extractor ──────────────────────────────────────────────────────
  function extractDetails(el) {
    function selectorPath(node) {
      var parts = [];
      var cur = node;
      for (var d = 0; d < 5 && cur && cur !== document.body; d++) {
        var seg = cur.tagName.toLowerCase();
        if (cur.id) {
          seg += '#' + cur.id;
        } else if (cur.getAttribute('data-pagelet')) {
          seg += '[data-pagelet="' + cur.getAttribute('data-pagelet') + '"]';
        } else if (cur.getAttribute('role')) {
          seg += '[role="' + cur.getAttribute('role') + '"]';
        } else if (cur.className && typeof cur.className === 'string') {
          var cls = cur.className.trim().split(/\s+/).slice(0, 2).join('.');
          if (cls) seg += '.' + cls;
        }
        parts.unshift(seg);
        cur = cur.parentElement;
      }
      return parts.join(' > ');
    }

    var r = el.getBoundingClientRect();
    return {
      tagName:         el.tagName.toLowerCase(),
      id:              el.id || null,
      ariaLabelledBy:  el.getAttribute('aria-labelledby') || null,
      ariaLabel:       el.getAttribute('aria-label')      || null,
      role:            el.getAttribute('role')            || null,
      dataPagelet:     el.getAttribute('data-pagelet')    || null,
      dataTestId:      el.getAttribute('data-testid')     || null,
      classList:       (typeof el.className === 'string')
                         ? el.className.trim().split(/\s+/).slice(0, 6).join(' ')
                         : null,
      boundingRect: {
        top:    Math.round(r.top),
        left:   Math.round(r.left),
        width:  Math.round(r.width),
        height: Math.round(r.height),
      },
      innerTextPreview: (el.innerText || '').replace(/\s+/g, ' ').trim().substring(0, 150),
      selector:        selectorPath(el),
    };
  }

  // ── 7. Result builders ───────────────────────────────────────────────────────
  function buildSuccess(container, labelEl) {
    var result = {
      status:  'success',
      message: "Post detected under 'From your link'",
      details: extractDetails(container),
      labelElement: {
        tagName:   labelEl.tagName.toLowerCase(),
        text:      (labelEl.innerText || labelEl.textContent || '').trim(),
        ariaLabel: labelEl.getAttribute('aria-label') || null,
      },
      detectedAt: Date.now(),
    };
    window.__fbLinkedPostResult = result;

    // Also send via postMessage so Flutter event listener catches it
    try {
      window.chrome.webview.postMessage(JSON.stringify({
        type:    'FB_LINKED_POST_DETECTED',
        payload: JSON.stringify(result),
      }));
    } catch (_) {}

    console.log('[fbLPD] SUCCESS — container: ' + result.details.selector);
    return result;
  }

  function buildFailure(reason) {
    var result = {
      status:  'failed',
      message: 'Could not find the linked post',
      reason:  reason,
      detectedAt: Date.now(),
    };
    window.__fbLinkedPostResult = result;

    try {
      window.chrome.webview.postMessage(JSON.stringify({
        type:    'FB_LINKED_POST_DETECTED',
        payload: JSON.stringify(result),
      }));
    } catch (_) {}

    console.log('[fbLPD] FAILED — ' + reason);
    return result;
  }

  // ── 8. Core ──────────────────────────────────────────────────────────────────
  function tryDetect() {
    var labelEl = findLabelNode();
    if (!labelEl) return null;
    var container = findContainer(labelEl);
    return { labelEl: labelEl, container: container };
  }

  // ── 9. Main Promise ──────────────────────────────────────────────────────────
  window.__fbDetectLinkedPost = function () {
    // Hide the "Open App" banner first so it doesn't interfere with detection
    hideOpenAppBanner();

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

      // Immediate attempt
      var found = tryDetect();
      if (found) {
        highlight(found.container);
        settle(buildSuccess(found.container, found.labelEl));
        return;
      }

      console.log('[fbLPD] Label not found immediately — watching DOM...');

      // MutationObserver for late-rendered content
      observer = new MutationObserver(function () {
        if (settled) return;
        // Re-run banner hide on each mutation (banner may re-appear)
        hideOpenAppBanner();
        var late = tryDetect();
        if (!late) return;
        highlight(late.container);
        settle(buildSuccess(late.container, late.labelEl));
      });

      observer.observe(document.body, {
        childList:     true,
        subtree:       true,
        characterData: true,
        attributes:    true,
        attributeFilter: ['style', 'class', 'hidden', 'aria-hidden'],
      });

      // Hard 10-second timeout
      timer = setTimeout(function () {
        settle(buildFailure('"From your link" not found within ' + TIMEOUT_MS + ' ms.'));
      }, TIMEOUT_MS);
    });
  };

  // Return Promise — Flutter's executeScript() captures the resolved JSON string
  return window.__fbDetectLinkedPost().then(function (r) {
    return JSON.stringify(r);
  });

}());
