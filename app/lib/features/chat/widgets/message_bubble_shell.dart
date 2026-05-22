import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'chat_message_context_menu.dart';

/// 为聊天气泡包装长按手势。
class MessageBubbleShell extends StatelessWidget {
  const MessageBubbleShell({
    required this.message,
    required this.isSentByMe,
    required this.canModify,
    required this.onDelete,
    required this.child,
    this.onResend,
    this.onEdit,
    super.key,
  });

  final TextMessage message;
  final bool isSentByMe;
  final bool canModify;
  final Future<void> Function() onDelete;
  final VoidCallback? onResend;
  final VoidCallback? onEdit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox?;
        final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
        final size = box?.size ?? Size.zero;
        final anchor = Offset(
          origin.dx + size.width * (isSentByMe ? 0.72 : 0.28),
          origin.dy + size.height * 0.35,
        );
        showChatMessageContextMenu(
          context,
          anchor: anchor,
          message: message,
          isSentByMe: isSentByMe,
          canModify: canModify,
          onDelete: onDelete,
          onResend: onResend,
          onEdit: onEdit,
        );
      },
      child: child,
    );
  }
}
