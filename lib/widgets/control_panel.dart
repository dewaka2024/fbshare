import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/automation_provider.dart';
import '../providers/theme_provider.dart';

class ControlPanel extends StatefulWidget {
  final VoidCallback onNavigate;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final VoidCallback onHome;
  final VoidCallback onWatch;
  final VoidCallback onStopWatch;

  const ControlPanel({
    super.key,
    required this.onNavigate,
    required this.onStart,
    required this.onStop,
    required this.onReset,
    required this.onHome,
    required this.onWatch,
    required this.onStopWatch,
  });

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    // postUrl may be empty here if SharedPreferences haven't loaded yet —
    // didChangeDependencies handles the async-loaded value below.
    _urlCtrl = TextEditingController(text: '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // FIX: keep _urlCtrl in sync when prefs load asynchronously after build.
    final url = context.read<AutomationProvider>().postUrl;
    if (_urlCtrl.text != url) {
      _urlCtrl.value = _urlCtrl.value.copyWith(
        text: url,
        selection: TextSelection.collapsed(offset: url.length),
      );
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auto = context.watch<AutomationProvider>();
    final surfaceColor =
        isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final cardColor = isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;
    final subColor = isDark ? AppColors.darkSubText : AppColors.lightSubText;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      color: surfaceColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel('Post URL', color: subColor),
            const SizedBox(height: 8),
            TextField(
              controller: _urlCtrl,
              onChanged: auto.setPostUrl,
              style: TextStyle(fontSize: 13, color: textColor),
              decoration: const InputDecoration(
                hintText: 'https://www.facebook.com/...',
                prefixIcon: Icon(Icons.link_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _OutlineButton(
                    icon: Icons.open_in_browser_rounded,
                    label: 'Go to Post',
                    onTap: widget.onNavigate,
                    enabled: auto.postUrl.isNotEmpty && !auto.isRunning,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                _OutlineButton(
                  icon: Icons.home_rounded,
                  label: 'FB Home',
                  onTap: widget.onHome,
                  enabled: !auto.isRunning,
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(color: borderColor, height: 1),
            const SizedBox(height: 24),

            _SectionLabel('Click Delay', color: subColor),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${auto.clickDelayMs} ms',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                const Spacer(),
                Text(
                  'between group clicks',
                  style: TextStyle(fontSize: 11, color: subColor),
                ),
              ],
            ),
            Slider(
              value: auto.clickDelayMs.toDouble(),
              // FIX: min now matches kMinDelayMs so UI and JS are in sync
              min: AutomationProvider.kMinDelayMs.toDouble(),
              max: AutomationProvider.kMaxDelayMs.toDouble(),
              divisions: 24,
              activeColor: AppColors.accent,
              onChanged: (v) => auto.setClickDelay(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${AutomationProvider.kMinDelayMs}ms',
                    style: TextStyle(fontSize: 10, color: subColor)),
                Text('${AutomationProvider.kMaxDelayMs}ms',
                    style: TextStyle(fontSize: 10, color: subColor)),
              ],
            ),
            const SizedBox(height: 20),

            _SectionLabel('Groups Per Run', color: subColor),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${auto.groupsPerRun}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                const Spacer(),
                Text(
                  'groups per automation run',
                  style: TextStyle(fontSize: 11, color: subColor),
                ),
              ],
            ),
            Slider(
              value: auto.groupsPerRun.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              activeColor: AppColors.accent,
              onChanged: (v) => auto.setGroupsPerRun(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('1', style: TextStyle(fontSize: 10, color: subColor)),
                Text('50', style: TextStyle(fontSize: 10, color: subColor)),
              ],
            ),
            const SizedBox(height: 24),
            Divider(color: borderColor, height: 1),
            const SizedBox(height: 24),

            _SectionLabel('Group Index Memory', color: subColor),
            const SizedBox(height: 12),
            _InfoCard(
              color: cardColor,
              border: borderColor,
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '${auto.lastGroupIndex}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next run starts at',
                        style: TextStyle(fontSize: 11, color: subColor),
                      ),
                      Text(
                        'Group #${auto.lastGroupIndex + 1}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Tooltip(
                    message: 'Reset to Group #1',
                    child: IconButton(
                      icon: const Icon(Icons.restart_alt_rounded, size: 20),
                      color: AppColors.warning,
                      onPressed: auto.isRunning ? null : widget.onReset,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Divider(color: borderColor, height: 1),
            const SizedBox(height: 24),

            _AutomationStatusCard(isDark: isDark),
            const SizedBox(height: 24),

            // ── Start / Stop button ──────────────────────────────────────
            if (auto.isRunning)
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: widget.onStop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.stop_rounded, size: 22),
                  label: Text(
                    auto.status == AutomationStatus.navigating
                        ? 'Cancel'
                        : 'Stop Automation',
                  ),
                ),
              )
            else
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: (!auto.webViewReady || auto.postUrl.isEmpty)
                      ? null
                      : widget.onStart,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Start Automation'),
                ),
              ),

            const SizedBox(height: 10),

            // ── Watch button (MutationObserver auto-trigger) ─────────────
            SizedBox(
              height: 44,
              child: auto.postWatcherActive
                  ? OutlinedButton.icon(
                      onPressed: widget.onStopWatch,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                      icon: const Icon(Icons.visibility_off_rounded, size: 18),
                      label: const Text('Stop Watching'),
                    )
                  : OutlinedButton.icon(
                      onPressed: (!auto.webViewReady ||
                              auto.postUrl.isEmpty ||
                              auto.isRunning)
                          ? null
                          : widget.onWatch,
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: const Text('Watch & Auto-Start'),
                    ),
            ),

            const SizedBox(height: 24),
            Divider(color: borderColor, height: 1),
            const SizedBox(height: 12),

            // ── Step Debug ──────────────────────────────────────────────
            _SectionLabel('Step Debug', color: subColor),
            const SizedBox(height: 8),
            Text(
              'Use these to test each step manually and find correct selectors.',
              style: TextStyle(fontSize: 11, color: subColor, height: 1.4),
            ),
            const SizedBox(height: 10),

            // Step 1: Click Share
            _DebugButton(
              label: '① Click Share Button',
              icon: Icons.ads_click_rounded,
              color: const Color(0xFF4F6EF7),
              onTap: () async {
                final msg =
                    await context.read<AutomationProvider>().stepClickShare();
                if (!context.mounted) return;
                _showResult(context, msg);
              },
            ),
            const SizedBox(height: 8),

            // Step 2: Scan what appeared
            _DebugButton(
              label: '② Scan Dialog/Menu Items',
              icon: Icons.document_scanner_rounded,
              color: const Color(0xFFF59E0B),
              onTap: () async {
                final msg = await context
                    .read<AutomationProvider>()
                    .stepScanAfterClick();
                if (!context.mounted) return;
                _showResult(context, msg);
              },
            ),
            const SizedBox(height: 8),

            // Manual click by text
            _ManualClickField(isDark: isDark, subColor: subColor),
          ],
        ),
      ),
    );
  }

  void _showResult(BuildContext context, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Debug Result', style: TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: SelectableText(
            msg,
            style: const TextStyle(fontSize: 12, fontFamily: 'Courier New'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ─── _DebugButton ──────────────────────────────────────────────────────────────
class _DebugButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _DebugButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16, color: color),
          label: Text(label, style: TextStyle(fontSize: 12, color: color)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      );
}

