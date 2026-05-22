import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/chat/chat_message_metadata.dart';
import '../../../core/chat/file_preview_launcher.dart';
import '../../../core/chat/media_link_utils.dart';
import '../../../core/chat/tool_activity_log.dart';
import '../../../core/device_actions/device_action_model.dart';
import '../../../core/device_actions/device_action_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/app_providers.dart';
import 'approval_action_bar.dart';
import 'chat_markdown_content.dart';
import 'device_action_card.dart';
import 'hermes_loading_bubble.dart';
import 'tool_activity_panel.dart';
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
    this.liveToolProgress,
    this.deviceActions = const [],
    this.onApproveDeviceAction,
    this.onDenyDeviceAction,
    super.key,
  });

  final TextMessage message;
  final int index;
  final bool isSentByMe;
  final bool showApproval;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;
  final VoidCallback? onContentExpanded;
  final String? liveToolProgress;
  final List<DeviceAction> deviceActions;
  final void Function(DeviceAction action)? onApproveDeviceAction;
  final void Function(DeviceAction action)? onDenyDeviceAction;

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
      return HermesLoadingBubble(
        message: message,
        index: index,
        toolProgress: liveToolProgress,
      );
    }

    final toolLog = parseToolLog(message.metadata);
    final parsed = parseAssistantContent(text);
    final displayText = parsed.displayText.startsWith('⏳')
        ? parsed.displayText.split('\n').skip(1).join('\n').trim()
        : parsed.displayText;

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

    final actions = deviceActions.isNotEmpty ? deviceActions : parsed.actions;
    final hasToolPanel = toolLog.isNotEmpty || (liveToolProgress?.isNotEmpty ?? false);
    final hasText = displayText.isNotEmpty;
    final hasApproval = showApproval && onApprove != null && onDeny != null;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.88;

    Widget assistantBubble({required Widget child}) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.grayLight),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: child,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasToolPanel)
                assistantBubble(
                  child: ToolActivityPanel(entries: toolLog, currentProgress: liveToolProgress),
                ),
              for (final action in actions)
                DeviceActionCard(
                  action: action,
                  onApprove: action.status == DeviceActionStatus.pending &&
                          onApproveDeviceAction != null
                      ? () => onApproveDeviceAction!(action)
                      : null,
                  onDeny: action.status == DeviceActionStatus.pending &&
                          onDenyDeviceAction != null
                      ? () => onDenyDeviceAction!(action)
                      : null,
                ),
              if (hasText || hasApproval)
                assistantBubble(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasText)
                        ChatMarkdownContent(
                          text: displayText,
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
                      if (hasApproval) ApprovalActionBar(onApprove: onApprove!, onDeny: onDeny!),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
