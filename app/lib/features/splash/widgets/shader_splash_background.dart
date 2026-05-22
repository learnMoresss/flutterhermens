import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../splash_shader_cache.dart';

/// 开屏全屏 GPU shader 背景（参考 shader-animation 流动线条效果）。
class ShaderSplashBackground extends StatefulWidget {
  const ShaderSplashBackground({super.key, this.onShaderReady});

  final VoidCallback? onShaderReady;

  @override
  State<ShaderSplashBackground> createState() => _ShaderSplashBackgroundState();
}

class _ShaderSplashBackgroundState extends State<ShaderSplashBackground>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  bool _failed = false;
  double _time = 1.0;
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      _time += 0.05;
      if (mounted) setState(() {});
    })..start();
    _loadShader();
  }

  void _notifyReady() {
    widget.onShaderReady?.call();
  }

  Future<void> _loadShader() async {
    final cached = SplashShaderCache.createShader();
    if (cached != null) {
      if (!mounted) {
        cached.dispose();
        return;
      }
      setState(() => _shader = cached);
      _notifyReady();
      return;
    }

    await SplashShaderCache.preload();

    if (!mounted) return;

    final shader = SplashShaderCache.createShader();
    if (shader != null) {
      setState(() => _shader = shader);
      _notifyReady();
      return;
    }

    setState(() => _failed = true);
    _notifyReady();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _shader == null) {
      return const SizedBox.expand();
    }

    return CustomPaint(
      painter: _SplashShaderPainter(shader: _shader!, time: _time),
      size: Size.infinite,
    );
  }
}

class _SplashShaderPainter extends CustomPainter {
  _SplashShaderPainter({required this.shader, required this.time});

  final ui.FragmentShader shader;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    shader.setFloat(0, time);
    shader.setFloat(1, size.width);
    shader.setFloat(2, size.height);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _SplashShaderPainter oldDelegate) {
    return oldDelegate.time != time || oldDelegate.shader != shader;
  }
}
