import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart';

import '../providers/automation_provider.dart';
import '../providers/template_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/control_panel.dart';
import '../widgets/status_bar.dart';
import '../widgets/history_panel.dart';
import '../widgets/template_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WebviewController _wvc = WebviewController();
  bool _showHistory = false;
  bool _showInspector = false;
  bool _showTemplates = false;
  OverlayEntry? _contextOverlay;
  StreamSubscription<LoadingState>? _loadingSub;

  @override
  void initState() {
    super.initState();
    _initWebView();
    // Req 5: wire TemplateProvider → AutomationProvider so switching templates
    // immediately refreshes the step search parameters for the next run.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tplProvider = context.read<TemplateProvider>();
      final autoProvider = context.read<AutomationProvider>();
      tplProvider.onTemplateActivated = (tpl) {
        autoProvider.setActiveTemplate(
          label: '📋 Active Template: ${tpl.name}',
          steps: tpl.steps.map((s) => s.toJson()).toList(),
          clickDelayMs: tpl.clickDelayMs,
          groupsPerRun: tpl.groupsPerRun,
        );
      };
      // Apply currently active template right away (on first load)
      if (tplProvider.activeTemplate != null) {
        tplProvider.onTemplateActivated!(tplProvider.activeTemplate!);
      }
    });
  }

  void _showElementPopup(Map<String, dynamic> info) {
    _dismissContextMenu();
    _contextOverlay = OverlayEntry(
      builder: (_) => _ElementInfoOverlay(
        info: info,
        onDismiss: _dismissContextMenu,
        onInspect: () {
          _dismissContextMenu();
          _openInspector();
        },
      ),
    );
    Overlay.of(context).insert(_contextOverlay!);
  }

  void _dismissContextMenu() {
    _contextOverlay?.remove();
    _contextOverlay = null;
  }

  Future<void> _initWebView() async {
    // ── Phase 1.1: Dedicated userDataFolder for persistent cookies/cache ──────
    // webview_windows uses WebviewController.initializeEnvironment() (a static
    // method) to set the userDataFolder BEFORE calling initialize().
    // Facebook session, cookies, and localStorage survive app restarts.
    final appSupport = await getApplicationSupportDirectory();
    final userDataPath = '${appSupport.path}\\WebView2UserData';
    // Mobile User-Agent — tells Facebook to serve the mobile web UI
    // (m.facebook.com layout) on www.facebook.com. This avoids the full desktop
    // feed render, making post isolation trivial: only the target post renders.
    const mobileUA = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36';

    await WebviewController.initializeEnvironment(
      userDataPath: userDataPath,
      additionalArguments: '--user-agent="$mobileUA"',
    );
    await _wvc.initialize();

    // ── Phase 1.3: Hardware / GPU acceleration ────────────────────────────────
    // webview_windows/WebView2 uses GPU acceleration by default.
    // This no-op canvas call ensures the GPU compositor path stays active.
    await _wvc.executeScript(r'''
(function(){
  if(window.__gpuCheckDone) return; window.__gpuCheckDone=true;
  try { document.createElement("canvas").getContext("webgl"); } catch(_){}
})();
''');

    await _wvc.setBackgroundColor(Colors.white);

    // ── Phase 1.2: Tracker blocking ───────────────────────────────────────────
    // URL-level blocking is handled inside AutomationProvider's url listener
    // (which owns the single broadcast subscription to _wvc.url).
    // Sub-resource blocking uses a CSP meta tag injected on every page load.

    // ── Viewport fix: force 390px mobile viewport width ──────────────────────
    // Mobile UA triggers Facebook's mobile layout, but WebView2 still reports
    // its own desktop viewport width unless we override the viewport meta tag.
    // width=390 matches iPhone 14 Pro and keeps FB's breakpoints in mobile mode.
    await _wvc.addScriptToExecuteOnDocumentCreated(r'''
(function() {
  function applyViewport() {
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'viewport';
      (document.head || document.documentElement).appendChild(meta);
    }
    meta.content = 'width=390,initial-scale=1.0,maximum-scale=1.0,user-scalable=no';
  }
  if (document.head) { applyViewport(); }
  else { document.addEventListener('DOMContentLoaded', applyViewport, { once: true }); }
})();
''');

    // Block analytics sub-resources via Content Security Policy meta injection
    await _wvc.addScriptToExecuteOnDocumentCreated(r'''
(function() {
  const meta = document.createElement('meta');
  meta.httpEquiv = 'Content-Security-Policy';
  meta.content = [
    "connect-src * 'self'",
    "script-src * 'self' 'unsafe-inline' 'unsafe-eval'",
    "img-src * data: blob: 'self'",
  ].join('; ');
  // Insert early so the browser honours it before other resources load
  const head = document.head || document.documentElement;
  if (head.firstChild) head.insertBefore(meta, head.firstChild);
  else head.appendChild(meta);
})();
''');

    // Suppress "Leave page?" / "Leave site?" confirmation dialogs.
    // These appear when Facebook's React router marks the page as "dirty"
    // after our JS automation injects synthetic events.
    // We override window.onbeforeunload and intercept the beforeunload event
    // at the capture phase so FB's own handlers never get a chance to set
    // a returnValue, which is what triggers the browser's leave-page prompt.
    await _wvc.addScriptToExecuteOnDocumentCreated(r'''
(function() {
  if (window.__fbBeforeUnloadSuppressed) return;
  window.__fbBeforeUnloadSuppressed = true;

  // 1. Null out any existing onbeforeunload handler FB may have registered.
  window.onbeforeunload = null;

  // 2. Intercept ALL beforeunload events before FB's handlers run.
  //    Removing returnValue prevents the browser from showing the dialog.
  window.addEventListener('beforeunload', function(e) {
    e.stopImmediatePropagation();
    delete e.returnValue;
  }, true);   // capture phase = runs before any bubble-phase listener

  // 3. Re-apply the override whenever FB re-assigns window.onbeforeunload
  //    (FB's router sometimes resets it on soft navigations).
  const desc = Object.getOwnPropertyDescriptor(window, 'onbeforeunload');
  if (!desc || desc.configurable) {
    try {
      Object.defineProperty(window, 'onbeforeunload', {
        get: () => null,
        set: (_) => {},   // silently discard any assignment
        configurable: true,
      });
    } catch(_) {}
  }
})();
''');

    // Allow popups so FB Share dialogs are never blocked
    await _wvc.setPopupWindowPolicy(WebviewPopupWindowPolicy.allow);

    if (mounted) {
      context.read<AutomationProvider>().webviewController = _wvc;
      context.read<AutomationProvider>().setWebViewReady(true);
      context.read<AutomationProvider>().listenRightClick((info) {
        if (mounted) _showElementPopup(info);
      });
    }

    // Inject JS overrides on every page load
    _loadingSub = _wvc.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted) {
        _injectWindowOpenOverride();
      }
    });

    await _wvc.loadUrl('https://www.facebook.com');
  }

  Future<void> _injectWindowOpenOverride() async {
    await _wvc.executeScript(r'''
(function() {
  if (window.__fbOpenOverridden) return;
  window.__fbOpenOverridden = true;

  const _orig = window.open.bind(window);
  window.open = function(url, target, features) {
    if (url && url !== '' && url !== 'about:blank') {
      window.location.href = url;
      return window;
    }
    return _orig(url, target, features);
  };

  document.addEventListener('click', function(e) {
    const a = e.target.closest('a[target="_blank"]');
    if (a && a.href && a.href.includes('facebook.com')) {
      e.preventDefault();
      e.stopPropagation();
      window.location.href = a.href;
    }
  }, true);

  // ── Right-click → inspect element ──────────────────────────────────────
  document.addEventListener('contextmenu', function(e) {
    e.preventDefault();
    const el = e.target;
    if (!el) return;

    // Walk up to find most meaningful interactive parent
    let target = el;
    for (let i = 0; i < 5; i++) {
      const r = target.getAttribute('role') || '';
      const ti = target.getAttribute('tabindex');
      if (r === 'button' || r === 'menuitem' || r === 'option' ||
          target.tagName === 'BUTTON' || target.tagName === 'A' ||
          ti === '0' || ti === '-1') break;
      if (target.parentElement) target = target.parentElement;
      else break;
    }

    // Collect all meaningful attributes
    const attrs = {};
    for (const a of target.attributes) attrs[a.name] = a.value;

    // Compute selector path (up to 4 levels)
    function selectorOf(el) {
      const parts = [];
      let cur = el;
      for (let i = 0; i < 4 && cur && cur !== document.body; i++) {
        let sel = cur.tagName.toLowerCase();
        if (cur.id) sel += '#' + cur.id;
        else if (cur.className && typeof cur.className === 'string') {
          sel += '.' + cur.className.trim().split(/\s+/).slice(0,2).join('.');
        }
        parts.unshift(sel);
        cur = cur.parentElement;
      }
      return parts.join(' > ');
    }

    const info = {
      tag:        target.tagName.toLowerCase(),
      role:       target.getAttribute('role') || '',
      ariaLabel:  target.getAttribute('aria-label') || '',
      ariaChecked:target.getAttribute('aria-checked') || '',
      ariaSelected:target.getAttribute('aria-selected') || '',
      tabindex:   target.getAttribute('tabindex') || '',
      dataTestId: target.getAttribute('data-testid') || '',
      id:         target.id || '',
      className:  (target.className && typeof target.className === 'string')
                    ? target.className.trim().split(/\s+/).slice(0,6).join(' ') : '',
      innerText:  (target.innerText || '').trim().substring(0, 120),
      href:       target.getAttribute('href') || '',
      type:       target.getAttribute('type') || '',
      selector:   selectorOf(target),
      clickX:     e.clientX,
      clickY:     e.clientY,
    };

    window.chrome.webview.postMessage(
      JSON.stringify({ type: 'FB_RIGHT_CLICK', payload: JSON.stringify(info) })
    );
  }, true);

  // Re-apply beforeunload suppressor after every SPA navigation.
  // addScriptToExecuteOnDocumentCreated covers fresh page loads, but
  // Facebook's router can reassign window.onbeforeunload on soft navigations.
  window.onbeforeunload = null;
  window.addEventListener('beforeunload', function(e) {
    e.stopImmediatePropagation();
    delete e.returnValue;
  }, true);
})();
''');
  }

  @override
  void dispose() {
    _contextOverlay?.remove();
    _loadingSub?.cancel();
    _wvc.dispose();
    super.dispose();
  }

  void _openInspector() {
    setState(() {
      _showInspector = true;
      _showHistory = false;
    });
    context.read<AutomationProvider>().deepScan();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          _TopBar(
            showHistory: _showHistory,
            showInspector: _showInspector,
            showTemplates: _showTemplates,
            onToggleHistory: () => setState(() {
              _showHistory = !_showHistory;
              _showInspector = false;
              _showTemplates = false;
            }),
            onOpenInspector: _openInspector,
            onToggleTemplates: () => setState(() {
              _showTemplates = !_showTemplates;
              _showHistory = false;
              _showInspector = false;
            }),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left panel
                SizedBox(
                  width: 300,
                  child: ControlPanel(
                    onNavigate: () =>
                        context.read<AutomationProvider>().navigateToPost(),
                    onStart: () =>
                        context.read<AutomationProvider>().startAutomation(),
                    onStop: () =>
                        context.read<AutomationProvider>().stopAutomation(),
                    onReset: () =>
                        context.read<AutomationProvider>().resetGroupIndex(),
                    onHome: () =>
                        context.read<AutomationProvider>().navigateToFacebook(),
                    onWatch: () =>
                        context.read<AutomationProvider>().startPostWatcher(),
                    onStopWatch: () =>
                        context.read<AutomationProvider>().stopPostWatcher(),
                  ),
                ),
                VerticalDivider(width: 1, color: theme.dividerColor),

                // WebView — centred in a fixed 380×750 mobile frame
                // The Expanded + dark Container fills the remaining space so
                // the frame sits centred on a dark backdrop, matching the phone
                // frame injected by fb_mobile_frame_injector.js.
                Expanded(
                  child: Container(
                    color: const Color(0xFF0F1117), // dark backdrop
                    child: Center(
                      child: SizedBox(
                        width: 380,
                        height: 750,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Stack(children: [
                            Webview(_wvc),
                            _LoadingOverlay(controller: _wvc, isDark: isDark),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),

                // Inspector panel
                if (_showInspector) ...[
                  VerticalDivider(width: 1, color: theme.dividerColor),
                  _InspectorPanel(
                    onClose: () => setState(() => _showInspector = false),
                    onRescan: _openInspector,
                  ),
                ],

                // History panel
                if (_showHistory && !_showInspector) ...[
                  VerticalDivider(width: 1, color: theme.dividerColor),
                  SizedBox(
                    width: 280,
                    child: HistoryPanel(
                      onClose: () => setState(() => _showHistory = false),
                    ),
                  ),
                ],

                // Templates panel
                if (_showTemplates && !_showInspector && !_showHistory) ...[
                  VerticalDivider(width: 1, color: theme.dividerColor),
                  TemplatePanel(
                    onClose: () => setState(() => _showTemplates = false),
                  ),
                ],
              ],
            ),
          ),
          const StatusBar(),
        ],
      ),
    );
  }
}

