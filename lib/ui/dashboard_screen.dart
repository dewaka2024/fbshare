// lib/ui/dashboard_screen.dart
// FB Share Pro — Professional 3-Column Dashboard
// Layout: Post Repository (2.5) | Group Categorizer (4) | Live Status (3.5)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dashboard_provider.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _bg       = Color(0xFF0B0E17);
const _surface  = Color(0xFF111520);
const _card     = Color(0xFF161C2D);
const _cardHov  = Color(0xFF1C2438);
const _border   = Color(0xFF1F2640);
const _divider  = Color(0xFF181D2E);
const _accent   = Color(0xFF1877F2);
const _accentL  = Color(0xFF4D9BFF);
const _green    = Color(0xFF1ED760);
const _amber    = Color(0xFFFFAA00);
const _red      = Color(0xFFFF4757);
const _terminal = Color(0xFF080C14);
const _text     = Color(0xFFE2E8F8);
const _sub      = Color(0xFF4E5B7A);
const _subL     = Color(0xFF7B8DB8);
const _slate    = Color(0xFF8A99C0);

TextStyle _labelStyle() => const TextStyle(
    color: _slate, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.1);

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen
// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DashboardProvider()..loadDemoGroups(),
      child: const _DashboardBody(),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          const _TopBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Column 1 — Post Repository (flex 25)
                Expanded(
                  flex: 25,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: _surface,
                      border: Border(right: BorderSide(color: _border)),
                    ),
                    child: const _PostRepositoryColumn(),
                  ),
                ),
                // Column 2 — Group Categorizer (flex 40)
                Expanded(
                  flex: 40,
                  child: Container(
                    color: _surface,
                    child: const _GroupCategorizerColumn(),
                  ),
                ),
                // Column 3 — Live Status Log (flex 35)
                Expanded(
                  flex: 35,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: _surface,
                      border: Border(left: BorderSide(color: _border)),
                    ),
                    child: const _LiveStatusColumn(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: _surface,
        border: const Border(bottom: BorderSide(color: _border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Logo
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: _accent.withValues(alpha: .4), blurRadius: 10)],
            ),
            child: const Center(
              child: Text('f', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, height: 1)),
            ),
          ),
          const SizedBox(width: 10),
          const Text('FB Share Pro', style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: .3)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _accent.withValues(alpha: .3)),
            ),
            child: const Text('PRO', style: TextStyle(color: _accentL, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
          const Spacer(),
          if (prov.selectedGroupCount > 0) ...[
            _StatusChip(icon: Icons.groups_rounded, label: '${prov.selectedGroupCount} selected', color: _accentL),
            const SizedBox(width: 8),
          ],
          if (prov.isRunning) ...[
            _StatusChip(icon: Icons.play_circle_filled_rounded, label: '${prov.sharedCount}/${prov.targetCount} shared', color: _green, pulse: true),
            const SizedBox(width: 8),
          ],
          const _TopBarIcon(icon: Icons.send_rounded, tooltip: 'Post Share', active: true),
          const SizedBox(width: 4),
          const _TopBarIcon(icon: Icons.person_add_rounded, tooltip: 'Follow-up'),
          const SizedBox(width: 4),
          const _TopBarIcon(icon: Icons.settings_rounded, tooltip: 'Settings'),
        ],
      ),
    );
  }
}

