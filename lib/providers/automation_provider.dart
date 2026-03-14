import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

import '../constants/fb_strings.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

enum AutomationStatus { idle, navigating, running, success, error }

class ShareResult {
  final bool success;
  final String? message;
  final String? error;
  final String? step;
  final List<dynamic> clickedGroups;
  final List<dynamic> failedGroups;
  final int nextRunStartIndex;
  final int totalGroupsFound;
  final String? hint;
  final DateTime timestamp;

  ShareResult({
    required this.success,
    this.message,
    this.error,
    this.step,
    this.clickedGroups = const [],
    this.failedGroups = const [],
    this.nextRunStartIndex = 0,
    this.totalGroupsFound = 0,
    this.hint,
    required this.timestamp,
  });

  factory ShareResult.fromJson(Map<String, dynamic> json) => ShareResult(
        success: json['success'] == true,
        message: json['message'],
        error: json['error'],
        step: json['step'],
        clickedGroups: json['clickedGroups'] ?? [],
        failedGroups: json['failedGroups'] ?? [],
        nextRunStartIndex: json['nextRunStartIndex'] ?? 0,
        totalGroupsFound: json['totalGroupsFound'] ?? 0,
        hint: json['hint'],
        // timestamp = time JS result arrived on Dart side
        timestamp: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        'error': error,
        'step': step,
        'clickedGroups': clickedGroups,
        'failedGroups': failedGroups,
        'nextRunStartIndex': nextRunStartIndex,
        'totalGroupsFound': totalGroupsFound,
        'hint': hint,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ShareResult.fromPersistedJson(Map<String, dynamic> json) =>
      ShareResult(
        success: json['success'] == true,
        message: json['message'],
        error: json['error'],
        step: json['step'],
        clickedGroups: json['clickedGroups'] ?? [],
        failedGroups: json['failedGroups'] ?? [],
        nextRunStartIndex: json['nextRunStartIndex'] ?? 0,
        totalGroupsFound: json['totalGroupsFound'] ?? 0,
        hint: json['hint'],
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

// ─── PageElement model ────────────────────────────────────────────────────────

class PageElement {
  final String text;
  final String ariaLabel;
  final String testId;
  final String role;
  final String tag;
  final String index;
  final bool shareHint;

  PageElement({
    required this.text,
    required this.ariaLabel,
    required this.testId,
    required this.role,
    required this.tag,
    required this.index,
    this.shareHint = false,
  });

  factory PageElement.fromJson(Map<String, dynamic> j) => PageElement(
        text: (j['text'] ?? '') as String,
        ariaLabel: (j['aria'] ?? '') as String,
        testId: (j['testId'] ?? '') as String,
        role: (j['role'] ?? '') as String,
        tag: (j['tag'] ?? '') as String,
        index: (j['index'] ?? '').toString(),
        shareHint: (j['shareHint'] ?? false) as bool,
      );

  String get displayLabel {
    if (ariaLabel.isNotEmpty) return ariaLabel;
    if (shareHint && text.isNotEmpty) return '↗ Share ($text)';
    return text;
  }

  String get subtitle {
    if (ariaLabel.isNotEmpty && text.isNotEmpty && text != ariaLabel) {
      return text.substring(0, text.length > 50 ? 50 : text.length);
    }
    if (shareHint) return 'share button (count)';
    if (testId.isNotEmpty) return 'testid: $testId';
    return role.isNotEmpty ? role : tag;
  }

  bool get isShareRelated {
    if (shareHint) return true;
    final all = '$text $ariaLabel $testId'.toLowerCase();
    // Use centralized keyword lists from FbStrings
    final hasShare =
        FbStrings.shareKeywords.any((kw) => all.contains(kw.toLowerCase()));
    final excluded = FbStrings.shareExcludeKeywords
        .any((kw) => all.contains(kw.toLowerCase()));
    return hasShare && !excluded;
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

class AutomationProvider extends ChangeNotifier {
  static const _indexKey = 'fb_last_group_index';
  static const _delayKey = 'fb_click_delay_ms';
  static const _urlKey = 'fb_last_post_url';
  static const _groupsKey = 'fb_groups_per_run';
  static const _historyKey = 'fb_run_history';

  // ── Minimum delay enforced by both the slider and the JS script ───────────
  // FIX: was 600ms in JS but 300ms in UI — now consistent everywhere.
  static const int kMinDelayMs = 600;
  static const int kMaxDelayMs = 3000;

  WebviewController? _webviewController;
  Stream<dynamic>? _webMessageBroadcast;
  Stream<String>? _urlBroadcast;
  String _currentUrl = '';

  // FIX: store subscription so listenRightClick doesn't stack duplicates
  StreamSubscription<dynamic>? _rightClickSub;

  // Post-watcher auto-trigger
  StreamSubscription<dynamic>? _postDetectSub;
  bool _postWatcherActive = false;
  bool get postWatcherActive => _postWatcherActive;

  String get currentUrl => _currentUrl;

  WebviewController? get webviewController => _webviewController;
  set webviewController(WebviewController? ctrl) {
    _webviewController = ctrl;
    if (ctrl == null) {
      _webMessageBroadcast = null;
      _urlBroadcast = null;
      // Cancel any dangling right-click listener
      _rightClickSub?.cancel();
      _rightClickSub = null;
      return;
    }
    _webMessageBroadcast = ctrl.webMessage.asBroadcastStream();
    _urlBroadcast = ctrl.url.asBroadcastStream();
    _urlBroadcast!.listen((url) {
      _currentUrl = url;

      // ── Tracker / analytics blocking ────────────────────────────────────────
      const blockedDomains = [
        'pixel.facebook.com',
        'google-analytics.com',
        'analytics.google.com',
        'doubleclick.net',
        'facebook.com/tr',
      ];
      final lower = url.toLowerCase();
      for (final b in blockedDomains) {
        if (lower.contains(b)) {
          ctrl.goBack();
          return;
        }
      }

      // ── Mobile Facebook redirect ─────────────────────────────────────────────
      // Redirect suppressed: mobile User-Agent is set in WebView2 initialization,
      // so www.facebook.com already serves mobile layout. No redirect needed.
      // m.facebook.com / mbasic.facebook.com links still work normally.
      notifyListeners();
    });
  }

  Stream<String>? get urlStream => _urlBroadcast;

  // ── Scope selector captured via right-click ────────────────────────────────
  // Set by the Right-Click to Focus feature. Cleared between automation runs.
  String? _capturedScopeSelector;
  String? get capturedScopeSelector => _capturedScopeSelector;

  /// Inject an enhanced contextmenu listener that also identifies the nearest
  /// scoping container (dialog/menu/listbox ancestor).
  /// Returns a Future that completes after the script is injected.
  ///
  /// The JS posts two message types:
  ///   • FB_RIGHT_CLICK  — element detail (existing, handled by home_screen)
  ///   • FB_SCOPE_FOCUS  — { scopeSelector, scopeRole, scopeLabel }
  Future<void> injectRightClickScopeListener() async {
    if (_webviewController == null) return;
    await _webviewController!.executeScript(r'''
(function() {
  if (window.__fbScopeFocusInjected) return;
  window.__fbScopeFocusInjected = true;

  document.addEventListener('contextmenu', function(e) {
    // Walk up to find the nearest scoping container
    // Priority: role=dialog > aria-modal=true > role=menu > role=listbox > body
    const SCOPE_ROLES = ['dialog', 'alertdialog', 'menu', 'listbox', 'combobox'];
    let scope = null;
    let cur = e.target;
    while (cur && cur !== document.body) {
      const role = (cur.getAttribute('role') || '').toLowerCase();
      const modal = cur.getAttribute('aria-modal');
      if (SCOPE_ROLES.includes(role) || modal === 'true') {
        scope = cur;
        break;
      }
      cur = cur.parentElement;
    }

    if (!scope) return; // no meaningful scope found — don't send

    // Build the most specific stable selector for this scope element
    function buildScopeSelector(el) {
      // Prefer aria-label (very stable on FB dialogs)
      const al = el.getAttribute('aria-label');
      if (al) {
        const escaped = al.replace(/"/g, '\\"');
        const role = el.getAttribute('role');
        return role
          ? '[role="' + role + '"][aria-label="' + escaped + '"]'
          : '[aria-label="' + escaped + '"]';
      }
      // Prefer data-testid
      const tid = el.getAttribute('data-testid');
      if (tid) return '[data-testid="' + tid + '"]';
      // Prefer id
      if (el.id) return '#' + el.id;
      // Fallback: role only
      const role = el.getAttribute('role');
      if (role) return '[role="' + role + '"]';
      // Last resort: tag
      return el.tagName.toLowerCase();
    }

    const sel = buildScopeSelector(scope);
    const info = {
      scopeSelector: sel,
      scopeRole:     scope.getAttribute('role') || scope.tagName.toLowerCase(),
      scopeLabel:    scope.getAttribute('aria-label') || '',
      scopeText:     (scope.innerText || '').trim().substring(0, 60),
    };

    window.chrome.webview.postMessage(
      JSON.stringify({ type: 'FB_SCOPE_FOCUS', payload: JSON.stringify(info) })
    );
  }, true); // capture phase
})();
''');
  }

  /// Called by home_screen when a FB_SCOPE_FOCUS message arrives.
  /// Stores the scope selector so the next _runStep call uses it.
  void setScopeFromRightClick(String scopeSelector) {
    _capturedScopeSelector = scopeSelector;
    notifyListeners();
  }

  /// Clear the captured scope (e.g. when automation starts or step changes).
  void clearCapturedScope() {
    _capturedScopeSelector = null;
    notifyListeners();
  }

  /// Register right-click inspection callback.
  /// FIX: cancels any previous subscription before creating a new one,
  /// preventing listener accumulation on hot-reload or widget rebuilds.
  void listenRightClick(void Function(Map<String, dynamic>) onInfo) {
    _rightClickSub?.cancel();
    _rightClickSub = _webMessageBroadcast?.listen((msg) {
      try {
        final decoded = jsonDecode(msg as String) as Map;
        if (decoded['type'] == 'FB_RIGHT_CLICK') {
          final info =
              jsonDecode(decoded['payload'] as String) as Map<String, dynamic>;
          onInfo(info);
        } else if (decoded['type'] == 'FB_SCOPE_FOCUS') {
          final info =
              jsonDecode(decoded['payload'] as String) as Map<String, dynamic>;
          final sel = info['scopeSelector'] as String? ?? '';
          if (sel.isNotEmpty) setScopeFromRightClick(sel);
        }
      } catch (_) {}
    });
  }

  // ── Post Watcher ────────────────────────────────────────────────────────────

  Future<void> startPostWatcher() async {
    if (_webviewController == null || _postUrl.isEmpty) return;
    await stopPostWatcher();

    final escapedUrl = _postUrl.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

    // Build JS with string concatenation to avoid Dart raw-string escaping issues
    final js = '''
(function() {
  if (window.__fbPostWatcher) { window.__fbPostWatcher.disconnect(); window.__fbPostWatcher = null; }
  window.__fbPostWatcherActive = true;
  const POST_URL = '$escapedUrl';
  function extractToken(url) {
    if (!url) return null;
    const pp = [
      /\\/permalink\\/(\\d+)/,
      /[?&]fbid=(\\d+)/,
      /[?&]story_fbid=(\\d+)/,
      /\\/posts\\/([\\w]+)/,
      /\\/reel\\/(\\d+)/,
      /(pfbid[A-Za-z0-9]+)/,
    ];
    for (const p of pp) { const m = url.match(p); if (m) return m[1]; }
    return null;
  }
  const TARGET_TOKEN = extractToken(POST_URL);
  function isVisible(el) {
    if (!el || el.offsetWidth===0 || el.offsetHeight===0) return false;
    const r = el.getBoundingClientRect();
    return r.width>0 && r.height>0;
  }
  const SHARE_ARIA = [
    'Send this to friends or post it on your profile.',
    'Send this to friends or post it on your profile',
    'Share','Share post','Share this post',
    '\\u0db6\\u0dd9\\u0daf\\u0dcf\\u0d9c\\u0db1\\u0dca\\u0db1',
    '\\u0db6\\u0dd9\\u0daf\\u0dcf \\u0d9c\\u0db1\\u0dca\\u0db1',
  ];
  function findShareBtn(scope) {
    for (const lbl of SHARE_ARIA) {
      const el = scope.querySelector('[aria-label="'+lbl+'"]');
      if (el && isVisible(el)) return el;
    }
    return null;
  }
  function getPostScope() {
    const isolated = document.querySelector('[data-fbi-z]');
    if (isolated) return isolated;
    const pl = document.querySelector('[data-pagelet="PermalinkLayout"],[data-pagelet="SingleStory"]');
    if (pl) return pl;
    if (TARGET_TOKEN) {
      const cards = [...document.querySelectorAll('[data-pagelet^="FeedUnit"],[role="article"],article')].filter(isVisible);
      for (const c of cards) { if ((c.innerHTML||'').includes(TARGET_TOKEN)) return c; }
    }
    const arts = [...document.querySelectorAll('[role="article"],article')].filter(isVisible);
    if (arts.length >= 1) return arts[0];
    return null;
  }
  function tryDetect() {
    const scope = getPostScope();
    if (!scope) return false;
    const btn = findShareBtn(scope);
    if (!btn) return false;
    if (window.__fbPostWatcher) { window.__fbPostWatcher.disconnect(); window.__fbPostWatcher = null; }
    window.__fbPostWatcherActive = false;
    try {
      window.chrome.webview.postMessage(JSON.stringify({
        type:'FB_POST_DETECTED',
        payload: JSON.stringify({ found:true, url: window.location.href })
      }));
    } catch(e) {}
    return true;
  }
  if (tryDetect()) return;
  window.__fbPostWatcher = new MutationObserver(function() {
    if (!window.__fbPostWatcherActive) { window.__fbPostWatcher&&window.__fbPostWatcher.disconnect(); return; }
    tryDetect();
  });
  window.__fbPostWatcher.observe(document.body, { childList:true, subtree:true });
  setTimeout(function() {
    if (window.__fbPostWatcher) { window.__fbPostWatcher.disconnect(); window.__fbPostWatcher=null; }
    window.__fbPostWatcherActive = false;
  }, 30000);
})();
''';

    await _webviewController!.executeScript(js);

    _postDetectSub = _webMessageBroadcast?.listen((msg) {
      try {
        final decoded = jsonDecode(msg as String) as Map;
        if (decoded['type'] == 'FB_POST_DETECTED') {
          _postDetectSub?.cancel();
          _postDetectSub = null;
          _postWatcherActive = false;
          notifyListeners();
          if (!isRunning && _status == AutomationStatus.idle) {
            startAutomation();
          }
        }
      } catch (_) {}
    });

    _postWatcherActive = true;
    _setStatus(AutomationStatus.idle,
        '\u{1F441} Watching for post... (auto-starts when detected)');
  }

  Future<void> stopPostWatcher() async {
    _postDetectSub?.cancel();
    _postDetectSub = null;
    _postWatcherActive = false;
    try {
      await _webviewController?.executeScript(
          "(function(){ if(window.__fbPostWatcher){window.__fbPostWatcher.disconnect();window.__fbPostWatcher=null;} window.__fbPostWatcherActive=false; })();");
    } catch (_) {}
    notifyListeners();
  }

  AutomationStatus _status = AutomationStatus.idle;
  String _statusMessage = 'Ready to automate';
  String _postUrl = '';
  int _clickDelayMs = kMinDelayMs;
  int _lastGroupIndex = 0;
  int _groupsPerRun = 10;
  List<ShareResult> _history = [];
  bool _webViewReady = false;
  List<PageElement> _scannedElements = [];
  bool _scanning = false;
  bool _stopRequested =
      false; // set by stopAutomation() to cancel _waitForPageLoad
  // Req 5: label injected by TemplateProvider when a template is activated.
  String _activeTemplateLabel = '';

  AutomationStatus get status => _status;
  // Full status prefixed with the active template name when set.
  String get statusMessage => _activeTemplateLabel.isEmpty
      ? _statusMessage
      : '$_activeTemplateLabel  |  $_statusMessage';
  String get postUrl => _postUrl;
  int get clickDelayMs => _clickDelayMs;
  int get lastGroupIndex => _lastGroupIndex;
  int get groupsPerRun => _groupsPerRun;
  List<ShareResult> get history => List.unmodifiable(_history);
  bool get webViewReady => _webViewReady;
  bool get scanning => _scanning;
  List<PageElement> get scannedElements => List.unmodifiable(_scannedElements);
  bool get isRunning =>
      _status == AutomationStatus.running ||
      _status == AutomationStatus.navigating;

  AutomationProvider() {
    _loadPrefs();
  }

  // ── Prefs ──────────────────────────────────────────────────────────────────

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _lastGroupIndex = prefs.getInt(_indexKey) ?? 0;
    _clickDelayMs = prefs.getInt(_delayKey) ?? kMinDelayMs;
    _groupsPerRun = prefs.getInt(_groupsKey) ?? 10;
    _postUrl = prefs.getString(_urlKey) ?? '';

    // FIX: persist history across restarts
    final raw = prefs.getString(_historyKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _history = list
            .map(
                (e) => ShareResult.fromPersistedJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _history = [];
      }
    }

    notifyListeners();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_indexKey, _lastGroupIndex);
    await prefs.setInt(_delayKey, _clickDelayMs);
    await prefs.setInt(_groupsKey, _groupsPerRun);
    await prefs.setString(_urlKey, _postUrl);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_history.map((r) => r.toJson()).toList());
    await prefs.setString(_historyKey, encoded);
  }

  // ── Setters ────────────────────────────────────────────────────────────────

  void setPostUrl(String url) {
    _postUrl = url.trim();
    _savePrefs();
    notifyListeners();
  }

  void setClickDelay(int ms) {
    // FIX: clamp matches kMinDelayMs so UI and JS are always in sync
    _clickDelayMs = ms.clamp(kMinDelayMs, kMaxDelayMs);
    _savePrefs();
    notifyListeners();
  }

  void setGroupsPerRun(int count) {
    _groupsPerRun = count.clamp(1, 50);
    _savePrefs();
    notifyListeners();
  }

  void setWebViewReady(bool ready) {
    _webViewReady = ready;
    notifyListeners();
  }

  /// Called by TemplateProvider/TemplatePanel when the active template changes.
  /// Kept for backward compatibility — prefer setActiveTemplate() for full data.
  void setActiveTemplateLabel(String label) {
    _activeTemplateLabel = label;
    notifyListeners();
  }

  /// Stop the automation loop. Sets status to idle so the auto-loop
  /// condition fails and no further runs are triggered.
  void stopAutomation() {
    _stopRequested = true;
    _setStatus(AutomationStatus.idle, 'Automation stopped by user.');
    unawaited(_restoreIsolation());
  }

  Future<void> resetGroupIndex() async {
    _lastGroupIndex = 0;
    await _savePrefs();
    await _webviewController?.executeScript(
        "localStorage.removeItem('fb_share_group_last_index');");
    notifyListeners();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  /// "Go to Post" — simply navigates the WebView to the saved post URL.
  /// Isolation is NOT done here; it runs inside startAutomation() so the
  /// user can freely scroll / inspect the page before starting.
  Future<void> navigateToPost() async {
    if (_webviewController == null || _postUrl.isEmpty) return;
    _setStatus(AutomationStatus.navigating, 'Navigating to post...');
    await _webviewController!.loadUrl(_postUrl);
    _setStatus(AutomationStatus.idle, 'Post loaded. Press Start Automation.');
  }

  // ── Post isolation ─────────────────────────────────────────────────────────

  /// Loads fb_post_isolate.js as a string (cached after first load).
  String? _isolateJsCache;
  Future<String?> _loadIsolateJs() async {
    if (_isolateJsCache != null) return _isolateJsCache;
    try {
      _isolateJsCache =
          await rootBundle.loadString('assets/scripts/fb_post_isolate.js');
      return _isolateJsCache;
    } catch (e) {
      debugPrint('⚠️  fb_post_isolate.js load failed: $e');
      return null;
    }
  }

  /// Waits until WebView navigation is fully complete (navigationCompleted),
  /// then waits an extra [extraMs] for JS-rendered content to settle.
  ///
  /// Times out after [timeoutMs] and returns false.
  Future<bool> _waitForPageLoad({
    int timeoutMs = 15000,
    int extraMs = 2000,
  }) async {
    final ctrl = _webviewController;
    if (ctrl == null) return false;

    final completer = Completer<bool>();
    StreamSubscription<LoadingState>? sub;

    // Timeout: complete with false if page never finishes loading
    Future.delayed(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) completer.complete(false);
    });

    sub = ctrl.loadingState.listen((state) {
      if (_stopRequested && !completer.isCompleted) {
        sub?.cancel();
        completer.complete(false);
        return;
      }
      if (state == LoadingState.navigationCompleted) {
        sub?.cancel();
        // Extra settle time so JS-rendered feed cards appear in the DOM.
        // Also bail early if stop was requested during the settle window.
        Future.delayed(Duration(milliseconds: extraMs), () {
          if (!completer.isCompleted) {
            completer.complete(!_stopRequested);
          }
        });
      }
    });

    final result = await completer.future;
    await sub.cancel();
    return result;
  }

  /// Navigates to [_postUrl], waits for full page load, then hides all feed
  /// articles except the target post. Returns the number of items hidden.
  ///
  /// Called at the very start of startAutomation() — the user never needs to
  /// press "Go to Post" separately.
  Future<int> _navigateAndIsolate() async {
    final ctrl = _webviewController;
    if (ctrl == null || _postUrl.isEmpty) return 0;

    // ── 1. Subscribe to loadingState BEFORE calling loadUrl ─────────────────
    _setStatus(AutomationStatus.navigating, '🔗 Opening post...');
    final loadFuture = _waitForPageLoad(timeoutMs: 20000, extraMs: 1500);

    // ── 2. Register cover overlay + Navigate ────────────────────────────────

    // ── Register cover overlay via addScriptToExecuteOnDocumentCreated ──────
    // This fires at document-created time (before any FB React renders),
    // giving us a full-screen cover before the feed appears.
    // Guard: only activates when localStorage key '__fbAutoCover' = '1',
    // which we set just before loadUrl and clear after isolation.
    const coverScript = r'''
(function() {
  try {
    if (localStorage.getItem('__fbAutoCover') !== '1') return;
  } catch(e) { return; }

  if (document.getElementById('__fb_cover__')) return;

  function attachCover() {
    if (document.getElementById('__fb_cover__')) return;
    var cover = document.createElement('div');
    cover.id = '__fb_cover__';
    cover.style.cssText = [
      'position:fixed','inset:0','z-index:2147483647',
      'background:#0f1117',
      'display:flex','flex-direction:column',
      'align-items:center','justify-content:center','gap:16px',
      'pointer-events:all',
    ].join(';');

    var sp = document.createElement('div');
    sp.style.cssText = [
      'width:44px','height:44px',
      'border:3px solid rgba(255,255,255,0.12)',
      'border-top-color:#4f6ef7','border-radius:50%',
      'animation:__fbSpin 0.7s linear infinite',
    ].join(';');

    var lb = document.createElement('div');
    lb.id = '__fb_cover_label__';
    lb.style.cssText = 'color:rgba(255,255,255,0.5);font-size:13px;' +
      'font-family:system-ui,sans-serif;letter-spacing:0.3px;';
    lb.textContent = 'Locating post\u2026';

    if (!document.getElementById('__fb_cover_style__')) {
      var st = document.createElement('style');
      st.id = '__fb_cover_style__';
      st.textContent = '@keyframes __fbSpin{to{transform:rotate(360deg)}}';
      (document.head || document.documentElement).appendChild(st);
    }
    cover.appendChild(sp);
    cover.appendChild(lb);
    (document.body || document.documentElement).appendChild(cover);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', attachCover, {once:true});
  } else {
    attachCover();
  }

  window.__fbRemoveCover = function(msg) {
    try { localStorage.removeItem('__fbAutoCover'); } catch(e) {}
    var lb = document.getElementById('__fb_cover_label__');
    if (lb && msg) lb.textContent = msg;
    var c = document.getElementById('__fb_cover__');
    if (!c) return;
    c.style.transition = 'opacity 0.3s';
    c.style.opacity = '0';
    setTimeout(function() { if (c.parentNode) c.parentNode.removeChild(c); }, 320);
  };
})();
''';

    await ctrl.addScriptToExecuteOnDocumentCreated(coverScript);

    // Arm the guard key — cover script checks this on document-created
    try {
      await ctrl.executeScript(
          "try{localStorage.setItem('__fbAutoCover','1');}catch(e){}");
    } catch (_) {}

    await ctrl.loadUrl(_postUrl);

    // ── 4. Await page load ───────────────────────────────────────────────────
    _setStatus(AutomationStatus.navigating, '⏳ Page loading...');
    final loaded = await loadFuture;
    if (_stopRequested) {
      unawaited(ctrl.executeScript('window.__fbRemoveCover?.();'));
      return 0;
    }
    if (!loaded) {
      _setStatus(
          AutomationStatus.navigating, '⚠️ Page load timeout — continuing...');
    }

    // ── 5. Inject the isolate helper ────────────────────────────────────────
    final isolateJs = await _loadIsolateJs();
    if (isolateJs == null) {
      unawaited(ctrl.executeScript('window.__fbRemoveCover?.();'));
      return 0;
    }

    try {
      await ctrl.executeScript(isolateJs);
    } catch (e) {
      debugPrint('⚠️  isolate helper inject: $e');
      unawaited(ctrl.executeScript('window.__fbRemoveCover?.();'));
      return 0;
    }

    // ── 6. Call __fbIsolatePost(url) via Promise → postMessage bridge ────────
    // __fbIsolatePost() waits (MutationObserver) for feed cards to appear,
    // identifies the target post, hides everything else, then removes the
    // full-screen cover so only the target post is visible.
    if (_webMessageBroadcast == null) {
      unawaited(ctrl.executeScript('window.__fbRemoveCover?.();'));
      return 0;
    }
    if (_stopRequested) {
      unawaited(ctrl.executeScript('window.__fbRemoveCover?.();'));
      return 0;
    }

    _setStatus(AutomationStatus.navigating, '🔍 Detecting target post...');

    final escapedUrl = _postUrl.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

    final isolateCallJs = """
window.__fbIsolatePost('$escapedUrl', 10000).then(function(r) {
  // Cover is removed inside __fbIsolatePost on success.
  // Remove it here too as a fallback for the failure path.
  if (!r.success) {
    window.__fbRemoveCover && window.__fbRemoveCover('Could not isolate — showing page');
  }
  window.chrome.webview.postMessage(
    JSON.stringify({ type: 'FB_ISOLATE_RESULT', payload: r })
  );
}).catch(function(e) {
  window.__fbRemoveCover && window.__fbRemoveCover('Error — showing page');
  window.chrome.webview.postMessage(
    JSON.stringify({ type: 'FB_ISOLATE_RESULT',
      payload: { success: false, error: String(e) } })
  );
});
""";

    try {
      final resultFuture = _webMessageBroadcast!
          .where((msg) {
            try {
              return (jsonDecode(msg as String) as Map)['type'] ==
                  'FB_ISOLATE_RESULT';
            } catch (_) {
              return false;
            }
          })
          .first
          .timeout(const Duration(seconds: 15));

      await ctrl.executeScript(isolateCallJs);
      final rawMsg = await resultFuture;

      final outer = jsonDecode(rawMsg as String) as Map<String, dynamic>;
      final payload = outer['payload'];
      Map<String, dynamic> result;
      if (payload is Map<String, dynamic>) {
        result = payload;
      } else if (payload is String) {
        result = jsonDecode(payload) as Map<String, dynamic>;
      } else {
        result = {'success': false, 'error': 'unexpected payload type'};
      }

      if (result['success'] == true) {
        final hidden = (result['hiddenCount'] as num?)?.toInt() ?? 0;
        _setStatus(AutomationStatus.running,
            '🔒 Feed isolated — $hidden post(s) hidden. Starting...');
        return hidden;
      } else {
        final err = result['error'] as String? ?? 'unknown';
        debugPrint('⚠️  __fbIsolatePost: $err');
        _setStatus(AutomationStatus.running,
            '⚠️  Could not isolate ($err). Continuing anyway...');
        return 0;
      }
    } catch (e) {
      debugPrint('⚠️  _navigateAndIsolate result: $e');
      unawaited(ctrl.executeScript('window.__fbRemoveCover?.();'));
      _setStatus(AutomationStatus.running,
          '⚠️  Isolation timed out. Continuing anyway...');
      return 0;
    }
  }

  /// Restores all hidden feed posts. Called after automation finishes or stops.
  Future<void> _restoreIsolation() async {
    if (_webviewController == null) return;
    try {
      await _webviewController!.executeScript('window.__fbRestorePost?.();');
    } catch (_) {}
  }

  Future<void> navigateToFacebook() async {
    if (_webviewController == null) return;
    await _webviewController!.loadUrl('https://www.facebook.com');
  }

  // ── Deep Scan ──────────────────────────────────────────────────────────────

  Future<void> deepScan() async {
    if (_webviewController == null) return;
    _scanning = true;
    _scannedElements = [];
    notifyListeners();

    // FIX: load scan script from asset instead of inline string
    String js;
    try {
      js = await rootBundle.loadString('assets/scripts/deep_scan.js');
    } catch (_) {
      // Fallback to inline if asset not found (shouldn't happen in release)
      js = _deepScanInline;
    }

    try {
      final raw = await _webviewController!.executeScript(js);
      if (raw == null) {
        _scanning = false;
        notifyListeners();
        return;
      }
      String clean = raw.toString();
      if (clean.startsWith('"') && clean.endsWith('"')) {
        clean = jsonDecode(clean) as String;
      }
      final list = jsonDecode(clean) as List;
      _scannedElements = list
          .map((e) => PageElement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _scannedElements = [
        PageElement(
            text: 'Scan error: $e',
            ariaLabel: '',
            testId: '',
            role: '',
            tag: '',
            index: '-1')
      ];
    }

    _scanning = false;
    notifyListeners();
  }

  // ── Click / Highlight helpers ──────────────────────────────────────────────

  Future<String> clickByIndex(String index) async {
    if (_webviewController == null) return 'WebView not ready';
    final js = '''
(function(){
  const el = (window.__scanEls || [])[${int.tryParse(index) ?? 0}];
  if (!el) return 'NOT FOUND at index $index';
  el.scrollIntoView({behavior:'smooth', block:'center'});
  ['mouseover','mousedown','mouseup','click'].forEach(n =>
    el.dispatchEvent(new MouseEvent(n, {bubbles:true, cancelable:true, view:window})));
  const label = el.getAttribute('aria-label') ||
                (el.innerText||'').trim().substring(0,40);
  return 'CLICKED: ' + label;
})();
''';
    final result = await _webviewController!.executeScript(js);
    return result?.toString() ?? 'null';
  }

  Future<void> highlightByIndex(String index) async {
    if (_webviewController == null) return;
    final js = '''
(function(){
  document.querySelectorAll('.__fb_hl__').forEach(e => {
    e.style.outline = '';
    e.style.backgroundColor = '';
    e.classList.remove('__fb_hl__');
  });
  const el = (window.__scanEls || [])[${int.tryParse(index) ?? 0}];
  if (!el) return;
  el.classList.add('__fb_hl__');
  el.style.outline = '3px solid #f00';
  el.style.backgroundColor = 'rgba(255,0,0,0.1)';
  el.scrollIntoView({behavior:'smooth', block:'center'});
})();
''';
    await _webviewController!.executeScript(js);
  }

  Future<String> clickByAria(String ariaLabel) async {
    if (_webviewController == null) return 'WebView not ready';
    final escaped = ariaLabel.replaceAll('"', '\\"');
    final js = '''
(function(){
  const el = document.querySelector('[aria-label="$escaped"]');
  if (!el) return 'NOT FOUND: $escaped';
  ['mouseover','mousedown','mouseup','click'].forEach(n =>
    el.dispatchEvent(new MouseEvent(n, {bubbles:true, cancelable:true, view:window})));
  return 'CLICKED: $escaped';
})();
''';
    final result = await _webviewController!.executeScript(js);
    return result?.toString() ?? 'null';
  }

  Future<String> clickByText(String text) async {
    if (_webviewController == null) return 'WebView not ready';
    final safe = text
        .replaceAll("'", "\\'")
        .substring(0, text.length > 60 ? 60 : text.length);
    final js = '''
(function(){
  const all = document.querySelectorAll(
    '[role="button"],button,[tabindex="0"],[aria-label],' +
    '[role="menuitem"],[role="option"]');
  for (const el of all) {
    const t = (el.innerText||el.textContent||'').trim();
    const a = el.getAttribute('aria-label')||'';
    if (t.toLowerCase().includes('${safe.toLowerCase()}') ||
        a.toLowerCase().includes('${safe.toLowerCase()}')) {
      ['mouseover','mousedown','mouseup','click'].forEach(n =>
        el.dispatchEvent(new MouseEvent(n, {bubbles:true, cancelable:true, view:window})));
      return 'CLICKED: '+(a||t).substring(0,60);
    }
  }
  return 'NOT FOUND: $safe';
})();
''';
    final result = await _webviewController!.executeScript(js);
    return result?.toString() ?? 'null';
  }

  // ── Step Debug (only exposed in debug builds) ──────────────────────────────

  Future<String> stepClickShare() async {
    if (_webviewController == null) return 'WebView not ready';
    const js = r'''
(function(){
  const fire = el => ['mouseover','mousedown','mouseup','click'].forEach(n=>
    el.dispatchEvent(new MouseEvent(n,{bubbles:true,cancelable:true,view:window})));

  // Mirrors the same priority chain as findShareButton in the main automation.
  const SHARE_ARIA_EXACT = [
    'send this to friends or post it on your profile',
    'share','share post','share this post',
    'බෙදාගන්න','බෙදා ගන්න',
  ];
  const SHARE_TEXT_EXACT = ['Share','බෙදාගන්න','බෙදා ගන්න'];

  function isClickableRoot(el){
    const tag=el.tagName.toLowerCase();
    if(tag==='span'||tag==='i'||tag==='svg'||tag==='path') return false;
    const role=(el.getAttribute('role')||'').toLowerCase();
    if(role==='button'||role==='link') return true;
    if(tag==='button'||tag==='a') return true;
    if((tag==='div'||tag==='li')&&el.getAttribute('tabindex')!==null) return true;
    return false;
  }
  function isExactShareText(el){
    const raw=(el.innerText||'').trim();
    if(/\d/.test(raw)) return false;
    if(/[·•|]/.test(raw)) return false;
    if(raw.length===0||raw.length>30) return false;
    return SHARE_TEXT_EXACT.some(t=>raw.toLowerCase()===t.toLowerCase());
  }
  function hasSvgIcon(el){ return !!(el.querySelector('svg')); }
  function isVisible(el){
    if(!el||el.offsetWidth===0||el.offsetHeight===0) return false;
    const r=el.getBoundingClientRect();
    return r.width>0&&r.height>0;
  }

  const allEls=[...document.querySelectorAll(
    'div[role="button"],button,a[role="button"],[tabindex="0"]')]
    .filter(isClickableRoot).filter(isVisible);

  // P1: Exact aria-label — "Send this to friends or post it on your profile."
  for(const el of allEls){
    const a=(el.getAttribute('aria-label')||'').trim().toLowerCase();
    if(SHARE_ARIA_EXACT.includes(a)){
      fire(el); return 'P1: CLICKED aria="'+el.getAttribute('aria-label')+'"';
    }
  }
  // P2: aria starts with "share" + has SVG icon
  for(const el of allEls){
    const a=(el.getAttribute('aria-label')||'').toLowerCase();
    if(a.startsWith('share')&&!a.includes('comment')&&!a.includes('like')&&hasSvgIcon(el)){
      fire(el); return 'P2: CLICKED aria+icon="'+el.getAttribute('aria-label')+'"';
    }
  }
  // P3: Like→Comment→Share row, 3rd button
  const likeBtns=allEls.filter(el=>{
    const a=(el.getAttribute('aria-label')||'').toLowerCase();
    return a==='like'||a==='likes'||a.startsWith('like ');
  });
  for(const likeBtn of likeBtns){
    const row=likeBtn.closest('div[role="group"]')||likeBtn.parentElement?.parentElement;
    if(!row) continue;
    const rowBtns=[...row.querySelectorAll('div[role="button"],button,[tabindex="0"]')]
      .filter(b=>isClickableRoot(b)&&isVisible(b));
    if(rowBtns.length>=3){
      const third=rowBtns[2];
      if(/^\d/.test((third.innerText||'').trim())) continue;
      fire(third);
      return 'P3: CLICKED 3rd row btn aria="'+(third.getAttribute('aria-label')||'')+
             '" text="'+((third.innerText||'').trim().substring(0,30))+'"';
    }
  }
  // P4: Exact share text + SVG icon
  for(const el of allEls){
    if(isExactShareText(el)&&hasSvgIcon(el)){
      fire(el); return 'P4: CLICKED text+icon="'+((el.innerText||'').trim())+'"';
    }
  }
  // P5: Exact share text (no icon required)
  for(const el of allEls){
    if(isExactShareText(el)){
      fire(el); return 'P5: CLICKED exact-text="'+((el.innerText||'').trim())+'"';
    }
  }

  // Diagnostic
  const likeInfo=likeBtns.map(el=>{
    const row=el.closest('div[role="group"]')||el.parentElement?.parentElement;
    if(!row) return 'like btn: no row found';
    const btns=[...row.querySelectorAll('div[role="button"],button,[tabindex="0"]')]
      .filter(b=>isClickableRoot(b)&&isVisible(b));
    return 'Row has '+btns.length+' btns: '+btns.map((b,i)=>
      i+'[aria="'+(b.getAttribute('aria-label')||'none')+
      '" text="'+((b.innerText||'').trim().substring(0,20))+'"]').join(', ');
  });
  const shareRelated=[...document.querySelectorAll('[aria-label],[role="button"],button')]
    .filter(el=>{
      const a=(el.getAttribute('aria-label')||'').toLowerCase();
      const t=(el.innerText||'').trim().toLowerCase();
      return a.includes('share')||t.includes('share');
    }).slice(0,10).map(el=>
      'tag='+el.tagName.toLowerCase()+
      ' aria="'+(el.getAttribute('aria-label')||'')+
      '" text="'+((el.innerText||'').trim().substring(0,25))+'"'
    );
  return 'NOT FOUND.\nLike button rows:\n'+(likeInfo.join('\n')||'none')+
    '\n\nShare-related elements:\n'+shareRelated.join('\n');
})();
''';
    final result = await _webviewController!.executeScript(js);
    return result?.toString() ?? 'null';
  }

  Future<String> stepScanAfterClick() async {
    if (_webviewController == null) return 'WebView not ready';
    // Scans ALL current dialogs and reports their content — call this AFTER
    // manually clicking Share so we can see exactly what text FB shows.
    const js = r'''
(function(){
  const dialogs = [...document.querySelectorAll(
    '[role="dialog"],[aria-modal="true"],[role="menu"],[role="listbox"]'
  )].filter(d => d.offsetWidth > 0 && d.offsetHeight > 0);

  if (!dialogs.length) return 'NO DIALOGS VISIBLE on screen right now.';

  function zOf(el) {
    let z=0, c=el;
    while(c && c!==document.body){
      const zi=parseInt(window.getComputedStyle(c).zIndex);
      if(!isNaN(zi)&&zi>z) z=zi; c=c.parentElement;
    }
    return z;
  }

  return dialogs.map((d,i) => {
    const role  = d.getAttribute('role')||d.tagName;
    const modal = d.getAttribute('aria-modal')||'?';
    const z     = zOf(d);
    const w     = d.offsetWidth, h = d.offsetHeight;
    const rawTxt = (d.innerText||'').replace(/\s+/g,' ').trim().substring(0,300);
    const btns = [...d.querySelectorAll('div[role="button"],button,[tabindex="0"]')]
      .filter(b=>b.offsetWidth>0)
      .map(b=>{
        const t=(b.innerText||'').trim().replace(/\s+/g,' ').substring(0,40);
        const a=b.getAttribute('aria-label')||'';
        return '  BTN: text="'+t+'" aria="'+a+'"';
      }).slice(0,15).join('\n');
    return '── Dialog '+i+' ──\n'+
           'role='+role+' modal='+modal+' z='+z+' size='+w+'x'+h+'\n'+
           'text: '+rawTxt+'\n'+
           (btns||'  (no buttons)');
  }).join('\n\n');
})();
''';
    final result = await _webviewController!.executeScript(js);
    return result?.toString() ?? 'null';
  }

  // ── Active template steps (refreshed on template switch — Req 5) ──────────
  List<Map<String, dynamic>> _activeSteps = [];

  /// Called by TemplatePanel whenever the active template changes.
  /// Req 5: immediately refreshes search parameters so next run uses new template.
  void setActiveTemplate({
    required String label,
    required List<Map<String, dynamic>> steps,
    int? clickDelayMs,
    int? groupsPerRun,
  }) {
    _activeTemplateLabel = label;
    // steps map: {label, attributes:[{key,value}], fallbackText, scopeSelector}
    _activeSteps = steps;
    if (clickDelayMs != null) {
      _clickDelayMs = clickDelayMs.clamp(kMinDelayMs, kMaxDelayMs);
    }
    if (groupsPerRun != null) {
      _groupsPerRun = groupsPerRun.clamp(1, 50);
    }
    notifyListeners();
  }

  // ── Core Automation ────────────────────────────────────────────────────────

  Future<void> startAutomation() async {
    if (_webviewController == null) {
      _setStatus(AutomationStatus.error, 'WebView not initialised');
      return;
    }
    if (_postUrl.isEmpty) {
      _setStatus(AutomationStatus.error, 'Please enter a post URL first');
      return;
    }

    _stopRequested = false;
    _setStatus(AutomationStatus.running, 'Starting automation...');
    clearCapturedScope();

    // ── Navigate to the post URL and isolate the feed ─────────────────────
    // This replaces the separate "Go to Post" step: Start Automation always
    // navigates fresh, waits for the page to fully load, then hides every
    // feed article except the target post so Step 1's Share-button click
    // cannot accidentally hit a different post in the feed.
    await _navigateAndIsolate();

    // After navigate + isolate, ensure status is running so the while loop
    // enters. _navigateAndIsolate sets navigating then running internally,
    // but if isolation failed silently we might still be on navigating.
    if (_status == AutomationStatus.navigating) {
      _setStatus(AutomationStatus.running, '▶ Starting automation loop...');
    }

    // ── Bail out if user stopped during navigate ──────────────────────────
    if (_status != AutomationStatus.running) {
      await _restoreIsolation();
      return;
    }
    // Runs entirely in Dart — no page refresh between iterations.
    //
    // Each iteration:
    //   Step 1: Click Share button  (template step 0, or heuristic)
    //   Step 2: Click "Group" menu  (template step 1, or heuristic)
    //   Step 3: Select group[lastGroupIndex] from the modal list
    //   Step 4: Click Post button (FbStrings.postExact)
    //   → wait for modal close → increment index → back to Step 1
    //
    // Stops when: groupsPerRun reached | all groups done | user stops | error

    int sharesThisRun = 0;
    final List<Map<String, dynamic>> clickedGroups = [];
    final List<Map<String, dynamic>> failedGroups = [];

    while (
        _status == AutomationStatus.running && sharesThisRun < _groupsPerRun) {
      // ── Step 1: Share button ────────────────────────────────────────────
      _setStatus(AutomationStatus.running,
          '🔁 Run ${sharesThisRun + 1}/$_groupsPerRun — Step 1/4: Share button...');

      Map<String, dynamic> stepResult;

      if (_activeSteps.isNotEmpty) {
        // Use template step 0 (Share button)
        stepResult = await _runStep(_activeSteps[0]);
      } else {
        // Heuristic: inject the share-button-only JS
        stepResult = await _runShareButtonStep();
      }

      if (!_checkStepOk(stepResult, 'share_button')) break;
      await Future.delayed(Duration(milliseconds: _clickDelayMs));
      if (_status != AutomationStatus.running) break;

      // ── Linked post detection (after Share dialog opens) ────────────────
      // Inject the detector script now — the Share dialog is open and the
      // "From your link" section should be visible. This is detect-only:
      // no clicks, no navigation. Result is logged for verification.
      _setStatus(AutomationStatus.running,
          '🔍 Verifying linked post detection...');
      try {
        final detectorJs = await rootBundle
            .loadString('assets/scripts/fb_linked_post_detector.js');
        final detectorRaw =
            await _webviewController!.executeScript(detectorJs);
        debugPrint('[AutomationProvider] Linked post detector raw: $detectorRaw');
        if (detectorRaw != null && detectorRaw.contains('"success"')) {
          _setStatus(AutomationStatus.running,
              '✅ Linked post detected — proceeding to group menu...');
        } else {
          debugPrint('[AutomationProvider] Linked post not detected — continuing anyway');
        }
      } catch (e) {
        debugPrint('[AutomationProvider] Detector inject error: $e');
      }
      if (_status != AutomationStatus.running) break;

      // ── Step 2: Group menu option ───────────────────────────────────────
      _setStatus(AutomationStatus.running,
          '🔁 Run ${sharesThisRun + 1}/$_groupsPerRun — Step 2/4: Group menu...');

      if (_activeSteps.length >= 2) {
        stepResult = await _runStep(_activeSteps[1]);
      } else {
        stepResult = await _runGroupMenuStep();
      }

      if (!_checkStepOk(stepResult, 'group_menu')) break;
      await Future.delayed(Duration(milliseconds: _clickDelayMs));
      if (_status != AutomationStatus.running) break;

      // ── Step 3 + 4: Select group by index, then Post ────────────────────
      // This is always handled by the core JS (group list navigation +
      // compose modal + Post button are tightly coupled and can't be split).
      _setStatus(AutomationStatus.running,
          '🔁 Run ${sharesThisRun + 1}/$_groupsPerRun — Step 3/4: Group #${_lastGroupIndex + 1}...');

      final coreResult = await _runGroupSelectAndPost(_lastGroupIndex);

      if (coreResult == null) {
        // Timed out waiting for JS result
        _setStatus(AutomationStatus.error, '❌ JS result timeout');
        break;
      }

      final groupName = (coreResult['groupName'] as String?) ??
          'Group ${_lastGroupIndex + 1}';

      if (coreResult['success'] == true) {
        clickedGroups.add({'index': _lastGroupIndex, 'name': groupName});
        sharesThisRun++;
        _lastGroupIndex =
            (coreResult['nextRunStartIndex'] as int?) ?? (_lastGroupIndex + 1);
        await _savePrefs();

        _setStatus(AutomationStatus.running,
            '✅ Posted to "$groupName" ($sharesThisRun/$_groupsPerRun). Next: #${_lastGroupIndex + 1}');

        // Check if all groups are exhausted
        final total = (coreResult['totalGroupsFound'] as int?) ?? 0;
        if (total > 0 && _lastGroupIndex >= total) {
          _lastGroupIndex = 0;
          await _savePrefs();
          _setStatus(AutomationStatus.success,
              '🎉 All $total groups done! Resetting index.');
          break;
        }
      } else {
        // Step 3/4 failure — skip this group and continue if possible
        final errStep = coreResult['step'] as String? ?? 'unknown';
        final errMsg = coreResult['error'] as String? ?? 'Unknown error';
        failedGroups.add({
          'index': _lastGroupIndex,
          'name': groupName,
          'error': errMsg,
        });

        // Advance index so we don't retry the same group forever
        _lastGroupIndex =
            (coreResult['nextRunStartIndex'] as int?) ?? (_lastGroupIndex + 1);
        await _savePrefs();

        // Fatal steps stop the loop; skippable steps continue
        const skipableSteps = {
          'post_modal',
          'post_disabled',
          'post_confirm',
          'group_click',
          'pagination', // index >= total — reset and continue
        };

        // Auto-reset index when we've gone past all groups
        if (errStep == 'pagination') {
          _lastGroupIndex = 0;
          await _savePrefs();
          _setStatus(AutomationStatus.running,
              '🔄 All groups done, resetting index to #1. Continuing...');
          continue;
        }

        if (!skipableSteps.contains(errStep)) {
          _setStatus(AutomationStatus.error, '❌ [$errStep]: $errMsg');
          break;
        }

        _setStatus(AutomationStatus.running,
            '⚠️ Skipped "$groupName" [$errStep]. Continuing...');
      }

      // Inter-run delay
      await Future.delayed(Duration(milliseconds: _clickDelayMs));
      if (_status != AutomationStatus.running) break;
    }

    // ── Restore feed after automation ───────────────────────────────────────
    // Always restore hidden posts regardless of success / failure.
    await _restoreIsolation();

    // ── Persist history ─────────────────────────────────────────────────────
    final overallSuccess = clickedGroups.isNotEmpty;
    final result = ShareResult(
      success: overallSuccess,
      message: overallSuccess
          ? 'Shared to ${clickedGroups.length} group(s).'
          : 'No groups posted.',
      clickedGroups: clickedGroups,
      failedGroups: failedGroups,
      nextRunStartIndex: _lastGroupIndex,
      totalGroupsFound: (clickedGroups.length + failedGroups.length),
      timestamp: DateTime.now(),
    );
    _history.insert(0, result);
    if (_history.length > 50) _history = _history.sublist(0, 50);
    await _saveHistory();

    if (_status == AutomationStatus.running) {
      _setStatus(
        overallSuccess ? AutomationStatus.success : AutomationStatus.error,
        overallSuccess
            ? '✅ Done! Shared to ${clickedGroups.length} groups. Next: #${_lastGroupIndex + 1}'
            : '❌ Completed with errors. ${failedGroups.length} failed.',
      );
    }
  }

  /// Returns false and sets error status if step failed.
  bool _checkStepOk(Map<String, dynamic> result, String stepName) {
    if (result['success'] == true) return true;
    final err = result['error'] as String? ?? 'Unknown error';
    _setStatus(AutomationStatus.error, '❌ [$stepName]: $err');
    _history.insert(
        0,
        ShareResult(
          success: false,
          step: stepName,
          error: err,
          timestamp: DateTime.now(),
        ));
    _saveHistory();
    return false;
  }

  // ── Step helpers: heuristic Share button (no template) ────────────────────

  /// Runs the Share button heuristic as a standalone _runStep-compatible call.
  /// Reuses the same JS priority chain from stepClickShare() but posts result
  /// via FB_STEP_RESULT so it integrates with the new loop.
  Future<Map<String, dynamic>> _runShareButtonStep() async {
    if (_webviewController == null) {
      return {'success': false, 'error': 'WebView not ready'};
    }
    final broadcast = _webMessageBroadcast;
    if (broadcast == null) {
      return {'success': false, 'error': 'WebView stream not ready'};
    }

    // Build JS that finds+clicks Share button then posts FB_STEP_RESULT
    const js = r'''
(async function() {
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  function isVisible(el) {
    if (!el || el.offsetWidth===0 || el.offsetHeight===0) return false;
    // Also check computed style — catches display:none from clean-window isolation
    let cur = el;
    while (cur && cur !== document.body) {
      const s = window.getComputedStyle(cur);
      if (s.display==='none' || s.visibility==='hidden' || s.opacity==='0') return false;
      cur = cur.parentElement;
    }
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }
  function isClickableRoot(el) {
    const tag = el.tagName.toLowerCase();
    if (tag==='span'||tag==='i'||tag==='svg'||tag==='path') return false;
    const role = (el.getAttribute('role')||'').toLowerCase();
    return role==='button'||role==='link'||tag==='button'||tag==='a'||
           ((tag==='div'||tag==='li')&&el.getAttribute('tabindex')!==null);
  }
  const SHARE_ARIA = [
    'Send this to friends or post it on your profile.',
    'Send this to friends or post it on your profile',
    'share','Share','Share post','Share this post','බෙදාගන්න','බෙදා ගන්න',
  ];
  const SHARE_TEXT = ['Share','බෙදාගන්න','බෙදා ගන්න'];
  function isExactShareText(el) {
    const raw=(el.innerText||'').trim();
    if(/\d/.test(raw)) return false;
    if(/[·•|]/.test(raw)) return false;
    if(raw.length===0||raw.length>30) return false;
    return SHARE_TEXT.some(t=>raw.toLowerCase()===t.toLowerCase());
  }
  function hasSvg(el) { return !!(el.querySelector('svg')); }

  // Snapshot pre-click dialogs
  const preDlg = new Set([...document.querySelectorAll('[role="dialog"],[aria-modal="true"]')]
    .filter(d=>isVisible(d)));

  function hasNewDialog() {
    return [...document.querySelectorAll('[role="dialog"],[aria-modal="true"]')]
      .some(d=>isVisible(d)&&!preDlg.has(d));
  }

  // Find the target post scope — works with or without isolation
  function getSearchScope() {
    // 1. Isolation succeeded: data-fbi-z marks the elevated target card
    const isolated = document.querySelector('[data-fbi-z]');
    if (isolated) return isolated;

    // 2. Permalink/single-story pagelet
    const permalink = document.querySelector(
      '[data-pagelet="PermalinkLayout"],[data-pagelet="SingleStory"]');
    if (permalink) return permalink;

    // 3. Single-post URL: find the card whose innerHTML contains the post token
    const url = window.location.href;
    const postMatch = url.match(
      /\/(posts|permalink|reel|videos|photo)\/([A-Za-z0-9]+)|(pfbid[A-Za-z0-9]+)|[?&](?:fbid|story_fbid)=(\d+)/);
    if (postMatch) {
      const token = postMatch[2] || postMatch[3] || postMatch[4];
      if (token) {
        const cards = [...document.querySelectorAll(
          '[data-pagelet^="FeedUnit"],[role="article"],article')].filter(isVisible);
        for (const c of cards) {
          if ((c.innerHTML || '').includes(token)) return c;
        }
      }
      const arts = [...document.querySelectorAll('[role="article"],article')].filter(isVisible);
      if (arts.length > 0) return arts[0];
    }

    // 4. Feed page with only one visible FeedUnit
    const units = [...document.querySelectorAll('[data-pagelet^="FeedUnit"]')].filter(isVisible);
    if (units.length === 1) return units[0];

    // 5. Mobile feed layout — no pagelet/article wrappers, search whole document
    return document;
  }

  // Mobile mode: share action may open a bottom sheet / inline share panel
  // instead of a [role="dialog"]. Detect both cases.
  function hasShareOpened() {
    // Classic: new dialog appeared
    if ([...document.querySelectorAll('[role="dialog"],[aria-modal="true"]')]
        .some(d => isVisible(d) && !preDlg.has(d))) return true;
    // Mobile bottom sheet: element with known share-sheet indicators
    const sheets = document.querySelectorAll(
      '[data-testid="share_dialog"],[data-testid="shareDialogRoot"],' +
      '[aria-label*="Share"],[aria-label*="share"],[aria-label*="බෙදා"]');
    for (const s of sheets) {
      if (isVisible(s) && !preDlg.has(s)) return true;
    }
    // Mobile inline: "From your link" text appearing = share panel opened
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
    let node;
    while ((node = walker.nextNode())) {
      const t = (node.nodeValue || '').trim().toLowerCase();
      if (t.indexOf('from your link') !== -1 || t.indexOf('ඔබේ සබැඳියෙන්') !== -1) return true;
    }
    return false;
  }

  async function tryClick(el) {
    el.focus();
    el.click();
    await sleep(600);
    if(hasShareOpened()) return true;
    // Synthetic event fallback
    ['mousedown','mouseup','click'].forEach(n=>
      el.dispatchEvent(new MouseEvent(n,{bubbles:true,cancelable:true,view:window})));
    await sleep(700);
    if(hasShareOpened()) return true;
    // Touch event fallback for mobile layout
    ['touchstart','touchend'].forEach(n=>
      el.dispatchEvent(new TouchEvent(n,{bubbles:true,cancelable:true})));
    await sleep(600);
    return hasShareOpened();
  }

  const deadline = Date.now() + 10000;
  while(Date.now() < deadline) {
    const scope = getSearchScope();
    const all = [...scope.querySelectorAll(
      'div[role="button"],button,a[role="button"],[tabindex="0"],a[href]')]
      .filter(isClickableRoot).filter(isVisible);

    // Priority 1: aria-label exact match
    for(const lbl of SHARE_ARIA) {
      const el = scope.querySelector('[aria-label="'+lbl+'"]');
      if(el&&isClickableRoot(el)&&isVisible(el)) {
        const ok = await tryClick(el);
        window.chrome.webview.postMessage(JSON.stringify({type:'FB_STEP_RESULT',
          payload:JSON.stringify(ok
            ? {success:true,clicked:'Share: '+lbl}
            : {success:false,error:'Share click did not open share panel (aria: '+lbl+')'})}));
        return;
      }
    }

    // Priority 2: text+svg match
    for(const el of all) {
      if(isExactShareText(el)&&hasSvg(el)) {
        const ok = await tryClick(el);
        window.chrome.webview.postMessage(JSON.stringify({type:'FB_STEP_RESULT',
          payload:JSON.stringify(ok
            ? {success:true,clicked:'Share (text+svg)'}
            : {success:false,error:'Share text+svg click did not open share panel'})}));
        return;
      }
    }

    // Priority 3: text-only match
    for(const el of all) {
      if(isExactShareText(el)) {
        const ok = await tryClick(el);
        window.chrome.webview.postMessage(JSON.stringify({type:'FB_STEP_RESULT',
          payload:JSON.stringify(ok
            ? {success:true,clicked:'Share (text)'}
            : {success:false,error:'Share text click did not open share panel'})}));
        return;
      }
    }

    // Priority 4: Mobile layout — look for the share icon button in the
    // post action bar (3rd button after Like and Comment)
    // In mobile feed the share button has no text, only an SVG arrow icon.
    const likeBtn = document.querySelector(
      '[aria-label="Like"],[aria-label="Likes"],[aria-label^="Like "],' +
      '[aria-label="ම ් ▶"]');
    if (likeBtn) {
      const actionRow = likeBtn.closest('div[role="group"],ul,div');
      if (actionRow) {
        const actionBtns = [...actionRow.querySelectorAll(
          '[role="button"],[tabindex="0"],button,a')]
          .filter(b => isVisible(b) && actionRow.contains(b));
        // Share is typically the 3rd button (Like, Comment, Share)
        if (actionBtns.length >= 3) {
          const shareBtn = actionBtns[2];
          const ok = await tryClick(shareBtn);
          window.chrome.webview.postMessage(JSON.stringify({type:'FB_STEP_RESULT',
            payload:JSON.stringify(ok
              ? {success:true,clicked:'Share (mobile action bar 3rd btn)'}
              : {success:false,error:'Mobile action bar share click did not open share panel'})}));
          return;
        }
      }
    }

    await sleep(400);
  }
  window.chrome.webview.postMessage(JSON.stringify({type:'FB_STEP_RESULT',
    payload:JSON.stringify({success:false,
      error:'Share button not found after 10s. Mobile layout detected — use Inspector to find the share button aria-label.'})}));
})().catch(e=>window.chrome.webview.postMessage(JSON.stringify({type:'FB_STEP_RESULT',
  payload:JSON.stringify({success:false,error:e.toString()})})));
''';

    return _awaitStepResult(js, timeoutMs: 12000);
  }

  /// Heuristic Group menu option step (no template).
  Future<Map<String, dynamic>> _runGroupMenuStep() async {
    if (_webviewController == null) {
      return {'success': false, 'error': 'WebView not ready'};
    }

    final groupLabelsJs = FbStrings.toJsArray(FbStrings.shareToGroupExact);
    final js = '''
(async function() {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const GROUP_LABELS = $groupLabelsJs;
  const IGNORE = ['messenger','whatsapp','your story','copy link',
    'facebook story','news feed','friends','instagram','telegram',
    'twitter','more options','email'];
  function normText(el) {
    return (el.innerText||'').replace(/[^\\w\\s\\u0D80-\\u0DFF]/g,'')
      .replace(/\\s+/g,' ').trim();
  }
  function isIgnored(el) {
    const t=normText(el).toLowerCase();
    return IGNORE.some(x=>t===x);
  }
  function isVisible(el) {
    if(!el||el.offsetWidth===0||el.offsetHeight===0) return false;
    const r=el.getBoundingClientRect();
    return r.width>0&&r.height>0&&r.top>=-10&&r.bottom<=window.innerHeight+80;
  }

  const deadline = Date.now() + 8000;
  while(Date.now() < deadline) {
    const dialogs=[...document.querySelectorAll(
      '[role="dialog"],[aria-modal="true"],[role="menu"],[role="listbox"]')]
      .filter(d=>d.offsetWidth>0&&d.offsetHeight>0);
    for(const scope of dialogs) {
      const cands=[...scope.querySelectorAll(
        'div[role="button"],button,li[role="option"],[tabindex="0"]')]
        .filter(el=>isVisible(el)&&!isIgnored(el));
      for(const el of cands) {
        const t=normText(el);
        if(GROUP_LABELS.some(lbl=>t.toLowerCase()===lbl.toLowerCase()||
           (el.getAttribute('aria-label')||'').toLowerCase()===lbl.toLowerCase())) {
          const r=el.getBoundingClientRect();
          const cx=r.left+r.width/2,cy=r.top+r.height/2;
          el.focus();
          ['mousedown','mouseup','click'].forEach(n=>
            el.dispatchEvent(new MouseEvent(n,{bubbles:true,cancelable:true,
              view:window,clientX:cx,clientY:cy})));
          window.chrome.webview.postMessage(JSON.stringify({type:'FB_STEP_RESULT',
            payload:JSON.stringify({success:true,clicked:t})}));
          return;
        }
      }
    }
    await sleep(300);
  }
  window.chrome.webview.postMessage(JSON.stringify({type:'FB_STEP_RESULT',
    payload:JSON.stringify({success:false,
      error:'Group menu button not found after 8s.'})}));
})().catch(e=>window.chrome.webview.postMessage(JSON.stringify({type:'FB_STEP_RESULT',
  payload:JSON.stringify({success:false,error:e.toString()})})));
''';

    return _awaitStepResult(js, timeoutMs: 12000);
  }

  Future<Map<String, dynamic>?> _runGroupSelectAndPost(int groupIndex) async {
    if (_webviewController == null) return null;
    final broadcast = _webMessageBroadcast;
    if (broadcast == null) return null;

    final postWords = FbStrings.toJsArray(FbStrings.postExact);

    // ── Phase 1: Ping test — verify postMessage bridge works ─────────────────
    // If this times out, the WebView2 message bridge is unavailable.
    const pingJs = '''
(function(){
  try {
    window.chrome.webview.postMessage(JSON.stringify({
      type:'FB_GROUP_POST_RESULT',
      payload:JSON.stringify({success:false,step:'bridge_ping',
        error:'PING_OK — bridge works, real JS starting next'})
    }));
  } catch(e) {
    // bridge unavailable — can't report back
  }
})();
''';

    // Set up listener BEFORE inject
    final sub = broadcast.listen((msg) {
      try {
        final decoded = jsonDecode(msg as String) as Map;
        if (decoded['type'] == 'FB_SHARE_PROGRESS') {
          _setStatus(AutomationStatus.running,
              decoded['message']?.toString() ?? 'Running...');
        }
      } catch (_) {}
    });

    final pingFuture = broadcast
        .where((msg) {
          try {
            return (jsonDecode(msg as String) as Map)['type'] ==
                'FB_GROUP_POST_RESULT';
          } catch (_) {
            return false;
          }
        })
        .first
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => jsonEncode({
            'type': 'FB_GROUP_POST_RESULT',
            'payload': jsonEncode({
              'success': false,
              'step': 'bridge_unavailable',
              'error':
                  'window.chrome.webview.postMessage is not available. WebView bridge not ready.',
            })
          }),
        );

    await _webviewController!.executeScript(pingJs);
    final pingMsg = await pingFuture;
    final pingResult =
        jsonDecode(jsonDecode(pingMsg as String)['payload'] as String) as Map;

    // If bridge_unavailable, stop immediately — no point running main JS
    if (pingResult['step'] == 'bridge_unavailable') {
      await sub.cancel();
      return Map<String, dynamic>.from(pingResult);
    }

    // Bridge is confirmed working — PING returned bridge_ping (not a real error).
    // Now run the real Step 3+4 JS.
    _setStatus(
        AutomationStatus.running, '✅ Bridge OK — injecting Step 3/4 JS...');

    final innerJs = _buildGroupSelectJs(groupIndex, postWords);

    final resultFuture = broadcast
        .where((msg) {
          try {
            return (jsonDecode(msg as String) as Map)['type'] ==
                'FB_GROUP_POST_RESULT';
          } catch (_) {
            return false;
          }
        })
        .first
        .timeout(
          const Duration(seconds: 90),
          onTimeout: () => jsonEncode({
            'type': 'FB_GROUP_POST_RESULT',
            'payload': jsonEncode({
              'success': false,
              'step': 'timeout',
              'error': 'Step 3/4 timed out after 90s.',
            })
          }),
        );

    await _webviewController!.executeScript(innerJs);
    final rawMsg = await resultFuture;
    await sub.cancel();

    try {
      final outer = jsonDecode(rawMsg as String) as Map<String, dynamic>;
      final payload = outer['payload'] as String? ?? '{}';
      String clean = payload.trim();
      if (clean.startsWith('"') && clean.endsWith('"')) {
        clean = jsonDecode(clean) as String;
      }
      return jsonDecode(clean) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'step': 'parse', 'error': 'Result parse: $e'};
    }
  }

