/**
 * fb_photo_viewer_launcher.js  v1.0
 * ─────────────────────────────────────────────────────────────────────────────
 * Injected via Flutter WebView2 executeScript().
 *
 * Purpose — Automate the INITIAL stage of Facebook sharing for a Flutter
 * WebView by:
 *   1. Waiting for the page to be fully loaded.
 *   2. Cleaning the UI: hiding all background elements (feed, sidebars, header)
 *      and centering the main post content in a 380×750 fixed frame.
 *   3. Finding the main post image and performing a click() to open Facebook's
 *      native Photo Viewer mode.
 *   4. Fixing fonts so that icon glyphs (Share arrow, etc.) render correctly
 *      instead of □ boxes.
 *   5. Using a MutationObserver to detect when the Photo Viewer opens, then
 *      automatically hiding the "Open App" banner if it appears.
 *   6. Reporting status back to Flutter via window.__fbPhotoViewerStatus once
 *      the Photo Viewer is confirmed active.
 *
 * Flutter integration:
 *   await controller.executeScript(photoViewerLauncherScript);
 *   // Then poll or listen for window.__fbPhotoViewerStatus:
 *   //   { stage: 'photo_viewer_active' | 'error' | ..., ... }
 *
 * Idempotency: Safe to inject more than once — the guard at the top prevents
 * double-execution on the same page.
 * ─────────────────────────────────────────────────────────────────────────────
 */

