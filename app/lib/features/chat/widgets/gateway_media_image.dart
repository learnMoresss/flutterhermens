import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/chat/file_preview_launcher.dart';
import '../../../core/chat/gateway_file_fetch.dart';
import '../../../core/chat/media_link_utils.dart';
import '../../../providers/app_providers.dart';

/// Gateway 媒体图片：统一经 Dio 拉取 bytes（勿用 Image.network，避免 serve 空 body）。
class GatewayMediaImage extends ConsumerStatefulWidget {
  const GatewayMediaImage({
    required this.url,
    this.alt,
    this.onLoaded,
    this.boxSize = 220,
    super.key,
  });

  final String url;
  final String? alt;
  final VoidCallback? onLoaded;

  /// 固定宽高，避免在 Markdown / List 中出现无界 expand。
  final double boxSize;

  @override
  ConsumerState<GatewayMediaImage> createState() => _GatewayMediaImageState();
}

class _GatewayMediaImageState extends ConsumerState<GatewayMediaImage> {
  bool _loading = true;
  Uint8List? _bytes;
  bool _failed = false;
  var _notifiedLoaded = false;

  void _notifyLoadedOnce() {
    if (_notifiedLoaded) return;
    _notifiedLoaded = true;
    widget.onLoaded?.call();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GatewayMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _notifiedLoaded = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (Uri.tryParse(widget.url) == null) {
      if (mounted) setState(() { _loading = false; _failed = true; });
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _bytes = null;
      });
    }

    try {
      if (!mounted) return;
      final api = ref.read(gatewayClientProvider);
      final gatewayBase = ref.read(appConfigProvider).gatewayUrl;
      var url = widget.url;
      if (isGatewayMediaUrl(url, gatewayBase) || url.contains('/v1/media/serve')) {
        final fresh = await refreshGatewayMediaUrl(
          api,
          url,
          mediaFileName: widget.alt,
        );
        if (fresh != null && fresh.isNotEmpty) url = fresh;
      }
      final payload = await fetchGatewayFileResilient(
        api.dio,
        url,
        client: api,
        mediaFileName: widget.alt,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _bytes = payload.bytes;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyLoadedOnce());
    } on Object {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  Widget _boxed(Widget child) {
    return SizedBox(
      width: widget.boxSize,
      height: widget.boxSize,
      child: child,
    );
  }

  Widget _tappable(Widget child) {
    return GestureDetector(
      onTap: () => openImagePreview(
        context,
        url: widget.url,
        title: widget.alt,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _boxed(
        const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_failed || _bytes == null) {
      return _boxed(
        const Center(
          child: Text('图片加载失败', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return _tappable(
      _boxed(
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.memory(
            _bytes!,
            width: widget.boxSize,
            height: widget.boxSize,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame != null || wasSynchronouslyLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _notifyLoadedOnce());
              }
              return child;
            },
            errorBuilder: (_, _, _) => const Center(
              child: Text('图片解码失败', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ),
      ),
    );
  }
}
