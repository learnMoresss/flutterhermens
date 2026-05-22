import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../network/api_client.dart';
import 'gateway_file_fetch.dart';
import 'media_link_utils.dart';

/// 媒体/文件磁盘缓存统计。
class GatewayMediaCacheStats {
  const GatewayMediaCacheStats({
    required this.fileCount,
    required this.totalBytes,
  });

  final int fileCount;
  final int totalBytes;

  String get sizeLabel => _formatBytes(totalBytes);
}

/// Gateway 图片/视频/文件磁盘缓存（稳定资源键 + LRU 容量淘汰）。
class GatewayMediaCache {
  GatewayMediaCache._();

  static final GatewayMediaCache instance = GatewayMediaCache._();

  static const int maxCacheBytes = 512 * 1024 * 1024;
  static const Duration maxAge = Duration(days: 14);

  Directory? _root;

  Future<Directory> _cacheRoot() async {
    if (_root != null) return _root!;
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/gateway_media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _root = dir;
    return dir;
  }

  /// 稳定键：同一路径/文件 ID 在重新签名后仍命中缓存。
  String storageKey(String url, {String? mediaFileName}) {
    final path = decodedPathFromGatewayMediaUrl(url);
    if (path != null && path.isNotEmpty) {
      return _digest('path:$path');
    }
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final filesIdx = segments.indexOf('files');
      if (filesIdx >= 0 && filesIdx + 1 < segments.length) {
        return _digest('upload:${segments[filesIdx + 1]}');
      }
    }
    final name = mediaFileName?.trim();
    if (name != null && name.isNotEmpty) {
      return _digest('name:$name');
    }
    return _digest('url:$url');
  }

  String _digest(String input) {
    return sha256.convert(utf8.encode(input)).toString().substring(0, 32);
  }

  Future<File> _entryFile(String key, String filename) async {
    final root = await _cacheRoot();
    final sub = key.substring(0, 2);
    final dir = Directory('${root.path}/$sub');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/${key}_${_safeFilename(filename)}');
  }

  Future<File?> getFile(String url, {String? mediaFileName}) async {
    final name = filenameFromGatewayUrl(url) ?? mediaFileName ?? 'media.bin';
    final file = await _entryFile(storageKey(url, mediaFileName: mediaFileName), name);
    if (!await file.exists()) return null;
    final len = await file.length();
    if (len <= 0) {
      await file.delete();
      return null;
    }
    final age = DateTime.now().difference(await file.lastModified());
    if (age > maxAge) {
      await file.delete();
      return null;
    }
    await file.setLastModified(DateTime.now());
    return file;
  }

  Future<Uint8List?> getBytes(String url, {String? mediaFileName}) async {
    final file = await getFile(url, mediaFileName: mediaFileName);
    if (file == null) return null;
    return file.readAsBytes();
  }

  Future<File> putBytes(
    String url,
    Uint8List bytes, {
    String? mediaFileName,
    String? contentType,
  }) async {
    final name = filenameFromGatewayUrl(url) ?? mediaFileName ?? 'media.bin';
    final file = await _entryFile(storageKey(url, mediaFileName: mediaFileName), name);
    await file.writeAsBytes(bytes, flush: true);
    await file.setLastModified(DateTime.now());
    await _evictIfNeeded();
    return file;
  }

  /// 命中磁盘则直接返回，否则下载并写入缓存。
  Future<File> getOrDownload(
    Dio dio,
    String url, {
    ApiClient? clientForResign,
    String? mediaFileName,
    void Function(int received, int? total)? onProgress,
  }) async {
    final cached = await getFile(url, mediaFileName: mediaFileName);
    if (cached != null) return cached;

    try {
      final file = await _downloadToCache(
        dio,
        url,
        mediaFileName: mediaFileName,
        onProgress: onProgress,
      );
      await _evictIfNeeded();
      return file;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final empty = e.message == '文件为空' || e.message == '下载为空';
      if (clientForResign != null && (code == 400 || code == 403 || code == 404 || empty)) {
        final fresh = await refreshGatewayMediaUrl(
          clientForResign,
          url,
          mediaFileName: mediaFileName,
        );
        if (fresh != null && fresh != url) {
          final hit = await getFile(fresh, mediaFileName: mediaFileName);
          if (hit != null) return hit;
          final file = await _downloadToCache(
            dio,
            fresh,
            mediaFileName: mediaFileName,
            onProgress: onProgress,
          );
          await _evictIfNeeded();
          return file;
        }
      }
      rethrow;
    }
  }

  Future<File> _downloadToCache(
    Dio dio,
    String url, {
    String? mediaFileName,
    void Function(int received, int? total)? onProgress,
  }) async {
    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        validateStatus: (status) => status == 200 || status == 206,
      ),
      onReceiveProgress: onProgress,
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
        response: response,
        message: '下载为空',
      );
    }

    return putBytes(
      url,
      Uint8List.fromList(data),
      mediaFileName: mediaFileName,
      contentType: response.headers.value('content-type'),
    );
  }

  Future<GatewayMediaCacheStats> getStats() async {
    final root = await _cacheRoot();
    var count = 0;
    var bytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      count++;
      bytes += await entity.length();
    }
    return GatewayMediaCacheStats(fileCount: count, totalBytes: bytes);
  }

  Future<void> clearAll() async {
    final root = await _cacheRoot();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    _root = null;
    await _cacheRoot();
  }

  Future<void> _evictIfNeeded() async {
    final root = await _cacheRoot();
    final entries = <File>[];
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final len = await entity.length();
      total += len;
      entries.add(entity);
    }
    if (total <= maxCacheBytes) return;

    entries.sort(
      (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
    );
    for (final f in entries) {
      if (total <= maxCacheBytes * 0.85) break;
      total -= await f.length();
      await f.delete();
    }
  }

  String _safeFilename(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'media.bin' : cleaned;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
