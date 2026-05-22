import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

import '../../../core/chat/chat_message_metadata.dart';
import '../../../core/theme/app_colors.dart';
import 'chat_image_tile.dart';

/// 用户消息：文本 + 图片/文件附件。
class UserMessageBubble extends StatelessWidget {
  const UserMessageBubble({
    required this.message,
    required this.index,
    this.onContentExpanded,
    super.key,
  });

  final TextMessage message;
  final int index;
  final VoidCallback? onContentExpanded;

  @override
  Widget build(BuildContext context) {
    final images = parseChatImages(message.metadata);
    final file = parseChatFile(message.metadata);
    final text = message.text.trim();

    if (images.isEmpty && file == null && text.isNotEmpty) {
      return SimpleTextMessage(message: message, index: index);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.black,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (images.isNotEmpty) _ImageStrip(images: images, onLoaded: onContentExpanded),
                  if (file != null) _FileChip(file: file),
                  if (text.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: images.isNotEmpty || file != null ? 8 : 0),
                      child: Text(
                        message.text,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.white,
                              height: 1.45,
                            ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TimeAndStatus(
                      time: message.resolvedTime,
                      status: message.resolvedStatus,
                      textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.white.withValues(alpha: 0.75),
                            fontSize: 11,
                          ),
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

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.images, this.onLoaded});

  final List<ChatImageAttachment> images;
  final VoidCallback? onLoaded;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        for (final image in images)
          ChatImageTile(
            image: image,
            onLoaded: onLoaded,
          ),
      ],
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.file});

  final ChatFileAttachment file;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 18, color: AppColors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
