import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/platform/chat_generation_foreground.dart';
import 'core/device_actions/device_action_executor.dart';
import 'features/splash/splash_shader_cache.dart';
import 'providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 尽早并行编译 shader，不阻塞 runApp。
  unawaited(SplashShaderCache.preload());
  unawaited(ChatGenerationForeground.ensureInitialized());
  unawaited(DeviceActionExecutor.ensureInitialized());

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const HermesApp(),
    ),
  );
}
