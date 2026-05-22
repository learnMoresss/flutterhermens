import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 文件类型分类（saveFile / shareFile 路由依据）。
enum HermesFileCategory {
  image,
  video,
  audio,
  document,
  archive,
  text,
  other,
}

class HermesMime {
  HermesMime._();

  static const maxSaveBytes = 80 * 1024 * 1024;

  static const mimeByExt = <String, String>{
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'svg': 'image/svg+xml',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'bmp': 'image/bmp',
    'ico': 'image/x-icon',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
    'avi': 'video/x-msvideo',
    'm4v': 'video/x-m4v',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'flac': 'audio/flac',
    'opus': 'audio/opus',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'csv': 'text/csv',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'html': 'text/html',
    'htm': 'text/html',
    'json': 'application/json',
    'xml': 'application/xml',
    'zip': 'application/zip',
    'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed',
    'tar': 'application/x-tar',
    'gz': 'application/gzip',
    'apk': 'application/vnd.android.package-archive',
    'epub': 'application/epub+zip',
  };

  static String guess(String filename, {String fallback = 'application/octet-stream'}) {
    final ext = extension(filename);
    if (ext.isEmpty) return fallback;
    return mimeByExt[ext] ?? fallback;
  }

  static String extension(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot <= 0 || dot >= filename.length - 1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  static HermesFileCategory category(String mimeType, String filename) {
    final m = mimeType.toLowerCase();
    if (m.startsWith('image/')) return HermesFileCategory.image;
    if (m.startsWith('video/')) return HermesFileCategory.video;
    if (m.startsWith('audio/')) return HermesFileCategory.audio;
    if (m.startsWith('text/')) return HermesFileCategory.text;
    if (m == 'application/pdf' ||
        m.contains('word') ||
        m.contains('excel') ||
        m.contains('spreadsheet') ||
        m.contains('powerpoint') ||
        m.contains('presentation') ||
        m == 'application/epub+zip') {
      return HermesFileCategory.document;
    }
    if (m.contains('zip') ||
        m.contains('rar') ||
        m.contains('7z') ||
        m.contains('tar') ||
        m.contains('gzip') ||
        m == 'application/x-7z-compressed') {
      return HermesFileCategory.archive;
    }
    final ext = extension(filename);
    if (const {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'epub'}.contains(ext)) {
      return HermesFileCategory.document;
    }
    if (const {'zip', 'rar', '7z', 'tar', 'gz'}.contains(ext)) {
      return HermesFileCategory.archive;
    }
    if (const {'txt', 'md', 'csv', 'json', 'xml', 'html', 'htm'}.contains(ext)) {
      return HermesFileCategory.text;
    }
    return HermesFileCategory.other;
  }

  static String destinationLabel(String destination) {
    switch (destination) {
      case 'gallery-image':
        return '已保存到相册';
      case 'gallery-video':
        return '已保存到相册（视频）';
      case 'downloads':
        return '已保存到下载目录';
      case 'documents':
        return '已保存到文件';
      case 'picker':
        return '已保存';
      default:
        return '已保存';
    }
  }
}

class HermesFileSaveResult {
  const HermesFileSaveResult({
    required this.filename,
    required this.size,
    required this.mimeType,
    required this.category,
    required this.destination,
    this.path,
  });

  final String filename;
  final int size;
  final String mimeType;
  final String category;
  final String destination;
  final String? path;

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'size': size,
        'mimeType': mimeType,
        'category': category,
        'destination': destination,
        if (path != null && path!.isNotEmpty) 'path': path,
        'saved': true,
      };
}

