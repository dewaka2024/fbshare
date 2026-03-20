// lib/ui/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/automation_provider.dart';
import 'floating_webview_window.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
const _bg      = Color(0xFF0D0F14);
const _surface = Color(0xFF141720);
const _card    = Color(0xFF1A1E28);
const _cardHov = Color(0xFF1F2433);
const _border  = Color(0xFF252A38);
const _accent  = Color(0xFF1877F2);
const _accentL = Color(0xFF4A9BFF);
const _green   = Color(0xFF23D18B);
const _red     = Color(0xFFFF4F5E);
const _amber   = Color(0xFFFFB830);
const _text    = Color(0xFFE8ECF4);
const _sub     = Color(0xFF5A6180);
const _subL    = Color(0xFF8894B8);
const _divider = Color(0xFF1C2030);

// ─────────────────────────────────────────────────────────────────────────────
// Root scaffold
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen — thin shell kept for backwards compat, delegates to MainScreen
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => const MainScreen();
}

// ─────────────────────────────────────────────────────────────────────────────
// MainScreen — Navigation Rail + page switcher
// ─────────────────────────────────────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AutomationProvider>().initWebView();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Row(
            children: [
              // ── Left Navigation Rail ─────────────────────────────────────
              _AppNavRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (i) =>
                    setState(() => _selectedIndex = i),
              ),
              // ── Right content area ───────────────────────────────────────
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: const [
                    _AutomationPage(),
                    _FollowUpPage(),
                  ],
                ),
              ),
            ],
          ),
          // Floating WebView overlay (always on top)
          const FloatingWebViewWindow(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navigation Rail
// ─────────────────────────────────────────────────────────────────────────────
class _AppNavRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  const _AppNavRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();

    return Container(
      width: 72,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(right: BorderSide(color: _divider)),
      ),
      child: Column(
        children: [
          // ── App logo ──────────────────────────────────────────────────────
          const SizedBox(height: 16),
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x441877F2), blurRadius: 12,
                    offset: Offset(0, 3)),
              ],
            ),
            child: const Center(
              child: Text('f',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1)),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: _divider, height: 1, indent: 12, endIndent: 12),
          const SizedBox(height: 8),

          // ── Nav destinations ──────────────────────────────────────────────
          _NavItem(
            icon: Icons.smart_toy_rounded,
            label: 'Automation',
            selected: selectedIndex == 0,
            onTap: () => onDestinationSelected(0),
            badgeCount: prov.groups.length,
          ),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.person_add_rounded,
            label: 'Follow-up',
            selected: selectedIndex == 1,
            onTap: () => onDestinationSelected(1),
          ),

          const Spacer(),
          const Divider(color: _divider, height: 1, indent: 12, endIndent: 12),
          const SizedBox(height: 12),

          // ── Status dot ───────────────────────────────────────────────────
          Tooltip(
            message: prov.webViewReady ? 'WebView ready' : 'Initialising…',
            child: Container(
              width: 7, height: 7,
              decoration: BoxDecoration(
                color: prov.webViewReady ? _green : _sub,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: (prov.webViewReady ? _green : _sub)
                          .withValues(alpha: .5),
                      blurRadius: 6,
                      spreadRadius: 1),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Profile avatar placeholder ────────────────────────────────────
          Tooltip(
            message: 'Profile',
            child: Container(
              width: 36, height: 36,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: _card,
                shape: BoxShape.circle,
                border: Border.all(color: _border, width: 1.5),
              ),
              child: const Icon(Icons.person_rounded, color: _sub, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single nav rail item ───────────────────────────────────────────────────────
class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final color  = active ? _accent : (_hovered ? _subL : _sub);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? _accent.withValues(alpha: .12)
                : _hovered
                    ? _card.withValues(alpha: .6)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active
                ? Border.all(color: _accent.withValues(alpha: .25))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(widget.icon, color: color, size: 22),
                  if (widget.badgeCount > 0)
                    Positioned(
                      top: -4, right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.badgeCount > 99
                              ? '99+'
                              : '${widget.badgeCount}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 7.5,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                    color: color,
                    fontSize: 8.5,
                    fontWeight: active
                        ? FontWeight.w700
                        : FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Automation Page  (index 0)
// NEW: Professional 3-Column Dashboard
//   Col 1 (25%): Post Repository   — add/select FB post links
//   Col 2 (40%): Group Categorizer — sync, deep sync, organize groups
//   Col 3 (35%): Live Status Log   — progress bar + terminal-style log
// All functionality wired to the existing AutomationProvider.
// ─────────────────────────────────────────────────────────────────────────────
class _AutomationPage extends StatefulWidget {
  const _AutomationPage();
  @override
  State<_AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends State<_AutomationPage> {
  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Column 1 — Post Repository (flex 25)
        Expanded(flex: 25, child: _Col1PostRepository()),
        // Column 2 — Group Categorizer (flex 40)
        Expanded(flex: 40, child: _Col2GroupCategorizer()),
        // Column 3 — Live Status Log (flex 35)
        Expanded(flex: 35, child: _Col3LiveStatus()),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// COLUMN 1 — Post Repository
// ══════════════════════════════════════════════════════════════════════════════
class _Col1PostRepository extends StatefulWidget {
  const _Col1PostRepository();
  @override
  State<_Col1PostRepository> createState() => _Col1PostRepositoryState();
}

class _Col1PostRepositoryState extends State<_Col1PostRepository> {
  final _urlCtrl   = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _urlFocus  = FocusNode();
  final _nameFocus = FocusNode();
  final _descFocus = FocusNode();
  bool _adding = false;

  @override
  void dispose() {
    _urlCtrl.dispose(); _nameCtrl.dispose(); _descCtrl.dispose();
    _urlFocus.dispose(); _nameFocus.dispose(); _descFocus.dispose();
    super.dispose();
  }

  Future<void> _save(AutomationProvider prov) async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || _adding) return;
    setState(() => _adding = true);
    final savedDesc = _descCtrl.text.trim();
    final savedName = _nameCtrl.text.trim();
    _urlCtrl.clear(); _nameCtrl.clear(); _descCtrl.clear();
    await prov.addItem(url, manualTitle: savedName, manualDesc: savedDesc);
    if (mounted) setState(() => _adding = false);
    _urlFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(right: BorderSide(color: _divider)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Column header ─────────────────────────────────────────────────
        _DashColHeader(icon: Icons.bookmark_rounded, title: 'Post Repository', badge: prov.items.length),

        // ── Add new link form ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: _DashCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.add_link_rounded, size: 13, color: _accentL),
              const SizedBox(width: 6),
              Text('ADD NEW LINK', style: _dashLabelStyle()),
            ]),
            const SizedBox(height: 9),
            _ThemedTextField(
              controller: _urlCtrl,
              focusNode: _urlFocus,
              hint: 'https://facebook.com/…',
              prefixIcon: Icons.link_rounded,
              showPaste: true,
              onSubmitted: (_) => _nameFocus.requestFocus(),
            ),
            const SizedBox(height: 7),
            _ThemedTextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              hint: 'Post name / title',
              prefixIcon: Icons.title_rounded,
              onSubmitted: (_) => _descFocus.requestFocus(),
            ),
            const SizedBox(height: 7),
            _ThemedTextField(
              controller: _descCtrl,
              focusNode: _descFocus,
              hint: 'Description (optional)',
              prefixIcon: Icons.notes_rounded,
              onSubmitted: (_) => _save(prov),
            ),
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity, height: 36,
              child: _DashAccentButton(
                icon: Icons.bookmark_add_rounded,
                label: _adding ? 'Saving…' : 'Save Post',
                onPressed: _adding ? null : () => _save(prov),
              ),
            ),
          ])),
        ),

        // ── Saved posts list header ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Text('SAVED POSTS', style: _dashLabelStyle()),
            const Spacer(),
            if (prov.items.isNotEmpty)
              Text('${prov.items.length}',
                  style: const TextStyle(color: _subL, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 6),

        // ── Posts list ────────────────────────────────────────────────────
        Expanded(
          child: prov.items.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inbox_rounded, color: _sub, size: 32),
                  SizedBox(height: 8),
                  Text('No posts saved yet', style: TextStyle(color: _sub, fontSize: 12)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                  itemCount: prov.items.length,
                  itemBuilder: (_, i) {
                    final item = prov.items[i];
                    final isSelected = prov.postUrl == item.originalUrl;
                    return _PostRepositoryTile(
                      item: item,
                      isSelected: isSelected,
                      onTap: () => prov.setPostUrl(item.originalUrl),
                      onDelete: () => prov.removeItem(item.id),
                    );
                  },
                ),
        ),

        // ── START AUTOMATION button ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: _StartSharingButton(),
        ),
      ]),
    );
  }
}

