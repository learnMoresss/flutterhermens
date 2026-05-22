import 'package:dio/dio.dart';

import 'api_client.dart';

Map<String, dynamic> _asStringKeyMap(Object? data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return {};
}

List<Map<String, dynamic>> _asBackupList(Object? raw) {
  if (raw is! List) return [];
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map<String, dynamic>) {
      out.add(e);
    } else if (e is Map) {
      out.add(Map<String, dynamic>.from(e));
    }
  }
  return out;
}

/// Gateway `/v1/admin/hermes/*`：与聊天相同，仅须用户 JWT（`Authorization: Bearer`）。
class HermesAdminApi {
  HermesAdminApi(this._dio);

  factory HermesAdminApi.fromClient(ApiClient client) => HermesAdminApi(client.dio);

  final Dio _dio;

  Future<Map<String, dynamic>> status() async {
    final r = await _dio.get<Object?>('/v1/admin/hermes/status');
    return _asStringKeyMap(r.data);
  }

  Future<List<Map<String, dynamic>>> listBackups() async {
    final r = await _dio.get<Object?>('/v1/admin/hermes/backups');
    final map = _asStringKeyMap(r.data);
    return _asBackupList(map['backups']);
  }

  Future<void> triggerBackup() async {
    await _dio.post<Object?>('/v1/admin/hermes/backup');
  }

  Future<void> restore(String filename) async {
    await _dio.post<Object?>(
      '/v1/admin/hermes/restore',
      data: {'filename': filename},
    );
  }

  Future<String?> restart() async {
    final r = await _dio.post<Object?>('/v1/admin/hermes/restart');
    final map = _asStringKeyMap(r.data);
    final out = map['stdout'];
    return out?.toString();
  }

  Future<String?> runMaintenance() async {
    final r = await _dio.post<Object?>(
      '/v1/admin/hermes/run',
      data: {'preset': 'maintenance'},
    );
    final map = _asStringKeyMap(r.data);
    final out = map['stdout'];
    return out?.toString();
  }

  Future<int> getRetention() async {
    final r = await _dio.get<Object?>('/v1/admin/hermes/retention');
    final map = _asStringKeyMap(r.data);
    final n = map['maxBackups'];
    if (n is int) return n;
    if (n is num) return n.toInt();
    return 7;
  }

  Future<void> setRetention(int maxBackups) async {
    await _dio.put<Object?>(
      '/v1/admin/hermes/retention',
      data: {'maxBackups': maxBackups},
    );
  }

  Future<void> reloadGatewayEnv() async {
    await _dio.post<Object?>('/v1/admin/hermes/config/reload');
  }

  Future<String> fetchLogs({String file = 'gateway.log', int tail = 500}) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/v1/admin/hermes/logs',
      queryParameters: {'file': file, 'tail': tail},
    );
    return r.data?['content']?.toString() ?? '';
  }

  Future<List<String>> listLogFiles() async {
    final r = await _dio.get<Map<String, dynamic>>('/v1/admin/hermes/logs');
    final files = r.data?['files'];
    if (files is! List) return const [];
    return files.map((e) => e.toString()).toList(growable: false);
  }

  Future<({bool ok, String output})> runDoctor() async {
    final r = await _dio.post<Map<String, dynamic>>('/v1/admin/hermes/doctor');
    return (
      ok: r.data?['ok'] == true,
      output: r.data?['output']?.toString() ?? '',
    );
  }

  Future<List<Map<String, String>>> listMcpServers() async {
    final r = await _dio.get<Map<String, dynamic>>('/v1/admin/hermes/mcp');
    final list = r.data?['servers'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => {
              'name': (e['name'] ?? '').toString(),
              'command': (e['command'] ?? '').toString(),
            })
        .toList(growable: false);
  }

  Future<String> importArchive(String archivePath) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/v1/admin/hermes/import',
      data: {'archivePath': archivePath},
    );
    return r.data?['stdout']?.toString() ?? '导入完成';
  }
}