class HermesFileIo {
  static String safeFilename(String raw, {String fallback = 'file.bin'}) {
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  static Future<String> writeTempFile(String filename, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final safe = safeFilename(filename);
    final path = '${dir.path}/$safe';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  static Future<String> uniquePath(String dirPath, String filename) async {
    final safe = safeFilename(filename);
    var candidate = '$dirPath/$safe';
    if (!await File(candidate).exists()) return candidate;
    final dot = safe.lastIndexOf('.');
    final stem = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      candidate = '$dirPath/${stem}_$i$ext';
      if (!await File(candidate).exists()) return candidate;
    }
    return '$dirPath/${stem}_${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  static Future<bool> ensureGalleryAccess() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    if (await Gal.hasAccess(toAlbum: true)) return true;
    return Gal.requestAccess(toAlbum: true);
  }

  static Future<HermesFileSaveResult> saveBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    bool usePicker = false,
    void Function(String message)? onSuccess,
  }) async {
    if (bytes.isEmpty) {
      throw HermesFileIoException('INVALID', '空文件');
    }
    if (bytes.length > HermesMime.maxSaveBytes) {
      throw HermesFileIoException('TOO_LARGE', '文件过大（最大 ${HermesMime.maxSaveBytes ~/ (1024 * 1024)}MB）');
    }

    final safeName = safeFilename(filename);
    final category = HermesMime.category(mimeType, safeName);
    final categoryName = category.name;

    if (usePicker) {
      final path = await FilePicker.platform.saveFile(
        fileName: safeName,
        bytes: bytes,
        type: FileType.any,
      );
      if (path == null || path.isEmpty) {
        throw HermesFileIoException('CANCELLED', '用户取消');
      }
      onSuccess?.call(HermesMime.destinationLabel('picker'));
      return HermesFileSaveResult(
        filename: safeName,
        size: bytes.length,
        mimeType: mimeType,
        category: categoryName,
        destination: 'picker',
        path: path,
      );
    }

    switch (category) {
      case HermesFileCategory.image:
        if (!await ensureGalleryAccess()) {
          throw HermesFileIoException('PERMISSION_DENIED', '需要相册写入权限才能保存图片');
        }
        try {
          await Gal.putImageBytes(bytes, name: safeName);
        } on GalException catch (e) {
          throw HermesFileIoException('SAVE_FAILED', e.type.message);
        }
        onSuccess?.call(HermesMime.destinationLabel('gallery-image'));
        return HermesFileSaveResult(
          filename: safeName,
          size: bytes.length,
          mimeType: mimeType,
          category: categoryName,
          destination: 'gallery-image',
        );

      case HermesFileCategory.video:
        if (!await ensureGalleryAccess()) {
          throw HermesFileIoException('PERMISSION_DENIED', '需要相册写入权限才能保存视频');
        }
        final tempPath = await writeTempFile(safeName, bytes);
        try {
          try {
            await Gal.putVideo(tempPath);
          } on GalException catch (e) {
            throw HermesFileIoException('SAVE_FAILED', e.type.message);
          }
        } finally {
          final f = File(tempPath);
          if (await f.exists()) await f.delete();
        }
        onSuccess?.call(HermesMime.destinationLabel('gallery-video'));
        return HermesFileSaveResult(
          filename: safeName,
          size: bytes.length,
          mimeType: mimeType,
          category: categoryName,
          destination: 'gallery-video',
        );

      case HermesFileCategory.audio:
      case HermesFileCategory.document:
      case HermesFileCategory.archive:
      case HermesFileCategory.text:
      case HermesFileCategory.other:
        return _saveToFilesystem(
          bytes: bytes,
          filename: safeName,
          mimeType: mimeType,
          category: categoryName,
          onSuccess: onSuccess,
        );
    }
  }

  static Future<HermesFileSaveResult> _saveToFilesystem({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required String category,
    void Function(String message)? onSuccess,
  }) async {
    Directory? dir;
    String destination;
    if (Platform.isAndroid) {
      dir = await getDownloadsDirectory();
      destination = 'downloads';
    } else if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
      destination = 'documents';
    } else {
      dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      destination = 'downloads';
    }
    if (dir == null) {
      throw HermesFileIoException('UNAVAILABLE', '无法访问保存目录');
    }
    final path = await uniquePath(dir.path, filename);
    await File(path).writeAsBytes(bytes, flush: true);
    onSuccess?.call(HermesMime.destinationLabel(destination));
    return HermesFileSaveResult(
      filename: path.split(Platform.pathSeparator).last,
      size: bytes.length,
      mimeType: mimeType,
      category: category,
      destination: destination,
      path: path,
    );
  }

  static Future<void> shareBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String title = '',
  }) async {
    if (bytes.isEmpty) {
      throw HermesFileIoException('INVALID', '空文件');
    }
    final path = await writeTempFile(filename, bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType, name: safeFilename(filename))],
        subject: title.isNotEmpty ? title : safeFilename(filename),
        text: title.isNotEmpty ? title : null,
      ),
    );
  }
}

class HermesFileIoException implements Exception {
  HermesFileIoException(this.code, this.message);
  final String code;
  final String message;
}
