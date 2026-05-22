import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import '../../../core/chat/chat_message_metadata.dart';
import '../../../core/theme/app_colors.dart';

/// Hermes 等待回复时的打字动画气泡。
class HermesLoadingBubble extends StatelessWidget {
  const HermesLoadingBubble({
    required this.message,
    required this.index,
    this.toolProgress,
    super.key,
  });

  final TextMessage message;
  final int index;
  final String? toolProgress;

  @override
  Widget build(BuildContext context) {
    final progress = toolProgress ?? extractToolProgressLine(message.text);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.grayLight),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IsTypingIndicator(
                    size: 7,
                    spacing: 4,
                    color: AppColors.gray,
                  ),
                  if (progress != null && progress.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      progress,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray,
                            height: 1.35,
                          ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  TimeAndStatus(
                    time: message.resolvedTime,
                    status: message.resolvedStatus,
                    showStatus: false,
                    textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.gray,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