// Post tile in repository
class _PostRepositoryTile extends StatefulWidget {
  final FBItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PostRepositoryTile({required this.item, required this.isSelected, required this.onTap, required this.onDelete});
  @override
  State<_PostRepositoryTile> createState() => _PostRepositoryTileState();
}

class _PostRepositoryTileState extends State<_PostRepositoryTile> {
  bool _hovered = false;

  // Pick a consistent accent color per post based on id hash
  Color get _iconColor {
    final colors = [_accent, const Color(0xFF7C3AED), const Color(0xFF0EA5E9),
                    _green, const Color(0xFFEC4899), _amber];
    return colors[widget.item.id.hashCode.abs() % colors.length];
  }

  String get _displayName {
    if (widget.item.ogTitle.isNotEmpty) return widget.item.ogTitle;
    final uri = Uri.tryParse(widget.item.originalUrl);
    if (uri != null) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) return segs.last;
    }
    return widget.item.originalUrl;
  }

  String get _shortUrl {
    final uri = Uri.tryParse(widget.item.originalUrl);
    if (uri == null) return widget.item.originalUrl;
    final path = uri.path.length > 28 ? '${uri.path.substring(0, 28)}…' : uri.path;
    return '${uri.host}$path';
  }

  @override
  Widget build(BuildContext context) {
    final sel  = widget.isSelected;
    final item = widget.item;
    final c    = _iconColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: sel ? c.withValues(alpha: .12) : (_hovered ? _cardHov : _card),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: sel ? c.withValues(alpha: .55) : (_hovered ? c.withValues(alpha: .25) : _border),
              width: sel ? 1.5 : 1,
            ),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Icon box ─────────────────────────────────────────────────
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: c.withValues(alpha: sel ? .22 : .13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.article_rounded, size: 18, color: c),
            ),
            const SizedBox(width: 10),

            // ── Text content ──────────────────────────────────────────────
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Name / title
                Text(
                  _displayName,
                  style: TextStyle(
                    color: sel ? _text : _subL,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Description
                if (item.ogDescription.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.ogDescription,
                    style: TextStyle(
                      color: sel ? _subL : _sub,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 5),
                // URL chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      'f',
                      style: TextStyle(
                        color: c,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _shortUrl,
                        style: const TextStyle(color: _sub, fontSize: 9.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
              ]),
            ),

            // ── Right actions ─────────────────────────────────────────────
            const SizedBox(width: 4),
            Column(children: [
              if (sel)
                Icon(Icons.check_circle_rounded, color: c, size: 15)
              else if (_hovered)
                GestureDetector(
                  onTap: widget.onDelete,
                  child: const Icon(Icons.close_rounded, color: _sub, size: 15),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}
class _StartSharingButton extends StatefulWidget {
  @override
  State<_StartSharingButton> createState() => _StartSharingButtonState();
}

class _StartSharingButtonState extends State<_StartSharingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _glow = Tween<double>(begin: 6.0, end: 18.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    final canStart = prov.webViewReady && prov.postUrl.isNotEmpty && prov.groups.isNotEmpty;
    final running  = prov.isRunning;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => GestureDetector(
        onTap: () {
          if (running) {
            prov.stopAutomation();
          } else if (canStart) {
            prov.startAutomation();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: running
                  ? [_red, const Color(0xFFCC2233)]
                  : canStart
                      ? [_accent, const Color(0xFF1565D8)]
                      : [_sub.withValues(alpha: .4), _sub.withValues(alpha: .3)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(
              color: (running ? _red : canStart ? _accent : Colors.transparent).withValues(alpha: canStart ? .4 : 0),
              blurRadius: (canStart && !running) ? _glow.value : 6,
            )],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              running ? 'STOP AUTOMATION' : canStart ? 'START AUTOMATION' : 'SELECT POST & GROUPS',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// COLUMN 2 — Group Categorizer
// ══════════════════════════════════════════════════════════════════════════════
class _Col2GroupCategorizer extends StatelessWidget {
  const _Col2GroupCategorizer();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    return Container(
      color: _bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Column header ─────────────────────────────────────────────────
        _DashColHeader(icon: Icons.account_tree_rounded, title: 'Group Categorizer', badge: prov.groups.length),

        // ── Sync control card ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: _DashCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Status row
            Row(children: [
              Text('SYNC STATUS', style: _dashLabelStyle()),
              const Spacer(),
              if (prov.isSyncing)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _amber.withValues(alpha: .12), borderRadius: BorderRadius.circular(4)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 8, height: 8,
                      child: CircularProgressIndicator(strokeWidth: 1.5)),
                    SizedBox(width: 5),
                    Text('SYNCING', style: TextStyle(color: _amber, fontSize: 9, fontWeight: FontWeight.w700)),
                  ]),
                )
              else if (prov.groups.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _green.withValues(alpha: .1), borderRadius: BorderRadius.circular(4)),
                  child: const Text('SYNCED', style: TextStyle(color: _green, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 8),

            // Sync + Deep Sync buttons
            Row(children: [
              Expanded(
                child: SizedBox(height: 34,
                  child: _DashAccentButton(
                    icon: Icons.sync_rounded,
                    label: prov.isSyncing ? 'Syncing… (${prov.groupsFound})' : 'Sync Groups',
                    color: _accent,
                    onPressed: prov.webViewReady && !prov.isSyncing ? () => prov.fetchGroups() : null,
                  )),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(height: 34,
                  child: _DashAccentButton(
                    icon: prov.isDeepSyncing ? Icons.stop_rounded : Icons.travel_explore_rounded,
                    label: prov.isDeepSyncing
                        ? 'Stop (${prov.deepSyncIndex + 1}/${prov.groups.length})'
                        : 'Deep Sync',
                    color: prov.isDeepSyncing ? _amber : const Color(0xFF7C3AED),
                    onPressed: prov.webViewReady && prov.groups.isNotEmpty
                        ? (prov.isDeepSyncing ? prov.stopDeepSync : prov.deepSync)
                        : null,
                  )),
              ),
            ]),
            const SizedBox(height: 8),

            // Progress bar: groups found / total
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: prov.groups.isEmpty ? 0
                        : prov.isDeepSyncing
                            ? prov.deepSyncIndex / prov.groups.length
                            : 1.0,
                    backgroundColor: _border,
                    valueColor: AlwaysStoppedAnimation<Color>(prov.isSyncing ? _amber : _accent),
                    minHeight: 5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                prov.isSyncing
                    ? '${prov.groupsFound} found'
                    : '${prov.groups.length} groups',
                style: const TextStyle(color: _subL, fontSize: 10.5, fontWeight: FontWeight.w500),
              ),
            ]),

            // Error message
            if (prov.groupsError != null && !prov.isSyncing) ...[
              const SizedBox(height: 7),
              Row(children: [
                const Icon(Icons.error_outline_rounded, color: _red, size: 12),
                const SizedBox(width: 5),
                Expanded(child: Text(prov.groupsError!,
                    style: const TextStyle(color: _red, fontSize: 10, height: 1.3),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
            ],

            // DeepSync progress
            if (prov.isDeepSyncing && prov.highlightedGroup.isNotEmpty) ...[
              const SizedBox(height: 7),
              Row(children: [
                const SizedBox(width: 10, height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: _accentL)),
                const SizedBox(width: 7),
                Expanded(child: Text('Processing: ${prov.highlightedGroup}',
                    style: const TextStyle(color: _accentL, fontSize: 10.5),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ],
          ])),
        ),

        // ── Groups accordion list ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(children: [
            Text('GROUPS', style: _dashLabelStyle()),
            const Spacer(),
            GestureDetector(
              onTap: () => _showNewCategoryDialog(context, prov),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.create_new_folder_rounded, size: 13, color: _accentL),
                SizedBox(width: 4),
                Text('New Category', style: TextStyle(color: _accentL, fontSize: 10.5, fontWeight: FontWeight.w600)),
              ]),
            ),
            if (prov.groups.isNotEmpty) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: prov.clearGroups,
                child: const Text('Clear', style: TextStyle(color: _sub, fontSize: 10, decoration: TextDecoration.underline)),
              ),
            ],
          ]),
        ),

        if (prov.isSyncing) _SyncProgressBanner(groupsFound: prov.groupsFound),

        Expanded(
          child: prov.groups.isEmpty
              ? _GroupsEmptyState(prov: prov)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  children: [
                    // Uncategorized accordion
                    _CategoryAccordion(
                      label: 'Uncategorized',
                      categoryId: '',
                      isExpanded: true,
                      isUncategorized: true,
                      groups: prov.groupsForCategory(''),
                      allCategories: prov.categories,
                      highlightedGroup: prov.highlightedGroup,
                      onTapGroup: (g) => prov.navigateToGroup(g),
                      onMoveGroup: (groupName, catId) => prov.moveGroupToCategory(groupName, catId),
                    ),
                    const SizedBox(height: 6),
                    // Named categories
                    ...prov.categories.map((cat) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _CategoryAccordion(
                        label: cat.name,
                        categoryId: cat.id,
                        isExpanded: cat.isExpanded,
                        isUncategorized: false,
                        groups: prov.groupsForCategory(cat.id),
                        allCategories: prov.categories,
                        highlightedGroup: prov.highlightedGroup,
                        onTapGroup: (g) => prov.navigateToGroup(g),
                        onMoveGroup: (groupName, catId) => prov.moveGroupToCategory(groupName, catId),
                        onToggleExpand: () => prov.toggleCategoryExpanded(cat.id),
                        onDelete: prov.groupsForCategory(cat.id).isEmpty
                            ? () => prov.removeCategory(cat.id)
                            : null,
                        onAddGroups: () => _showGroupPickerDialog(context, prov, cat.id, cat.name),
                      ),
                    )),
                  ],
                ),
        ),
      ]),
    );
  }

  void _showGroupPickerDialog(BuildContext context, AutomationProvider prov, String categoryId, String categoryName) {
    // Groups not already in this category
    final available = prov.groups.where((g) => g.categoryId != categoryId).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('All groups are already in "$categoryName"'),
          backgroundColor: _card,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Track which groups are checked inside the dialog
    final selected = <String>{};

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _border)),
          title: Row(children: [
            const Icon(Icons.folder_rounded, color: _amber, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Add groups to "$categoryName"',
                style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w600))),
          ]),
          content: SizedBox(
            width: 360,
            height: 400,
            child: Column(children: [
              // Select all / deselect all
              Row(children: [
                TextButton(
                  onPressed: () => setDialogState(() => selected.addAll(available.map((g) => g.name))),
                  child: const Text('Select all', style: TextStyle(color: _accentL, fontSize: 11)),
                ),
                TextButton(
                  onPressed: () => setDialogState(() => selected.clear()),
                  child: const Text('Clear', style: TextStyle(color: _sub, fontSize: 11)),
                ),
                const Spacer(),
                Text('${selected.length} selected',
                    style: const TextStyle(color: _subL, fontSize: 11)),
              ]),
              const Divider(color: _border, height: 1),
              // Scrollable group list
              Expanded(
                child: ListView.builder(
                  itemCount: available.length,
                  itemBuilder: (_, i) {
                    final g = available[i];
                    final isChecked = selected.contains(g.name);
                    return InkWell(
                      onTap: () => setDialogState(() {
                        if (isChecked) { selected.remove(g.name); }
                        else { selected.add(g.name); }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: Row(children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: 18, height: 18,
                            decoration: BoxDecoration(
                              color: isChecked ? _accent : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: isChecked ? _accent : _sub, width: 1.5),
                            ),
                            child: isChecked
                                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          _GroupCircleAvatar(imageUrl: g.imageUrl),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(g.name,
                                style: TextStyle(
                                    color: isChecked ? _text : _subL,
                                    fontSize: 12, fontWeight: FontWeight.w500),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (g.categoryId.isNotEmpty)
                              Text('Currently in: ${prov.categories.firstWhere((c) => c.id == g.categoryId, orElse: () => GroupCategory(id: '', name: 'Unknown')).name}',
                                  style: const TextStyle(color: _sub, fontSize: 9.5)),
                          ])),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: _subL))),
            ElevatedButton.icon(
              onPressed: selected.isEmpty ? null : () {
                for (final name in selected) {
                  prov.moveGroupToCategory(name, categoryId);
                }
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check_rounded, size: 14),
              label: Text('Add ${selected.isEmpty ? '' : '(${selected.length})'}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent, foregroundColor: Colors.white,
                disabledBackgroundColor: _sub.withValues(alpha: .3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewCategoryDialog(BuildContext context, AutomationProvider prov) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _border)),
        title: const Row(children: [
          Icon(Icons.create_new_folder_rounded, color: _accentL, size: 18),
          SizedBox(width: 8),
          Text('Create Category', style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
        content: SizedBox(
          width: 300,
          child: _ThemedTextField(controller: ctrl, hint: 'e.g. Sales, Leads, Marketing', prefixIcon: Icons.label_rounded),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: _subL))),
          ElevatedButton(
            onPressed: () { prov.addCategory(ctrl.text); Navigator.pop(context); },
            style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// ── Category Accordion widget ──────────────────────────────────────────────────
class _CategoryAccordion extends StatelessWidget {
  final String label;
  final String categoryId;
  final bool isExpanded;
  final bool isUncategorized;
  final List<FBGroup> groups;
  final List<GroupCategory> allCategories;
  final String highlightedGroup;
  final void Function(FBGroup g) onTapGroup;
  final void Function(String groupName, String catId) onMoveGroup;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onDelete;
  final VoidCallback? onAddGroups; // opens group-picker dialog

  const _CategoryAccordion({
    required this.label,
    required this.categoryId,
    required this.groups,
    required this.allCategories,
    required this.highlightedGroup,
    required this.onTapGroup,
    required this.onMoveGroup,
    this.isExpanded = true,
    this.isUncategorized = false,
    this.onToggleExpand,
    this.onDelete,
    this.onAddGroups,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(children: [
        // ── Header ──
        GestureDetector(
          onTap: isUncategorized ? onToggleExpand : onAddGroups,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              // expand/collapse arrow (only for uncategorized or when expanded)
              GestureDetector(
                onTap: onToggleExpand,
                child: Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: _subL, size: 15),
              ),
              const SizedBox(width: 6),
              Icon(isUncategorized ? Icons.help_outline_rounded : Icons.folder_rounded,
                  size: 14, color: isUncategorized ? _sub : _amber),
              const SizedBox(width: 6),
              Expanded(child: Text(label,
                  style: TextStyle(
                      color: isUncategorized ? _subL : _text,
                      fontSize: 12.5, fontWeight: FontWeight.w600))),
              // "Add groups" hint for named categories
              if (!isUncategorized)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 13, color: _accentL),
                    SizedBox(width: 2),
                    Text('Add', style: TextStyle(color: _accentL, fontSize: 10, fontWeight: FontWeight.w600)),
                  ]),
                ),
              // Group count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: _surface, borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _border)),
                child: Text('${groups.length}',
                    style: const TextStyle(color: _subL, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              // Delete button (only for empty named categories)
              if (!isUncategorized && onDelete != null) ...[
                const SizedBox(width: 6),
                GestureDetector(onTap: onDelete,
                    child: const Icon(Icons.delete_outline_rounded, color: _sub, size: 14)),
              ],
            ]),
          ),
        ),
        // ── Group tiles ──
        if (isExpanded) ...[
          if (groups.isNotEmpty) ...[
            const Divider(color: _divider, height: 1),
            ...groups.map((g) => _CategoryGroupTile(
              group: g,
              isActive: highlightedGroup == g.name,
              allCategories: allCategories,
              currentCategoryId: categoryId,
              onTap: () => onTapGroup(g),
              onMove: (catId) => onMoveGroup(g.name, catId),
            )),
            const SizedBox(height: 4),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.touch_app_rounded, color: _sub, size: 20),
                const SizedBox(height: 4),
                Text(
                  isUncategorized ? 'No uncategorized groups' : 'Tap category header to add groups',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _sub, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

// ── Group tile inside a category ───────────────────────────────────────────────
class _CategoryGroupTile extends StatefulWidget {
  final FBGroup group;
  final bool isActive;
  final List<GroupCategory> allCategories;
  final String currentCategoryId;
  final VoidCallback onTap;
  final void Function(String catId) onMove;
  const _CategoryGroupTile({
    required this.group, required this.isActive, required this.allCategories,
    required this.currentCategoryId, required this.onTap, required this.onMove,
  });
  @override
  State<_CategoryGroupTile> createState() => _CategoryGroupTileState();
}

class _CategoryGroupTileState extends State<_CategoryGroupTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: active ? _accent.withValues(alpha: .12)
                : _hovered ? _cardHov : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active ? Border.all(color: _accent.withValues(alpha: .4)) : null,
          ),
          child: Row(children: [
            _GroupCircleAvatar(imageUrl: widget.group.imageUrl),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(widget.group.name,
                    style: TextStyle(
                        color: active ? Colors.white : (_hovered ? _accentL : _text),
                        fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (active) ...[
                  const SizedBox(width: 6),
                  const SizedBox(width: 10, height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: _accentL)),
                ],
              ]),
              if (widget.group.groupId.isNotEmpty || widget.group.url.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  widget.group.groupId.isNotEmpty
                      ? 'ID: ${widget.group.groupId}'
                      : widget.group.url,
                  style: const TextStyle(color: _sub, fontSize: 9.5),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ])),
            // Move to category popup
            if (_hovered && widget.allCategories.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Move to category',
                padding: EdgeInsets.zero,
                color: _card,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: _border)),
                icon: const Icon(Icons.drive_file_move_rounded, size: 14, color: _subL),
                onSelected: widget.onMove,
                itemBuilder: (_) => [
                  if (widget.currentCategoryId != '')
                    const PopupMenuItem(value: '',
                      child: Row(children: [
                        Icon(Icons.folder_off_rounded, size: 14, color: _sub),
                        SizedBox(width: 6),
                        Text('Uncategorized', style: TextStyle(color: _subL, fontSize: 12)),
                      ])),
                  ...widget.allCategories
                      .where((c) => c.id != widget.currentCategoryId)
                      .map((cat) => PopupMenuItem(value: cat.id,
                        child: Row(children: [
                          const Icon(Icons.folder_rounded, size: 14, color: _amber),
                          const SizedBox(width: 6),
                          Text(cat.name, style: const TextStyle(color: _text, fontSize: 12)),
                        ]))),
                ],
              ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// COLUMN 3 — Live Status Log
// ══════════════════════════════════════════════════════════════════════════════
class _Col3LiveStatus extends StatelessWidget {
  const _Col3LiveStatus();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();

    // Derive status color
    final statusColor = switch (prov.status) {
      AutomationStatus.success   => _green,
      AutomationStatus.error     => _red,
      AutomationStatus.running   => _amber,
      AutomationStatus.navigating => _accentL,
      _ => _sub,
    };
    final statusLabel = switch (prov.status) {
      AutomationStatus.success    => 'Success',
      AutomationStatus.error      => 'Error',
      AutomationStatus.running    => 'Running…',
      AutomationStatus.navigating => 'Navigating…',
      _ => 'Ready',
    };

    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(left: BorderSide(color: _divider)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Column header ─────────────────────────────────────────────────
        const _DashColHeader(icon: Icons.terminal_rounded, title: 'Live Status'),

        // ── Overall progress card ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: _DashCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('AUTOMATION STATUS', style: _dashLabelStyle()),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: .3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(statusLabel,
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 10),

            // Post URL being shared
            if (prov.postUrl.isNotEmpty) ...[
              Row(children: [
                const Icon(Icons.link_rounded, color: _sub, size: 12),
                const SizedBox(width: 5),
                Expanded(child: Text(prov.postUrl,
                    style: const TextStyle(color: _subL, fontSize: 10),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 8),
            ],

            // Groups progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: prov.isRunning ? null : (prov.groups.isNotEmpty ? 1.0 : 0.0),
                backgroundColor: _border,
                valueColor: AlwaysStoppedAnimation<Color>(
                    prov.status == AutomationStatus.running ? _green : _accent),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),

            Row(children: [
              _LiveStat(label: 'Groups', value: '${prov.groups.length}', color: _accentL),
              const SizedBox(width: 14),
              _LiveStat(label: 'Status', value: statusLabel, color: statusColor),
              const SizedBox(width: 14),
              _LiveStat(label: 'WebView', value: prov.webViewReady ? 'Ready' : 'Init…',
                  color: prov.webViewReady ? _green : _sub),
            ]),
            const SizedBox(height: 8),
            const _NetworkIndicator(),
          ])),
        ),

        // ── Status message log header ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(children: [
            Text('ACTIVITY LOG', style: _dashLabelStyle()),
            const Spacer(),
            if (prov.isRunning)
              const Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 6, height: 6,
                  child: DecoratedBox(decoration: BoxDecoration(color: _green, shape: BoxShape.circle))),
                SizedBox(width: 4),
                Text('LIVE', style: TextStyle(color: _green, fontSize: 9, fontWeight: FontWeight.w700)),
              ]),
          ]),
        ),

        // ── Terminal log area ─────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF080C14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Column(children: [
                // Title bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _surface.withValues(alpha: .6),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                    border: const Border(bottom: BorderSide(color: _border)),
                  ),
                  child: const Row(children: [
                    _TermDot(color: _red),
                    SizedBox(width: 5),
                    _TermDot(color: _amber),
                    SizedBox(width: 5),
                    _TermDot(color: _green),
                    SizedBox(width: 10),
                    Text('fb_share_pro — automation.log',
                        style: TextStyle(color: _sub, fontSize: 10, fontFamily: 'monospace')),
                  ]),
                ),
                // Log entries — show statusMsg history
                Expanded(
                  child: _AutomationLogView(),
                ),
              ]),
            ),
          ),
        ),

        // ── Quick action buttons ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Row(children: [
            Expanded(child: SizedBox(height: 34,
              child: _DashAccentButton(
                icon: Icons.open_in_browser_rounded,
                label: 'Open Post',
                onPressed: prov.webViewReady && prov.postUrl.isNotEmpty ? prov.navigateToPost : null,
              ))),
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 34,
              child: _DashAccentButton(
                icon: Icons.home_rounded,
                label: 'FB Home',
                color: _sub,
                onPressed: prov.webViewReady ? prov.navigateHome : null,
              ))),
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 34,
              child: _DashAccentButton(
                icon: Icons.tune_rounded,
                label: 'Settings',
                color: const Color(0xFF7C3AED),
                onPressed: () => showDialog(context: context,
                    builder: (_) => _AutomationSettingsDialog(
                        prov: context.read<AutomationProvider>())),
              ))),
          ]),
        ),
      ]),
    );
  }
}