class _StatusChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;
  const _StatusChip({required this.icon, required this.label, required this.color, this.pulse = false});
  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    Widget dot = Container(width: 6, height: 6, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle));
    if (widget.pulse) dot = FadeTransition(opacity: _anim, child: dot);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: widget.color.withValues(alpha: .25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        dot, const SizedBox(width: 5),
        Text(widget.label, style: TextStyle(color: widget.color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _TopBarIcon extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  const _TopBarIcon({required this.icon, required this.tooltip, this.active = false});
  @override
  State<_TopBarIcon> createState() => _TopBarIconState();
}

class _TopBarIconState extends State<_TopBarIcon> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: widget.active ? _accent.withValues(alpha: .15) : (_hovered ? _card : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: widget.active ? Border.all(color: _accent.withValues(alpha: .3)) : null,
          ),
          child: Icon(widget.icon, size: 17, color: widget.active ? _accentL : (_hovered ? _subL : _sub)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Column 1 — Post Repository
// ─────────────────────────────────────────────────────────────────────────────
class _PostRepositoryColumn extends StatefulWidget {
  const _PostRepositoryColumn();
  @override
  State<_PostRepositoryColumn> createState() => _PostRepositoryColumnState();
}

class _PostRepositoryColumnState extends State<_PostRepositoryColumn> {
  final _nameCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _linkFocus = FocusNode();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _linkCtrl.dispose();
    _nameFocus.dispose();
    _linkFocus.dispose();
    super.dispose();
  }

  void _save(DashboardProvider prov) {
    if (_nameCtrl.text.trim().isEmpty || _linkCtrl.text.trim().isEmpty) return;
    prov.addPost(_nameCtrl.text, _linkCtrl.text);
    _nameCtrl.clear();
    _linkCtrl.clear();
    _nameFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ColHeader(icon: Icons.bookmark_rounded, title: 'Post Repository', badge: prov.posts.length),
        // Add form
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.add_link_rounded, size: 14, color: _accentL),
                const SizedBox(width: 6),
                Text('ADD NEW LINK', style: _labelStyle()),
              ]),
              const SizedBox(height: 10),
              _DarkTextField(controller: _nameCtrl, focusNode: _nameFocus, hint: 'Post name / label', icon: Icons.title_rounded,
                  onSubmitted: (_) => _linkFocus.requestFocus()),
              const SizedBox(height: 8),
              _DarkTextField(controller: _linkCtrl, focusNode: _linkFocus, hint: 'https://facebook.com/…', icon: Icons.link_rounded,
                  onSubmitted: (_) => _save(prov)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity, height: 36,
                child: _AccentButton(icon: Icons.save_rounded, label: 'Save Post', onPressed: () => _save(prov)),
              ),
            ]),
          ),
        ),
        // List header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Text('SAVED POSTS', style: _labelStyle()),
            const Spacer(),
            if (prov.posts.isNotEmpty)
              Text('${prov.posts.length}', style: const TextStyle(color: _subL, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 6),
        // Posts list
        Expanded(
          child: prov.posts.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inbox_rounded, color: _sub, size: 32),
                  SizedBox(height: 8),
                  Text('No posts saved yet', style: TextStyle(color: _sub, fontSize: 12)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  itemCount: prov.posts.length,
                  itemBuilder: (_, i) {
                    final post = prov.posts[i];
                    return _PostListItem(
                      post: post,
                      selected: prov.selectedPost?.id == post.id,
                      onTap: () => prov.selectPost(post),
                      onDelete: () => prov.removePost(post.id),
                    );
                  },
                ),
        ),
        // START AUTOMATION button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
          child: _StartAutomationButton(),
        ),
      ],
    );
  }
}

class _PostListItem extends StatefulWidget {
  final PostItem post;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _PostListItem({required this.post, required this.selected, required this.onTap, required this.onDelete});
  @override
  State<_PostListItem> createState() => _PostListItemState();
}

class _PostListItemState extends State<_PostListItem> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: sel ? _accent.withValues(alpha: .15) : (_hovered ? _cardHov : _card),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? _accent.withValues(alpha: .5) : _border),
          ),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: sel ? _accent.withValues(alpha: .2) : _surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.article_rounded, size: 16, color: sel ? _accentL : _sub),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.post.name,
                style: TextStyle(color: sel ? _text : _subL, fontSize: 12.5, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(widget.post.link,
                style: const TextStyle(color: _sub, fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            if (sel) const Icon(Icons.check_circle_rounded, color: _accentL, size: 14),
            if (_hovered && !sel)
              GestureDetector(onTap: widget.onDelete,
                child: const Icon(Icons.close_rounded, color: _sub, size: 14)),
          ]),
        ),
      ),
    );
  }
}

class _StartAutomationButton extends StatefulWidget {
  @override
  State<_StartAutomationButton> createState() => _StartAutomationButtonState();
}