  /// Awaits a FB_STEP_RESULT message after injecting [js].
  Future<Map<String, dynamic>> _awaitStepResult(String js,
      {int timeoutMs = 9000}) async {
    final broadcast = _webMessageBroadcast;
    if (broadcast == null) {
      return {'success': false, 'error': 'WebView stream not ready'};
    }
    try {
      final resultFuture = broadcast
          .where((msg) {
            try {
              return (jsonDecode(msg as String) as Map)['type'] ==
                  'FB_STEP_RESULT';
            } catch (_) {
              return false;
            }
          })
          .first
          .timeout(
            Duration(milliseconds: timeoutMs),
            onTimeout: () => jsonEncode({
              'type': 'FB_STEP_RESULT',
              'payload': jsonEncode({
                'success': false,
                'error': 'Step timed out after ${timeoutMs}ms',
              }),
            }),
          );

      await _webviewController!.executeScript(js);
      final rawMsg = await resultFuture;
      final outer = jsonDecode(rawMsg as String) as Map<String, dynamic>;
      final payload = outer['payload'] as String? ?? '{}';
      String clean = payload.trim();
      if (clean.startsWith('"') && clean.endsWith('"')) {
        try {
          clean = jsonDecode(clean) as String;
        } catch (_) {
          clean = clean.substring(1, clean.length - 1);
        }
      }
      final result = jsonDecode(clean) as Map<String, dynamic>;
      return {...result, 'success': result['success'] == true};
    } catch (e) {
      return {'success': false, 'error': 'Step exception: $e'};
    }
  }