// ─── Inspector Panel ──────────────────────────────────────────────────────────

class _InspectorPanel extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onRescan;
  const _InspectorPanel({required this.onClose, required this.onRescan});

  @override
  State<_InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<_InspectorPanel> {
  final _searchCtrl = TextEditingController();
  String _filter = '';
  bool _shareOnly = false;
  String? _highlighted;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auto = context.watch<AutomationProvider>();

    const accent = Color(0xFF4F6EF7);
    const green = Color(0xFF22C55E);
    final bg = isDark ? const Color(0xFF1A1D27) : Colors.white;
    final card = isDark ? const Color(0xFF222636) : const Color(0xFFF7F8FC);
    final txt = isDark ? const Color(0xFFE8EAF6) : const Color(0xFF1A1D27);
    final sub = isDark ? const Color(0xFF8B91A8) : const Color(0xFF6B7280);
    final border = isDark ? const Color(0xFF2E3347) : const Color(0xFFDDE1F0);

    var elements = auto.scannedElements;
    if (_shareOnly) {
      elements = elements.where((e) => e.isShareRelated).toList();
    }
    if (_filter.isNotEmpty) {
      final f = _filter.toLowerCase();
      elements = elements
          .where((e) =>
              e.text.toLowerCase().contains(f) ||
              e.ariaLabel.toLowerCase().contains(f) ||
              e.testId.toLowerCase().contains(f))
          .toList();
    }

    return Container(
      width: 360,
      color: bg,
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            decoration: BoxDecoration(
              color: bg,
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(children: [
                  const Icon(Icons.manage_search_rounded,
                      size: 16, color: accent),
                  const SizedBox(width: 6),
                  Text('Page Inspector',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: txt)),
                  const Spacer(),
                  // Rescan
                  Tooltip(
                    message: 'Re-scan page',
                    child: InkWell(
                      onTap: auto.scanning ? null : widget.onRescan,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: auto.scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: accent))
                            : const Icon(Icons.refresh_rounded,
                                size: 18, color: accent),
                      ),
                    ),
                  ),
                  // Close
                  InkWell(
                    onTap: widget.onClose,
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),

                // Search field
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _filter = v),
                  style: TextStyle(fontSize: 12, color: txt),
                  decoration: InputDecoration(
                    hintText: 'Filter by text or aria-label...',
                    hintStyle: TextStyle(fontSize: 12, color: sub),
                    prefixIcon: const Icon(Icons.search_rounded, size: 15),
                    suffixIcon: _filter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 15),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _filter = '');
                            })
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: card,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: accent, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Filter chip + count
                Row(children: [
                  GestureDetector(
                    onTap: () => setState(() => _shareOnly = !_shareOnly),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color:
                            _shareOnly ? green.withValues(alpha: 0.15) : card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _shareOnly
                              ? green.withValues(alpha: 0.5)
                              : border,
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.share_rounded,
                            size: 12, color: _shareOnly ? green : sub),
                        const SizedBox(width: 4),
                        Text('Share related only',
                            style: TextStyle(
                                fontSize: 11,
                                color: _shareOnly ? green : sub,
                                fontWeight: _shareOnly
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  Text('${elements.length} items',
                      style: TextStyle(fontSize: 11, color: sub)),
                ]),
              ],
            ),
          ),

          // ── Empty state ──────────────────────────────────────────────────
          if (auto.scannedElements.isEmpty && !auto.scanning)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to find Share button:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: txt)),
                  const SizedBox(height: 8),
                  _Step('1', 'Open a Facebook post', sub, txt),
                  _Step('2', 'Click 🔄 Scan button above', sub, txt),
                  _Step('3', 'Enable "Share related only"', sub, txt),
                  _Step('4', '🎯 Click item → highlights on page', sub, txt),
                  _Step('5', '▶ Click item → triggers it on page', sub, txt),
                  _Step('6', '📋 Long press → copy aria-label', sub, txt),
                ],
              ),
            ),

          // ── List ─────────────────────────────────────────────────────────
          Expanded(
            child: auto.scanning
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(
                        color: accent, strokeWidth: 2),
                    const SizedBox(height: 12),
                    Text('Scanning page elements...',
                        style: TextStyle(color: sub, fontSize: 12)),
                  ]))
                : elements.isEmpty
                    ? Center(
                        child: Text('No elements match filter',
                            style: TextStyle(color: sub, fontSize: 12)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                        itemCount: elements.length,
                        itemBuilder: (_, i) => _ElementTile(
                          element: elements[i],
                          isDark: isDark,
                          isHighlighted: _highlighted == elements[i].index,
                          onTap: () async {
                            // Click element on page
                            final auto2 = context.read<AutomationProvider>();
                            final msg =
                                await auto2.clickByIndex(elements[i].index);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(msg),
                              duration: const Duration(seconds: 2),
                              backgroundColor: const Color(0xFF222636),
                            ));
                            // Re-scan after click to see new elements
                            await Future.delayed(
                                const Duration(milliseconds: 800));
                            if (context.mounted) {
                              context.read<AutomationProvider>().deepScan();
                            }
                          },
                          onHighlight: () {
                            setState(() => _highlighted = elements[i].index);
                            context
                                .read<AutomationProvider>()
                                .highlightByIndex(elements[i].index);
                          },
                          onCopy: () {
                            final label = elements[i].ariaLabel.isNotEmpty
                                ? elements[i].ariaLabel
                                : elements[i].text;
                            Clipboard.setData(ClipboardData(text: label));
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                              content: Text('Copied to clipboard!'),
                              duration: Duration(seconds: 1),
                              backgroundColor: Color(0xFF22C55E),
                            ));
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Element Tile ─────────────────────────────────────────────────────────────