class _StartAutomationButtonState extends State<_StartAutomationButton>
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
    final prov = context.watch<DashboardProvider>();
    final canStart = prov.selectedPost != null && prov.selectedGroupCount > 0;
    final running = prov.isRunning;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => GestureDetector(
        onTap: () {
          if (running) { prov.stopAutomation(); }
          else if (canStart) { prov.startAutomation(); }
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
                      : [_sub.withValues(alpha: .5), _sub.withValues(alpha: .4)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(
              color: (running ? _red : canStart ? _accent : Colors.transparent).withValues(alpha: canStart ? .45 : 0),
              blurRadius: (canStart && !running) ? _glow.value : 6,
            )],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              running ? 'STOP AUTOMATION' : canStart ? 'START AUTOMATION' : 'SELECT POST & GROUPS',
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: .7),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Column 2 — Group Categorizer
// ─────────────────────────────────────────────────────────────────────────────
class _GroupCategorizerColumn extends StatelessWidget {
  const _GroupCategorizerColumn();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ColHeader(
          icon: Icons.account_tree_rounded,
          title: 'Group Categorizer',
          badge: prov.totalGroupCount,
          action: _HeaderAction(
            icon: Icons.create_new_folder_rounded,
            label: 'New Category',
            onPressed: () => _showNewCategoryDialog(context, prov),
          ),
        ),
        // Sync controls
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('SYNC STATUS', style: _labelStyle()),
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
              else if (prov.totalGroupCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _green.withValues(alpha: .1), borderRadius: BorderRadius.circular(4)),
                  child: const Text('SYNCED', style: TextStyle(color: _green, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: SizedBox(height: 34,
                  child: _AccentButton(
                    icon: Icons.sync_rounded,
                    label: prov.isSyncing ? 'Syncing…' : 'Deep Sync',
                    onPressed: prov.isSyncing ? null
                        : () => prov.beginSyncDemo(prov.totalGroupCount > 0 ? prov.totalGroupCount : 69),
                  )),
              ),
              const SizedBox(width: 10),
              Text(
                '${prov.isSyncing ? prov.syncCurrent : prov.totalGroupCount}/${prov.isSyncing ? prov.syncTotal : prov.totalGroupCount} Groups',
                style: const TextStyle(color: _subL, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: prov.syncTotal > 0
                    ? prov.syncCurrent / prov.syncTotal
                    : (prov.totalGroupCount > 0 ? 1.0 : 0.0),
                backgroundColor: _border,
                valueColor: AlwaysStoppedAnimation<Color>(prov.isSyncing ? _amber : _accent),
                minHeight: 5,
              ),
            ),
          ])),
        ),
        // Groups accordion list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              _CategoryAccordion(
                categoryId: '',
                categoryName: 'Uncategorized',
                isUncategorized: true,
                isExpanded: true,
                groups: prov.groupsForCategory(''),
                categories: prov.categories,
                onMoveGroup: prov.moveGroupToCategory,
                onToggleGroup: prov.toggleGroupSelection,
                onSelectAll: () => prov.selectAllGroups(''),
              ),
              const SizedBox(height: 6),
              ...prov.categories.map((cat) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _CategoryAccordion(
                  categoryId: cat.id,
                  categoryName: cat.name,
                  isExpanded: cat.isExpanded,
                  groups: prov.groupsForCategory(cat.id),
                  categories: prov.categories,
                  onMoveGroup: prov.moveGroupToCategory,
                  onToggleGroup: prov.toggleGroupSelection,
                  onSelectAll: () => prov.selectAllGroups(cat.id),
                  onToggleExpand: () => prov.toggleCategoryExpanded(cat.id),
                  onDelete: () => prov.removeCategory(cat.id),
                ),
              )),
            ],
          ),
        ),
      ],
    );
  }

  void _showNewCategoryDialog(BuildContext context, DashboardProvider prov) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _border)),
        title: const Row(children: [
          Icon(Icons.create_new_folder_rounded, color: _accentL, size: 20),
          SizedBox(width: 8),
          Text('Create Category', style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
        content: SizedBox(
          width: 320,
          child: _DarkTextField(controller: ctrl, hint: 'e.g. Sales, Leads, Marketing', icon: Icons.label_rounded),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _subL))),
          ElevatedButton(
            onPressed: () { prov.addCategory(ctrl.text); Navigator.pop(context); },
            style: ElevatedButton.styleFrom(backgroundColor: _accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _CategoryAccordion extends StatelessWidget {
  final String categoryId;
  final String categoryName;
  final bool isExpanded;
  final bool isUncategorized;
  final List<GroupItem> groups;
  final List<CategoryItem> categories;
  final void Function(String groupId, String catId) onMoveGroup;
  final void Function(String groupId) onToggleGroup;
  final VoidCallback onSelectAll;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onDelete;

  const _CategoryAccordion({
    required this.categoryId,
    required this.categoryName,
    required this.groups,
    required this.categories,
    required this.onMoveGroup,
    required this.onToggleGroup,
    required this.onSelectAll,
    this.isExpanded = true,
    this.isUncategorized = false,
    this.onToggleExpand,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final selectedCount = groups.where((g) => g.isSelected).length;
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(children: [
        // Header
        GestureDetector(
          onTap: onToggleExpand,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: _subL, size: 16),
              const SizedBox(width: 6),
              Icon(isUncategorized ? Icons.help_outline_rounded : Icons.folder_rounded,
                  size: 15, color: isUncategorized ? _sub : _amber),
              const SizedBox(width: 6),
              Expanded(child: Text(categoryName,
                style: TextStyle(color: isUncategorized ? _subL : _text, fontSize: 12.5, fontWeight: FontWeight.w600))),
              if (selectedCount > 0) ...[
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: _accent.withValues(alpha: .2), borderRadius: BorderRadius.circular(4)),
                  child: Text('$selectedCount ✓', style: const TextStyle(color: _accentL, fontSize: 9.5, fontWeight: FontWeight.w700)),
                ),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(4), border: Border.all(color: _border)),
                child: Text('${groups.length}', style: const TextStyle(color: _subL, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              if (!isUncategorized) ...[
                const SizedBox(width: 6),
                GestureDetector(onTap: onDelete,
                  child: const Icon(Icons.delete_outline_rounded, color: _sub, size: 14)),
              ],
              if (groups.isNotEmpty) ...[
                const SizedBox(width: 6),
                Tooltip(message: 'Select all',
                  child: GestureDetector(onTap: onSelectAll,
                    child: const Icon(Icons.select_all_rounded, color: _sub, size: 14))),
              ],
            ]),
          ),
        ),
        if (isExpanded) ...[
          if (groups.isNotEmpty) ...[
            const Divider(color: _divider, height: 1),
            ...groups.map((g) => _GroupTile(
              group: g,
              categories: categories,
              currentCategoryId: categoryId,
              onToggle: () => onToggleGroup(g.id),
              onMove: (catId) => onMoveGroup(g.id, catId),
            )),
            const SizedBox(height: 4),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('No groups — drop some here', textAlign: TextAlign.center,
                  style: TextStyle(color: _sub, fontSize: 11, fontStyle: FontStyle.italic)),
            ),
        ],
      ]),
    );
  }
}

