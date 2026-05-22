import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../../core/chat/chat_message_metadata.dart';
import '../../../core/chat/chat_shortcuts.dart';
import '../../../core/device_actions/device_action_parser.dart';
import '../../../core/ui/app_message.dart';

class _MenuItem {
  const _MenuItem({required this.key, required this.label, this.destructive = false});

  final String key;
  final String label;
  final bool destructive;
}

/// 聊天气泡长按菜单：仿微信深色横条浮层。
Future<void> showChatMessageContextMenu(
  BuildContext context, {
  required TextMessage message,
  required bool isSentByMe,
  required bool canModify,
  required Offset anchor,
  required Future<void> Function() onDelete,
  VoidCallback? onResend,
  VoidCallback? onEdit,
}) async {
  if (!canModify && isUiOnlyAssistantText(message.text)) return;

  final items = <_MenuItem>[
    const _MenuItem(key: 'copy', label: '复制'),
    if (isSentByMe && onResend != null) const _MenuItem(key: 'resend', label: '重新发送'),
    if (isSentByMe && onEdit != null) const _MenuItem(key: 'edit', label: '编辑'),
    if (canModify) const _MenuItem(key: 'delete', label: '删除', destructive: true),
  ];
  if (items.isEmpty) return;

  HapticFeedback.mediumImpact();

  final action = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭菜单',
    barrierColor: Colors.black.withValues(alpha: 0.08),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return _WeChatContextMenuOverlay(
        anchor: anchor,
        items: items,
        animation: animation,
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );

  if (!context.mounted || action == null) return;

  switch (action) {
    case 'copy':
      final text = _copyText(message, isSentByMe);
      if (text.isEmpty) {
        AppMessage.info('没有可复制的内容');
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) AppMessage.success('已复制');
    case 'resend':
      onResend?.call();
    case 'edit':
      onEdit?.call();
    case 'delete':
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除消息'),
          content: const Text('确定从当前对话中删除这条消息？（仅本机 UI，不影响服务端历史）'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Color(0xFFB00020))),
            ),
          ],
        ),
      );
      if (ok == true) await onDelete();
  }
}

class _WeChatContextMenuOverlay extends StatelessWidget {
  const _WeChatContextMenuOverlay({
    required this.anchor,
    required this.items,
    required this.animation,
  });

  final Offset anchor;
  final List<_MenuItem> items;
  final Animation<double> animation;

  static const _menuBg = Color(0xFF4C4C4C);
  static const _destructiveColor = Color(0xFFFF6B6B);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top + 8;
    const horizontalPadding = 12.0;
    const arrowSize = 6.0;
    const gap = 8.0;
    const menuHeight = 40.0;

    final menuWidth = (items.length * 58.0).clamp(120.0, screen.width - horizontalPadding * 2);
    final left = (anchor.dx - menuWidth / 2).clamp(
      horizontalPadding,
      screen.width - menuWidth - horizontalPadding,
    );
    final arrowOffset = (anchor.dx - left - 6).clamp(12.0, menuWidth - 24.0);

    var showBelow = false;
    var top = anchor.dy - menuHeight - arrowSize - gap;
    if (top < topInset) {
      showBelow = true;
      top = anchor.dy + gap;
    }

    final menuBar = DecoratedBox(
      decoration: BoxDecoration(
        color: _menuBg,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Container(
                  width: 0.5,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              Expanded(
                child: _MenuButton(
                  label: items[i].label,
                  destructive: items[i].destructive,
                  onTap: () => Navigator.pop(context, items[i].key),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final arrow = Padding(
      padding: EdgeInsets.only(left: arrowOffset),
      child: CustomPaint(
        size: const Size(12, 6),
        painter: _BubbleArrowPainter(color: _menuBg, pointDown: showBelow),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              alignment: showBelow ? Alignment.topCenter : Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: showBelow ? [arrow, menuBar] : [menuBar, arrow],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: destructive ? _WeChatContextMenuOverlay._destructiveColor : Colors.white,
              fontSize: 14,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _BubbleArrowPainter extends CustomPainter {
  _BubbleArrowPainter({required this.color, required this.pointDown});

  final Color color;
  final bool pointDown;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (pointDown) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    } else {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BubbleArrowPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointDown != pointDown;
  }
}

String _copyText(TextMessage message, bool isSentByMe) {
  var text = message.text.trim();
  if (text == kHermesLoadingText || text == '…') return '';
  if (isSentByMe) return text;
  if (isUiOnlyAssistantText(text)) return text;
  return stripDeviceActionBlocks(text);
}
