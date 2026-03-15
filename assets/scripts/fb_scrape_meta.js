/**
 * fb_scrape_meta.js  v2.0
 * ─────────────────────────────────────────────────────────────────────────────
 * Scrapes page title and profile image from a Facebook page/post.
 * Called by automation_provider.dart → addPageToList().
 *
 * Image extraction priority:
 *  1. meta[property="og:image"]
 *  2. meta[name="twitter:image"]
 *  3. <img> with "profile" or "avatar" in class/id/alt (largest first)
 *  4. First <img> inside a <header> element
 *  5. Empty string (caller will show fallback avatar)
 *
 * Returns a clean JSON string (no double-encoding).
 * ─────────────────────────────────────────────────────────────────────────────
 */
(function () {
  'use strict';

  // ── Helpers ──────────────────────────────────────────────────────────────────

  function getMeta(prop) {
    var el = document.querySelector('meta[property="' + prop + '"]') ||
             document.querySelector('meta[name="' + prop + '"]');
    return el ? (el.getAttribute('content') || '').trim() : '';
  }

  /** Strip any extra JSON-string wrapping that WebView2 sometimes adds. */
  function cleanUrl(raw) {
    if (!raw) return '';
    var s = raw.trim();
    // unwrap a double-quoted JSON string  e.g.  "\"https://...\""
    if (s.charAt(0) === '"' && s.charAt(s.length - 1) === '"') {
      try {
        var inner = JSON.parse(s);
        if (typeof inner === 'string') s = inner.trim();
      } catch (_) {}
    }
    return s;
  }

  // ── 1. Title ──────────────────────────────────────────────────────────────────
  var title = getMeta('og:title') ||
               getMeta('twitter:title') ||
               document.title ||
               'Unknown Page';
  title = title.trim();

  // ── 2. Image — cascading fallback ─────────────────────────────────────────────
  var imageUrl = '';

  // Priority 1: og:image
  imageUrl = cleanUrl(getMeta('og:image'));

  // Priority 2: twitter:image
  if (!imageUrl) {
    imageUrl = cleanUrl(getMeta('twitter:image'));
  }

  // Priority 3: <img> whose class / id / alt contains "profile" or "avatar"
  if (!imageUrl) {
    var imgs = Array.prototype.slice.call(document.querySelectorAll('img'));
    var profileImgs = imgs.filter(function (img) {
      var cls = (img.className || '').toLowerCase();
      var id  = (img.id        || '').toLowerCase();
      var alt = (img.alt       || '').toLowerCase();
      return (
        cls.indexOf('profile') !== -1 || cls.indexOf('avatar') !== -1 ||
        id.indexOf('profile')  !== -1 || id.indexOf('avatar')  !== -1 ||
        alt.indexOf('profile') !== -1 || alt.indexOf('avatar')  !== -1
      );
    });
    // Pick the largest one (natural width × height)
    if (profileImgs.length > 0) {
      profileImgs.sort(function (a, b) {
        return (b.naturalWidth * b.naturalHeight) - (a.naturalWidth * a.naturalHeight);
      });
      imageUrl = cleanUrl(profileImgs[0].src);
    }
  }

  // Priority 4: first <img> inside <header>
  if (!imageUrl) {
    var header = document.querySelector('header');
    if (header) {
      var hImg = header.querySelector('img');
      if (hImg && hImg.src) {
        imageUrl = cleanUrl(hImg.src);
      }
    }
  }

  // Sanity-check: reject data: URIs and blob: URIs (not useful for Image.network)
  if (imageUrl && (imageUrl.indexOf('data:') === 0 || imageUrl.indexOf('blob:') === 0)) {
    imageUrl = '';
  }

  // ── 3. Return ─────────────────────────────────────────────────────────────────
  var result = { status: 'success', name: title, imageUrl: imageUrl };
  return JSON.stringify(result);   // single-encoded – no wrapping needed
}());