class _GroupTile extends StatefulWidget {
  final GroupItem group;
  final List<CategoryItem> categories;
  final String currentCategoryId;
  final VoidCallback onToggle;
  final void Function(String catId) onMove;
  const _GroupTile({required this.group, required this.categories, required this.currentCategoryId, required this.onToggle, required this.onMove});
  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final sel = widget.group.isSelected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _accent.withValues(alpha: .1) : (_hovered ? _cardHov : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: sel ? Border.all(color: _accent.withValues(alpha: .3)) : null,
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: sel ? _accent : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: sel ? _accent : _sub, width: 1.5),
              ),
              child: sel ? const Icon(Icons.check_rounded, size: 10, color: Colors.white) : null,
            ),
            const SizedBox(width: 8),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.groups_rounded, size: 15, color: _subL),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.group.name,
              style: TextStyle(color: sel ? _text : _subL, fontSize: 12,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (_hovered && widget.categories.isNotEmpty)
              _MoveButton(categories: widget.categories, currentCategoryId: widget.currentCategoryId, onMove: widget.onMove),
          ]),
        ),
      ),
    );
  }
}

class _MoveButton extends StatelessWidget {
  final List<CategoryItem> categories;
  final String currentCategoryId;
  final void Function(String catId) onMove;
  const _MoveButton({required this.categories, required this.currentCategoryId, required this.onMove});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Move to category',
      padding: EdgeInsets.zero,
      color: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: _border)),
      icon: const Icon(Icons.drive_file_move_rounded, size: 14, color: _subL),
      onSelected: onMove,
      itemBuilder: (_) => [
        if (currentCategoryId != '')
          const PopupMenuItem(value: '',
            child: Row(children: [
              Icon(Icons.folder_off_rounded, size: 14, color: _sub),
              SizedBox(width: 6),
              Text('Uncategorized', style: TextStyle(color: _subL, fontSize: 12)),
            ])),
        ...categories.where((c) => c.id != currentCategoryId).map((cat) =>
          PopupMenuItem(value: cat.id,
            child: Row(children: [
              const Icon(Icons.folder_rounded, size: 14, color: _amber),
              const SizedBox(width: 6),
              Text(cat.name, style: const TextStyle(color: _text, fontSize: 12)),
            ]))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Column 3 — Live Status Log
// ─────────────────────────────────────────────────────────────────────────────
class _LiveStatusColumn extends StatelessWidget {
  const _LiveStatusColumn();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ColHeader(
          icon: Icons.terminal_rounded,
          title: 'Live Status',
          action: _HeaderAction(icon: Icons.delete_sweep_rounded, label: 'Clear', onPressed: prov.clearLog),
        ),
        // Progress card
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('OVERALL PROGRESS', style: _labelStyle()),
              const Spacer(),
              Text(
                prov.targetCount > 0 ? '${prov.sharedCount} / ${prov.targetCount} Groups' : 'Idle',
                style: TextStyle(color: prov.isRunning ? _accentL : _sub, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: prov.targetCount > 0 ? prov.sharedCount / prov.targetCount : 0,
                backgroundColor: _border,
                valueColor: AlwaysStoppedAnimation<Color>(
                    prov.isRunning ? _green : (prov.sharedCount > 0 ? _accentL : _sub)),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              _ProgressStat(label: 'Shared', value: '${prov.sharedCount}', color: _green),
              const SizedBox(width: 14),
              _ProgressStat(label: 'Remaining', value: '${(prov.targetCount - prov.sharedCount).clamp(0, 9999)}', color: _amber),
              const SizedBox(width: 14),
              _ProgressStat(label: 'Selected', value: '${prov.selectedGroupCount}', color: _accentL),
            ]),
          ])),
        ),
        // Log header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Row(children: [
            Text('ACTIVITY LOG', style: _labelStyle()),
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
        // Terminal
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: _terminal,
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
                // Entries
                Expanded(
                  child: prov.logEntries.isEmpty
                      ? const Center(child: Text(
                          '> Waiting for automation…\n> Select a post and groups to begin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF2A4A2A), fontSize: 11, fontFamily: 'monospace')))
                      : ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: prov.logEntries.length,
                          itemBuilder: (_, i) => _LogLine(entry: prov.logEntries[i]),
                        ),
                ),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ProgressStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
    Text(label, style: const TextStyle(color: _sub, fontSize: 9.5)),
  ]);
}

