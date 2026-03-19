// lib/ui/floating_webview_window.dart
//
// Draggable floating "mobile phone" WebView window.
// ─────────────────────────────────────────────────────────────────────────────
// • Fixed mobile size: 320 × 580 content area.
// • Looks like a phone: rounded frame, top notch, drag-handle bar.
// • GestureDetector-based drag — moves freely anywhere on screen.
// • Show/Hide toggle collapses to a compact pill (WebView stays alive).
// • Address bar + Home / DevTools action buttons in the phone chrome.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart';

import '../providers/automation_provider.dart';

// ── Design tokens (keep in sync with home_screen.dart) ──────────────────────
const _surface = Color(0xFF141720);
const _card    = Color(0xFF1A1E28);
const _border  = Color(0xFF252A38);
const _accent  = Color(0xFF1877F2);
const _green   = Color(0xFF23D18B);
const _red     = Color(0xFFFF4F5E);
const _sub     = Color(0xFF5A6180);
const _subL    = Color(0xFF8894B8);
const _text    = Color(0xFFE8ECF4);

// Phone chrome dimensions
const double _phoneW      = 320.0;  // content width
const double _phoneH      = 580.0;  // content height
const double _frameTop    = 52.0;   // top chrome height (notch + address bar)
const double _frameBottom = 30.0;   // bottom chrome height
const double _borderW     = 12.0;   // phone frame border thickness
const double _cornerR     = 36.0;   // outer corner radius

// Total widget size (frame + content)
const double _totalW = _phoneW + _borderW * 2;
const double _totalH = _phoneH + _frameTop + _frameBottom;

// ─────────────────────────────────────────────────────────────────────────────
// FloatingWebViewWindow
// ─────────────────────────────────────────────────────────────────────────────

class FloatingWebViewWindow extends StatefulWidget {
  const FloatingWebViewWindow({super.key});

  @override
  State<FloatingWebViewWindow> createState() => _FloatingWebViewWindowState();
}

