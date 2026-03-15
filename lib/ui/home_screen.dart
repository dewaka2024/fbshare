// lib/ui/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart';
import '../providers/automation_provider.dart';

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
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AutomationProvider>().initWebView();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          _ControlPanel(),
          _LibraryPanel(),
          Expanded(child: _WebViewPanel()),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// LEFT — Control panel with tabs
// ═════════════════════════════════════════════════════════════════════════════
class _ControlPanel extends StatelessWidget {
  const _ControlPanel();
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Container(
        width: 300,
        decoration: const BoxDecoration(
          color: _surface,
          border: Border(right: BorderSide(color: _divider)),
        ),
        child: const Column(
          children: [
            _AppHeader(),
            _ControlTabBar(),
            Expanded(child: _ControlTabBody()),
            _UrlFooter(),
          ],
        ),
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader();
  @override
  Widget build(BuildContext context) {
    final ready = context.watch<AutomationProvider>().webViewReady;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
      decoration: const BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: _divider)),
      ),
      child: Row(
        children: [
          _FbBadge(),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FB Share Automation',
                    style: TextStyle(color: _text, fontSize: 12.5, fontWeight: FontWeight.w700)),
                SizedBox(height: 1),
                Text('Windows Desktop — v4.0',
                    style: TextStyle(color: _sub, fontSize: 9.5)),
              ],
            ),
          ),
          _ReadyDot(ready: ready),
        ],
      ),
    );
  }
}

class _FbBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color: _accent,
        borderRadius: BorderRadius.circular(9),
        boxShadow: const [BoxShadow(color: Color(0x441877F2), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: const Center(
        child: Text('f', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1)),
      ),
    );
  }
}

class _ReadyDot extends StatelessWidget {
  final bool ready;
  const _ReadyDot({required this.ready});
  @override
  Widget build(BuildContext context) {
    final color = ready ? _green : _sub;
    return Tooltip(
      message: ready ? 'WebView ready' : 'Initialising…',
      child: Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withValues(alpha: .5), blurRadius: 6, spreadRadius: 1)],
        ),
      ),
    );
  }
}

class _ControlTabBar extends StatelessWidget {
  const _ControlTabBar();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _card,
      child: const TabBar(
        labelColor: _accent,
        unselectedLabelColor: _sub,
        indicatorColor: _accent,
        indicatorWeight: 2,
        labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6),
        unselectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
        tabs: [
          Tab(icon: Icon(Icons.layers_rounded, size: 14), text: 'PAGE MANAGER', iconMargin: EdgeInsets.only(bottom: 2)),
          Tab(icon: Icon(Icons.play_circle_rounded, size: 14), text: 'AUTOMATION', iconMargin: EdgeInsets.only(bottom: 2)),
        ],
      ),
    );
  }
}

class _ControlTabBody extends StatelessWidget {
  const _ControlTabBody();
  @override
  Widget build(BuildContext context) {
    return const TabBarView(children: [_PageManagerTab(), _AutomationTab()]);
  }
}

