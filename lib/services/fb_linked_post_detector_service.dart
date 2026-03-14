// ─────────────────────────────────────────────────────────────────────────────
// fb_linked_post_detector_service.dart
//
// Flutter service that loads and injects fb_linked_post_detector.js into the
// WebView2 controller, then parses and returns the structured result.
//
// Usage:
//   final svc    = FbLinkedPostDetectorService(controller: _wvc);
//   final result = await svc.detect();
//
//   if (result.isSuccess) {
//     print('Container id: ${result.details?.id}');
//     print('aria-labelledby: ${result.details?.ariaLabelledBy}');
//   } else {
//     print('Failed: ${result.message}');
//   }
//
// CONTRACT — READ-ONLY:
//   This service performs detection ONLY.
//   It never clicks, navigates, or triggers any further automation.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_windows/webview_windows.dart';

// ── Result models ─────────────────────────────────────────────────────────────

/// Bounding rect of the detected element.
class DetectedRect {
  final int top, left, width, height;
  const DetectedRect({
    required this.top,
    required this.left,
    required this.width,
    required this.height,
  });

  factory DetectedRect.fromJson(Map<String, dynamic> j) => DetectedRect(
        top:    (j['top']    as num?)?.toInt() ?? 0,
        left:   (j['left']   as num?)?.toInt() ?? 0,
        width:  (j['width']  as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() => '{top:$top, left:$left, width:$width, height:$height}';
}

/// Identifying attributes extracted from the post container element.
class LinkedPostDetails {
  final String tagName;
  final String? id;
  final String? ariaLabelledBy;
  final String? ariaLabel;
  final String? role;
  final String? dataPagelet;
  final String? dataTestId;
  final String? classList;
  final DetectedRect? boundingRect;
  final String? innerTextPreview;
  final String? selector;

  const LinkedPostDetails({
    required this.tagName,
    this.id,
    this.ariaLabelledBy,
    this.ariaLabel,
    this.role,
    this.dataPagelet,
    this.dataTestId,
    this.classList,
    this.boundingRect,
    this.innerTextPreview,
    this.selector,
  });

  factory LinkedPostDetails.fromJson(Map<String, dynamic> j) =>
      LinkedPostDetails(
        tagName:          j['tagName']         as String? ?? 'unknown',
        id:               j['id']              as String?,
        ariaLabelledBy:   j['ariaLabelledBy']  as String?,
        ariaLabel:        j['ariaLabel']       as String?,
        role:             j['role']            as String?,
        dataPagelet:      j['dataPagelet']     as String?,
        dataTestId:       j['dataTestId']      as String?,
        classList:        j['classList']       as String?,
        boundingRect:     j['boundingRect'] != null
            ? DetectedRect.fromJson(
                Map<String, dynamic>.from(j['boundingRect'] as Map))
            : null,
        innerTextPreview: j['innerTextPreview'] as String?,
        selector:         j['selector']         as String?,
      );

  /// Returns the best available unique identifier for the element.
  String get uniqueId {
    if (id != null && id!.isNotEmpty) return '#$id';
    if (ariaLabelledBy != null && ariaLabelledBy!.isNotEmpty) {
      return '[aria-labelledby="$ariaLabelledBy"]';
    }
    if (dataPagelet != null && dataPagelet!.isNotEmpty) {
      return '[data-pagelet="$dataPagelet"]';
    }
    if (dataTestId != null && dataTestId!.isNotEmpty) {
      return '[data-testid="$dataTestId"]';
    }
    return selector ?? tagName;
  }

  @override
  String toString() =>
      'LinkedPostDetails(tag:$tagName, id:$id, '
      'aria-labelledby:$ariaLabelledBy, selector:$selector)';
}

/// Top-level result returned by [FbLinkedPostDetectorService.detect].
class LinkedPostResult {
  /// 'success' or 'failed'.
  final String status;

  /// Human-readable status message.
  final String message;

  /// Populated on success — attributes of the post container.
  final LinkedPostDetails? details;

  /// Populated on failure — reason string from the JS script.
  final String? reason;

  /// Epoch ms from the JS side when detection completed.
  final int? detectedAt;

  const LinkedPostResult({
    required this.status,
    required this.message,
    this.details,
    this.reason,
    this.detectedAt,
  });

  bool get isSuccess => status == 'success';
  bool get isFailed  => status == 'failed';

  factory LinkedPostResult.fromJson(Map<String, dynamic> j) {
    return LinkedPostResult(
      status:     j['status']     as String? ?? 'failed',
      message:    j['message']    as String? ?? '',
      reason:     j['reason']     as String?,
      detectedAt: j['detectedAt'] as int?,
      details: j['details'] != null
          ? LinkedPostDetails.fromJson(
              Map<String, dynamic>.from(j['details'] as Map))
          : null,
    );
  }

  factory LinkedPostResult.dartError(String msg) => LinkedPostResult(
        status:  'failed',
        message: 'Could not find the linked post',
        reason:  msg,
      );

  @override
  String toString() =>
      'LinkedPostResult(status:$status, message:$message, '
      'details:$details)';
}

// ── Service ───────────────────────────────────────────────────────────────────

class FbLinkedPostDetectorService {
  final WebviewController controller;

  static const _assetPath =
      'assets/scripts/fb_linked_post_detector.js';

  /// Script is loaded once and cached for the lifetime of the service.
  static String? _scriptCache;

  FbLinkedPostDetectorService({required this.controller});

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Injects the detector script and awaits its result.
  ///
  /// The JS script runs with a built-in 10-second timeout. This Dart method
  /// adds an additional [dartTimeoutMs] guard (default 12 s) to handle cases
  /// where WebView2's executeScript itself hangs.
  ///
  /// Returns a [LinkedPostResult] — never throws.
  Future<LinkedPostResult> detect({int dartTimeoutMs = 12000}) async {
    final script = await _loadScript();
    if (script == null) {
      return LinkedPostResult.dartError(
          'Could not load asset: $_assetPath');
    }

    try {
      final raw = await controller
          .executeScript(script)
          .timeout(Duration(milliseconds: dartTimeoutMs));

      return _parse(raw);
    } on Exception catch (e) {
      return LinkedPostResult.dartError('executeScript error: $e');
    }
  }

  /// Polls [window.__fbLinkedPostResult] if you prefer a polling strategy
  /// over awaiting the Promise directly.
  ///
  /// Useful when the script was injected earlier via
  /// `addScriptToExecuteOnDocumentCreated`.
  Future<LinkedPostResult> getStoredResult() async {
    try {
      final raw = await controller.executeScript(
        'JSON.stringify(window.__fbLinkedPostResult || null)',
      );
      if (raw == null || raw.trim() == 'null' || raw.trim().isEmpty) {
        return LinkedPostResult.dartError('No stored result yet.');
      }
      return _parse(raw);
    } on Exception catch (e) {
      return LinkedPostResult.dartError('getStoredResult error: $e');
    }
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Parses the raw string returned by executeScript into [LinkedPostResult].
  LinkedPostResult _parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return LinkedPostResult.dartError('Script returned empty response.');
    }

    // WebView2 wraps JSON strings in extra quotes on some versions.
    var clean = raw.trim();
    if (clean.startsWith('"') && clean.endsWith('"')) {
      try {
        clean = jsonDecode(clean) as String;
      } catch (_) {
        // Already unquoted — use as-is.
      }
    }

    try {
      final map = jsonDecode(clean) as Map<String, dynamic>;
      return LinkedPostResult.fromJson(map);
    } on FormatException catch (e) {
      return LinkedPostResult.dartError('JSON parse error: $e — raw: $clean');
    }
  }

  Future<String?> _loadScript() async {
    if (_scriptCache != null) return _scriptCache;
    try {
      _scriptCache = await rootBundle.loadString(_assetPath);
      return _scriptCache;
    } on Exception catch (e) {
      // ignore: avoid_print
      print('⚠️  FbLinkedPostDetectorService: could not load $_assetPath — $e');
      return null;
    }
  }
}