  /// Builds the Step 3+4 JS: select group[groupIndex] from open modal, then Post.
  /// Posts FB_GROUP_POST_RESULT when done.
  ///
  /// Redesigned engine — key improvements:
  ///   1. waitFor() polls DOM every 150 ms — zero blind sleeps.
  ///   2. getTopModal() always picks the highest z-index visible dialog so we
  ///      never accidentally search behind an overlay.
  ///   3. Group click is confirmed by condition (Post btn visible) not a fixed delay.
  ///   4. Step 4 always searches the TOP-MOST modal regardless of whether it is a
  ///      new dialog or the same one reused by Facebook.
  ///   5. Confirmation waits for toast OR Post-button disappearance.
  String _buildGroupSelectJs(int groupIndex, String postWordsJs) {
    // Dart-side values injected at build time
    final int delay = _clickDelayMs;

    return '''
(async function() {

// ── Comms ────────────────────────────────────────────────────────────────────
const sleep   = ms => new Promise(r => setTimeout(r, ms));
const progress = msg => {
  try { window.chrome.webview.postMessage(
    JSON.stringify({type:'FB_SHARE_PROGRESS', message:msg})); } catch(_){}
};
const post = payload => window.chrome.webview.postMessage(
  JSON.stringify({type:'FB_GROUP_POST_RESULT', payload:JSON.stringify(payload)}));

// ── Injected constants ───────────────────────────────────────────────────────
const TARGET_IDX  = $groupIndex;
const POST_LABELS = $postWordsJs;
const INTER_DELAY = $delay;

// ── Core helper: poll fn() every intervalMs until truthy, or timeout ─────────
async function waitFor(fn, timeoutMs, intervalMs) {
  intervalMs = intervalMs || 150;
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    const v = fn();
    if (v) return v;
    await sleep(intervalMs);
  }
  return null;
}

// ── Visibility ───────────────────────────────────────────────────────────────
function isVisible(el) {
  if (!el) return false;
  if (el.offsetWidth === 0 || el.offsetHeight === 0) return false;
  const r = el.getBoundingClientRect();
  return r.width > 0 && r.height > 0;
}

// ── z-index helper: max z in ancestor chain ──────────────────────────────────
function zOf(el) {
  let z = 0, cur = el;
  while (cur && cur !== document.body) {
    const zi = parseInt(window.getComputedStyle(cur).zIndex, 10);
    if (!isNaN(zi) && zi > z) z = zi;
    cur = cur.parentElement;
  }
  return z;
}

// ── getTopModal: highest z-index visible dialog/modal ───────────────────────
// Requirement 2: always prioritise the topmost overlay.
// When z-index is equal, prefer the composer/post dialog over the group-list
// dialog — this matches what the user actually sees on screen.
function isComposerDialog(d) {
  const txt = (d.innerText||'').toLowerCase();
  if (txt.includes('create a public post')) return true;
  if (txt.includes('create post'))          return true;
  if (txt.includes('say something'))        return true;
  // Has a visible blue Post button (aria-label or innerText)
  return !![...d.querySelectorAll('div[role="button"],button,[tabindex="0"]')]
    .find(el => {
      if (!isVisible(el)) return false;
      const t = (el.innerText||'').trim().toLowerCase();
      const a = (el.getAttribute('aria-label')||'').toLowerCase();
      return t === 'post' || a === 'post' || t === 'share now';
    });
}

function getTopModal() {
  const list = [...document.querySelectorAll(
    '[role="dialog"],[aria-modal="true"],[role="alertdialog"]'
  )].filter(d => isVisible(d) && document.contains(d));
  if (!list.length) return null;
  list.sort((a,b) => {
    const dz = zOf(b) - zOf(a);
    if (dz !== 0) return dz;
    // Same z: prefer composer dialog (the one with Post button / "Create post")
    const ac = isComposerDialog(a) ? 1 : 0;
    const bc = isComposerDialog(b) ? 1 : 0;
    if (bc !== ac) return bc - ac;
    // Final tiebreak: later in DOM = rendered on top
    return (b.compareDocumentPosition(a) & Node.DOCUMENT_POSITION_FOLLOWING) ? -1 : 1;
  });
  return list[0];
}

// ── Full synthetic click (pointer + mouse events) ────────────────────────────
function fullClick(el) {
  const r = el.getBoundingClientRect();
  const cx = r.left + r.width/2, cy = r.top + r.height/2;
  el.focus();
  for (const t of ['pointerover','pointerenter','pointerdown','pointerup']) {
    try { el.dispatchEvent(new PointerEvent(t,{
      bubbles:true,cancelable:true,view:window,
      clientX:cx,clientY:cy,pointerId:1,isPrimary:true})); } catch(_){}
  }
  for (const t of ['mousedown','mouseup','click']) {
    el.dispatchEvent(new MouseEvent(t,{
      bubbles:true,cancelable:true,view:window,
      clientX:cx,clientY:cy,screenX:cx,screenY:cy}));
  }
  try { el.click(); } catch(_) {}
}

// ── Group-list modal detection ───────────────────────────────────────────────
const GROUP_TYPE_RE = /public group|private group|\\u0db4\\u0ddc\\u0daf\\u0dd4 \\u0d9a\\u0dab\\u0dca\\u0daa\\u0dcf\\u0dba\\u0db8|\\u0db4\\u0dd4\\u0daf\\u0dca\\u0d9c\\u0dbd\\u0dd2\\u0d9a \\u0d9a\\u0dab\\u0dca\\u0daa\\u0dcf\\u0dba\\u0db8/i;
const REJECT_SET    = new Set(['group','groups','messenger','whatsapp','copy link',
  'your story','facebook story','friends','public','all groups','share to a group']);

function looksLikeGroupRow(el) {
  const txt = (el.innerText||'').trim();
  if (txt.length < 3 || REJECT_SET.has(txt.toLowerCase())) return false;
  const hasType   = GROUP_TYPE_RE.test(txt);
  const hasMember = /member|people/i.test(txt) || /\\d+\\s*(members?|people)/i.test(txt);
  const hasImg    = !!(el.querySelector('img,[style*="background-image"]'));
  const isMulti   = txt.includes('\\n') || el.querySelectorAll('span,div').length > 1;
  const firstLine = txt.split('\\n')[0].trim();
  return firstLine.length >= 3 && firstLine.length <= 80
      && (hasType || hasMember || (hasImg && isMulti));
}

// Returns the group-list modal IF the topmost visible dialog IS the group picker.
// Hard-rejects compose/post modals so we never confuse the two.
function getGroupListModal() {
  const top = getTopModal();
  if (!top) return null;
  const txt = (top.innerText||'').toLowerCase();
  // Hard-reject compose dialogs
  if (txt.includes('say something'))      return null;
  if (txt.includes('send in messenger'))  return null;
  const hasSearch = !!top.querySelector(
    'input[type="text"],input[type="search"],[role="searchbox"]');
  if (hasSearch) return top;
  if (txt.includes('share to a group') || txt.includes('all groups')
      || txt.includes('your groups'))     return top;
  if (GROUP_TYPE_RE.test(top.innerText||'')) return top;
  return null;
}

function getGroupRows(modal) {
  // ── Strategy 1: Find rows via "Public group" / "Private group" type labels ──
  // Walk UP from the label to find the clickable row container.
  // FB's current UI: each row is a div ~72px tall with avatar img + name + type label.
  const typeLabels = [...modal.querySelectorAll('span,div')]
    .filter(el => {
      const t = (el.innerText||'').trim();
      return GROUP_TYPE_RE.test(t) && t.length < 40 && isVisible(el)
             && el.children.length === 0; // leaf node = the label span itself
    });

  if (typeLabels.length > 0) {
    const rows = [], seen = new Set();
    for (const lbl of typeLabels) {
      let cur = lbl.parentElement;
      let best = null;
      for (let d = 0; d < 12 && cur && cur !== modal; d++) {
        const h = cur.offsetHeight, w = cur.offsetWidth;
        // Row must be: taller than 48px, wider than 200px, and a direct child
        // of a scrollable list container (not the entire modal).
        // Relaxed: no img requirement — some rows use CSS background or SVG avatar.
        if (h >= 48 && h <= 300 && w > 200) {
          // Prefer the smallest container that still contains the label
          best = cur;
          break;
        }
        cur = cur.parentElement;
      }
      if (best && !seen.has(best)) { seen.add(best); rows.push(best); }
    }
    if (rows.length > 0) return rows;
  }

  // ── Strategy 2: Rows that have BOTH a group name span AND "Public/Private group" ──
  // Collect all visible divs/lis that contain "Public group" or "Private group"
  // as a child text node, and whose height suggests a list row.
  const rowCandidates = [...modal.querySelectorAll('div,li,a')]
    .filter(el => {
      if (!isVisible(el)) return false;
      const h = el.offsetHeight, w = el.offsetWidth;
      if (h < 48 || h > 300 || w < 200) return false;
      const txt = (el.innerText||'');
      if (!GROUP_TYPE_RE.test(txt)) return false;
      // Must NOT be the modal itself or a large container
      if (el === modal) return false;
      const childRows = [...el.querySelectorAll('div,li')]
        .filter(c => c !== el && GROUP_TYPE_RE.test(c.innerText||''));
      // Reject containers that themselves contain sub-rows
      return childRows.length === 0;
    });

  if (rowCandidates.length > 0) return rowCandidates.slice(0, 50);

  // ── Strategy 3: semantic role selectors ─────────────────────────────────────
  for (const sel of ['[role="option"]','li[role="option"]','li','[role="listitem"]',
                      'div[tabindex="0"]','a[tabindex="0"]']) {
    const items = [...modal.querySelectorAll(sel)]
      .filter(r => isVisible(r) && looksLikeGroupRow(r));
    if (items.length > 0) return items;
  }

  // ── Strategy 4: any tall row-like div ───────────────────────────────────────
  return [...modal.querySelectorAll('div,a')]
    .filter(r => isVisible(r) && r.offsetHeight >= 48 && looksLikeGroupRow(r))
    .slice(0, 50);
}

// ── Post-button detection (searches given scope) ─────────────────────────────
// Requirement 4: always call with getTopModal() so we never miss the active modal.
function findPostBtn(scope) {
  if (!scope) return null;

  // ── Strategy 1: data-testid (most stable) ──────────────────────────────────
  for (const sel of [
    '[data-testid="react-composer-post-button"]',
    '[data-testid="share-dialog-post-button"]',
    '[data-testid="tweetButton"]',
  ]) {
    const el = scope.querySelector(sel);
    if (el && isVisible(el) && el.getAttribute('aria-disabled') !== 'true') return el;
  }

  // ── Strategy 2: aria-label exact match — POST only (NOT 'share'/'Share') ───
  // 'share'/'Share' labels are used on audience selectors inside the composer
  // and cause wrong-element clicks. Only use 'post'-equivalent labels here.
  const SUBMIT_ARIA = ['Post','post','Share now','share now',
    '\u0db4\u0dbd \u0d9a\u0dbb\u0db1\u0dca\u0db1',  // Sinhala: පළ කරන්න
  ];
  for (const lbl of SUBMIT_ARIA) {
    const el = scope.querySelector('[aria-label="'+lbl+'"]');
    if (el && isVisible(el) && el.getAttribute('aria-disabled') !== 'true') return el;
  }

  // ── Strategy 3: innerText exact match — POST only (NOT 'share'/'Share') ────
  // We explicitly exclude 'share'/'Share' to avoid audience/share-option buttons
  const SUBMIT_TEXT = ['post','share now','\u0db4\u0dbd \u0d9a\u0dbb\u0db1\u0dca\u0db1'];
  const allBtns = [...scope.querySelectorAll('div[role="button"],button,[tabindex="0"]')]
    .filter(c => isVisible(c) && c.getAttribute('aria-disabled') !== 'true');

  for (const c of allBtns) {
    const t = (c.innerText||'').trim().toLowerCase();
    if (SUBMIT_TEXT.includes(t)) return c;
  }

  // ── Strategy 4: Position-based — bottom-most large blue/primary button ──────
  // FB's "Post" submit button is always at the bottom-right of the composer.
  // It is typically a wide button (>= 100px) near the bottom of the dialog.
  const scopeRect = scope.getBoundingClientRect();
  const bottomThreshold = scopeRect.bottom - 80; // bottom 80px of dialog
  const bottomBtns = allBtns.filter(c => {
    const r = c.getBoundingClientRect();
    // Must be in bottom section of dialog, reasonably wide
    return r.top >= bottomThreshold && r.width >= 80 && r.height >= 28;
  });

  // Among bottom buttons, pick the one most likely to be "Post":
  // prefer buttons that contain ONLY short text (1-3 words) and no child images
  const submitBtn = bottomBtns.find(c => {
    const t = (c.innerText||'').trim();
    const a = (c.getAttribute('aria-label')||'').toLowerCase();
    const wordCount = t.trim().split(' ').filter(w => w.length > 0).length;
    if (wordCount > 4) return false; // long text = not a submit button
    if (c.querySelector('img,svg[style*="color"]')) return false; // icon buttons
    // Must not be audience/privacy selector (those contain dropdown arrows)
    if (a.includes('audience') || a.includes('privacy') ||
        a.includes('public') || a.includes('friends')) return false;
    return true;
  });
  if (submitBtn) return submitBtn;

  // Last resort: any bottom button if only one exists
  if (bottomBtns.length === 1) return bottomBtns[0];

  return null;
}

// ── Toast detection ───────────────────────────────────────────────────────────
const TOAST_SIGNALS = ['post shared','posted to','shared to','your post',
  'successfully','post published',
  '\\u0db4\\u0dbd \\u0d9a\\u0dbb\\u0db1 \\u0dbd\\u0daf\\u0dba\\u0dd3',
  'share \\u0d9a\\u0dbb\\u0db1 \\u0dbd\\u0daf\\u0dba\\u0dd3'];
function hasToast() {
  return [...document.querySelectorAll(
    '[role="alert"],[role="status"],[aria-live],' +
    '[data-testid*="toast"],[data-testid*="notification"]'
  )].some(n => {
    if (!isVisible(n)) return false;
    const t = (n.innerText||'').toLowerCase();
    return TOAST_SIGNALS.some(s => t.includes(s));
  });
}

// ── Detect and dismiss "Leave page?" confirmation modal ──────────────────────
// Returns true if a "Leave page?" modal was found and handled (Continue Editing).
// This MUST be called BEFORE any Escape/close attempts so we never accidentally
// trigger the "Leave" action which discards the compose dialog.
async function dismissLeavePageModal() {
  const LEAVE_PAGE_SIGNALS = [
    "leave page", "leave without", "haven't finished",
    "leave?", "discard post", "discard changes",
    // Sinhala variants
    "\\u0db4ිටත්\\u0dbd \\u0dba\\u0db1්\\u0db1\\u0daf", // පිටත්ල යන්නද
    "\\u0daf\\u0dd0\\u0db4 \\u0d9a\\u0dbb\\u0db1\\u0dca\\u0db1\\u0daf"
  ];
  const CONTINUE_LABELS = [
    "continue editing", "stay", "keep editing",
    "continue", "\\u0d9c\\u0ddc\\u0db8\\u0dd4 \\u0dc3\\u0db8\\u0dca\\u0db4\\u0dcf\\u0daf\\u0db1\\u0dba" // Sinhala
  ];

  const dialogs = [...document.querySelectorAll(
    '[role="dialog"],[aria-modal="true"],[role="alertdialog"]'
  )].filter(d => isVisible(d) && document.contains(d));

  for (const d of dialogs) {
    const txt = (d.innerText || '').toLowerCase();
    const isLeaveModal = LEAVE_PAGE_SIGNALS.some(s => txt.includes(s));
    if (!isLeaveModal) continue;

    // Found "Leave page?" modal — click "Continue Editing" to stay on composer
    const continueBtn = [...d.querySelectorAll(
      'div[role="button"],button,[tabindex="0"]'
    )].find(btn => {
      if (!isVisible(btn)) return false;
      const t = (btn.innerText || '').trim().toLowerCase();
      const a = (btn.getAttribute('aria-label') || '').toLowerCase();
      return CONTINUE_LABELS.some(l => t.includes(l) || a.includes(l));
    });

    if (continueBtn) {
      continueBtn.dispatchEvent(
        new MouseEvent('click', {bubbles:true, cancelable:true, view:window}));
      await sleep(600);
      return true;
    }
  }
  return false;
}

// ── Close all open modals aggressively ───────────────────────────────────────
async function closeAllModals() {
  // Pre-Pass: Handle "Leave page?" modal — always prefer "Continue Editing"
  // so we never accidentally abandon an in-progress compose dialog.
  await dismissLeavePageModal();

  // Pass 1: Escape key
  document.dispatchEvent(new KeyboardEvent('keydown',{
    key:'Escape',code:'Escape',keyCode:27,bubbles:true,cancelable:true}));
  await sleep(400);

  // Pass 2: Click Close/Back/X buttons on every visible dialog
  const dialogs = [...document.querySelectorAll('[role="dialog"],[aria-modal="true"]')]
    .filter(d => isVisible(d) && document.contains(d));

  for (const d of dialogs) {
    // Try multiple close button selectors
    const closeBtn =
      d.querySelector('[aria-label="Close"],[aria-label="close"]') ||
      d.querySelector('[aria-label="Back"],[aria-label="back"]')   ||
      d.querySelector('div[role="button"][aria-label*="lose"]')    ||
      d.querySelector('div[role="button"][aria-label*="ack"]')     ||
      // FB sometimes uses an SVG X button with no aria-label — find by position
      // (top-right corner buttons in the dialog header)
      [...d.querySelectorAll('div[role="button"],button')]
        .find(btn => {
          if (!isVisible(btn)) return false;
          const dr = d.getBoundingClientRect();
          const br = btn.getBoundingClientRect();
          // Button in top-right quadrant of the dialog
          return br.right >= dr.right - 60 && br.top <= dr.top + 80;
        });
    if (closeBtn && isVisible(closeBtn)) {
      closeBtn.dispatchEvent(
        new MouseEvent('click',{bubbles:true,cancelable:true,view:window}));
      await sleep(350);
    }
  }

  // Pass 3: Escape again
  document.dispatchEvent(new KeyboardEvent('keydown',{
    key:'Escape',code:'Escape',keyCode:27,bubbles:true,cancelable:true}));
  await sleep(400);

  // Pass 4: If dialogs still open, try clicking outside them (backdrop)
  const remaining = [...document.querySelectorAll('[role="dialog"],[aria-modal="true"]')]
    .filter(d => isVisible(d) && document.contains(d));
  for (const d of remaining) {
    const r = d.getBoundingClientRect();
    // Click just outside the dialog (the backdrop)
    const bx = Math.max(0, r.left - 20), by = r.top + r.height/2;
    document.dispatchEvent(new MouseEvent('click',{
      bubbles:true,cancelable:true,view:window,clientX:bx,clientY:by}));
    await sleep(300);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// STEP 3 — Wait for group-list modal, then click target group
// Requirement 3: auto-identify group at TARGET_IDX once modal is loaded.
// ════════════════════════════════════════════════════════════════════════════════
progress('Step 3/4: Waiting for group-list modal...');

// Pre-cleanup: if a "Create post" / composer dialog is still open from a
// previous iteration, close it before we try to find the group-list modal.
{
  const lingering = [...document.querySelectorAll('[role="dialog"],[aria-modal="true"]')]
    .filter(d => {
      if (!isVisible(d)) return false;
      const t = (d.innerText||'').toLowerCase();
      return t.includes('create post') || t.includes('create a public post')
          || t.includes('say something') || t.includes('add to your post');
    });
  if (lingering.length > 0) {
    progress('Closing '+lingering.length+' leftover composer dialog(s)...');
    await closeAllModals();
    await sleep(500);
  }
}

// Diagnostic snapshot
{
  const dlgs = [...document.querySelectorAll(
    '[role="dialog"],[aria-modal="true"],[role="alertdialog"]')].filter(isVisible);
  progress('Dialogs visible: '+dlgs.length+' | '+
    dlgs.map((d,i)=>i+':z='+zOf(d)+
      ' txt='+(d.innerText||'').trim().substring(0,25).replace(/\\n/g,' ')
    ).join(' | '));
}

// Requirement 1: waitFor — poll until group-list modal appears (14 s budget)
const modal = await waitFor(getGroupListModal, 14000, 200);
if (!modal) {
  post({success:false, step:'modal',
        error:'Group-list modal not found within 14s.'});
  return;
}

progress('Step 3/4: Modal found. Loading group rows...');

// waitFor group rows to render (12 s budget)
const allRows = await waitFor(() => {
  const r = getGroupRows(modal);
  return r.length > 0 ? r : null;
}, 12000, 200);

if (!allRows) {
  progress('No rows found. Modal text: '+(modal.innerText||'').trim().substring(0,120));
  post({success:false, step:'groups',
        error:'No group rows appeared within 12s.'});
  return;
}

const totalFound = allRows.length;
progress('Step 3/4: '+totalFound+' group(s). Selecting #'+(TARGET_IDX+1)+'...');

if (TARGET_IDX >= totalFound) {
  post({success:false, step:'pagination',
        error:'Index '+TARGET_IDX+' >= '+totalFound+' groups.',
        nextRunStartIndex:0, totalGroupsFound:totalFound});
  return;
}

const groupRow  = allRows[TARGET_IDX];
const groupName = (groupRow.innerText||'Group '+(TARGET_IDX+1))
                    .trim().split('\\n')[0].substring(0,60);

progress('Step 3/4: Clicking "'+groupName+'"...');
groupRow.scrollIntoView({behavior:'smooth', block:'nearest'});
await sleep(350);

// Snapshot dialogs before click — to detect if a NEW dialog opens
const preDlgs = new Set(
  [...document.querySelectorAll('[role="dialog"],[aria-modal="true"]')]
    .filter(isVisible));

function newDialogOpened() {
  return [...document.querySelectorAll('[role="dialog"],[aria-modal="true"]')]
    .some(d => isVisible(d) && !preDlgs.has(d));
}

// clickSucceeded = a new dialog opened OR Post button visible in top modal
// Requirement 4: findPostBtn always uses getTopModal()
function clickSucceeded() {
  return newDialogOpened() || !!findPostBtn(getTopModal());
}

// Primary click attempt — confirmed by condition, not by sleep
fullClick(groupRow);
let clickOk = await waitFor(clickSucceeded, 3000, 150);

// Retry: walk up ancestor chain if primary click had no effect
if (!clickOk) {
  let cur = groupRow.parentElement;
  for (let d = 0; d < 6 && cur && cur !== modal; d++) {
    fullClick(cur);
    clickOk = await waitFor(clickSucceeded, 800, 150);
    if (clickOk) break;
    cur = cur.parentElement;
  }
}

// elementFromPoint fallback
if (!clickOk) {
  const r  = groupRow.getBoundingClientRect();
  const el = document.elementFromPoint(r.left+r.width/2, r.top+r.height/2);
  if (el && el !== groupRow) {
    fullClick(el);
    await waitFor(clickSucceeded, 1000, 150);
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// STEP 4 — Find Post button in ANY visible composer modal and click it.
// We scan ALL visible dialogs (not just the "top" one) to avoid z-index
// sort issues. We pick the dialog that:
//   a) looks like a composer (has "create post" text or contenteditable), AND
//   b) has a visible, enabled Post button.
// ════════════════════════════════════════════════════════════════════════════════
progress('Step 4/4: Waiting for Post button for "'+groupName+'"...');

function findComposerAndPostBtn() {
  const allDialogs = [...document.querySelectorAll(
    '[role="dialog"],[aria-modal="true"],[role="alertdialog"]'
  )].filter(d => isVisible(d) && document.contains(d));

  // Sort by z-index descending so we prefer the frontmost dialog
  allDialogs.sort((a,b) => zOf(b) - zOf(a));

  for (const d of allDialogs) {
    const btn = findPostBtn(d);
    if (!btn) continue;
    // Verify this dialog is a composer, not the group-list picker
    const txt = (d.innerText||'').toLowerCase();
    if (txt.includes('search for groups') || txt.includes('all groups')) continue;
    if (txt.includes('share to a group')) continue;
    return {dialog:d, btn};
  }
  return null;
}

const postScope = await waitFor(findComposerAndPostBtn, 15000, 200);

if (!postScope) {
  await closeAllModals();
  post({success:false, step:'post_modal',
        error:'Post button not found for "'+groupName+'" within 10s.',
        groupName, nextRunStartIndex:TARGET_IDX+1, totalGroupsFound:totalFound});
  return;
}

const {dialog:postDialog, btn:postBtn} = postScope;
progress('Step 4/4: Clicking Post for "'+groupName+'"...');

if (postBtn.getAttribute('aria-disabled') === 'true') {
  await closeAllModals();
  post({success:false, step:'post_disabled',
        error:'Post button disabled for "'+groupName+'".',
        groupName, nextRunStartIndex:TARGET_IDX+1, totalGroupsFound:totalFound});
  return;
}

fullClick(postBtn);

// ── Confirm submission ────────────────────────────────────────────────────────
progress('Step 4/4: Waiting for confirmation for "'+groupName+'"...');

// ── "Leave page?" guard ─────────────────────────────────────────────────────
// After clicking Post, Facebook sometimes shows a "Leave page?" modal.
// This means the click was treated as navigation, NOT a submit — post NOT sent.
// We detect this and click "Continue Editing" to return to the composer.
const LEAVE_SIGNALS_S4 = [
  "leave page","leave without","haven't finished",
  "leave?","discard post","discard changes"
];
const CONTINUE_LABELS_S4 = ["continue editing","stay","keep editing","continue"];

async function handleLeavePageIfVisible() {
  const dialogs = [...document.querySelectorAll(
    '[role="dialog"],[aria-modal="true"],[role="alertdialog"]'
  )].filter(d => isVisible(d) && document.contains(d));
  for (const d of dialogs) {
    const txt = (d.innerText||'').toLowerCase();
    if (!LEAVE_SIGNALS_S4.some(s => txt.includes(s))) continue;
    const continueBtn = [...d.querySelectorAll(
      'div[role="button"],button,[tabindex="0"]'
    )].find(btn => {
      if (!isVisible(btn)) return false;
      const t = (btn.innerText||'').trim().toLowerCase();
      const a = (btn.getAttribute('aria-label')||'').toLowerCase();
      return CONTINUE_LABELS_S4.some(l => t.includes(l) || a.includes(l));
    });
    if (continueBtn) {
      continueBtn.dispatchEvent(
        new MouseEvent('click',{bubbles:true,cancelable:true,view:window}));
      await sleep(700);
      return true;
    }
  }
  return false;
}

function isLeavePageModalVisible() {
  return [...document.querySelectorAll(
    '[role="dialog"],[aria-modal="true"],[role="alertdialog"]'
  )].some(d => {
    if (!isVisible(d)) return false;
    const t = (d.innerText||'').toLowerCase();
    return LEAVE_SIGNALS_S4.some(s => t.includes(s));
  });
}

// Dialog dismissed = removed from DOM, hidden, OR Post button gone from it.
// KEY FIX: If "Leave page?" is visible, post was NOT sent — return false.
function postDialogDismissed() {
  if (isLeavePageModalVisible()) return false; // ← KEY FIX: not dismissed, just navigating away
  if (!document.contains(postDialog)) return true;
  if (!isVisible(postDialog))         return true;
  // Post button gone = FB submitted and cleared the composer
  const stillHasPostBtn = !![...postDialog.querySelectorAll(
    'div[role="button"],button,[tabindex="0"]')]
    .find(el => {
      if (!isVisible(el)) return false;
      const t = (el.innerText||'').trim().toLowerCase();
      const a = (el.getAttribute('aria-label')||'').toLowerCase();
      return t==='post' || a==='post' || t==='share now';
    });
  return !stillHasPostBtn;
}

function isConfirmed() {
  return (hasToast() || postDialogDismissed()) ? true : null;
}

// Handle "Leave page?" that may appear immediately after Post click
await sleep(400);
const leaveHandled1 = await handleLeavePageIfVisible();
if (leaveHandled1) {
  progress('Step 4/4: Recovered "Leave page?" — retrying Post for "'+groupName+'"...');
  await sleep(500);
  const retryScope = await waitFor(findComposerAndPostBtn, 5000, 200);
  if (retryScope && isVisible(retryScope.btn) &&
      retryScope.btn.getAttribute('aria-disabled') !== 'true') {
    fullClick(retryScope.btn);
    await sleep(400);
    await handleLeavePageIfVisible();
  }
}

let confirmed = !!(await waitFor(isConfirmed, 12000, 200));

if (!confirmed) {
  // Handle any "Leave page?" before retrying
  await handleLeavePageIfVisible();
  await sleep(300);
  progress('Retrying Post click for "'+groupName+'"...');
  try { postBtn.click(); } catch(_){}
  await sleep(400);
  await handleLeavePageIfVisible();
  confirmed = !!(await waitFor(isConfirmed, 6000, 200));
}

// Clean up any lingering dialogs before the next loop iteration
await closeAllModals();

// Requirement 5: stability gap before Dart restarts Step 1
await sleep(INTER_DELAY);

if (!confirmed) {
  post({success:false, step:'post_confirm',
        error:'Post not confirmed for "'+groupName+'" after retry.',
        groupName, nextRunStartIndex:TARGET_IDX+1, totalGroupsFound:totalFound});
  return;
}

progress('Posted to "'+groupName+'"!');
post({success:true,
      message:'Posted to "'+groupName+'"!',
      groupName,
      nextRunStartIndex:TARGET_IDX+1,
      totalGroupsFound:totalFound});

})().catch(e => {
  try {
    window.chrome.webview.postMessage(JSON.stringify({
      type:'FB_GROUP_POST_RESULT',
      payload:JSON.stringify({success:false,step:'uncaught',error:e.toString()})
    }));
  } catch(_){}
});
''';
  }

