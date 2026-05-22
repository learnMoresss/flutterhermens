import '../../core/setup/setup_preset.dart';

class AppConfig {
  const AppConfig({
    required this.gatewayUrl,
    required this.requireLogin,
    this.isConfigured = false,
    this.setupPresetId = SetupPreset.tencentLite,
    this.hermesOriginForServer = '',
    this.backupSourcePath = '/home/ubuntu/hermes-data',
    this.backupDirPath = '/home/ubuntu/hermes-backups',
  });

  final String gatewayUrl;
  final bool requireLogin;
  final bool isConfigured;

  /// 与 [SetupPreset] 中 id 对应，仅本地保存。
  final String setupPresetId;

  /// 服务器上 Hermes 根 URL（写入 .env 的 HERMES_ORIGIN），与 Gateway URL 可不同。
  final String hermesOriginForServer;

  /// 服务器待备份目录（与网关 .env 中 HERMES_BACKUP_SOURCE 对齐）。
  final String backupSourcePath;

  /// 服务器备份存放目录（与 HERMES_BACKUP_DIR 对齐）。
  final String backupDirPath;

  static const empty = AppConfig(
    gatewayUrl: '',
    requireLogin: false,
    isConfigured: false,
    setupPresetId: SetupPreset.tencentLite,
    hermesOriginForServer: '',
    backupSourcePath: '/home/ubuntu/hermes-data',
    backupDirPath: '/home/ubuntu/hermes-backups',
  );

  AppConfig copyWith({
    String? gatewayUrl,
    bool? requireLogin,
    bool? isConfigured,
    String? setupPresetId,
    String? hermesOriginForServer,
    String? backupSourcePath,
    String? backupDirPath,
  }) {
    return AppConfig(
      gatewayUrl: gatewayUrl ?? this.gatewayUrl,
      requireLogin: requireLogin ?? this.requireLogin,
      isConfigured: isConfigured ?? this.isConfigured,
      setupPresetId: setupPresetId ?? this.setupPresetId,
      hermesOriginForServer: hermesOriginForServer ?? this.hermesOriginForServer,
      backupSourcePath: backupSourcePath ?? this.backupSourcePath,
      backupDirPath: backupDirPath ?? this.backupDirPath,
    );
  }

  Map<String, dynamic> toJson() => {
        'gatewayUrl': gatewayUrl,
        'requireLogin': requireLogin,
        'isConfigured': isConfigured,
        'setupPresetId': setupPresetId,
        'hermesOriginForServer': hermesOriginForServer,
        'backupSourcePath': backupSourcePath,
        'backupDirPath': backupDirPath,
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    String s(Object? k, [String fallback = '']) {
      final v = json[k];
      if (v == null) return fallback;
      if (v is String) return v;
      return v.toString();
    }

    return AppConfig(
      gatewayUrl: s('gatewayUrl'),
      requireLogin: json['requireLogin'] as bool? ?? false,
      isConfigured: json['isConfigured'] as bool? ?? false,
      setupPresetId: s('setupPresetId', SetupPreset.tencentLite),
      hermesOriginForServer: s('hermesOriginForServer'),
      backupSourcePath: s('backupSourcePath', '/home/ubuntu/hermes-data'),
      backupDirPath: s('backupDirPath', '/home/ubuntu/hermes-backups'),
    );
  }
}

/// 热重载或异常持久化后，个别 `final String` 字段在极少数情况下可能读取出错；用 try/catch 避免配置页红屏。
extension AppConfigSafeAccess on AppConfig {
  String _read(String Function(AppConfig) accessor, [String fallback = '']) {
    try {
      return accessor(this);
    } on Object {
      return fallback;
    }
  }

  String get gatewayUrlSafe => _read((c) => c.gatewayUrl);

  String get hermesOriginForServerSafe =>
      _read((c) => c.hermesOriginForServer);

  String get backupSourcePathSafe => _read((c) => c.backupSourcePath);

  String get backupDirPathSafe => _read((c) => c.backupDirPath);

  String get setupPresetIdSafe =>
      _read((c) => c.setupPresetId, SetupPreset.tencentLite);
}
