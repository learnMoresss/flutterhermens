import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// 分享 / 剪贴板等轻量设备能力（聊天与 WebView 共用）。
class DeviceCapabilityService {
  const DeviceCapabilityService._();

  static Future<void> writeClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> shareText({required String text, String? subject}) async {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject != null && subject.isNotEmpty ? subject : null,
      ),
    );
  }
}