  // ── _runStep: Smart Wait + Force Click for a single TemplateStep ──────────
  //
  // Req 1: polls every 200ms up to 4s (group step) / 5s (other steps).
  // Req 2: aria-label → data-testid → role+innerText → CSS → fallbackText.
  // Req 3: FbStrings.shareToGroupExact used as contextual labels for group step.
  // Req 4: mousedown → mouseup → click dispatch with bubbles:true + clientX/Y.
  // Req 5: template fingerprint + scopeSelector from active template step.
  //
  // IMPORTANT: WebView2 executeScript() cannot return async Promise results —
  // it always returns null for async IIFEs. We use the postMessage bridge
  // (window.chrome.webview.postMessage) to receive the result.
  //
  // Returns {success:bool, clicked:String?, error:String?}
  Future<Map<String, dynamic>> _runStep(Map<String, dynamic> step) async {
    if (_webviewController == null) {
      return {'success': false, 'error': 'WebView not ready'};
    }

    final broadcast = _webMessageBroadcast;
    if (broadcast == null) {
      return {'success': false, 'error': 'WebView stream not ready'};
    }

    final attributes =
        (step['attributes'] as List? ?? []).cast<Map<String, dynamic>>();
    final fallbackText = step['fallbackText'] as String?;
    final label = (step['label'] as String? ?? '').toLowerCase();
    // scopeSelector: from template step, OR from right-click capture
    final scopeSelector =
        (step['scopeSelector'] as String?) ?? _capturedScopeSelector;

    // Detect if this step is the "Group" menu option step.
    final bool isGroupStep = label.contains('group') ||
        (fallbackText != null &&
            FbStrings.shareToGroupExact
                .any((s) => s.toLowerCase() == fallbackText.toLowerCase()));

    final js = _buildStepJs(attributes, fallbackText,
        isGroupStep: isGroupStep, scopeSelector: scopeSelector);

    return _awaitStepResult(js, timeoutMs: isGroupStep ? 8000 : 9000);
  }

