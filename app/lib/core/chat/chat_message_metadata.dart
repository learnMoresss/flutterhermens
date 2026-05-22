import 'dart:typed_data';

const kChatMetaImagesKey = 'images';
const kChatMetaFileKey = 'file';
const kHermesLoadingText = '…';

/// 输入框待发送图片（本地 previewBytes 仅用于 UI 预览）。
class PendingChatImage {
  const PendingChatImage({
    required this.mimeType,
    required this.url,
    required this.previewBytes,
  });

  final String mimeType;
  final String url;
  final Uint8List previewBytes;

  ChatImageAttachment toAttachment() => ChatImageAttachment(
        mimeType: mimeType,
        url: url,
      );

  /// Hermes vision_analyze 需要 http URL；previewBytes 仅 UI 预览。
  ({String mimeType, String url}) toApiPayload() => (
        mimeType: mimeType,
        url: url,
      );
}

class ChatImageAttachment {
  const ChatImageAttachment({
    required this.mimeType,
    required this.url,
    this.base64,
  });

  final String mimeType;
  final String url;

  /// 仅用于旧消息兼容展示，新消息不再写入。
  final String? base64;

  Map<String, dynamic> toJson() => {
        'mimeType': mimeType,
        'url': url,
      };

  factory ChatImageAttachment.fromJson(Map<String, dynamic> json) {
    return ChatImageAttachment(
      mimeType: json['mimeType']?.toString() ?? 'image/jpeg',
      url: json['url']?.toString() ?? '',
      base64: json['base64']?.toString(),
    );
  }

  /// 历史消息公网 URL，Gateway 转为 Hermes 可拉取的内网 URL。
  ({String mimeType, String url}) toApiPayload() => (
        mimeType: mimeType,
        url: url,
      );
}

class ChatFileAttachment {
  const ChatFileAttachment({required this.name, required this.mimeType});

  final String name;
  final String mimeType;

  Map<String, dynamic> toJson() => {'name': name, 'mimeType': mimeType};

  factory ChatFileAttachment.fromJson(Map<String, dynamic> json) {
    return ChatFileAttachment(
      name: json['name']?.toString() ?? '文件',
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
    );
  }
}

List<ChatImageAttachment> parseChatImages(Map<String, dynamic>? metadata) {
  final raw = metadata?[kChatMetaImagesKey];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => ChatImageAttachment.fromJson(Map<String, dynamic>.from(e)))
      .where((img) => img.url.isNotEmpty || (img.base64?.isNotEmpty ?? false))
      .toList(growable: false);
}

ChatFileAttachment? parseChatFile(Map<String, dynamic>? metadata) {
  final raw = metadata?[kChatMetaFileKey];
  if (raw is! Map) return null;
  return ChatFileAttachment.fromJson(Map<String, dynamic>.from(raw));
}

bool hasChatAttachments(Map<String, dynamic>? metadata) {
  return parseChatImages(metadata).isNotEmpty || parseChatFile(metadata) != null;
}

Map<String, dynamic>? buildChatAttachmentsMetadata({
  List<ChatImageAttachment>? images,
  ChatFileAttachment? file,
}) {
  if ((images == null || images.isEmpty) && file == null) return null;
  return {
    if (images != null && images.isNotEmpty)
      kChatMetaImagesKey: images.map((e) => e.toJson()).toList(growable: false),
    if (file != null) kChatMetaFileKey: file.toJson(),
  };
}

String? extractToolProgressLine(String text) {
  if (!text.startsWith('⏳')) return null;
  final firstLine = text.split('\n').first;
  if (!firstLine.startsWith('⏳')) return null;
  return firstLine.substring('⏳'.length).trim();
}

bool isHermesLoadingText(String text) {
  if (text == kHermesLoadingText) return true;
  final body = text.startsWith('⏳') ? text.split('\n').skip(1).join('\n').trim() : text.trim();
  return body.isEmpty || body == kHermesLoadingText;
}
