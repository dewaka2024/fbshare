// lib/providers/automation_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Human-like delay helper
// ─────────────────────────────────────────────────────────────────────────────

/// Returns a Future that completes after a random duration in [minMs, maxMs].
/// Used everywhere we need to pause between navigation / interaction steps so
/// behaviour does not look mechanically uniform to Facebook's bot detection.
Future<void> randomDelay({int minMs = 3000, int maxMs = 7000}) {
  final ms = minMs + Random().nextInt(maxMs - minMs + 1);
  return Future<void>.delayed(Duration(milliseconds: ms));
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

enum AutomationStatus { idle, navigating, running, success, error }

/// A Facebook group the user has joined.
class FBGroup {
  final String name;
  /// DOM index inside window.__foundGroups[].  Used to click-navigate via
  /// window.navigateToGroup(index).  -1 means URL-based navigation only.
  final int    index;
  /// CDN thumbnail URL extracted from the group row <img> src.
  final String imageUrl;
  /// Canonical group URL — present only when extractable, otherwise empty.
  final String url;

  const FBGroup({
    required this.name,
    required this.index,
    this.imageUrl = '',
    this.url      = '',
  });

  Map<String, dynamic> toJson() => {
        'name':     name,
        'index':    index,
        'imageUrl': imageUrl,
        'url':      url,
      };

  factory FBGroup.fromJson(Map<String, dynamic> j) => FBGroup(
        name:     j['name']     as String? ?? 'Unknown Group',
        index:    (j['index']   as num?  )?.toInt() ?? -1,
        imageUrl: j['imageUrl'] as String? ?? '',
        url:      j['url']      as String? ?? '',
      );
}

/// A saved Facebook post link with its original URL and a desktop-safe embed URL.
class FBItem {
  final String id;
  final String originalUrl;
  final String embedUrl;
  final DateTime savedAt;
  // OG preview fields — populated after meta scrape
  final String ogTitle;
  final String ogDescription;
  final String ogImage;

  FBItem({
    required this.id,
    required this.originalUrl,
    required this.embedUrl,
    required this.savedAt,
    this.ogTitle       = '',
    this.ogDescription = '',
    this.ogImage       = '',
  });

  /// Returns a copy with updated OG fields.
  FBItem withMeta({
    required String title,
    required String description,
    required String image,
  }) => FBItem(
    id:            id,
    originalUrl:   originalUrl,
    embedUrl:      embedUrl,
    savedAt:       savedAt,
    ogTitle:       title,
    ogDescription: description,
    ogImage:       image,
  );

  static String buildEmbedUrl(String originalUrl) {
    var url = originalUrl.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (url.startsWith('http://')) {
      url = 'https://${url.substring(7)}';
    }
    url = url
        .replaceFirst('https://m.facebook.com', 'https://www.facebook.com')
        .replaceFirst('http://m.facebook.com',  'https://www.facebook.com');
    final encoded = Uri.encodeComponent(url);
    return 'https://www.facebook.com/plugins/post.php'
        '?href=$encoded'
        '&show_text=true'
        '&width=350';
  }

  factory FBItem.fromUrl(String url) => FBItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        originalUrl: url.trim(),
        embedUrl: buildEmbedUrl(url),
        savedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id':            id,
        'originalUrl':   originalUrl,
        'embedUrl':      embedUrl,
        'savedAt':       savedAt.toIso8601String(),
        'ogTitle':       ogTitle,
        'ogDescription': ogDescription,
        'ogImage':       ogImage,
      };

  factory FBItem.fromJson(Map<String, dynamic> j) {
    final orig = j['originalUrl'] as String? ?? '';
    return FBItem(
      id:            j['id']            as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      originalUrl:   orig,
      embedUrl:      buildEmbedUrl(orig),
      savedAt:       DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
      ogTitle:       j['ogTitle']       as String? ?? '',
      ogDescription: j['ogDescription'] as String? ?? '',
      ogImage:       j['ogImage']       as String? ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WebEnvironmentManager
// ─────────────────────────────────────────────────────────────────────────────
//
// Two isolated WebView2 browser processes via distinct userDataPaths:
//
//  mobileEnv  (.../webview_mobile)   --user-agent="<Galaxy S23 UA>"
//    → Facebook server sees mobile UA → serves mobile layout
//    → Used by: main automation WebView
//
//  desktopEnv (.../webview_desktop)  (default Chromium UA)
//    → facebook.com/plugins/post.php serves the proper embed iframe
//    → Used by: embed cards, share popup dialog
//
class WebEnvironmentManager {
  WebEnvironmentManager._();
  static final WebEnvironmentManager instance = WebEnvironmentManager._();

  bool _mobileReady  = false;
  bool _desktopReady = false;

  Completer<void>? _mobileCompleter;
  Completer<void>? _desktopCompleter;

  static const String mobileUA =
      'Mozilla/5.0 (Linux; Android 13; SM-S911B) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/116.0.0.0 Mobile Safari/537.36';

  Future<void> ensureMobileEnv() async {
    if (_mobileReady) return;
    if (_mobileCompleter != null) return _mobileCompleter!.future;
    _mobileCompleter = Completer<void>();
    try {
      final appSupport = await getApplicationSupportDirectory();
      await WebviewController.initializeEnvironment(
        userDataPath: '${appSupport.path}\\webview_mobile',
        additionalArguments: '--user-agent="$mobileUA"',
      );
      _mobileReady = true;
      _mobileCompleter!.complete();
    } catch (e) {
      _mobileCompleter!.completeError(e);
      _mobileCompleter = null;
      rethrow;
    }
  }

  Future<void> ensureDesktopEnv() async {
    if (_desktopReady) return;
    if (_desktopCompleter != null) return _desktopCompleter!.future;
    _desktopCompleter = Completer<void>();
    try {
      final appSupport = await getApplicationSupportDirectory();
      await WebviewController.initializeEnvironment(
        userDataPath: '${appSupport.path}\\webview_desktop',
      );
      _desktopReady = true;
      _desktopCompleter!.complete();
    } catch (e) {
      _desktopCompleter!.completeError(e);
      _desktopCompleter = null;
      rethrow;
    }
  }

  Future<WebviewController> createMobileController() async {
    assert(_mobileReady);
    final ctrl = WebviewController();
    await ctrl.initialize();
    return ctrl;
  }

  Future<WebviewController> createDesktopController() async {
    assert(_desktopReady);
    final ctrl = WebviewController();
    await ctrl.initialize();
    return ctrl;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EmbedCardController — uses desktopEnv
// ─────────────────────────────────────────────────────────────────────────────

class EmbedCardController extends ChangeNotifier {
  WebviewController? _wvc;
  WebviewController? get wvc => _wvc;

  bool _ready = false;
  bool get ready => _ready;

  final String embedUrl;

  EmbedCardController(this.embedUrl);

  Future<void> init() async {
    if (_wvc != null) return;
    await WebEnvironmentManager.instance.ensureDesktopEnv();
    _wvc = await WebEnvironmentManager.instance.createDesktopController();
    await _wvc!.setBackgroundColor(Colors.white);
    await _wvc!.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
    await _wvc!.loadUrl(embedUrl);
    _ready = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _wvc?.dispose();
    _wvc = null;
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundShareController
// ─────────────────────────────────────────────────────────────────────────────
//
// Owns a hidden desktop WebviewController that handles the share dialog URL
// intercepted from an embed card. Unlike the modal _SharePopupDialog, this
// controller runs silently in the background: it navigates to the share URL,
// waits for the page to load, then auto-submits via the human-like click
// helper. Progress is surfaced through the parent AutomationProvider status.
//
// Usage:
//   final bsc = BackgroundShareController(shareUrl, onDone, onError);
//   await bsc.execute();
//
class BackgroundShareController {
  final String shareUrl;
  final void Function(String msg) onDone;
  final void Function(String msg) onError;

  WebviewController? _wvc;

  BackgroundShareController({
    required this.shareUrl,
    required this.onDone,
    required this.onError,
  });

  Future<void> execute() async {
    try {
      await WebEnvironmentManager.instance.ensureDesktopEnv();
      _wvc = await WebEnvironmentManager.instance.createDesktopController();
      await _wvc!.setBackgroundColor(Colors.white);
      await _wvc!.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      await _wvc!.loadUrl(shareUrl);

      // Wait for navigation to complete.
      final loaded = await _waitForLoad(timeoutMs: 12000);
      if (!loaded) {
        onError('Share dialog timed out.');
        return;
      }

      // Human-like pause before interacting (3–7 s).
      await randomDelay(minMs: 3000, maxMs: 7000);

      // Attempt to find and click the share / post button.
      final dynamic raw = await _wvc!.executeScript(_submitScript);
      final result = _decode(raw);
      final st  = result['status']  as String? ?? '';
      final msg = result['message'] as String? ?? '';

      if (st == 'success') {
        onDone(msg);
      } else {
        onError(msg);
      }
    } catch (e) {
      onError('Background share error: $e');
    } finally {
      _wvc?.dispose();
      _wvc = null;
    }
  }

  Future<bool> _waitForLoad({int timeoutMs = 12000}) async {
    final ctrl = _wvc;
    if (ctrl == null) return false;
    final completer = Completer<bool>();
    StreamSubscription<LoadingState>? sub;
    Future.delayed(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) completer.complete(false);
    });
    sub = ctrl.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted) {
        sub?.cancel();
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!completer.isCompleted) completer.complete(true);
        });
      }
    });
    final result = await completer.future;
    await sub.cancel();
    return result;
  }

  static const String _submitScript = r'''
(function(){
  'use strict';
  // Human-like click: scroll into view, then dispatch mousedown/mouseup/click.
  function humanClick(el) {
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    ['mousedown','mouseup','click'].forEach(function(t){
      el.dispatchEvent(new MouseEvent(t,{bubbles:true,cancelable:true,view:window}));
    });
    el.focus();
    el.click();
  }

  // Look for the primary submit / share button in the dialog.
  var SUBMIT_RE = /^(post|share|share\s+now|send|publish)$/i;
  var btns = document.querySelectorAll('[role="button"], button');
  for (var i = 0; i < btns.length; i++) {
    var b = btns[i];
    var lbl = (b.getAttribute('aria-label') || b.innerText || '').trim();
    if (!SUBMIT_RE.test(lbl)) continue;
    var r = b.getBoundingClientRect();
    if (!r.width || !r.height) continue;
    humanClick(b);
    return JSON.stringify({ status: 'success', message: 'Share submitted via background WebView.' });
  }
  return JSON.stringify({ status: 'failed', message: 'Submit button not found in share dialog.' });
}());
''';

  Map<String, dynamic> _decode(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    var s = raw.toString().trim();
    if (s.isEmpty) return {'status': 'failed', 'message': 'Empty response'};
    try {
      final v = jsonDecode(s);
      if (v is Map) return Map<String, dynamic>.from(v);
      if (v is String) {
        final v2 = jsonDecode(v);
        if (v2 is Map) return Map<String, dynamic>.from(v2);
      }
    } catch (_) {}
    return {'status': 'failed', 'message': 'Non-JSON: $s'};
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legacy page model (Automation tab)
// ─────────────────────────────────────────────────────────────────────────────

class FBPage {
  final String url;
  final String name;
  final String imageUrl;

  const FBPage({required this.url, required this.name, required this.imageUrl});

  Map<String, dynamic> toJson() => {'url': url, 'name': name, 'imageUrl': imageUrl};

  factory FBPage.fromJson(Map<String, dynamic> j) => FBPage(
        url: j['url']      as String? ?? '',
        name: j['name']    as String? ?? 'Unknown Page',
        imageUrl: j['imageUrl'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// AutomationProvider
// ─────────────────────────────────────────────────────────────────────────────

class AutomationProvider extends ChangeNotifier {
  // ── Main WebView (Automation tab) — mobileEnv ─────────────────────────────
  WebviewController? _wvc;
  WebviewController? get webviewController => _wvc;

  Stream<String>?       _urlStream;
  Stream<LoadingState>? _loadingStream;
  Stream<dynamic>?      _webMessageStream; // broadcast — reusable
  Stream<String>?       get urlStream     => _urlStream;
  Stream<LoadingState>? get loadingStream => _loadingStream;

  bool _webViewReady = false;
  bool get webViewReady => _webViewReady;

  // ── Automation state ───────────────────────────────────────────────────────
  AutomationStatus _status   = AutomationStatus.idle;
  String _statusMsg = 'Ready. Add pages and configure a post URL.';
  String _postUrl   = '';
  bool   _stopReq   = false;

  AutomationStatus get status    => _status;
  String           get statusMsg => _statusMsg;
  String           get postUrl   => _postUrl;
  bool get isRunning =>
      _status == AutomationStatus.running ||
      _status == AutomationStatus.navigating;

  // ── Legacy page list ───────────────────────────────────────────────────────
  final List<FBPage> _pages = [];
  FBPage? _selected;
  bool    _isFetching = false;

  List<FBPage> get pages      => List.unmodifiable(_pages);
  FBPage?      get selected   => _selected;
  bool         get isFetching => _isFetching;

  // ── Link Library (Embed Cards) ─────────────────────────────────────────────
  final List<FBItem>                     _items            = [];
  final Map<String, EmbedCardController> _embedControllers = {};

  List<FBItem> get items => List.unmodifiable(_items);

  // ── Groups ─────────────────────────────────────────────────────────────────
  final List<FBGroup> _groups = [];
  bool _groupsFetching = false;
  String? _groupsError;

  // Sync progress state
  bool _isSyncing   = false;
  int  _groupsFound = 0;
  StreamSubscription<dynamic>? _webMsgSub;

  List<FBGroup> get groups         => List.unmodifiable(_groups);
  bool          get groupsFetching => _groupsFetching;
  String?       get groupsError    => _groupsError;
  bool          get isSyncing      => _isSyncing;
  int           get groupsFound    => _groupsFound;

  // ── Prefs keys ─────────────────────────────────────────────────────────────
  static const _kUrl    = 'fb_post_url';
  static const _kPages  = 'fb_pages_list';
  static const _kItems  = 'fb_items_list';
  static const _kGroups = 'fb_groups_list';

  AutomationProvider() { _loadPrefs(); }

  // ── URL helpers ────────────────────────────────────────────────────────────

  /// Normalises any Facebook URL to www.facebook.com.
  /// The mobile UA (set at process level in mobileEnv) causes Facebook's server
  /// to serve the mobile layout regardless of domain.
  static String toAutomationUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
    url = url
        .replaceFirst('https://m.facebook.com',  'https://www.facebook.com')
        .replaceFirst('https://facebook.com',     'https://www.facebook.com')
        .replaceFirst('http://facebook.com',      'https://www.facebook.com');
    return url;
  }

  static String toMobileUrl(String raw) => toAutomationUrl(raw);

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _postUrl = prefs.getString(_kUrl) ?? '';

    final rawPages = prefs.getString(_kPages);
    if (rawPages != null) {
      try {
        final list = jsonDecode(rawPages) as List<dynamic>;
        _pages.addAll(list.map((e) => FBPage.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (_) {}
    }

    final rawItems = prefs.getString(_kItems);
    if (rawItems != null) {
      try {
        final list = jsonDecode(rawItems) as List<dynamic>;
        _items.addAll(list.map((e) => FBItem.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (_) {}
    }

    final rawGroups = prefs.getString(_kGroups);
    if (rawGroups != null) {
      try {
        final list = jsonDecode(rawGroups) as List<dynamic>;
        _groups.addAll(list.map((e) => FBGroup.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUrl,    _postUrl);
    await prefs.setString(_kPages,  jsonEncode(_pages.map((p)  => p.toJson()).toList()));
    await prefs.setString(_kItems,  jsonEncode(_items.map((i)  => i.toJson()).toList()));
    await prefs.setString(_kGroups, jsonEncode(_groups.map((g) => g.toJson()).toList()));
  }

  void setPostUrl(String url) {
    _postUrl = toAutomationUrl(url);
    _savePrefs();
    notifyListeners();
  }

  // ── WebView init (Automation tab — mobileEnv) ─────────────────────────────

  Future<void> initWebView() async {
    if (_wvc != null) return;
    await WebEnvironmentManager.instance.ensureMobileEnv();
    _wvc = await WebEnvironmentManager.instance.createMobileController();

    // ── Developer tools ───────────────────────────────────────────────────
    //
    // webview_windows does NOT have a setSettings / WebviewSettings API.
    // DevTools are opened imperatively via openDevTools() after init.
    // The right-click context menu is enabled by default in WebView2.
    //
    // Call openDevTools() from the UI or debug console at any time.

    await _wvc!.setBackgroundColor(const Color(0xFF121212));
    await _wvc!.setPopupWindowPolicy(WebviewPopupWindowPolicy.allow);

    // ── JS-visible UA patch ───────────────────────────────────────────────
    //
    // The HTTP-level UA is already set at process level via the mobileEnv
    // --user-agent argument, so Facebook's SERVER always sees the mobile UA.
    // This addScriptToExecuteOnDocumentCreated call additionally patches
    // navigator.userAgent so that client-side FB scripts reading it also
    // see the mobile value.  Both layers must be present — removing either
    // causes Facebook to partially revert to the desktop layout.
    //
    await _wvc!.addScriptToExecuteOnDocumentCreated(
      'Object.defineProperty(navigator,"userAgent",'
      '{get:()=>"${WebEnvironmentManager.mobileUA}",configurable:true});'
      'Object.defineProperty(navigator,"platform",'
      '{get:()=>"Linux armv8l",configurable:true});',
    );

    await _wvc!.addScriptToExecuteOnDocumentCreated(r'''
(function(){
  if(window.__fbLeaveSuppressed) return;
  window.__fbLeaveSuppressed = true;
  window.onbeforeunload = null;
  window.addEventListener('beforeunload', function(e){
    e.stopImmediatePropagation(); delete e.returnValue;
  }, true);
  try { Object.defineProperty(window,'onbeforeunload',{get:()=>null,set:()=>{},configurable:true}); } catch(_){}
})();
''');

    await _wvc!.addScriptToExecuteOnDocumentCreated(r'''
(function(){
  if(window.__fbBannerHider) return;
  window.__fbBannerHider = true;
  function hideBanners() {
    ['[data-testid="open_app_banner"]','[data-testid="msite-open-app-banner"]','.smartbanner','#smartbanner'].forEach(function(s){
      try { document.querySelectorAll(s).forEach(function(el){ el.style.setProperty('display','none','important'); }); } catch(_){}
    });
    document.querySelectorAll('div,section,aside,footer').forEach(function(el){
      try {
        var cs = window.getComputedStyle(el);
        if(cs.position!=='fixed'&&cs.position!=='sticky') return;
        var txt=(el.innerText||'').toLowerCase();
        if(txt.indexOf('open app')!==-1||txt.indexOf('install')!==-1||txt.indexOf("isn't supported")!==-1||txt.indexOf('not supported')!==-1)
          el.style.setProperty('display','none','important');
      } catch(_){}
    });
  }
  hideBanners(); setTimeout(hideBanners,800); setTimeout(hideBanners,2000);
  new MutationObserver(hideBanners).observe(document.documentElement,{childList:true,subtree:true});
})();
''');

    await _wvc!.addScriptToExecuteOnDocumentCreated(r'''
(function(){
  if(window.__fbBlankFixed) return;
  window.__fbBlankFixed = true;
  const orig = window.open.bind(window);
  window.open = function(u,t,f){ if(u&&u!=='about:blank'){ window.location.href=u; return window; } return orig(u,t,f); };
  document.addEventListener('click', function(e){
    const a=e.target.closest('a[target="_blank"]');
    if(a&&a.href&&a.href.includes('facebook.com')){ e.preventDefault(); window.location.href=a.href; }
  }, true);
})();
''');

    _urlStream        = _wvc!.url.asBroadcastStream();
    _loadingStream    = _wvc!.loadingState.asBroadcastStream();
    _webMessageStream = _wvc!.webMessage.asBroadcastStream();

    await _wvc!.loadUrl('https://www.facebook.com');
    _webViewReady = true;
    notifyListeners();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> navigateToPost() async {
    if (_wvc == null || _postUrl.isEmpty) return;
    _setStatus(AutomationStatus.navigating, 'Navigating to post…');
    await _wvc!.loadUrl(_postUrl);
    _setStatus(AutomationStatus.idle, 'Post loaded — press Start Automation.');
  }

  Future<void> navigateHome() async => _wvc?.loadUrl('https://www.facebook.com');

  /// Opens the WebView2 DevTools panel for the main automation browser.
  ///
  /// Right-click → Inspect is available by default in WebView2.
  /// Call this method for a programmatic open (e.g. from a debug button).
  /// No-ops if the WebView has not been initialised yet.
  void openDevTools() => _wvc?.openDevTools();

  /// Navigates the main WebView to a group by clicking its DOM element.
  ///
  /// Uses window.navigateToGroup(index) which was registered by the last
  /// fb_group_scraper.js run.  This simulates a real tap on the group row
  /// so Facebook's msite router handles the navigation — no href needed.
  ///
  /// Falls back to URL-based loadUrl() if the group has a url and the
  /// index-based click is not available (e.g. after a page reload).
  Future<void> navigateToGroup(FBGroup group) async {
    if (_wvc == null) return;
    _setStatus(AutomationStatus.navigating, 'Opening group: ${group.name}…');

    var clicked = false;

    if (group.index >= 0) {
      // Try index-based click first — most reliable for msite layout
      try {
        final dynamic result = await _wvc!.executeScript(
          'window.navigateToGroup(${group.index})',
        );
        clicked = (result?.toString() ?? '').contains('true');
        debugPrint('[navigateToGroup] click index=${group.index} result=$result');
      } catch (e) {
        debugPrint('[navigateToGroup] click failed: $e');
      }
    }

    if (!clicked && group.url.isNotEmpty) {
      // Fallback: direct URL navigation
      await _wvc!.loadUrl(toAutomationUrl(group.url));
    }

    // Human-like pause after navigation trigger
    await randomDelay(minMs: 1500, maxMs: 3000);
    _setStatus(AutomationStatus.idle, 'Group loaded: ${group.name}');
  }

  // ── Group fetching ─────────────────────────────────────────────────────────
  //
  // Navigates the main (mobileEnv) WebView to facebook.com/groups/, waits for
  // the page to load, then runs fb_group_scraper.js to extract the joined
  // group list.  A 3–7 s random delay is inserted after navigation to let
  // React hydrate the groups feed before scraping.
  //

  Future<void> fetchGroups() async {
    if (_wvc == null) {
      _groupsError = 'WebView not ready.';
      notifyListeners();
      return;
    }

    await _webMsgSub?.cancel();
    _webMsgSub = null;

    _groupsFetching = true;
    _isSyncing      = true;
    _groupsFound    = 0;
    _groupsError    = null;
    notifyListeners();

    try {
      // Navigate to groups page — user can watch scroll in floating window
      await _wvc!.loadUrl(
          'https://www.facebook.com/groups/');

      final loaded = await _waitForLoad(timeoutMs: 25000, extraMs: 4000);
      if (!loaded) {
        _groupsError = 'Groups page timed out. Check your internet.';
        _isSyncing   = false;
        _groupsFetching = false;
        notifyListeners();
        return;
      }

      // Dismiss open-app banners
      await _wvc!.executeScript(
        '(function(){'
        'var U=/open\\s*app|install|use\\s+mobile/i;'
        'document.querySelectorAll("[data-testid=msite-open-app-banner],[data-testid=open_app_banner],.smartbanner,#smartbanner")'
        '.forEach(function(el){el.style.setProperty("display","none","important");});'
        'document.querySelectorAll("div,a,button").forEach(function(el){'
        'try{var cs=window.getComputedStyle(el);'
        'if(cs.position!=="fixed"&&cs.position!=="sticky")return;'
        'if(U.test(el.innerText||""))el.style.setProperty("display","none","important");'
        '}catch(_){}});'
        '})();'
      );

      // Listen for progress / final messages from JS scraper
      _webMsgSub = _webMessageStream!.listen((dynamic raw) {
        final msg = raw?.toString() ?? '';
        debugPrint('[webMessage] $msg');

        if (msg.startsWith('COUNT:')) {
          // COUNT message may contain DBG: suffix — extract just the number
          final raw = msg.substring(6).trim();
          final numStr = raw.contains(' ') ? raw.split(' ')[0] : raw;
          final n = int.tryParse(numStr) ?? _groupsFound;
          if (n != _groupsFound) {
            _groupsFound = n;
            notifyListeners();
          }
          // Log debug info if present
          if (raw.contains('DBG:')) {
            debugPrint('[Scraper DBG] ${raw.substring(raw.indexOf('DBG:'))}');
          }
        } else if (msg.startsWith('FINAL_DATA:')) {
          _handleFinalData(msg.substring(11).trim());
        }
      });

      // Inject scroll scraper from assets
      final script =
          await rootBundle.loadString('assets/scripts/fb_group_scraper.js');
      await _wvc!.executeScript(script);

      // Safety timeout — 3 minutes
      Future.delayed(const Duration(minutes: 3), () {
        if (_isSyncing) {
          _isSyncing      = false;
          _groupsFetching = false;
          if (_groupsError == null && _groups.isEmpty) {
            _groupsError = 'Sync timed out. Please try again.';
          }
          notifyListeners();
        }
      });

    } catch (e, stack) {
      debugPrint('[fetchGroups] error: $e\n$stack');
      _groupsError    = 'Failed to fetch groups: $e';
      _isSyncing      = false;
      _groupsFetching = false;
      notifyListeners();
    }
  }

  void _handleFinalData(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      List<dynamic> list = [];
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map) {
        list = (decoded['groups'] as List<dynamic>?) ?? [];
      }
      _groups
        ..clear()
        ..addAll(list.map((e) =>
            FBGroup.fromJson(Map<String, dynamic>.from(e as Map))));
      _groupsFound = _groups.length;
      _groupsError = _groups.isEmpty
          ? 'No groups found after full scroll. Make sure you are logged in.'
          : null;
      _savePrefs();
    } catch (e) {
      debugPrint('[_handleFinalData] parse error: $e');
      _groupsError = 'Failed to parse group data: $e';
    } finally {
      _isSyncing      = false;
      _groupsFetching = false;
      _webMsgSub?.cancel();
      _webMsgSub = null;
      notifyListeners();
    }
  }

  void clearGroups() {
    _groups.clear();
    _groupsError = null;
    _savePrefs();
    notifyListeners();
  }

  // ── Link Library: Add / Remove ─────────────────────────────────────────────

  // addItem: URL + optional manual title/description — no scraping needed.
  Future<void> addItem(String url, {String manualTitle = '', String manualDesc = ''}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    var item = FBItem.fromUrl(trimmed);

    // Apply manual meta immediately if provided
    if (manualTitle.isNotEmpty || manualDesc.isNotEmpty) {
      item = item.withMeta(
        title:       manualTitle.trim(),
        description: manualDesc.trim(),
        image:       '',
      );
    }

    _items.insert(0, item);
    await _savePrefs();
    notifyListeners();
  }

  EmbedCardController? controllerFor(String itemId) => _embedControllers[itemId];

  Future<EmbedCardController> getOrCreateController(FBItem item) async {
    if (_embedControllers.containsKey(item.id)) return _embedControllers[item.id]!;
    await WebEnvironmentManager.instance.ensureDesktopEnv();
    final ctrl = EmbedCardController(item.embedUrl);
    _embedControllers[item.id] = ctrl;
    ctrl.addListener(notifyListeners);
    await ctrl.init();
    notifyListeners();
    return ctrl;
  }

  void removeItem(String itemId) {
    final ctrl = _embedControllers.remove(itemId);
    if (ctrl != null) {
      ctrl.removeListener(notifyListeners);
      ctrl.dispose();
    }
    _items.removeWhere((i) => i.id == itemId);
    _savePrefs();
    notifyListeners();
  }

  // ── Background share ───────────────────────────────────────────────────────
  //
  // Called by _EmbedCardState when the url stream intercepts a share dialog
  // URL. Runs the share silently in the background via BackgroundShareController
  // and surfaces progress through the AutomationProvider status.
  //

  Future<void> handleBackgroundShare(String shareUrl) async {
    _setStatus(AutomationStatus.running, '🔄 Background share in progress…');
    await BackgroundShareController(
      shareUrl: shareUrl,
      onDone: (msg) => _setStatus(AutomationStatus.success, '✅ $msg'),
      onError: (msg) => _setStatus(AutomationStatus.error,  '❌ $msg'),
    ).execute();
  }

  // ── Legacy page list ───────────────────────────────────────────────────────

  Future<void> addPageToList(String url) async {
    if (_wvc == null || url.trim().isEmpty) return;
    final automationUrl = toAutomationUrl(url);
    _isFetching = true;
    notifyListeners();
    try {
      await _wvc!.loadUrl(automationUrl);
      final loaded = await _waitForLoad(timeoutMs: 15000, extraMs: 4000);
      if (!loaded) { _setStatus(AutomationStatus.error, '⚠️ Page load timed out.'); return; }
      final finalUrl = await _getFinalUrl() ?? automationUrl;
      const scrapeScript = r'''
(function(){
  'use strict';
  function metaContent(prop) {
    var el=document.querySelector('meta[property="'+prop+'"]')||document.querySelector('meta[name="'+prop+'"]');
    return el?(el.getAttribute('content')||'').trim():'';
  }
  function isUsable(src){ return src&&src.indexOf('data:')!==0&&src.indexOf('blob:')!==0; }
  var SKIP=/^(facebook|log\s?in|sign\s?up|create\s?new|home)$/i;
  function clean(s){return(s||'').trim();} function skip(s){return!s||SKIP.test(s);}
  var name='';
  name=clean(metaContent('og:title')||metaContent('twitter:title'));
  if(skip(name)){var heads=document.querySelectorAll('h1,h2');for(var i=0;i<heads.length;i++){var t=clean(heads[i].innerText);if(t&&!skip(t)){name=t;break;}}}
  if(skip(name)){var dt=document.title.replace(/\s*[|\-\u2013]\s*Facebook\s*$/i,'').trim();if(dt&&!skip(dt))name=dt;}
  if(!name)name='Unknown Page';
  var imageUrl=metaContent('og:image');
  if(!isUsable(imageUrl))imageUrl='';
  return JSON.stringify({status:'success',name:name,imageUrl:imageUrl});
})();
''';
      final dynamic raw = await _wvc!.executeScript(scrapeScript);
      final result = _decodeResult(raw);
      if (result['status'] == 'success') {
        final page = FBPage(
          url: finalUrl,
          name: (result['name'] as String?)?.trim() ?? 'Unknown Page',
          imageUrl: (result['imageUrl'] as String?)?.trim() ?? '',
        );
        _pages.add(page);
        _selected = page;
        await _savePrefs();
      }
    } catch (e) {
      debugPrint('[Provider] addPageToList error: $e');
      _setStatus(AutomationStatus.error, '⚠️ Failed to fetch page info.');
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }

  Future<String?> _getFinalUrl() async {
    try {
      final dynamic raw = await _wvc!.executeScript('window.location.href;');
      final decoded = jsonDecode(raw.toString());
      final href = (decoded is String) ? decoded.trim() : decoded.toString().trim();
      if (href.isEmpty || href == 'about:blank' || href == 'null') return null;
      return href;
    } catch (_) { return null; }
  }

  Future<void> selectPage(FBPage page) async {
    _selected = page;
    notifyListeners();
    await _wvc?.loadUrl(page.url);
  }

  void removePage(FBPage page) {
    _pages.remove(page);
    if (_selected == page) _selected = _pages.isNotEmpty ? _pages.last : null;
    _savePrefs();
    notifyListeners();
  }

  // ── Page-load await ────────────────────────────────────────────────────────

  Future<bool> _waitForLoad({int timeoutMs = 15000, int extraMs = 2000}) async {
    final ctrl = _wvc;
    if (ctrl == null) return false;
    final completer = Completer<bool>();
    StreamSubscription<LoadingState>? sub;
    Future.delayed(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) completer.complete(false);
    });
    sub = ctrl.loadingState.listen((state) {
      if (_stopReq && !completer.isCompleted) { sub?.cancel(); completer.complete(false); return; }
      if (state == LoadingState.navigationCompleted) {
        sub?.cancel();
        Future.delayed(Duration(milliseconds: extraMs), () {
          if (!completer.isCompleted) completer.complete(!_stopReq);
        });
      }
    });
    final result = await completer.future;
    await sub.cancel();
    return result;
  }

  // ── Automation ─────────────────────────────────────────────────────────────

  Future<void> startAutomation() async {
    if (_wvc == null || _postUrl.isEmpty) {
      _setStatus(AutomationStatus.error, '❌ Enter a post URL first.');
      return;
    }
    _stopReq = false;
    _setStatus(AutomationStatus.navigating, '🔄 Loading post…');
    await _wvc!.loadUrl(_postUrl);
    final loaded = await _waitForLoad();
    if (!loaded || _stopReq) {
      _setStatus(AutomationStatus.error, '❌ Page load failed or was stopped.');
      return;
    }
    // Human-like delay before running automation (3–7 s).
    await randomDelay(minMs: 3000, maxMs: 7000);
    await _runMasterScript();
  }

  void stopAutomation() {
    _stopReq = true;
    _setStatus(AutomationStatus.idle, 'Stopped by user.');
  }

  Future<void> _runMasterScript() async {
    if (_wvc == null) return;
    _setStatus(AutomationStatus.running, '🔄 Running automation…');
    try {
      final script = await rootBundle.loadString('assets/scripts/fb_master_script.js');
      final dynamic raw = await _wvc!.executeScript(script);
      final result = _decodeResult(raw);
      final st  = result['status']    as String? ?? 'unknown';
      final msg = result['message']   as String? ?? '';
      final lbl = result['ariaLabel'] as String? ?? '';
      if (st == 'success') {
        _setStatus(AutomationStatus.success, '✅ $msg${lbl.isNotEmpty ? '  [$lbl]' : ''}');
      } else {
        _setStatus(AutomationStatus.error, '❌ $msg');
      }
    } catch (e) {
      _setStatus(AutomationStatus.error, '❌ Script error: $e');
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  Map<String, dynamic> _decodeResult(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    var s = raw.toString().trim();
    if (s.isEmpty) return {'status': 'failed', 'message': 'Empty response'};
    dynamic step1;
    try { step1 = jsonDecode(s); } catch (_) { return {'status': 'failed', 'message': 'Non-JSON: $s'}; }
    if (step1 is Map) return Map<String, dynamic>.from(step1);
    if (step1 is String) {
      try { final step2 = jsonDecode(step1); if (step2 is Map) return Map<String, dynamic>.from(step2); } catch (_) {}
    }
    return {'status': 'failed', 'message': 'Unexpected shape: $s'};
  }

  void _setStatus(AutomationStatus st, String msg) {
    _status    = st;
    _statusMsg = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    _webMsgSub?.cancel();
    _wvc?.dispose();
    for (final ctrl in _embedControllers.values) {
      ctrl.removeListener(notifyListeners);
      ctrl.dispose();
    }
    _embedControllers.clear();
    super.dispose();
  }
}