// Live stat widget
// ── Network Status Indicator ──────────────────────────────────────────────────
class _NetworkIndicator extends StatelessWidget {
  const _NetworkIndicator();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    final ping = prov.pingMs;

    final Color dotColor;
    final String label;
    final String pingText;

    if (ping == null) {
      dotColor = _sub;
      label    = 'Checking…';
      pingText = '';
    } else if (ping == -1) {
      dotColor = _red;
      label    = 'Offline';
      pingText = '';
    } else if (ping > 800) {
      dotColor = _amber;
      label    = 'Slow Network';
      pingText = '${ping}ms';
    } else {
      dotColor = _green;
      label    = 'Connected';
      pingText = '${ping}ms';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: dotColor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: dotColor.withValues(alpha: .25)),
      ),
      child: Row(children: [
        // Animated dot
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        const Text('NETWORK', style: TextStyle(color: _sub, fontSize: 9, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: dotColor, fontSize: 10, fontWeight: FontWeight.w700)),
        if (pingText.isNotEmpty) ...[ 
          const SizedBox(width: 6),
          Text(pingText, style: const TextStyle(color: _sub, fontSize: 9)),
        ],
        const Spacer(),
        // Manual refresh button
        GestureDetector(
          onTap: () => prov.checkNetworkNow(),
          child: const Icon(Icons.refresh_rounded, size: 13, color: _sub),
        ),
      ]),
    );
  }
}

