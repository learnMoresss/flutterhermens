import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/chat/widgets/file_preview_page.dart';
import '../../features/chat/widgets/video_preview_page.dart';
import 'gateway_file_fetch.dart';

/// 打开应用内预览；非 Gateway 链接仍走系统浏览器。
Future<void> openFilePreview(
  BuildContext context, {
  required String href,
  String? linkText,
  String? gatewayBaseUrl,
}) async {
  final uri = Uri.tryParse(href);
  if (uri == null) return;

  if (_shouldPreviewInApp(href, gatewayBaseUrl)) {
    await FilePreviewPage.open(
      context,
      url: href,
      title: linkText ?? filenameFromGatewayUrl(href),
    );
    return;
  }

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

bool _shouldPreviewInApp(String href, String? gatewayBase) {
  if (gatewayBase == null || gatewayBase.isEmpty) return false;
  final base = gatewayBase.endsWith('/')
      ? gatewayBase.substring(0, gatewayBase.length - 1)
      : gatewayBase;
  if (!href.startsWith(base)) return false;
  return href.contains('/v1/media/serve') || href.contains('/v1/files/');
}

/// 图片链接也走预览页（全屏缩放）。
Future<void> openImagePreview(
  BuildContext context, {
  required String url,
  String? title,
}) {
  return FilePreviewPage.open(context, url: url, title: title);
}

/// 视频链接全屏播放。
Future<void> openVideoPreview(
  BuildContext context, {
  required String url,
  String? title,
}) {
  return VideoPreviewPage.open(context, url: url, title: title);
}