// ─── _ManualClickField ─────────────────────────────────────────────────────────
class _ManualClickField extends StatefulWidget {
  final bool isDark;
  final Color subColor;
  const _ManualClickField({required this.isDark, required this.subColor});

  @override
  State<_ManualClickField> createState() => _ManualClickFieldState();
}

class _ManualClickFieldState extends State<_ManualClickField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auto = context.read<AutomationProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('③ Click by text/aria-label:',
            style: TextStyle(fontSize: 11, color: widget.subColor)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: TextStyle(
                fontSize: 12,
                color: widget.isDark
                    ? const Color(0xFFE8EAF6)
                    : const Color(0xFF1A1D27),
              ),
              decoration: InputDecoration(
                hintText: 'e.g. Share to a group',
                hintStyle: TextStyle(fontSize: 11, color: widget.subColor),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () async {
              final txt = _ctrl.text.trim();
              if (txt.isEmpty) return;
              final msg = await auto.clickByText(txt);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(msg), duration: const Duration(seconds: 3)));
              }
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Go', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: color,
        ),
      );
}

// ─── _InfoCard ─────────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final Color color;
  final Color border;
  final Widget child;
  const _InfoCard({
    required this.color,
    required this.border,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: child,
      );
}

// ─── _OutlineButton ────────────────────────────────────────────────────────────
class _OutlineButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool isDark;

  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.enabled,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;

    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: textColor,
        side: BorderSide(color: borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// ─── _AutomationStatusCard ─────────────────────────────────────────────────────
class _AutomationStatusCard extends StatelessWidget {
  final bool isDark;
  const _AutomationStatusCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final auto = context.watch<AutomationProvider>();
    final cardColor = isDark ? AppColors.darkCard : AppColors.lightCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textColor = isDark ? AppColors.darkText : AppColors.lightText;

    final Color dotColor;
    switch (auto.status) {
      case AutomationStatus.running:
      case AutomationStatus.navigating:
        dotColor = AppColors.warning;
        break;
      case AutomationStatus.success:
        dotColor = AppColors.success;
        break;
      case AutomationStatus.error:
        dotColor = AppColors.error;
        break;
      default:
        dotColor = isDark ? AppColors.darkSubText : AppColors.lightSubText;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              auto.statusMessage,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
