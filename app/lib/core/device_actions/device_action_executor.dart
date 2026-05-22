import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_calendar/native_calendar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../ui/app_message.dart';
import 'device_action_model.dart';
import 'device_capability_service.dart';

class DeviceActionExecutor {
  DeviceActionExecutor._();

  static final _notifications = FlutterLocalNotificationsPlugin();
  static var _initialized = false;
  static int _notificationIdSeq = 9000;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } on Object {
      tz.setLocalLocation(tz.local);
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _notifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  static Future<DeviceActionResult> execute(DeviceAction action) async {
    await ensureInitialized();
    try {
      return switch (action.type) {
        DeviceActionType.notificationSchedule => await _scheduleNotification(action),
        DeviceActionType.calendarEvent => await _addCalendarEvent(action, prefillOnly: false),
        DeviceActionType.calendarPrefill => await _addCalendarEvent(action, prefillOnly: true),
        DeviceActionType.shareText => await _share(action),
        DeviceActionType.clipboardWrite => await _clipboard(action),
        DeviceActionType.settingsOpen => await _openSettings(action),
        DeviceActionType.unknown => DeviceActionResult.fail('不支持的操作类型'),
      };
    } on Object catch (e) {
      return DeviceActionResult.fail(e.toString());
    }
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  static Future<DeviceActionResult> _scheduleNotification(DeviceAction action) async {
    if (Platform.isAndroid) {
      final notif = await Permission.notification.request();
      if (!notif.isGranted) {
        return DeviceActionResult.fail('需要通知权限');
      }
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
    }

    final p = action.params;
    final title = (p['title'] ?? action.title).toString();
    final body = (p['body'] ?? action.summary).toString();
    final at = _parseDateTime(p['scheduledAt']);
    if (at == null) return DeviceActionResult.fail('scheduledAt 无效');

    final scheduled = tz.TZDateTime.from(at, tz.local);
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      return DeviceActionResult.fail('提醒时间已过期');
    }

    final id = _notificationIdSeq++;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'hermes_device_actions',
        'Hermes 提醒',
        channelDescription: 'AI 批准的本地提醒',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final repeatDaily = p['repeatDaily'] == true;
    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: repeatDaily ? DateTimeComponents.time : null,
    );

    return DeviceActionResult.ok('已设置提醒：$title');
  }

  static CalendarEvent _buildCalendarEvent(Map<String, dynamic> p, DeviceAction action) {
    final title = (p['title'] ?? action.title).toString();
    final start = _parseDateTime(p['startAt'])!;
    final end = _parseDateTime(p['endAt']) ?? start.add(const Duration(hours: 1));
    final reminders = p['reminderMinutes'];
    List<int>? reminderMinutes;
    if (reminders is List) {
      reminderMinutes = reminders.whereType<num>().map((e) => e.toInt()).toList();
    }
    return CalendarEvent(
      title: title,
      startDate: start,
      endDate: end,
      description: p['description']?.toString(),
      location: p['location']?.toString(),
      androidSettings: AndroidEventSettings(
        reminderMinutes: reminderMinutes ?? [15],
        hasAlarm: true,
      ),
    );
  }

  static Future<DeviceActionResult> _addCalendarEvent(
    DeviceAction action, {
    required bool prefillOnly,
  }) async {
    final p = action.params;
    final start = _parseDateTime(p['startAt']);
    final end = _parseDateTime(p['endAt']) ?? start?.add(const Duration(hours: 1));
    if (start == null || end == null) {
      return DeviceActionResult.fail('startAt/endAt 无效');
    }

    final event = _buildCalendarEvent(p, action);

    if (prefillOnly) {
      final ok = await NativeCalendar.openCalendarWithEvent(event);
      if (!ok) return DeviceActionResult.fail('无法打开日历');
      return DeviceActionResult.ok('已打开日历，请在系统界面确认保存');
    }

    final granted = await NativeCalendar.requestCalendarPermissions();
    if (!granted) {
      return DeviceActionResult.fail('需要日历读写权限');
    }

    final ok = await NativeCalendar.addEventToCalendar(event);
    if (!ok) return DeviceActionResult.fail('添加日历失败');
    return DeviceActionResult.ok('已添加到日历：${event.title}');
  }

  static Future<DeviceActionResult> _share(DeviceAction action) async {
    final text = action.params['text']?.toString() ?? '';
    if (text.trim().isEmpty) return DeviceActionResult.fail('分享内容为空');
    await DeviceCapabilityService.shareText(
      text: text,
      subject: action.params['subject']?.toString(),
    );
    return DeviceActionResult.ok('已打开分享');
  }

  static Future<DeviceActionResult> _clipboard(DeviceAction action) async {
    final text = action.params['text']?.toString() ?? '';
    if (text.trim().isEmpty) return DeviceActionResult.fail('复制内容为空');
    await DeviceCapabilityService.writeClipboard(text);
    return DeviceActionResult.ok('已复制到剪贴板');
  }

  static Future<DeviceActionResult> _openSettings(DeviceAction action) async {
    final opened = await openAppSettings();
    if (!opened) return DeviceActionResult.fail('无法打开设置');
    return DeviceActionResult.ok('已打开设置');
  }
}

class DeviceActionResult {
  const DeviceActionResult._({required this.success, this.message});

  final bool success;
  final String? message;

  factory DeviceActionResult.ok(String message) =>
      DeviceActionResult._(success: true, message: message);

  factory DeviceActionResult.fail(String message) =>
      DeviceActionResult._(success: false, message: message);

  void showToast() {
    if (success) {
      AppMessage.success(message ?? '操作成功');
    } else {
      AppMessage.error(message ?? '操作失败');
    }
  }
}
