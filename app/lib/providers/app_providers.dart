import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_client.dart';
import '../core/network/session_auth.dart';
import '../core/storage/app_storage.dart';
import '../shared/models/app_config.dart';
import '../shared/models/user_session.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main()');
});

final appStorageProvider = Provider<AppStorage>((ref) {
  return AppStorage(ref.watch(sharedPreferencesProvider));
});

class AppConfigNotifier extends Notifier<AppConfig> {
  @override
  AppConfig build() => AppConfig.empty;

  Future<void> load() async {
    state = await ref.read(appStorageProvider).loadConfig();
  }

  Future<void> save({
    required String gatewayUrl,
    required bool requireLogin,
    String? setupPresetId,
    String? hermesOriginForServer,
    String? backupSourcePath,
    String? backupDirPath,
  }) async {
    final config = AppConfig(
      gatewayUrl: gatewayUrl,
      requireLogin: requireLogin,
      isConfigured: true,
      setupPresetId: setupPresetId ?? state.setupPresetIdSafe,
      hermesOriginForServer: hermesOriginForServer ?? state.hermesOriginForServerSafe,
      backupSourcePath: backupSourcePath ?? state.backupSourcePathSafe,
      backupDirPath: backupDirPath ?? state.backupDirPathSafe,
    );
    await ref.read(appStorageProvider).saveConfig(config);
    state = config;
  }

  Future<void> clear() async {
    await ref.read(appStorageProvider).clearConfig();
    state = AppConfig.empty;
  }
}

final appConfigProvider =
    NotifierProvider<AppConfigNotifier, AppConfig>(AppConfigNotifier.new);

class UserSessionNotifier extends Notifier<UserSession> {
  @override
  UserSession build() => UserSession.empty;

  Future<void> load() async {
    state = await ref.read(appStorageProvider).loadSession();
  }

  Future<void> save(UserSession session) async {
    await ref.read(appStorageProvider).saveSession(session);
    state = session;
  }

  Future<void> clear() async {
    await ref.read(appStorageProvider).clearSession();
    state = UserSession.empty;
  }
}

final userSessionProvider =
    NotifierProvider<UserSessionNotifier, UserSession>(UserSessionNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  Future<void> load() async {
    state = ref.read(appStorageProvider).loadThemeMode();
  }

  Future<void> set(ThemeMode mode) async {
    await ref.read(appStorageProvider).saveThemeMode(mode);
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// 带 Token 自动续期的 Gateway 客户端（401 时尝试 refresh）
final gatewayClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final session = ref.watch(userSessionProvider);
  return ApiClient(
    baseUrl: config.gatewayUrl,
    token: session.token,
    onRefreshToken: config.requireLogin && session.token != null
        ? () async {
            final current = ref.read(userSessionProvider);
            if (current.token == null) return null;
            final refreshed = await SessionAuth.refreshSession(
              gatewayUrl: config.gatewayUrl,
              token: current.token!,
            );
            if (refreshed == null) return null;
            await ref.read(userSessionProvider.notifier).save(refreshed);
            return refreshed.token;
          }
        : null,
  );
});

/// 启动或登录后：若 Token 即将过期则主动续期
Future<void> ensureFreshSession(WidgetRef ref) async {
  final config = ref.read(appConfigProvider);
  if (!config.requireLogin || !config.isConfigured) return;
  var session = ref.read(userSessionProvider);
  if (!session.isLoggedIn || session.isExpired) return;
  if (!session.isExpiringSoon) return;
  final refreshed = await SessionAuth.refreshSession(
    gatewayUrl: config.gatewayUrl,
    token: session.token!,
  );
  if (refreshed != null) {
    await ref.read(userSessionProvider.notifier).save(refreshed);
  }
}
