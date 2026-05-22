import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/chat/media_link_utils.dart';
import 'gateway_media_image.dart';
import 'gateway_media_video.dart';

/// 将 Markdown 中的 Gateway 视频链渲染为可播放卡片，其余仍走 MarkdownBody。
class ChatMarkdownContent extends StatelessWidget {
  const ChatMarkdownContent({
    required this.text,
    required this.gatewayBase,
    required this.styleSheet,
    this.onContentExpanded,
    this.onTapLink,
    super.key,
  });

  final String text;
  final String gatewayBase;
  final MarkdownStyleSheet styleSheet;
  final VoidCallback? onContentExpanded;
  final Future<void> Function(String text, String? href, String title)? onTapLink;

  static final _mediaLinkRe = RegExp(
    r'!\[([^\]]*)\]\((https?:\/\/[^)\s]+)\)|\[([^\]]*)\]\((https?:\/\/[^)\s]+)\)',
  );

  @override
  Widget build(BuildContext context) {
    final segments = _splitSegments(text);
    if (segments.length == 1 && segments.first is _TextSegment) {
      return _markdownBody((segments.first as _TextSegment).content);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final seg in segments) ...[
          switch (seg) {
            _TextSegment(:final content) => _markdownBody(content),
            _ImageSegment(:final url, :final alt) => GatewayMediaImage(
                key: ValueKey(url),
                url: url,
                alt: alt,
                onLoaded: onContentExpanded,
              ),
            _VideoSegment(:final url, :final title) => GatewayMediaVideo(
                key: ValueKey(url),
                url: url,
                title: title,
                onLoaded: onContentExpanded,
              ),
          },
        ],
      ],
    );
  }

  List<_Segment> _splitSegments(String input) {
    final out = <_Segment>[];
    var last = 0;

    for (final m in _mediaLinkRe.allMatches(input)) {
      if (m.start > last) {
        final chunk = input.substring(last, m.start);
        if (chunk.trim().isNotEmpty) {
          out.add(_TextSegment(chunk));
        }
      }

      final isImage = m.group(1) != null;
      final label = (isImage ? m.group(1) : m.group(3)) ?? '';
      final url = (isImage ? m.group(2) : m.group(4)) ?? '';

      if (url.isEmpty) {
        out.add(_TextSegment(m.group(0)!));
      } else if (isImage &&
          (isGatewayMediaUrl(url, gatewayBase) || isImageHref(url))) {
        out.add(_ImageSegment(url: url, alt: label.isEmpty ? null : label));
      } else if (!isImage &&
          isGatewayMediaVideoUrl(url, gatewayBase, linkLabel: label)) {
        out.add(_VideoSegment(url: url, title: label.isEmpty ? null : label));
      } else {
        out.add(_TextSegment(m.group(0)!));
      }

      last = m.end;
    }

    if (last < input.length) {
      final tail = input.substring(last);
      if (tail.trim().isNotEmpty) {
        out.add(_TextSegment(tail));
      }
    }

    if (out.isEmpty) {
      out.add(_TextSegment(input));
    }
    return out;
  }

  Widget _markdownBody(String data) {
    if (data.trim().isEmpty) return const SizedBox.shrink();
    return MarkdownBody(
      data: data,
      selectable: true,
      shrinkWrap: true,
      sizedImageBuilder: (config) {
        final href = config.uri.toString();
        final alt = config.alt;
        if (isGatewayMediaUrl(href, gatewayBase) || isImageHref(href)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: GatewayMediaImage(
              key: ValueKey(href),
              url: href,
              alt: alt,
              onLoaded: onContentExpanded,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Image.network(
            href,
            errorBuilder: (_, _, _) => Text(alt ?? href),
          ),
        );
      },
      onTapLink: onTapLink,
      styleSheet: styleSheet,
    );
  }
}

sealed class _Segment {}

class _TextSegment extends _Segment {
  _TextSegment(this.content);
  final String content;
}

class _ImageSegment extends _Segment {
  _ImageSegment({required this.url, this.alt});
  final String url;
  final String? alt;
}

class _VideoSegment extends _Segment {
  _VideoSegment({required this.url, this.title});
  final String url;
  final String? title;
}
