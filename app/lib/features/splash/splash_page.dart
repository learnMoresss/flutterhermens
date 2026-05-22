import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import 'widgets/shader_splash_background.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  static const _minShaderDisplay = Duration(milliseconds: 1800);

  static const _titleStyle = TextStyle(
    fontFamily: 'serif',
    fontSize: 36,
    fontWeight: FontWeight.w600,
    letterSpacing: 8,
    color: Colors.white,
    decoration: TextDecoration.none,
  );

  static const _subtitleStyle = TextStyle(
    fontSize: 12,
    letterSpacing: 3,
    color: Colors.white70,
    decoration: TextDecoration.none,
  );

  late final AnimationController _controller;
  late final Animation<double> _fade;
  DateTime? _shaderReadyAt;
  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _showOverlay = true);
      _controller.forward();
      unawaited(_bootstrap());
    });
  }

  void _onShaderReady() {
    _shaderReadyAt ??= DateTime.now();
  }

  Future<void> _waitForMinimumShaderDisplay() async {
    final readyAt = _shaderReadyAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(readyAt);
    final remaining = _minShaderDisplay - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      ref.read(appConfigProvider.notifier).load(),
      ref.read(userSessionProvider.notifier).load(),
    ]);

    if (!mounted) return;

    final config = ref.read(appConfigProvider);
    if (!config.isConfigured) {
      await _waitForMinimumShaderDisplay();
      if (!mounted) return;
      context.go('/setup');
      return;
    }

    await ref.read(themeModeProvider.notifier).load();

    if (config.requireLogin) {
      await ensureFreshSession(ref);
    }

    await _waitForMinimumShaderDisplay();

    if (!mounted) return;

    final session = ref.read(userSessionProvider);
    if (config.requireLogin && (!session.isLoggedIn || session.isExpired)) {
      context.go('/login');
      return;
    }

    context.go('/home/chat');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ShaderSplashBackground(onShaderReady: _onShaderReady),
          if (_showOverlay)
            FadeTransition(
              opacity: _fade,
              child: Center(
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('HERMES', style: _titleStyle),
                      SizedBox(height: 12),
                      Text('Mobile Client', style: _subtitleStyle),
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
