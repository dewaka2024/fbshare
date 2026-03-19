// lib/providers/automation_provider.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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
  /// Short group ID extracted from the URL path (e.g. "1234567890" or "mygroup").
  /// Empty until deepSync resolves the real URL.
  final String groupId;

  const FBGroup({
    required this.name,
    required this.index,
    this.imageUrl  = '',
    this.url       = '',
    this.groupId   = '',
    this.categoryId = '',
  });

  /// Category this group belongs to. '' = Uncategorized.
  final String categoryId;

  /// Extract a short group ID from a Facebook group URL.
  /// https://www.facebook.com/groups/1234567890/ → "1234567890"
  static String extractGroupId(String url) {
    if (url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final segments = uri.pathSegments
        .where((s) => s.isNotEmpty && s != 'groups')
        .toList();
    return segments.isNotEmpty ? segments.first : '';
  }

  /// Returns a copy with a new URL (and auto-computed groupId).
  FBGroup withUrl(String newUrl) => FBGroup(
    name:       name,
    index:      index,
    imageUrl:   imageUrl,
    url:        newUrl,
    groupId:    extractGroupId(newUrl),
    categoryId: categoryId,
  );

  /// Returns a copy with a new categoryId.
  FBGroup withCategory(String newCategoryId) => FBGroup(
    name:       name,
    index:      index,
    imageUrl:   imageUrl,
    url:        url,
    groupId:    groupId,
    categoryId: newCategoryId,
  );

  Map<String, dynamic> toJson() => {
        'name':       name,
        'index':      index,
        'imageUrl':   imageUrl,
        'url':        url,
        'groupId':    groupId,
        'categoryId': categoryId,
      };

  factory FBGroup.fromJson(Map<String, dynamic> j) {
    final url = j['url'] as String? ?? '';
    return FBGroup(
      name:       j['name']       as String? ?? 'Unknown Group',
      index:      (j['index']     as num?  )?.toInt() ?? -1,
      imageUrl:   j['imageUrl']   as String? ?? '',
      url:        url,
      groupId:    j['groupId']    as String? ?? FBGroup.extractGroupId(url),
      categoryId: j['categoryId'] as String? ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GroupCategory model
// ─────────────────────────────────────────────────────────────────────────────

/// A named folder for organizing FBGroups.
/// Each group belongs to at most ONE category (categoryId '' = Uncategorized).
class GroupCategory {
  final String id;
  final String name;
  bool isExpanded;

  GroupCategory({required this.id, required this.name, this.isExpanded = true});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory GroupCategory.fromJson(Map<String, dynamic> j) => GroupCategory(
        id:   j['id']   as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: j['name'] as String? ?? 'Category',
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
// WebView2 environment is initialized ONCE in main() before runApp().
// This manager simply creates controllers from that single shared environment.
// The mobile UA is already baked into the environment via main()'s
// --user-agent argument, so all controllers automatically use it.
//
class WebEnvironmentManager {
  WebEnvironmentManager._();
  static final WebEnvironmentManager instance = WebEnvironmentManager._();

  static const String mobileUA =
      'Mozilla/5.0 (Linux; Android 13; SM-S911B) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/116.0.0.0 Mobile Safari/537.36';

  // No-op — environment is initialized in main() already.
  Future<void> ensureMobileEnv()  async {}
  Future<void> ensureDesktopEnv() async {}

  Future<WebviewController> createMobileController() async {
    final ctrl = WebviewController();
    await ctrl.initialize();
    return ctrl;
  }

  Future<WebviewController> createDesktopController() async {
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

  // ── Categories ─────────────────────────────────────────────────────────────
  final List<GroupCategory> _categories = [];

  List<GroupCategory> get categories => List.unmodifiable(_categories);

  List<FBGroup> groupsForCategory(String categoryId) =>
      _groups.where((g) => g.categoryId == categoryId).toList();

  void addCategory(String name) {
    if (name.trim().isEmpty) return;
    _categories.add(GroupCategory(
      id:   DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim(),
    ));
    _savePrefs();
    notifyListeners();
  }

  void removeCategory(String id) {
    // Move all groups in this category back to Uncategorized
    for (int i = 0; i < _groups.length; i++) {
      if (_groups[i].categoryId == id) {
        _groups[i] = _groups[i].withCategory('');
      }
    }
    _categories.removeWhere((c) => c.id == id);
    _savePrefs();
    notifyListeners();
  }

  void toggleCategoryExpanded(String id) {
    final idx = _categories.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    _categories[idx].isExpanded = !_categories[idx].isExpanded;
    notifyListeners();
  }

  /// Move a group to a category. Pass '' for Uncategorized.
  void moveGroupToCategory(String groupName, String categoryId) {
    final idx = _groups.indexWhere((g) => g.name == groupName);
    if (idx == -1) return;
    _groups[idx] = _groups[idx].withCategory(categoryId);
    _savePrefs();
    notifyListeners();
  }

  // Sync progress state
  bool _isSyncing    = false;
  int  _groupsFound  = 0;
  StreamSubscription<dynamic>? _webMsgSub;

  // ── Deep sync state ────────────────────────────────────────────────────
  bool   _isDeepSyncing     = false;
  bool   _stopDeepSync      = false;
  int    _deepSyncIndex     = 0;
  String _highlightedGroup  = ''; // name of group currently being processed
  final List<FBGroup> _deepSyncResults = [];

  List<FBGroup> get groups         => List.unmodifiable(_groups);
  bool          get groupsFetching => _groupsFetching;
  String?       get groupsError    => _groupsError;
  bool          get isSyncing      => _isSyncing;
  int           get groupsFound    => _groupsFound;
  bool          get isDeepSyncing    => _isDeepSyncing;
  int           get deepSyncIndex    => _deepSyncIndex;
  String        get highlightedGroup => _highlightedGroup;

  // ── Prefs keys ─────────────────────────────────────────────────────────────
  static const _kUrl        = 'fb_post_url';
  static const _kPages      = 'fb_pages_list';
  static const _kItems      = 'fb_items_list';
  static const _kGroups     = 'fb_groups_list';
  static const _kCategories = 'fb_categories_list';

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

    final rawCats = prefs.getString(_kCategories);
    if (rawCats != null) {
      try {
        final list = jsonDecode(rawCats) as List<dynamic>;
        _categories.addAll(list.map((e) => GroupCategory.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUrl,        _postUrl);
    await prefs.setString(_kPages,      jsonEncode(_pages.map((p)  => p.toJson()).toList()));
    await prefs.setString(_kItems,      jsonEncode(_items.map((i)  => i.toJson()).toList()));
    await prefs.setString(_kGroups,     jsonEncode(_groups.map((g) => g.toJson()).toList()));
    await prefs.setString(_kCategories, jsonEncode(_categories.map((c) => c.toJson()).toList()));
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


  // ── _saveGroupsToDisk ─────────────────────────────────────────────────────
  //
  // Persists only the groups list immediately.
  // Called inside the deepSync loop after every group is resolved so
  // progress is never lost if the app is closed mid-sync.
  //
  Future<void> _saveGroupsToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kGroups,
      jsonEncode(_groups.map((g) => g.toJson()).toList()),
    );
    await prefs.setString(
      _kCategories,
      jsonEncode(_categories.map((c) => c.toJson()).toList()),
    );
  }

  // ── deepSync ───────────────────────────────────────────────────────────────
  //
  // Strict sequential flow — one group fully resolved before the next starts.
  //
  // Fix for "navigation never started":
  //   The old _waitForGroupNavigation() subscribed to loadingState AFTER
  //   navigateToGroup() was called.  Facebook's msite router fires
  //   LoadingState.loading within ~20-80 ms of the click — well before
  //   the subscription was registered.  The 5-second startTimeoutMs
  //   therefore always expired without seeing the event.
  //
  //   _beginGroupUrlWatch() registers its listener synchronously (zero
  //   awaits before listen()) so it is ALWAYS live before the navigation
  //   trigger runs — this is the key fix.
  //
  // Phase 2 per-group flow:
  //   1. Register URL watcher     <- listener live on current microtask
  //   2. Trigger navigation       <- loadUrl (primary) or click (fallback)
  //   3. Await watcher            <- blocks until group URL or timeout
  //   4. 2-second stabilise       <- inside watcher, handles FB redirects
  //   5. Read window.location.href  <- final canonical URL from address bar
  //   6. _extractGroupId() regex  <- numeric IDs and named slugs
  //   7. _saveGroupsToDisk()      <- persist after every group
  //
  Future<void> deepSync() async {
    if (_wvc == null) {
      _setStatus(AutomationStatus.error, '❌ WebView not ready.');
      return;
    }
    if (_groups.isEmpty) {
      _setStatus(AutomationStatus.error,
          '❌ No groups. Run Sync Groups first.');
      return;
    }

    _isDeepSyncing    = true;
    _stopDeepSync     = false;
    _deepSyncIndex    = 0;
    _highlightedGroup = '';
    _deepSyncResults.clear();
    notifyListeners();

    final total = _groups.length;

    try {
      // ── Phase 1: Load groups page + run scraper ──────────────────
      _setStatus(AutomationStatus.navigating,
          '🔄 Deep Sync: loading groups page…');
      await _wvc!.loadUrl('https://www.facebook.com/groups/');
      await _waitForNavigation(timeoutMs: 28000, extraMs: 3000);
      if (_stopDeepSync) return;

      _setStatus(AutomationStatus.running,
          '🔄 Deep Sync: scanning groups (auto-scrolling)…');

      final script =
          await rootBundle.loadString('assets/scripts/fb_group_scraper.js');

      final scraperDone = Completer<void>();
      StreamSubscription<dynamic>? scraperSub;
      Future.delayed(const Duration(minutes: 3), () {
        if (!scraperDone.isCompleted) scraperDone.complete();
      });
      scraperSub = _webMessageStream?.listen((dynamic raw) {
        final msg = raw?.toString() ?? '';
        if (msg.startsWith('COUNT:')) {
          final n = int.tryParse(
                  msg.substring(6).trim().split(' ').first) ??
              0;
          _setStatus(AutomationStatus.running,
              '🔄 Deep Sync: found $n groups so far…');
          notifyListeners();
        } else if (msg.startsWith('FINAL_DATA:')) {
          _handleFinalData(msg.substring(11).trim());
          scraperSub?.cancel();
          if (!scraperDone.isCompleted) scraperDone.complete();
        }
      });

      await _wvc!.executeScript(script);
      await scraperDone.future;
      await scraperSub?.cancel();
      if (_stopDeepSync) return;

      await Future.delayed(const Duration(milliseconds: 600));

      final dynamic foundLen = await _wvc!
          .executeScript('window.__foundGroups ? window.__foundGroups.length : -1');
      debugPrint('[deepSync] Phase 1 complete. __foundGroups.length = $foundLen');

      // ── Phase 2: Navigate each group — strictly one-by-one ───────
      //
      // ROOT CAUSE FIX:
      //   Facebook msite uses history.pushState() for client-side routing.
      //   WebView2's url stream ONLY fires on real navigations (loadUrl /
      //   hard redirect).  A JS click that triggers pushState() is
      //   completely invisible to the url stream — which is why every
      //   previous approach got "navigation never started".
      //
      //   Fix: fb_group_scraper.js now patches history.pushState and
      //   history.replaceState to call postMessage('NAV_URL:<url>').
      //   For Strategy B (JS click) we listen on _webMessageStream.
      //   For Strategy A (loadUrl) we use _urlStream as before since
      //   a real navigation DOES fire it.
      //
      for (int i = 0; i < total; i++) {
        if (_stopDeepSync) break;

        _deepSyncIndex    = i;
        _highlightedGroup = _groups[i].name;
        _setStatus(
          AutomationStatus.running,
          '🔄 Processing ${i + 1}/$total — ${_groups[i].name}',
        );
        notifyListeners();

        // ── Highlight row (best-effort) ────────────────────────────
        try {
          await _wvc!.executeScript(
            '(function(){'
            '  if (!window.__foundGroups) return;'
            '  window.__foundGroups.forEach(function(el){'
            '    el.style.outline=""; el.style.background="";'
            '  });'
            '  var el = window.__foundGroups[${_groups[i].index}];'
            '  if (!el) return;'
            '  el.scrollIntoView({behavior:"smooth",block:"center"});'
            '  el.style.outline="3px solid #1877F2";'
            '  el.style.background="rgba(24,119,242,0.12)";'
            '})()',
          );
        } catch (e) {
          debugPrint('[deepSync] highlight #$i failed: $e');
        }
        await Future.delayed(const Duration(milliseconds: 500));
        if (_stopDeepSync) break;

        final String existingUrl = _groups[i].url;
        String resolvedUrl;

        if (existingUrl.isNotEmpty) {
          // ── Strategy A: direct loadUrl ─────────────────────────
          // WebView2 url stream fires for real navigations.
          // ⚡ Watch BEFORE loadUrl — no await above this.
          debugPrint('[deepSync] #$i Strategy A loadUrl — ${_groups[i].name}');
          final urlWatch = _waitForNavUrl(
            fallback: existingUrl,
            context: '#$i',
            useWebMessage: false,
          );
          await _wvc!.loadUrl(existingUrl);
          resolvedUrl = await urlWatch;

        } else {
          // ── Strategy B: JS click → history.pushState → NAV_URL: msg
          // ⚡ Watch BEFORE click — no await above this.
          debugPrint('[deepSync] #$i Strategy B click — ${_groups[i].name}');
          final urlWatch = _waitForNavUrl(
            fallback: '',
            context: '#$i',
            useWebMessage: true,
          );

          bool navTriggered = false;
          try {
            final dynamic res = await _wvc!.executeScript(
              'typeof window.navigateToGroup === "function"'
              ' ? String(window.navigateToGroup(${_groups[i].index}))'
              ' : "missing"',
            );
            final resStr = res?.toString() ?? '';
            navTriggered = resStr.contains('true');
            debugPrint('[deepSync] #$i navigateToGroup(${_groups[i].index}) → $resStr');
          } catch (e) {
            debugPrint('[deepSync] #$i JS click error: $e');
          }

          if (!navTriggered) {
            debugPrint('[deepSync] #$i skipped — navigateToGroup unavailable');
            _deepSyncResults.add(_groups[i]);
            continue;
          }
          resolvedUrl = await urlWatch;
        }

        if (_stopDeepSync) break;
        debugPrint('[deepSync] #$i resolvedUrl="$resolvedUrl"');

        // ── Extract groupId with regex ─────────────────────────────
        final extractedId = _extractGroupId(resolvedUrl);
        debugPrint('[deepSync] #$i extractedId="$extractedId"');

        final updated = FBGroup(
          name:     _groups[i].name,
          index:    _groups[i].index,
          imageUrl: _groups[i].imageUrl,
          url:      resolvedUrl.isNotEmpty ? resolvedUrl : existingUrl,
          groupId:  extractedId.isNotEmpty ? extractedId : _groups[i].groupId,
        );

        _groups[i] = updated;
        _deepSyncResults.add(updated);

        _setStatus(
          AutomationStatus.running,
          '💾 Saving: ${updated.name} (${i + 1}/$total)',
        );
        notifyListeners();

        await _saveGroupsToDisk();
        debugPrint('[deepSync] #$i saved. url="${updated.url}" groupId="${updated.groupId}"');
      }

      // ── Clear highlights ────────────────────────────────────────────
      try {
        await _wvc!.executeScript(
          'if(window.__foundGroups) window.__foundGroups.forEach('
          'function(el){el.style.outline="";el.style.background="";});',
        );
      } catch (_) {}

      _highlightedGroup = '';
      if (_stopDeepSync) {
        _setStatus(AutomationStatus.idle,
            '⏹ Deep Sync stopped — '
            '${_deepSyncResults.length}/$total saved.');
      } else {
        _setStatus(AutomationStatus.success,
            '✅ Deep Sync complete — '
            '${_deepSyncResults.length} groups resolved.');
      }

    } catch (e, stack) {
      debugPrint('[deepSync] fatal error: $e\n$stack');
      _setStatus(AutomationStatus.error, '❌ Deep Sync error: $e');
    } finally {
      _isDeepSyncing    = false;
      _highlightedGroup = '';
      notifyListeners();
    }
  }

  void stopDeepSync() {
    _stopDeepSync = true;
    _highlightedGroup = '';
    _setStatus(AutomationStatus.idle, 'Deep Sync stopping…');
    notifyListeners();
  }

  // ── _waitForNavUrl ────────────────────────────────────────────────────────
  //
  // Unified URL watcher for deepSync.  Supports two modes:
  //
  //   useWebMessage: false  (Strategy A — loadUrl)
  //     Listens on _urlStream (WebView2 url stream).
  //     WebView2 fires this stream for every real navigation (loadUrl,
  //     HTTP redirect).  Works correctly for Strategy A.
  //
  //   useWebMessage: true   (Strategy B — JS click)
  //     Listens on _webMessageStream for NAV_URL: messages.
  //     Facebook uses history.pushState() for client-side routing after
  //     a JS click — this is INVISIBLE to WebView2's url stream.
  //     fb_group_scraper.js patches pushState/replaceState to call
  //     window.chrome.webview.postMessage('NAV_URL:<url>') so we can
  //     catch the SPA navigation here.
  //
  // ⚡ CRITICAL: This function has ZERO awaits before the listen() call.
  //    Dart runs code before the first await synchronously on the current
  //    microtask.  The caller does:
  //      final watch = _waitForNavUrl(...);   // listener registered NOW
  //      await _wvc.loadUrl(...);             // trigger AFTER
  //      final url = await watch;             // catches the event
  //    This eliminates the race condition entirely.
  //
  // After a valid URL is detected, waits 2 s for FB's redirect chain to
  // settle, then reads window.location.href for the final canonical URL.
  //
  Future<String> _waitForNavUrl({
    required String fallback,
    String context        = '',
    bool   useWebMessage  = false,
    int    timeoutMs      = 22000,
  }) {
    final completer = Completer<String>();
    StreamSubscription? sub;
    Timer? timer;

    void resolve(String url) {
      if (completer.isCompleted) return;
      sub?.cancel();
      timer?.cancel();
      completer.complete(url);
    }

    // Hard timeout guard.
    timer = Timer(Duration(milliseconds: timeoutMs), () {
      debugPrint('[waitForNavUrl][$context] timed out (${timeoutMs}ms) — fallback');
      resolve(fallback);
    });

    // ⚡ NO await above this line.
    if (useWebMessage) {
      // Strategy B: listen for NAV_URL: messages from the patched pushState.
      sub = _webMessageStream?.listen((dynamic raw) {
        if (completer.isCompleted) return;
        if (_stopDeepSync) { resolve(fallback); return; }

        final msg = raw?.toString() ?? '';
        if (!msg.startsWith('NAV_URL:')) return;

        final url = msg.substring(8).trim();
        if (!_isGroupDetailUrl(url)) return;

        debugPrint('[waitForNavUrl][$context] NAV_URL detected: $url');
        _stabiliseAndResolve(url, resolve, context, completer);
      });
    } else {
      // Strategy A: listen on WebView2 url stream for real navigations.
      sub = _urlStream?.listen((String url) {
        if (completer.isCompleted) return;
        if (_stopDeepSync) { resolve(fallback); return; }
        if (!_isGroupDetailUrl(url)) return;

        debugPrint('[waitForNavUrl][$context] urlStream detected: $url');
        _stabiliseAndResolve(url, resolve, context, completer);
      });
    }

    if (sub == null) {
      debugPrint('[waitForNavUrl][$context] stream is null — fallback');
      timer.cancel();
      resolve(fallback);
    }

    return completer.future;
  }

  // ── _stabiliseAndResolve ──────────────────────────────────────────────────
  //
  // Called when a candidate group URL is first detected.  Waits 2 seconds
  // for Facebook's redirect chain to settle (slug → numeric ID etc.), then
  // reads window.location.href from the live WebView for the final URL.
  //
  void _stabiliseAndResolve(
    String candidateUrl,
    void Function(String) resolve,
    String context,
    Completer<String> completer,
  ) {
    Future.delayed(const Duration(seconds: 2), () async {
      if (completer.isCompleted) return;
      String finalUrl = candidateUrl.split('?').first;
      try {
        // Read the live address bar — catches any further redirect.
        final dynamic raw =
            await _wvc?.executeScript('window.location.href;');
        if (raw != null) {
          String href = raw.toString().trim();
          // webview_windows double-JSON-encodes the return value.
          if (href.startsWith('"') && href.endsWith('"')) {
            href = jsonDecode(href) as String;
          }
          if (href.isNotEmpty &&
              href != 'about:blank' &&
              _isGroupDetailUrl(href)) {
            finalUrl = href.split('?').first;
            debugPrint('[waitForNavUrl][$context] stabilised: $finalUrl');
          }
        }
      } catch (e) {
        debugPrint('[waitForNavUrl][$context] href read error: $e');
      }
      resolve(finalUrl);
    });
  }

  // ── _isGroupDetailUrl ──────────────────────────────────────────────────────
  //
  // Returns true only for URLs representing a real group detail page.
  // Filters out the list root, feed, discover, and other noise paths.
  //
  static bool _isGroupDetailUrl(String url) {
    if (!url.contains('/groups/')) return false;
    if (RegExp(r'facebook\.com/groups/?\??(?:#.*)?$', caseSensitive: false)
        .hasMatch(url)) {
      return false;
    }
    const noiseSegments = {
      'feed', 'discover', 'create', 'join', 'search',
      'members', 'requests', 'videos', 'photos', 'events',
      'files', 'about', 'announcements', 'topics',
    };
    final match =
        RegExp(r'/groups/([^/?#]+)', caseSensitive: false).firstMatch(url);
    final segment = match?.group(1) ?? '';
    return segment.isNotEmpty &&
        !noiseSegments.contains(segment.toLowerCase());
  }

  // ── _extractGroupId ────────────────────────────────────────────────────────
  //
  // Requirement 4: Regex-based group ID extraction.
  //   Numeric: facebook.com/groups/123456789/   → '123456789'
  //   Named:   facebook.com/groups/my-group/    → 'my-group'
  //
  static String _extractGroupId(String url) {
    if (url.isEmpty) return '';
    final match = RegExp(
      r'facebook\.com/groups/([a-zA-Z0-9][a-zA-Z0-9._\-]*)',
      caseSensitive: false,
    ).firstMatch(url);
    final id = match?.group(1) ?? '';
    if (id.isEmpty) return '';
    const noiseSegments = {
      'feed', 'discover', 'create', 'join', 'search',
      'members', 'requests', 'videos', 'photos', 'events',
      'files', 'about', 'announcements', 'topics',
    };
    return noiseSegments.contains(id.toLowerCase()) ? '' : id;
  }


  Future<bool> _waitForNavigation({
    int timeoutMs = 18000,
    int extraMs   = 1500,
  }) async {
    final ctrl = _wvc;
    if (ctrl == null) return false;

    final completer = Completer<bool>();
    StreamSubscription<LoadingState>? sub;

    // Timeout guard
    final timer = Future.delayed(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) completer.complete(false);
    });

    sub = ctrl.loadingState.listen((state) {
      // Abort immediately if deep sync was stopped
      if (_stopDeepSync && !completer.isCompleted) {
        sub?.cancel();
        completer.complete(false);
        return;
      }
      if (state == LoadingState.navigationCompleted &&
          !completer.isCompleted) {
        sub?.cancel();
        // Extra wait for React hydration / lazy-load
        Future.delayed(Duration(milliseconds: extraMs), () {
          if (!completer.isCompleted) {
            completer.complete(!_stopDeepSync);
          }
        });
      }
    });

    final result = await completer.future;
    await sub.cancel();
    // ignore: unawaited_futures — timer future is fire-and-forget
    timer.ignore();
    return result;
  }

  // ── Link Library: Add / Remove ─────────────────────────────────────────────

  // addItem: saves URL immediately, then fetches OG meta via HTTP in background.
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

    // Insert immediately — tile appears right away
    _items.insert(0, item);
    await _savePrefs();
    notifyListeners();

    // Fetch OG meta in background without disturbing the WebView session
    _fetchOgMeta(item.id, trimmed);
  }

  /// Fetches OG meta (title + image) directly via HTTP without navigating
  /// the WebView. Parses <meta property="og:..."> tags from the raw HTML.
  /// Fire-and-forget — errors are silently logged.
  Future<void> _fetchOgMeta(String itemId, String rawUrl) async {
    try {
      final url = toAutomationUrl(rawUrl);

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 12);
      // Use a desktop UA so Facebook's server returns a crawlable HTML page
      // (mobile UA often returns a JS-only shell with no OG tags)
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.0.0 Safari/537.36');
      request.headers.set(HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      request.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');

      final response = await request.close()
          .timeout(const Duration(seconds: 12));
      client.close();

      if (response.statusCode != 200) return;

      final bytes   = await response.fold<List<int>>(
          [], (prev, chunk) => prev..addAll(chunk));
      final html    = String.fromCharCodes(bytes);

      final title = _extractOgTag(html, 'og:title') ??
                    _extractOgTag(html, 'twitter:title') ??
                    _extractTitleTag(html) ?? '';
      final image = _extractOgTag(html, 'og:image') ??
                    _extractOgTag(html, 'twitter:image') ?? '';

      final idx = _items.indexWhere((i) => i.id == itemId);
      if (idx == -1) return;
      if (title.isEmpty && image.isEmpty) return;

      _items[idx] = _items[idx].withMeta(
        title:       title.isNotEmpty ? title : _items[idx].ogTitle,
        description: _items[idx].ogDescription,
        image:       image,
      );
      await _savePrefs();
      notifyListeners();
      debugPrint('[_fetchOgMeta] ✅ title="$title" image="${image.length > 40 ? '${image.substring(0,40)}…' : image}"');
    } catch (e) {
      debugPrint('[_fetchOgMeta] error: $e');
    }
  }

  /// Extracts content of a <meta property="NAME"> or <meta name="NAME"> tag.
  static String? _extractOgTag(String html, String property) {
    // Match both property= and name= variants, single and double quotes
    final patterns = [
      RegExp('<meta[^>]+property=["\']${RegExp.escape(property)}["\'][^>]+content=["\'](.*?)["\']',
          caseSensitive: false, dotAll: true),
      RegExp('<meta[^>]+content=["\'](.*?)["\'][^>]+property=["\']${RegExp.escape(property)}["\']',
          caseSensitive: false, dotAll: true),
      RegExp('<meta[^>]+name=["\']${RegExp.escape(property)}["\'][^>]+content=["\'](.*?)["\']',
          caseSensitive: false, dotAll: true),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(html);
      if (m != null) {
        final val = _htmlDecode(m.group(1) ?? '').trim();
        if (val.isNotEmpty) return val;
      }
    }
    return null;
  }

  static String? _extractTitleTag(String html) {
    final m = RegExp('<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true)
        .firstMatch(html);
    if (m == null) return null;
    final t = _htmlDecode(m.group(1) ?? '').trim();
    // Strip " | Facebook" suffix
    return t.replaceAll(RegExp(r'\s*[|\-–]\s*Facebook\s*$', caseSensitive: false), '').trim();
  }

  static String _htmlDecode(String s) => s
      .replaceAll('&amp;',  '&')
      .replaceAll('&lt;',   '<')
      .replaceAll('&gt;',   '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;',  "'")
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.tryParse(m.group(1) ?? '');
        return code != null ? String.fromCharCode(code) : m.group(0)!;
      });

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
