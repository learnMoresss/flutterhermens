import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/chat/chat_message_metadata.dart';
import '../../../core/theme/app_colors.dart';
import 'gateway_media_image.dart';

/// 聊天内图片块：预留高度，加载完成后回调以便滚动到底部。
class ChatImageTile extends StatefulWidget {
  const ChatImageTile({
    required this.image,
    this.onLoaded,
    super.key,
  });

  final ChatImageAttachment image;
  final VoidCallback? onLoaded;

  static const double maxSide = 220;

  @override
  State<ChatImageTile> createState() => _ChatImageTileState();
}

class _ChatImageTileState extends State<ChatImageTile> {
  var _loaded = false;

  void _notifyLoadedOnce() {
    if (_loaded) return;
    _loaded = true;
    widget.onLoaded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.image.url.trim();
    if (url.isNotEmpty) {
      return GatewayMediaImage(
        url: url,
        boxSize: ChatImageTile.maxSide,
        onLoaded: _notifyLoadedOnce,
      );
    }

    final b64 = widget.image.base64;
    if (b64 != null && b64.isNotEmpty) {
      return _MemoryChatImage(bytes: b64, onLoaded: _notifyLoadedOnce);
    }

    return const _BrokenChatImage();
  }
}

class _MemoryChatImage extends StatefulWidget {
  const _MemoryChatImage({required this.bytes, this.onLoaded});

  final String bytes;
  final VoidCallback? onLoaded;

  @override
  State<_MemoryChatImage> createState() => _MemoryChatImageState();
}

class _MemoryChatImageState extends State<_MemoryChatImage> {
  Uint8List? _decoded;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  void _decode() {
    try {
      _decoded = base64Decode(widget.bytes);
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoaded?.call());
    } on Object {
      _failed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _decoded == null) {
      return const _BrokenChatImage();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: ChatImageTile.maxSide,
        height: ChatImageTile.maxSide,
        child: Image.memory(
          _decoded!,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoaded?.call());
            }
            return child;
          },
          errorBuilder: (_, _, _) => const _BrokenChatImage(),
        ),
      ),
    );
  }
}

class _BrokenChatImage extends StatelessWidget {
  const _BrokenChatImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ChatImageTile.maxSide,
      height: ChatImageTile.maxSide,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.grayLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.broken_image_outlined),
    );
  }
}