class _TermDot extends StatelessWidget {
  final Color color;
  const _TermDot({required this.color});
  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color.withValues(alpha: .6), shape: BoxShape.circle));
}

class _LogLine extends StatelessWidget {
  final LogEntry entry;
  const _LogLine({required this.entry});

  Color get _color {
    switch (entry.level) {
      case LogLevel.success: return const Color(0xFF1ED760);
      case LogLevel.warning: return const Color(0xFFFFAA00);
      case LogLevel.error:   return const Color(0xFFFF4757);
      case LogLevel.info:    return const Color(0xFF8899CC);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: RichText(text: TextSpan(
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.5),
      children: [
        TextSpan(text: '${entry.timestamp} ', style: const TextStyle(color: Color(0xFF3A5070))),
        const TextSpan(text: '— ', style: TextStyle(color: Color(0xFF2A3A55))),
        TextSpan(text: entry.message, style: TextStyle(color: _color)),
      ],
    )),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Components
// ─────────────────────────────────────────────────────────────────────────────

class _ColHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? badge;
  final Widget? action;
  const _ColHeader({required this.icon, required this.title, this.badge, this.action});

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
      const Spacer(),
      if (action != null) action!,
    ]),
  );
}

class _HeaderAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _HeaderAction({required this.icon, required this.label, required this.onPressed});
  @override
  State<_HeaderAction> createState() => _HeaderActionState();
}

class _HeaderActionState extends State<_HeaderAction> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: _hovered ? _card : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _hovered ? _border : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.icon, size: 13, color: _hovered ? _accentL : _sub),
          const SizedBox(width: 4),
          Text(widget.label, style: TextStyle(color: _hovered ? _accentL : _sub, fontSize: 11, fontWeight: FontWeight.w500)),
        ]),
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _Card({required this.child, this.padding});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .2), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: child,
  );
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  const _DarkTextField({required this.controller, required this.hint, required this.icon, this.focusNode, this.onSubmitted});

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
    child: Row(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Icon(icon, size: 14, color: _sub)),
      Expanded(child: TextField(
        controller: controller,
        focusNode: focusNode,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: _text, fontSize: 12.5),
        cursorColor: _accentL,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _sub, fontSize: 12),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.only(right: 10),
          isDense: true,
        ),
      )),
    ]),
  );
}

class _AccentButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _AccentButton({required this.icon, required this.label, required this.onPressed});
  @override
  State<_AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<_AccentButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: enabled ? (_hovered ? _accentL : _accent) : _sub.withValues(alpha: .3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 14, color: Colors.white.withValues(alpha: enabled ? 1 : .4)),
            const SizedBox(width: 6),
            Text(widget.label,
              style: TextStyle(color: Colors.white.withValues(alpha: enabled ? 1 : .4), fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
