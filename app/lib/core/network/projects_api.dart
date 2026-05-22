import 'package:dio/dio.dart';

import 'api_client.dart';

enum HermesProjectType { static, dynamic }

enum HermesProjectStatus { running, stopped, error, starting }

class HermesProjectLockInfo {
  const HermesProjectLockInfo({
    required this.locked,
    required this.reason,
    this.since,
    this.by,
  });

  final bool locked;
  final String reason;
  final String? since;
  final String? by;

  factory HermesProjectLockInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const HermesProjectLockInfo(locked: false, reason: '');
    }
    return HermesProjectLockInfo(
      locked: json['locked'] == true,
      reason: json['reason']?.toString() ?? '',
      since: json['since']?.toString(),
      by: json['by']?.toString(),
    );
  }
}

class HermesProjectInfo {
  HermesProjectInfo({
    required this.id,
    required this.title,
    required this.type,
    required this.version,
    required this.status,
    required this.url,
    this.description,
    this.port,
    this.error,
    this.lock,
  });

  final String id;
  final String title;
  final HermesProjectType type;
  final String version;
  final HermesProjectStatus status;
  final String url;
  final String? description;
  final int? port;
  final String? error;
  final HermesProjectLockInfo? lock;

  bool get isStatic => type == HermesProjectType.static;

  bool get isLocked => lock?.locked == true;

  bool get needsStart => type == HermesProjectType.dynamic && status != HermesProjectStatus.running;

  factory HermesProjectInfo.fromJson(Map<String, dynamic> json) {
    final typeRaw = json['type']?.toString() ?? 'static';
    final statusRaw = json['status']?.toString() ?? 'stopped';
    final lockRaw = json['lock'];
    return HermesProjectInfo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      type: typeRaw == 'dynamic' ? HermesProjectType.dynamic : HermesProjectType.static,
      version: json['version']?.toString() ?? '1.0.0',
      status: _parseStatus(statusRaw),
      url: json['url']?.toString() ?? '',
      description: json['description']?.toString(),
      port: json['port'] is num ? (json['port'] as num).toInt() : int.tryParse('${json['port']}'),
      error: json['error']?.toString(),
      lock: lockRaw is Map
          ? HermesProjectLockInfo.fromJson(Map<String, dynamic>.from(lockRaw))
          : const HermesProjectLockInfo(locked: false, reason: ''),
    );
  }

  static HermesProjectStatus _parseStatus(String s) {
    switch (s) {
      case 'running':
        return HermesProjectStatus.running;
      case 'starting':
        return HermesProjectStatus.starting;
      case 'error':
        return HermesProjectStatus.error;
      default:
        return HermesProjectStatus.stopped;
    }
  }
}

class ProjectsApi {
  ProjectsApi(this._dio);

  factory ProjectsApi.fromClient(ApiClient client) => ProjectsApi(client.dio);

  final Dio _dio;

  Future<List<HermesProjectInfo>> listProjects() async {
    final r = await _dio.get<Map<String, dynamic>>('/v1/projects');
    final list = r.data?['projects'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => HermesProjectInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<HermesProjectInfo> fetchMeta(String slug) async {
    final r = await _dio.get<Map<String, dynamic>>('/v1/projects/$slug/meta');
    return HermesProjectInfo.fromJson(Map<String, dynamic>.from(r.data?['project'] as Map? ?? {}));
  }

  Future<HermesProjectInfo> start(String slug) async {
    final r = await _dio.post<Map<String, dynamic>>('/v1/projects/$slug/start');
    return HermesProjectInfo.fromJson(Map<String, dynamic>.from(r.data?['project'] as Map? ?? {}));
  }

  Future<HermesProjectInfo> stop(String slug) async {
    final r = await _dio.post<Map<String, dynamic>>('/v1/projects/$slug/stop');
    return HermesProjectInfo.fromJson(Map<String, dynamic>.from(r.data?['project'] as Map? ?? {}));
  }

  Future<HermesProjectInfo> restart(String slug) async {
    final r = await _dio.post<Map<String, dynamic>>('/v1/projects/$slug/restart');
    return HermesProjectInfo.fromJson(Map<String, dynamic>.from(r.data?['project'] as Map? ?? {}));
  }

  Future<void> delete(String slug) async {
    await _dio.delete<Object?>('/v1/projects/$slug', queryParameters: {'confirm': '1'});
  }
}
