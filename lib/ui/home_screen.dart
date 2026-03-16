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
// Three-column: Control | Groups List | Library
// ─────────────────────────────────────────────────────────────────────────────
class _AutomationPage extends StatefulWidget {
  const _AutomationPage();
  @override
  State<_AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends State<_AutomationPage> {
  final _postLinkCtrl = TextEditingController();

  @override
  void dispose() {
    _postLinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();

    return Column(
      children: [
        // ── Header bar ─────────────────────────────────────────────────────
        _PageHeader(prov: prov),

        // ── Body: groups list + library sidebar ────────────────────────────
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left column: groups list
              Expanded(child: _GroupsListColumn(prov: prov)),
              // Right sidebar: saved posts library
              const SizedBox(
                width: 400,
                child: _LibraryPanel(),
              ),
            ],
          ),
        ),

        // ── Footer: post link + start sharing ──────────────────────────────
        _PageFooter(prov: prov, postLinkCtrl: _postLinkCtrl),
      ],
    );
  }
}

// ── Header bar ────────────────────────────────────────────────────────────────
class _PageHeader extends StatelessWidget {
  final AutomationProvider prov;
  const _PageHeader({required this.prov});

  Color get _statusColor {
    switch (prov.status) {
      case AutomationStatus.success:   return _green;
      case AutomationStatus.error:     return _red;
      case AutomationStatus.running:
      case AutomationStatus.navigating: return _amber;
      default: return _sub;
    }
  }

  String get _statusLabel {
    switch (prov.status) {
      case AutomationStatus.success:    return 'Success';
      case AutomationStatus.error:      return 'Error';
      case AutomationStatus.running:    return 'Running…';
      case AutomationStatus.navigating: return 'Navigating…';
      default: return 'Ready';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _divider)),
      ),
      child: Row(
        children: [
          // Page title
          const Text('Automation',
              style: TextStyle(
                  color: _text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          const Text('Groups & Sharing',
              style: TextStyle(color: _sub, fontSize: 11)),

          const Spacer(),

          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _statusColor.withValues(alpha: .3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: _statusColor.withValues(alpha: .5),
                          blurRadius: 4),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Status: $_statusLabel',
                  style: TextStyle(
                      color: _statusColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Sync Groups button
          ElevatedButton.icon(
            onPressed: prov.webViewReady && !prov.isSyncing
                ? () => prov.fetchGroups()
                : null,
            icon: prov.isSyncing
                ? const SizedBox(
                    width: 13, height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.8, color: Colors.white))
                : const Icon(Icons.sync_rounded, size: 15),
            label: Text(prov.isSyncing
                ? 'Syncing… (${prov.groupsFound})'
                : 'Sync Groups'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
              elevation: 0,
            ),
          ),
          const SizedBox(width: 10),

          // Control panel toggle — compact icon button
          Tooltip(
            message: 'Automation settings',
            child: _IconBtn(
              icon: Icons.tune_rounded,
              onTap: () => _showAutomationSettings(context, prov),
            ),
          ),
        ],
      ),
    );
  }

  void _showAutomationSettings(
      BuildContext context, AutomationProvider prov) {
    showDialog(
      context: context,
      builder: (_) => _AutomationSettingsDialog(prov: prov),
    );
  }
}

// ── Groups list column (middle of automation page) ─────────────────────────────
class _GroupsListColumn extends StatelessWidget {
  final AutomationProvider prov;
  const _GroupsListColumn({required this.prov});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sub-header
          if (prov.isSyncing) _SyncProgressBanner(groupsFound: prov.groupsFound),
          if (prov.groupsError != null && !prov.isSyncing)
            _ErrorBanner(message: prov.groupsError!),

