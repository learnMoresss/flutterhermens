import 'dart:ui' as ui;

/// 在 main() 中尽早启动 shader 编译，与引擎初始化并行，不阻塞 runApp。
class SplashShaderCache {
  SplashShaderCache._();

  static ui.FragmentProgram? _program;
  static Future<void>? _preloadFuture;

  static bool get isReady => _program != null;

  static Future<void> preload() {
    return _preloadFuture ??= _loadProgram();
  }

  static Future<void> _loadProgram() async {
    try {
      _program ??= await ui.FragmentProgram.fromAsset('shaders/splash_ring.frag');
    } on Object {
      // ShaderSplashBackground 会降级为纯黑背景。
    }
  }

  static ui.FragmentShader? createShader() => _program?.fragmentShader();
}
