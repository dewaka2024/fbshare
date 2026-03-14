// ─────────────────────────────────────────────────────────────────────────────
// fb_photo_viewer_service.dart
//
// Flutter service that loads and injects fb_photo_viewer_launcher.js into
// the WebView2 controller.
//
// Usage (after WebView finishes loading):
//   final svc = FbPhotoViewerService(controller: _wvc);
//   await svc.launch();                          // inject + auto-start
//   final status = await svc.getStatus();        // poll for result
//   await svc.cleanup();                         // disconnect observers
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_windows/webview_windows.dart';

/// Structured status returned by [FbPhotoViewerService.getStatus].
class PhotoViewerStatus {
  final String stage;
  final String message;
  final int? ts;
  final Map<String, dynamic> extra;

  const PhotoViewerStatus({
    required this.stage,
    required this.message,
    this.ts,
    this.extra = const {},
  });

  bool get isActive      => stage == 'photo_viewer_active';
  bool get isError       => stage == 'error';
  bool get isInitialised => stage != 'unknown';

  factory PhotoViewerStatus.fromJson(Map<String, dynamic> json) {
    return PhotoViewerStatus(
      stage:   json['stage']   as String? ?? 'unknown',
      message: json['message'] as String? ?? '',
      ts:      json['ts']      as int?,
      extra:   Map<String, dynamic>.from(json)
        ..remove('stage')
        ..remove('message')
        ..remove('ts'),
    );
  }

  factory PhotoViewerStatus.unknown() => const PhotoViewerStatus(
    stage: 'unknown', message: 'Status not yet available.',
  );

  @override
  String toString() => 'PhotoViewerStatus(stage: $stage, message: $message)';
}

class FbPhotoViewerService {
  final WebviewController controller;

  static const _assetPath = 'assets/scripts/fb_photo_viewer_launcher.js';
  static String? _scriptCache;

  FbPhotoViewerService({required this.controller});

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Injects the script and starts the photo-viewer launch sequence.
  ///
  /// [timeoutMs]  How long (ms) the JS waits for the Photo Viewer to appear.
  ///              Defaults to 12 000 ms.
  /// [skipFrame]  Pass true if fb_mobile_frame_injector.js is already active
  ///              on the page — avoids injecting a second phone frame.
  ///
  /// Returns true if injection succeeded, false on asset-load or script error.
  Future<bool> launch({
    int timeoutMs = 12000,
    bool skipFrame = false,
  }) async {
    final script = await _loadScript();
    if (script == null) return false;

    try {
      // Pre-seed options so the script auto-starts with the correct config.
      await controller.executeScript(
        'window.__fbPVLOptions = '
        '{ timeoutMs: $timeoutMs, skipFrame: $skipFrame };',
      );
      await controller.executeScript(script);
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('⚠️  FbPhotoViewerService.launch: $e');
      return false;
    }
  }

  /// Reads the current status written by the JS script.
  ///
  /// Returns [PhotoViewerStatus.unknown] if no status is available yet.
  Future<PhotoViewerStatus> getStatus() async {
    try {
      final raw = await controller.executeScript(
        'JSON.stringify(window.__fbPhotoViewerStatus || null)',
      );
      if (raw == null || raw.trim() == 'null' || raw.trim().isEmpty) {
        return PhotoViewerStatus.unknown();
      }
      // WebView2 sometimes wraps the JSON string in extra quotes.
      var clean = raw.trim();
      if (clean.startsWith('"') && clean.endsWith('"')) {
        clean = jsonDecode(clean) as String;
      }
      final map = jsonDecode(clean) as Map<String, dynamic>;
      return PhotoViewerStatus.fromJson(map);
    } catch (e) {
      // ignore: avoid_print
      print('⚠️  FbPhotoViewerService.getStatus: $e');
      return PhotoViewerStatus.unknown();
    }
  }

  /// Polls [getStatus] every [intervalMs] milliseconds until the Photo Viewer
  /// is active, an error occurs, or [timeoutMs] elapses.
  ///
  /// Returns the final [PhotoViewerStatus].
  Future<PhotoViewerStatus> waitForPhotoViewer({
    int timeoutMs  = 15000,
    int intervalMs = 500,
  }) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
      final status = await getStatus();
      if (status.isActive || status.isError) return status;
    }
    return const PhotoViewerStatus(
      stage: 'error',
      message: 'Dart-side polling timed out waiting for Photo Viewer.',
    );
  }

  /// Disconnects MutationObservers and removes injected styles.
  /// Call this when navigating away from the post page.
  Future<void> cleanup() async {
    try {
      await controller.executeScript('window.__fbPhotoViewerCleanup?.();');
    } catch (_) {}
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<String?> _loadScript() async {
    if (_scriptCache != null) return _scriptCache;
    try {
      _scriptCache = await rootBundle.loadString(_assetPath);
      return _scriptCache;
    } catch (e) {
      // ignore: avoid_print
      print('⚠️  FbPhotoViewerService: could not load $_assetPath — $e');
      return null;
    }
  }
}