class _LiveStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _LiveStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
    Text(label, style: const TextStyle(color: _sub, fontSize: 9.5)),
  ]);
}

// Terminal dot
class _TermDot extends StatelessWidget {
  final Color color;
  const _TermDot({required this.color});
  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color.withValues(alpha: .6), shape: BoxShape.circle));
}

// Automation log view — keeps a rolling history of statusMsg
class _AutomationLogView extends StatefulWidget {
  @override
  State<_AutomationLogView> createState() => _AutomationLogViewState();
}

class _AutomationLogViewState extends State<_AutomationLogView> {
  final List<_LogLine> _lines = [];
  String _lastMsg = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prov = context.watch<AutomationProvider>();
    if (prov.statusMsg != _lastMsg) {
      _lastMsg = prov.statusMsg;
      final now = DateTime.now();
      final ts = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final level = prov.status == AutomationStatus.success
          ? _LogLevel.success
          : prov.status == AutomationStatus.error
              ? _LogLevel.error
              : prov.status == AutomationStatus.running || prov.status == AutomationStatus.navigating
                  ? _LogLevel.info
                  : _LogLevel.muted;
      _lines.insert(0, _LogLine(ts: ts, msg: prov.statusMsg, level: level));
      if (_lines.length > 200) _lines.removeLast();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return const Center(child: Text(
        '> Waiting for automation…\n> Select a post and sync groups.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF2A4A2A), fontSize: 11, fontFamily: 'monospace'),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: _lines.length,
      itemBuilder: (_, i) {
        final line = _lines[i];
        final color = switch (line.level) {
          _LogLevel.success => const Color(0xFF1ED760),
          _LogLevel.error   => const Color(0xFFFF4757),
          _LogLevel.info    => const Color(0xFF8899CC),
          _LogLevel.muted   => const Color(0xFF3A5070),
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: RichText(text: TextSpan(
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5),
            children: [
              TextSpan(text: '${line.ts} ', style: const TextStyle(color: Color(0xFF3A5070))),
              const TextSpan(text: '— ', style: TextStyle(color: Color(0xFF2A3A55))),
              TextSpan(text: line.msg, style: TextStyle(color: color)),
            ],
          )),
        );
      },
    );
  }
}

