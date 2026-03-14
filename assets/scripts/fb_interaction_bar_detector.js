/**
 * fb_interaction_bar_detector.js  v1.0
 * ─────────────────────────────────────────────────────────────────────────────
 * Detects the interaction bar (Like / Comment / Share buttons) of the
 * "From your link" post on the Facebook mobile feed.
 *
 * Strategy — attribute-only, zero dynamic class names:
 *   1. Find "From your link" via text-node TreeWalker.
 *   2. From that anchor, walk the DOM (siblings + descendants) to find a
 *      container that holds role="button" elements whose aria-labels include
 *      "Like", "Comment", and "Share" (icon-stripped).
 *   3. Apply neon-green border + floating "Post Found" badge.
 *   4. Return JSON status to Flutter. STOP — no clicks ever.
 *
 * CONTRACT:
 *   NO  click(), dispatchEvent() for interaction, navigation.
 *   YES Read DOM, highlight, return result.
 * ─────────────────────────────────────────────────────────────────────────────
 */

(function () {
  'use strict';

  console.log('[fbIBD] v1.0 started');

  var TIMEOUT_MS   = 7000;
  var HIGHLIGHT_MS = 6000;

  // ── 1. "From your link" label search ────────────────────────────────────────
  var FROM_LINK_LABELS = [
    'from your link', 'from your shared link', 'linked post', 'from link',
    'ඔබේ සබැඳියෙන්', 'ඔබගේ සබැඳියෙන්', 'සබැඳියෙන්',
    'depuis votre lien', 'de votre lien',
    'aus deinem link',   'von deinem link',
    'desde tu enlace',   'do seu link',
  ];

  function normText(s) {
    return (s || '').replace(/\s+/g, ' ').trim().toLowerCase();
  }

  function isFromLinkText(raw) {
    var t = normText(raw);
    if (!t) return false;
    for (var i = 0; i < FROM_LINK_LABELS.length; i++) {
      if (t.indexOf(FROM_LINK_LABELS[i]) !== -1) return true;
    }
    return false;
  }

  function findFromLinkAnchor() {
    // Primary: text-node TreeWalker (finds deeply-nested plain text)
    var walker = document.createTreeWalker(
      document.body, NodeFilter.SHOW_TEXT, null, false);
    var node;
    while ((node = walker.nextNode())) {
      if (isFromLinkText(node.nodeValue)) {
        console.log('[fbIBD] Label found via text-node: "' +
          node.nodeValue.trim() + '"');
        return node.parentElement;
      }
    }
    // Fallback: aria-label attribute
    var ariaEls = document.querySelectorAll('[aria-label]');
    for (var j = 0; j < ariaEls.length; j++) {
      if (isFromLinkText(ariaEls[j].getAttribute('aria-label'))) {
        console.log('[fbIBD] Label found via aria-label');
        return ariaEls[j];
      }
    }
    return null;
  }

  // ── 2. aria-label normaliser (strips PUA / non-ASCII icon prefixes) ──────────
  function stripIcons(raw) {
    return (raw || '')
      .replace(/[\uE000-\uF8FF]/g, '')
      .replace(/[\uDB80-\uDBFF][\uDC00-\uDFFF]/g, '')
      .replace(/[^\x00-\x7F]/g, '')
      .trim()
      .toLowerCase();
  }

  function labelIncludes(el, word) {
    var raw = el.getAttribute('aria-label') || '';
    return stripIcons(raw).indexOf(word.toLowerCase()) !== -1;
  }

  // ── 3. Interaction bar detection ─────────────────────────────────────────────
  // A valid interaction bar is a container that holds role="button" elements
  // whose stripped aria-labels include ALL THREE of: "like", "comment", "share".
  function isInteractionBar(el) {
    var btns = el.querySelectorAll('[role="button"]');
    if (btns.length < 3) return false;

    var hasLike    = false;
    var hasComment = false;
    var hasShare   = false;

    for (var i = 0; i < btns.length; i++) {
      var b = btns[i];
      if (labelIncludes(b, 'like'))    hasLike    = true;
      if (labelIncludes(b, 'comment')) hasComment = true;
      if (labelIncludes(b, 'share'))   hasShare   = true;
      if (hasLike && hasComment && hasShare) return true;
    }
    return false;
  }

  /**
   * Given the "From your link" anchor element, search for the interaction bar:
   *
   *  Step A — Walk UP the DOM from anchor to body.
   *           At each ancestor, check ALL siblings and their descendants.
   *           This catches the bar even when it is a sibling of a parent,
   *           not a sibling of the anchor itself.
   *
   *  Step B — Direct descendants of the anchor's parent subtree.
   *
   *  Step C — Broad document sweep (last resort).
   */
  function findInteractionBar(anchor) {
    // Step A: walk up; at each level check siblings' subtrees
    var cur = anchor;
    while (cur && cur !== document.body) {
      var parent = cur.parentElement;
      if (!parent) break;

      // Check siblings of cur
      for (var i = 0; i < parent.children.length; i++) {
        var sib = parent.children[i];
        if (sib === cur) continue;
        // Sibling itself
        if (isInteractionBar(sib)) {
          console.log('[fbIBD] Bar found: sibling at depth ' +
            _depth(anchor, sib));
          return sib;
        }
        // Sibling's children
        var sibKids = sib.children;
        for (var k = 0; k < sibKids.length; k++) {
          if (isInteractionBar(sibKids[k])) {
            console.log('[fbIBD] Bar found: sibling child at depth ' +
              _depth(anchor, sibKids[k]));
            return sibKids[k];
          }
        }
      }
      // Also check cur itself (in case it wraps both label + bar)
      if (isInteractionBar(cur)) {
        console.log('[fbIBD] Bar found: ancestor contains bar');
        return cur;
      }
      cur = parent;
    }

    // Step B: descendants of anchor's grandparent
    var gp = anchor.parentElement && anchor.parentElement.parentElement;
    if (gp) {
      var allDesc = gp.querySelectorAll('*');
      for (var d = 0; d < allDesc.length; d++) {
        if (isInteractionBar(allDesc[d])) {
          console.log('[fbIBD] Bar found: grandparent descendant sweep');
          return allDesc[d];
        }
      }
    }

    // Step C: full document sweep
    var allEls = document.querySelectorAll('*');
    for (var z = 0; z < allEls.length; z++) {
      if (isInteractionBar(allEls[z])) {
        console.log('[fbIBD] Bar found: full document sweep');
        return allEls[z];
      }
    }

    return null;
  }

  function _depth(from, to) {
    var d = 0;
    var cur = to;
    while (cur && cur !== from && cur !== document.body) {
      d++; cur = cur.parentElement;
    }
    return d;
  }

  // ── 4. Highlight ─────────────────────────────────────────────────────────────
  var STYLE_ID = '__fbIBD_style';
  var HL_CLASS = '__fbIBD_hl';

  function highlight(bar) {
    // CSS class (survives React re-renders)
    if (!document.getElementById(STYLE_ID)) {
      var s = document.createElement('style');
      s.id = STYLE_ID;
      s.textContent = [
        '.' + HL_CLASS + ' {',
        '  outline: 4px solid #00FF00 !important;',
        '  outline-offset: 2px !important;',
        '  background: rgba(0,255,0,0.08) !important;',
        '  transition: none !important;',
        '}',
      ].join('\n');
      (document.head || document.documentElement).appendChild(s);
    }
    bar.classList.add(HL_CLASS);

    // Fixed overlay + "Post Found" badge
    var r = bar.getBoundingClientRect();
    var ov = document.createElement('div');
    ov.id = '__fbIBD_overlay';
    ov.style.cssText = [
      'position:fixed',
      'top:'    + Math.round(r.top    - 4) + 'px',
      'left:'   + Math.round(r.left   - 4) + 'px',
      'width:'  + Math.round(r.width  + 8) + 'px',
      'height:' + Math.round(r.height + 8) + 'px',
      'border:4px solid #00FF00',
      'background:rgba(0,255,0,0.07)',
      'z-index:2147483647',
      'pointer-events:none',
      'border-radius:8px',
      'box-sizing:border-box',
    ].join(';');

    // "Post Found" floating label
    var badge = document.createElement('div');
    badge.style.cssText = [
      'position:absolute',
      'top:-28px', 'left:0',
      'background:#00CC00',
      'color:#fff',
      'font:bold 12px/1 sans-serif',
      'padding:4px 10px',
      'border-radius:5px 5px 0 0',
      'white-space:nowrap',
      'letter-spacing:.3px',
    ].join(';');
    badge.textContent = '\u2705 Post Found \u2014 Interaction Bar';
    ov.appendChild(badge);
    document.body.appendChild(ov);

    console.log('[fbIBD] Highlight at rect: top=' + Math.round(r.top) +
      ' left=' + Math.round(r.left) +
      ' w=' + Math.round(r.width) +
      ' h=' + Math.round(r.height));

    setTimeout(function () {
      bar.classList.remove(HL_CLASS);
      var st = document.getElementById(STYLE_ID);
      if (st) st.remove();
      var overlay = document.getElementById('__fbIBD_overlay');
      if (overlay) overlay.remove();
    }, HIGHLIGHT_MS);
  }

  // ── 5. Detail extractor ──────────────────────────────────────────────────────
  function extractBarInfo(bar) {
    var btns = bar.querySelectorAll('[role="button"]');
    var btnLabels = [];
    for (var i = 0; i < btns.length; i++) {
      var lbl = btns[i].getAttribute('aria-label');
      if (lbl) btnLabels.push(lbl);
    }
    var r = bar.getBoundingClientRect();
    return {
      tagName:      bar.tagName.toLowerCase(),
      role:         bar.getAttribute('role') || null,
      id:           bar.id || null,
      ariaLabel:    bar.getAttribute('aria-label') || null,
      buttonCount:  btns.length,
      buttonLabels: btnLabels.slice(0, 6),
      boundingRect: {
        top:    Math.round(r.top),
        left:   Math.round(r.left),
        width:  Math.round(r.width),
        height: Math.round(r.height),
      },
    };
  }

  // ── 6. Result builders ───────────────────────────────────────────────────────
  function buildSuccess(bar) {
    var result = {
      status:  'success',
      message: 'Interaction bar identified by roles/labels',
      details: extractBarInfo(bar),
      detectedAt: Date.now(),
    };
    window.__fbIBDResult = result;
    try {
      window.chrome.webview.postMessage(JSON.stringify({
        type: 'FB_INTERACTION_BAR_DETECTED', payload: JSON.stringify(result),
      }));
    } catch (_) {}
    console.log('[fbIBD] SUCCESS');
    return result;
  }

  function buildFailure() {
    var result = { status: 'failed', detectedAt: Date.now() };
    window.__fbIBDResult = result;
    try {
      window.chrome.webview.postMessage(JSON.stringify({
        type: 'FB_INTERACTION_BAR_DETECTED', payload: JSON.stringify(result),
      }));
    } catch (_) {}
    console.log('[fbIBD] FAILED');
    return result;
  }

  // ── 7. Main Promise ──────────────────────────────────────────────────────────
  window.__fbDetectInteractionBar = function () {
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
        // ── STRICT STOP — no clicks, no navigation, nothing after this ──
      }

      function tryNow() {
        var anchor = findFromLinkAnchor();
        if (!anchor) return false;
        var bar = findInteractionBar(anchor);
        if (!bar) return false;
        highlight(bar);
        settle(buildSuccess(bar));
        return true;
      }

      // Immediate attempt
      if (tryNow()) return;

      console.log('[fbIBD] Not found immediately — watching DOM...');

      // MutationObserver for late-rendered content
      observer = new MutationObserver(function () {
        if (settled) return;
        tryNow();
      });
      observer.observe(document.body, {
        childList:     true,
        subtree:       true,
        characterData: true,
        attributes:    true,
        attributeFilter: ['role', 'aria-label'],
      });

      // Hard 7-second timeout
      timer = setTimeout(function () {
        settle(buildFailure());
      }, TIMEOUT_MS);
    });
  };

  // Return Promise → Flutter executeScript() captures JSON string
  return window.__fbDetectInteractionBar().then(function (r) {
    return JSON.stringify(r);
  });

}());
