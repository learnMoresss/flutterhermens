import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chat/file_preview_launcher.dart';
import '../../../core/theme/app_colors.dart';

/// 聊天内视频卡片：仅展示封面与播放按钮，点击全屏播放。
class GatewayMediaVideo extends ConsumerStatefulWidget {
  const GatewayMediaVideo({
    required this.url,
    this.title,
    this.onLoaded,
    super.key,
  });

  final String url;
  final String? title;
  final VoidCallback? onLoaded;

  @override
  ConsumerState<GatewayMediaVideo> createState() => _GatewayMediaVideoState();
}

class _GatewayMediaVideoState extends ConsumerState<GatewayMediaVideo> {
  var _notifiedLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_notifiedLoaded) return;
      _notifiedLoaded = true;
      widget.onLoaded?.call();
    });
  }

  void _openFullscreen() {
    openVideoPreview(
      context,
      url: widget.url,
      title: widget.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.82;
    final title = widget.title?.trim();

    return Container(
      width: maxW,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.grayLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null && title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Material(
              color: Colors.black87,
              child: InkWell(
                onTap: _openFullscreen,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.movie_outlined,
                      size: 48,
                      color: Colors.white24,
                    ),
                    Icon(
                      Icons.play_circle_filled,
                      size: 56,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '全屏播放',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
