// ─────────────────────────────────────────────────────────────────────────────
// fb_share_button_detector_service.dart
//
// Flutter service that injects fb_share_button_detector.js and returns the
// structured detection result.
//
// Usage:
//   final svc    = FbShareButtonDetectorService(controller: _wvc);
//   final result = await svc.detect();
//   if (result.isSuccess) {
//     print('Share button found: ${result.details}');
//   }
//
// CONTRACT — STRICTLY NO CLICK. Detect and report only.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_windows/webview_windows.dart';

class ShareButtonResult {
  final String status;
  final String? message;
  final String? details;
  final Map<String, dynamic>? element;
  final int? detectedAt;

  const ShareButtonResult({
    required this.status,
    this.message,
    this.details,
    this.element,
    this.detectedAt,
  });

  bool get isSuccess => status == 'success';
  bool get isFailed  => status == 'failed';

  factory ShareButtonResult.fromJson(Map<String, dynamic> j) =>
      ShareButtonResult(
        status:     j['status']     as String? ?? 'failed',
        message:    j['message']    as String?,
        details:    j['details']    as String?,
        element:    j['element']    != null
                      ? Map<String, dynamic>.from(j['element'] as Map)
                      : null,
        detectedAt: j['detectedAt'] as int?,
      );

  factory ShareButtonResult.dartError(String msg) =>
      ShareButtonResult(status: 'failed', message: msg);

  @override
  String toString() =>
      'ShareButtonResult(status:$status, details:$details)';
}

class FbShareButtonDetectorService {
  final WebviewController controller;

  static const _assetPath = 'assets/scripts/fb_share_button_detector.js';
  static String? _scriptCache;

  FbShareButtonDetectorService({required this.controller});

  /// Injects the detector and returns the result.
  /// Never throws — errors are wrapped in a failed result.
  Future<ShareButtonResult> detect({int dartTimeoutMs = 10000}) async {
    final script = await _load();
    if (script == null) {
      return ShareButtonResult.dartError('Could not load $_assetPath');
    }
    try {
      final raw = await controller
          .executeScript(script)
          .timeout(Duration(milliseconds: dartTimeoutMs));
      return _parse(raw);
    } on Exception catch (e) {
      return ShareButtonResult.dartError('executeScript error: $e');
    }
  }

  ShareButtonResult _parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return ShareButtonResult.dartError('Empty response from script');
    }
    var clean = raw.trim();
    if (clean.startsWith('"') && clean.endsWith('"')) {
      try { clean = jsonDecode(clean) as String; } catch (_) {}
    }
    try {
      return ShareButtonResult.fromJson(
          jsonDecode(clean) as Map<String, dynamic>);
    } on FormatException catch (e) {
      return ShareButtonResult.dartError('JSON parse error: $e');
    }
  }

  Future<String?> _load() async {
    if (_scriptCache != null) return _scriptCache;
    try {
      _scriptCache = await rootBundle.loadString(_assetPath);
      return _scriptCache;
    } on Exception catch (e) {
      // ignore: avoid_print
      print('⚠️  FbShareButtonDetectorService: $e');
      return null;
    }
  }
}