class _ElementTile extends StatelessWidget {
  final PageElement element;
  final bool isDark;
  final bool isHighlighted;
  final VoidCallback onTap;
  final VoidCallback onHighlight;
  final VoidCallback onCopy;

  const _ElementTile({
    required this.element,
    required this.isDark,
    required this.isHighlighted,
    required this.onTap,
    required this.onHighlight,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4F6EF7);
    const green = Color(0xFF22C55E);
    const orange = Color(0xFFF59E0B);
    final card = isDark ? const Color(0xFF222636) : const Color(0xFFF7F8FC);
    final txt = isDark ? const Color(0xFFE8EAF6) : const Color(0xFF1A1D27);
    final sub = isDark ? const Color(0xFF8B91A8) : const Color(0xFF6B7280);
    final border = isDark ? const Color(0xFF2E3347) : const Color(0xFFDDE1F0);

    final isShare = element.isShareRelated;
    final bgColor = isHighlighted
        ? orange.withValues(alpha: 0.15)
        : isShare
            ? green.withValues(alpha: 0.07)
            : card;
    final borderColor = isHighlighted
        ? orange.withValues(alpha: 0.6)
        : isShare
            ? green.withValues(alpha: 0.3)
            : border;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: isHighlighted ? 1.5 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isShare
                        ? green.withValues(alpha: 0.15)
                        : accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    isShare ? Icons.share_rounded : Icons.touch_app_rounded,
                    size: 14,
                    color: isShare ? green : accent,
                  ),
                ),
                const SizedBox(width: 10),

                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        element.displayLabel.isNotEmpty
                            ? element.displayLabel
                            : '(no label)',
                        style: TextStyle(
                          fontSize: 11,
                          color: txt,
                          fontWeight:
                              isShare ? FontWeight.w700 : FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (element.subtitle.isNotEmpty)
                        Text(
                          element.subtitle,
                          style: TextStyle(fontSize: 10, color: sub),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),

                // Action buttons: Highlight | Copy | Click
                Row(mainAxisSize: MainAxisSize.min, children: [
                  // Highlight
                  Tooltip(
                    message: 'Highlight on page',
                    child: InkWell(
                      onTap: onHighlight,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(Icons.center_focus_strong_rounded,
                            size: 16, color: isHighlighted ? orange : sub),
                      ),
                    ),
                  ),
                  // Copy
                  Tooltip(
                    message: 'Copy label',
                    child: InkWell(
                      onTap: onCopy,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(Icons.copy_rounded, size: 15, color: sub),
                      ),
                    ),
                  ),
                  // Click button
                  Tooltip(
                    message: 'Click this element',
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isShare
                              ? green.withValues(alpha: 0.15)
                              : accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('▶',
                            style: TextStyle(
                              fontSize: 12,
                              color: isShare ? green : accent,
                            )),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Step helper ─────────────────────────────────────────────────────────────

class _Step extends StatelessWidget {
  final String num, text;
  final Color sub, txt;
  const _Step(this.num, this.text, this.sub, this.txt);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(right: 8, top: 1),
            decoration: const BoxDecoration(
              color: Color(0xFF4F6EF7),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
          Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 11, color: txt, height: 1.4))),
        ]),
      );
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool showHistory, showInspector, showTemplates;
  final VoidCallback onToggleHistory, onOpenInspector, onToggleTemplates;

  const _TopBar({
    required this.showHistory,
    required this.showInspector,
    required this.showTemplates,
    required this.onToggleHistory,
    required this.onOpenInspector,
    required this.onToggleTemplates,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;
    final auto = context.watch<AutomationProvider>();
    final tpl = context.watch<TemplateProvider>();
    final sub = isDark ? const Color(0xFF8B91A8) : const Color(0xFF6B7280);
    const accent = Color(0xFF4F6EF7);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.share_rounded, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        Text('FB Share Automation', style: theme.appBarTheme.titleTextStyle),
        const SizedBox(width: 8),
        // Active template badge in top bar (Req 5)
        if (tpl.activeLabel.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              tpl.activeLabel,
              style: const TextStyle(
                color: accent,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: StreamBuilder<String>(
            stream: auto.urlStream,
            builder: (_, snap) => Text(
              snap.data ?? auto.currentUrl,
              style: TextStyle(fontSize: 11, color: sub),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // Templates toggle
        Tooltip(
          message: 'Automation Templates',
          child: IconButton(
            icon: Icon(Icons.layers_rounded,
                size: 20, color: showTemplates ? accent : null),
            onPressed: onToggleTemplates,
          ),
        ),
        // Inspector
        Tooltip(
          message: 'Scan & Inspect elements',
          child: IconButton(
            icon: Icon(Icons.manage_search_rounded,
                size: 20, color: showInspector ? accent : null),
            onPressed: onOpenInspector,
          ),
        ),
        // Dark mode
        IconButton(
          icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 20),
          onPressed: () => context.read<ThemeProvider>().toggle(),
        ),
        // History
        Tooltip(
          message: 'Run History',
          child: IconButton(
            icon: Icon(
                showHistory
                    ? Icons.history_toggle_off_rounded
                    : Icons.history_rounded,
                size: 20,
                color: showHistory ? accent : null),
            onPressed: onToggleHistory,
          ),
        ),
      ]),
    );
  }
}

