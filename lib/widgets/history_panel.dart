import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/automation_provider.dart';
import '../providers/theme_provider.dart';

class HistoryPanel extends StatelessWidget {
  final VoidCallback onClose;
  const HistoryPanel({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auto = context.watch<AutomationProvider>();
    final theme = Theme.of(context);

    final bg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final card = isDark ? AppColors.darkCard : AppColors.lightCard;
    final sub = isDark ? AppColors.darkSubText : AppColors.lightSubText;
    final text = isDark ? AppColors.darkText : AppColors.lightText;

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: bg,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Text('Run History',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: text)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: auto.history.isEmpty
                ? Center(
                    child: Text('No runs yet',
                        style: TextStyle(fontSize: 13, color: sub)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: auto.history.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = auto.history[i];
                      return _HistoryCard(
                        result: r,
                        card: card,
                        text: text,
                        sub: sub,
                        border: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatefulWidget {
  final ShareResult result;
  final Color card, text, sub, border;
  const _HistoryCard(
      {required this.result,
      required this.card,
      required this.text,
      required this.sub,
      required this.border});

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final accent = r.success ? AppColors.success : AppColors.error;
    final t = r.timestamp;
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: widget.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.success
                              ? '${r.clickedGroups.length} groups shared'
                              : 'Failed: ${r.error ?? r.step ?? 'unknown error'}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: widget.text),
                        ),
                        Text(
                          timeStr,
                          style:
                              TextStyle(fontSize: 10, color: widget.sub),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: widget.sub,
                  ),
                ],
              ),
            ),
          ),

          // Expanded detail
          if (_expanded) ...[
            Divider(height: 1, color: widget.border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.message != null)
                    _Row('Result', r.message!, widget.text, widget.sub),
                  if (r.error != null)
                    _Row('Error', r.error!, AppColors.error, widget.sub),
                  if (r.hint != null)
                    _Row('Hint', r.hint!, AppColors.warning, widget.sub),
                  _Row('Total groups', '${r.totalGroupsFound}',
                      widget.text, widget.sub),
                  _Row('Next index', '${r.nextRunStartIndex}',
                      widget.text, widget.sub),

                  if (r.clickedGroups.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Shared to:',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: widget.sub)),
                    const SizedBox(height: 4),
                    ...r.clickedGroups.map((g) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '• ${g['name']}',
                            style: TextStyle(
                                fontSize: 11, color: widget.text),
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final Color valueColor, labelColor;
  const _Row(this.label, this.value, this.valueColor, this.labelColor);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: TextStyle(fontSize: 10, color: labelColor)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 11,
                      color: valueColor,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}