class _UrlFooter extends StatelessWidget {
  const _UrlFooter();
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _divider))),
      child: StreamBuilder<String>(
        stream: prov.urlStream,
        builder: (_, snap) {
          final url = snap.data ?? 'https://www.facebook.com';
          return Row(
            children: [
              const Icon(Icons.language_rounded, color: _sub, size: 10),
              const SizedBox(width: 5),
              Expanded(child: Text(url, style: const TextStyle(color: _sub, fontSize: 9.5), overflow: TextOverflow.ellipsis)),
            ],
          );
        },
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
              ? const _EmptyHint(icon: Icons.web_asset_rounded, message: 'No pages yet.\nPaste a Facebook URL above.')
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
// TAB 2 — AUTOMATION
// ═════════════════════════════════════════════════════════════════════════════
class _AutomationTab extends StatefulWidget {
  const _AutomationTab();
  @override
  State<_AutomationTab> createState() => _AutomationTabState();
}

class _AutomationTabState extends State<_AutomationTab> {
  final _postUrlCtrl = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postUrlCtrl.text = context.read<AutomationProvider>().postUrl;
    });
  }
  @override
  void dispose() { _postUrlCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (prov.selected != null) ...[
            const _SectionLabel('TARGET PAGE'),
            const SizedBox(height: 7),
            _SelectedPageCard(page: prov.selected!),
            const SizedBox(height: 14),
          ] else ...[
            const _InfoTile(icon: Icons.info_outline_rounded, text: 'Select a page in Page Manager first.'),
            const SizedBox(height: 14),
          ],
          const Divider(color: _divider, height: 1),
          const SizedBox(height: 14),
          const _SectionLabel('POST URL TO SHARE'),
          const SizedBox(height: 7),
          _ThemedTextField(
            controller: _postUrlCtrl,
            hint: 'https://www.facebook.com/share/p/…',
            prefixIcon: Icons.link_rounded,
            showPaste: true,
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'Navigate', icon: Icons.open_in_browser_rounded, color: _accent,
                  enabled: prov.webViewReady,
                  onTap: () { prov.setPostUrl(_postUrlCtrl.text); prov.navigateToPost(); },
                ),
              ),
              const SizedBox(width: 7),
              _SmallIconButton(icon: Icons.home_rounded, color: _card, enabled: prov.webViewReady, onTap: prov.navigateHome),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: _divider, height: 1),
          const SizedBox(height: 14),
          const _SectionLabel('STATUS'),
          const SizedBox(height: 7),
          _StatusCard(status: prov.status, message: prov.statusMsg),
          const SizedBox(height: 14),
          const Divider(color: _divider, height: 1),
          const SizedBox(height: 14),
          const _SectionLabel('RUN'),
          const SizedBox(height: 9),
          _StartButton(prov: prov, urlCtrl: _postUrlCtrl),
          if (prov.isRunning) ...[
            const SizedBox(height: 7),
            _ActionButton(label: 'Stop', icon: Icons.stop_rounded, color: _red, enabled: true, onTap: prov.stopAutomation),
          ],
          const SizedBox(height: 16),
          const _HowToBox(),
        ],
      ),
    );
  }
}

class _SelectedPageCard extends StatelessWidget {
  final FBPage page;
  const _SelectedPageCard({required this.page});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(9), border: Border.all(color: _accent.withValues(alpha: .3))),
      child: Row(
        children: [
          _PageAvatar(page: page),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(page.name, style: const TextStyle(color: _accentL, fontSize: 11.5, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(page.url, style: const TextStyle(color: _sub, fontSize: 9.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  final AutomationProvider prov;
  final TextEditingController urlCtrl;
  const _StartButton({required this.prov, required this.urlCtrl});
  @override
  Widget build(BuildContext context) {
    final canStart = prov.webViewReady && !prov.isRunning;
    return Material(
      color: canStart ? _accent : _card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: canStart ? () { prov.setPostUrl(urlCtrl.text); prov.startAutomation(); } : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (prov.isRunning) const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              else const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 7),
              Text(prov.isRunning ? 'Running…' : 'Start Automation',
                  style: TextStyle(color: canStart ? Colors.white : _sub, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final AutomationStatus status;
  final String message;
  const _StatusCard({required this.status, required this.message});

  Color get _dot {
    switch (status) {
      case AutomationStatus.success:  return _green;
      case AutomationStatus.error:    return _red;
      case AutomationStatus.running:
      case AutomationStatus.navigating: return _amber;
      default: return _sub;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dot = _dot;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(9), border: Border.all(color: _border)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6, height: 6,
            margin: const EdgeInsets.only(top: 3.5, right: 8),
            decoration: BoxDecoration(
              color: dot, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: dot.withValues(alpha: .45), blurRadius: 5, spreadRadius: 1)],
            ),
          ),
          Expanded(child: Text(message, style: const TextStyle(color: _text, fontSize: 10.5, height: 1.5))),
        ],
      ),
    );
  }
}

class _HowToBox extends StatelessWidget {
  const _HowToBox();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _accent.withValues(alpha: .16)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HOW TO USE', style: TextStyle(color: _accentL, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          SizedBox(height: 7),
          _Step('1', 'Log in to Facebook inside the WebView.'),
          _Step('2', 'Page Manager → paste page URL → tap +.'),
          _Step('3', 'Select the page from the list.'),
          _Step('4', 'Automation tab → paste post URL.'),
          _Step('5', 'Tap Navigate, then Start Automation.'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String num;
  final String text;
  const _Step(this.num, this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14, height: 14,
            margin: const EdgeInsets.only(right: 7, top: 1),
            decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
            child: Center(child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.w800))),
          ),
          Expanded(child: Text(text, style: const TextStyle(color: _sub, fontSize: 10.5, height: 1.4))),
        ],
      ),
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
  final _urlCtrl = TextEditingController();
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
    super.dispose();
  }

  Future<void> _savePost(AutomationProvider prov) async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || _adding) return;
    setState(() => _adding = true);
    _urlCtrl.clear();
    await prov.addItem(url);
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
                    _PostInputBar(urlCtrl: _urlCtrl, adding: _adding, onSave: () => _savePost(prov)),
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
  final bool adding;
  final VoidCallback onSave;
  const _PostInputBar({required this.urlCtrl, required this.adding, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ThemedTextField(
              controller: urlCtrl,
              hint: 'Paste a Facebook post URL and save…',
              prefixIcon: Icons.add_link_rounded,
              showPaste: true,
              onSubmitted: (_) => onSave(),
            ),
          ),
          const SizedBox(width: 8),
          _SaveButton(loading: adding, onTap: onSave),
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
class _EmbedCard extends StatefulWidget {
  final FBItem item;
  final VoidCallback onDelete;
  const _EmbedCard({super.key, required this.item, required this.onDelete});
  @override
  State<_EmbedCard> createState() => _EmbedCardState();
}

class _EmbedCardState extends State<_EmbedCard> with AutomaticKeepAliveClientMixin {
  EmbedCardController? _ctrl;
  bool _initialising = true;
  bool _expanded = true;
  StreamSubscription<String>? _urlSub;
  // Toast overlay for background share feedback
  OverlayEntry? _toastEntry;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    final prov = context.read<AutomationProvider>();
    final ctrl = await prov.getOrCreateController(widget.item);
    if (!mounted) return;

    if (ctrl.wvc != null) {
      _urlSub = ctrl.wvc!.url.listen((url) {
        if (!mounted) return;
        if (url.contains('facebook.com/dialog/share') ||
            url.contains('facebook.com/sharer')) {
          // Reset the embed card immediately.
          ctrl.wvc!.loadUrl(widget.item.embedUrl);
          // Route share to background handler — no blocking modal.
          _handleShareInBackground(url);
        }
      });
    }

    setState(() { _ctrl = ctrl; _initialising = false; });
  }

  // ── Background share ──────────────────────────────────────────────────────
  void _handleShareInBackground(String shareUrl) {
    _showToast('Sharing in background…', _amber);
    context.read<AutomationProvider>().handleBackgroundShare(shareUrl).then((_) {
      if (!mounted) return;
      final prov = context.read<AutomationProvider>();
      if (prov.status == AutomationStatus.success) {
        _showToast('✅ Shared successfully', _green);
      } else if (prov.status == AutomationStatus.error) {
        _showToast('❌ Share failed', _red);
      }
    });
  }

  void _showToast(String message, Color color) {
    _toastEntry?.remove();
    _toastEntry = null;
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
              child: Text(message,
                  style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
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
    _urlSub?.cancel();
    _toastEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 16, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            item: widget.item,
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
            onDelete: widget.onDelete,
            onReload: () => _ctrl?.wvc?.loadUrl(widget.item.embedUrl),
          ),
          if (_expanded) _EmbedBody(ctrl: _ctrl, initialising: _initialising),
        ],
      ),
    );
  }
}

