// ─────────────────────────────────────────────────────────────────────────────
// fb_mobile_frame_service.dart
//
// Flutter service that loads and injects fb_mobile_frame_injector.js into
// the WebView2 controller.  Drop this in lib/services/ and call
//   FbMobileFrameService(controller: _wvc).inject();
// once the WebView has finished loading the Facebook page.
//
// The script is idempotent — calling inject() multiple times or across
// page navigations is safe (the JS guard window.__fbMobileFrameInjected
// prevents double-application).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_windows/webview_windows.dart';

class FbMobileFrameService {
  final WebviewController controller;

  static const _assetPath = 'assets/scripts/fb_mobile_frame_injector.js';

  // Cached script string — loaded once, reused on subsequent inject() calls.
  static String? _scriptCache;

  FbMobileFrameService({required this.controller});

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Injects the mobile-frame + font-fix + smart-match script into the WebView.
  ///
  /// Returns `true` on success, `false` if the asset could not be loaded or
  /// if executeScript threw.  Never throws — errors are returned as false.
  Future<bool> inject() async {
    final script = await _loadScript();
    if (script == null) return false;

    try {
      await controller.executeScript(script);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('⚠️  FbMobileFrameService.inject: $e');
      return false;
    }
  }

  /// Removes the phone frame and restores the original Facebook layout.
  /// Useful after automation finishes or before navigating away.
  Future<void> restore() async {
    try {
      await controller.executeScript(
          'window.__fbMobileFrameRestore?.();');
    } catch (_) {}
  }

  /// Convenience wrapper: use the smart __fbCleanMatch helper to find a
  /// button inside [scope] (a CSS selector string, defaults to 'document').
  ///
  /// [type] must be one of: 'share' | 'group' | 'post'
  ///
  /// Returns the element's aria-label / innerText if found, null otherwise.
  Future<String?> findButton({
    required String type,
    String scope = 'document',
  }) async {
    try {
      final js = '''
(function(){
  const scope = "$scope" === "document"
      ? document
      : document.querySelector("$scope");
  const el = window.__fbCleanMatch?.(scope, "$type");
  if (!el) return null;
  return el.getAttribute("aria-label") || (el.innerText || "").trim().substring(0, 80);
})()
''';
      final result = await controller.executeScript(js);
      final raw = result?.toString() ?? '';
      if (raw.isEmpty || raw == 'null') return null;
      // executeScript wraps strings in extra quotes on some WebView2 versions
      if (raw.startsWith('"') && raw.endsWith('"')) {
        return raw.substring(1, raw.length - 1);
      }
      return raw;
    } catch (_) {
      return null;
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<String?> _loadScript() async {
    if (_scriptCache != null) return _scriptCache;
    try {
      _scriptCache = await rootBundle.loadString(_assetPath);
      return _scriptCache;
    } catch (e) {
      // ignore: avoid_print
      print('⚠️  FbMobileFrameService: could not load $_assetPath — $e');
      return null;
    }
  }
}
