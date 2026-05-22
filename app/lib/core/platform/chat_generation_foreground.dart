import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Android 前台服务：保持 Hermes SSE 在后台继续，并更新通知栏进度。
class ChatGenerationForeground {
  ChatGenerationForeground._();

  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'hermes_chat_generation',
        channelName: 'Hermes 对话',
        channelDescription: 'AI 回复进行中，显示执行进度',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  static Future<bool> ensureNotificationPermission() async {
    await ensureInitialized();
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission == NotificationPermission.granted) return true;
    final requested = await FlutterForegroundTask.requestNotificationPermission();
    return requested == NotificationPermission.granted;
  }

  static Future<void> start({String? progress}) async {
    await ensureInitialized();
    await ensureNotificationPermission();
    final text = progress?.trim().isNotEmpty == true ? progress!.trim() : 'Hermes 正在思考…';
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Hermes 正在回复',
        notificationText: text,
      );
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 61001,
      notificationTitle: 'Hermes 正在回复',
      notificationText: text,
      notificationIcon: null,
      callback: chatForegroundStartCallback,
    );
  }

  static Future<void> updateProgress(String progress) async {
    if (!_initialized) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    final text = progress.trim().isEmpty ? 'Hermes 正在思考…' : progress.trim();
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Hermes 正在回复',
      notificationText: text,
    );
  }

  static Future<void> stop() async {
    if (!_initialized) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void chatForegroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(_ChatForegroundTaskHandler());
}

class _ChatForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationDismissed() {}
}
