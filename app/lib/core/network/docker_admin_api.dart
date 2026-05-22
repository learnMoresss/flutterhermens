import 'package:dio/dio.dart';

import 'api_client.dart';

class DockerContainerInfo {
  DockerContainerInfo({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
    required this.state,
    required this.ports,
    this.composeProject,
    this.createdAt,
    this.labels,
  });

  final String id;
  final String name;
  final String image;
  final String status;
  final String state;
  final String ports;
  final String? composeProject;
  final String? createdAt;
  final String? labels;

  bool get isRunning => state.toLowerCase() == 'running';

  bool get isPaused => status.toLowerCase().contains('paused');

  String get displayRef => id.length > 12 ? id.substring(0, 12) : id;

  factory DockerContainerInfo.fromJson(Map<String, dynamic> json) {
    return DockerContainerInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      image: json['image']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      ports: json['ports']?.toString() ?? '',
      composeProject: json['composeProject']?.toString(),
      createdAt: json['createdAt']?.toString(),
      labels: json['labels']?.toString(),
    );
  }
}

class DockerImageInfo {
  DockerImageInfo({
    required this.id,
    required this.repository,
    required this.tag,
    required this.size,
    this.createdAt,
  });

  final String id;
  final String repository;
  final String tag;
  final String size;
  final String? createdAt;

  String get fullName => tag == '<none>' ? repository : '$repository:$tag';

  factory DockerImageInfo.fromJson(Map<String, dynamic> json) {
    return DockerImageInfo(
      id: json['id']?.toString() ?? '',
      repository: json['repository']?.toString() ?? '',
      tag: json['tag']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      createdAt: json['createdAt']?.toString(),
    );
  }
}

class DockerContainerStatsInfo {
  const DockerContainerStatsInfo({
    required this.cpuPercent,
    required this.memUsage,
    required this.memPercent,
    required this.netIO,
    required this.blockIO,
  });

  final String cpuPercent;
  final String memUsage;
  final String memPercent;
  final String netIO;
  final String blockIO;

  factory DockerContainerStatsInfo.fromJson(Map<String, dynamic> json) {
    return DockerContainerStatsInfo(
      cpuPercent: json['cpuPercent']?.toString() ?? '',
      memUsage: json['memUsage']?.toString() ?? '',
      memPercent: json['memPercent']?.toString() ?? '',
      netIO: json['netIO']?.toString() ?? '',
      blockIO: json['blockIO']?.toString() ?? '',
    );
  }
}

class DockerListQuery {
  const DockerListQuery({this.search, this.state, this.project});

  final String? search;
  final String? state;
  final String? project;

  Map<String, String> toQuery() {
    final q = <String, String>{};
    if (search != null && search!.trim().isNotEmpty) q['search'] = search!.trim();
    if (state != null && state!.trim().isNotEmpty && state != 'all') {
      q['state'] = state!.trim();
    }
    if (project != null && project!.trim().isNotEmpty && project != 'all') {
      q['project'] = project!.trim();
    }
    return q;
  }
}

class DockerAdminApi {
  DockerAdminApi(this._dio);

  factory DockerAdminApi.fromClient(ApiClient client) => DockerAdminApi(client.dio);

  final Dio _dio;

  Future<bool> dockerAvailable() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/v1/admin/docker/status');
      return r.data?['dockerAvailable'] == true;
    } on DioException {
      return false;
    }
  }

  Future<List<DockerContainerInfo>> listContainers({DockerListQuery? query}) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/v1/admin/docker/containers',
        queryParameters: query?.toQuery(),
      );
      final list = r.data?['containers'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => DockerContainerInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(_messageFromDio(e), statusCode: e.response?.statusCode);
    }
  }

  Future<List<DockerImageInfo>> listImages() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/v1/admin/docker/images');
      final list = r.data?['images'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => DockerImageInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(_messageFromDio(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> inspect(String containerId) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/v1/admin/docker/containers/$containerId');
      final detail = r.data?['detail'];
      if (detail is Map) return Map<String, dynamic>.from(detail);
      return {};
    } on DioException catch (e) {
      throw ApiException(_messageFromDio(e), statusCode: e.response?.statusCode);
    }
  }

  Future<DockerContainerStatsInfo> fetchStats(String containerId) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/v1/admin/docker/containers/$containerId/stats',
      );
      final stats = r.data?['stats'];
      if (stats is Map) {
        return DockerContainerStatsInfo.fromJson(Map<String, dynamic>.from(stats));
      }
      return const DockerContainerStatsInfo(
        cpuPercent: '',
        memUsage: '',
        memPercent: '',
        netIO: '',
        blockIO: '',
      );
    } on DioException catch (e) {
      throw ApiException(_messageFromDio(e), statusCode: e.response?.statusCode);
    }
  }

  Future<String> fetchLogs(String containerId, {int tail = 200}) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/v1/admin/docker/containers/$containerId/logs',
        queryParameters: {'tail': tail},
      );
      return r.data?['logs']?.toString() ?? '';
    } on DioException catch (e) {
      throw ApiException(_messageFromDio(e), statusCode: e.response?.statusCode);
    }
  }

  Future<void> start(String containerId) => _action('start', containerId);

  Future<void> stop(String containerId) => _action('stop', containerId);

  Future<void> restart(String containerId) => _action('restart', containerId);

  Future<void> pause(String containerId) => _action('pause', containerId);

  Future<void> unpause(String containerId) => _action('unpause', containerId);

  Future<void> rename(String containerId, String newName) async {
    try {
      await _dio.post<Object?>(
        '/v1/admin/docker/containers/$containerId/rename',
        data: {'name': newName},
      );
    } on DioException catch (e) {
      throw ApiException(_messageFromDio(e), statusCode: e.response?.statusCode);
    }
  }

  Future<void> remove(String containerId, {bool force = false}) async {
    try {
      await _dio.delete<Object?>(
        '/v1/admin/docker/containers/$containerId',
        queryParameters: force ? {'force': 'true'} : null,
      );
    } on DioException catch (e) {
      throw ApiException(_messageFromDio(e), statusCode: e.response?.statusCode);
    }
  }

  Future<void> removeImage(String imageRef, {bool force = false}) async {
    try {
      final encoded = Uri.encodeComponent(imageRef);
      await _dio.delete<Object?>(
        '/v1/admin/docker/images/$encoded',
        queryParameters: force ? {'force': 'true'} : null,
      );
    } on DioException catch (e) {
      throw ApiException(_messageFromDio(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Map<String, String>> prune(List<String> targets) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/v1/admin/docker/prune',
        data: {'targets': targets},
      );
      final result = r.data?['result'];
      if (result is Map) {
        return result.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return {};
    } on DioException catch (e) {
      throw ApiException(_messageFromDio(e), statusCode: e.response?.statusCode);
    }
  }

  Future<void> _action(String action, String containerId) async {
    try {
      await _dio.post<Object?>('/v1/admin/docker/containers/$containerId/$action');
    } on DioException catch (e) {
      throw ApiException(_messageFromDio(e), statusCode: e.response?.statusCode);
    }
  }

  String _messageFromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return data['message'].toString();
    return e.message ?? 'Docker 请求失败';
  }
}
