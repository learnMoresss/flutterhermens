import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Hermes 识图经 Gateway inline 后请求体约 1MB，移动端上传前压到该上限内。
const chatImageMaxBytes = 700 * 1024;

class ChatImageTooLargeException implements Exception {
  ChatImageTooLargeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ChatImageCompressResult {
  const ChatImageCompressResult({
    required this.bytes,
    required this.mimeType,
    required this.filename,
    required this.originalBytes,
    required this.compressed,
  });

  final Uint8List bytes;
  final String mimeType;
  final String filename;
  final int originalBytes;
  final bool compressed;
}

/// 聊天图片上传前压缩：限制边长并逐步降低 JPEG 质量，直到满足 [chatImageMaxBytes]。
class ChatImageCompressor {
  ChatImageCompressor._();

  static const _maxSide = 1600;
  static const _initialQuality = 85;
  static const _minQuality = 40;
  static const _qualityStep = 10;
  static const _sideSteps = [_maxSide, 1280, 1024, 800];

  static Future<ChatImageCompressResult> compress({
    required Uint8List input,
    String? filePath,
    String filename = 'image.jpg',
  }) async {
    final originalSize = input.length;
    Uint8List? smallest;

    for (final side in _sideSteps) {
      var quality = _initialQuality;
      while (quality >= _minQuality) {
        final out = await _compressOnce(
          input: input,
          filePath: filePath,
          minSide: side,
          quality: quality,
        );
        if (out == null || out.isEmpty) {
          quality -= _qualityStep;
          continue;
        }

        if (smallest == null || out.length < smallest.length) {
          smallest = out;
        }

        if (out.length <= chatImageMaxBytes) {
          return ChatImageCompressResult(
            bytes: out,
            mimeType: 'image/jpeg',
            filename: _jpegFilename(filename),
            originalBytes: originalSize,
            compressed: out.length != originalSize || side != _maxSide || quality != _initialQuality,
          );
        }

        quality -= _qualityStep;
      }
    }

    if (smallest != null && smallest.length <= chatImageMaxBytes) {
      return ChatImageCompressResult(
        bytes: smallest,
        mimeType: 'image/jpeg',
        filename: _jpegFilename(filename),
        originalBytes: originalSize,
        compressed: true,
      );
    }

    final best = smallest?.length ?? originalSize;
    throw ChatImageTooLargeException(
      '图片压缩后仍过大（${best ~/ 1024}KB，建议 ≤ ${chatImageMaxBytes ~/ 1024}KB）',
    );
  }

  static Future<Uint8List?> _compressOnce({
    required Uint8List input,
    String? filePath,
    required int minSide,
    required int quality,
  }) async {
    if (filePath != null && filePath.isNotEmpty && !kIsWeb) {
      return FlutterImageCompress.compressWithFile(
        filePath,
        minWidth: minSide,
        minHeight: minSide,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
    }

    return FlutterImageCompress.compressWithList(
      input,
      minWidth: minSide,
      minHeight: minSide,
      quality: quality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
  }

  static String _jpegFilename(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '$base.jpg';
  }
}
