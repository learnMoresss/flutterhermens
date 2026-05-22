import 'package:dio/dio.dart';

/// 对应网关 `GET /v1/setup/discover`（无需登录）。
class SetupDiscovery {
  const SetupDiscovery({
    required this.hermesOriginEffective,
    this.hermesOriginProbed,
    this.hermesOriginMismatch = false,
    required this.hermesLoginPath,
    required this.hermesChatPath,
    required this.hermesReachable,
    required this.hermesProbeDetail,
    this.hermesPortScanTried = '',
    this.hermesPortScanLines = const [],
    this.composePortHint = '',
    required this.backupSource,
    required this.backupDir,
    required this.gatewayVersion,
    this.backupDockerNote = '',
  });

  final String hermesOriginEffective;
  /// 实际探测到可达的 Hermes 根地址；与 [hermesOriginEffective] 可能不同。
  final String? hermesOriginProbed;
  /// 网关 .env 中的地址与探测结果不一致。
  final bool hermesOriginMismatch;
  final String hermesLoginPath;
  final String hermesChatPath;
  final bool hermesReachable;
  final String hermesProbeDetail;
  final String hermesPortScanTried;
  final List<String> hermesPortScanLines;
  final String composePortHint;
  final String backupSource;
  final String backupDir;
  final String gatewayVersion;
  final String backupDockerNote;

  /// 写入服务器 `.env` 的 `HERMES_ORIGIN` 建议：探测与网关当前配置不一致时优先用探测结果。
  String get recommendedHermesForServerEnv {
    final p = hermesOriginProbed?.trim();
    if (hermesOriginMismatch && p != null && p.isNotEmpty) return p;
    return hermesOriginEffective;
  }

  factory SetupDiscovery.fromJson(Map<String, dynamic> json) {
    String s(String k, [String fallback = '']) {
      final v = json[k];
      if (v == null) return fallback;
      if (v is String) return v;
      return v.toString();
    }

    String? sOpt(String k) {
      final v = json[k];
      if (v == null) return null;
      if (v is String && v.isEmpty) return null;
      return v.toString();
    }

    List<String> stringList(String k) {
      final v = json[k];
      if (v is! List) return const [];
      return v.map((e) => e.toString()).toList(growable: false);
    }

    return SetupDiscovery(
      hermesOriginEffective: s('hermesOriginEffective'),
      hermesOriginProbed: sOpt('hermesOriginProbed'),
      hermesOriginMismatch: json['hermesOriginMismatch'] == true,
      hermesLoginPath: s('hermesLoginPath', '/api/auth/login'),
      hermesChatPath: s('hermesChatPath', '/api/chat'),
      hermesReachable: json['hermesReachable'] == true,
      hermesProbeDetail: s('hermesProbeDetail'),
      hermesPortScanTried: s('hermesPortScanTried'),
      hermesPortScanLines: stringList('hermesPortScanLines'),
      composePortHint: s('composePortHint'),
      backupSource: s('backupSource'),
      backupDir: s('backupDir'),
      gatewayVersion: s('gatewayVersion'),
      backupDockerNote: s('backupDockerNote'),
    );
  }

  /// 无网络时用本机已保存配置构造摘要（不保证 Hermes 仍可达）。
  factory SetupDiscovery.fromSavedLocal({
    required String hermesOrigin,
    required String backupSource,
    required String backupDir,
  }) {
    return SetupDiscovery(
      hermesOriginEffective: hermesOrigin,
      hermesOriginProbed: null,
      hermesOriginMismatch: false,
      hermesLoginPath: '/api/auth/login',
      hermesChatPath: '/api/chat',
      hermesReachable: true,
      hermesProbeDetail: '来自本机已保存配置（未重新探测）',
      backupSource: backupSource,
      backupDir: backupDir,
      gatewayVersion: '—',
    );
  }
}

String normalizeGatewayBaseUrl(String url) {
  final t = url.trim();
  if (t.isEmpty) return t;
  return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
}

/// 先 `/health` 再 `/v1/setup/discover`；失败返回错误文案。
Future<(SetupDiscovery?, String?)> fetchSetupDiscovery(String gatewayUrl) async {
  final base = normalizeGatewayBaseUrl(gatewayUrl);
  if (base.isEmpty) {
    return (null, '请先填写 Gateway 地址');
  }
  final dio = Dio(
    BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ),
  );
  try {
    await dio.get<Object?>('/health');
    final r = await dio.get<Object?>('/v1/setup/discover');
    final raw = r.data;
    if (raw is! Map) {
      return (null, 'discover 响应格式异常');
    }
    return (SetupDiscovery.fromJson(Map<String, dynamic>.from(raw)), null);
  } on DioException catch (e) {
    final msg = e.response?.data is Map && (e.response!.data as Map)['message'] != null
        ? (e.response!.data as Map)['message'].toString()
        : (e.message ?? '请求失败');
    return (null, msg);
  } catch (e) {
    return (null, e.toString());
  }
}