  /// Builds the injected JS for a single template step.
  ///
  /// [isGroupStep] = true  → Group-menu mode.
  /// [scopeSelector] = CSS selector to restrict the DOM search scope.
  ///   When set (Right-Click to Focus), only searches inside that container.
  ///   Overrides the default document / dialog heuristics.
  String _buildStepJs(
    List<Map<String, dynamic>> attributes,
    String? fallbackText, {
    bool isGroupStep = false,
    String? scopeSelector,
  }) {
    // ── Extract attribute values ─────────────────────────────────────────────
    String? ariaLabel;
    String? role;
    String? text;
    String? testId;
    String? cssSelector;

    for (final attr in attributes) {
      final key = attr['key'] as String? ?? '';
      final value = attr['value'] as String? ?? '';
      switch (key) {
        case 'aria-label':
          ariaLabel = value;
          break;
        case 'role':
          role = value;
          break;
        case 'text':
          text = value;
          break;
        case 'data-testid':
          testId = value;
          break;
        case 'css':
          cssSelector = value;
          break;
      }
    }

    final effectiveText = fallbackText ?? text ?? '';

    // JS-safe string escaper
    String jsStr(String? s) =>
        (s ?? '').replaceAll('\\', '\\\\').replaceAll('"', '\\"');

    // FbStrings contextual label list → JS array (Req 3)
    final groupLabelsJs = FbStrings.toJsArray(FbStrings.shareToGroupExact);

    // Polling config: tighter window for group step (Req 1)
    const pollInterval = 200;
    final pollTimeout = isGroupStep ? 4000 : 5000;

    return '''
(async function() {

  // ── Constants ──────────────────────────────────────────────────────────────
  const IS_GROUP_STEP   = ${isGroupStep ? 'true' : 'false'};
  const SCOPE_SELECTOR  = ${scopeSelector != null ? '"${jsStr(scopeSelector)}"' : 'null'};
  const POLL_INTERVAL   = $pollInterval;  // ms between retries (Req 1)
  const POLL_TIMEOUT    = $pollTimeout;   // total wait budget
  // Req 3: contextual group labels from FbStrings.shareToGroupExact
  const GROUP_LABELS    = $groupLabelsJs;
  // Non-group share-menu options to exclude
  const IGNORE_LABELS   = [
    'messenger','whatsapp','your story','copy link','copy',
    'facebook story','news feed','timeline','friends',
    'instagram','telegram','twitter','more options','email',
  ];

  // ── Helpers ────────────────────────────────────────────────────────────────

  // Reject share-count stats labels e.g. "1 share", "12 shares"
  const STATS_RE = /^\\d[\\d.,KkMm ]*\\s*(share|shares|like|likes|comment|comments)/i;

  function normText(el) {
    return (el.innerText || el.textContent || '')
      .replace(/[^\\w\\s\\u0D80-\\u0DFF\\u00C0-\\u024F]/g, '')
      .replace(/\\s+/g, ' ').trim();
  }

  function isStatsLabel(el) {
    const aria = (el.getAttribute('aria-label') || '').trim();
    const txt  = normText(el);
    return STATS_RE.test(aria) || STATS_RE.test(txt);
  }

  function isIgnored(el) {
    const t = normText(el).toLowerCase();
    const a = (el.getAttribute('aria-label') || '').toLowerCase().trim();
    return IGNORE_LABELS.some(x => t === x || a === x);
  }

  function isVisible(el) {
    if (!el || el.offsetWidth === 0 || el.offsetHeight === 0) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  function isFullyVisible(el) {
    if (!isVisible(el)) return false;
    const r = el.getBoundingClientRect();
    return r.top >= -10 && r.bottom <= window.innerHeight + 80;
  }

  function isClickable(el) {
    if (!el) return false;
    const tag  = (el.tagName || '').toLowerCase();
    const role = (el.getAttribute('role') || '').toLowerCase();
    // FB Share-menu items are typically div[role="button"] or div[role="menuitem"]
    return role === 'button' || role === 'menuitem' || role === 'option' ||
           tag  === 'button' || tag  === 'a' ||
           el.getAttribute('tabindex') !== null ||
           (tag === 'div' && role !== '');  // any div with explicit role
  }

  function isReady(el) {
    return isVisible(el) && isClickable(el) && !isStatsLabel(el);
  }

  // ── Search scopes ──────────────────────────────────────────────────────────
  // Priority: scopeSelector (Right-Click to Focus) > group-menu dialogs > document.
  function getScopes() {
    // Right-Click to Focus: user pinned a specific container — use only that.
    ${scopeSelector != null ? '''
    {
      try {
        const pinned = document.querySelector("${jsStr(scopeSelector)}");
        if (pinned && pinned.offsetWidth > 0) return [pinned];
      } catch(_) {}
      // Selector invalid or element gone — fall through to heuristics
    }
    ''' : '// no scopeSelector'}

    if (!IS_GROUP_STEP) return [document];
    // Share-menu signals — text that appears in the Share popup but NOT in the
    // post-viewer dialog. Used to pick the right dialog when multiple are open.
    const SHARE_MENU_SIGNALS = [
      'messenger','whatsapp','copy link','your story',
      'share to','send in messenger','share now',
      '\u0DC3\u0DB8\u0DD4\u0DC4','\u0D9A\u0DAB\u0DCA\u0DBD\u0DCF\u0DBA',
    ];
    const allDialogs = [
      ...document.querySelectorAll(
        '[role="dialog"],[aria-modal="true"],[role="menu"],[role="listbox"]'
      )
    ].filter(d => d.offsetWidth > 0 && d.offsetHeight > 0);

    // Prefer dialogs that look like the Share popup
    const shareMenuDialogs = allDialogs.filter(d => {
      const txt = (d.innerText || '').toLowerCase();
      return SHARE_MENU_SIGNALS.some(s => txt.includes(s));
    });

    // Also always search full document as final fallback
    const scopes = shareMenuDialogs.length > 0 ? shareMenuDialogs : allDialogs;
    return scopes.length > 0 ? scopes : [document];
  }

  // ── Req 2: Multi-attribute priority finder ─────────────────────────────────
  // Priority: aria-label → data-testid → role+innerText → CSS → fallbackText
  // For group step: additionally match against GROUP_LABELS (Req 3).
  function findElement() {
    for (const scope of getScopes()) {

      // P1 — aria-label exact match (template fingerprint, Req 5)
      ${ariaLabel != null ? '''
      {
        const want = "${jsStr(ariaLabel)}";
        let el = scope === document
          ? document.querySelector('[aria-label="' + want + '"]')
          : scope.querySelector('[aria-label="' + want + '"]');
        if (!el) {
          for (const c of scope.querySelectorAll('[aria-label]')) {
            if ((c.getAttribute('aria-label')||'').trim().toLowerCase()
                === want.toLowerCase()) { el = c; break; }
          }
        }
        if (el && isReady(el) && !isIgnored(el)) return el;
      }
      ''' : '// aria-label not in template'}

      // P2 — data-testid (template fingerprint)
      ${testId != null ? '''
      {
        const el = scope.querySelector('[data-testid="${jsStr(testId)}"]');
        if (el && isReady(el) && !isIgnored(el)) return el;
      }
      ''' : '// testid not in template'}

      // P3 — role + innerText (template fingerprint, Req 2)
      ${role != null && effectiveText.isNotEmpty ? '''
      {
        const wantRole = "${jsStr(role)}";
        const wantText = "${jsStr(effectiveText)}".toLowerCase();
        for (const c of scope.querySelectorAll(
            '[role="' + wantRole + '"],[role="menuitem"],[role="button"]')) {
          const t = normText(c).toLowerCase();
          if ((t === wantText || t.startsWith(wantText))
              && isReady(c) && !isIgnored(c)) return c;
        }
      }
      ''' : '// role+text not in template'}

      // P4 — CSS selector (template fingerprint)
      ${cssSelector != null ? '''
      try {
        const el = scope.querySelector("${jsStr(cssSelector)}");
        if (el && isReady(el) && !isIgnored(el)) return el;
      } catch(_) {}
      ''' : '// css selector not in template'}

      // P5 — FbStrings GROUP_LABELS contextual match (Req 3) — group step only
      if (IS_GROUP_STEP) {
        const candidates = [...scope.querySelectorAll(
          'div[role="button"],div[role="menuitem"],button,' +
          'li[role="option"],[tabindex="0"],a[role="menuitem"]'
        )].filter(el => isFullyVisible(el) && !isIgnored(el));

        // Pass A: exact normText match against GROUP_LABELS
        for (const el of candidates) {
          const t = normText(el);
          if (GROUP_LABELS.some(lbl =>
              t.toLowerCase() === lbl.toLowerCase() ||
              (el.getAttribute('aria-label')||'').toLowerCase() === lbl.toLowerCase()
          )) return el;
        }
        // Pass B: normText starts-with any GROUP_LABEL (short, ≤15 chars)
        for (const el of candidates) {
          const t = normText(el);
          if (t.length <= 15 && GROUP_LABELS.some(lbl =>
              t.toLowerCase().startsWith(lbl.toLowerCase()))) return el;
        }
      }

      // P6 — fallbackText innerText match (any step)
      ${effectiveText.isNotEmpty ? '''
      {
        const want = "${jsStr(effectiveText)}".toLowerCase();
        for (const c of scope.querySelectorAll(
            '[role="button"],button,[tabindex="0"],' +
            '[role="menuitem"],[role="option"],[role="listitem"]')) {
          const t = normText(c).toLowerCase();
          if (t === want && isReady(c) && !isIgnored(c)) return c;
        }
      }
      ''' : '// no fallback text'}
    }
    return null;
  }

  // ── Req 1: waitForElement — poll every 200ms, up to POLL_TIMEOUT ──────────
  const deadline = Date.now() + POLL_TIMEOUT;
  let target = null;
  while (Date.now() < deadline) {
    target = findElement();
    if (target) break;
    await new Promise(r => setTimeout(r, POLL_INTERVAL));
  }

  if (!target) {
    // Diagnostic: collect visible button labels from all dialogs
    const diags = [...document.querySelectorAll(
      '[role="dialog"],[aria-modal="true"],[role="menu"],div[role="button"],button'
    )]
      .filter(e => e.offsetWidth > 0 && e.offsetHeight > 0)
      .slice(0, 20)
      .map(e => {
        const a = e.getAttribute('aria-label') || '';
        const t = normText(e).substring(0, 30);
        return '"' + (a || t) + '"';
      });
    window.chrome.webview.postMessage(JSON.stringify({
      type: 'FB_STEP_RESULT',
      payload: JSON.stringify({
        success: false,
        error: (IS_GROUP_STEP
          ? 'Group button not found after ' + POLL_TIMEOUT + 'ms polling in share-menu dialogs.'
          : 'Element not found after ' + POLL_TIMEOUT + 'ms polling.' +
            (SCOPE_SELECTOR ? ' (scoped to: ' + SCOPE_SELECTOR + ')' : '')) +
          ' Visible: ' + diags.join(', ')
      })
    }));
    return;
  }

  // ── Req 4: Force interaction ───────────────────────────────────────────────
  // 1. Scroll element into view (both window + parent container)
  const rect = target.getBoundingClientRect();
  const scrollY = window.scrollY + rect.top + rect.height / 2 - window.innerHeight / 2;
  window.scrollTo({ top: scrollY, behavior: 'smooth' });

  // Also scroll nearest scrollable ancestor (handles dialog popups)
  let par = target.parentElement;
  while (par && par !== document.body) {
    if (par.scrollHeight > par.clientHeight + 4) {
      const parRect = par.getBoundingClientRect();
      par.scrollTop += rect.top - parRect.top - 80;
      break;
    }
    par = par.parentElement;
  }

  await new Promise(r => setTimeout(r, 300));

  // 2. Re-measure after scroll (rect may have shifted)
  const r2 = target.getBoundingClientRect();
  const cx  = r2.left + r2.width  / 2;
  const cy  = r2.top  + r2.height / 2;

  // 3. Dispatch mousedown → mouseup → click with bubbles (Req 4)
  target.focus();
  for (const type of ['mousedown', 'mouseup', 'click']) {
    target.dispatchEvent(new MouseEvent(type, {
      bubbles: true, cancelable: true, view: window,
      clientX: cx, clientY: cy,
      screenX: cx, screenY: cy,
    }));
  }

  const clicked = target.getAttribute('aria-label') ||
                  normText(target).substring(0, 60);
  // Post result via webview bridge — executeScript cannot return async values
  window.chrome.webview.postMessage(
    JSON.stringify({
      type: 'FB_STEP_RESULT',
      payload: JSON.stringify({ success: true, clicked: clicked })
    })
  );
})().catch(e => {
  try {
    window.chrome.webview.postMessage(
      JSON.stringify({
        type: 'FB_STEP_RESULT',
        payload: JSON.stringify({ success: false, error: e.toString() })
      })
    );
  } catch(_) {}
});
''';
  }

