import '../network/api_client.dart';

final _mediaFileRe = RegExp(r'MEDIA:file://[^\s\]\)]+', caseSensitive: false);
final _mediaBareRe = RegExp(r'MEDIA:(?!file://)([^\s\]\)<>"]+)', caseSensitive: false);
final _fileUrlRe = RegExp(r'(?<!MEDIA:)file://[^\s\]\)]+', caseSensitive: false);

/// 客户端兜底：将仍含 file:// / MEDIA: 的文本改写为可访问的 Markdown 链接。
Future<String> rewriteMediaUrlsAsync(
  String text, {
  required ApiClient client,
}) async {
  if (text.isEmpty) return text;
  if (!text.contains('file://') && !text.toUpperCase().contains('MEDIA:')) {
    return text;
  }

  var out = text;
  final refs = <String>{
    ..._mediaFileRe.allMatches(text).map((m) => m.group(0)!),
    ..._mediaBareRe.allMatches(text).map((m) => m.group(0)!),
    ..._fileUrlRe.allMatches(text).map((m) => m.group(0)!),
  };

  for (final raw in refs) {
    final signed = await client.signMediaUrl(raw);
    if (signed == null) continue;
    final path = _pathFromFileRef(raw) ?? _pathFromBareMedia(raw);
    final name = path?.split('/').where((s) => s.isNotEmpty).lastOrNull ??
        raw.replaceFirst(RegExp(r'^MEDIA:', caseSensitive: false), '');
    final replacement = path != null && _isImagePath(path)
        ? '![$name]($signed)'
        : '[$name]($signed)';
    out = out.replaceAll(raw, replacement);
  }
  return out;
}

String? _pathFromBareMedia(String raw) {
  if (!raw.toUpperCase().startsWith('MEDIA:')) return null;
  final name = raw.substring(6).trim();
  return name.isEmpty ? null : name;
}

String? _pathFromFileRef(String raw) {
  final trimmed = raw.startsWith('MEDIA:') ? raw.substring(6) : raw;
  if (!trimmed.toLowerCase().startsWith('file://')) return null;
  try {
    return Uri.parse(trimmed).toFilePath(windows: false);
  } on Object {
    return null;
  }
}

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.svg') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.avif');
}

/// 同步轻量改写（仅清理 MEDIA: 前缀，供流式中间态；最终应调用 [rewriteMediaUrlsAsync]）。
String rewriteMediaUrlsLite(String text) {
  if (text.isEmpty) return text;
  return text.replaceAll(RegExp(r'MEDIA:(?=file://)', caseSensitive: false), '');
}
