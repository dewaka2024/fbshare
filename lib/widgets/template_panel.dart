import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/automation_provider.dart';
import '../providers/template_provider.dart';

// ─── Colour palette (matches home_screen dark theme) ─────────────────────────
const Color _bg = Color(0xFF1A1D2E);
const Color _card = Color(0xFF252840);
const Color _accent = Color(0xFF4F6EF7);
const Color _green = Color(0xFF22C55E);
const Color _red = Color(0xFFEF4444);
const Color _yellow = Color(0xFFFBBF24);
const Color _dimText = Color(0xFF8B91A8);
const Color _white = Color(0xFFE2E8F0);

class TemplatePanel extends StatefulWidget {
  final VoidCallback onClose;
  const TemplatePanel({super.key, required this.onClose});

  @override
  State<TemplatePanel> createState() => _TemplatePanelState();
}

class _TemplatePanelState extends State<TemplatePanel> {
  // Track which template is expanded in the list
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    final tplProvider = context.watch<TemplateProvider>();
    final autoProvider = context.watch<AutomationProvider>();
    final templates = tplProvider.templates;
    final activeId = tplProvider.activeTemplateId;

    return Container(
      width: 320,
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          _PanelHeader(
            onClose: widget.onClose,
            onAdd: () => _showCreateDialog(context, tplProvider, autoProvider),
          ),

          // ── Active template badge ──────────────────────────────────────────
          if (tplProvider.activeLabel.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: _accent, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tplProvider.activeLabel,
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ]),
            ),

          const SizedBox(height: 8),

          // ── Template list ─────────────────────────────────────────────────
          Expanded(
            child: templates.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: templates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final t = templates[i];
                      final isActive = t.id == activeId;
                      final isExpanded = _expandedId == t.id;
                      return _TemplateCard(
                        template: t,
                        isActive: isActive,
                        isExpanded: isExpanded,
                        onActivate: () {
                          context
                              .read<TemplateProvider>()
                              .setActiveTemplate(t.id);
                          // Apply template settings to AutomationProvider
                          _applyTemplate(context, t);
                        },
                        onExpand: () => setState(
                          () => _expandedId = isExpanded ? null : t.id,
                        ),
                        onEdit: () => _showEditDialog(context, tplProvider, t),
                        onDuplicate: () =>
                            _showDuplicateDialog(context, tplProvider, t.id),
                        onDelete: t.id.startsWith('default')
                            ? null
                            : () => _confirmDelete(context, tplProvider, t),
                        onCaptureStep: (stepIdx) => _captureStep(
                            context, tplProvider, autoProvider, t.id, stepIdx),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Apply template settings to AutomationProvider ─────────────────────────
  void _applyTemplate(BuildContext ctx, AutomationTemplate t) {
    final auto = ctx.read<AutomationProvider>();
    if (t.postUrl.isNotEmpty) auto.setPostUrl(t.postUrl);
    auto.setClickDelay(t.clickDelayMs);
    auto.setGroupsPerRun(t.groupsPerRun);
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text('Template "${t.name}" loaded'),
        duration: const Duration(seconds: 2),
        backgroundColor: _accent,
      ),
    );
  }

  // ── Capture current Inspector element into a step ─────────────────────────
  void _captureStep(
    BuildContext ctx,
    TemplateProvider tpl,
    AutomationProvider auto,
    String templateId,
    int stepIndex,
  ) async {
    final scanned = auto.scannedElements;
    if (scanned.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('No scanned elements. Open the Inspector first.'),
          backgroundColor: _red,
        ),
      );
      return;
    }
    // Show element picker
    if (!ctx.mounted) return;
    final chosen = await showDialog<PageElement>(
      context: ctx,
      builder: (_) => _ElementPickerDialog(elements: scanned),
    );
    if (chosen == null) return;

    final attrs = <CapturedAttribute>[
      if (chosen.ariaLabel.isNotEmpty)
        CapturedAttribute(key: 'aria-label', value: chosen.ariaLabel),
      if (chosen.role.isNotEmpty)
        CapturedAttribute(key: 'role', value: chosen.role),
      if (chosen.testId.isNotEmpty)
        CapturedAttribute(key: 'data-testid', value: chosen.testId),
      if (chosen.tag.isNotEmpty)
        CapturedAttribute(key: 'tag', value: chosen.tag),
    ];

    await tpl.updateStepAttributes(
      templateId,
      stepIndex,
      attrs,
      fallbackText: chosen.text.isNotEmpty ? chosen.text : null,
    );

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Step attributes captured ✅'),
          backgroundColor: _green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showCreateDialog(
    BuildContext ctx,
    TemplateProvider tpl,
    AutomationProvider auto,
  ) {
    showDialog(
      context: ctx,
      builder: (_) => _TemplateFormDialog(
        title: 'New Template',
        initialName: '',
        initialDescription: '',
        initialUrl: auto.postUrl,
        initialDelay: auto.clickDelayMs,
        initialGroups: auto.groupsPerRun,
        onSave: (name, desc, url, delay, groups) async {
          final t = AutomationTemplate(
            id: generateId(),
            name: name,
            description: desc,
            postUrl: url,
            clickDelayMs: delay,
            groupsPerRun: groups,
            steps: [
              const TemplateStep(
                label: 'Click Share button',
                attributes: [
                  CapturedAttribute(
                    key: 'aria-label',
                    value: 'Send this to friends or post it on your profile.',
                  ),
                ],
              ),
              const TemplateStep(
                label: 'Click Group option',
                attributes: [
                  CapturedAttribute(key: 'role', value: 'button'),
                ],
                fallbackText: 'Group',
              ),
            ],
          );
          await tpl.addTemplate(t);
          await tpl.setActiveTemplate(t.id);
          if (ctx.mounted) _applyTemplate(ctx, t);
        },
      ),
    );
  }

  void _showEditDialog(
    BuildContext ctx,
    TemplateProvider tpl,
    AutomationTemplate t,
  ) {
    showDialog(
      context: ctx,
      builder: (_) => _TemplateFormDialog(
        title: 'Edit Template',
        initialName: t.name,
        initialDescription: t.description,
        initialUrl: t.postUrl,
        initialDelay: t.clickDelayMs,
        initialGroups: t.groupsPerRun,
        onSave: (name, desc, url, delay, groups) async {
          await tpl.updateTemplate(t.copyWith(
            name: name,
            description: desc,
            postUrl: url,
            clickDelayMs: delay,
            groupsPerRun: groups,
          ));
        },
      ),
    );
  }

  void _showDuplicateDialog(
    BuildContext ctx,
    TemplateProvider tpl,
    String id,
  ) {
    final ctrl = TextEditingController(text: 'Copy of ...');
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Duplicate Template',
            style: TextStyle(color: _white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: _white),
          decoration: _inputDeco('New name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _dimText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                await tpl.duplicateTemplate(id, ctrl.text.trim());
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext ctx,
    TemplateProvider tpl,
    AutomationTemplate t,
  ) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Delete Template',
            style: TextStyle(color: _white, fontSize: 15)),
        content: Text(
          'Delete "${t.name}"? This cannot be undone.',
          style: const TextStyle(color: _dimText, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _dimText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () async {
              await tpl.deleteTemplate(t.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─── Panel Header ─────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onAdd;
  const _PanelHeader({required this.onClose, required this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: const BoxDecoration(
          color: _card,
          border: Border(bottom: BorderSide(color: Color(0xFF353859))),
        ),
        child: Row(children: [
          const Icon(Icons.layers_rounded, color: _accent, size: 16),
          const SizedBox(width: 8),
          const Text('Templates',
              style: TextStyle(
                  color: _white, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Tooltip(
            message: 'New template',
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.add_rounded, color: _accent, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, color: _dimText, size: 16),
            ),
          ),
        ]),
      );
}

// ─── Template Card ────────────────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  final AutomationTemplate template;
  final bool isActive;
  final bool isExpanded;
  final VoidCallback onActivate;
  final VoidCallback onExpand;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;
  final void Function(int stepIndex) onCaptureStep;

  const _TemplateCard({
    required this.template,
    required this.isActive,
    required this.isExpanded,
    required this.onActivate,
    required this.onExpand,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onCaptureStep,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isActive ? _accent : const Color(0xFF353859);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: isActive ? 1.5 : 1),
        boxShadow: isActive
            ? [BoxShadow(color: _accent.withValues(alpha: 0.15), blurRadius: 8)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header row ──────────────────────────────────────────────
          InkWell(
            onTap: onExpand,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(children: [
                // Active indicator dot
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? _green : const Color(0xFF444866),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: TextStyle(
                          color: isActive ? _white : const Color(0xFFB0B7D0),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (template.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            template.description,
                            style: const TextStyle(
                                color: _dimText, fontSize: 10.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                // Config chips
                _Chip('${template.groupsPerRun}g', _accent),
                const SizedBox(width: 4),
                _Chip('${(template.clickDelayMs / 1000).toStringAsFixed(1)}s',
                    _yellow),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: _dimText,
                  size: 16,
                ),
              ]),
            ),
          ),

          // ── Expanded detail ──────────────────────────────────────────────
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Color(0xFF353859), height: 16),

                  // URL
                  if (template.postUrl.isNotEmpty) ...[
                    _DetailRow(
                      icon: Icons.link_rounded,
                      label: 'URL',
                      value: template.postUrl,
                      copyable: true,
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Steps
                  const Text('Steps',
                      style: TextStyle(
                          color: _dimText,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  ...template.steps.asMap().entries.map((e) => _StepRow(
                        index: e.key,
                        step: e.value,
                        onCapture: () => onCaptureStep(e.key),
                      )),

                  const SizedBox(height: 10),

                  // Action buttons
                  Row(children: [
                    if (!isActive)
                      _ActionBtn(
                        label: 'Activate',
                        icon: Icons.play_arrow_rounded,
                        color: _green,
                        onTap: onActivate,
                      ),
                    if (isActive) const _ActiveBadge(),
                    const Spacer(),
                    _ActionBtn(
                      label: 'Edit',
                      icon: Icons.edit_rounded,
                      color: _accent,
                      onTap: onEdit,
                    ),
                    const SizedBox(width: 6),
                    _ActionBtn(
                      label: 'Copy',
                      icon: Icons.copy_all_rounded,
                      color: _yellow,
                      onTap: onDuplicate,
                    ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 6),
                      _ActionBtn(
                        label: 'Del',
                        icon: Icons.delete_outline_rounded,
                        color: _red,
                        onTap: onDelete!,
                      ),
                    ],
                  ]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Step Row ─────────────────────────────────────────────────────────────────

class _StepRow extends StatelessWidget {
  final int index;
  final TemplateStep step;
  final VoidCallback onCapture;

  const _StepRow({
    required this.index,
    required this.step,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) {
    final hasAria = step.attributes.any((a) => a.key == 'aria-label');
    final captureColor = hasAria ? _green : _yellow;

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: hasAria
              ? _green.withValues(alpha: 0.25)
              : _yellow.withValues(alpha: 0.25),
        ),
      ),
      child: Row(children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                  color: _accent, fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.label,
                  style: const TextStyle(color: _white, fontSize: 11)),
              if (step.attributes.isNotEmpty)
                Text(
                  step.attributes
                      .map((a) => '${a.key}: "${a.value}"')
                      .join(' · '),
                  style: const TextStyle(color: _dimText, fontSize: 9.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        Tooltip(
          message: hasAria ? 'Re-capture attributes' : 'Capture from Inspector',
          child: InkWell(
            onTap: onCapture,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                hasAria ? Icons.refresh_rounded : Icons.colorize_rounded,
                color: captureColor,
                size: 14,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 9, fontWeight: FontWeight.w600)),
      );
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _green.withValues(alpha: 0.4)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_rounded, color: _green, size: 11),
          SizedBox(width: 4),
          Text('Active',
              style: TextStyle(
                  color: _green, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 11),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool copyable;
  const _DetailRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.copyable = false});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: _dimText, size: 12),
        const SizedBox(width: 5),
        Text('$label: ', style: const TextStyle(color: _dimText, fontSize: 10)),
        Expanded(
            child: Text(
          value,
          style: const TextStyle(color: _white, fontSize: 10),
          overflow: TextOverflow.ellipsis,
        )),
        if (copyable)
          InkWell(
            onTap: () => Clipboard.setData(ClipboardData(text: value)),
            child: const Icon(Icons.copy_rounded, color: _dimText, size: 11),
          ),
      ]);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.layers_clear_rounded, color: _dimText, size: 36),
          SizedBox(height: 10),
          Text('No templates yet',
              style: TextStyle(color: _dimText, fontSize: 13)),
          SizedBox(height: 4),
          Text('Tap + to create one',
              style: TextStyle(color: Color(0xFF555870), fontSize: 11)),
        ]),
      );
}

// ─── Template Form Dialog ─────────────────────────────────────────────────────

class _TemplateFormDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String initialDescription;
  final String initialUrl;
  final int initialDelay;
  final int initialGroups;
  final Future<void> Function(
      String name, String desc, String url, int delay, int groups) onSave;

  const _TemplateFormDialog({
    required this.title,
    required this.initialName,
    required this.initialDescription,
    required this.initialUrl,
    required this.initialDelay,
    required this.initialGroups,
    required this.onSave,
  });

  @override
  State<_TemplateFormDialog> createState() => _TemplateFormDialogState();
}

class _TemplateFormDialogState extends State<_TemplateFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _url;
  late int _delay;
  late int _groups;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _desc = TextEditingController(text: widget.initialDescription);
    _url = TextEditingController(text: widget.initialUrl);
    _delay = widget.initialDelay;
    _groups = widget.initialGroups;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: _card,
        title: Text(widget.title,
            style: const TextStyle(
                color: _white, fontSize: 15, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FormField(
                    label: 'Name *',
                    child: TextField(
                      controller: _name,
                      autofocus: true,
                      style: const TextStyle(color: _white, fontSize: 13),
                      decoration: _inputDeco('e.g. Business Page Share'),
                    )),
                const SizedBox(height: 10),
                _FormField(
                    label: 'Description',
                    child: TextField(
                      controller: _desc,
                      style: const TextStyle(color: _white, fontSize: 13),
                      decoration: _inputDeco('Optional notes'),
                    )),
                const SizedBox(height: 10),
                _FormField(
                    label: 'Post URL',
                    child: TextField(
                      controller: _url,
                      style: const TextStyle(color: _white, fontSize: 12),
                      decoration: _inputDeco('https://facebook.com/...'),
                    )),
                const SizedBox(height: 14),
                _FormField(
                  label: 'Click Delay: ${_delay}ms',
                  child: Slider(
                    value: _delay.toDouble(),
                    min: 600,
                    max: 3000,
                    divisions: 24,
                    activeColor: _accent,
                    inactiveColor: const Color(0xFF353859),
                    onChanged: (v) => setState(() => _delay = v.round()),
                  ),
                ),
                _FormField(
                  label: 'Groups per run: $_groups',
                  child: Slider(
                    value: _groups.toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    activeColor: _accent,
                    inactiveColor: const Color(0xFF353859),
                    onChanged: (v) => setState(() => _groups = v.round()),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _dimText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: _saving || _name.text.trim().isEmpty
                ? null
                : () async {
                    setState(() => _saving = true);
                    // Capture navigator before the async gap (use_build_context_synchronously)
                    final nav = Navigator.of(context);
                    await widget.onSave(
                      _name.text.trim(),
                      _desc.text.trim(),
                      _url.text.trim(),
                      _delay,
                      _groups,
                    );
                    if (mounted) nav.pop();
                  },
            child: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save'),
          ),
        ],
      );
}

class _FormField extends StatelessWidget {
  final String label;
  final Widget child;
  const _FormField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: _dimText,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4)),
          const SizedBox(height: 4),
          child,
        ],
      );
}