          // Group count label
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                const Icon(Icons.group_rounded, color: _sub, size: 13),
                const SizedBox(width: 6),
                Text(
                  prov.groups.isEmpty
                      ? 'No groups loaded'
                      : '${prov.groups.length} groups',
                  style: const TextStyle(
                      color: _sub,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3),
                ),
                if (prov.groups.isNotEmpty) ...[
                  const Spacer(),
                  GestureDetector(
                    onTap: prov.clearGroups,
                    child: const Text('Clear',
                        style: TextStyle(
                            color: _sub,
                            fontSize: 9.5,
                            decoration: TextDecoration.underline)),
                  ),
                ],
              ],
            ),
          ),

          // Groups list
          Expanded(
            child: prov.groups.isEmpty
                ? _GroupsEmptyState(prov: prov)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 80),
                    itemCount: prov.groups.length,
                    itemBuilder: (_, i) {
                      final g = prov.groups[i];
                      return _GroupRowCard(
                        group: g,
                        onTap: () => prov.navigateToGroup(g),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Group row card ─────────────────────────────────────────────────────────────
class _GroupRowCard extends StatefulWidget {
  final FBGroup group;
  final VoidCallback onTap;
  const _GroupRowCard({required this.group, required this.onTap});
  @override
  State<_GroupRowCard> createState() => _GroupRowCardState();
}

class _GroupRowCardState extends State<_GroupRowCard> {
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
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF1F2433) : _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? _accent.withValues(alpha: .3)
                  : _border,
              width: _hovered ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Leading: CircleAvatar
              _GroupCircleAvatar(imageUrl: widget.group.imageUrl),
              const SizedBox(width: 12),
              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.group.name,
                      style: TextStyle(
                          color: _hovered ? _accentL : _text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.group.url.isNotEmpty
                          ? widget.group.url
                          : 'Index #${widget.group.index}',
                      style: const TextStyle(
                          color: _sub, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Trailing: checkmark
              AnimatedOpacity(
                opacity: _hovered ? 1 : 0.35,
                duration: const Duration(milliseconds: 120),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: _hovered ? _green : _sub,
                ),
              ),
            ],
          ),
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

// ── Footer: post link + start sharing ─────────────────────────────────────────
class _PageFooter extends StatelessWidget {
  final AutomationProvider prov;
  final TextEditingController postLinkCtrl;
  const _PageFooter({required this.prov, required this.postLinkCtrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _divider)),
      ),
      child: Row(
        children: [
          // Post link field
          Expanded(
            child: TextField(
              controller: postLinkCtrl,
              style: const TextStyle(color: _text, fontSize: 12),
              onSubmitted: (v) {
                prov.setPostUrl(v);
                prov.startAutomation();
              },
              decoration: InputDecoration(
                hintText: 'Paste Facebook post link to share…',
                hintStyle:
                    const TextStyle(color: _sub, fontSize: 11),
                prefixIcon: const Icon(Icons.link_rounded,
                    color: _sub, size: 16),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded,
                      color: _sub, size: 14),
                  onPressed: () async {
                    final d =
                        await Clipboard.getData('text/plain');
                    if (d?.text != null) {
                      postLinkCtrl.text = d!.text!;
                    }
                  },
                ),
                filled: true,
                fillColor: _card,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 11),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide:
                        const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide:
                        const BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: const BorderSide(
                        color: _accent, width: 1.5)),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Navigate button
          _IconBtn(
            icon: Icons.open_in_browser_rounded,
            tooltip: 'Navigate to post',
            onTap: prov.webViewReady
                ? () {
                    prov.setPostUrl(postLinkCtrl.text);
                    prov.navigateToPost();
                  }
                : null,
          ),
          const SizedBox(width: 8),

          // Start Sharing button
          ElevatedButton.icon(
            onPressed:
                prov.webViewReady && !prov.isRunning && prov.groups.isNotEmpty
                    ? () {
                        prov.setPostUrl(postLinkCtrl.text);
                        prov.startAutomation();
                      }
                    : null,
            icon: prov.isRunning
                ? const SizedBox(
                    width: 13, height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.8, color: Colors.white))
                : const Icon(Icons.play_arrow_rounded, size: 16),
            label: Text(
                prov.isRunning ? 'Running…' : 'Start Sharing'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _card,
              disabledForegroundColor: _sub,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 11),
              textStyle: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
              elevation: 0,
            ),
          ),

          // Stop button (only when running)
          if (prov.isRunning) ...[
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: prov.stopAutomation,
              icon: const Icon(Icons.stop_rounded, size: 15),
              label: const Text('Stop'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
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

// ── Error banner ───────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _red.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: _red, size: 14),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: _red, fontSize: 10.5, height: 1.4))),
        ],
      ),
    );
  }
}

// ── Small icon button ──────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;
  const _IconBtn({required this.icon, this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            width: 38, height: 38,
            alignment: Alignment.center,
            child: Icon(icon,
                size: 16,
                color: onTap != null ? _subL : _sub),
          ),
        ),
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
  final ValueChanged<String>? onSubmitted;
  const _ThemedTextField({required this.controller, required this.hint, required this.prefixIcon, this.showPaste = false, this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
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