enum _LogLevel { success, error, info, muted }

class _LogLine {
  final String ts;
  final String msg;
  final _LogLevel level;
  _LogLine({required this.ts, required this.msg, required this.level});
}

// ══════════════════════════════════════════════════════════════════════════════
// Dashboard shared components (prefixed _Dash to avoid conflicts)
// ══════════════════════════════════════════════════════════════════════════════

TextStyle _dashLabelStyle() => const TextStyle(
    color: Color(0xFF8A99C0), fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.1);

class _DashColHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? badge;
  const _DashColHeader({required this.icon, required this.title, this.badge});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _divider))),
    child: Row(children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: _accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, color: _accentL, size: 15),
      ),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w700)),
      if (badge != null && badge! > 0) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: _accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(5)),
          child: Text('$badge', style: const TextStyle(color: _accentL, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ],
    ]),
  );
}

class _DashCard extends StatelessWidget {
  final Widget child;
  const _DashCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: child,
  );
}

class _DashAccentButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onPressed;
  const _DashAccentButton({required this.icon, required this.label, this.color, required this.onPressed});
  @override
  State<_DashAccentButton> createState() => _DashAccentButtonState();
}

class _DashAccentButtonState extends State<_DashAccentButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final base = widget.color ?? _accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: enabled ? (_hovered ? Color.lerp(base, Colors.white, .1)! : base) : _sub.withValues(alpha: .25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 13, color: Colors.white.withValues(alpha: enabled ? 1 : .4)),
            const SizedBox(width: 5),
            Flexible(child: Text(widget.label,
              style: TextStyle(color: Colors.white.withValues(alpha: enabled ? 1 : .4), fontSize: 11, fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}

// ── Group circle avatar ────────────────────────────────────────────────────────
class _GroupCircleAvatar extends StatelessWidget {
  final String imageUrl;
  const _GroupCircleAvatar({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    const double r = 20;
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: r,
        backgroundColor: _accent.withValues(alpha: .12),
        child: const Icon(Icons.group_rounded, color: _accentL, size: 18),
      );
    }
    return CircleAvatar(
      radius: r,
      backgroundColor: _border,
      backgroundImage: NetworkImage(imageUrl),
      onBackgroundImageError: (_, __) {},
    );
  }
}



// ── Automation settings dialog ─────────────────────────────────────────────────
class _AutomationSettingsDialog extends StatefulWidget {
  final AutomationProvider prov;
  const _AutomationSettingsDialog({required this.prov});
  @override
  State<_AutomationSettingsDialog> createState() =>
      _AutomationSettingsDialogState();
}

class _AutomationSettingsDialogState
    extends State<_AutomationSettingsDialog> {
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.prov.postUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Automation Settings',
                  style: TextStyle(
                      color: _text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              const Text('Post URL to share',
                  style: TextStyle(
                      color: _sub,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              const SizedBox(height: 7),
              _ThemedTextField(
                controller: _urlCtrl,
                hint: 'https://www.facebook.com/share/p/…',
                prefixIcon: Icons.link_rounded,
                showPaste: true,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: _sub)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      widget.prov.setPostUrl(_urlCtrl.text);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────
class _GroupsEmptyState extends StatelessWidget {
  final AutomationProvider prov;
  const _GroupsEmptyState({required this.prov});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: .07),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.group_outlined,
                color: _accentL, size: 32),
          ),
          const SizedBox(height: 18),
          const Text('No groups loaded',
              style: TextStyle(
                  color: _text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'Log in to Facebook in the WebView,\n'
            'then tap Sync Groups to load all your groups.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _sub, fontSize: 12, height: 1.65),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: prov.webViewReady && !prov.isSyncing
                ? () => prov.fetchGroups()
                : null,
            icon: const Icon(Icons.sync_rounded, size: 15),
            label: const Text('Sync Groups'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Follow-up Page  (index 1) — Coming Soon placeholder
// ─────────────────────────────────────────────────────────────────────────────
class _FollowUpPage extends StatelessWidget {
  const _FollowUpPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: Column(
        children: [
          // Header
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              color: _surface,
              border: Border(bottom: BorderSide(color: _divider)),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_add_rounded,
                    color: _accentL, size: 18),
                SizedBox(width: 10),
                Text('Follow-up',
                    style: TextStyle(
                        color: _text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                SizedBox(width: 8),
                Text('Audience Management',
                    style: TextStyle(color: _sub, fontSize: 11)),
              ],
            ),
          ),
          // Coming soon body
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: .07),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        color: _accentL, size: 36),
                  ),
                  const SizedBox(height: 20),
                  const Text('Coming Soon',
                      style: TextStyle(
                          color: _text,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    'Follow-up automation and\naudience management tools\nare under development.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _sub, fontSize: 13, height: 1.7),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _accent.withValues(alpha: .25)),
                    ),
                    child: const Text('v5.0 — Planned',
                        style: TextStyle(
                            color: _accentL,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
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

// ═════════════════════════════════════════════════════════════════════════════
// TAB 1 — PAGE MANAGER
// ═════════════════════════════════════════════════════════════════════════════
class _PageManagerTab extends StatefulWidget {
  const _PageManagerTab();
  @override
  State<_PageManagerTab> createState() => _PageManagerTabState();
}

class _PageManagerTabState extends State<_PageManagerTab> {
  final _urlCtrl = TextEditingController();
  @override
  void dispose() { _urlCtrl.dispose(); super.dispose(); }

  void _addPage(AutomationProvider prov) {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    prov.addPageToList(url);
    _urlCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionLabel('ADD FACEBOOK PAGE'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ThemedTextField(
                      controller: _urlCtrl,
                      hint: 'https://www.facebook.com/…',
                      prefixIcon: Icons.link_rounded,
                      onSubmitted: (_) => prov.isFetching || !prov.webViewReady ? null : _addPage(prov),
                    ),
                  ),
                  const SizedBox(width: 7),
                  _SmallIconButton(
                    icon: Icons.add_rounded,
                    color: _accent,
                    loading: prov.isFetching,
                    enabled: !prov.isFetching && prov.webViewReady,
                    onTap: () => _addPage(prov),
                  ),
                ],
              ),
              if (prov.isFetching) ...[
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: const LinearProgressIndicator(backgroundColor: _card, color: _accent, minHeight: 2),
                ),
                const SizedBox(height: 5),
                const Text('Fetching page info…', style: TextStyle(color: _sub, fontSize: 9.5)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Divider(color: _divider, height: 1, indent: 12, endIndent: 12),
        Expanded(
          child: prov.pages.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.web_asset_rounded, color: _border, size: 32),
                      SizedBox(height: 10),
                      Text('No pages yet.\nPaste a Facebook URL above.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _sub, fontSize: 11.5, height: 1.6)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 9),
                  itemCount: prov.pages.length,
                  itemBuilder: (_, i) {
                    final page = prov.pages[i];
                    return _PageListTile(
                      page: page,
                      isSelected: prov.selected == page,
                      onTap: () => prov.selectPage(page),
                      onDelete: () => prov.removePage(page),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PageListTile extends StatelessWidget {
  final FBPage page;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PageListTile({required this.page, required this.isSelected, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accent.withValues(alpha: .09) : _card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: isSelected ? _accent.withValues(alpha: .4) : _border, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            _PageAvatar(page: page),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(page.name,
                      style: TextStyle(color: isSelected ? _accentL : _text, fontSize: 11.5, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(page.url, style: const TextStyle(color: _sub, fontSize: 9.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close_rounded, size: 13, color: _sub)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageAvatar extends StatelessWidget {
  final FBPage page;
  const _PageAvatar({required this.page});
  @override
  Widget build(BuildContext context) {
    const double size = 36;
    const radius = size / 2;
    if (page.imageUrl.isEmpty) return const _AvatarFallback(radius: radius);
    return CircleAvatar(
      radius: radius, backgroundColor: _border,
      child: ClipOval(
        child: Image.network(
          page.imageUrl, width: size, height: size, fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) {
            if (progress == null) return child;
            return Container(width: size, height: size, color: _card,
              child: Center(child: SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: _accent,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes! : null))));
          },
          errorBuilder: (_, __, ___) => const _AvatarFallback(radius: radius),
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final double radius;
  const _AvatarFallback({required this.radius});
  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _accent.withValues(alpha: .15),
      child: Icon(Icons.business_rounded, color: _accentL, size: radius * 0.9),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MIDDLE — Library Panel with "Saved Posts" + "My Groups" tabs
// ═════════════════════════════════════════════════════════════════════════════
class _LibraryPanel extends StatefulWidget {
  const _LibraryPanel();
  @override
  State<_LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<_LibraryPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _urlCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _urlCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePost(AutomationProvider prov) async {
    final url  = _urlCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (url.isEmpty || _adding) return;
    setState(() => _adding = true);
    _urlCtrl.clear();
    _descCtrl.clear();
    await prov.addItem(url, manualDesc: desc);
    if (mounted) setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    return Container(
      width: 420,
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(right: BorderSide(color: _divider)),
      ),
      child: Column(
        children: [
          // ── Panel header ────────────────────────────────────────────────
          _LibraryPanelHeader(tabCtrl: _tabCtrl),
          // ── Tab body ────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // ── Tab 0: Saved Posts ────────────────────────────────────
                Column(
                  children: [
                    _PostInputBar(urlCtrl: _urlCtrl, descCtrl: _descCtrl, adding: _adding, onSave: () => _savePost(prov)),
                    Expanded(
                      child: prov.items.isEmpty
                          ? const _LibraryEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                              itemCount: prov.items.length,
                              itemBuilder: (_, i) {
                                final item = prov.items[i];
                                return _EmbedCard(
                                  key: ValueKey(item.id),
                                  item: item,
                                  onDelete: () => prov.removeItem(item.id),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                // ── Tab 1: My Groups ──────────────────────────────────────
                _GroupsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Library panel header with tab bar ─────────────────────────────────────────
class _LibraryPanelHeader extends StatelessWidget {
  final TabController tabCtrl;
  const _LibraryPanelHeader({required this.tabCtrl});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 13, 13, 0),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: _accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(7)),
                  child: const Icon(Icons.dashboard_rounded, color: _accentL, size: 14),
                ),
                const SizedBox(width: 9),
                const Text('Library', style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 7),
                if (prov.items.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: _accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
                    child: Text('${prov.items.length}',
                        style: const TextStyle(color: _accentL, fontSize: 9.5, fontWeight: FontWeight.w700)),
                  ),
                const Spacer(),
                const Text('Live Embed Preview', style: TextStyle(color: _sub, fontSize: 9, letterSpacing: 0.4)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: tabCtrl,
            labelColor: _accent,
            unselectedLabelColor: _sub,
            indicatorColor: _accent,
            indicatorWeight: 2,
            labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            unselectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
            tabs: [
              const Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_rounded, size: 12),
                    SizedBox(width: 5),
                    Text('SAVED POSTS'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.group_rounded, size: 12),
                    const SizedBox(width: 5),
                    const Text('MY GROUPS'),
                    if (prov.groups.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: _accent.withValues(alpha: .2), borderRadius: BorderRadius.circular(10)),
                        child: Text('${prov.groups.length}',
                            style: const TextStyle(color: _accentL, fontSize: 8.5, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Post input bar (Saved Posts tab header) ───────────────────────────────────
class _PostInputBar extends StatelessWidget {
  final TextEditingController urlCtrl;
  final TextEditingController descCtrl;
  final bool adding;
  final VoidCallback onSave;
  const _PostInputBar({
    required this.urlCtrl,
    required this.descCtrl,
    required this.adding,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── URL row ────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _ThemedTextField(
                  controller: urlCtrl,
                  hint: 'Paste Facebook post URL…',
                  prefixIcon: Icons.add_link_rounded,
                  showPaste: true,
                  onSubmitted: (_) => onSave(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          // ── Description row ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(color: _text, fontSize: 11.5),
                  decoration: InputDecoration(
                    hintText: 'Add a note or description (optional)…',
                    hintStyle: const TextStyle(color: _sub, fontSize: 10.5),
                    prefixIcon: const Icon(Icons.notes_rounded,
                        color: _sub, size: 14),
                    filled: true,
                    fillColor: _card,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: _accent, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SaveButton(loading: adding, onTap: onSave),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _SaveButton({required this.loading, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: _accent, borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: loading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
              : const Row(children: [
                  Icon(Icons.bookmark_add_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 5),
                  Text('Save', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
        ),
      ),
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 60, height: 60,
            decoration: BoxDecoration(color: _accent.withValues(alpha: .08), shape: BoxShape.circle),
            child: const Icon(Icons.bookmark_border_rounded, color: _accentL, size: 28)),
          const SizedBox(height: 14),
          const Text('No saved links yet', style: TextStyle(color: _text, fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          const Text('Paste a Facebook post URL above\nand click Save',
              textAlign: TextAlign.center, style: TextStyle(color: _sub, fontSize: 11.5, height: 1.6)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MY GROUPS TAB
// ═════════════════════════════════════════════════════════════════════════════
class _GroupsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Toolbar ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
          decoration: const BoxDecoration(
            color: _surface,
            border: Border(bottom: BorderSide(color: _divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Groups you\'ve joined', style: TextStyle(color: _text, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      prov.groupsError != null
                          ? prov.groupsError!
                          : prov.groups.isEmpty
                              ? 'Click Refresh to extract your groups.'
                              : '${prov.groups.length} group${prov.groups.length == 1 ? '' : 's'} — tap to navigate',
                      style: TextStyle(
                        color: prov.groupsError != null ? _red : _sub,
                        fontSize: 9.5,
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Refresh button
              Tooltip(
                message: 'Fetch groups from facebook.com/groups/',
                child: Material(
                  color: prov.webViewReady && !prov.groupsFetching ? _accent : _card,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: prov.webViewReady && !prov.groupsFetching ? () => prov.fetchGroups() : null,
                    child: SizedBox(
                      width: 34, height: 34,
                      child: Center(
                        child: prov.groupsFetching
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                            : Icon(Icons.refresh_rounded, size: 16,
                                color: prov.webViewReady ? Colors.white : _sub),
                      ),
                    ),
                  ),
                ),
              ),
              if (prov.groups.isNotEmpty) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Clear group list',
                  child: Material(
                    color: _card, borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: prov.clearGroups,
                      child: const SizedBox(width: 34, height: 34,
                          child: Center(child: Icon(Icons.delete_outline_rounded, size: 15, color: _sub))),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // ── Loading indicator ────────────────────────────────────────────
        if (prov.groupsFetching)
          const ClipRRect(
            child: LinearProgressIndicator(backgroundColor: _card, color: _accent, minHeight: 2),
          ),
        // ── Group list ───────────────────────────────────────────────────
        Expanded(
          child: prov.groups.isEmpty && !prov.groupsFetching
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 60, height: 60,
                        decoration: BoxDecoration(color: _accent.withValues(alpha: .08), shape: BoxShape.circle),
                        child: const Icon(Icons.group_outlined, color: _accentL, size: 28)),
                      const SizedBox(height: 14),
                      const Text('No groups loaded', style: TextStyle(color: _text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 5),
                      const Text('Log in to Facebook, then\ntap Refresh to extract your groups.',
                          textAlign: TextAlign.center, style: TextStyle(color: _sub, fontSize: 11.5, height: 1.6)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 9),
                  itemCount: prov.groups.length,
                  itemBuilder: (_, i) {
                    final group = prov.groups[i];
                    return _GroupListTile(
                      group: group,
                      onTap: () => prov.navigateToGroup(group),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Group thumbnail avatar ────────────────────────────────────────────────────
class _GroupAvatar extends StatelessWidget {
  final String imageUrl;
  const _GroupAvatar({required this.imageUrl});
  @override
  Widget build(BuildContext context) {
    const double size = 34;
    if (imageUrl.isEmpty) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: Icon(Icons.group_rounded, color: _accentL, size: 17)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imageUrl, width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size, height: size,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(child: Icon(Icons.group_rounded, color: _accentL, size: 17)),
        ),
      ),
    );
  }
}

// ── Group list tile ────────────────────────────────────────────────────────────
class _GroupListTile extends StatefulWidget {
  final FBGroup group;
  final VoidCallback onTap;
  const _GroupListTile({required this.group, required this.onTap});
  @override
  State<_GroupListTile> createState() => _GroupListTileState();
}

class _GroupListTileState extends State<_GroupListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? _cardHov : _card,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _hovered ? _accent.withValues(alpha: .3) : _border),
          ),
          child: Row(
            children: [
              _GroupAvatar(imageUrl: widget.group.imageUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.group.name,
                        style: const TextStyle(color: _text, fontSize: 11.5, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                        widget.group.url.isNotEmpty
                            ? _shortUrl(widget.group.url)
                            : 'Index #${widget.group.index}',
                        style: const TextStyle(color: _sub, fontSize: 9.5),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.open_in_browser_rounded, size: 13,
                  color: _hovered ? _accentL : _sub),
            ],
          ),
        ),
      ),
    );
  }

  String _shortUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final path = uri.path.length > 30 ? '${uri.path.substring(0, 30)}…' : uri.path;
    return '${uri.host}$path';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EMBED CARD
// ═════════════════════════════════════════════════════════════════════════════
//
// Intercepts share dialog URLs from the embed WebView. Instead of opening a
// modal dialog, it routes the shareUrl to AutomationProvider.handleBackgroundShare()
// which silently completes the share in a hidden WebView. A brief overlay
// toast confirms the action to the user without blocking the UI.
//
// ═════════════════════════════════════════════════════════════════════════════
// LINK PREVIEW CARD  —  image-left + text-right horizontal layout
// Replaces the old WebView embed card.
// ═════════════════════════════════════════════════════════════════════════════

// _EmbedCard is kept as an alias so existing references compile
typedef _EmbedCard = _PreviewCard;

class _PreviewCard extends StatefulWidget {
  final FBItem item;
  final VoidCallback onDelete;
  const _PreviewCard({super.key, required this.item, required this.onDelete});
  @override
  State<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<_PreviewCard>
    with AutomaticKeepAliveClientMixin {
  bool _hovered = false;

  // Toast overlay
  OverlayEntry? _toastEntry;

  @override
  bool get wantKeepAlive => true;

  // ── Time-ago label ─────────────────────────────────────────────────────────
  String get _timeAgo {
    final d = DateTime.now().difference(widget.item.savedAt);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours   < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  // ── Short URL display ──────────────────────────────────────────────────────
  String get _shortUrl {
    final uri = Uri.tryParse(widget.item.originalUrl);
    if (uri == null) return widget.item.originalUrl;
    final path = uri.path.length > 30
        ? '${uri.path.substring(0, 30)}…'
        : uri.path;
    return '${uri.host}$path';
  }

  // ── Toast helper ───────────────────────────────────────────────────────────
  void _showToast(String msg, Color color) {
    _toastEntry?.remove();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _toastEntry = OverlayEntry(
      builder: (_) => Positioned(
        bottom: 24, left: 0, right: 0,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: .4)),
              ),
              child: Text(msg,
                  style: TextStyle(color: color, fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_toastEntry!);
    Future.delayed(const Duration(seconds: 3), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  @override
  void dispose() {
    _toastEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final item = widget.item;
    final hasImage = item.ogImage.isNotEmpty;
    final hasTitle = item.ogTitle.isNotEmpty;
    final hasDesc  = item.ogDescription.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF1F2433) : _card,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: _hovered ? _accent.withValues(alpha: .35) : _border,
            width: _hovered ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovered ? .35 : .2),
              blurRadius: _hovered ? 18 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Main row: image + content ────────────────────────────────────────
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── OG Image ───────────────────────────────────────────────────
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft:     Radius.circular(12),
                      bottomLeft:  Radius.circular(12),
                    ),
                    child: SizedBox(
                      width: 96,
                      child: hasImage
                          ? Image.network(
                              item.ogImage,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _NoImagePlaceholder(),
                            )
                          : _NoImagePlaceholder(),
                    ),
                  ),
                  // ── Text content ───────────────────────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          if (hasTitle)
                            Text(
                              item.ogTitle,
                              style: const TextStyle(
                                  color: _text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (hasTitle) const SizedBox(height: 5),
                          // Description
                          if (hasDesc)
                            Text(
                              item.ogDescription,
                              style: const TextStyle(
                                  color: _subL,
                                  fontSize: 10.5,
                                  height: 1.45),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (!hasTitle && !hasDesc)
                            Text(
                              _shortUrl,
                              style: const TextStyle(color: _sub, fontSize: 10.5),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const Spacer(),
                          // URL chip + time
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _accent.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('f',
                                        style: TextStyle(
                                            color: _accent,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(width: 3),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 110),
                                      child: Text(
                                        _shortUrl,
                                        style: const TextStyle(
                                            color: _accentL, fontSize: 9),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(_timeAgo,
                                  style: const TextStyle(
                                      color: _sub, fontSize: 9)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Action toolbar ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: const BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(12)),
                border: Border(top: BorderSide(color: _divider)),
              ),
              child: Row(
                children: [
                  _ToolbarBtn(
                    icon: Icons.copy_rounded,
                    label: 'Copy URL',
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: item.originalUrl));
                      _showToast('URL copied!', _accent);
                    },
                  ),
                  const SizedBox(width: 4),
                  _ToolbarBtn(
                    icon: Icons.open_in_browser_rounded,
                    label: 'Open',
                    onTap: () => context
                        .read<AutomationProvider>()
                        .setPostUrl(item.originalUrl),
                  ),
                  const Spacer(),
                  _ToolbarBtn(
                    icon: Icons.delete_outline_rounded,
                    label: 'Remove',
                    color: _red.withValues(alpha: .8),
                    onTap: widget.onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── No-image placeholder ──────────────────────────────────────────────────────
class _NoImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _surface,
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined,
            color: _sub, size: 22),
      ),
    );
  }
}

// ── Toolbar action button ─────────────────────────────────────────────────────
class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _ToolbarBtn({required this.icon, required this.label,
      required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? _subL;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: c, fontSize: 10,
                fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ── Sync progress banner ─────────────────────────────────────────────────────────────────
class _SyncProgressBanner extends StatelessWidget {
  final int groupsFound;
  const _SyncProgressBanner({required this.groupsFound});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: .07),
        border: Border(
          bottom: BorderSide(color: _accent.withValues(alpha: .18)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: _accentL),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Loaded $groupsFound groups… '
                  'Please wait, handling slow connection.',
                  style: const TextStyle(
                    color: _accentL,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: const LinearProgressIndicator(
              backgroundColor: Color(0xFF252A38),
              color: _accent,
              minHeight: 3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'The WebView is auto-scrolling to load all groups. '
            'Watch progress in the floating window.',
            style: TextStyle(color: _sub, fontSize: 9.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared primitives
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: _sub, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.2));
  }
}

class _ThemedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool showPaste;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  const _ThemedTextField({required this.controller, required this.hint, required this.prefixIcon, this.showPaste = false, this.focusNode, this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: _text, fontSize: 11.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _sub, fontSize: 10.5),
        prefixIcon: Icon(prefixIcon, color: _sub, size: 14),
        suffixIcon: showPaste
            ? IconButton(
                icon: const Icon(Icons.content_paste_rounded, color: _sub, size: 13),
                onPressed: () async {
                  final d = await Clipboard.getData('text/plain');
                  if (d?.text != null) controller.text = d!.text!;
                },
              )
            : null,
        filled: true, fillColor: _card, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _accent, width: 1.5)),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  const _SmallIconButton({required this.icon, required this.color, required this.enabled, required this.onTap, this.loading = false});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? color : _card, borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled && !loading ? onTap : null,
        child: SizedBox(
          width: 38, height: 38,
          child: Center(
            child: loading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white))
                : Icon(icon, size: 16, color: enabled ? Colors.white : _sub),
          ),
        ),
      ),
    );
  }
}

