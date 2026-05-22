import 'package:flutter/material.dart';

import 'device_action_model.dart';

class DeviceActionTypeInfo {
  const DeviceActionTypeInfo({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}

DeviceActionTypeInfo deviceActionTypeInfo(DeviceActionType type) {
  return switch (type) {
    DeviceActionType.notificationSchedule => const DeviceActionTypeInfo(
        label: '本地提醒',
        icon: Icons.notifications_outlined,
      ),
    DeviceActionType.calendarEvent => const DeviceActionTypeInfo(
        label: '日历事件',
        icon: Icons.event_outlined,
      ),
    DeviceActionType.calendarPrefill => const DeviceActionTypeInfo(
        label: '预填日历',
        icon: Icons.edit_calendar_outlined,
      ),
    DeviceActionType.shareText => const DeviceActionTypeInfo(
        label: '分享',
        icon: Icons.share_outlined,
      ),
    DeviceActionType.clipboardWrite => const DeviceActionTypeInfo(
        label: '复制',
        icon: Icons.content_copy_outlined,
      ),
    DeviceActionType.settingsOpen => const DeviceActionTypeInfo(
        label: '打开设置',
        icon: Icons.settings_outlined,
      ),
    DeviceActionType.unknown => const DeviceActionTypeInfo(
        label: '未知操作',
        icon: Icons.help_outline,
      ),
  };
}

String formatActionParamsPreview(DeviceAction action) {
  final p = action.params;
  return switch (action.type) {
    DeviceActionType.notificationSchedule =>
      '${p['title'] ?? ''} · ${p['scheduledAt'] ?? ''}',
    DeviceActionType.calendarEvent || DeviceActionType.calendarPrefill =>
      '${p['title'] ?? ''}\n${p['startAt'] ?? ''} → ${p['endAt'] ?? ''}',
    DeviceActionType.shareText => (p['text'] ?? '').toString(),
    DeviceActionType.clipboardWrite => (p['text'] ?? '').toString(),
    DeviceActionType.settingsOpen => (p['target'] ?? 'app').toString(),
    DeviceActionType.unknown => '',
  };
}