class _FloatingWebViewWindowState extends State<FloatingWebViewWindow>
    with SingleTickerProviderStateMixin {
  // ── Position state ─────────────────────────────────────────────────────────
  Offset _position = const Offset(80, 80);
  Offset _dragStart = Offset.zero;
  Offset _posStart  = Offset.zero;

  // ── Visibility / animation ─────────────────────────────────────────────────
  bool _visible = true;
  late final AnimationController _animCtrl;
  late final Animation<double>    _scaleAnim;
  late final Animation<double>    _fadeAnim;

  bool _wasSyncing = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn);
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-show the floating window when group sync starts
    final syncing = context.read<AutomationProvider>().isSyncing;
    if (syncing && !_wasSyncing && !_visible) {
      setState(() => _visible = true);
      _animCtrl.forward();
    }
    _wasSyncing = syncing;
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Drag handlers ──────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    _dragStart = d.globalPosition;
    _posStart  = _position;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final delta = d.globalPosition - _dragStart;
    setState(() {
      _position = _posStart + delta;
    });
  }

  // ── Show / Hide toggle ─────────────────────────────────────────────────────

  void _toggleVisible() {
    if (_visible) {
      _animCtrl.reverse().then((_) {
        if (mounted) setState(() => _visible = false);
      });
    } else {
      setState(() => _visible = true);
      _animCtrl.forward();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top:  _position.dy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Toggle pill ──────────────────────────────────────────────────
          GestureDetector(
            onPanStart:  _onPanStart,
            onPanUpdate: _onPanUpdate,
            child: _TogglePill(visible: _visible, onToggle: _toggleVisible),
          ),
          const SizedBox(height: 6),

          // ── Phone frame (animated show/hide) ──────────────────────────────
          if (_visible)
            FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                alignment: Alignment.topRight,
                child: _PhoneFrame(
                  onDragStart:  _onPanStart,
                  onDragUpdate: _onPanUpdate,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle pill (drag + show/hide button)
// ─────────────────────────────────────────────────────────────────────────────

class _TogglePill extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggle;
  const _TogglePill({required this.visible, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();

    // Status dot color
    final Color dotColor;
    switch (prov.status) {
      case AutomationStatus.success:
        dotColor = _green;
      case AutomationStatus.error:
        dotColor = _red;
      case AutomationStatus.running:
      case AutomationStatus.navigating:
        dotColor = const Color(0xFFFFB830);
      default:
        dotColor = _sub;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag grip icon
              const Icon(Icons.drag_indicator_rounded, size: 13, color: _sub),
              const SizedBox(width: 6),
              // FB badge
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(4)),
                child: const Center(
                  child: Text('f', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, height: 1)),
                ),
              ),
              const SizedBox(width: 6),
              const Text('WebView', style: TextStyle(color: _text, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 7),
              // Status dot
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: dotColor.withValues(alpha: .5), blurRadius: 4)],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                visible ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: _subL,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone frame
// ─────────────────────────────────────────────────────────────────────────────

class _PhoneFrame extends StatelessWidget {
  final GestureDragStartCallback  onDragStart;
  final GestureDragUpdateCallback onDragUpdate;

  const _PhoneFrame({required this.onDragStart, required this.onDragUpdate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  _totalW,
      height: _totalH,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0C12),
        borderRadius: BorderRadius.circular(_cornerR),
        border: Border.all(color: const Color(0xFF30364A), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 40, offset: Offset(0, 12)),
          BoxShadow(color: Color(0x22000000), blurRadius: 80, offset: Offset(0, 24)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_cornerR - 1.5),
        child: Column(
          children: [
            // ── Top chrome: drag handle + notch + address bar ──────────────
            GestureDetector(
              onPanStart:  onDragStart,
              onPanUpdate: onDragUpdate,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(
                height: _frameTop,
                child: _PhoneTopChrome(),
              ),
            ),
            // ── WebView content ────────────────────────────────────────────
            Expanded(
              child: Container(
                color: const Color(0xFF121212),
                child: const _PhoneWebViewBody(),
              ),
            ),
            // ── Bottom chrome: home bar ────────────────────────────────────
            GestureDetector(
              onPanStart:  onDragStart,
              onPanUpdate: onDragUpdate,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(
                height: _frameBottom,
                child: _PhoneBottomChrome(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top chrome ────────────────────────────────────────────────────────────────

class _PhoneTopChrome extends StatelessWidget {
  const _PhoneTopChrome();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();

    return Container(
      color: const Color(0xFF0D0F14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Notch row ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Row(
              children: [
                // Status bar time placeholder
                const Text('12:00', style: TextStyle(color: _sub, fontSize: 9, fontWeight: FontWeight.w700)),
                const Spacer(),
                // Notch pill
                Container(
                  width: 80, height: 12,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const Spacer(),
                // Signal icons
                const Icon(Icons.signal_cellular_alt, color: _sub, size: 10),
                const SizedBox(width: 3),
                const Icon(Icons.battery_full_rounded, color: _sub, size: 10),
              ],
            ),
          ),
          // ── Address bar row ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: _sub, size: 9),
                  const SizedBox(width: 4),
                  Expanded(
                    child: StreamBuilder<String>(
                      stream: prov.urlStream,
                      builder: (_, snap) => Text(
                        snap.data ?? 'facebook.com',
                        style: const TextStyle(color: _sub, fontSize: 9),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Loading indicator
                  StreamBuilder<LoadingState>(
                    stream: prov.loadingStream,
                    builder: (_, snap) {
                      if (snap.data == LoadingState.loading) {
                        return const SizedBox(
                          width: 8, height: 8,
                          child: CircularProgressIndicator(strokeWidth: 1, color: _accent),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  // Home button
                  GestureDetector(
                    onTap: prov.webViewReady ? prov.navigateHome : null,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Icon(Icons.home_rounded, size: 12, color: _subL),
                    ),
                  ),
                  // DevTools button
                  GestureDetector(
                    onTap: prov.webViewReady ? prov.openDevTools : null,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Icon(Icons.code_rounded, size: 12, color: _subL),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── WebView body ──────────────────────────────────────────────────────────────

class _PhoneWebViewBody extends StatelessWidget {
  const _PhoneWebViewBody();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    final wvc  = prov.webviewController;

    if (wvc == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
            SizedBox(height: 10),
            Text('Initialising…', style: TextStyle(color: _sub, fontSize: 10)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Webview(wvc),
        // Loading overlay
        StreamBuilder<LoadingState>(
          stream: prov.loadingStream,
          builder: (_, snap) {
            if (snap.data != LoadingState.loading) return const SizedBox.shrink();
            return Container(
              color: const Color(0x99121212),
              child: const Center(
                child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Bottom chrome ─────────────────────────────────────────────────────────────

class _PhoneBottomChrome extends StatelessWidget {
  const _PhoneBottomChrome();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _frameBottom,
      color: const Color(0xFF0D0F14),
      alignment: Alignment.center,
      child: Container(
        width: 100,
        height: 4,
        decoration: BoxDecoration(
          color: _border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
