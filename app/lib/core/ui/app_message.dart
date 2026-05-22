import 'dart:async';

import 'package:flutter/material.dart';

/// 仿 Ant Design Message：顶部居中、多状态、自动消失。
enum AppMessageType {
  success,
  error,
  warning,
  info,
}

class AppMessageEntry {
  AppMessageEntry({
    required this.id,
    required this.message,
    required this.type,
  });

  final int id;
  final String message;
  final AppMessageType type;
}

/// 全局消息队列（无需 BuildContext）。
final AppMessageNotifier appMessageNotifier = AppMessageNotifier();

class AppMessageNotifier extends ChangeNotifier {
  final List<AppMessageEntry> items = [];
  var _seq = 0;
  final Map<int, Timer> _timers = {};

  void show(String message, AppMessageType type, {Duration? duration}) {
    final id = ++_seq;
    items.add(AppMessageEntry(id: id, message: message, type: type));
    notifyListeners();
    _timers[id]?.cancel();
    _timers[id] = Timer(duration ?? _defaultDuration(type), () => dismiss(id));
  }

  void dismiss(int id) {
    _timers.remove(id)?.cancel();
    final before = items.length;
    items.removeWhere((e) => e.id == id);
    if (items.length != before) notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

Duration _defaultDuration(AppMessageType type) {
  return switch (type) {
    AppMessageType.error => const Duration(seconds: 4),
    AppMessageType.warning => const Duration(seconds: 4),
    _ => const Duration(seconds: 3),
  };
}

/// 顶部消息 API（全应用统一使用，替代 SnackBar）。
abstract final class AppMessage {
  static void success(String message) => _show(message, AppMessageType.success);

  static void error(String message) => _show(message, AppMessageType.error);

  static void warning(String message) => _show(message, AppMessageType.warning);

  static void info(String message) => _show(message, AppMessageType.info);

  static void _show(String message, AppMessageType type) {
    final text = message.trim();
    if (text.isEmpty) return;
    appMessageNotifier.show(text, type);
  }
}

/// 放在 [MaterialApp.builder] 内，渲染顶部消息条（须在 Directionality 之下）。
class AppMessageHost extends StatelessWidget {
  const AppMessageHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.topCenter,
      children: [
        child,
        ListenableBuilder(
          listenable: appMessageNotifier,
          builder: (context, _) {
            final items = appMessageNotifier.items;
            if (items.isEmpty) return const SizedBox.shrink();
            final top = MediaQuery.paddingOf(context).top + 12;
            return Positioned(
              top: top,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in items) ...[
                        _AppMessageBanner(item: item),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AppMessageBanner extends StatelessWidget {
  const _AppMessageBanner({required this.item});

  final AppMessageEntry item;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(item.type);
    final maxW = MediaQuery.sizeOf(context).width * 0.88;

    return Material(
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(2),
      color: style.background,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW.clamp(280, 520)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: style.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, color: style.iconColor, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                item.message,
                style: TextStyle(
                  color: style.text,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _MessageStyle _styleFor(AppMessageType type) {
    return switch (type) {
      AppMessageType.success => const _MessageStyle(
          icon: Icons.check_circle_outline,
          iconColor: Color(0xFF52C41A),
          background: Color(0xFFF6FFED),
          border: Color(0xFFB7EB8F),
          text: Color(0xFF135200),
        ),
      AppMessageType.error => const _MessageStyle(
          icon: Icons.cancel_outlined,
          iconColor: Color(0xFFFF4D4F),
          background: Color(0xFFFFF2F0),
          border: Color(0xFFFFCCC7),
          text: Color(0xFF820014),
        ),
      AppMessageType.warning => const _MessageStyle(
          icon: Icons.warning_amber_rounded,
          iconColor: Color(0xFFFAAD14),
          background: Color(0xFFFFFBE6),
          border: Color(0xFFFFE58F),
          text: Color(0xFF613400),
        ),
      AppMessageType.info => const _MessageStyle(
          icon: Icons.info_outline,
          iconColor: Color(0xFF1677FF),
          background: Color(0xFFE6F4FF),
          border: Color(0xFF91CAFF),
          text: Color(0xFF003EB3),
        ),
    };
  }
}

class _MessageStyle {
  const _MessageStyle({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.border,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final Color background;
  final Color border;
  final Color text;
}