(function () {
  'use strict';

  // ── 0. Idempotency guard ────────────────────────────────────────────────────
  if (window.__fbPhotoViewerLauncherActive) return;
  window.__fbPhotoViewerLauncherActive = true;

  // ── 1. Shared state ─────────────────────────────────────────────────────────
  /** @type {MutationObserver|null} Watches the DOM for the Photo Viewer opening. */
  var _viewerObserver = null;

  /** @type {MutationObserver|null} Watches for the "Open App" banner. */
  var _bannerObserver = null;

  /** @type {boolean} Becomes true once the Photo Viewer is confirmed open. */
  var _viewerConfirmed = false;

  // ── 2. Status channel back to Flutter ──────────────────────────────────────
  /**
   * Writes a structured status object to window.__fbPhotoViewerStatus.
   * Flutter can read this at any time via:
   *   final raw = await controller.executeScript('JSON.stringify(window.__fbPhotoViewerStatus)');
   *
   * @param {string} stage   - Machine-readable stage identifier.
   * @param {string} message - Human-readable description.
   * @param {Object} [extra] - Optional extra data merged into the status object.
   */
  function setStatus(stage, message, extra) {
    window.__fbPhotoViewerStatus = Object.assign(
      { stage: stage, message: message, ts: Date.now() },
      extra || {}
    );
    // Also log to console so Flutter's WebView console listener can pick it up.
    console.log('[fbPhotoViewer] ' + stage + ': ' + message);
  }

  // ── 3. Font / icon fix ──────────────────────────────────────────────────────
  /**
   * Injects a <style> that forces "Segoe UI Symbol" globally so that Facebook's
   * Unicode PUA icon glyphs (Share arrow ›, etc.) render as real glyphs on
   * Windows WebView2 instead of showing empty □ boxes.
   * This mirrors the approach used in fb_mobile_frame_injector.js but is kept
   * self-contained here so this script can be used independently.
   */
  function injectFontFix() {
    var id = '__fbPhotoViewerFontFix';
    if (document.getElementById(id)) return; // already injected

    var style = document.createElement('style');
    style.id = id;
    style.textContent = [
      '/* fb_photo_viewer_launcher — icon/font fix */',
      '* {',
      '  font-family: "Segoe UI Symbol", "Segoe UI Historic",',
      '               "Segoe UI", Arial, sans-serif !important;',
      '}',
    ].join('\n');
    (document.head || document.documentElement).appendChild(style);
  }

  // ── 4. UI clean-up: 380×750 centred frame ───────────────────────────────────
  /**
   * Hides all desktop chrome (feed, sidebars, header, footer) and centres the
   * page content in a fixed 380×750 phone-like frame.
   *
   * Design:
   *  - A full-screen dark backdrop covers the original page.
   *  - A 380×750 centred white container holds a scrollable clone of the
   *    document body's children so that Facebook's event listeners are preserved.
   *  - pointer-events are disabled on the backdrop and enabled only inside the
   *    frame, preventing accidental background clicks.
   */
  function injectMobileFrame() {
    var styleId = '__fbPVLFrameStyle';
    if (document.getElementById(styleId)) return;

    // ── 4a. CSS ─────────────────────────────────────────────────────────────
    var style = document.createElement('style');
    style.id = styleId;
    style.textContent = [
      '/* fb_photo_viewer_launcher — mobile frame */',

      // Dark backdrop + no scroll on the raw body
      'html, body {',
      '  background: #0f1117 !important;',
      '  margin: 0 !important; padding: 0 !important;',
      '  overflow: hidden !important;',
      '  pointer-events: none !important;',   // block backdrop clicks
      '}',

      // Hide desktop chrome elements using stable Facebook selectors
      '[role="banner"], header, footer,',
      '[data-pagelet="NavBar"], [data-pagelet="LeftRail"],',
      '[data-pagelet="RightRail"], [data-pagelet="Stories"],',
      '[data-pagelet="Header"], [data-pagelet="MWebHeaderTopBar"],',
      '[aria-label="Facebook"], nav[aria-label],',
      '.x1n2onr6.xh8yej3,',         // common FB nav wrapper
      '.x78zum5.xdt5ytf.x1t2pt76 {', // left sidebar
      '  display: none !important;',
      '}',

      // Centred phone frame
      '#__fbPVLFrame {',
      '  position: fixed !important;',
      '  top: 50% !important; left: 50% !important;',
      '  transform: translate(-50%, -50%) !important;',
      '  width: 380px !important; height: 750px !important;',
      '  border-radius: 24px !important;',
      '  overflow: hidden !important;',
      '  background: #fff !important;',
      '  box-shadow: 0 0 0 1px rgba(255,255,255,.07),',
      '              0 8px 32px rgba(0,0,0,.7),',
      '              0 24px 64px rgba(0,0,0,.5) !important;',
      '  z-index: 2147483640 !important;',
      '  pointer-events: auto !important;', // re-enable inside frame
      '}',

      // Scrollable inner wrapper
      '#__fbPVLScroll {',
      '  width: 100% !important; height: 100% !important;',
      '  overflow-y: auto !important; overflow-x: hidden !important;',
      '  -webkit-overflow-scrolling: touch !important;',
      '}',
      '#__fbPVLScroll > * { pointer-events: auto !important; }',

      // Keep dialogs / modals clipped to the frame dimensions
      '[role="dialog"], [aria-modal="true"], [role="alertdialog"] {',
      '  position: fixed !important;',
      '  max-width: 380px !important; max-height: 750px !important;',
      '  overflow-y: auto !important;',
      '  pointer-events: auto !important;',
      '}',
    ].join('\n');

    (document.head || document.documentElement).appendChild(style);

    // ── 4b. DOM restructure ─────────────────────────────────────────────────
    // Move existing <body> children into a scrollable div inside the frame,
    // rather than re-parenting <body> itself, so that Facebook's event
    // listeners (bound to body descendants) continue to fire correctly.
    function buildFrame() {
      if (document.getElementById('__fbPVLFrame')) return; // already built

      var frame  = document.createElement('div');
      frame.id   = '__fbPVLFrame';

      var scroll = document.createElement('div');
      scroll.id  = '__fbPVLScroll';

      // Migrate body children into the scroll wrapper
      while (document.body.firstChild) {
        scroll.appendChild(document.body.firstChild);
      }

      frame.appendChild(scroll);
      document.body.appendChild(frame);
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', buildFrame, { once: true });
    } else {
      buildFrame();
    }
  }

  // ── 5. Image-finding strategies ─────────────────────────────────────────────
  /**
   * Returns true if `el` is a visible, clickable element whose bounding rect
   * has a non-zero area.
   */
  function isVisible(el) {
    if (!el) return false;
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  /**
   * Searches the document for the main post image and returns the best
   * candidate Element to click, or null if nothing was found.
   *
   * Strategy (in priority order):
   *  A. <img> inside a [role="main"] or [role="article"] whose natural size
   *     is at least 100×100 px — most reliable for desktop / www.facebook.com.
   *  B. A <div> with a non-empty CSS background-image inside the same scopes —
   *     covers cases where Facebook renders the image as a background layer.
   *  C. A data-testid="photo-image" img — m.facebook.com mobile page variant.
   *  D. Broadest fallback: the largest <img> on the page by rendered area,
   *     excluding tiny icons (< 80px on the shortest side).
   */
  function findPostImage() {
    // ── A. <img> inside article/main ────────────────────────────────────────
    var scopes = [
      '[role="main"]',
      '[role="article"]',
      '[data-pagelet="FeedUnit_0"]',
      '[data-pagelet^="FeedUnit"]',
    ];
    for (var si = 0; si < scopes.length; si++) {
      var container = document.querySelector(scopes[si]);
      if (!container) continue;

      var imgs = container.querySelectorAll('img');
      for (var ii = 0; ii < imgs.length; ii++) {
        var img = imgs[ii];
        if (!isVisible(img)) continue;
        // Prefer images that are large enough to be the post photo
        if (img.naturalWidth >= 100 && img.naturalHeight >= 100) return img;
      }
    }

    // ── B. Background-image <div> inside article/main ───────────────────────
    for (var si2 = 0; si2 < scopes.length; si2++) {
      var container2 = document.querySelector(scopes[si2]);
      if (!container2) continue;

      var divs = container2.querySelectorAll('div[style]');
      for (var di = 0; di < divs.length; di++) {
        var d = divs[di];
        var bg = window.getComputedStyle(d).backgroundImage;
        if (bg && bg !== 'none' && bg.indexOf('url(') !== -1 && isVisible(d)) {
          return d;
        }
      }
    }

    // ── C. m.facebook.com: data-testid attribute ─────────────────────────────
    var testIdImg = document.querySelector('[data-testid="photo-image"]');
    if (testIdImg && isVisible(testIdImg)) return testIdImg;

    // ── D. Largest <img> fallback ────────────────────────────────────────────
    var allImgs = document.querySelectorAll('img');
    var bestEl = null, bestArea = 0;
    for (var ai = 0; ai < allImgs.length; ai++) {
      var el = allImgs[ai];
      if (!isVisible(el)) continue;
      var r = el.getBoundingClientRect();
      // Skip tiny icons: require at least 80px on the shortest side
      if (Math.min(r.width, r.height) < 80) continue;
      var area = r.width * r.height;
      if (area > bestArea) { bestArea = area; bestEl = el; }
    }
    return bestEl; // may be null if nothing passes the 80px threshold
  }

  // ── 6. "Open App" banner suppressor ─────────────────────────────────────────
  /**
   * Hides the "Open in Facebook App" (or similar) smart-app-banner that
   * Facebook may inject over the Photo Viewer on mobile WebView.
   *
   * Identified by:
   *  - apple-itunes-app / google-play-app <meta> presence (not actionable here)
   *  - Visible elements with aria-label containing "app" or "open"
   *  - Common FB class patterns for the sticky top banner
   *  - The element's bounding rect being at the very top of the viewport
   */
  function suppressOpenAppBanner() {
    // Known selector patterns for the Facebook "Open App" banner
    var bannerSelectors = [
      // Generic smart-app-banner (Safari / Chrome inject this from <meta>)
      '.smartbanner', '#smartbanner', '.smart-app-banner',
      // Facebook-specific sticky header variants
      '[data-testid="open_app_banner"]',
      '[data-testid="msite-open-app-banner"]',
      '[aria-label*="app" i]',
      // Element pinned to top of the viewport whose text contains "Open"
    ];

    var hidden = [];
    for (var i = 0; i < bannerSelectors.length; i++) {
      try {
        var els = document.querySelectorAll(bannerSelectors[i]);
        for (var j = 0; j < els.length; j++) {
          var el = els[j];
          if (!isVisible(el)) continue;
          // Extra check: must be near the top of the viewport (y < 120px)
          var rect = el.getBoundingClientRect();
          if (rect.top > 120) continue;
          el.style.setProperty('display', 'none', 'important');
          hidden.push(el);
        }
      } catch (_) { /* ignore invalid selectors */ }
    }

    // Heuristic sweep: any visible element pinned at top whose inner text
    // includes "open" and "app" (case-insensitive)
    var allFixed = document.querySelectorAll('*');
    for (var k = 0; k < allFixed.length; k++) {
      var el2 = allFixed[k];
      if (!isVisible(el2)) continue;
      var style = window.getComputedStyle(el2);
      if (style.position !== 'fixed' && style.position !== 'sticky') continue;
      var rect2 = el2.getBoundingClientRect();
      if (rect2.top > 120) continue;
      var txt = (el2.innerText || el2.textContent || '').toLowerCase();
      if (txt.indexOf('open') !== -1 && txt.indexOf('app') !== -1) {
        el2.style.setProperty('display', 'none', 'important');
        hidden.push(el2);
      }
    }

    if (hidden.length > 0) {
      console.log('[fbPhotoViewer] suppressOpenAppBanner: hid ' + hidden.length + ' banner element(s).');
    }
  }

  // ── 7. Photo Viewer detection via MutationObserver ───────────────────────────
  /**
   * Determines whether Facebook's Photo Viewer overlay is currently open.
   *
   * Positive signals (any one is sufficient):
   *  - A [role="dialog"] with a visible <img> large enough to be a photo view.
   *  - An element carrying data-testid="photoViewer" or id containing "photo".
   *  - The URL hash changing to include "?type=3" or "/photos/" (m.facebook.com).
   *  - A [role="presentation"] dialog containing a high-resolution <img>.
   */
  function isPhotoViewerOpen() {
    // Signal 1: role="dialog" with a large image inside
    var dialogs = document.querySelectorAll('[role="dialog"],[role="presentation"]');
    for (var i = 0; i < dialogs.length; i++) {
      var dlg = dialogs[i];
      if (!isVisible(dlg)) continue;
      var imgs = dlg.querySelectorAll('img');
      for (var j = 0; j < imgs.length; j++) {
        var img = imgs[j];
        if (!isVisible(img)) continue;
        if (img.naturalWidth >= 200 || img.naturalHeight >= 200) return true;
      }
    }

    // Signal 2: known Facebook Photo Viewer test ID / id attributes
    var pvEl = document.querySelector(
      '[data-testid="photoViewer"], [data-testid="photo_view"], #photoViewer'
    );
    if (pvEl && isVisible(pvEl)) return true;

    // Signal 3: URL-based — m.facebook.com adds ?type=3 or /photos/ segment
    var href = window.location.href;
    if (/\/(photos|photo)\//i.test(href) || /[?&]type=3/.test(href)) {
      // Confirm there's a visible large image (not just a nav change)
      var largeImg = document.querySelector('img[src*="scontent"]');
      if (largeImg && isVisible(largeImg)) return true;
    }

    return false;
  }

  /**
   * Starts a MutationObserver on document.body that watches for DOM subtree
   * changes.  When isPhotoViewerOpen() becomes true, it:
   *   1. Disconnects itself (one-shot behaviour).
   *   2. Starts a secondary observer that watches for and hides the "Open App"
   *      banner — banners often appear a few hundred ms after the viewer opens.
   *   3. Calls setStatus('photo_viewer_active', ...) to signal Flutter.
   *
   * @param {number} timeoutMs - Maximum ms to wait before reporting an error.
   */
  function watchForPhotoViewer(timeoutMs) {
    var deadline = setTimeout(function () {
      if (_viewerConfirmed) return;
      if (_viewerObserver) { _viewerObserver.disconnect(); _viewerObserver = null; }
      setStatus('error', 'Photo Viewer did not open within ' + timeoutMs + 'ms.',
        { timeoutMs: timeoutMs });
    }, timeoutMs);

    _viewerObserver = new MutationObserver(function (mutations, obs) {
      if (_viewerConfirmed) { obs.disconnect(); return; }

      if (!isPhotoViewerOpen()) return;

      // ── Photo Viewer is now open ──────────────────────────────────────────
      _viewerConfirmed = true;
      obs.disconnect();
      _viewerObserver = null;
      clearTimeout(deadline);

      // Run the banner suppressor immediately …
      suppressOpenAppBanner();

      // … and keep watching for late-appearing banners for up to 5 seconds.
      _bannerObserver = new MutationObserver(function () {
        suppressOpenAppBanner();
      });
      _bannerObserver.observe(document.body, {
        childList: true,
        subtree:   true,
        attributes: true,
        attributeFilter: ['style', 'class'],
      });
      // Auto-stop the banner observer after 5 s to avoid memory leaks.
      setTimeout(function () {
        if (_bannerObserver) { _bannerObserver.disconnect(); _bannerObserver = null; }
      }, 5000);

      setStatus('photo_viewer_active',
        'Photo Viewer is open. Banner suppressor active.',
        { viewerDetectedAt: Date.now() });
    });

    _viewerObserver.observe(document.body, {
      childList:  true,
      subtree:    true,
      attributes: true,
      attributeFilter: ['style', 'class', 'role', 'aria-modal'],
    });
  }

  // ── 8. Main orchestrator ─────────────────────────────────────────────────────
  /**
   * window.__fbLaunchPhotoViewer(opts?)
   *
   * Public entry-point called by Flutter after the WebView finishes loading.
   *
   * @param {Object}  [opts]
   * @param {number}  [opts.timeoutMs=12000]  - How long (ms) to wait for the
   *                                            Photo Viewer to appear.
   * @param {boolean} [opts.skipFrame=false]  - Set true to skip the 380×750
   *                                            phone-frame injection (useful if
   *                                            fb_mobile_frame_injector.js is
   *                                            already active on this page).
   * @returns {void}  Status is communicated via window.__fbPhotoViewerStatus.
   */
  window.__fbLaunchPhotoViewer = function (opts) {
    opts = opts || {};
    var timeoutMs = typeof opts.timeoutMs === 'number' ? opts.timeoutMs : 12000;
    var skipFrame = !!opts.skipFrame;

    setStatus('initialising', 'Script started, waiting for page readiness.');

    // ── Step 1: Wait for DOMContentLoaded / readyState ───────────────────────
    function run() {
      setStatus('page_ready', 'Page DOM is ready. Applying UI transforms.');

      // ── Step 2: Font fix ──────────────────────────────────────────────────
      injectFontFix();

      // ── Step 3: Mobile frame (clean UI) ──────────────────────────────────
      if (!skipFrame) {
        injectMobileFrame();
      }

      // ── Step 4: Arm the Photo Viewer detector BEFORE clicking the image ──
      // (The click is async; the viewer may open before JS returns control.)
      watchForPhotoViewer(timeoutMs);

      // ── Step 5: Find and click the post image ────────────────────────────
      // Small delay lets the frame CSS settle so getBoundingClientRect() is
      // accurate when findPostImage() measures element sizes.
      setTimeout(function () {
        var imgEl = findPostImage();

        if (!imgEl) {
          // If no image is found, stop the observer and report the error.
          if (_viewerObserver) { _viewerObserver.disconnect(); _viewerObserver = null; }
          setStatus('error', 'No post image found on the page.',
            { hint: 'Ensure the post contains an image and the page is fully loaded.' });
          return;
        }

        setStatus('image_found',
          'Post image located. Performing click to open Photo Viewer.',
          {
            tagName:      imgEl.tagName,
            naturalWidth: imgEl.naturalWidth || 0,
            naturalHeight: imgEl.naturalHeight || 0,
          });

        try {
          imgEl.click();
        } catch (clickErr) {
          setStatus('error', 'click() on image element threw: ' + String(clickErr));
        }
      }, 200); // 200 ms grace period for layout
    }

    // Respect the page load state — behave correctly whether the script is
    // injected early (before DOMContentLoaded) or late (after full load).
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', run, { once: true });
    } else {
      run();
    }
  };

  // ── 9. Cleanup / teardown API ────────────────────────────────────────────────
  /**
   * window.__fbPhotoViewerCleanup()
   *
   * Disconnects all observers and removes injected styles.  Call this when
   * navigation moves away from the post page or automation is complete.
   */
  window.__fbPhotoViewerCleanup = function () {
    if (_viewerObserver) { _viewerObserver.disconnect(); _viewerObserver = null; }
    if (_bannerObserver) { _bannerObserver.disconnect(); _bannerObserver = null; }

    var ids = ['__fbPVLFrameStyle', '__fbPhotoViewerFontFix'];
    ids.forEach(function (id) {
      var el = document.getElementById(id);
      if (el) el.remove();
    });

    // Restore body children if frame was built
    var frame  = document.getElementById('__fbPVLFrame');
    var scroll = document.getElementById('__fbPVLScroll');
    if (frame && scroll) {
      while (scroll.firstChild) {
        document.body.insertBefore(scroll.firstChild, frame);
      }
      frame.remove();
    }

    _viewerConfirmed = false;
    window.__fbPhotoViewerLauncherActive = false;
    setStatus('cleaned_up', 'All observers disconnected and styles removed.');
  };

  // ── 10. Auto-start if Flutter passed options via window.__fbPVLOptions ──────
  // Flutter can pre-seed options before injection:
  //   await controller.executeScript('window.__fbPVLOptions = { timeoutMs: 15000 };');
  //   await controller.executeScript(/* this script */);
  if (window.__fbPVLOptions) {
    window.__fbLaunchPhotoViewer(window.__fbPVLOptions);
  } else {
    // Default auto-start with standard options
    window.__fbLaunchPhotoViewer({});
  }

  console.log('[fbPhotoViewer] ✅ fb_photo_viewer_launcher.js loaded.');

})();