// ── Card header ───────────────────────────────────────────────────────────────
class _CardHeader extends StatelessWidget {
  final FBItem item;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onReload;
  const _CardHeader({required this.item, required this.expanded, required this.onToggle, required this.onDelete, required this.onReload});

  String get _shortUrl {
    final uri = Uri.tryParse(item.originalUrl);
    if (uri == null) return item.originalUrl;
    final path = uri.path.length > 28 ? '${uri.path.substring(0, 28)}…' : uri.path;
    return '${uri.host}$path';
  }

  String get _timeAgo {
    final diff = DateTime.now().difference(item.savedAt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle, behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: _cardHov,
          borderRadius: expanded
              ? const BorderRadius.vertical(top: Radius.circular(12))
              : BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(color: _accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(6)),
              child: const Center(child: Text('f', style: TextStyle(color: _accent, fontSize: 14, fontWeight: FontWeight.w900, height: 1))),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_shortUrl, style: const TextStyle(color: _text, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.schedule_rounded, color: _sub, size: 9),
                    const SizedBox(width: 3),
                    Text(_timeAgo, style: const TextStyle(color: _sub, fontSize: 9.5)),
                  ]),
                ],
              ),
            ),
            _HeaderIconBtn(icon: Icons.copy_rounded, tooltip: 'Copy URL', onTap: () => Clipboard.setData(ClipboardData(text: item.originalUrl))),
            const SizedBox(width: 1),
            _HeaderIconBtn(icon: Icons.refresh_rounded, tooltip: 'Reload embed', onTap: onReload),
            const SizedBox(width: 1),
            _HeaderIconBtn(
              icon: expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              tooltip: expanded ? 'Collapse' : 'Expand',
              onTap: onToggle,
            ),
            const SizedBox(width: 1),
            _HeaderIconBtn(icon: Icons.delete_outline_rounded, tooltip: 'Remove', color: _red.withValues(alpha: .7), onTap: onDelete),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;
  const _HeaderIconBtn({required this.icon, required this.tooltip, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, size: 13, color: color ?? _subL)),
      ),
    );
  }
}