  static const String _deepScanInline = r'''
(function() {
  const scopes = [document];
  const dialogs = document.querySelectorAll(
    '[role="dialog"],[role="menu"],[role="listbox"],[aria-modal="true"]');
  dialogs.forEach(d => scopes.push(d));

  const allEls = [];
  const seen   = new Set();

  function isShareCountBtn(el) {
    const t = (el.innerText || '').trim();
    if (t.length === 0 || t.length > 10) return false;
    const tNum = t.replace('K','').replace('k','').replace('M','').replace('m','').replace(',','');
    if (isNaN(parseFloat(tNum)) || parseFloat(tNum) <= 0) return false;
    const parent = el.parentElement;
    if (!parent) return false;
    const ph = (parent.innerHTML || '').toLowerCase();
    const pa = (parent.getAttribute('aria-label') || '').toLowerCase();
    const gp = parent.parentElement;
    const gph = gp ? (gp.innerHTML || '').toLowerCase() : '';
    return ph.includes('share') || pa.includes('share') ||
           gph.includes('"share"') || gph.includes('share');
  }

  function isActionBarShareBtn(el) {
    const likeBtn = document.querySelector(
      '[aria-label="Like"],[aria-label="Likes"],[aria-label^="Like "]');
    if (!likeBtn) return false;
    const row = likeBtn.closest('div[role="group"],ul,div');
    if (!row) return false;
    const btns = [...row.querySelectorAll('[role="button"],[tabindex="0"],button')]
      .filter(b => row === b.closest('div[role="group"],ul,div'));
    return btns.length >= 3 && btns[2] === el;
  }

  scopes.forEach(scope => {
    const candidates = scope.querySelectorAll(
      '[role="button"],[role="menuitem"],[role="option"],[role="checkbox"],' +
      '[role="listitem"],button,[tabindex="0"],[tabindex="-1"],[aria-label],' +
      'a[href],[role="link"]'
    );
    candidates.forEach(el => {
      const aria   = el.getAttribute('aria-label') || '';
      const testId = el.getAttribute('data-testid') || '';
      const role   = el.getAttribute('role') || el.tagName.toLowerCase();
      const tag    = el.tagName.toLowerCase();
      const text   = (el.innerText || el.textContent || '')
                       .trim().replace(/\s+/g,' ').substring(0, 80);
      const key    = (aria + text + el.className).substring(0, 40);
      if (!key.trim()) return;
      if (seen.has(key)) return;
      seen.add(key);
      allEls.push(el);
    });
  });

  window.__scanEls = allEls;

  const result = allEls.map((el, i) => ({
    index:     String(i),
    text:      (el.innerText || el.textContent || '').trim()
                 .replace(/\s+/g,' ').substring(0, 80),
    aria:      el.getAttribute('aria-label') || '',
    testId:    el.getAttribute('data-testid') || '',
    role:      el.getAttribute('role') || el.tagName.toLowerCase(),
    tag:       el.tagName.toLowerCase(),
    shareHint: isShareCountBtn(el) || isActionBarShareBtn(el),
  }));

  return JSON.stringify(result);
})();
''';

  void _setStatus(AutomationStatus s, String msg) {
    _status = s;
    _statusMessage = msg;
    notifyListeners();
  }
}
