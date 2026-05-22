import 'dart:convert';

/// Gateway 聊天消息中的媒体链接识别。
bool isGatewayMediaUrl(String href, String gatewayBase) {
  if (gatewayBase.isEmpty) return false;
  final base = gatewayBase.endsWith('/')
      ? gatewayBase.substring(0, gatewayBase.length - 1)
      : gatewayBase;
  return href.startsWith(base) &&
      (href.contains('/v1/media/serve') || href.contains('/v1/files/'));
}

bool _hasVideoExtension(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.mkv');
}

/// 从 `/v1/media/serve?path=` 解出服务器绝对路径。
String? decodedPathFromGatewayMediaUrl(String href) {
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  final pathParam = uri.queryParameters['path'];
  if (pathParam == null || pathParam.isEmpty) return null;
  if (pathParam.startsWith('/')) {
    return Uri.decodeComponent(pathParam);
  }
  if (pathParam.toLowerCase().startsWith('file://')) {
    try {
      return Uri.parse(pathParam).toFilePath(windows: false);
    } on Object {
      return null;
    }
  }
  try {
    final normalized = base64Url.normalize(pathParam);
    return utf8.decode(base64Url.decode(normalized));
  } on Object {
    try {
      var b64 = pathParam.replaceAll('-', '+').replaceAll('_', '/');
      final pad = b64.length % 4;
      if (pad > 0) b64 += '=' * (4 - pad);
      return utf8.decode(base64.decode(b64));
    } on Object {
      return null;
    }
  }
}

bool isImageHref(String href) {
  final lower = href.toLowerCase();
  final path = Uri.tryParse(href)?.path.toLowerCase() ?? lower;
  return lower.contains('image/') ||
      path.endsWith('.png') ||
      path.endsWith('.jpg') ||
      path.endsWith('.jpeg') ||
      path.endsWith('.gif') ||
      path.endsWith('.webp') ||
      path.endsWith('.svg') ||
      path.endsWith('.bmp') ||
      path.endsWith('.avif');
}

/// [linkLabel] 为 Markdown 链接文字，如 `final_video.mp4`（serve URL 本身常无扩展名）。
bool isVideoHref(String href, {String? linkLabel}) {
  if (linkLabel != null && linkLabel.trim().isNotEmpty && _hasVideoExtension(linkLabel)) {
    return true;
  }
  final decoded = decodedPathFromGatewayMediaUrl(href);
  if (decoded != null && _hasVideoExtension(decoded)) {
    return true;
  }
  final lower = href.toLowerCase();
  final path = Uri.tryParse(href)?.path.toLowerCase() ?? lower;
  return lower.contains('video/') ||
      _hasVideoExtension(path) ||
      _hasVideoExtension(lower);
}

bool isGatewayMediaVideoUrl(String href, String gatewayBase, {String? linkLabel}) {
  return isGatewayMediaUrl(href, gatewayBase) && isVideoHref(href, linkLabel: linkLabel);
}
