import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/automation_provider.dart';
import '../providers/theme_provider.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auto = context.watch<AutomationProvider>();
    final theme = Theme.of(context);

    final bg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final sub = isDark ? AppColors.darkSubText : AppColors.lightSubText;

    final isActive = auto.status == AutomationStatus.running ||
        auto.status == AutomationStatus.navigating;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Running indicator
          if (isActive) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Status text
          Expanded(
            child: Text(
              auto.statusMessage,
              style: TextStyle(fontSize: 11, color: sub),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // History summary
          if (auto.history.isNotEmpty)
            Text(
              '${auto.history.length} run${auto.history.length == 1 ? '' : 's'} • '
              'Next group: #${auto.lastGroupIndex + 1}',
              style: TextStyle(fontSize: 11, color: sub),
            ),

          const SizedBox(width: 16),

          // Delay indicator
          Text(
            '⏱ ${auto.clickDelayMs}ms delay',
            style: TextStyle(fontSize: 11, color: sub),
          ),
        ],
      ),
    );
  }
}
