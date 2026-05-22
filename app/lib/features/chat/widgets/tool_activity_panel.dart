import 'package:flutter/material.dart';

import '../../../core/chat/tool_activity_log.dart';
import '../../../core/theme/app_colors.dart';

/// 展示 Hermes 工具执行步骤（terminal / web_search 等）。
class ToolActivityPanel extends StatelessWidget {
  const ToolActivityPanel({
    required this.entries,
    this.currentProgress,
    super.key,
  });

  final List<ToolActivityEntry> entries;
  final String? currentProgress;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty && (currentProgress == null || currentProgress!.isEmpty)) {
      return const SizedBox.shrink();
    }

    final bodyStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.gray,
          height: 1.4,
          fontFamily: 'monospace',
          fontSize: 12,
        );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.grayLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.grayLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '执行过程',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.gray,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          if (entries.isNotEmpty)
            ...entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(e.displayLine, style: bodyStyle),
              ),
            ),
          if (currentProgress != null && currentProgress!.isNotEmpty)
            Text('▶ $currentProgress', style: bodyStyle),
        ],
      ),
    );
  }
}
