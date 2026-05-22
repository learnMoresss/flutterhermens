import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../network/api_client.dart';
import 'gateway_file_fetch.dart';
import 'gateway_media_cache.dart';

/// 将已下载的文件保存到临时目录并通过系统分享面板导出（保存/发送）。
Future<void> shareGatewayFile(GatewayFilePayload payload) async {
  final name = _safeFilename(payload.filename ?? 'hermes_file');
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(payload.bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, name: name, mimeType: payload.contentType)],
      subject: name,
      text: 'Hermes 文件：$name',
    ),
  );
}

/// 下载 Gateway 媒体（优先磁盘缓存，签名 URL 变更仍可按路径命中）。
Future<File> downloadGatewayFileToTemp(
  Dio dio,
  String url, {
  ApiClient? clientForResign,
  String? mediaFileName,
  void Function(int received, int? total)? onProgress,
}) {
  return GatewayMediaCache.instance.getOrDownload(
    dio,
    url,
    clientForResign: clientForResign,
    mediaFileName: mediaFileName,
    onProgress: onProgress,
  );
}

String _safeFilename(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'hermes_file' : cleaned;
}
