import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../network/api_client.dart';
import 'gateway_media_cache.dart';
import 'media_link_utils.dart';

class GatewayFilePayload {
  const GatewayFilePayload({
    required this.bytes,
    this.contentType,
    this.filename,
  });

  final Uint8List bytes;
  final String? contentType;
  final String? filename;
}

/// 从 Gateway 媒体/上传 URL 拉取文件（自动携带 Dio 上的 JWT，带磁盘缓存）。
Future<GatewayFilePayload> fetchGatewayFile(
  Dio dio,
  String url, {
  String? mediaFileName,
}) async {
  final cached = await GatewayMediaCache.instance.getBytes(
    url,
    mediaFileName: mediaFileName,
  );
  if (cached != null && cached.isNotEmpty) {
    return GatewayFilePayload(
      bytes: cached,
      filename: filenameFromGatewayUrl(url) ?? mediaFileName,
    );
  }

  final response = await dio.get<List<int>>(
    url,
    options: Options(
      responseType: ResponseType.bytes,
      followRedirects: true,
      validateStatus: (s) => s == 200 || s == 206,
    ),
  );

  if (response.statusCode != 200 && response.statusCode != 206) {
    throw DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: '下载失败 (${response.statusCode})',
    );
  }

  final data = response.data;
  if (data == null || data.isEmpty) {
    throw DioException(
      requestOptions: response.requestOptions,
      message: '文件为空',
    );
  }

  final ct = response.headers.value('content-type');
  final filename = _filenameFromHeaders(response.headers) ??
      filenameFromGatewayUrl(url) ??
      mediaFileName;

  final bytes = Uint8List.fromList(data);
  await GatewayMediaCache.instance.putBytes(
    url,
    bytes,
    mediaFileName: mediaFileName ?? filename,
    contentType: ct,
  );

  return GatewayFilePayload(
    bytes: bytes,
    contentType: ct,
    filename: filename,
  );
}

/// 链接无效/过期时重新签名。
Future<String?> refreshGatewayMediaUrl(
  ApiClient client,
  String url, {
  String? mediaFileName,
}) async {
  final absPath = decodedPathFromGatewayMediaUrl(url);
  if (absPath != null && absPath.isNotEmpty) {
    final signed = await client.signMediaUrl(absPath);
    if (signed != null) return signed;
    if (absPath.startsWith('/')) {
      final viaFile = await client.signMediaUrl('file://$absPath');
      if (viaFile != null) return viaFile;
    }
  }
  final name = mediaFileName?.trim();
  if (name != null && name.isNotEmpty) {
    return client.signMediaUrl('MEDIA:$name');
  }
  return null;
}

/// 拉取失败或 body 为空时尝试重新签名后再拉（图片/预览/视频共用）。
Future<GatewayFilePayload> fetchGatewayFileResilient(
  Dio dio,
  String url, {
  ApiClient? client,
  String? mediaFileName,
}) async {
  try {
    return await fetchGatewayFile(dio, url, mediaFileName: mediaFileName);
  } on DioException catch (e) {
    final retry = client != null &&
        (e.response?.statusCode == 400 ||
            e.response?.statusCode == 403 ||
            e.response?.statusCode == 404 ||
            e.message == '文件为空');
    if (!retry) rethrow;
    final fresh = await refreshGatewayMediaUrl(
      client,
      url,
      mediaFileName: mediaFileName,
    );
    if (fresh == null || fresh == url) rethrow;
    return fetchGatewayFile(dio, fresh, mediaFileName: mediaFileName);
  }
}

String? _filenameFromHeaders(Headers headers) {
  final cd = headers.value('content-disposition');
  if (cd == null) return null;
  final match = RegExp(r'''filename\*=UTF-8''([^;]+)|filename="([^"]+)"|filename=([^;]+)''')
      .firstMatch(cd);
  if (match == null) return null;
  final raw = match.group(1) ?? match.group(2) ?? match.group(3);
  if (raw == null) return null;
  try {
    return Uri.decodeComponent(raw.trim());
  } on Object {
    return raw.trim();
  }
}

/// 从 Gateway URL 推断展示用文件名（含 base64 path 参数）。
String? filenameFromGatewayUrl(String url) {
  final decoded = decodedPathFromGatewayMediaUrl(url);
  if (decoded != null && decoded.isNotEmpty) {
    final name = decoded.split('/').where((s) => s.isNotEmpty).lastOrNull;
    if (name != null && name.isNotEmpty) return name;
  }

  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;
  final last = segments.last;
  if (last == 'serve' || last == 'files') return null;
  return last;
}