// ─── Element Picker Dialog ────────────────────────────────────────────────────

class _ElementPickerDialog extends StatefulWidget {
  final List<PageElement> elements;
  const _ElementPickerDialog({required this.elements});

  @override
  State<_ElementPickerDialog> createState() => _ElementPickerDialogState();
}

class _ElementPickerDialogState extends State<_ElementPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.elements.where((e) {
      final q = _query.toLowerCase();
      return e.ariaLabel.toLowerCase().contains(q) ||
          e.text.toLowerCase().contains(q) ||
          e.role.toLowerCase().contains(q);
    }).toList();

    return AlertDialog(
      backgroundColor: _card,
      title: const Text('Pick Element to Capture',
          style: TextStyle(color: _white, fontSize: 14)),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              style: const TextStyle(color: _white, fontSize: 12),
              decoration: _inputDeco('Filter by aria-label, text, role…'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Color(0xFF353859), height: 1),
                itemBuilder: (_, i) {
                  final e = filtered[i];
                  return InkWell(
                    onTap: () => Navigator.pop(context, e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(e.role.isNotEmpty ? e.role : e.tag,
                              style:
                                  const TextStyle(color: _accent, fontSize: 9)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (e.ariaLabel.isNotEmpty)
                                Text(e.ariaLabel,
                                    style: const TextStyle(
                                        color: _green, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              if (e.text.isNotEmpty)
                                Text(e.text,
                                    style: const TextStyle(
                                        color: _white, fontSize: 10.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: _dimText)),
        ),
      ],
    );
  }
}

// ─── Shared input decoration ──────────────────────────────────────────────────

InputDecoration _inputDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _dimText, fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF1A1D2E),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFF353859)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFF353859)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: _accent),
      ),
    );
