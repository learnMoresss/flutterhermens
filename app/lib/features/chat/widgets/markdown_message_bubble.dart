import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/chat/chat_message_metadata.dart';
import '../../../core/chat/file_preview_launcher.dart';
import '../../../core/chat/media_link_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/app_providers.dart';
import 'approval_action_bar.dart';
import 'chat_markdown_content.dart';
import 'hermes_loading_bubble.dart';
import 'user_message_bubble.dart';

/// 助手消息 Markdown 渲染；用户消息保持纯文本。
class MarkdownMessageBubble extends ConsumerWidget {
  const MarkdownMessageBubble({
    required this.message,
    required this.index,
    required this.isSentByMe,
    this.showApproval = false,
    this.onApprove,
    this.onDeny,
    this.onContentExpanded,
    super.key,
  });

  final TextMessage message;
  final int index;
  final bool isSentByMe;
  final bool showApproval;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;
  final VoidCallback? onContentExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isSentByMe) {
      return UserMessageBubble(
        message: message,
        index: index,
        onContentExpanded: onContentExpanded,
      );
    }

    final gatewayBase = ref.watch(appConfigProvider).gatewayUrl;

    final text = message.text;
    if (isHermesLoadingText(text)) {
      return HermesLoadingBubble(message: message, index: index);
    }

    final styleSheet = MarkdownStyleSheet(
      p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        backgroundColor: AppColors.grayLight.withValues(alpha: 0.35),
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.grayLight.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.gray, width: 3)),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.grayLight),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChatMarkdownContent(
                    text: text,
                    gatewayBase: gatewayBase,
                    styleSheet: styleSheet,
                    onContentExpanded: onContentExpanded,
                    onTapLink: (linkText, href, title) async {
                      if (href == null || href.isEmpty) return;
                      if (isGatewayMediaUrl(href, gatewayBase) && isVideoHref(href)) {
                        return;
                      }
                      await openFilePreview(
                        context,
                        href: href,
                        linkText: title.isNotEmpty ? title : linkText,
                        gatewayBaseUrl: gatewayBase,
                      );
                    },
                  ),
                  if (showApproval && onApprove != null && onDeny != null)
                    ApprovalActionBar(onApprove: onApprove!, onDeny: onDeny!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
