import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/chat/gateway_file_download.dart';
import '../../../core/chat/gateway_file_fetch.dart';
import '../../../core/chat/media_link_utils.dart';
import '../../../providers/app_providers.dart';

/// 全屏播放 Gateway 视频（聊天内卡片点击后进入）。
class VideoPreviewPage extends ConsumerStatefulWidget {
  const VideoPreviewPage({
    required this.url,
    this.title,
    super.key,
  });

  final String url;
  final String? title;

  static Future<void> open(
    BuildContext context, {
    required String url,
    String? title,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VideoPreviewPage(url: url, title: title),
      ),
    );
  }

  @override
  ConsumerState<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends ConsumerState<VideoPreviewPage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  double? _progress;
  String? _error;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = null;
    });

    try {
      final api = ref.read(gatewayClientProvider);
      final gatewayBase = ref.read(appConfigProvider).gatewayUrl;
      var playUrl = widget.url;
      if (isGatewayMediaUrl(playUrl, gatewayBase) || playUrl.contains('/v1/media/serve')) {
        final fresh = await refreshGatewayMediaUrl(
          api,
          playUrl,
          mediaFileName: widget.title,
        );
        if (fresh != null && fresh.isNotEmpty) playUrl = fresh;
      }

      final file = await downloadGatewayFileToTemp(
        api.dio,
        playUrl,
        clientForResign: api,
        mediaFileName: widget.title,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total != null && total > 0 ? received / total : null;
          });
        },
      );

      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
      _scheduleHideControls();
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _friendlyMessage(e);
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  String _friendlyMessage(DioException e) {
    final code = e.response?.statusCode;
    return switch (code) {
      400 => '媒体链接无效',
      403 => '无权访问该视频',
      404 => '服务器上找不到该视频',
      _ => e.message ?? '加载失败',
    };
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _showControls = true;
        _hideControlsTimer?.cancel();
      } else {
        c.play();
        _scheduleHideControls();
      }
    });
  }

  String get _displayTitle {
    final t = widget.title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return '视频';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              _progress != null
                  ? '正在加载 ${(_progress! * 100).toStringAsFixed(0)}%'
                  : '正在加载视频…',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _prepare, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final c = _controller!;
    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          if (_showControls)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black38,
                child: Center(
                  child: IconButton(
                    iconSize: 72,
                    color: Colors.white,
                    onPressed: _togglePlay,
                    icon: Icon(
                      c.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    ),
                  ),
                ),
              ),
            ),
          if (_showControls)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
