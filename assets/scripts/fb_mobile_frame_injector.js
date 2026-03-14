/**
 * fb_mobile_frame_injector.js
 * ─────────────────────────────────────────────────────────────────────────────
 * Injected via Flutter WebView2 executeScript().
 *
 * What this does:
 *  1. Visual Transform  — wraps the active Facebook content in a 380×750
 *     "phone frame", centres it on a dark background, hides all desktop chrome.
 *  2. Font / Icon Fix   — forces Segoe UI Historic / Segoe UI Symbol so that
 *     Unicode PUA icons (e.g. 󰍺) render as glyphs instead of □□□.
 *  3. Smart Label Match — strips non-ASCII icon characters from aria-labels
 *     before matching against FbStrings (shareExact, shareToGroupExact, postExact).
 *  4. Pointer Guard     — disables clicks on the dark backdrop; only the phone
 *     frame receives pointer events.
 *
 * Guard: calling this twice in the same page is safe — the script is idempotent.
 * ─────────────────────────────────────────────────────────────────────────────
 */

(function () {
  'use strict';

  // ── 0. Idempotency guard ────────────────────────────────────────────────────
  if (window.__fbMobileFrameInjected) return;
  window.__fbMobileFrameInjected = true;

  // ══════════════════════════════════════════════════════════════════════════
  // 1.  FONT & ICON FIX
  //     Injects a <style> tag that forces Segoe UI Historic / Segoe UI Symbol
  //     globally so Facebook's PUA icon glyphs (Share arrow, etc.) render
  //     correctly on Windows instead of showing empty squares.
  // ══════════════════════════════════════════════════════════════════════════

  (function injectFontFix() {
    if (document.getElementById('__fbFontFix')) return;
    const style = document.createElement('style');
    style.id = '__fbFontFix';
    style.textContent = `
      /* ── Icon / Font Fix ─────────────────────────────────────────────── */
      * {
        font-family: "Segoe UI Historic", "Segoe UI Symbol",
                     "Segoe UI", Arial, sans-serif !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  })();

  // ══════════════════════════════════════════════════════════════════════════
  // 2.  VISUAL TRANSFORM — Mobile Phone Frame
  //     • Hides desktop nav, sidebars, footer
  //     • Wraps page content in a 380×750 rounded container
  //     • Sets dark body background
  //     • Disables backdrop pointer events, re-enables inside the frame
  // ══════════════════════════════════════════════════════════════════════════

  (function injectMobileFrame() {
    if (document.getElementById('__fbMobileFrameStyle')) return;

    // ── 2a. Global layout CSS ──────────────────────────────────────────────
    const style = document.createElement('style');
    style.id = '__fbMobileFrameStyle';
    style.textContent = `
      /* ── Dark backdrop ───────────────────────────────────────────────── */
      html, body {
        background: #0f1117 !important;
        margin: 0 !important;
        padding: 0 !important;
        overflow: hidden !important;
        /* Block all backdrop clicks */
        pointer-events: none !important;
      }

      /* ── Hide desktop chrome ─────────────────────────────────────────── */

      /* Top navigation bar */
      [role="banner"],
      [data-pagelet="MWebHeaderTopBar"],
      [data-pagelet="NavBar"],
      [data-pagelet="LeftRail"],
      [data-pagelet="RightRail"],
      [data-pagelet="Stories"],
      [data-pagelet="Header"],
      [aria-label="Facebook"],
      nav[aria-label],
      .x1n2onr6.xh8yej3,           /* common FB nav wrapper class */
      .x78zum5.xdt5ytf.x1t2pt76,   /* left sidebar */
      header,
      footer {
        display: none !important;
      }

      /* ── Phone frame container ───────────────────────────────────────── */
      #__fbMobileFrame {
        position: fixed !important;
        top:  50% !important;
        left: 50% !important;
        transform: translate(-50%, -50%) !important;
        width:  380px !important;
        height: 750px !important;
        border-radius: 25px !important;
        overflow: hidden !important;
        box-shadow:
          0 0  0  1px rgba(255,255,255,0.06),
          0 8px 32px rgba(0,0,0,0.7),
          0 24px 64px rgba(0,0,0,0.5) !important;
        background: #fff !important;
        z-index: 2147483640 !important;
        /* Re-enable clicks inside the frame */
        pointer-events: auto !important;
      }

      /* ── Scrollable inner area ───────────────────────────────────────── */
      #__fbMobileFrame > * {
        pointer-events: auto !important;
      }
      #__fbMobileFrameScroll {
        width:   100% !important;
        height:  100% !important;
        overflow-y: auto !important;
        overflow-x: hidden !important;
        -webkit-overflow-scrolling: touch !important;
      }

      /* ── Phone notch decoration (cosmetic only) ──────────────────────── */
      #__fbMobileNotch {
        position: absolute !important;
        top: 10px !important;
        left: 50% !important;
        transform: translateX(-50%) !important;
        width: 80px !important;
        height: 6px !important;
        background: rgba(0,0,0,0.15) !important;
        border-radius: 3px !important;
        z-index: 2147483641 !important;
        pointer-events: none !important;
      }

      /* ── Dialogs / modals: keep inside frame ─────────────────────────── */
      [role="dialog"],
      [aria-modal="true"],
      [role="alertdialog"] {
        position: fixed !important;
        max-width: 380px !important;
        max-height: 750px !important;
        overflow-y: auto !important;
        pointer-events: auto !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);

    // ── 2b. Build the phone frame DOM ──────────────────────────────────────
    //        We move the document <body>'s children into a scrollable div
    //        inside the frame, rather than reparenting <body> itself, so that
    //        Facebook's event listeners (attached to body children) keep working.

    function buildFrame() {
      if (document.getElementById('__fbMobileFrame')) return; // already built

      const frame = document.createElement('div');
      frame.id = '__fbMobileFrame';

      const notch = document.createElement('div');
      notch.id = '__fbMobileNotch';

      const scroll = document.createElement('div');
      scroll.id = '__fbMobileFrameScroll';

      // Move existing body children into the scroll wrapper
      while (document.body.firstChild) {
        scroll.appendChild(document.body.firstChild);
      }

      frame.appendChild(notch);
      frame.appendChild(scroll);
      document.body.appendChild(frame);
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', buildFrame, { once: true });
    } else {
      buildFrame();
    }
  })();

  // ══════════════════════════════════════════════════════════════════════════
  // 3.  SMART LABEL MATCHING  (window.__fbCleanMatch)
  //
  //     Strips non-ASCII / PUA icon characters from aria-labels before
  //     comparing with FbStrings lists.  Call this helper from your
  //     automation scripts instead of raw string equality.
  //
  //     Usage:
  //       const btn = window.__fbCleanMatch(scope, 'share');
  //       const btn = window.__fbCleanMatch(scope, 'group');
  //       const btn = window.__fbCleanMatch(scope, 'post');
  //
  //     Returns the first matching Element, or null.
  // ══════════════════════════════════════════════════════════════════════════

  // ── 3a. FbStrings label lists (mirrors fb_strings.dart) ──────────────────
  const FB_STRINGS = {
    shareExact: [
      'share', 'Share', 'SHARE',
      'බෙදාගන්න', 'බෙදා ගන්න',
      'partager', 'teilen',
    ],
    shareToGroupExact: [
      'Group', 'Groups',
      'share to group', 'share to a group',
      'share to groups', 'share to your group',
      'post to groups',
      'සමූහය', 'සමූහ', 'කණ්ඩාය', 'කණ්ඩායමට', 'කණ්ඩායමකට',
    ],
    postExact: [
      'post', 'Post',
      'share now', 'Share now',
      'පළ කරන්න',
    ],
    excluded: [
      'leave a comment', 'comment', 'like', 'react', 'send',
      'bookmark', 'save', 'follow', 'unfollow', 'more', 'hide', 'report',
    ],
  };

  // ── 3b. Strip non-ASCII / PUA icon characters ─────────────────────────────
  //        Regex: removes every character outside the basic ASCII range (0x00–0x7F)
  //        AND specifically targets Unicode Private Use Area (U+E000–U+F8FF),
  //        Supplementary PUA-A (U+F0000–U+FFFFF), and Supplementary PUA-B.
  function cleanLabel(raw) {
    return (raw || '')
      // Strip PUA blocks (Facebook icon font glyphs live here)
      .replace(/[\uE000-\uF8FF]/g, '')
      // Strip supplementary PUA via surrogate pairs
      .replace(/[\uDB80-\uDBFF][\uDC00-\uDFFF]/g, '')
      // Strip remaining non-ASCII (the caller's original requirement)
      .replace(/[^\x00-\x7F]/g, '')
      .trim();
  }

  // ── 3c. isVisible helper ──────────────────────────────────────────────────
  function _isVisible(el) {
    if (!el) return false;
    if (el.offsetWidth === 0 || el.offsetHeight === 0) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  // ── 3d. isExcluded helper ─────────────────────────────────────────────────
  function _isExcluded(cleaned) {
    const lc = cleaned.toLowerCase();
    return FB_STRINGS.excluded.some(ex => lc === ex.toLowerCase());
  }

  /**
   * window.__fbCleanMatch(scope, type)
   *
   * Searches `scope` (Element or document) for a visible button whose
   * aria-label or innerText — after stripping icon characters — matches one of
   * the FbStrings labels for `type`.
   *
   * @param {Element|Document} scope  Root to search within.
   * @param {'share'|'group'|'post'} type  Which label list to use.
   * @returns {Element|null}
   */
  window.__fbCleanMatch = function (scope, type) {
    scope = scope || document;

    const lists = {
      share: FB_STRINGS.shareExact,
      group: FB_STRINGS.shareToGroupExact,
      post:  FB_STRINGS.postExact,
    };

    const labelList = lists[type];
    if (!labelList) {
      console.warn('[fbCleanMatch] Unknown type:', type);
      return null;
    }

    const candidates = [
      ...scope.querySelectorAll(
        'div[role="button"],button,a[role="button"],' +
        '[tabindex="0"][role="button"],[role="menuitem"],[role="option"]'
      ),
    ].filter(_isVisible);

    for (const el of candidates) {
      const rawAria = el.getAttribute('aria-label') || '';
      const rawText = (el.innerText || el.textContent || '').replace(/\s+/g, ' ');

      const cleanedAria = cleanLabel(rawAria);
      const cleanedText = cleanLabel(rawText);

      if (_isExcluded(cleanedAria) || _isExcluded(cleanedText)) continue;

      const matchesAria = labelList.some(
        lbl => cleanedAria.toLowerCase() === lbl.toLowerCase()
      );
      const matchesText = labelList.some(
        lbl => cleanedText.toLowerCase() === lbl.toLowerCase()
      );

      if (matchesAria || matchesText) return el;
    }

    return null;
  };

  /**
   * window.__fbCleanMatchAll(scope, type)
   * Same as __fbCleanMatch but returns ALL matching elements.
   */
  window.__fbCleanMatchAll = function (scope, type) {
    scope = scope || document;

    const lists = {
      share: FB_STRINGS.shareExact,
      group: FB_STRINGS.shareToGroupExact,
      post:  FB_STRINGS.postExact,
    };

    const labelList = lists[type];
    if (!labelList) return [];

    const results = [];
    const candidates = [
      ...scope.querySelectorAll(
        'div[role="button"],button,a[role="button"],' +
        '[tabindex="0"][role="button"],[role="menuitem"],[role="option"]'
      ),
    ].filter(_isVisible);

    for (const el of candidates) {
      const rawAria = el.getAttribute('aria-label') || '';
      const rawText = (el.innerText || el.textContent || '').replace(/\s+/g, ' ');

      const cleanedAria = cleanLabel(rawAria);
      const cleanedText = cleanLabel(rawText);

      if (_isExcluded(cleanedAria) || _isExcluded(cleanedText)) continue;

      const matchesAria = labelList.some(
        lbl => cleanedAria.toLowerCase() === lbl.toLowerCase()
      );
      const matchesText = labelList.some(
        lbl => cleanedText.toLowerCase() === lbl.toLowerCase()
      );

      if (matchesAria || matchesText) results.push(el);
    }

    return results;
  };

  /**
   * window.__fbStripIcons(str)
   * Utility: returns the icon-stripped version of any string.
   * Use this in your automation scripts when building custom matchers.
   */
  window.__fbStripIcons = cleanLabel;

  // ── 3e. Expose FB_STRINGS for use in other scripts ────────────────────────
  window.__fbStrings = FB_STRINGS;

  // ══════════════════════════════════════════════════════════════════════════
  // 4.  CLEANUP / RESTORE API
  //     window.__fbMobileFrameRestore() — removes the frame and restores the
  //     original body layout. Call this if you want to undo the transformation
  //     (e.g. after automation completes, or when navigating away).
  // ══════════════════════════════════════════════════════════════════════════

  window.__fbMobileFrameRestore = function () {
    try {
      const frame  = document.getElementById('__fbMobileFrame');
      const scroll = document.getElementById('__fbMobileFrameScroll');

      if (frame && scroll) {
        // Move children back to <body>
        while (scroll.firstChild) {
          document.body.insertBefore(scroll.firstChild, frame);
        }
        frame.remove();
      }

      const styleEl = document.getElementById('__fbMobileFrameStyle');
      if (styleEl) styleEl.remove();

      const fontEl = document.getElementById('__fbFontFix');
      if (fontEl) fontEl.remove();

      window.__fbMobileFrameInjected = false;
      console.log('[fbMobileFrame] Restored original layout.');
    } catch (e) {
      console.error('[fbMobileFrame] Restore error:', e);
    }
  };

  console.log('[fbMobileFrame] ✅ Injected — phone frame active, font fix applied, __fbCleanMatch ready.');

})();