// ── Embed body ────────────────────────────────────────────────────────────────
class _EmbedBody extends StatelessWidget {
  final EmbedCardController? ctrl;
  final bool initialising;
  const _EmbedBody({required this.ctrl, required this.initialising});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Container(
        color: Colors.white, height: 420,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (initialising || ctrl == null || !ctrl!.ready || ctrl!.wvc == null) {
      return const _EmbedLoadingPlaceholder();
    }
    return Stack(
      children: [
        Webview(ctrl!.wvc!),
        StreamBuilder<LoadingState>(
          stream: ctrl!.wvc!.loadingState,
          builder: (_, snap) {
            if (snap.data != LoadingState.loading) return const SizedBox.shrink();
            return Container(
              color: Colors.white.withValues(alpha: .88),
              child: const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: _accent)),
                  SizedBox(height: 10),
                  Text('Loading embed…', style: TextStyle(color: _sub, fontSize: 11, fontWeight: FontWeight.w500)),
                ]),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _EmbedLoadingPlaceholder extends StatelessWidget {
  const _EmbedLoadingPlaceholder();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: _accent)),
        SizedBox(height: 12),
        Text('Initialising WebView…', style: TextStyle(color: _sub, fontSize: 11, fontWeight: FontWeight.w500)),
        SizedBox(height: 3),
        Text('Facebook embed will appear here', style: TextStyle(color: _sub, fontSize: 10)),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// RIGHT — Main WebView panel
// ═════════════════════════════════════════════════════════════════════════════
class _WebViewPanel extends StatelessWidget {
  const _WebViewPanel();
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AutomationProvider>();
    return Container(
      color: _bg,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _AddressBar(prov: prov),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _border, width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 28, offset: const Offset(0, 10))],
              ),
              clipBehavior: Clip.hardEdge,
              child: prov.webviewController == null
                  ? const Center(child: CircularProgressIndicator(color: _accent))
                  : Stack(children: [
                      Webview(prov.webviewController!),
                      _LoadingOverlay(stream: prov.loadingStream),
                    ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressBar extends StatelessWidget {
  final AutomationProvider prov;
  const _AddressBar({required this.prov});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(9), border: Border.all(color: _border)),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, color: _sub, size: 12),
          const SizedBox(width: 7),
          Expanded(
            child: StreamBuilder<String>(
              stream: prov.urlStream,
              builder: (_, snap) => Text(
                snap.data ?? 'https://www.facebook.com',
                style: const TextStyle(color: _sub, fontSize: 10.5), overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          StreamBuilder<LoadingState>(
            stream: prov.loadingStream,
            builder: (_, snap) {
              if (snap.data == LoadingState.loading) {
                return const SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: _accent));
              }
              return const Icon(Icons.check_circle_rounded, color: _green, size: 12);
            },
          ),
          const SizedBox(width: 6),
          // ── DevTools button ────────────────────────────────────────────
          // Opens the WebView2 Chromium DevTools panel for the main
          // automation browser. Use it to inspect the mobile Facebook DOM
          // and find exact selectors for group rows, share buttons, etc.
          Tooltip(
            message: 'Open DevTools (Inspect)',
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: prov.webViewReady ? prov.openDevTools : null,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.code_rounded,
                  size: 13,
                  color: prov.webViewReady ? _accentL : _sub,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  final Stream<LoadingState>? stream;
  const _LoadingOverlay({required this.stream});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LoadingState>(
      stream: stream,
      builder: (_, snap) {
        if (snap.data != LoadingState.loading) return const SizedBox.shrink();
        return Container(
          color: _bg.withValues(alpha: .6),
          child: const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2.5)),
        );
      },
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

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? color : _card, borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: enabled ? Colors.white : _sub),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: enabled ? Colors.white : _sub, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
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

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyHint({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _border, size: 32),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _sub, fontSize: 11.5, height: 1.6)),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoTile({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
      child: Row(
        children: [
          Icon(icon, color: _sub, size: 14),
          const SizedBox(width: 7),
          Expanded(child: Text(text, style: const TextStyle(color: _sub, fontSize: 10.5, height: 1.4))),
        ],
      ),
    );
  }
}