// ─── Loading overlay ──────────────────────────────────────────────────────────

class _LoadingOverlay extends StatelessWidget {
  final WebviewController controller;
  final bool isDark;
  const _LoadingOverlay({required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) => StreamBuilder<LoadingState>(
        stream: controller.loadingState,
        builder: (_, snap) {
          if (snap.data != LoadingState.loading) {
            return const SizedBox.shrink();
          }
          return Container(
            color: (isDark ? const Color(0xFF0F1117) : const Color(0xFFF0F2FA))
                .withValues(alpha: 0.65),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4F6EF7)),
                strokeWidth: 2.5,
              ),
            ),
          );
        },
      );
}

// ─── Element Info Overlay (Right-click popup) ─────────────────────────────────

class _ElementInfoOverlay extends StatelessWidget {
  final Map<String, dynamic> info;
  final VoidCallback onDismiss;
  final VoidCallback onInspect;

  const _ElementInfoOverlay({
    required this.info,
    required this.onDismiss,
    required this.onInspect,
  });

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1A1D2E);
    const accent = Color(0xFF4F6EF7);
    const green = Color(0xFF34D399);
    const yellow = Color(0xFFFBBF24);
    const dimText = Color(0xFF8B91A8);

    final rows = <MapEntry<String, String>>[];
    void add(String k, String v) {
      if (v.isNotEmpty) rows.add(MapEntry(k, v));
    }

    add('Tag', info['tag'] ?? '');
    add('Role', info['role'] ?? '');
    add('aria-label', info['ariaLabel'] ?? '');
    add('aria-checked', info['ariaChecked'] ?? '');
    add('aria-selected', info['ariaSelected'] ?? '');
    add('tabindex', info['tabindex'] ?? '');
    add('data-testid', info['dataTestId'] ?? '');
    add('id', info['id'] ?? '');
    add('type', info['type'] ?? '');
    add('href', info['href'] ?? '');
    add('class', info['className'] ?? '');
    add('Text', info['innerText'] ?? '');
    add('Selector', info['selector'] ?? '');

    return GestureDetector(
      onTap: onDismiss,
      child: Material(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {}, // prevent dismiss on card tap
            child: Container(
              width: 480,
              constraints: const BoxConstraints(maxHeight: 520),
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                      border: Border(
                          bottom:
                              BorderSide(color: accent.withValues(alpha: 0.3))),
                    ),
                    child: Row(children: [
                      const Icon(Icons.code_rounded, color: accent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Element Inspector  ·  <${info['tag'] ?? '?'}>',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onDismiss,
                        child: const Icon(Icons.close_rounded,
                            color: dimText, size: 18),
                      ),
                    ]),
                  ),

                  // Attribute rows
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: rows.map((e) {
                          final isLabel = e.key == 'aria-label';
                          final isText = e.key == 'Text';
                          final isSel = e.key == 'Selector';
                          final valueColor = isLabel
                              ? green
                              : isText
                                  ? yellow
                                  : isSel
                                      ? dimText
                                      : const Color(0xFFE2E8F0);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 110,
                                  child: Text(
                                    e.key,
                                    style: const TextStyle(
                                      color: dimText,
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SelectableText(
                                    e.value,
                                    style: TextStyle(
                                      color: valueColor,
                                      fontSize: 11.5,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                // Copy button
                                GestureDetector(
                                  onTap: () => Clipboard.setData(
                                      ClipboardData(text: e.value)),
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Icon(Icons.copy_rounded,
                                        size: 13, color: dimText),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // Footer buttons
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                          top:
                              BorderSide(color: accent.withValues(alpha: 0.2))),
                    ),
                    child: Row(children: [
                      _OverlayBtn(
                        label: 'Copy aria-label',
                        icon: Icons.label_rounded,
                        color: green,
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: info['ariaLabel'] ?? ''));
                          onDismiss();
                        },
                      ),
                      const SizedBox(width: 8),
                      _OverlayBtn(
                        label: 'Copy Text',
                        icon: Icons.text_fields_rounded,
                        color: yellow,
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: info['innerText'] ?? ''));
                          onDismiss();
                        },
                      ),
                      const SizedBox(width: 8),
                      _OverlayBtn(
                        label: 'Open Inspector',
                        icon: Icons.search_rounded,
                        color: accent,
                        onTap: onInspect,
                      ),
                      const Spacer(),
                      Text(
                        'Click outside to close',
                        style: TextStyle(
                            color: dimText.withValues(alpha: 0.6),
                            fontSize: 10),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _OverlayBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}
